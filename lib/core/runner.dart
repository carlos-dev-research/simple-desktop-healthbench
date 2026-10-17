/// Running a whole evaluation, with progress, stop and resume
/// (port of pygrader runner.run_evaluation; spec 002 US4, US5; research
/// R6, R13, R14, R17).
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_info.dart';
import 'chat_client.dart';
import 'dataset.dart';
import 'grader_prompt.dart';
import 'grading.dart';
import 'run_file.dart';
import 'scoring.dart';
import 'settings.dart';

/// Stop the run when this many conversations fail in a row (reference
/// MAX_CONSECUTIVE_FAILURES).
const int maxConsecutiveFailures = 5;

/// At most this many recent error messages are kept.
const int maxRecentErrors = 10;

/// A snapshot of a run, sent after every criterion and conversation.
class RunProgress {
  const RunProgress({
    required this.runId,
    required this.status,
    required this.stopRequested,
    required this.total,
    required this.done,
    required this.failed,
    required this.criterionDone,
    required this.criterionTotal,
    required this.score,
    required this.recentErrors,
    required this.elapsed,
    this.failureReason,
  });

  final String runId;
  final RunStatus status;

  /// A stop was requested; the run stops after the current conversation.
  final bool stopRequested;

  /// Conversations selected for the run.
  final int total;

  /// Conversations graded and in the run file (including earlier sessions).
  final int done;

  /// Conversations that failed in this session (not in the file).
  final int failed;

  /// Grading progress inside the current conversation.
  final int criterionDone;
  final int criterionTotal;

  /// Run score over the graded conversations; null before the first one.
  final double? score;

  /// The last [maxRecentErrors] error messages, never containing the key.
  final List<String> recentErrors;
  final Duration elapsed;

  /// Why the run failed, once [status] is [RunStatus.failed].
  final String? failureReason;
}

/// A run could not be started or resumed.
class RunStartException implements Exception {
  const RunStartException(this.reason);

  final String reason;

  @override
  String toString() => 'RunStartException: $reason';
}

/// One evaluation run in progress. Create it with [start] or [resume].
class EvaluationRun {
  EvaluationRun._({
    required this._path,
    required this.runId,
    required this._writer,
    required this._client,
    required this._apiKey,
    required this._modelTest,
    required this._modelGrader,
    required this._pending,
    required this._total,
    required this._scores,
    required this._fresh,
  });

  final String runId;
  String? _path;
  final RunFileWriter _writer;
  final ChatClient _client;
  final String _apiKey;
  final ModelSettings _modelTest;
  final ModelSettings _modelGrader;
  final List<Conversation> _pending;
  final int _total;
  final List<double?> _scores;
  final bool _fresh;

  final _progress = StreamController<RunProgress>.broadcast();
  final _finished = Completer<RunProgress>();
  final _stopwatch = Stopwatch();
  final _errors = <String>[];
  var _status = RunStatus.running;
  var _stopRequested = false;
  var _failed = 0;
  var _criterionDone = 0;
  var _criterionTotal = 0;
  String? _failureReason;
  late RunProgress _latest = _snapshot();

  /// Progress events; broadcast, closed when the run ends.
  Stream<RunProgress> get progress => _progress.stream;

  /// The most recent snapshot.
  RunProgress get current => _latest;

  /// Completes with the final snapshot: completed, stopped or failed.
  Future<RunProgress> get finished => _finished.future;

  /// The run file, or null once a run that graded nothing has been removed.
  String? get runFilePath => _path;

  /// Stops after the conversation in progress (FR-015).
  void stop() {
    if (_stopRequested || _finished.isCompleted) return;
    _stopRequested = true;
    _emit();
  }

