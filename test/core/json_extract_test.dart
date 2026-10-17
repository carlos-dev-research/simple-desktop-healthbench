// US3: reading the grader's answer exactly like pygrader's get_result
// (spec 002 FR-006, research R4).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/grading.dart';

void main() {
  final cases = jsonDecode(
    File('test/fixtures/json_extract_golden.json').readAsStringSync(),
  ) as List<Object?>;

  for (final (i, c) in cases.cast<Map<String, Object?>>().indexed) {
    final input = c['input']! as String;
    final expected = c['result'];
    test('golden case $i matches the reference', () {
      if (expected == null) {
        expect(
          () => extractFirstJsonObject(input),
          throwsA(isA<GraderAnswerException>()),
        );
      } else {
        expect(extractFirstJsonObject(input), expected);
      }
    });
  }

  test('raw control characters inside strings are accepted (strict=False)', () {
    expect(extractFirstJsonObject('{"explanation": "a\tb\nc", "x": 1}'), {
      'explanation': 'a\tb\nc',
      'x': 1,
    });
  });
}
