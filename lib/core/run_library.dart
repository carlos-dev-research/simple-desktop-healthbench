/// The run files in the app's storage folder (spec 003 FR-009, FR-010).
library;

import 'dart:io';
import 'dart:isolate';

import 'dataset.dart';
import 'run_file.dart';

/// One `.jsonl` file in the runs folder: a valid run, or a rejected file with
/// the reason.
class RunEntry {
  const RunEntry({required this.path, this.contents, this.error});

  final String path;
  final RunFileContents? contents;
  final String? error;

  String get fileName => fileNameOf(path);
  bool get isValid => contents != null;
}

/// Lists every `.jsonl` file in [directory]: valid runs newest first, then
/// rejected files by name. Each file is parsed on another isolate so a large
/// run doesn't block the caller (spec 003 NFR-001).
Future<List<RunEntry>> listRuns(String directory) async {
  final dir = Directory(directory);
  if (!await dir.exists()) return const [];
  final files = [
    await for (final entity in dir.list())
      if (entity is File && entity.path.endsWith('.jsonl')) entity.path,
  ];
  final entries = <RunEntry>[];
  for (final path in files) {
    entries.add(await readRunEntry(path));
  }
  return sortRunEntries(entries);
}

/// Valid runs newest first, then rejected files by name.
List<RunEntry> sortRunEntries(Iterable<RunEntry> entries) {
  final valid = entries.where((e) => e.isValid).toList()
    ..sort((a, b) => _newestFirst(a.fileName, b.fileName));
  final rejected = entries.where((e) => !e.isValid).toList()
    ..sort((a, b) => a.fileName.compareTo(b.fileName));
  return [...valid, ...rejected];
}

/// Orders run file names by start time, then by `-N` suffix, newest first.
int _newestFirst(String a, String b) {
  (String, int) key(String name) {
    final match = RegExp(r'^(.*-\d{8}-\d{6})(?:-(\d+))?\.jsonl$')
        .firstMatch(name);
    if (match == null) return (name, 0);
    return (match.group(1)!, int.parse(match.group(2) ?? '1'));
  }

  final (baseA, suffixA) = key(a);
  final (baseB, suffixB) = key(b);
  final byTime = baseB.compareTo(baseA);
  return byTime != 0 ? byTime : suffixB.compareTo(suffixA);
}

/// Reads one run file on another isolate.
Future<RunEntry> readRunEntry(String path) async {
  final active = isRunActive(path);
  try {
    final contents = await Isolate.run(() => readRunFile(path, active: active));
    return RunEntry(path: path, contents: contents);
  } on RunFileFormatException catch (e) {
    return RunEntry(path: path, error: e.toString());
  } on FileSystemException catch (e) {
    return RunEntry(path: path, error: 'Could not read the file: ${e.message}');
  }
}
