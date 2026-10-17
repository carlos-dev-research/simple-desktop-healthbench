// US1: reading a HealthBench dataset (spec 002 FR-001–FR-003).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/dataset.dart';

import '../support/fixtures.dart';

void main() {
  late Directory dir;
  setUp(() => dir = tempDir(addTearDown));

  Future<Dataset> read(String text) async {
    final file = File('${dir.path}/data.jsonl')..writeAsStringSync(text);
    return readDataset(file.path);
  }

  Matcher failsAt(int line, String reasonPart) => throwsA(
    isA<DatasetFormatException>()
        .having((e) => e.line, 'line', line)
        .having((e) => e.reason, 'reason', contains(reasonPart)),
  );

  test('reads every conversation with all its fields', () async {
    final text = datasetText([
      datasetRecord(
        'a',
        prompt: [
          {'role': 'user', 'content': 'Hi'},
          {'role': 'assistant', 'content': 'Hello'},
          {'role': 'user', 'content': 'Chest pain'},
        ],
      ),
      datasetRecord('b'),
    ]);
    final dataset = await read(text);

    expect(dataset.fileName, 'data.jsonl');
    expect(dataset.sha256, sha256.convert(utf8.encode(text)).toString());
    expect(dataset.conversations, hasLength(2));
    final a = dataset.conversations.first;
    expect(a.index, 0);
    expect(a.promptId, 'a');
    expect(a.prompt.map((m) => m.role), ['user', 'assistant', 'user']);
    expect(a.criteria.map((c) => c.points), [5, -3]);
    expect(a.criteria.first.tags, ['axis:accuracy']);
    expect(a.exampleTags, ['theme:emergency_referrals']);
    expect(dataset.conversations[1].index, 1);
  });

  test(
    'criteria encoded as JSON text, and missing tags, are tolerated',
    () async {
      final dataset = await read(
        datasetText([
          datasetRecord(
            'a',
            rubrics: [
              jsonEncode(criterionJson('As text', 2)),
              {'criterion': 'No tags', 'points': 3.0, 'tags': null},
            ],
            exampleTags: null,
          ),
        ]),
      );
      final c = dataset.conversations.single;
      expect(c.criteria.map((x) => x.text), ['As text', 'No tags']);
      expect(c.criteria.map((x) => x.points), [2, 3]);
      expect(c.criteria[1].tags, isEmpty);
      expect(c.exampleTags, isEmpty);
    },
  );

  test('blank lines are skipped but still counted for line numbers', () async {
    final good = jsonEncode(datasetRecord('a'));
    expect((await read('\n$good\n\n')).conversations, hasLength(1));
    await expectLater(read('\n$good\n\n{oops'), failsAt(4, 'JSON'));
  });

  test('an invalid line fails the whole read, naming the line', () async {
    final good = jsonEncode(datasetRecord('a'));
    await expectLater(read('$good\nnot json\n'), failsAt(2, 'JSON'));
    await expectLater(
      read('$good\n${jsonEncode({'prompt_id': 'x'})}\n'),
      failsAt(2, 'prompt'),
    );
    await expectLater(
      read(datasetText([datasetRecord('a', rubrics: [])])),
      failsAt(1, 'rubrics'),
    );
    await expectLater(
      read(
        datasetText([
          datasetRecord('a', rubrics: [criterionJson('', 1)]),
        ]),
      ),
      failsAt(1, 'criterion'),
    );
    await expectLater(
      read(
        datasetText([
          datasetRecord(
            'a',
            rubrics: [
              {'criterion': 'x', 'points': 1.5},
            ],
          ),
        ]),
      ),
      failsAt(1, 'points'),
    );
  });

  test('duplicate prompt ids are rejected', () async {
    await expectLater(
      read(datasetText([datasetRecord('a'), datasetRecord('a')])),
      failsAt(2, 'duplicate'),
    );
  });

  test('an empty file is rejected', () async {
    await expectLater(read('\n\n'), failsAt(0, 'no conversations'));
  });

  test('a line over 8 MB is rejected', () async {
    final huge = jsonEncode(
      datasetRecord(
        'a',
        prompt: [
          {'role': 'user', 'content': 'x' * (8 * 1024 * 1024 + 1)},
        ],
      ),
    );
    await expectLater(read('$huge\n'), failsAt(1, 'too large'));
  });

  test('select returns the first N conversations, or all', () async {
    final dataset = await read(
      datasetText([for (var i = 0; i < 5; i++) datasetRecord('p$i')]),
    );
    expect(dataset.select(2).map((c) => c.promptId), ['p0', 'p1']);
    expect(dataset.select(null), hasLength(5));
    expect(dataset.select(50), hasLength(5));
    expect(() => dataset.select(0), throwsA(isA<ArgumentError>()));
  });
}
