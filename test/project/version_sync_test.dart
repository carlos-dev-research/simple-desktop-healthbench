// PR-2: the version shown in the app matches pubspec.yaml (spec 001 FR-002).
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/app_info.dart';

import 'repo_files.dart';

void main() {
  test('PR-2 appVersion equals the pubspec.yaml version (without +build)', () {
    final pubspec = readRepoFile('pubspec.yaml');
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');
    expect(appVersion, match!.group(1));
  });
}
