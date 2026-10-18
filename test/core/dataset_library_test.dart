// Spec 005: the dataset library (download, add, sample, list, delete).
// Downloads use a local fake host and small fixture files with their own
// pinned size / SHA-256 / count; no test touches the real host.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/dataset.dart';
import 'package:healthbench/core/dataset_library.dart';

import '../support/fixtures.dart';

/// Serves [files] by name; [delay] slows each response (for cancel tests).
Future<HttpServer> fileHost(
  Map<String, List<int>> files, {
  Duration delay = Duration.zero,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final name = request.uri.pathSegments.last;
    final body = files[name];
    if (body == null) {
      request.response.statusCode = 404;
    } else {
      request.response.contentLength = body.length;
      // Send in two halves, pausing in between, so progress and cancel can
      // be observed mid-download.
      final half = body.length ~/ 2;
      request.response.add(body.sublist(0, half));
      await request.response.flush();
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      request.response.add(body.sublist(half));
    }
    try {
      await request.response.close();
    } on Object {
      // Client went away (cancel test).
    }
  });
  return server;
}

void main() {
  late Directory root;
  late String library;
  setUp(() {
    root = tempDir(addTearDown);
    library = '${root.path}/datasets';
  });

  List<int> datasetBytes(int count) => utf8.encode(
    datasetText([for (var i = 0; i < count; i++) datasetRecord('p$i')]),
  );

  OfficialDataset pinned(String name, List<int> bytes, int count) =>
      OfficialDataset(
        fileName: name,
        label: name,
        description: 'test file',
        bytes: bytes.length,
        sha256: sha256.convert(bytes).toString(),
        conversations: count,
      );

  test('the three official files are pinned', () {
    expect(officialDatasets.map((d) => d.fileName), [
      '2025-05-07-06-14-12_oss_eval.jsonl',
      'hard_2025-05-08-21-00-10.jsonl',
      'consensus_2025-05-09-20-00-46.jsonl',
    ]);
    expect(officialDatasets.map((d) => d.conversations), [5000, 1000, 3671]);
    for (final d in officialDatasets) {
      expect(d.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(d.bytes, greaterThan(1000000));
    }
    expect(officialDatasetHost.host, 'openaipublic.blob.core.windows.net');
  });

  group('download', () {
    test('streams with progress, verifies, and lands in the library', () async {
      final bytes = datasetBytes(4);
      final host = await fileHost({'data.jsonl': bytes});
      addTearDown(host.close);
      final progress = <int>[];
      final entry = await downloadOfficial(
        pinned('data.jsonl', bytes, 4),
        library,
        host: Uri.parse('http://127.0.0.1:${host.port}/files'),
        onProgress: (received, total) => progress.add(received),
      );
      expect(entry.fileName, 'data.jsonl');
      expect(entry.conversations, 4);
      expect(entry.origin, DatasetOrigin.official);
      expect(File(entry.path).readAsBytesSync(), bytes);
      expect(progress.last, bytes.length);
      expect(
        Directory(library).listSync().map((e) => fileNameOf(e.path)),
        contains('data.jsonl'),
      );
    });

    for (final (what, tamper) in [
      (
        'size',
        (OfficialDataset d) => OfficialDataset(
          fileName: d.fileName,
          label: d.label,
          description: d.description,
          bytes: d.bytes + 1,
          sha256: d.sha256,
          conversations: d.conversations,
        ),
      ),
      (
        'SHA-256',
        (OfficialDataset d) => OfficialDataset(
          fileName: d.fileName,
          label: d.label,
          description: d.description,
          bytes: d.bytes,
          sha256: '0' * 64,
          conversations: d.conversations,
        ),
      ),
      (
        'count',
        (OfficialDataset d) => OfficialDataset(
          fileName: d.fileName,
          label: d.label,
          description: d.description,
          bytes: d.bytes,
          sha256: d.sha256,
          conversations: 99,
        ),
      ),
    ]) {
      test('a $what mismatch is rejected and nothing is kept', () async {
        final bytes = datasetBytes(3);
        final host = await fileHost({'data.jsonl': bytes});
        addTearDown(host.close);
        await expectLater(
          downloadOfficial(
            tamper(pinned('data.jsonl', bytes, 3)),
            library,
            host: Uri.parse('http://127.0.0.1:${host.port}/files'),
          ),
          throwsA(isA<DatasetDownloadException>()),
        );
        expect(
          Directory(library).existsSync()
              ? Directory(library).listSync()
              : <FileSystemEntity>[],
          isEmpty,
        );
      });
    }

    test('an HTTP error is reported, nothing kept', () async {
      final host = await fileHost({});
      addTearDown(host.close);
      await expectLater(
        downloadOfficial(
          pinned('missing.jsonl', [1, 2, 3], 1),
          library,
          host: Uri.parse('http://127.0.0.1:${host.port}/files'),
        ),
        throwsA(
          isA<DatasetDownloadException>().having(
            (e) => e.reason,
            'reason',
            contains('404'),
          ),
        ),
      );
      expect(
        Directory(library).existsSync()
            ? Directory(library).listSync()
            : <FileSystemEntity>[],
        isEmpty,
      );
    });

    test('cancel stops the download and leaves no partial file', () async {
      final bytes = datasetBytes(50);
      final host = await fileHost({
        'data.jsonl': bytes,
      }, delay: const Duration(seconds: 3));
      addTearDown(host.close);
      final cancel = Completer<void>();
      final download = downloadOfficial(
        pinned('data.jsonl', bytes, 50),
        library,
        host: Uri.parse('http://127.0.0.1:${host.port}/files'),
        cancel: cancel.future,
        onProgress: (received, _) {
          if (received > 0 && !cancel.isCompleted) cancel.complete();
        },
      );
      await expectLater(download, throwsA(isA<DownloadCancelled>()));
      expect(Directory(library).listSync(), isEmpty);
    });
  });

  group('add a local file', () {
    test('valid: copied in, original untouched', () async {
      final source = writeDataset('${root.path}/mine.jsonl', 5);
      final result = await addDatasetFile(source.path, library);
      expect(result.alreadyPresent, isFalse);
      expect(result.entry.fileName, 'mine.jsonl');
      expect(result.entry.origin, DatasetOrigin.added);
      expect(result.entry.conversations, 5);
      expect(source.existsSync(), isTrue);
    });

    test('invalid: rejected naming the line, nothing written', () async {
      final bad = File('${root.path}/bad.jsonl')
        ..writeAsStringSync('${jsonEncode(datasetRecord('a'))}\nnope\n');
      await expectLater(
        addDatasetFile(bad.path, library),
        throwsA(isA<DatasetFormatException>().having((e) => e.line, 'line', 2)),
      );
      expect(
        Directory(library).existsSync()
            ? Directory(library).listSync()
            : <FileSystemEntity>[],
        isEmpty,
      );
    });

    test('the same file twice is recognised; a different file with the same name gets -2', () async {
      final a = writeDataset('${root.path}/same.jsonl', 3);
      await addDatasetFile(a.path, library);
      expect((await addDatasetFile(a.path, library)).alreadyPresent, isTrue);

      Directory('${root.path}/other').createSync();
      final b = writeDataset('${root.path}/other/same.jsonl', 4);
      final added = await addDatasetFile(b.path, library);
      expect(added.alreadyPresent, isFalse);
      expect(added.entry.fileName, 'same-2.jsonl');
    });
  });

  group('samples', () {
    late LibraryDataset source;
    setUp(() async {
      final file = writeDataset('${root.path}/big.jsonl', 40);
      source = (await addDatasetFile(file.path, library)).entry;
    });

    test('N conversations, named after source, N and seed, in original order, lines unchanged', () async {
      final sample = await createSample(source, 10, 40, library);
      expect(sample.fileName, 'big_N10_seed40.jsonl');
      expect(sample.origin, DatasetOrigin.sample);
      expect(sample.conversations, 10);

      final sourceLines = File(source.path).readAsLinesSync();
      final sampleLines = File(sample.path).readAsLinesSync();
      expect(sampleLines, everyElement(isIn(sourceLines)));
      final positions = [for (final l in sampleLines) sourceLines.indexOf(l)];
      expect(positions, orderedEquals([...positions]..sort()));
    });

    test(
      'deterministic: same source, N and seed give a byte-identical file',
      () async {
        final first = await createSample(source, 10, 40, library);
        final bytes = File(first.path).readAsBytesSync();
        await deleteDataset(first.path);
        final again = await createSample(source, 10, 40, library);
        expect(File(again.path).readAsBytesSync(), bytes);
        final otherSeed = await createSample(source, 10, 41, library);
        expect(File(otherSeed.path).readAsBytesSync(), isNot(bytes));
      },
    );

    test('N out of range is refused', () async {
      await expectLater(
        createSample(source, 0, 40, library),
        throwsArgumentError,
      );
      await expectLater(
        createSample(source, 41, 40, library),
        throwsArgumentError,
      );
    });

    test('a sample of a sample works', () async {
      final first = await createSample(source, 20, 40, library);
      final second = await createSample(first, 5, 7, library);
      expect(second.fileName, 'big_N20_seed40_N5_seed7.jsonl');
      expect(second.conversations, 5);
    });
  });

  group('listing and deleting', () {
    test('lists datasets with origin, count, size and SHA-256; ignores partial downloads', () async {
      final file = writeDataset('${root.path}/x.jsonl', 6);
      final added = (await addDatasetFile(file.path, library)).entry;
      File('$library/oss.jsonl.part').writeAsStringSync('half a download');

      final listed = await listLibrary(library);
      expect(listed.map((d) => d.fileName), ['x.jsonl']);
      expect(listed.single.conversations, 6);
      expect(listed.single.bytes, File(added.path).lengthSync());
      expect(
        listed.single.sha256,
        sha256.convert(File(added.path).readAsBytesSync()).toString(),
      );
    });

    test('a changed file is read again (the index is not stale)', () async {
      final file = writeDataset('${root.path}/x.jsonl', 6);
      final added = (await addDatasetFile(file.path, library)).entry;
      expect((await listLibrary(library)).single.conversations, 6);
      writeDataset(added.path, 8);
      expect((await listLibrary(library)).single.conversations, 8);
    });

    test('delete removes it; refused while in use', () async {
      final file = writeDataset('${root.path}/x.jsonl', 2);
      final added = (await addDatasetFile(file.path, library)).entry;
      await expectLater(
        deleteDataset(added.path, inUse: {added.path}),
        throwsA(isA<StateError>()),
      );
      await deleteDataset(added.path);
      expect(await listLibrary(library), isEmpty);
    });

    test('a missing library folder is an empty library', () async {
      expect(await listLibrary('${root.path}/none'), isEmpty);
    });
  });
}
