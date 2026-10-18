// US6: run files are written append-only and read with full validation
// (spec 002 FR-017–FR-020; contracts/run-file.md RF-1–RF-9).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/dataset.dart';
import 'package:healthbench/core/grader_prompt.dart';
import 'package:healthbench/core/grading.dart';
import 'package:healthbench/core/run_file.dart';
import 'package:healthbench/core/scoring.dart';
import 'package:healthbench/core/settings.dart';

import '../support/fixtures.dart';

const _runId = 'healthbench-run-20261017-163000';

RunHeader header({int? limit = 2}) => RunHeader(
  runId: _runId,
  app: 'HealthBench Evals',
  appVersion: '0.1.0',
  createdAt: DateTime.parse('2026-10-17T16:30:00-05:00'),
  baseUrl: Uri.parse('https://api.example.com/v1'),
  modelTest: ModelSettings(name: 'm', reasoningEffort: ReasoningEffort.low),
  modelGrader: ModelSettings(name: 'g'),
  temperature: 0.3,
  graderPromptId: graderPromptId,
  graderPromptSha256: graderPromptSha256,
  dataset: DatasetRef(
    fileName: 'data.jsonl',
    sha256: 'a' * 64,
    conversationCount: 5,
    limit: limit,
  ),
);

GradedConversation graded(int index, List<(int, bool)> grades) {
  final criteria = [
    for (final (i, (points, _)) in grades.indexed)
      Criterion(
        text: 'criterion $i',
        points: points,
        tags: const ['axis:accuracy'],
      ),
  ];
  return GradedConversation(
    conversation: Conversation(
      index: index,
      promptId: 'p$index',
      prompt: const [Message(role: 'user', content: 'Q')],
      criteria: criteria,
      exampleTags: const ['theme:global_health'],
    ),
    completion: 'A',
    grades: [
      for (final (i, (_, met)) in grades.indexed)
        Grade(criterion: criteria[i], criteriaMet: met, explanation: 'why $i'),
    ],
    gradedAt: DateTime.parse('2026-10-17T16:31:00-05:00'),
  );
}

StatusEntry status(RunStatus s, int graded, {double? score, String? reason}) =>
    StatusEntry(
      status: s,
      at: DateTime.parse('2026-10-17T16:32:00-05:00'),
      graded: graded,
      score: score,
      reason: reason,
    );

/// A valid completed run: 2 conversations scoring 1.0 and 0.5 → 0.75.
List<Map<String, Object?>> validLines() => [
  headerJson(header()),
  statusJson(status(RunStatus.running, 0)),
  conversationJson(graded(0, [(5, true), (-2, false)])),
  conversationJson(graded(1, [(4, true), (4, false)])),
  statusJson(status(RunStatus.completed, 2, score: 0.75)),
];

