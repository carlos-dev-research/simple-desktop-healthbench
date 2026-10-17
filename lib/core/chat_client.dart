/// Minimal OpenAI-compatible Chat Completions client
/// (contracts/chat-completions.md; research R1, R2).
///
/// Retries follow the official openai-python SDK the reference toolkit used:
/// 408/409/429/5xx, timeouts and connection errors are retried with
/// exponential backoff and jitter, honouring Retry-After.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'settings.dart';

/// Why a chat request failed. Messages never contain the API key.
sealed class ChatError implements Exception {
  const ChatError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// True when the error will repeat for every conversation, so the run stops.
  bool get isFatal => false;

  @override
  String toString() => message;
}

/// HTTP 401: the API key was rejected.
final class AuthenticationError extends ChatError {
  const AuthenticationError(super.message, {super.statusCode});
  @override
  bool get isFatal => true;
}

/// HTTP 403: the key may not use this model or endpoint.
final class PermissionDeniedError extends ChatError {
  const PermissionDeniedError(super.message, {super.statusCode});
  @override
  bool get isFatal => true;
}

/// HTTP 404: unknown model or endpoint.
final class NotFoundError extends ChatError {
  const NotFoundError(super.message, {super.statusCode});
  @override
  bool get isFatal => true;
}

/// Rate limit, server error, timeout or connection problem that persisted
/// through every retry.
final class TransientError extends ChatError {
  const TransientError(super.message, {super.statusCode});
}

/// Any other rejected request (for example HTTP 400).
final class RequestError extends ChatError {
  const RequestError(super.message, {super.statusCode});
}

/// The reply had no choices or no content.
final class EmptyReplyError extends ChatError {
  const EmptyReplyError(super.message);
}

/// The response was not usable JSON, or was too large.
final class BadResponseError extends ChatError {
  const BadResponseError(super.message, {super.statusCode});
}

class _Retry implements Exception {
  _Retry(this.error, [this.retryAfter]);

  final ChatError error;
  final Duration? retryAfter;
}

class ChatClient {
  ChatClient(
    this._connection, {
    this.options = const ClientOptions(),
    http.Client? httpClient,
    Random? random,
  }) : _http = httpClient ?? http.Client(),
       _random = random ?? Random();

  final ConnectionSettings _connection;
  final ClientOptions options;
  final http.Client _http;
  final Random _random;

  Uri get _endpoint => _connection.baseUrl.replace(
    path: '${_connection.baseUrl.path}/chat/completions',
  );

  /// Sends one chat completion request and returns the reply text
  /// (`choices[0].message.content`). Throws a [ChatError].
  Future<String> complete({
    required ModelSettings model,
    required List<Map<String, String>> messages,
    Map<String, Object?>? responseFormat,
  }) async {
    final body = jsonEncode({
      'model': model.name,
      'messages': messages,
      'temperature': requestTemperature,
      'reasoning_effort': ?model.reasoningEffort.requestValue,
      'response_format': ?responseFormat,
    });
    for (var attempt = 0; ; attempt++) {
      try {
        return await _attempt(body);
      } on _Retry catch (retry) {
        if (attempt >= options.maxRetries) {
          throw TransientError(
            '${retry.error.message} (after ${options.maxRetries} retries)',
            statusCode: retry.error.statusCode,
          );
        }
        await Future<void>.delayed(retry.retryAfter ?? _backoff(attempt));
      }
    }
  }

  void close() => _http.close();

  Duration _backoff(int retry) {
    final base = options.initialBackoff * pow(2, retry).toDouble();
    final capped = base > options.maxBackoff ? options.maxBackoff : base;
    return capped * (1 - 0.25 * _random.nextDouble());
  }

