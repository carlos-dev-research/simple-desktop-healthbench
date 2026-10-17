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

// ------------------------------------------------- import / export / delete
// Spec 004: per-run file actions. The core refuses to touch a run that is
// being written (Constitution V.3, V.4), whatever the UI shows.

/// The run is being written by this app, so it can't be changed now.
class RunActiveException implements Exception {
  const RunActiveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The result of checking a file the user chose to import.
sealed class ImportCheck {
  const ImportCheck(this.sourcePath);

  final String sourcePath;
}

/// A valid run file, ready to be copied to [targetPath].
final class ImportReady extends ImportCheck {
  const ImportReady(
    super.sourcePath, {
    required this.contents,
    required this.targetPath,
    required this.replacesExisting,
  });

  final RunFileContents contents;
  final String targetPath;

  /// A run with the same file name is already in the app.
  final bool replacesExisting;
}

/// Not a valid run file; [reason] says why (with the line where relevant).
final class ImportRejected extends ImportCheck {
  const ImportRejected(super.sourcePath, this.reason);

  final String reason;
}

/// The chosen file is already the app's own copy.
final class ImportAlreadyInApp extends ImportCheck {
  const ImportAlreadyInApp(super.sourcePath);
}

String _inRuns(String runsDirectory, String fileName) =>
    '$runsDirectory${Platform.pathSeparator}$fileName';

/// Validates [sourcePath] completely with the run-file reader (on another
/// isolate) before anything is written (spec 004 FR-004).
Future<ImportCheck> checkImport(String sourcePath, String runsDirectory) async {
  final target = _inRuns(runsDirectory, fileNameOf(sourcePath));
  if (isSamePath(sourcePath, target)) return ImportAlreadyInApp(sourcePath);
  try {
    final contents = await Isolate.run(
      () => readRunFile(sourcePath, active: false),
    );
    return ImportReady(
      sourcePath,
      contents: contents,
      targetPath: target,
      replacesExisting: await File(target).exists(),
    );
  } on RunFileFormatException catch (e) {
    return ImportRejected(sourcePath, e.toString());
  } on FileSystemException catch (e) {
    return ImportRejected(sourcePath, 'Could not read the file: ${e.message}');
  }
}

/// Copies a checked file into the app's storage and returns its new path.
/// The original is never modified. The copy is written under a temporary
/// name and renamed into place, so a failure never leaves a broken run.
/// Throws [StateError] if the name exists and [replace] is false, and
/// [RunActiveException] if that run is being written.
Future<String> importRun(ImportReady check, {required bool replace}) async {
  final target = check.targetPath;
  final exists = await File(target).exists();
  if (exists && !replace) {
    throw StateError('A run named ${fileNameOf(target)} already exists');
  }
  if (isRunActive(target)) {
    throw const RunActiveException(
      'That run is in progress; stop it before replacing it',
    );
  }
  await Directory(File(target).parent.path).create(recursive: true);
  final temporary = File('$target.importing');
  try {
    await File(check.sourcePath).copy(temporary.path);
    if (await temporary.length() != await File(check.sourcePath).length()) {
      throw const FileSystemException('The copy is incomplete');
    }
    if (exists) await File(target).delete();
    await temporary.rename(target);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
  return target;
}

/// Writes a byte-identical copy of a run file to [destinationPath]
/// (spec 004 FR-002).
Future<void> exportRun(String runPath, String destinationPath) async {
  if (isRunActive(runPath)) {
    throw const RunActiveException(
      'The run is in progress; stop it before exporting',
    );
  }
  await File(runPath).copy(destinationPath);
}

/// Removes a run file from the app's storage (spec 004 FR-003).
Future<void> deleteRun(String path) async {
  if (isRunActive(path)) {
    throw const RunActiveException(
      'The run is in progress; stop it before deleting',
    );
  }
  await File(path).delete();
}
