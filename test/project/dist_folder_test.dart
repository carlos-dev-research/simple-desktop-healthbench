// Constitution XII.2 (1.2.0): dist/ holds only app archives named
// HealthBench-Evals-<platform>-v<version>.zip, plus its README.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/dataset.dart' show fileNameOf;

void main() {
  test('dist/ contains only versioned app archives and its README', () {
    final pattern = RegExp(
      r'^HealthBench-Evals-(macOS|Windows|Linux)-v\d+\.\d+\.\d+\.zip$',
    );
    final names = [
      for (final e in Directory('dist').listSync()) fileNameOf(e.path),
    ];
    expect(names, contains('README.md'));
    final unexpected = [
      for (final n in names)
        if (n != 'README.md' && !pattern.hasMatch(n)) n,
    ];
    expect(unexpected, isEmpty);
  });
}