  Future<String> _attempt(String body) async {
    final abort = Completer<void>();
    final request =
        http.AbortableRequest('POST', _endpoint, abortTrigger: abort.future)
          ..headers['Authorization'] = 'Bearer ${_connection.apiKey}'
          ..headers['Content-Type'] = 'application/json'
          ..body = body;
    final ({int status, Map<String, String> headers, Uint8List bytes}) response;
    try {
      response = await _sendAndRead(request).timeout(options.timeout);
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      throw _Retry(
        TransientError(
          'Request timed out after ${options.timeout.inMilliseconds / 1000} s',
        ),
      );
    } on http.ClientException catch (e) {
      throw _Retry(TransientError(_redact('Connection error: ${e.message}')));
    } on SocketException catch (e) {
      throw _Retry(TransientError(_redact('Connection error: ${e.message}')));
    } on HttpException catch (e) {
      throw _Retry(TransientError(_redact('Connection error: ${e.message}')));
    }
    return _interpret(response.status, response.headers, response.bytes);
  }

  Future<({int status, Map<String, String> headers, Uint8List bytes})>
  _sendAndRead(http.BaseRequest request) async {
    final streamed = await _http.send(request);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream) {
      builder.add(chunk);
      if (builder.length > options.maxResponseBytes) {
        throw BadResponseError(
          'Response too large (over ${options.maxResponseBytes} bytes)',
          statusCode: streamed.statusCode,
        );
      }
    }
    return (
      status: streamed.statusCode,
      headers: streamed.headers,
      bytes: builder.takeBytes(),
    );
  }

  String _interpret(int status, Map<String, String> headers, Uint8List bytes) {
    if (status >= 200 && status < 300) return _replyText(status, bytes);

    final detail = _serverMessage(bytes);
    String describe(String kind) => _redact('$kind (HTTP $status): $detail');
    switch (status) {
      case 401:
        throw AuthenticationError(
          describe('Authentication failed'),
          statusCode: status,
        );
      case 403:
        throw PermissionDeniedError(
          describe('Permission denied'),
          statusCode: status,
        );
      case 404:
        throw NotFoundError(
          describe('Model or endpoint not found'),
          statusCode: status,
        );
    }
    final retry = switch (headers['x-should-retry']) {
      'true' => true,
      'false' => false,
      _ => status == 408 || status == 409 || status == 429 || status >= 500,
    };
    if (retry) {
      throw _Retry(
        TransientError(describe('Temporary error'), statusCode: status),
        _retryAfter(headers),
      );
    }
    throw RequestError(describe('Request rejected'), statusCode: status);
  }

  String _replyText(int status, Uint8List bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw BadResponseError(
        'Response is not valid JSON (HTTP $status)',
        statusCode: status,
      );
    }
    if (json
        case {'choices': [{'message': {'content': final String text}}, ...]}
        when text.isNotEmpty) {
      return text;
    }
    if (json is! Map<String, Object?>) {
      throw BadResponseError(
        'Response is not a JSON object (HTTP $status)',
        statusCode: status,
      );
    }
    throw const EmptyReplyError('The model returned an empty reply');
  }

  /// The server's `error.message`, or the start of the body, truncated.
  String _serverMessage(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    var message = text;
    try {
      if (jsonDecode(text) case {'error': {'message': final String m}}) {
        message = m;
      }
    } on FormatException {
      // Keep the raw text.
    }
    message = _redact(message.trim());
    return message.length > 500 ? '${message.substring(0, 500)}…' : message;
  }

  /// Removes every occurrence of the API key (spec 002 FR-008).
  String _redact(String text) => text.replaceAll(_connection.apiKey, '***');

  Duration? _retryAfter(Map<String, String> headers) {
    Duration? wait;
    final ms = double.tryParse(headers['retry-after-ms'] ?? '');
    final seconds = headers['retry-after'];
    if (ms != null) {
      wait = Duration(microseconds: (ms * 1000).round());
    } else if (seconds != null) {
      final value = double.tryParse(seconds);
      if (value != null) {
        wait = Duration(microseconds: (value * 1e6).round());
      } else {
        try {
          wait = HttpDate.parse(seconds).difference(DateTime.now());
        } on HttpException {
          wait = null;
        } on FormatException {
          wait = null;
        }
      }
    }
    if (wait == null || wait <= Duration.zero || wait > options.maxRetryAfter) {
      return null;
    }
    return wait;
  }
}
