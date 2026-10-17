// A scripted OpenAI-compatible endpoint on 127.0.0.1 for tests
// (Constitution Article VII.4: tests never call a real API).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What the fake server answers to one request.
class FakeResponse {
  FakeResponse(
    this.status, {
    Object? body,
    this.headers = const {},
    this.delay = Duration.zero,
    this.rawBody,
  }) : body = body ?? const <String, Object?>{};

  /// A successful chat completion whose message content is [content].
  factory FakeResponse.reply(String content) => FakeResponse(
    200,
    body: {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content},
        },
      ],
    },
  );

  /// A grader answer in the JSON shape the grader prompt asks for.
  factory FakeResponse.grade({required bool met, String explanation = 'ok'}) =>
      FakeResponse.reply(
        jsonEncode({'explanation': explanation, 'criteria_met': met}),
      );

  /// An OpenAI-style error body.
  factory FakeResponse.error(
    int status,
    String message, {
    Map<String, String> headers = const {},
  }) => FakeResponse(
    status,
    body: {
      'error': {'message': message},
    },
    headers: headers,
  );

  final int status;
  final Object body;
  final Map<String, String> headers;
  final Duration delay;

  /// Sent verbatim instead of [body] when set (for malformed responses).
  final String? rawBody;
}

/// One request the fake server received.
class RecordedRequest {
  RecordedRequest(this.path, this.headers, this.body);

  final String path;
  final Map<String, String> headers;
  final Map<String, Object?> body;

  /// The `content` of the first message (the grader prompt for grader calls).
  String get firstMessageContent {
    final messages = body['messages']! as List<Object?>;
    return (messages.first! as Map<String, Object?>)['content']! as String;
  }

  bool get isGraderCall => body.containsKey('response_format');
}

/// Decides the response for each request; receives the request and its
/// 0-based number.
typedef FakeHandler = FutureOr<FakeResponse> Function(RecordedRequest, int);

class FakeOpenAiServer {
  FakeOpenAiServer._(this._server, this._handler) {
    _server.listen(_serve);
  }

  static Future<FakeOpenAiServer> start(FakeHandler handler) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return FakeOpenAiServer._(server, handler);
  }

  /// Answers from a fixed list, in order; fails the request if it runs out.
  static Future<FakeOpenAiServer> scripted(List<FakeResponse> responses) =>
      start(
        (_, n) => n < responses.length
            ? responses[n]
            : FakeResponse.error(500, 'script exhausted'),
      );

  final HttpServer _server;
  final FakeHandler _handler;
  final List<RecordedRequest> requests = [];

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}/v1');

  Future<void> _serve(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.join(','));
    final recorded = RecordedRequest(
      request.uri.path,
      headers,
      text.isEmpty
          ? <String, Object?>{}
          : jsonDecode(text) as Map<String, Object?>,
    );
    final number = requests.length;
    requests.add(recorded);
    final response = await _handler(recorded, number);
    if (response.delay > Duration.zero) {
      await Future<void>.delayed(response.delay);
    }
    try {
      request.response.statusCode = response.status;
      request.response.headers.contentType = ContentType.json;
      response.headers.forEach(request.response.headers.set);
      request.response.write(response.rawBody ?? jsonEncode(response.body));
      await request.response.close();
    } on Object {
      // The client may have given up (timeout tests); ignore.
    }
  }

  Future<void> close() => _server.close(force: true);
}
