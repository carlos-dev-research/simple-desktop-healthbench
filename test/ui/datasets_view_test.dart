// Datasets view, library dropdown in New run, Continue auto-selection
// (spec 005 US1–US4, FR-004, FR-005, FR-009).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/dataset_library.dart';
import 'package:healthbench/core/run_file.dart';
import 'package:healthbench/ui/datasets/datasets_view.dart';
import 'package:healthbench/ui/new_run/dataset_field.dart';
import 'package:healthbench/ui/runs/continue_dialog.dart';
import 'package:healthbench/ui/state/datasets_controller.dart';
import 'package:healthbench/ui/state/providers.dart';

import '../support/fixtures.dart';
import '../support/run_files.dart';

void main() {
  late String storage;
  late HttpServer host;
  late List<int> officialBytes;
  late OfficialDataset official;
  String? addPicked;

  setUp(() async {
    storage = tempDir(addTearDown).path;
    addPicked = null;
    officialBytes = utf8.encode(
      datasetText([for (var i = 0; i < 4; i++) datasetRecord('o$i')]),
    );
    official = OfficialDataset(
      fileName: 'official.jsonl',
      label: 'Test Official',
      description: 'four conversations',
      bytes: officialBytes.length,
      sha256: sha256.convert(officialBytes).toString(),
      conversations: 4,
    );
  });

  Future<ProviderContainer> pump(WidgetTester tester, Widget child) async {
    // Widget tests replace real HTTP with a stub that answers 400; these
    // tests talk to their own local host, so use real HTTP and restore after.
    final stubbed = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = stubbed);
    await tester.runAsync(() async {
      host = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      host.listen((r) async {
        r.response.contentLength = officialBytes.length;
        r.response.add(officialBytes);
        await r.response.close();
      });
    });
    addTearDown(() => tester.runAsync(() => host.close(force: true)));
    final container = ProviderContainer(
      overrides: [
        storageDirectoryProvider.overrideWith((ref) async => storage),
        officialDatasetsProvider.overrideWithValue([official]),
        datasetHostProvider.overrideWithValue(
          Uri.parse('http://127.0.0.1:${host.port}/files'),
        ),
        addFilePickerProvider.overrideWithValue(() async => addPicked),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(datasetLibraryProvider.future));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pump();
    return container;
  }

  /// Taps, then alternates real time (downloads, isolates, file I/O) with
  /// frames until [until] matches (or the UI settles, if none is given).
  Future<void> act(WidgetTester tester, Finder target, {Finder? until}) async {
    await tester.tap(target);
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (until != null && until.evaluate().isNotEmpty) break;
      if (until == null && i >= 10) break;
    }
    await tester.pumpAndSettle();
  }

  testWidgets('official file: download, verified, then shown as downloaded', (
    tester,
  ) async {
    await pump(tester, const DatasetsView());
    expect(find.text('Test Official'), findsOneWidget);
    expect(find.textContaining('No datasets yet'), findsOneWidget);

    await act(
      tester,
      find.text('Download'),
      until: find.text('Downloaded · 4 conversations'),
    );
    expect(find.text('Downloaded · 4 conversations'), findsOneWidget);
    expect(find.text('official.jsonl'), findsOneWidget); // now in the library
    expect(find.textContaining('Official · 4 conversations'), findsOneWidget);
    expect(
      File('${datasetsDirectoryIn(storage)}/official.jsonl').readAsBytesSync(),
      officialBytes,
    );
  });

  testWidgets('add a valid file; an invalid one is explained', (tester) async {
    await pump(tester, const DatasetsView());
    addPicked = writeDataset('${tempDir(addTearDown).path}/mine.jsonl', 6).path;
    await act(tester, find.text('Add file…'), until: find.text('mine.jsonl'));
    // ignore: avoid_print
    print(
      'DEBUG add: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).where((d) => d != null).toList()}',
    );
    expect(find.text('mine.jsonl'), findsOneWidget);
    expect(find.textContaining('Added file · 6 conversations'), findsOneWidget);

    final bad = '${tempDir(addTearDown).path}/bad.jsonl';
    await tester.runAsync(() => writeTextFile(bad, 'nope\n'));
    addPicked = bad;
    await act(
      tester,
      find.text('Add file…'),
      until: find.textContaining('Not a valid'),
    );
    expect(find.textContaining('Not a valid HealthBench file'), findsOneWidget);
  });

  testWidgets('create a sample; size is validated; delete asks first', (
    tester,
  ) async {
    await pump(tester, const DatasetsView());
    addPicked = writeDataset('${tempDir(addTearDown).path}/big.jsonl', 12).path;
    await act(tester, find.text('Add file…'), until: find.text('big.jsonl'));

    await act(
      tester,
      find.text('Sample…'),
      until: find.text('Create a sample'),
    );
    expect(find.text('Create a sample'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Size (conversations)'),
      '99',
    );
    await act(tester, find.widgetWithText(FilledButton, 'Create'));
    expect(
      find.text('Size must be a whole number from 1 to 12'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Size (conversations)'),
      '5',
    );
    await act(
      tester,
      find.widgetWithText(FilledButton, 'Create'),
      until: find.text('big_N5_seed40.jsonl'),
    );
    expect(find.text('big_N5_seed40.jsonl'), findsOneWidget);
    expect(
      find.textContaining('Sample of big.jsonl · 5 conversations'),
      findsOneWidget,
    );

    await act(tester, find.byTooltip('Delete dataset').last);
    expect(find.text('Delete dataset?'), findsOneWidget);
    await act(
      tester,
      find.widgetWithText(FilledButton, 'Delete'),
      until: find.textContaining('Deleted '),
    );
    expect(find.textContaining('Deleted '), findsOneWidget);
  });

  testWidgets('New run offers library datasets in a dropdown', (tester) async {
    final added = writeDataset(
      '${tempDir(addTearDown).path}/pick.jsonl',
      3,
    ).path;
    await tester.runAsync(
      () => addDatasetFile(added, datasetsDirectoryIn(storage)),
    );
    String? chosen;
    await pump(tester, DatasetField(onChanged: (path, _) => chosen = path));

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pick.jsonl · 3 conversations').last);
    await tester.pumpAndSettle();
    expect(chosen, '${datasetsDirectoryIn(storage)}/pick.jsonl');
  });

  testWidgets('Continue selects the run\'s dataset automatically by SHA-256', (
    tester,
  ) async {
    final file = writeDataset('${tempDir(addTearDown).path}/used.jsonl', 3);
    await tester.runAsync(
      () => addDatasetFile(file.path, datasetsDirectoryIn(storage)),
    );
    final sha = sha256.convert(file.readAsBytesSync()).toString();
    final runPath = writeRunFile(
      runsDirectoryIn(storage),
      runId: 'healthbench-run-20261018-100000',
      finalStatus: RunStatus.stopped,
      conversations: [
        gradedConversation(0, [(1, true)]),
      ],
    );
    // Point the run at the library dataset's fingerprint.
    final text = File(runPath)
        .readAsStringSync()
        .replaceFirst('"${'a' * 64}"', '"$sha"');
    File(runPath).writeAsStringSync(text);
    final contents = (await tester.runAsync(() => readRunFile(runPath)))!;

    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showContinueDialog(context, contents),
          child: const Text('open'),
        ),
      ),
    );
    await act(tester, find.text('open'), until: find.text('Continue run'));
    // Let the library load and the matching dataset be selected.
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.text('Continue run'), findsOneWidget);
    final dropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(dropdown.initialValue, '${datasetsDirectoryIn(storage)}/used.jsonl');
  });
}
