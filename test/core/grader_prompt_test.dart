// US3: the reference GRADER.md prompt, filled exactly like pygrader
// (spec 002 FR-009, research R3).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/dataset.dart';
import 'package:healthbench/core/grader_prompt.dart';

void main() {
  final golden = jsonDecode(
    File('test/fixtures/grader_prompt_golden.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final messages = [
    for (final m
        in (golden['prompt']! as List<Object?>).cast<Map<String, Object?>>())
      Message(role: m['role']! as String, content: m['content']! as String),
  ];

  test('filled prompt is byte-identical to the reference toolkit', () {
    final filled = fillGraderPrompt(
      prompt: conversationText(messages),
      completion: golden['completion']! as String,
      criterion: golden['criterion']! as String,
    );
    expect(filled, golden['expected']);
  });

  test('placeholders inside model output are not substituted again', () {
    final filled = fillGraderPrompt(
      prompt: 'user\nsays {completion}',
      completion: 'reply mentions {criterion}',
      criterion: 'the criterion',
    );
    expect(filled, contains('user\nsays {completion}'));
    expect(filled, contains('reply mentions {criterion}'));
    expect(filled, contains('Criterion:\nthe criterion'));
  });

  test('conversation text joins "role\\ncontent" with blank lines', () {
    expect(
      conversationText(const [
        Message(role: 'user', content: 'a'),
        Message(role: 'assistant', content: 'b'),
      ]),
      'user\na\n\nassistant\nb',
    );
  });

  test('prompt id and a stable SHA-256 of the template', () {
    expect(graderPromptId, 'pygrader-GRADER.md');
    expect(graderPromptSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    // GRADER.md is 681 characters; its two doubled braces {{ }} become single.
    expect(graderPromptTemplate.length, 679);
  });
}
