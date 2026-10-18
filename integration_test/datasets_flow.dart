// Spec 005 in the real (sandboxed) app: download an "official" file from a
// local fake host (pinned size / SHA-256 / count), create a sample, pick it
// from the library in New run, and run it against a local fake endpoint.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/app.dart';
import 'package:healthbench/core/dataset_library.dart';
import 'package:healthbench/core/settings.dart';
import 'package:healthbench/ui/state/datasets_controller.dart';
import 'package:healthbench/ui/state/providers.dart';

import '../test/support/fake_openai_server.dart';
import '../test/support/fixtures.dart';
import 'evaluation_flow.dart' show pumpUntil;

void main() {
  testWidgets('download, sample, run on the sample', (tester) async {
    final dir = Directory.systemTemp.createTempSync('healthbench_datasets_');
    addTearDown(() => dir.deleteSync(recursive: true));

    // A small "official" file with its own pinned values, served locally.
    final bytes = utf8.encode(
      datasetText([for (var i = 0; i < 8; i++) datasetRecord('p$i')]),
    );
    final official = OfficialDataset(
      fileName: 'mini_official.jsonl',
      label: 'Mini Official',
      description: 'eight conversations',
      bytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      conversations: 8,
    );
    final files = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => files.close(force: true));
    files.listen((r) async {
      r.response.contentLength = bytes.length;
      r.response.add(bytes);
      await r.response.close();
    });

    final model = await FakeOpenAiServer.start(
      (r, _) => r.isGraderCall
          ? FakeResponse.grade(met: true)
          : FakeResponse.reply('reply'),
    );
    addTearDown(model.close);

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageDirectoryProvider.overrideWith((ref) async => dir.path),
          officialDatasetsProvider.overrideWithValue([official]),
          datasetHostProvider.overrideWithValue(
            Uri.parse('http://127.0.0.1:${files.port}/files'),
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

    // Download and verify.
    await tester.tap(find.text('Datasets'));
    await pumpUntil(tester, find.text('Mini Official'));
    await tester.tap(find.text('Download'));
    await pumpUntil(tester, find.text('Downloaded · 8 conversations'));

    // Sample 3 with the default seed 40.
    await tester.tap(find.text('Sample…'));
    await pumpUntil(tester, find.text('Create a sample'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Size (conversations)'),
      '3',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await pumpUntil(tester, find.text('mini_official_N3_seed40.jsonl'));

    // New run with the sample from the library dropdown.
    await tester.tap(find.text('New run'));
    await pumpUntil(tester, find.text('New evaluation run'));
    Finder field(String label) => find.widgetWithText(TextFormField, label);
    await tester.enterText(field('Base URL'), model.baseUrl.toString());
    await tester.enterText(field('API key'), 'sk-test');
    await tester.enterText(field('Model under test'), 'tested-model');
    await tester.enterText(field('Grader model'), 'grader-model');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await pumpUntil(
      tester,
      find.text('mini_official_N3_seed40.jsonl · 3 conversations'),
    );
    await tester.tap(
      find.text('mini_official_N3_seed40.jsonl · 3 conversations').last,
    );
    await tester.pump();
    await tester.tap(find.text('Start run'));
    await pumpUntil(tester, find.text('Open results'));
    expect(find.text('completed'), findsWidgets);
    expect(find.textContaining('3 of 3', findRichText: true), findsOneWidget);

    // The run used the sample: 3 conversations, each a record of the source.
    final sample = File(
      '${datasetsDirectoryIn(dir.path)}/mini_official_N3_seed40.jsonl',
    ).readAsLinesSync();
    expect(sample, hasLength(3));
    expect(sample, everyElement(isIn(utf8.decode(bytes).trim().split('\n'))));

    await tester.pumpWidget(const SizedBox());
  });
}