  /// Starts a new run over the first [limit] conversations of the dataset.
  static Future<EvaluationRun> start({
    required String runsDirectory,
    required String datasetPath,
    int? limit,
    required ConnectionSettings connection,
    required ModelSettings modelTest,
    required ModelSettings modelGrader,
    ClientOptions options = const ClientOptions(),
    http.Client? httpClient,
  }) async {
    final dataset = await readDataset(datasetPath);
    final selected = dataset.select(limit);
    final startedAt = DateTime.now();
    final writer = await RunFileWriter.createNew(runsDirectory, startedAt);
    markRunActive(writer.path);
    try {
      await writer.write(
        headerJson(
          RunHeader(
            runId: writer.runId,
            app: appName,
            appVersion: appVersion,
            createdAt: startedAt,
            baseUrl: connection.baseUrl,
            modelTest: modelTest,
            modelGrader: modelGrader,
            temperature: requestTemperature,
            graderPromptId: graderPromptId,
            graderPromptSha256: graderPromptSha256,
            dataset: DatasetRef(
              fileName: dataset.fileName,
              sha256: dataset.sha256,
              conversationCount: dataset.conversations.length,
              limit: limit,
            ),
          ),
        ),
      );
      await writer.write(
        statusJson(
          StatusEntry(status: RunStatus.running, at: startedAt, graded: 0),
        ),
      );
    } on Object {
      markRunInactive(writer.path);
      await writer.close();
      await File(writer.path).delete();
      rethrow;
    }
    return EvaluationRun._(
      path: writer.path,
      runId: writer.runId,
      writer: writer,
      client: ChatClient(connection, options: options, httpClient: httpClient),
      apiKey: connection.apiKey,
      modelTest: modelTest,
      modelGrader: modelGrader,
      pending: selected,
      total: selected.length,
      scores: [],
      fresh: true,
    ).._launch();
  }

  /// Continues a run file: grades only the selected conversations that are
  /// not in it yet (including ones that failed before). Every setting except
  /// the API key comes from the file (US5-3).
  static Future<EvaluationRun> resume({
    required String runFilePath,
    required String datasetPath,
    required String apiKey,
    ClientOptions options = const ClientOptions(),
    http.Client? httpClient,
  }) async {
    if (isRunActive(runFilePath)) {
      throw const RunStartException('This run is already in progress');
    }
    final contents = await readRunFile(runFilePath);
    final header = contents.header;
    final connection = ConnectionSettings(
      baseUrl: header.baseUrl.toString(),
      apiKey: apiKey,
    );
    final dataset = await readDataset(datasetPath);
    if (dataset.sha256 != header.dataset.sha256 ||
        dataset.conversations.length != header.dataset.conversationCount) {
      throw RunStartException(
        'The dataset file differs from the one this run used '
        '(${header.dataset.fileName}); results from different datasets are '
        'never mixed',
      );
    }
    final done = contents.doneIds;
    final pending = [
      for (final c in dataset.select(header.dataset.limit))
        if (!done.contains(c.promptId)) c,
    ];
    if (pending.isEmpty) {
      throw const RunStartException('This run has nothing left to evaluate');
    }
    if (!markRunActive(runFilePath)) {
      throw const RunStartException('This run is already in progress');
    }
    final RunFileWriter writer;
    try {
      writer = await RunFileWriter.reopen(contents);
      await writer.write(
        statusJson(
          StatusEntry(
            status: RunStatus.running,
            at: DateTime.now(),
            graded: contents.conversations.length,
          ),
        ),
      );
    } on Object {
      markRunInactive(runFilePath);
      rethrow;
    }
    return EvaluationRun._(
      path: runFilePath,
      runId: header.runId,
      writer: writer,
      client: ChatClient(connection, options: options, httpClient: httpClient),
      apiKey: apiKey,
      modelTest: header.modelTest,
      modelGrader: header.modelGrader,
      pending: pending,
      total: header.dataset.selectedCount,
      scores: [
        for (final c in contents.conversations) conversationScore(c.grades),
      ],
      fresh: false,
    ).._launch();
  }

