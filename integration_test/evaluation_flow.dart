// Spec 003 NFR-004: a full evaluation driven through the real UI, inside the
// real (sandboxed) app, against a local fake OpenAI-compatible endpoint.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/app.dart';
import 'package:healthbench/core/settings.dart';
import 'package:healthbench/ui/state/providers.dart';

import '../test/support/fake_openai_server.dart';
import '../test/support/fixtures.dart';

const _key = 'sk-integration-SECRET-9';

/// Pumps frames until [finder] matches, or fails after [timeout].
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

void main() {
  testWidgets('start a run from the form, watch it finish, open the results', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('healthbench_flow_');
    addTearDown(() => dir.deleteSync(recursive: true));
    writeDataset('${dir.path}/data.jsonl', 3);
    final server = await FakeOpenAiServer.start(
      (r, _) => r.isGraderCall
          ? FakeResponse.grade(
              met: r.firstMessageContent.contains(
                'Criterion:\nGives the right advice',
              ),
              explanation: 'checked by the fake grader',
            )
          : FakeResponse.reply('Please **call** emergency services.'),
    );
    addTearDown(server.close);

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageDirectoryProvider.overrideWith((ref) async => dir.path),
          datasetPickerProvider.overrideWithValue(
            () async => '${dir.path}/data.jsonl',
          ),
          clientOptionsProvider.overrideWithValue(
            const ClientOptions(timeout: Duration(seconds: 10), maxRetries: 0),
          ),
        ],
        retry: (_, _) => null,
        child: const HealthBenchApp(),
      ),
    );
    await tester.pump();

    // Fill in the New-run form.
    await tester.tap(find.text('New run'));
    await pumpUntil(tester, find.text('New evaluation run'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Base URL'),
      server.baseUrl.toString(),
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'API key'), _key);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Model under test'),
      'tested-model',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Grader model'),
      'grader-model',
    );
    await tester.tap(find.text('Choose dataset file…'));
    await pumpUntil(tester, find.text('data.jsonl · 3 conversations'));

    // Run it.
    await tester.tap(find.text('Start run'));
    await pumpUntil(tester, find.text('Open results'));
    expect(find.text('completed'), findsOneWidget);
    expect(find.textContaining('3 of 3'), findsOneWidget);
    expect(find.text('Final score'), findsOneWidget);

    // Results: run summary and one conversation.
    await tester.tap(find.text('Open results'));
    await pumpUntil(tester, find.text('Conversations graded'));
    expect(find.text('3/3'), findsOneWidget);
    expect(find.text('Run score'), findsOneWidget);
    await tester.tap(find.text('Question for p0'));
    await pumpUntil(tester, find.text('Model response (evaluated)'));
    expect(find.text('Gives the right advice'), findsOneWidget);
    expect(find.text('checked by the fake grader'), findsWidgets);

    // The run file exists in the app's storage and never contains the key.
    final runs = Directory(runsDirectoryIn(dir.path)).listSync();
    expect(runs, hasLength(1));
    expect(File(runs.single.path).readAsStringSync(), isNot(contains(_key)));
    expect(
      server.requests,
      hasLength(3 * 3),
    ); // per conversation: 1 reply + 2 criteria

    await tester.pumpWidget(const SizedBox()); // stop timers before teardown
  });
}
