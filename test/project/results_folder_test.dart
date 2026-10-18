// Constitution XII.2 (1.2.0): results/ holds only valid run files (plus its
// README), each small enough for GitHub.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/dataset.dart' show fileNameOf;
import 'package:healthbench/core/run_file.dart';

/// GitHub rejects files over 100 MB; stay clearly below.
const _maxBytes = 95 * 1024 * 1024;

void main() {
  final dir = Directory('results');

  test('results/ exists with its README', () {
    expect(File('results/README.md').existsSync(), isTrue);
  });

  test('results/ contains only run files and its README', () {
    final unexpected = [
      for (final entity in dir.listSync())
        if (fileNameOf(entity.path) != 'README.md' &&
            !(entity is File && entity.path.endsWith('.jsonl')))
          fileNameOf(entity.path),
    ];
    expect(unexpected, isEmpty, reason: 'Only run files belong in results/');
  });

  final runFiles = [
    if (dir.existsSync())
      for (final entity in dir.listSync())
        if (entity is File && entity.path.endsWith('.jsonl')) entity,
  ];
  for (final file in runFiles) {
    test('${fileNameOf(file.path)} is a valid run file under 95 MB', () async {
      expect(file.lengthSync(), lessThan(_maxBytes));
      // Throws RunFileFormatException, naming the problem, if invalid.
      await readRunFile(file.path, active: false);
    });
  }
}
