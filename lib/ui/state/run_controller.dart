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

  @override
  ActiveRunState build() {
    ref.onDispose(() => _subscription?.cancel());
    return const ActiveRunState();
  }

  bool get isActive => _run != null;

  /// Starts a new run. Throws [StateError] while another run is active, and
  /// the core's exceptions for bad input.
  Future<void> start({
    required String datasetPath,
    required int? limit,
    required ConnectionSettings connection,
    required ModelSettings modelTest,
    required ModelSettings modelGrader,
  }) async {
    _ensureIdle();
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
  }

  /// Continues [runFilePath] with a freshly entered [apiKey] (spec 003 US4).
  Future<void> resume({
    required String runFilePath,
    required String datasetPath,
    required String apiKey,
  }) async {
    _ensureIdle();
    final run = await EvaluationRun.resume(
      runFilePath: runFilePath,
      datasetPath: datasetPath,
      apiKey: apiKey,
      options: ref.read(clientOptionsProvider),
    );
    _follow(run, null);
  }

  /// Stops after the conversation in progress (spec 003 FR-008).
  void stop() => _run?.stop();

  void _ensureIdle() {
    if (_run != null) {
      throw StateError('A run is already in progress');
    }
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
