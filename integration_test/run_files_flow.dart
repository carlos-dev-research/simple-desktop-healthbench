// Owner checks automated inside the real (sandboxed) app, against a local
// fake endpoint: wrong key (003 U12), form kept across views (U13), stop and
// continue with the session key (U9, U10), export / delete / import (004
// E1–E3, E7). The system file dialogs are replaced by fixed paths.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/app.dart';
import 'package:healthbench/core/settings.dart';
import 'package:healthbench/ui/state/providers.dart';

import '../test/support/fake_openai_server.dart';
import '../test/support/fixtures.dart';
import 'evaluation_flow.dart' show pumpUntil;

const _goodKey = 'sk-good-INTEGRATION-1';

void main() {
  testWidgets(
    'wrong key, form kept, stop and continue, export, delete, import',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('healthbench_files_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final datasetPath = '${dir.path}/data.jsonl';
      writeDataset(datasetPath, 6);
      // Like the real save dialog, keep the suggested (run's own) file name.
      final exportDir = Directory('${dir.path}/exported')..createSync();
      String? exportPath;
      String? importPath;

      // Only the good key works; each reply takes a moment, so Stop can land
      // in the middle of a run.
      final server = await FakeOpenAiServer.start((r, _) {
        if (r.headers['authorization'] != 'Bearer $_goodKey') {
          return FakeResponse.error(401, 'Invalid API key');
        }
        return r.isGraderCall
            ? FakeResponse.grade(met: true)
            : FakeResponse.reply('reply')
                  .withDelay(const Duration(milliseconds: 250));
      });
      addTearDown(server.close);

      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageDirectoryProvider.overrideWith((ref) async => dir.path),
            datasetPickerProvider.overrideWithValue(() async => datasetPath),
            importPickerProvider.overrideWithValue(() async => importPath),
            exportLocationProvider.overrideWithValue(
              (suggested) async => exportPath = '${exportDir.path}/$suggested',
            ),
            clientOptionsProvider.overrideWithValue(
              const ClientOptions(
                timeout: Duration(seconds: 10),
                maxRetries: 0,
              ),
            ),
          ],
          retry: (_, _) => null,
          child: const HealthBenchApp(),
        ),
      );
      await tester.pump();
      final runsDir = Directory(runsDirectoryIn(dir.path));
      List<FileSystemEntity> runFiles() => runsDir.existsSync()
          ? runsDir.listSync().where((e) => e.path.endsWith('.jsonl')).toList()
          : [];
      Finder field(String label) => find.widgetWithText(TextFormField, label);

      // --- U12: a wrong key fails at once and saves nothing.
      await tester.tap(find.text('New run'));
      await pumpUntil(tester, find.text('New evaluation run'));
      await tester.enterText(field('Base URL'), server.baseUrl.toString());
      await tester.enterText(field('API key'), 'sk-wrong');
      await tester.enterText(field('Model under test'), 'tested-model');
      await tester.enterText(field('Grader model'), 'grader-model');
      await tester.tap(find.text('Choose dataset file…'));
      await pumpUntil(tester, find.text('data.jsonl · 6 conversations'));
      await tester.tap(find.text('Start run'));
      await pumpUntil(
        tester,
        find.text('Nothing was saved: no conversation could be graded.'),
      );
      expect(find.text('failed'), findsWidgets);
      expect(runFiles(), isEmpty);

      // --- U13: the form survives leaving the view.
      await tester.tap(find.text('Runs'));
      await tester.pump();
      await tester.tap(find.text('New run'));
      await pumpUntil(tester, find.text('New evaluation run'));
      String text(String label) =>
          tester.widget<TextFormField>(field(label)).controller!.text;
      expect(text('API key'), 'sk-wrong');
      expect(text('Model under test'), 'tested-model');
      expect(find.text('data.jsonl · 6 conversations'), findsOneWidget);

      // --- U9: start with the good key, stop part-way.
      await tester.enterText(field('API key'), _goodKey);
      await tester.tap(find.text('Start run'));
      await pumpUntil(
        tester,
        find.textContaining('1 of 6', findRichText: true),
      );
      await tester.tap(find.text('Stop'));
      await pumpUntil(tester, find.text('Open results'));
      expect(find.text('stopped'), findsWidgets);

      // --- U10: Continue, with this session's key prefilled.
      await tester.tap(find.text('Open results'));
      await pumpUntil(tester, find.textContaining('Continue ('));
      await tester.tap(find.textContaining('Continue ('));
      await pumpUntil(tester, find.text('Continue run'));
      final dialogKey = tester.widget<TextField>(
        find.widgetWithText(TextField, 'API key'),
      );
      expect(dialogKey.controller!.text, _goodKey);
      await tester.tap(find.text('Choose dataset file…').last);
      await pumpUntil(tester, find.text('data.jsonl · 6 conversations'));
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await pumpUntil(
        tester,
        find.textContaining('6 of 6', findRichText: true),
        timeout: const Duration(seconds: 60),
      );
      await pumpUntil(tester, find.text('Open results'));
      expect(find.text('completed'), findsWidgets);
      expect(runFiles(), hasLength(1));
      final runPath = runFiles().single.path;

      // --- E1: export an identical copy.
      await tester.tap(find.text('Open results'));
      await pumpUntil(tester, find.byTooltip('Export'));
      await tester.tap(find.byTooltip('Export'));
      await pumpUntil(tester, find.textContaining('Exported to'));
      expect(
        File(exportPath!).readAsBytesSync(),
        File(runPath).readAsBytesSync(),
      );

      // --- E2: delete it, after confirming.
      await tester.tap(find.byTooltip('Delete'));
      await pumpUntil(tester, find.text('Delete run?'));
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await pumpUntil(tester, find.textContaining('Deleted '));
      expect(runFiles(), isEmpty);

      // --- E3 / E7: import the exported copy back; it can still be viewed.
      importPath = exportPath; // the exported copy, under its run-file name
      await tester.tap(find.text('Import'));
      await pumpUntil(tester, find.textContaining('Imported '));
      expect(runFiles(), hasLength(1));
      expect(
        File(runFiles().single.path).readAsBytesSync(),
        File(exportPath!).readAsBytesSync(),
      );
      await pumpUntil(tester, find.text('6/6'));
      expect(
        File(exportPath!).existsSync(),
        isTrue,
      ); // the original is untouched

      await tester.pumpWidget(const SizedBox());
    },
  );
}
