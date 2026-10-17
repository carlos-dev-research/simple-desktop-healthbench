/// Generating and grading one conversation (port of pygrader grader.py and
/// tools.get_result; spec 002 US3, research R3–R5).
library;

import 'dart:convert';

import 'chat_client.dart';
import 'dataset.dart';
import 'grader_prompt.dart';
import 'settings.dart';

/// Structured answer requested from the grader (as pygrader grade_prompt).
const Map<String, Object?> graderResponseFormat = {
  'type': 'json_schema',
  'json_schema': {
    'name': 'grading_result',
    'schema': {
      'type': 'object',
      'properties': {
        'explanation': {'type': 'string'},
        'criteria_met': {'type': 'boolean'},
      },
      'required': ['explanation', 'criteria_met'],
      'additionalProperties': false,
    },
  },
};

/// Generates the next reply with [modelTest], then asks [modelGrader] once per
/// criterion whether the reply meets it (port of pygrader grade/grade_prompt).
///
/// [onCriterion] is called with (0, total) once the reply exists and after
/// each graded criterion. Throws [ChatError] or [GraderAnswerException].
Future<GradedConversation> evaluateConversation(
  Conversation conversation, {
  required ChatClient client,
  required ModelSettings modelTest,
  required ModelSettings modelGrader,
  void Function(int done, int total)? onCriterion,
}) async {
  final completion = await client.complete(
    model: modelTest,
    messages: [for (final m in conversation.prompt) m.toJson()],
  );
  final total = conversation.criteria.length;
  onCriterion?.call(0, total);

  final prompt = conversationText(conversation.prompt);
  final grades = <Grade>[];
  for (final criterion in conversation.criteria) {
    final answer = await client.complete(
      model: modelGrader,
      messages: [
        {
          'role': 'user',
          'content': fillGraderPrompt(
            prompt: prompt,
            completion: completion,
            criterion: criterion.text,
          ),
        },
      ],
      responseFormat: graderResponseFormat,
    );
    grades.add(parseGraderAnswer(answer, criterion));
    onCriterion?.call(grades.length, total);
  }
  return GradedConversation(
    conversation: conversation,
    completion: completion,
    grades: grades,
    gradedAt: DateTime.now(),
  );
}

/// The grader's decision on one criterion.
class Grade {
  const Grade({
    required this.criterion,
    required this.criteriaMet,
    required this.explanation,
  });

  final Criterion criterion;
  final bool criteriaMet;
  final String explanation;
}

/// A conversation with the reply of the model under test and one grade per
/// criterion (same order as [Conversation.criteria]).
class GradedConversation {
  const GradedConversation({
    required this.conversation,
    required this.completion,
    required this.grades,
    required this.gradedAt,
  });

  final Conversation conversation;
  final String completion;
  final List<Grade> grades;
  final DateTime gradedAt;
}

/// The grader's answer could not be used.
class GraderAnswerException implements Exception {
  const GraderAnswerException(this.message);

  final String message;

  @override
  String toString() => 'GraderAnswerException: $message';
}

/// The first balanced `{…}` in [text] that parses as a JSON object, found
/// exactly like the reference's get_result: braces are counted without
/// regard to string literals, and a candidate that doesn't parse resets the
/// scan. Raw control characters inside strings are accepted, as Python's
/// `json.loads(strict=False)` does.
Map<String, Object?> extractFirstJsonObject(String text) {
  var found = false;
  var depth = 0;
  var start = -1;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == '{') {
      if (!found) start = i;
      found = true;
      depth++;
    } else if (char == '}') {
      depth--;
    }
    if (found && depth == 0) {
      final candidate = _decodeLenient(text.substring(start, i + 1));
      if (candidate is Map<String, Object?>) return candidate;
      found = false;
    }
  }
  throw const GraderAnswerException('no valid JSON object in grader answer');
}

Object? _decodeLenient(String candidate) {
  try {
    return jsonDecode(candidate);
  } on FormatException {
    try {
      return jsonDecode(_escapeControlCharsInStrings(candidate));
    } on FormatException {
      return null;
    }
  }
}

/// Escapes raw control characters that appear inside JSON string literals.
String _escapeControlCharsInStrings(String json) {
  final out = StringBuffer();
  var inString = false;
  var escaped = false;
  for (final unit in json.codeUnits) {
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (unit == 0x5C) {
        escaped = true;
      } else if (unit == 0x22) {
        inString = false;
      } else if (unit < 0x20) {
        out.write(switch (unit) {
          0x0A => r'\n',
          0x0D => r'\r',
          0x09 => r'\t',
          _ => '\\u${unit.toRadixString(16).padLeft(4, '0')}',
        });
        continue;
      }
    } else if (unit == 0x22) {
      inString = true;
    }
    out.writeCharCode(unit);
  }
  return out.toString();
}

/// Turns the grader's raw answer into a [Grade] for [criterion].
///
/// `criteria_met` must be a JSON boolean or the string "true"/"false" (any
/// case; research R4). A missing explanation becomes an empty string.
Grade parseGraderAnswer(String answer, Criterion criterion) {
  final json = extractFirstJsonObject(answer);
  final met = switch (json['criteria_met']) {
    final bool value => value,
    final String value when value.toLowerCase() == 'true' => true,
    final String value when value.toLowerCase() == 'false' => false,
    _ => throw const GraderAnswerException(
      'grader answer has no valid criteria_met',
    ),
  };
  final explanation = switch (json['explanation']) {
    null => '',
    final String value => value,
    final Object value => jsonEncode(value),
  };
  return Grade(
    criterion: criterion,
    criteriaMet: met,
    explanation: explanation,
  );
}
