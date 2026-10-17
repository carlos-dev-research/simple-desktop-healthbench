// PR-1: the core is pure Dart (Constitution Article VI, spec 001 FR-008).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PR-1 lib/core imports no Flutter, dart:ui or Riverpod code', () {
    final core = Directory('lib/core');
    expect(core.existsSync(), isTrue, reason: 'lib/core/ must exist');

    final files = core
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty, reason: 'lib/core/ must contain Dart code');

    final forbidden = RegExp(
      r'''^\s*(import|export)\s+['"](package:flutter/|package:flutter_riverpod/|package:riverpod/|dart:ui)''',
      multiLine: true,
    );
    final offenders = [
      for (final file in files)
        if (forbidden.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'Core files must stay pure Dart; move UI code to lib/ui/.',
    );
  });
}
