// US4/US5: running, stopping and resuming an evaluation (spec 002 FR-012–FR-021;
// port of pygrader runner.run_evaluation plus stop/continue).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/run_file.dart';
import 'package:healthbench/core/runner.dart';
import 'package:healthbench/core/settings.dart';

import '../support/fake_openai_server.dart';
import '../support/fixtures.dart';

const _fast = ClientOptions(
  timeout: Duration(seconds: 5),
  maxRetries: 1,
  initialBackoff: Duration(milliseconds: 1),
  maxBackoff: Duration(milliseconds: 2),
);

void main() {
  late Directory dir;
  late String datasetPath;
  late String runsDir;
  late FakeOpenAiServer server;
  var serverStarted = false;
  EvaluationRun? run;

  // Behaviour of the fake server; changed between sessions of one test. The
  // server itself stays up, because a resumed run uses the base URL stored
  // in its run file.
  var failWith = <String, FakeResponse>{};
  FutureOr<void> Function(String promptId)? onGenerate;
  var delay = Duration.zero;

  setUp(() {
    serverStarted = false;
    failWith = {};
    onGenerate = null;
    delay = Duration.zero;
    dir = tempDir(addTearDown);
    runsDir = '${dir.path}/runs';
    datasetPath = '${dir.path}/data.jsonl';
  });

  /// Which conversation (p0, p1, …) a request is about.
  String promptIdOf(RecordedRequest r) =>
      RegExp(r'Question for (p\d+)')
          .firstMatch(r.firstMessageContent)!
          .group(1)!;

  /// Sets the server's behaviour (starting it on first use): every
  /// conversation scores 1.0, except those [fail] maps to an error response;
  /// [hook] runs before each reply. Recorded requests are cleared.
  Future<void> serve({
    Map<String, FakeResponse> fail = const {},
    FutureOr<void> Function(String promptId)? hook,
    Duration wait = Duration.zero,
  }) async {
    failWith = fail;
    onGenerate = hook;
    delay = wait;
    if (serverStarted) {
      server.requests.clear();
      return;
    }
    serverStarted = true;
    server = await FakeOpenAiServer.start((r, _) async {
      final id = promptIdOf(r);
      if (failWith[id] case final error?) return error;
      if (!r.isGraderCall) {
        await onGenerate?.call(id);
        return FakeResponse.reply('Reply to $id').withDelay(delay);
      }
      final met = r.firstMessageContent.contains(
        'Criterion:\nGives the right advice',
      );
      return FakeResponse.grade(met: met);
    });
    addTearDown(server.close);
  }

  ConnectionSettings connection([String key = 'sk-test']) =>
      ConnectionSettings(baseUrl: server.baseUrl.toString(), apiKey: key);

  Future<EvaluationRun> start({int? limit}) async =>
      run = await EvaluationRun.start(
        runsDirectory: runsDir,
        datasetPath: datasetPath,
        limit: limit,
        connection: connection(),
        modelTest: ModelSettings(
          name: 'tested',
          reasoningEffort: ReasoningEffort.low,
        ),
        modelGrader: ModelSettings(name: 'grader'),
        options: _fast,
      );

  Future<EvaluationRun> resume(String path, {String key = 'sk-test'}) async =>
      run = await EvaluationRun.resume(
        runFilePath: path,
        datasetPath: datasetPath,
        apiKey: key,
        options: _fast,
      );

  List<Map<String, Object?>> linesOf(String path) => [
    for (final line in File(path).readAsLinesSync())
      jsonDecode(line) as Map<String, Object?>,
  ];

  List<String> statusesOf(String path) => [
    for (final l in linesOf(path))
      if (l['type'] == 'status') l['status']! as String,
  ];

  group('a run (US4)', () {
    test(
      'creates a timestamped run file and completes with the score',
      () async {
        writeDataset(datasetPath, 5);
        await serve();
        final r = await start(limit: 3);
        final done = await r.finished;

        expect(done.status, RunStatus.completed);
        expect(done.total, 3);
        expect(done.done, 3);
        expect(done.failed, 0);
        expect(done.score, 1.0);
        final path = r.runFilePath!;
        expect(isRunFileName(path.split(Platform.pathSeparator).last), isTrue);

        final contents = await readRunFile(path);
        expect(contents.header.dataset.fileName, 'data.jsonl');
        expect(contents.header.dataset.limit, 3);
        expect(contents.header.dataset.conversationCount, 5);
        expect(contents.header.modelTest.name, 'tested');
        expect(contents.header.baseUrl, server.baseUrl);
        expect(contents.conversations.map((c) => c.conversation.promptId), [
          'p0',
          'p1',
          'p2',
        ]);
        expect(contents.status, RunStatus.completed);
        expect(statusesOf(path), ['running', 'completed']);
      },
    );

    test('reports progress per criterion and per conversation', () async {
      writeDataset(datasetPath, 2);
      await serve();
      final r = await start();
      final events = <RunProgress>[];
      r.progress.listen(events.add);
      await r.finished;

      expect(events.map((e) => e.done).toSet(), containsAll([0, 1, 2]));
      expect(
        events.where((e) => e.criterionTotal == 2).map((e) => e.criterionDone),
        containsAllInOrder([0, 1, 2, 0, 1, 2]),
      );
      expect(events.last.status, RunStatus.completed);
      expect(events.every((e) => e.total == 2), isTrue);
    });

    test(
      'each conversation is in the file before the next one starts',
      () async {
        writeDataset(datasetPath, 3);
        final linesSeen = <String, int>{};
        await serve(
          hook: (id) {
            final conversations = linesOf(run!.runFilePath!)
                .where((l) => l['type'] == 'conversation')
                .length;
            linesSeen[id] = conversations;
          },
        );
        await (await start()).finished;
        expect(linesSeen, {'p0': 0, 'p1': 1, 'p2': 2});
      },
    );

    test(
      'a conversation that keeps failing is skipped; the run goes on',
      () async {
        writeDataset(datasetPath, 3);
        await serve(fail: {'p1': FakeResponse.error(500, 'server down')});
        final done = await (await start()).finished;

        expect(done.status, RunStatus.completed);
        expect(done.done, 2);
        expect(done.failed, 1);
        expect(
          done.recentErrors.single,
          allOf(contains('p1'), contains('server down')),
        );
        final contents = await readRunFile(run!.runFilePath!);
        expect(contents.doneIds, {'p0', 'p2'});
        // 2 retried attempts for p1 (maxRetries 1).
        expect(
          server.requests.where((r) => promptIdOf(r) == 'p1'),
          hasLength(2),
        );
      },
    );

    test(
      'a fatal error stops the run; nothing graded leaves no file',
      () async {
        writeDataset(datasetPath, 3);
        await serve(fail: {'p0': FakeResponse.error(401, 'bad key')});
        final r = await start();
        final done = await r.finished;

        expect(done.status, RunStatus.failed);
        expect(done.recentErrors.last, contains('Authentication failed'));
        expect(r.runFilePath, isNull);
        expect(Directory(runsDir).listSync(), isEmpty);
        expect(server.requests, hasLength(1)); // never retried, never continued
      },
    );

    test(
      'a fatal error after some progress keeps the file, marked failed',
      () async {
        writeDataset(datasetPath, 3);
        await serve(fail: {'p1': FakeResponse.error(404, 'no such model')});
        final r = await start();
        final done = await r.finished;

        expect(done.status, RunStatus.failed);
        final contents = await readRunFile(r.runFilePath!);
        expect(contents.status, RunStatus.failed);
        expect(contents.failureReason, contains('not found'));
        expect(contents.doneIds, {'p0'});
      },
    );

    test('5 conversations failing in a row stops the run', () async {
      writeDataset(datasetPath, 8);
      await serve(
        fail: {
          for (var i = 1; i <= 6; i++) 'p$i': FakeResponse.error(503, 'busy'),
        },
      );
      final done = await (await start()).finished;

      expect(done.status, RunStatus.failed);
      expect(done.failed, 5);
      expect(done.done, 1);
      final contents = await readRunFile(run!.runFilePath!);
      expect(
        contents.failureReason,
        contains('5 conversations failed in a row'),
      );
      expect(server.requests.any((r) => promptIdOf(r) == 'p6'), isFalse);
    });

    test('nothing graded (all fail) leaves no file', () async {
      writeDataset(datasetPath, 2);
      await serve(
        fail: {
          'p0': FakeResponse.error(500, 'x'),
          'p1': FakeResponse.error(500, 'x'),
        },
      );
      final r = await start();
      final done = await r.finished;
      expect(done.status, RunStatus.failed);
      expect(r.runFilePath, isNull);
      expect(Directory(runsDir).listSync(), isEmpty);
    });
  });

  group('stop and resume (US5)', () {
    Future<String> stoppedRun({int total = 5, int stopDuring = 1}) async {
      writeDataset(datasetPath, total);
      await serve(
        hook: (id) {
          if (id == 'p$stopDuring') run!.stop();
        },
      );
      final r = await start();
      final done = await r.finished;
      expect(done.status, RunStatus.stopped);
      expect(
        done.done,
        stopDuring + 1,
      ); // the conversation in progress finishes
      return r.runFilePath!;
    }

    test('stop takes effect after the conversation in progress', () async {
      final path = await stoppedRun();
      final contents = await readRunFile(path);
      expect(contents.status, RunStatus.stopped);
      expect(contents.doneIds, {'p0', 'p1'});
    });

    test('resume grades only the missing conversations', () async {
      final path = await stoppedRun();
      await serve();
      final done = await (await resume(path)).finished;

      expect(done.status, RunStatus.completed);
      expect(done.done, 5);
      expect(server.requests.map(promptIdOf).toSet(), {'p2', 'p3', 'p4'});
      expect(statusesOf(path), ['running', 'stopped', 'running', 'completed']);
      expect((await readRunFile(path)).score, 1.0);
    });

    test('resume retries conversations that failed before', () async {
      writeDataset(datasetPath, 3);
      await serve(fail: {'p1': FakeResponse.error(500, 'down')});
      final path = (await (await start()).finished).let(
        (_) => run!.runFilePath!,
      );

      await serve();
      final done = await (await resume(path)).finished;
      expect(done.done, 3);
      expect(server.requests.map(promptIdOf).toSet(), {'p1'});
    });

    test('resume needs the API key again', () async {
      final path = await stoppedRun();
      await serve();
      await expectLater(resume(path, key: ''), throwsA(isA<ArgumentError>()));
    });

    test('resume refuses a changed dataset', () async {
      final path = await stoppedRun();
      writeDataset(datasetPath, 6);
      await serve();
      await expectLater(
        resume(path),
        throwsA(
          isA<RunStartException>().having(
            (e) => e.reason,
            'reason',
            contains('dataset'),
          ),
        ),
      );
    });

    test('resume repairs a line cut off by a crash', () async {
      final path = await stoppedRun();
      File(
        path,
      ).writeAsStringSync('{"type":"conversation","ind', mode: FileMode.append);
      await serve();
      final done = await (await resume(path)).finished;
      expect(done.status, RunStatus.completed);
      final contents = await readRunFile(path);
      expect(contents.hasIncompleteTail, isFalse);
      expect(contents.conversations, hasLength(5));
    });

    test('resume refuses a run with nothing left to do', () async {
      writeDataset(datasetPath, 2);
      await serve();
      final path = (await (await start()).finished).let(
        (_) => run!.runFilePath!,
      );
      await expectLater(
        resume(path),
        throwsA(
          isA<RunStartException>().having(
            (e) => e.reason,
            'reason',
            contains('nothing left'),
          ),
        ),
      );
    });

    test('resume refuses a run that is in progress', () async {
      writeDataset(datasetPath, 3);
      await serve(wait: const Duration(milliseconds: 200));
      final r = await start();
      await expectLater(
        resume(r.runFilePath!),
        throwsA(
          isA<RunStartException>().having(
            (e) => e.reason,
            'reason',
            contains('in progress'),
          ),
        ),
      );
      r.stop();
      await r.finished;
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
