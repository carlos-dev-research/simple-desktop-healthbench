import 'dart:io';

// New-run form and progress panel (spec 003 US1, US2; FR-002–FR-008).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/run_file.dart';
import 'package:healthbench/core/runner.dart';
import 'package:healthbench/ui/new_run/new_run_view.dart';
import 'package:healthbench/ui/new_run/progress_panel.dart';
import 'package:healthbench/ui/state/providers.dart';

import '../support/fixtures.dart';

void main() {
  group('form', () {
    late String storage;

    Future<ProviderContainer> pumpForm(
      WidgetTester tester, {
      String? pickedDataset,
    }) async {
      storage = tempDir(addTearDown).path;
      final container = ProviderContainer(
        overrides: [
          storageDirectoryProvider.overrideWith((ref) async => storage),
          datasetPickerProvider.overrideWithValue(() async => pickedDataset),
        ],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1100);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: NewRunView())),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets('starting with empty fields shows why, and nothing starts', (
      tester,
    ) async {
      await pumpForm(tester);
      await tester.tap(find.text('Start run'));
      await tester.pump();
      expect(
        find.text('Base URL must be a full http(s) URL with a host'),
        findsOneWidget,
      );
      expect(find.text('The API key is required'), findsOneWidget);
      expect(find.text('The model is required'), findsOneWidget);
      expect(find.text('The grader model is required'), findsOneWidget);
      expect(find.text('Choose a dataset file'), findsOneWidget);
      expect(find.text('Progress'), findsNothing);
    });

    testWidgets('a base URL with credentials and a bad limit are rejected', (
      tester,
    ) async {
      await pumpForm(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Base URL'),
        'https://u:p@host/v1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Max conversations (optional)'),
        '0',
      );
      await tester.tap(find.text('Start run'));
      await tester.pump();
      expect(
        find.text('Base URL must not contain a user name or password'),
        findsOneWidget,
      );
      expect(find.text('Enter a whole number of at least 1'), findsOneWidget);
    });

    testWidgets('the API key is hidden and can be revealed', (tester) async {
      await pumpForm(tester);
      EditableText key() => tester.widget<EditableText>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'API key'),
          matching: find.byType(EditableText),
        ),
      );
      expect(key().obscureText, isTrue);
      await tester.tap(find.byTooltip('Show'));
      await tester.pump();
      expect(key().obscureText, isFalse);
    });

    testWidgets('a chosen dataset is read and its size shown', (tester) async {
      final dir = tempDir(addTearDown);
      writeDataset('${dir.path}/data.jsonl', 7);
      await pumpForm(tester, pickedDataset: '${dir.path}/data.jsonl');

      await tester.runAsync(() async {
        await tester.tap(find.text('Choose dataset file…'));
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      await tester.pump();
      expect(find.text('data.jsonl · 7 conversations'), findsOneWidget);
    });

    testWidgets('an invalid dataset shows the reader\'s reason', (
      tester,
    ) async {
      final dir = tempDir(addTearDown);
      final path = '${dir.path}/bad.jsonl';
      await tester.runAsync(() async {
        await writeTextFile(path, '{"prompt_id": 1}\n');
      });
      await pumpForm(tester, pickedDataset: path);
      await tester.runAsync(() async {
        await tester.tap(find.text('Choose dataset file…'));
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      await tester.pump();
      expect(find.textContaining('Dataset line 1'), findsOneWidget);
    });

    testWidgets(
      'every field survives switching views; nothing is saved to disk',
      (tester) async {
        final dir = tempDir(addTearDown);
        writeDataset('${dir.path}/data.jsonl', 4);
        final container = await pumpForm(
          tester,
          pickedDataset: '${dir.path}/data.jsonl',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Base URL'),
          'https://api.example.com/v1',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'API key'),
          'sk-session-key',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Model under test'),
          'model-a',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Grader model'),
          'model-b',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Max conversations (optional)'),
          '12',
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('Choose dataset file…'));
          await Future<void>.delayed(const Duration(seconds: 1));
        });
        await tester.pump();

        // Leave the view (it is disposed), then come back.
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: Scaffold(body: SizedBox())),
          ),
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: Scaffold(body: NewRunView())),
          ),
        );
        await tester.pump();

        String fieldText(String label) => tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, label))
            .controller!
            .text;
        expect(fieldText('Base URL'), 'https://api.example.com/v1');
        expect(fieldText('API key'), 'sk-session-key');
        expect(fieldText('Model under test'), 'model-a');
        expect(fieldText('Grader model'), 'model-b');
        expect(fieldText('Max conversations (optional)'), '12');
        expect(find.text('data.jsonl · 4 conversations'), findsOneWidget);
        expect(
          container.read(newRunFormProvider).datasetPath,
          '${dir.path}/data.jsonl',
        );

        // Nothing was written to the app's storage.
        final written = await tester.runAsync(
          () => Directory(storage).list().toList(),
        );
        expect(written, isEmpty);
      },
    );
  });

  group('progress panel', () {
    RunProgress progress({
      RunStatus status = RunStatus.running,
      bool stopRequested = false,
      int done = 2,
      int failed = 1,
      int criterionDone = 1,
      int criterionTotal = 4,
      String? failureReason,
      List<String> errors = const [
        'Conversation 2 (p1): Temporary error (HTTP 500)',
      ],
    }) => RunProgress(
      runId: 'healthbench-run-20261017-163000',
      status: status,
      stopRequested: stopRequested,
      total: 5,
      done: done,
      failed: failed,
      criterionDone: criterionDone,
      criterionTotal: criterionTotal,
      score: 0.5,
      recentErrors: errors,
      elapsed: const Duration(minutes: 1, seconds: 30),
      failureReason: failureReason,
    );

    Future<void> pumpPanel(
      WidgetTester tester,
      RunProgress p, {
      VoidCallback? onStop,
      VoidCallback? onOpen,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProgressPanel(
                progress: p,
                runFilePath: '/x/run.jsonl',
                modelsLabel: 'm graded by g',
                onStop: onStop,
                onOpenResults: onOpen,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a running run shows counts, criteria, times and errors', (
      tester,
    ) async {
      var stopped = false;
      await pumpPanel(tester, progress(), onStop: () => stopped = true);

      expect(find.text('running'), findsOneWidget);
      expect(find.textContaining('3 of 5'), findsOneWidget);
      expect(find.textContaining('1 failed'), findsOneWidget);
      expect(
        find.text('Conversation 4: graded 1 of 4 criteria'),
        findsOneWidget,
      );
      expect(find.text('Score so far'), findsOneWidget);
      expect(find.text('0.500'), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);
      expect(find.textContaining('Temporary error (HTTP 500)'), findsOneWidget);

      await tester.tap(find.text('Stop'));
      expect(stopped, isTrue);
      await tester.pumpWidget(const SizedBox()); // stop the 1 s ticker
    });

    testWidgets(
      'time left after Continue counts only this session (code review #7)',
      (tester) async {
        // 90 of 100 graded before; 1 more in 60 s this session → 9 left ≈ 9:00.
        await pumpPanel(
          tester,
          const RunProgress(
            runId: 'healthbench-run-20261017-163000',
            status: RunStatus.running,
            stopRequested: false,
            total: 100,
            done: 91,
            doneAtSessionStart: 90,
            failed: 0,
            criterionDone: 0,
            criterionTotal: 0,
            score: 0.5,
            recentErrors: [],
            elapsed: Duration(seconds: 60),
          ),
        );
        expect(find.text('9:00'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('a requested stop is shown and cannot be repeated', (
      tester,
    ) async {
      await pumpPanel(tester, progress(stopRequested: true), onStop: () {});
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNull);
      expect(find.text('Stopping after this conversation…'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('generating the response before any criterion', (tester) async {
      await pumpPanel(tester, progress(criterionTotal: 0, criterionDone: 0));
      expect(
        find.text('Conversation 4: generating the model response…'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed run shows the reason and offers the results', (
      tester,
    ) async {
      var opened = false;
      await pumpPanel(
        tester,
        progress(
          status: RunStatus.failed,
          failureReason: 'Authentication failed (HTTP 401): bad key',
        ),
        onOpen: () => opened = true,
      );
      expect(
        find.text('The run stopped: Authentication failed (HTTP 401): bad key'),
        findsOneWidget,
      );
      expect(find.text('Final score'), findsOneWidget);
      expect(find.text('Stop'), findsNothing);
      await tester.tap(find.text('Open results'));
      expect(opened, isTrue);
    });
  });
}
