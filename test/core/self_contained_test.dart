// Spec 002 FR-018 (amended) / research R19: a run file is a complete,
// self-contained copy of every graded dataset record, so results can be
// viewed and analysed without the dataset.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/run_file.dart';
import 'package:healthbench/core/runner.dart';
import 'package:healthbench/core/settings.dart';

import '../support/fake_openai_server.dart';
import '../support/fixtures.dart';

void main() {
  test(
    'every dataset field of every graded conversation is in the run file',
    () async {
      final dir = tempDir(addTearDown);
      final ideal = {
        'ideal_completion': 'Call emergency services now.',
        'ideal_completions_group': 'Group A',
        'ideal_completions_ref_completions': ['ref one', 'ref two'],
      };
      // Varied records: multi-turn prompt, criteria given as text, negative
      // points, tags, ideal data present or null, canary.
      final records = [
        {
          ...datasetRecord(
            'with-ideal',
            prompt: [
              {'role': 'user', 'content': 'Question for with-ideal'},
              {'role': 'assistant', 'content': 'Since when?'},
              {'role': 'user', 'content': 'Two hours'},
            ],
            rubrics: [
              criterionJson('Advises urgent care', 9, [
                'axis:accuracy',
                'level:example',
              ]),
              jsonEncode(
                criterionJson('Mentions heart attack', 3, [
                  'axis:completeness',
                ]),
              ),
              criterionJson('Gives a diagnosis', -6, ['axis:accuracy']),
            ],
            exampleTags: [
              'theme:emergency_referrals',
              'physician_agreed_category:emergent',
            ],
          ),
          'ideal_completions_data': ideal,
          'canary': 'canary-guid-1',
        },
        {
          ...datasetRecord('no-ideal', exampleTags: null),
          'ideal_completions_data': null,
          'canary': 'canary-guid-2',
        },
      ];
      final datasetPath = '${dir.path}/data.jsonl';
      File(datasetPath).writeAsStringSync(datasetText(records));

      final server = await FakeOpenAiServer.start(
        (r, _) => r.isGraderCall
            ? FakeResponse.grade(met: true, explanation: 'grader says')
            : FakeResponse.reply('model reply'),
      );
      addTearDown(server.close);
      final run = await EvaluationRun.start(
        runsDirectory: '${dir.path}/runs',
        datasetPath: datasetPath,
        connection: ConnectionSettings(
          baseUrl: server.baseUrl.toString(),
          apiKey: 'k',
        ),
        modelTest: ModelSettings(name: 'm'),
        modelGrader: ModelSettings(name: 'g'),
        options: const ClientOptions(maxRetries: 0),
      );
      expect((await run.finished).done, 2);

      final lines = [
        for (final l in File(run.runFilePath!).readAsLinesSync())
          jsonDecode(l) as Map<String, Object?>,
      ];
      final conversations = {
        for (final l in lines)
          if (l['type'] == 'conversation') l['promptId']: l,
      };
      expect(conversations.keys, unorderedEquals(['with-ideal', 'no-ideal']));

      for (final record in records) {
        final line = conversations[record['prompt_id']]!;
        expect(line['prompt'], record['prompt'], reason: 'messages');
        expect(
          line['exampleTags'],
          record['example_tags'] ?? <String>[],
          reason: 'example tags',
        );
        expect(
          line['idealCompletionsData'],
          record['ideal_completions_data'],
          reason: 'ideal completions',
        );
        expect(line['canary'], record['canary'], reason: 'canary');

        final criteria = [
          for (final r in record['rubrics']! as List<Object?>)
            (r is String ? jsonDecode(r) : r)! as Map<String, Object?>,
        ];
        final rubrics = (line['rubrics']! as List<Object?>)
            .cast<Map<String, Object?>>();
        expect(
          rubrics,
          hasLength(criteria.length),
          reason: 'one entry per criterion',
        );
        for (final (i, criterion) in criteria.indexed) {
          expect(rubrics[i]['criterion'], criterion['criterion']);
          expect(rubrics[i]['points'], criterion['points']);
          expect(rubrics[i]['tags'], criterion['tags']);
          expect(rubrics[i]['criteriaMet'], isTrue);
          expect(rubrics[i]['explanation'], 'grader says');
        }
      }

      // Reading the file back exposes the same data, without the dataset.
      final contents = await readRunFile(run.runFilePath!);
      final withIdeal = contents.conversations.firstWhere(
        (c) => c.conversation.promptId == 'with-ideal',
      );
      expect(withIdeal.conversation.idealCompletionsData, ideal);
      expect(withIdeal.conversation.canary, 'canary-guid-1');
      expect(withIdeal.conversation.criteria.map((c) => c.points), [9, 3, -6]);
    },
  );

  test(
    'a run file written before the amendment still reads (fields as null)',
    () async {
      final dir = tempDir(addTearDown);
      const runId = 'healthbench-run-20261017-090000';
      final header = {
        'type': 'header',
        'runId': runId,
        'app': 'HealthBench Evals',
        'appVersion': '0.1.0', //
        'createdAt': '2026-10-17T09:00:00.000-04:00',
        'baseUrl': 'https://x.y/v1',
        'modelTest': {'name': 'm', 'reasoningEffort': 'low'},
        'modelGrader': {'name': 'g', 'reasoningEffort': 'low'},
        'temperature': 0.3,
        'graderPrompt': {'id': 'pygrader-GRADER.md', 'sha256': 'a' * 64},
        'dataset': {
          'fileName': 'd.jsonl',
          'sha256': 'b' * 64,
          'conversationCount': 1,
          'limit': null,
        },
      };
      final old = {
        'type': 'conversation',
        'index': 0,
        'promptId': 'p0',
        'exampleTags': <String>[], //
        'prompt': [
          {'role': 'user', 'content': 'q'},
        ],
        'completion': 'a',
        'rubrics': [
          {
            'criterion': 'c',
            'points': 1,
            'tags': <String>[],
            'criteriaMet': true,
            'explanation': 'e',
          },
        ],
        'gradedAt': '2026-10-17T09:01:00.000-04:00',
      };
      final path = '${dir.path}/$runId.jsonl';
      File(path).writeAsStringSync(
        [
          jsonEncode(header),
          jsonEncode({
            'type': 'status',
            'status': 'running',
            'at': '2026-10-17T09:00:00.000-04:00',
            'graded': 0,
            'score': null,
            'reason': null,
          }),
          jsonEncode(old),
        ].map((l) => '$l\n').join(),
      );

      final contents = await readRunFile(path);
      expect(
        contents.conversations.single.conversation.idealCompletionsData,
        isNull,
      );
      expect(contents.conversations.single.conversation.canary, isNull);
    },
  );
}