  void _launch() {
    _stopwatch.start();
    _emit();
    unawaited(_run());
  }

  Future<void> _run() async {
    var consecutiveFailures = 0;
    var stopped = false;
    try {
      for (final conversation in _pending) {
        if (_stopRequested) {
          stopped = true;
          break;
        }
        _criterionDone = 0;
        _criterionTotal = 0;
        _emit();

        final GradedConversation graded;
        try {
          graded = await evaluateConversation(
            conversation,
            client: _client,
            modelTest: _modelTest,
            modelGrader: _modelGrader,
            onCriterion: (done, total) {
              _criterionDone = done;
              _criterionTotal = total;
              _emit();
            },
          );
        } on ChatError catch (error) {
          _recordError(conversation, error.message);
          if (error.isFatal) {
            _failureReason = _redact(error.message);
            break;
          }
          _failed++;
          if (++consecutiveFailures >= maxConsecutiveFailures) {
            _failureReason =
                '$maxConsecutiveFailures conversations failed in a row; '
                'stopping the run';
            break;
          }
          _emit();
          continue;
        } on Exception catch (error) {
          // Unusable grader answer or similar: skip this conversation.
          _recordError(conversation, '$error');
          _failed++;
          if (++consecutiveFailures >= maxConsecutiveFailures) {
            _failureReason =
                '$maxConsecutiveFailures conversations failed in a row; '
                'stopping the run';
            break;
          }
          _emit();
          continue;
        }

        await _writer.write(conversationJson(graded));
        consecutiveFailures = 0;
        _scores.add(conversationScore(graded.grades));
        _emit();
      }
    } on FileSystemException catch (error) {
      _failureReason = 'Could not write the run file: ${error.message}';
    } on Object catch (error) {
      _failureReason = _redact('Unexpected error: $error');
    }
    await _finish(stopped: stopped);
  }

  Future<void> _finish({required bool stopped}) async {
    if (_failureReason == null && _scores.isEmpty) {
      _failureReason = 'No conversation could be graded';
    }
    _status = _failureReason != null
        ? RunStatus.failed
        : stopped
        ? RunStatus.stopped
        : RunStatus.completed;
    _criterionDone = 0;
    _criterionTotal = 0;
    try {
      await _writer.write(
        statusJson(
          StatusEntry(
            status: _status,
            at: DateTime.now(),
            graded: _scores.length,
            score: _scores.isEmpty ? null : runScore(_scores),
            reason: _failureReason,
          ),
        ),
      );
    } on FileSystemException {
      // The failure is already reported; the file keeps its last good line.
    }
    await _writer.close();
    _client.close();
    markRunInactive(_writer.path);
    if (_fresh && _scores.isEmpty) {
      // Nothing graded: don't leave an empty run behind (FR-021).
      await File(_writer.path).delete();
      _path = null;
    }
    _stopwatch.stop();
    _emit();
    _finished.complete(_latest);
    await _progress.close();
  }

  void _recordError(Conversation conversation, String message) {
    _errors.add(
      _redact(
        'Conversation ${conversation.index + 1} '
        '(${conversation.promptId}): $message',
      ),
    );
    if (_errors.length > maxRecentErrors) _errors.removeAt(0);
  }

  String _redact(String text) => text.replaceAll(_apiKey, '***');

  RunProgress _snapshot() => RunProgress(
    runId: runId,
    status: _status,
    stopRequested: _stopRequested,
    total: _total,
    done: _scores.length,
    failed: _failed,
    criterionDone: _criterionDone,
    criterionTotal: _criterionTotal,
    score: _scores.isEmpty ? null : runScore(_scores),
    recentErrors: List.unmodifiable(_errors),
    elapsed: _stopwatch.elapsed,
    failureReason: _status == RunStatus.failed ? _failureReason : null,
  );

  void _emit() {
    _latest = _snapshot();
    if (!_progress.isClosed) _progress.add(_latest);
  }
}
