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
      RememberedForm? remembered,
    }) async {
      storage = tempDir(addTearDown).path;
      if (remembered != null) {
        await tester.runAsync(() => saveRememberedForm(storage, remembered));
      }
      final container = ProviderContainer(
        overrides: [
          storageDirectoryProvider.overrideWith((ref) async => storage),
          datasetPickerProvider.overrideWithValue(() async => pickedDataset),
        ],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);
      await tester.runAsync(
        () => container.read(rememberedFormProvider.future),
      );
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

    testWidgets('remembered fields are prefilled, but never the key', (
      tester,
    ) async {
      await pumpForm(
        tester,
        remembered: const RememberedForm(
          baseUrl: 'https://api.example.com/v1',
          modelTest: 'remembered-model',
          modelGrader: 'remembered-grader',
          limit: 12,
        ),
      );
      expect(find.text('https://api.example.com/v1'), findsOneWidget);
      expect(find.text('remembered-model'), findsOneWidget);
      expect(find.text('remembered-grader'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      final key = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'API key'),
      );
      expect(key.controller!.text, isEmpty);
    });
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
