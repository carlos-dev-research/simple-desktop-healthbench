// OpenAI-compatible client (spec 002 FR-004–FR-008; contracts/chat-completions.md).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/chat_client.dart';
import 'package:healthbench/core/settings.dart';

import '../support/fake_openai_server.dart';

const _key = 'sk-test-SECRET-123';

// Fast settings so retry and timeout tests run in milliseconds.
const _fast = ClientOptions(
  timeout: Duration(milliseconds: 300),
  initialBackoff: Duration(milliseconds: 1),
  maxBackoff: Duration(milliseconds: 4),
  maxRetryAfter: Duration(milliseconds: 200),
);

void main() {
  late FakeOpenAiServer server;
  late ChatClient client;

  Future<void> serve(
    List<FakeResponse> responses, {
    ClientOptions options = _fast,
  }) async {
    server = await FakeOpenAiServer.scripted(responses);
    client = ChatClient(
      ConnectionSettings(baseUrl: server.baseUrl.toString(), apiKey: _key),
      options: options,
    );
    addTearDown(() async {
      client.close();
      await server.close();
    });
  }

  final model = ModelSettings(name: 'test-model');
  const messages = [
    {'role': 'user', 'content': 'Hello'},
  ];

  Future<String> call({
    ModelSettings? withModel,
    Map<String, Object?>? format,
  }) => client.complete(
    model: withModel ?? model,
    messages: messages,
    responseFormat: format,
  );

  group('requests', () {
    test(
      'generate: model, messages, temperature 0.3, no effort for none',
      () async {
        await serve([FakeResponse.reply('Hi there')]);
        expect(await call(), 'Hi there');

        final request = server.requests.single;
        expect(request.path, '/v1/chat/completions');
        expect(request.headers['authorization'], 'Bearer $_key');
        expect(request.body['model'], 'test-model');
        expect(request.body['messages'], messages);
        expect(request.body['temperature'], 0.3);
        expect(request.body.containsKey('reasoning_effort'), isFalse);
        expect(request.body.containsKey('response_format'), isFalse);
      },
    );

    test(
      'effort low/medium/high is sent; response format is passed through',
      () async {
        await serve([FakeResponse.reply('ok')]);
        final format = {'type': 'json_schema'};
        await call(
          withModel: ModelSettings(
            name: 'grader',
            reasoningEffort: ReasoningEffort.high,
          ),
          format: format,
        );
        expect(server.requests.single.body['reasoning_effort'], 'high');
        expect(server.requests.single.body['response_format'], format);
      },
    );
  });

  group('retries', () {
    for (final status in [408, 409, 429, 500, 503]) {
      test('HTTP $status is retried', () async {
        await serve([
          FakeResponse.error(status, 'busy'),
          FakeResponse.reply('recovered'),
        ]);
        expect(await call(), 'recovered');
        expect(server.requests, hasLength(2));
      });
    }

    test(
      'gives up after 4 retries (5 attempts) with a non-fatal error',
      () async {
        await serve(List.generate(6, (_) => FakeResponse.error(500, 'down')));
        await expectLater(
          call(),
          throwsA(
            isA<TransientError>()
                .having((e) => e.isFatal, 'isFatal', isFalse)
                .having((e) => e.message, 'message', contains('4 retries')),
          ),
        );
        expect(server.requests, hasLength(5));
      },
    );

    test('x-should-retry overrides the status', () async {
      await serve([
        FakeResponse.error(500, 'no', headers: {'x-should-retry': 'false'}),
      ]);
      await expectLater(call(), throwsA(isA<RequestError>()));
      expect(server.requests, hasLength(1));

      await serve([
        FakeResponse.error(400, 'yes', headers: {'x-should-retry': 'true'}),
        FakeResponse.reply('ok'),
      ]);
      expect(await call(), 'ok');
    });

    test('retry-after-ms is honoured', () async {
      await serve([
        FakeResponse.error(
          429,
          'slow down',
          headers: {'retry-after-ms': '120'},
        ),
        FakeResponse.reply('ok'),
      ]);
      final watch = Stopwatch()..start();
      await call();
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(110));
    });

    test('a retry-after longer than the maximum is ignored', () async {
      await serve([
        FakeResponse.error(429, 'slow down', headers: {'retry-after': '30'}),
        FakeResponse.reply('ok'),
      ]);
      final watch = Stopwatch()..start();
      await call();
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('a timeout is retried, then reported', () async {
      await serve(
        [
          FakeResponse.reply('late').withDelay(const Duration(seconds: 2)),
          FakeResponse.reply('late').withDelay(const Duration(seconds: 2)),
        ],
        options: const ClientOptions(
          timeout: Duration(milliseconds: 150),
          maxRetries: 1,
          initialBackoff: Duration(milliseconds: 1),
        ),
      );
      await expectLater(
        call(),
        throwsA(
          isA<TransientError>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      expect(server.requests, hasLength(2));
    });

    test('a connection error is retried, then reported', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      client = ChatClient(
        ConnectionSettings(baseUrl: 'http://127.0.0.1:$port/v1', apiKey: _key),
        options: _fast,
      );
      addTearDown(client.close);
      await expectLater(
        call(),
        throwsA(
          isA<TransientError>().having(
            (e) => e.message,
            'message',
            contains('Connection'),
          ),
        ),
      );
    });
  });

  group('errors that stop the run', () {
    for (final (status, type) in [
      (401, isA<AuthenticationError>()),
      (403, isA<PermissionDeniedError>()),
      (404, isA<NotFoundError>()),
    ]) {
      test('HTTP $status is fatal and never retried', () async {
        await serve([
          FakeResponse.error(status, 'nope'),
          FakeResponse.reply('x'),
        ]);
        await expectLater(
          call(),
          throwsA(type.having((ChatError e) => e.isFatal, 'isFatal', isTrue)),
        );
        expect(server.requests, hasLength(1));
      });
    }

    test('other 4xx fails this conversation only', () async {
      await serve([FakeResponse.error(400, 'bad request')]);
      await expectLater(
        call(),
        throwsA(
          isA<RequestError>()
              .having((e) => e.isFatal, 'isFatal', isFalse)
              .having((e) => e.message, 'message', contains('bad request')),
        ),
      );
      expect(server.requests, hasLength(1));
    });
  });

  group('bad replies', () {
    test('empty content or no choices', () async {
      await serve([FakeResponse.reply('')]);
      await expectLater(call(), throwsA(isA<EmptyReplyError>()));
      await serve([
        FakeResponse(200, body: {'choices': <Object?>[]}),
      ]);
      await expectLater(call(), throwsA(isA<EmptyReplyError>()));
      await serve([
        FakeResponse(
          200,
          body: {
            'choices': [
              {
                'message': {'role': 'assistant', 'content': null},
              },
            ],
          },
        ),
      ]);
      await expectLater(call(), throwsA(isA<EmptyReplyError>()));
    });

    test('not JSON', () async {
      await serve([FakeResponse(200, rawBody: '<html>oops</html>')]);
      await expectLater(call(), throwsA(isA<BadResponseError>()));
    });

    test('too large', () async {
      await serve([
        FakeResponse.reply('x' * 5000),
      ], options: const ClientOptions(maxResponseBytes: 1000));
      await expectLater(
        call(),
        throwsA(
          isA<BadResponseError>().having(
            (e) => e.message,
            'message',
            contains('too large'),
          ),
        ),
      );
    });
  });

  test('the API key never appears in an error (FR-008)', () async {
    await serve([FakeResponse.error(401, 'Incorrect API key provided: $_key')]);
    try {
      await call();
      fail('expected an error');
    } on ChatError catch (e) {
      expect(e.message, isNot(contains(_key)));
      expect(e.toString(), isNot(contains(_key)));
      expect(e.message, contains('***'));
    }
  });
}
