// Export, delete and import from the Runs view (spec 004 US1–US3).
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

const _runId = 'healthbench-run-20261017-120000';

void main() {
  late String runs;
  late String outside;
  String? picked;
  String? saveTo;

  Future<void> pumpRuns(
    WidgetTester tester, {
    RunStatus status = RunStatus.completed,
    bool active = false,
  }) async {
    final root = tempDir(addTearDown).path;
    runs = runsDirectoryIn(root);
    outside = '$root/outside';
    Directory(outside).createSync();
    picked = null;
    saveTo = null;
    final path = writeRunFile(
      runs,
      runId: _runId,
      model: 'stored-model',
      finalStatus: status,
      conversations: [
        gradedConversation(0, [(3, true)]),
      ],
    );
    if (active) {
      markRunActive(path);
      addTearDown(() => markRunInactive(path));
    }
    final container = ProviderContainer(
      overrides: [
        storageDirectoryProvider.overrideWith((ref) async => root),
        importPickerProvider.overrideWithValue(() async => picked),
        exportLocationProvider.overrideWithValue((_) async => saveTo),
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
    await tester.tap(find.textContaining('stored-model'));
    await tester.pumpAndSettle();
  }

  /// Taps, then alternates real time (for file work and isolates) with
  /// frames (so each `await` in the flow can continue), then settles.
  Future<void> act(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  String runPath() => '$runs${Platform.pathSeparator}$_runId.jsonl';

  testWidgets('export writes an identical copy where the user chose', (
    tester,
  ) async {
    await pumpRuns(tester);
    saveTo = '$outside/copy.jsonl';
    await act(tester, find.byTooltip('Export'));

    expect(File(saveTo!).readAsBytesSync(), File(runPath()).readAsBytesSync());
    expect(find.textContaining('Exported to'), findsOneWidget);
  });

  testWidgets('export cancelled does nothing', (tester) async {
    await pumpRuns(tester);
    await act(tester, find.byTooltip('Export'));
    expect(Directory(outside).listSync(), isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('delete asks first; cancel keeps, confirm removes', (
    tester,
  ) async {
    await pumpRuns(tester);
    await act(tester, find.byTooltip('Delete'));
    expect(find.text('Delete run?'), findsOneWidget);
    expect(find.textContaining("can't be undone"), findsOneWidget);
    await act(tester, find.text('Cancel'));
    expect(File(runPath()).existsSync(), isTrue);

    await act(tester, find.byTooltip('Delete'));
    await act(tester, find.widgetWithText(FilledButton, 'Delete'));
    expect(File(runPath()).existsSync(), isFalse);
    expect(find.textContaining('stored-model'), findsNothing);
    expect(find.text('Deleted $_runId.jsonl'), findsOneWidget);
  });

  testWidgets('a running run offers neither export nor delete', (tester) async {
    await pumpRuns(tester, status: RunStatus.running, active: true);
    expect(find.text('running'), findsWidgets);
    expect(find.byTooltip('Export'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);
  });

  testWidgets('import a valid file: copied in, listed and selected', (
    tester,
  ) async {
    await pumpRuns(tester);
    picked = writeRunFile(
      outside,
      runId: 'healthbench-run-20261018-090000',
      model: 'imported-model',
      finalStatus: RunStatus.stopped,
      conversations: [
        gradedConversation(0, [(1, true)]),
      ],
    );
    await act(tester, find.text('Import'));

    expect(
      File('$runs/healthbench-run-20261018-090000.jsonl').existsSync(),
      isTrue,
    );
    expect(File(picked!).existsSync(), isTrue); // original untouched
    expect(
      find.text('healthbench-run-20261018-090000'),
      findsOneWidget,
    ); // selected
    expect(
      find.text('Imported healthbench-run-20261018-090000.jsonl'),
      findsOneWidget,
    );
  });

  testWidgets('import an invalid file: rejected with the reason', (
    tester,
  ) async {
    await pumpRuns(tester);
    picked = '$outside/healthbench-run-20261018-090000.jsonl';
    await tester.runAsync(() => writeTextFile(picked!, 'not json\n'));
    await act(tester, find.text('Import'));

    expect(find.text("Can't import this file"), findsOneWidget);
    expect(find.textContaining('line 1'), findsOneWidget);
    expect(Directory(runs).listSync(), hasLength(1));
  });

  testWidgets('import with the same name asks before replacing', (
    tester,
  ) async {
    await pumpRuns(tester);
    picked = writeRunFile(
      outside,
      runId: _runId,
      model: 'replacement-model',
      finalStatus: RunStatus.completed,
      conversations: [
        gradedConversation(0, [(1, false)]),
      ],
    );
    await act(tester, find.text('Import'));
    expect(find.text('Replace existing run?'), findsOneWidget);
    await act(tester, find.widgetWithText(FilledButton, 'Replace'));

    final contents = await tester.runAsync(() => readRunFile(runPath()));
    expect(contents!.header.modelTest.name, 'replacement-model');
    expect(find.textContaining('replacement-model'), findsWidgets);
  });
}
