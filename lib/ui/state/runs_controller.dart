import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/run_file.dart';
import '../../core/run_library.dart';
import 'providers.dart';

/// The run files in the app's storage (spec 003 FR-009, FR-010). Unchanged
/// files are not parsed again on refresh.
class RunsController extends AsyncNotifier<List<RunEntry>> {
  final Map<String, (DateTime, int, RunEntry)> _cache = {};

  @override
  Future<List<RunEntry>> build() => _load();

  Future<List<RunEntry>> _load() async {
    final storage = await ref.read(storageDirectoryProvider.future);
    final dir = Directory(runsDirectoryIn(storage));
    if (!await dir.exists()) return const [];
    final paths = <String>{};
    final entries = <RunEntry>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
      paths.add(entity.path);
      final stat = await entity.stat();
      final cached = _cache[entity.path];
      if (cached != null &&
          cached.$1 == stat.modified &&
          cached.$2 == stat.size &&
          // A running run must always be re-read: it changes constantly.
          cached.$3.contents?.status != RunStatus.running) {
        entries.add(cached.$3);
        continue;
      }
      final entry = await readRunEntry(entity.path);
      _cache[entity.path] = (stat.modified, stat.size, entry);
      entries.add(entry);
    }
    _cache.removeWhere((path, _) => !paths.contains(path));
    return sortRunEntries(entries);
  }

  /// Re-reads the folder.
  Future<void> refresh() async {
    state = await AsyncValue.guard(_load);
  }
}

final runsProvider = AsyncNotifierProvider<RunsController, List<RunEntry>>(
  RunsController.new,
);

/// The run whose details are shown.
class SelectedRun extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? path) => state = path;
}

final selectedRunProvider = NotifierProvider<SelectedRun, String?>(
  SelectedRun.new,
);
