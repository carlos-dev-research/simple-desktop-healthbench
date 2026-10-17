// Developer-only command-line runner for the evaluation core (spec 002
// research R16). Not part of the app. Use it to try the core against a real
// OpenAI-compatible endpoint before the UI exists.
//
//   export HEALTHBENCH_API_KEY=...        # in your shell only, never in a file
//   fvm dart run tool/try_run.dart --dataset healthbench/<file>.jsonl --count-only
//   fvm dart run tool/try_run.dart --dataset healthbench/<file>.jsonl --limit 3 \
//       --base-url https://api.groq.com/openai/v1 \
//       --model openai/gpt-oss-20b --grader openai/gpt-oss-20b --effort low
//   fvm dart run tool/try_run.dart --dataset healthbench/<file>.jsonl --resume build/try_runs/<run>.jsonl
//   fvm dart run tool/try_run.dart --validate build/try_runs/<run>.jsonl
//
// Ctrl-C once stops after the current conversation; twice exits at once.
// Runs are written to build/try_runs/ (git-ignored) unless --runs-dir is set.
import 'dart:async';
import 'dart:io';

import 'package:healthbench/core/dataset.dart';
import 'package:healthbench/core/run_file.dart';
import 'package:healthbench/core/runner.dart';
import 'package:healthbench/core/settings.dart';

const _usage = '''
Usage:
  try_run.dart --dataset FILE --count-only
  try_run.dart --dataset FILE [--limit N] --base-url URL --model NAME
               [--grader NAME] [--effort none|low|medium|high]
               [--effort-test E] [--effort-grader E] [--runs-dir DIR]
  try_run.dart --dataset FILE --resume RUN_FILE
  try_run.dart --validate RUN_FILE
The API key is read from the HEALTHBENCH_API_KEY environment variable.''';

Future<void> main(List<String> args) async {
  final options = _parse(args);
  if (options == null) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  try {
    if (options['validate'] case final path?) return await _validate(path);
    final dataset = options['dataset'];
    if (dataset == null) throw const FormatException('--dataset is required');
    if (options.containsKey('count-only')) return await _count(dataset);
    await _run(options, dataset);
  } on FormatException catch (e) {
    stderr.writeln('error: ${e.message}\n\n$_usage');
    exitCode = 64;
  } on DatasetFormatException catch (e) {
    stderr.writeln('error: $e');
    exitCode = 65;
  } on RunFileFormatException catch (e) {
    stderr.writeln('invalid: $e');
    exitCode = 65;
  } on RunStartException catch (e) {
    stderr.writeln('cannot start: ${e.reason}');
    exitCode = 1;
  } on ArgumentError catch (e) {
    stderr.writeln('error: ${e.message}');
    exitCode = 64;
  }
}

Map<String, String?>? _parse(List<String> args) {
  const flags = {'count-only'};
  const values = {
    'dataset', 'limit', 'base-url', 'model', 'grader', 'effort', //
    'effort-test', 'effort-grader', 'runs-dir', 'resume', 'validate',
  };
  final result = <String, String?>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) return null;
    final name = arg.substring(2);
    if (flags.contains(name)) {
      result[name] = null;
    } else if (values.contains(name) && i + 1 < args.length) {
      result[name] = args[++i];
    } else {
      return null;
    }
  }
  return result;
}

Future<void> _count(String path) async {
  final watch = Stopwatch()..start();
  final dataset = await readDataset(path);
  final criteria = dataset.conversations.fold<int>(
    0,
    (sum, c) => sum + c.criteria.length,
  );
  stdout.writeln(
    '${dataset.fileName}: ${dataset.conversations.length} conversations, '
    '$criteria criteria (read in ${watch.elapsedMilliseconds} ms)',
  );
}

Future<void> _validate(String path) async {
  final contents = await readRunFile(path);
  stdout.writeln(
    'valid: ${contents.header.runId} · ${contents.status.name} · '
    '${contents.conversations.length}/${contents.header.dataset.selectedCount} '
    'graded · score ${contents.score.toStringAsFixed(4)}',
  );
}

String _apiKey() {
  final key = Platform.environment['HEALTHBENCH_API_KEY'] ?? '';
  if (key.isEmpty) {
    throw ArgumentError('Set HEALTHBENCH_API_KEY in your shell first');
  }
  return key;
}

ReasoningEffort _effort(Map<String, String?> o, String specific) =>
    ReasoningEffort.parse(o[specific] ?? o['effort'] ?? 'none');

Future<void> _run(Map<String, String?> o, String datasetPath) async {
  final EvaluationRun run;
  if (o['resume'] case final runFile?) {
    run = await EvaluationRun.resume(
      runFilePath: runFile,
      datasetPath: datasetPath,
      apiKey: _apiKey(),
    );
  } else {
    final baseUrl = o['base-url'];
    final model = o['model'];
    if (baseUrl == null || model == null) {
      throw const FormatException('--base-url and --model are required');
    }
    final limit = o['limit'] == null ? null : int.tryParse(o['limit']!);
    if (o['limit'] != null && limit == null) {
      throw const FormatException('--limit must be a number');
    }
    run = await EvaluationRun.start(
      runsDirectory: o['runs-dir'] ?? 'build/try_runs',
      datasetPath: datasetPath,
      limit: limit,
      connection: ConnectionSettings(baseUrl: baseUrl, apiKey: _apiKey()),
      modelTest: ModelSettings(
        name: model,
        reasoningEffort: _effort(o, 'effort-test'),
      ),
      modelGrader: ModelSettings(
        name: o['grader'] ?? model,
        reasoningEffort: _effort(o, 'effort-grader'),
      ),
    );
  }
  stdout.writeln('run ${run.runId} → ${run.runFilePath}');

  var interrupts = 0;
  final sigint = ProcessSignal.sigint.watch().listen((_) {
    if (++interrupts > 1) exit(130);
    stdout.writeln(
      '\nstopping after the current conversation (Ctrl-C again to quit now)…',
    );
    run.stop();
  });

  var lastLine = '';
  final printed = run.progress.listen((p) {
    final score = p.score == null ? '-' : p.score!.toStringAsFixed(4);
    final line = '[${p.done}/${p.total}] failed ${p.failed} · score $score';
    if (line != lastLine) {
      stdout.writeln(line);
      lastLine = line;
    }
  });

  final done = await run.finished;
  await printed.cancel();
  await sigint.cancel();
  for (final error in done.recentErrors) {
    stdout.writeln('error: $error');
  }
  stdout.writeln(
    '${done.status.name}: ${done.done}/${done.total} graded, ${done.failed} failed'
    '${done.score == null ? '' : ', score ${done.score!.toStringAsFixed(4)}'}'
    '${done.failureReason == null ? '' : ' — ${done.failureReason}'}'
    ' (${done.elapsed.inSeconds} s)',
  );
  if (run.runFilePath == null) {
    stdout.writeln('(nothing graded; no run file kept)');
  }
  if (done.status == RunStatus.failed) exitCode = 1;
}
