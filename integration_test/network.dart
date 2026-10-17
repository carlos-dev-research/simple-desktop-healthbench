// Research R15 (carries spec 001 US3-3): the core's HTTP client can make an
// outgoing request from inside the real, sandboxed app. On macOS this fails
// unless the com.apple.security.network.client entitlement is granted.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/chat_client.dart';
import 'package:healthbench/core/settings.dart';

void main() {
  testWidgets('the chat client reaches a local endpoint from the app', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'pong'},
              },
            ],
          }),
        );
      await request.response.close();
    });

    final client = ChatClient(
      ConnectionSettings(
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'test',
      ),
      options: const ClientOptions(maxRetries: 0),
    );
    addTearDown(client.close);

    final reply = await tester.runAsync(
      () => client.complete(
        model: ModelSettings(name: 'm'),
        messages: const [
          {'role': 'user', 'content': 'ping'},
        ],
      ),
    );
    expect(reply, 'pong');
  });
}
