import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/run_file.dart';
import '../../core/runner.dart';
import '../../core/settings.dart';
import 'providers.dart';
import 'runs_controller.dart';

/// The run shown in the progress panel: the active one, or the last one that
/// finished in this session.
class ActiveRunState {
  const ActiveRunState({this.progress, this.runFilePath, this.modelsLabel});

  final RunProgress? progress;
  final String? runFilePath;

  /// "model graded by grader", for the panel's subtitle.
  final String? modelsLabel;

  bool get isRunning => progress?.status == RunStatus.running;
}

/// Starts, resumes and stops runs; only one at a time (spec 003 FR-006).
class RunController extends Notifier<ActiveRunState> {
  EvaluationRun? _run;
  StreamSubscription<RunProgress>? _subscription;

  /// Set synchronously before the first await of start()/resume(), so a
  /// second request during the dataset read is refused (code review #1).
  var _starting = false;

  @override
  ActiveRunState build() {
    ref.onDispose(() => _subscription?.cancel());
    return const ActiveRunState();
  }

  bool get isActive => _run != null || _starting;

  String? _datasetPath;

  /// The dataset the active run reads; it can't be deleted meanwhile
  /// (spec 005 FR-008).
  String? get activeDatasetPath => isActive ? _datasetPath : null;

  /// Starts a new run. Throws [StateError] while another run is active, and
  /// the core's exceptions for bad input.
  Future<void> start({
    required String datasetPath,
    required int? limit,
    required ConnectionSettings connection,
    required ModelSettings modelTest,
    required ModelSettings modelGrader,
  }) async {
    _claim();
    _datasetPath = datasetPath;
    try {
      final storage = await ref.read(storageDirectoryProvider.future);
      final run = await EvaluationRun.start(
        runsDirectory: runsDirectoryIn(storage),
        datasetPath: datasetPath,
        limit: limit,
        connection: connection,
        modelTest: modelTest,
        modelGrader: modelGrader,
        options: ref.read(clientOptionsProvider),
      );
      _follow(run, '${modelTest.name} graded by ${modelGrader.name}');
    } finally {
      _starting = false;
    }
  }

  /// Continues [runFilePath] with a freshly entered [apiKey] (spec 003 US4).
  Future<void> resume({
    required String runFilePath,
    required String datasetPath,
    required String apiKey,
  }) async {
    _claim();
    _datasetPath = datasetPath;
    try {
      final run = await EvaluationRun.resume(
        runFilePath: runFilePath,
        datasetPath: datasetPath,
        apiKey: apiKey,
        options: ref.read(clientOptionsProvider),
      );
      _follow(run, null);
    } finally {
      _starting = false;
    }
  }

  /// Stops after the conversation in progress (spec 003 FR-008).
  void stop() => _run?.stop();

  void _claim() {
    if (_run != null || _starting) {
      throw StateError('A run is already in progress');
    }
    _starting = true;
  }

  void _follow(EvaluationRun run, String? modelsLabel) {
    _run = run;
    state = ActiveRunState(
      progress: run.current,
      runFilePath: run.runFilePath,
      modelsLabel: modelsLabel,
    );
    _subscription = run.progress.listen((progress) {
      state = ActiveRunState(
        progress: progress,
        runFilePath: run.runFilePath,
        modelsLabel: modelsLabel,
      );
    });
    unawaited(_whenFinished(run, modelsLabel));
    // Show the new run in the list right away (as running).
    unawaited(ref.read(runsProvider.notifier).refresh());
  }

  Future<void> _whenFinished(EvaluationRun run, String? modelsLabel) async {
    final last = await run.finished;
    await _subscription?.cancel();
    _subscription = null;
    _run = null;
    if (!ref.mounted) return;
    state = ActiveRunState(
      progress: last,
      runFilePath: run.runFilePath,
      modelsLabel: modelsLabel,
    );
    await ref.read(runsProvider.notifier).refresh();
  }
}

final runControllerProvider = NotifierProvider<RunController, ActiveRunState>(
  RunController.new,
);
