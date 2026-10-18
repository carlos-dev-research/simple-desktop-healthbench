// Runs list, run detail, histogram, conversations and Continue
// (spec 003 US3, US4, FR-009–FR-014).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/run_file.dart';
import 'package:healthbench/ui/runs/runs_view.dart';
import 'package:healthbench/ui/state/providers.dart';
import 'package:healthbench/ui/state/runs_controller.dart';

import '../support/fixtures.dart';
import '../support/run_files.dart';

void main() {
  late ProviderContainer container;

  /// Two runs: a completed one (3/3) and a stopped one (1/3), plus a
  /// rejected file. Loads them into the container before pumping, because
  /// file reads don't complete inside the widget test's fake clock.
  Future<void> pumpRuns(WidgetTester tester) async {
    final dir = tempDir(addTearDown);
    final runs = runsDirectoryIn(dir.path);
    writeRunFile(
      runs,
      runId: 'healthbench-run-20261017-120000',
      model: 'model-complete',
      finalStatus: RunStatus.completed,
      conversations: [
        gradedConversation(0, [
          (5, true),
          (5, false),
          (-3, true),
        ], question: 'Chest pain since morning'),
        gradedConversation(
          1,
          [(4, true), (-2, false)],
          question: 'Rash on arm',
          reply: 'Use **cream**',
        ),
        gradedConversation(2, [(2, false)], question: 'Headache'),
      ],
    );
    writeRunFile(
      runs,
      runId: 'healthbench-run-20261017-130000',
      model: 'model-stopped',
      finalStatus: RunStatus.stopped,
      conversations: [
        gradedConversation(0, [(1, true)]),
      ],
    );
    File('$runs/healthbench-run-20261017-140000.jsonl')
        .writeAsStringSync('oops\n');

    container = ProviderContainer(
      overrides: [
        storageDirectoryProvider.overrideWith((ref) async => dir.path),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(runsProvider.future));

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: RunsView())),
      ),
    );
  }

  Future<void> select(WidgetTester tester, String model) async {
    await tester.tap(find.textContaining(model));
    await tester.pumpAndSettle();
  }

  testWidgets('lists runs newest first and the skipped file', (tester) async {
    await pumpRuns(tester);
    final stopped = tester.getTopLeft(find.textContaining('model-stopped')).dy;
    final complete = tester
        .getTopLeft(find.textContaining('model-complete'))
        .dy;
    expect(stopped, lessThan(complete)); // 13:00 before 12:00
    expect(find.text('completed'), findsOneWidget);
    expect(find.text('stopped'), findsOneWidget);
    expect(find.text('1 file(s) skipped'), findsOneWidget);

    await tester.tap(find.text('1 file(s) skipped'));
    await tester.pumpAndSettle();
    expect(find.textContaining('line 1'), findsOneWidget);
  });

  testWidgets('run summary tiles and histogram', (tester) async {
    await pumpRuns(tester);
    await select(tester, 'model-complete');

    // Scores: 2/10 = 0.2, 4/4 = 1.0, 0/2 = 0.0 → run score 0.4
    expect(find.text('0.400'), findsWidgets);
    expect(find.text('3/3'), findsOneWidget);
    expect(find.text('6'), findsWidgets); // criteria graded
    expect(find.textContaining('Positive criteria met (2/4)'), findsOneWidget);
    expect(find.textContaining('Penalties triggered (1/2)'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('0.0: 1, 0.1: 0, 0.2: 1.*0.9: 1')),
      findsOneWidget,
    );
    expect(find.textContaining('Continue'), findsNothing); // nothing missing
  });

  testWidgets('search and sort the conversations', (tester) async {
    await pumpRuns(tester);
    await select(tester, 'model-complete');
    expect(find.text('3 of 3'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'CREAM');
    await tester.pump();
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.text('Rash on arm'), findsOneWidget);
    expect(find.text('Headache'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Search'), '');
    await tester.pump();
    await tester.tap(find.text('Original order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Highest score first').last);
    await tester.pumpAndSettle();
    final rash = tester.getTopLeft(find.text('Rash on arm')).dy;
    final chest = tester.getTopLeft(find.text('Chest pain since morning')).dy;
    final headache = tester.getTopLeft(find.text('Headache')).dy;
    expect(rash < chest && chest < headache, isTrue);
  });

  testWidgets('an opened conversation shows messages, reply and rubric', (
    tester,
  ) async {
    await pumpRuns(tester);
    await select(tester, 'model-complete');
    await tester.tap(find.text('Chest pain since morning'));
    await tester.pumpAndSettle();

    expect(find.text('Model response (evaluated)'), findsOneWidget);
    expect(find.text('earned'), findsOneWidget);
    expect(find.text('missed'), findsOneWidget);
    expect(find.text('penalty'), findsOneWidget);
    expect(find.text('Criterion 1.3'), findsOneWidget);
    expect(find.text('Explanation 1.2'), findsOneWidget);
    expect(find.text('-3'), findsOneWidget);
    expect(find.text('+5'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an incomplete run offers Continue, asking for key and dataset', (
    tester,
  ) async {
    await pumpRuns(tester);
    await select(tester, 'model-stopped');
    expect(find.text('Continue (2 left)'), findsOneWidget);

    await tester.tap(find.text('Continue (2 left)'));
    await tester.pumpAndSettle();
    expect(find.text('Continue run'), findsOneWidget);
    final key = tester.widget<TextField>(
      find.widgetWithText(TextField, 'API key'),
    );
    expect(key.controller!.text, isEmpty);
    expect(key.obscureText, isTrue);
    expect(find.text('This run used data.jsonl'), findsOneWidget);

    await tester.tap(find.text('Continue').last);
    await tester.pump();
    expect(
      find.text('Enter the API key and choose the dataset.'),
      findsOneWidget,
    );
  });

  testWidgets('Continue reuses the key typed earlier in this session', (
    tester,
  ) async {
    await pumpRuns(tester);
    container
        .read(newRunFormProvider.notifier)
        .update((f) => f.copyWith(apiKey: 'sk-from-this-session'));
    await select(tester, 'model-stopped');
    await tester.tap(find.text('Continue (2 left)'));
    await tester.pumpAndSettle();

    final key = tester.widget<TextField>(
      find.widgetWithText(TextField, 'API key'),
    );
    expect(key.controller!.text, 'sk-from-this-session');
    expect(key.obscureText, isTrue);
  });
}
