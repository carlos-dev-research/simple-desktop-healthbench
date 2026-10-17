// Import, export and delete of run files (spec 004 FR-002–FR-006;
// Constitution V.3, V.4).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/dataset.dart' show fileNameOf;
import 'package:healthbench/core/run_file.dart';
import 'package:healthbench/core/run_library.dart';

import '../support/fixtures.dart';
import '../support/run_files.dart';

void main() {
  late Directory root;
  late String runs;
  late String outside;
  const runId = 'healthbench-run-20261017-120000';

  setUp(() {
    root = tempDir(addTearDown);
    runs = '${root.path}/runs';
    outside = '${root.path}/elsewhere';
    Directory(runs).createSync();
    Directory(outside).createSync();
  });

  String makeRun(String dir, {String id = runId, String model = 'm'}) =>
      writeRunFile(
        dir,
        runId: id,
        model: model,
        finalStatus: RunStatus.stopped,
        conversations: [
          gradedConversation(0, [(2, true)]),
        ],
      );

  group('checkImport', () {
    test('a valid run file outside the app is ready to import', () async {
      final source = makeRun(outside);
      final check = await checkImport(source, runs);
      expect(check, isA<ImportReady>());
      final ready = check as ImportReady;
      expect(fileNameOf(ready.targetPath), '$runId.jsonl');
      expect(ready.replacesExisting, isFalse);
      expect(ready.contents.header.runId, runId);
    });

    test('a name that already exists is flagged for replacement', () async {
      makeRun(runs);
      final check = await checkImport(makeRun(outside, model: 'other'), runs);
      expect((check as ImportReady).replacesExisting, isTrue);
    });

    test('invalid files are rejected with the reason', () async {
      final badName = File('$outside/results.jsonl')..writeAsStringSync('{}\n');
      final badContent = File('$outside/healthbench-run-20261017-130000.jsonl')
        ..writeAsStringSync('not json\n');
      final dataset = writeDataset(
        '$outside/healthbench-run-20261017-140000.jsonl',
        2,
      );

      for (final (file, part) in [
        (badName, 'file name'),
        (badContent, 'line 1'),
        (dataset, 'line 1'),
      ]) {
        final check = await checkImport(file.path, runs);
        expect(check, isA<ImportRejected>(), reason: file.path);
        expect((check as ImportRejected).reason, contains(part));
      }
    });

    test('a file already in the app is reported as such', () async {
      final inside = makeRun(runs);
      expect(await checkImport(inside, runs), isA<ImportAlreadyInApp>());
    });

    test('a file with a cut-off last line is accepted', () async {
      final source = makeRun(outside);
      File(source)
          .writeAsStringSync('{"type":"conversa', mode: FileMode.append);
      expect(await checkImport(source, runs), isA<ImportReady>());
    });
  });

  group('importRun', () {
    test(
      'copies the file in; the original is untouched; no temp file left',
      () async {
        final source = makeRun(outside);
        final before = File(source).readAsBytesSync();
        final ready = await checkImport(source, runs) as ImportReady;
        final target = await importRun(ready, replace: false);

        expect(File(target).readAsBytesSync(), before);
        expect(File(source).readAsBytesSync(), before);
        expect(Directory(runs).listSync().map((e) => fileNameOf(e.path)), [
          '$runId.jsonl',
        ]);
      },
    );

    test('replaces an existing run only when asked', () async {
      makeRun(runs, model: 'old');
      final ready = await checkImport(
        makeRun(outside, model: 'new'),
        runs,
      ) as ImportReady;
      await expectLater(importRun(ready, replace: false), throwsStateError);
      await importRun(ready, replace: true);
      final contents = await readRunFile('$runs/$runId.jsonl');
      expect(contents.header.modelTest.name, 'new');
    });

    test('refuses to replace a run that is running', () async {
      final existing = makeRun(runs);
      final ready = await checkImport(makeRun(outside), runs) as ImportReady;
      markRunActive(existing);
      addTearDown(() => markRunInactive(existing));
      await expectLater(
        importRun(ready, replace: true),
        throwsA(isA<RunActiveException>()),
      );
    });
  });

  group('exportRun', () {
    test('writes a byte-identical copy to the chosen place', () async {
      final path = makeRun(runs);
      final destination = '$outside/my-export.jsonl';
      await exportRun(path, destination);
      expect(File(destination).readAsBytesSync(), File(path).readAsBytesSync());
    });

    test('refuses while the run is running', () async {
      final path = makeRun(runs);
      markRunActive(path);
      addTearDown(() => markRunInactive(path));
      await expectLater(
        exportRun(path, '$outside/x.jsonl'),
        throwsA(isA<RunActiveException>()),
      );
      expect(File('$outside/x.jsonl').existsSync(), isFalse);
    });
  });

  group('deleteRun', () {
    test('removes the file', () async {
      final path = makeRun(runs);
      await deleteRun(path);
      expect(File(path).existsSync(), isFalse);
    });

    test('refuses while the run is running', () async {
      final path = makeRun(runs);
      markRunActive(path);
      addTearDown(() => markRunInactive(path));
      await expectLater(deleteRun(path), throwsA(isA<RunActiveException>()));
      expect(File(path).existsSync(), isTrue);
    });
  });
}
