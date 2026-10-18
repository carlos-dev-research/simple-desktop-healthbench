// Numbers shown by the results views (spec 003 FR-011, FR-012; reference
// webview app.js renderStats / renderHistogram / matches).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/dataset.dart';
import 'package:healthbench/core/grading.dart';
import 'package:healthbench/core/run_file.dart';
import 'package:healthbench/core/run_summary.dart';
import 'package:healthbench/core/settings.dart';

GradedConversation conv(
  int index,
  List<(int, bool)> grades, {
  String user = 'question',
  String completion = 'answer',
}) {
  final criteria = [
    for (final (i, (p, _)) in grades.indexed)
      Criterion(text: 'criterion $index.$i', points: p, tags: const []),
  ];
  return GradedConversation(
    conversation: Conversation(
      index: index,
      promptId: 'p$index',
      prompt: [
        const Message(role: 'user', content: 'first'),
        const Message(role: 'assistant', content: 'reply'),
        Message(role: 'user', content: user),
      ],
      criteria: criteria,
      exampleTags: const [],
    ),
    completion: completion,
    grades: [
      for (final (i, (_, met)) in grades.indexed)
        Grade(
          criterion: criteria[i],
          criteriaMet: met,
          explanation: 'because $index.$i',
        ),
    ],
    gradedAt: DateTime(2026),
  );
}

RunFileContents contents(
  List<GradedConversation> conversations, {
  int? limit,
}) => RunFileContents(
  path: '/runs/healthbench-run-20261017-163000.jsonl',
  header: RunHeader(
    runId: 'healthbench-run-20261017-163000',
    app: 'HealthBench Evals',
    appVersion: '0.1.0',
    createdAt: DateTime(2026, 10, 17),
    baseUrl: Uri.parse('https://x.y/v1'),
    modelTest: ModelSettings(name: 'm'),
    modelGrader: ModelSettings(name: 'g'),
    temperature: 0.3,
    graderPromptId: 'id',
    graderPromptSha256: 'a' * 64,
    dataset: DatasetRef(
      fileName: 'data.jsonl',
      sha256: 'b' * 64,
      conversationCount: 10,
      limit: limit,
    ),
  ),
  conversations: conversations,
  statusEntries: const [],
  status: RunStatus.stopped,
  score: 0,
  hasIncompleteTail: false,
  needsNewline: false,
  validLength: 0,
);

void main() {
  final rows = [
    conv(0, [
      (5, true),
      (5, false),
      (-3, true),
    ], user: 'chest pain'), // 2/10 = 0.2
    conv(1, [
      (4, true),
      (-2, false),
    ], completion: 'Call EMERGENCY services'), // 1.0
    conv(2, [(0, true), (-1, false)]), // no positive points → no score
    conv(3, [(2, false), (-6, true)]), // -6/2 = -3.0
  ];
  final summary = RunSummary.of(contents(rows, limit: 6));

  test('criteria, positive met and penalties triggered', () {
    expect(summary.conversationCount, 4);
    expect(summary.criteriaCount, 9);
    expect(summary.positiveCount, 4); // 5, 5, 4, 2
    expect(summary.positiveMet, 2);
    expect(summary.negativeCount, 4); // -3, -2, -1, -6
    expect(summary.negativeMet, 2);
  });

  test('per-conversation earned/possible and score', () {
    expect(summary.rows[0].earned, 2);
    expect(summary.rows[0].possible, 10);
    expect(summary.rows[0].score, closeTo(0.2, 1e-12));
    expect(summary.rows[2].score, isNull);
    expect(summary.rows[3].score, closeTo(-3.0, 1e-12));
    expect(summary.rows[0].preview, 'chest pain'); // last user message
  });

  test('histogram: <0, ten bins of 0.1, 1.0 in the last bin', () {
    expect(histogramLabels, [
      '<0',
      '0.0',
      '0.1',
      '0.2',
      '0.3',
      '0.4',
      '0.5',
      '0.6',
      '0.7',
      '0.8',
      '0.9',
    ]);
    expect(histogramBins([-0.5, 0.0, 0.05, 0.1, 0.99, 1.0, null]), [
      1,
      2,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      2,
    ]);
    expect(summary.histogram, [1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1]);
  });

  test('median, standard deviation and bootstrap std of the scores (006)', () {
    // Scored conversations: 0.2, 1.0, -3.0 (the one without a score is left out).
    expect(summary.medianScore, closeTo(0.2, 1e-12));
    // mean -0.6; squared deviations 0.64 + 2.56 + 5.76 = 8.96; / (3 - 1)
    expect(summary.scoreStdDev, closeTo(math.sqrt(4.48), 1e-12));
    expect(summary.bootstrapStd, isNotNull);
    expect(
      summary.bootstrapStd,
      RunSummary.of(contents(rows, limit: 6)).bootstrapStd,
    );
    final single = RunSummary.of(contents([rows[0]], limit: 1));
    expect(single.scoreStdDev, isNull);
    expect(single.bootstrapStd, isNull);
  });

  test('selected, missing and whether it can be continued', () {
    expect(summary.selectedCount, 6);
    expect(summary.missingCount, 2);
    expect(summary.canContinue, isTrue);
    final full = RunSummary.of(contents([rows[0]], limit: 1));
    expect(full.canContinue, isFalse);
  });

  test(
    'search ignores case and looks in messages, reply, criteria, explanations',
    () {
      List<int> find(String q) => [
        for (final r in filterRows(summary.rows, q, ConversationSort.original))
          r.index,
      ];
      expect(find(''), [0, 1, 2, 3]);
      expect(find('CHEST'), [0]);
      expect(find('emergency'), [1]);
      expect(find('criterion 2.1'), [2]);
      expect(find('because 3.0'), [3]);
      expect(find('nothing like this'), isEmpty);
    },
  );

  test('sort by score; conversations without a score go last', () {
    List<int> sorted(ConversationSort s) => [
      for (final r in filterRows(summary.rows, '', s)) r.index,
    ];
    expect(sorted(ConversationSort.original), [0, 1, 2, 3]);
    expect(sorted(ConversationSort.lowestFirst), [3, 0, 1, 2]);
    expect(sorted(ConversationSort.highestFirst), [1, 0, 3, 2]);
  });
}
