/// The grader prompt of the reference toolkit (GRADER.md) and how it is filled
/// (spec 002 FR-009, research R3).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'dataset.dart';

/// Recorded in each run file so results can be traced to this prompt.
const String graderPromptId = 'pygrader-GRADER.md';

/// GRADER.md from the reference toolkit, character for character. The
/// reference doubles the JSON braces only because Python's str.format needs
/// it; the filled result is identical.
const String graderPromptTemplate =
    'You will evaluate a response to a health-related conversation against a '
    'single grading criterion.\n'
    '\n'
    'Conversation:\n'
    '---\n'
    '\n'
    '{prompt}\n'
    '\n'
    '---\n'
    '\n'
    'Final Response to evaluate:\n'
    '{completion}\n'
    '\n'
    'Criterion:\n'
    '{criterion}\n'
    '\n'
    'Note: sometimes the criterion may describe something undesirable and have a\n'
    'negative point value. In this case, you should still return whether the\n'
    'criterion is met — not whether the response is "good." For example, if the\n'
    'criterion is "fails to give accurate information" and the response is\n'
    'accurate, the criterion is NOT met (return false), because the undesirable\n'
    'behavior did not occur.\n'
    '\n'
    'Return your answer as JSON:\n'
    '\n'
    '{\n'
    '  "explanation": "...",\n'
    '  "criteria_met": true | false\n'
    '}';

/// SHA-256 of [graderPromptTemplate], recorded in run files.
final String graderPromptSha256 = sha256
    .convert(utf8.encode(graderPromptTemplate))
    .toString();

final RegExp _placeholder = RegExp(r'\{(prompt|completion|criterion)\}');

/// Fills the template in a single pass, so placeholder-like text inside the
/// conversation or the reply is never substituted again.
String fillGraderPrompt({
  required String prompt,
  required String completion,
  required String criterion,
}) {
  final values = {
    'prompt': prompt,
    'completion': completion,
    'criterion': criterion,
  };
  return graderPromptTemplate.replaceAllMapped(
    _placeholder,
    (match) => values[match.group(1)]!,
  );
}

/// The conversation as the grader sees it: "role\ncontent" per message,
/// separated by a blank line (as pygrader grade_prompt).
String conversationText(List<Message> messages) =>
    messages.map((m) => '${m.role}\n${m.content}').join('\n\n');
