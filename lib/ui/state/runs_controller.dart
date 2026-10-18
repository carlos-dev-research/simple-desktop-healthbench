import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/run_library.dart';
import 'providers.dart';

/// The run files in the app's storage (spec 003 FR-009, FR-010). Unchanged
/// files are not parsed again on refresh.
class RunsController extends AsyncNotifier<List<RunEntry>> {
  final RunEntryCache _cache = {};

  @override
  Future<List<RunEntry>> build() => _load();

  Future<List<RunEntry>> _load() async {
    final storage = await ref.read(storageDirectoryProvider.future);
    return listRuns(runsDirectoryIn(storage), cache: _cache);
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
