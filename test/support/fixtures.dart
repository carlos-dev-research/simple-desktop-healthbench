// Builders for HealthBench dataset lines and files used across core tests.
import 'dart:convert';
import 'dart:io';

/// One dataset record in the HealthBench file format (healthbench.md §2).
Map<String, Object?> datasetRecord(
  String promptId, {
  List<Map<String, Object?>>? prompt,
  List<Object?>? rubrics,
  List<String>? exampleTags = const ['theme:emergency_referrals'],
}) => {
  'prompt_id': promptId,
  'prompt':
      prompt ??
      [
        {'role': 'user', 'content': 'Question for $promptId'},
      ],
  'rubrics':
      rubrics ??
      [
        criterionJson('Gives the right advice', 5, ['axis:accuracy']),
        criterionJson('Is dangerous', -3, ['axis:accuracy']),
      ],
  'example_tags': exampleTags,
  'ideal_completions_data': null,
  'canary': 'canary-string',
};

Map<String, Object?> criterionJson(
  String text,
  int points, [
  List<String> tags = const [],
]) => {'criterion': text, 'points': points, 'tags': tags};

/// Dataset file text: one JSON record per line.
String datasetText(List<Map<String, Object?>> records) =>
    '${records.map(jsonEncode).join('\n')}\n';

/// Writes [count] simple conversations (`p0`, `p1`, …) to [path].
File writeDataset(String path, int count) {
  final file = File(path)
    ..writeAsStringSync(
      datasetText([for (var i = 0; i < count; i++) datasetRecord('p$i')]),
    );
  return file;
}

/// A fresh temporary directory, deleted when the test ends.
Directory tempDir(void Function(void Function()) addTearDown) {
  final dir = Directory.systemTemp.createTempSync('healthbench_test_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}