void main() {
  late Directory dir;
  setUp(() => dir = tempDir(addTearDown));

  String write(
    List<Object> lines, {
    String name = '$_runId.jsonl',
    String tail = '',
  }) {
    final file = File('${dir.path}/$name')
      ..writeAsStringSync(
        '${lines.map((l) => l is String ? l : jsonEncode(l)).join('\n')}\n$tail',
      );
    return file.path;
  }

  Matcher rejected(String reasonPart, {int? line}) => throwsA(
    isA<RunFileFormatException>()
        .having((e) => e.reason, 'reason', contains(reasonPart))
        .having((e) => e.line, 'line', line),
  );

  group('file name', () {
    test('pattern and run id', () {
      expect(isRunFileName('healthbench-run-20261017-163000.jsonl'), isTrue);
      expect(isRunFileName('healthbench-run-20261017-163000-2.jsonl'), isTrue);
      expect(isRunFileName('healthbench-run-20261017-163000-0.jsonl'), isFalse);
      expect(isRunFileName('healthbench-run-2026101-163000.jsonl'), isFalse);
      expect(isRunFileName('results.jsonl'), isFalse);
      expect(
        runIdForTime(DateTime(2026, 1, 2, 3, 4, 5)),
        'healthbench-run-20260102-030405',
      );
    });

    test('timestamps carry the UTC offset and round-trip', () {
      final now = DateTime.now();
      final text = formatTimestamp(now);
      expect(
        text,
        matches(
          RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}[+-]\d\d:\d\d$'),
        ),
      );
      expect(
        DateTime.parse(text).millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
      );
    });
  });

  group('reading a valid file', () {
    test('header, conversations, status, recomputed scores', () async {
      final contents = await readRunFile(write(validLines()));
      expect(contents.header.runId, _runId);
      expect(contents.header.modelTest.reasoningEffort, ReasoningEffort.low);
      expect(contents.header.dataset.limit, 2);
      expect(contents.conversations, hasLength(2));
      expect(contents.conversations.first.grades.first.explanation, 'why 0');
      expect(contents.conversations.first.conversation.exampleTags, [
        'theme:global_health',
      ]);
      expect(contents.status, RunStatus.completed);
      expect(contents.score, closeTo(0.75, 1e-12));
      expect(contents.doneIds, {'p0', 'p1'});
      expect(
        conversationScore(contents.conversations[1].grades),
        closeTo(0.5, 1e-12),
      );
    });

    test(
      'last status "running" of an inactive run reads as interrupted',
      () async {
        final lines = validLines()..removeLast();
        final contents = await readRunFile(write(lines));
        expect(contents.status, RunStatus.interrupted);
      },
    );

    test('a failed run exposes its reason', () async {
      final lines = validLines()
        ..removeLast()
        ..add(
          statusJson(
            status(RunStatus.failed, 2, reason: 'Authentication failed'),
          ),
        );
      final contents = await readRunFile(write(lines));
      expect(contents.status, RunStatus.failed);
      expect(contents.failureReason, 'Authentication failed');
    });

    test('RF-9: an incomplete last line is ignored', () async {
      final path = write(validLines()..removeLast(), tail: '{"type":"conversa');
      final contents = await readRunFile(path);
      expect(contents.conversations, hasLength(2));
      expect(contents.hasIncompleteTail, isTrue);
    });
  });

  group('rejected files', () {
    test('RF-1 file name and run id', () async {
      await expectLater(
        readRunFile(write(validLines(), name: 'run.jsonl')),
        rejected('file name'),
      );
      await expectLater(
        readRunFile(
          write(validLines(), name: 'healthbench-run-20261017-163000-2.jsonl'),
        ),
        rejected('runId', line: 1),
      );
    });

    test('RF-2 header first and only once', () async {
      final lines = validLines();
      await expectLater(
        readRunFile(write(lines.sublist(1))),
        rejected('header', line: 1),
      );
      await expectLater(
        readRunFile(write([...lines, headerJson(header())])),
        rejected('header', line: 6),
      );
      await expectLater(
        readRunFile(write(const <Object>[])),
        rejected('header'),
      );
    });

    test('RF-3 unknown type, missing or extra fields, wrong types', () async {
      Future<void> tamper(
        int index,
        void Function(Map<String, Object?>) change,
        String reason,
      ) async {
        final lines = validLines();
        change(lines[index]);
        await expectLater(
          readRunFile(write(lines)),
          rejected(reason, line: index + 1),
        );
      }

      await tamper(2, (l) => l['type'] = 'note', 'type');
      await tamper(2, (l) => l.remove('completion'), 'completion');
      await tamper(2, (l) => l['extra'] = 1, 'extra');
      await tamper(2, (l) => l['index'] = '0', 'index');
      await tamper(
        2,
        (l) =>
            ((l['rubrics']! as List<Object?>).first!
                    as Map<String, Object?>)['criteriaMet'] =
                'yes',
        'criteriaMet',
      );
      await tamper(
        0,
        (l) => (l['modelTest']! as Map<String, Object?>)['apiKey'] = 'x',
        'apiKey',
      );
      await expectLater(
        readRunFile(
          write([...validLines().take(2), 'not json', ...validLines().skip(2)]),
        ),
        rejected('JSON', line: 3),
      );
    });

    test('RF-4 values', () async {
      Future<void> tamper(
        void Function(Map<String, Object?>) change,
        String reason,
      ) async {
        final lines = validLines();
        change(lines[0]);
        await expectLater(readRunFile(write(lines)), rejected(reason, line: 1));
      }

      await tamper(
        (h) => (h['modelGrader']! as Map<String, Object?>)['reasoningEffort'] =
            'max',
        'reasoningEffort',
      );
      await tamper(
        (h) => (h['dataset']! as Map<String, Object?>)['sha256'] = 'xyz',
        'sha256',
      );
      await tamper((h) => h['createdAt'] = 'yesterday', 'createdAt');
    });

    test('RF-5 status rules', () async {
      final noStatus = validLines()..removeWhere((l) => l['type'] == 'status');
      await expectLater(readRunFile(write(noStatus)), rejected('status'));

      final failedNoReason = validLines()
        ..removeLast()
        ..add(statusJson(status(RunStatus.failed, 2)));
      await expectLater(
        readRunFile(write(failedNoReason)),
        rejected('reason', line: 5),
      );

      final completedNoScore = validLines()
        ..removeLast()
        ..add(statusJson(status(RunStatus.completed, 2)));
      await expectLater(
        readRunFile(write(completedNoScore)),
        rejected('score', line: 5),
      );
    });

    test('RF-6 unique ids and indexes within range', () async {
      final duplicate = validLines()
        ..insert(3, conversationJson(graded(0, [(1, true)])));
      await expectLater(
        readRunFile(write(duplicate)),
        rejected('duplicate', line: 4),
      );

      final outOfRange = validLines()
        ..[3] = conversationJson(graded(4, [(1, true)]));
      await expectLater(
        readRunFile(write(outOfRange)),
        rejected('index', line: 4),
      );
    });

    test('RF-7 counts and score must match the content', () async {
      final wrongCount = validLines()
        ..removeLast()
        ..add(statusJson(status(RunStatus.completed, 3, score: 0.75)));
      await expectLater(
        readRunFile(write(wrongCount)),
        rejected('graded', line: 5),
      );

      final wrongScore = validLines()
        ..removeLast()
        ..add(statusJson(status(RunStatus.completed, 2, score: 0.9)));
      await expectLater(
        readRunFile(write(wrongScore)),
        rejected('score', line: 5),
      );
    });

    test(
      'blank model name and empty prompt are rejected (code review #2, #3)',
      () async {
        final blank = validLines();
        (blank[0]['modelTest']! as Map<String, Object?>)['name'] = '   ';
        await expectLater(readRunFile(write(blank)), rejected('name', line: 1));

        final noPrompt = validLines();
        noPrompt[2]['prompt'] = <Object?>[];
        await expectLater(
          readRunFile(write(noPrompt)),
          rejected('prompt', line: 3),
        );
      },
    );

    test('RF-8 base URL', () async {
      final lines = validLines();
      lines[0]['baseUrl'] = 'https://user:pw@api.example.com/v1';
      await expectLater(
        readRunFile(write(lines)),
        rejected('baseUrl', line: 1),
      );
    });

    test('RF-9 an invalid line before the end is not tolerated', () async {
      final lines = <Object>[...validLines()];
      lines.insert(2, '{"type":"conversa');
      await expectLater(readRunFile(write(lines)), rejected('JSON', line: 3));
    });
  });

  group('writer', () {
    test('creates a timestamped file, never reusing a name', () async {
      final time = DateTime(2026, 10, 17, 16, 30);
      final first = await RunFileWriter.createNew(dir.path, time);
      final second = await RunFileWriter.createNew(dir.path, time);
      expect(fileNameOf(first.path), 'healthbench-run-20261017-163000.jsonl');
      expect(
        fileNameOf(second.path),
        'healthbench-run-20261017-163000-2.jsonl',
      );
      expect(first.runId, 'healthbench-run-20261017-163000');
      await first.close();
      await second.close();
    });

    test(
      'appends one line per write; reopen repairs an incomplete tail',
      () async {
        final path = write(validLines().sublist(0, 3), tail: '{"type":"conv');
        final before = await readRunFile(path);
        final writer = await RunFileWriter.reopen(before);
        await writer.write(
          conversationJson(graded(1, [(4, true), (4, false)])),
        );
        await writer.write(
          statusJson(status(RunStatus.completed, 2, score: 0.75)),
        );
        await writer.close();

        final text = File(path).readAsStringSync();
        expect(text, isNot(contains('{"type":"conv\n')));
        expect(text.endsWith('\n'), isTrue);
        final after = await readRunFile(path);
        expect(after.status, RunStatus.completed);
        expect(after.conversations, hasLength(2));
        expect(after.hasIncompleteTail, isFalse);
      },
    );

    test(
      'reopen adds the missing newline after a complete last line',
      () async {
        final lines = validLines().sublist(0, 3);
        final path = '${dir.path}/$_runId.jsonl';
        File(path).writeAsStringSync(lines.map(jsonEncode).join('\n'));
        final writer = await RunFileWriter.reopen(await readRunFile(path));
        await writer.write(statusJson(status(RunStatus.stopped, 1)));
        await writer.close();
        expect((await readRunFile(path)).status, RunStatus.stopped);
      },
    );
  });
}
