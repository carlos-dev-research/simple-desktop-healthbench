// Builds valid run files for UI tests, using the core's own encoders.
import 'dart:convert';
import 'dart:io';

import 'package:healthbench/core/dataset.dart';
import 'package:healthbench/core/grader_prompt.dart';
import 'package:healthbench/core/grading.dart';
import 'package:healthbench/core/run_file.dart';
import 'package:healthbench/core/scoring.dart';
import 'package:healthbench/core/settings.dart';

/// A graded conversation whose criteria have the given (points, met) pairs.
GradedConversation gradedConversation(
  int index,
  List<(int, bool)> grades, {
  String question = 'What should I do?',
  String reply = 'Please see a doctor.',
}) {
  final criteria = [
    for (final (i, (points, _)) in grades.indexed)
      Criterion(
        text: 'Criterion ${index + 1}.${i + 1}',
        points: points,
        tags: const ['axis:accuracy'],
      ),
  ];
  return GradedConversation(
    conversation: Conversation(
      index: index,
      promptId: 'p$index',
      prompt: [Message(role: 'user', content: question)],
      criteria: criteria,
      exampleTags: const ['theme:emergency_referrals'],
    ),
    completion: reply,
    grades: [
      for (final (i, (_, met)) in grades.indexed)
        Grade(
          criterion: criteria[i],
          criteriaMet: met,
          explanation: 'Explanation ${index + 1}.${i + 1}',
        ),
    ],
    gradedAt: DateTime(2026, 10, 17, 16, 31),
  );
}

/// Writes `<runsDir>/<runId>.jsonl` and returns its path.
String writeRunFile(
  String runsDir, {
  required String runId,
  required List<GradedConversation> conversations,
  required RunStatus finalStatus,
  int selected = 3,
  String model = 'tested-model',
  String? reason,
}) {
  Directory(runsDir).createSync(recursive: true);
  final score = runScore(conversations.map((c) => conversationScore(c.grades)));
  final at = DateTime(2026, 10, 17, 16, 30);
  final lines = [
    headerJson(
      RunHeader(
        runId: runId,
        app: 'HealthBench Evals',
        appVersion: '0.1.0',
        createdAt: at,
        baseUrl: Uri.parse('https://api.example.com/v1'),
        modelTest: ModelSettings(
          name: model,
          reasoningEffort: ReasoningEffort.low,
        ),
        modelGrader: ModelSettings(name: 'grader-model'),
        temperature: 0.3,
        graderPromptId: graderPromptId,
        graderPromptSha256: graderPromptSha256,
        dataset: DatasetRef(
          fileName: 'data.jsonl',
          sha256: 'a' * 64,
          conversationCount: selected,
          limit: null,
        ),
      ),
    ),
    statusJson(StatusEntry(status: RunStatus.running, at: at, graded: 0)),
    for (final c in conversations) conversationJson(c),
    if (finalStatus != RunStatus.running)
      statusJson(
        StatusEntry(
          status: finalStatus,
          at: at,
          graded: conversations.length,
          score: conversations.isEmpty ? null : score,
          reason: reason,
        ),
      ),
  ];
  final path = '$runsDir${Platform.pathSeparator}$runId.jsonl';
  File(path).writeAsStringSync('${lines.map(jsonEncode).join('\n')}\n');
  return path;
}
