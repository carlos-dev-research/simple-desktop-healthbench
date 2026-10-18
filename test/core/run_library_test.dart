// Listing the run files in the app's storage (spec 003 FR-009, FR-010).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/run_file.dart';
import 'package:healthbench/core/run_library.dart';

import '../support/fixtures.dart';
import 'run_file_test.dart' show validLines;

void main() {
  late Directory dir;
  setUp(() => dir = tempDir(addTearDown));

  void put(String name, List<Map<String, Object?>> lines) {
    final runId = name.replaceAll('.jsonl', '');
    final fixed = [
      {...lines.first, 'runId': runId},
      ...lines.skip(1),
    ];
    File('${dir.path}/$name')
        .writeAsStringSync('${fixed.map(jsonEncode).join('\n')}\n');
  }

  test('a missing folder is an empty library', () async {
    expect(await listRuns('${dir.path}/does-not-exist'), isEmpty);
  });

  test('valid runs newest first; invalid files listed with a reason; others ignored', () async {
    put('healthbench-run-20261001-090000.jsonl', validLines());
    put('healthbench-run-20261017-163000.jsonl', validLines());
    put('healthbench-run-20261017-163000-2.jsonl', validLines());
    File('${dir.path}/healthbench-run-20261002-000000.jsonl')
        .writeAsStringSync('garbage\n');
    File('${dir.path}/notes.txt').writeAsStringSync('ignored');
    File('${dir.path}/results.jsonl').writeAsStringSync('{}\n');
    Directory('${dir.path}/sub.jsonl').createSync();

    final entries = await listRuns(dir.path);
    final valid = [
      for (final e in entries)
        if (e.isValid) e.fileName,
    ];
    final rejected = {
      for (final e in entries)
        if (!e.isValid) e.fileName: e.error,
    };

    expect(valid, [
      'healthbench-run-20261017-163000-2.jsonl',
      'healthbench-run-20261017-163000.jsonl',
      'healthbench-run-20261001-090000.jsonl',
    ]);
    expect(
      rejected.keys,
      unorderedEquals([
        'healthbench-run-20261002-000000.jsonl',
        'results.jsonl',
      ]),
    );
    expect(
      rejected['healthbench-run-20261002-000000.jsonl'],
      contains('line 1'),
    );
    expect(rejected['results.jsonl'], contains('file name'));
    expect(entries.first.contents!.status, RunStatus.completed);
  });

  test('a run active in this app reads as running, not interrupted', () async {
    final lines = validLines()..removeLast();
    put('healthbench-run-20261017-163000.jsonl', lines);
    final path = '${dir.path}/healthbench-run-20261017-163000.jsonl';

    expect(
      (await listRuns(dir.path)).single.contents!.status,
      RunStatus.interrupted,
    );
    markRunActive(path);
    addTearDown(() => markRunInactive(path));
    expect(
      (await listRuns(dir.path)).single.contents!.status,
      RunStatus.running,
    );
  });

  test(
    'with a cache, a changed file is read again and a removed one dropped',
    () async {
      final cache = <String, (DateTime, int, RunEntry)>{};
      put('healthbench-run-20261017-163000.jsonl', validLines());
      expect(
        (await listRuns(dir.path, cache: cache)).single.contents!.status,
        RunStatus.completed,
      );

      // Overwrite with different content (a stopped run) and list again.
      put('healthbench-run-20261017-163000.jsonl', [
        ...validLines().sublist(0, 4),
        {
          'type': 'status',
          'status': 'stopped',
          'at': '2026-10-17T16:33:00.000-05:00',
          'graded': 2,
          'score': 0.75,
          'reason': null,
        },
      ]);
      expect(
        (await listRuns(dir.path, cache: cache)).single.contents!.status,
        RunStatus.stopped,
      );

      File('${dir.path}/healthbench-run-20261017-163000.jsonl').deleteSync();
      expect(await listRuns(dir.path, cache: cache), isEmpty);
      expect(cache, isEmpty);
    },
  );
}
