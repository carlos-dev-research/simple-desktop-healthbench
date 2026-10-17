// PR-3 to PR-6: macOS permissions, signing and dependency management
// (spec 001 FR-004, FR-005, FR-012; Constitution Articles VIII and XI).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_files.dart';

const _required = {
  'com.apple.security.app-sandbox',
  'com.apple.security.network.client',
  'com.apple.security.files.user-selected.read-write',
};

// Development allowances the Dart VM and debugger need; debug/profile only.
const _debugOnly = {
  'com.apple.security.cs.allow-jit',
  'com.apple.security.network.server',
};

void main() {
  final debug = readRepoFile('macos/Runner/DebugProfile.entitlements');
  final release = readRepoFile('macos/Runner/Release.entitlements');

  group('PR-3 both entitlements files grant the required permissions', () {
    for (final entry in {'DebugProfile': debug, 'Release': release}.entries) {
      test(entry.key, () {
        expect(plistTrueKeys(entry.value), containsAll(_required));
      });
    }
  });

  group('PR-4 nothing else is granted', () {
    test('Release grants exactly the required permissions', () {
      expect(plistKeys(release), _required);
    });

    test('DebugProfile adds only debug-only development allowances', () {
      expect(
        plistKeys(debug).difference(_required),
        everyElement(isIn(_debugOnly)),
      );
    });
  });

  test('PR-5 no personal signing team; ad-hoc signing only', () {
    final project = readRepoFile('macos/Runner.xcodeproj/project.pbxproj');
    expect(project, isNot(contains('DEVELOPMENT_TEAM')));
    final identities = RegExp(r'CODE_SIGN_IDENTITY = ([^;]+);')
        .allMatches(project)
        .map((m) => m.group(1)!.trim())
        .toSet();
    expect(identities, {'"-"'});
  });

  test('PR-6 no CocoaPods Podfile', () {
    expect(File('macos/Podfile').existsSync(), isFalse);
  });
}
