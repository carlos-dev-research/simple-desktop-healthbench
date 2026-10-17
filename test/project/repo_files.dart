// Helpers for the project-rules tests (specs/001-project-scaffold/contracts/
// project-rules.md). `flutter test` runs with the repository root as the
// working directory, so paths are relative to it.
import 'dart:io';

/// Reads a repository file as text, failing clearly if it is missing.
String readRepoFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('Expected file not found: $path');
  }
  return file.readAsStringSync();
}

/// Keys whose value is `<true/>` in an Apple property list (entitlements).
Set<String> plistTrueKeys(String plist) {
  final pattern = RegExp(r'<key>([^<]+)</key>\s*<true\s*/>');
  return pattern.allMatches(plist).map((m) => m.group(1)!.trim()).toSet();
}

/// All keys in an Apple property list, whatever their value.
Set<String> plistKeys(String plist) {
  final pattern = RegExp(r'<key>([^<]+)</key>');
  return pattern.allMatches(plist).map((m) => m.group(1)!.trim()).toSet();
}
