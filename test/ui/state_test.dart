// App state: runs list, active run (start / stop / resume, one at a time) and
// remembered form fields (spec 003 FR-003, FR-004, FR-006–FR-010, FR-014).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/run_file.dart';
import 'package:healthbench/core/settings.dart';
import 'package:healthbench/ui/state/providers.dart';
import 'package:healthbench/ui/state/run_controller.dart';
import 'package:healthbench/ui/state/runs_controller.dart';

import '../support/fake_openai_server.dart';
import '../support/fixtures.dart';

const _fast = ClientOptions(
  timeout: Duration(seconds: 5),
  maxRetries: 0,
  initialBackoff: Duration(milliseconds: 1),
);

void main() {
  late Directory dir;
  late ProviderContainer container;
  late FakeOpenAiServer server;
  var delay = Duration.zero;

  setUp(() async {
    dir = tempDir(addTearDown);
    delay = Duration.zero;
    server = await FakeOpenAiServer.start(
      (r, _) => r.isGraderCall
          ? FakeResponse.grade(met: true)
          : FakeResponse.reply('reply').withDelay(delay),
    );
    addTearDown(server.close);
    container = ProviderContainer(
      overrides: [
        storageDirectoryProvider.overrideWith((ref) async => dir.path),
        clientOptionsProvider.overrideWithValue(_fast),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    writeDataset('${dir.path}/data.jsonl', 3);
  });

  RunController controller() => container.read(runControllerProvider.notifier);

  Future<void> start() => controller().start(
    datasetPath: '${dir.path}/data.jsonl',
    limit: null,
    connection: ConnectionSettings(
      baseUrl: server.baseUrl.toString(),
      apiKey: 'sk-test',
    ),
    modelTest: ModelSettings(name: 'tested'),
    modelGrader: ModelSettings(name: 'grader'),
  );

  /// Waits until the active run has ended and the runs list was refreshed.
  Future<ActiveRunState> finished() async {
    final done = Completer<ActiveRunState>();
    final sub = container.listen(runControllerProvider, (_, next) {
      if (next.progress != null && !next.isRunning && !done.isCompleted) {
        done.complete(next);
      }
    }, fireImmediately: true);
    final state = await done.future.timeout(const Duration(seconds: 20));
    sub.close();
    // The controller refreshes the list after the run ends.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return state;
  }

  test('a run completes and appears in the runs list', () async {
    expect(await container.read(runsProvider.future), isEmpty);
    await start();
    final state = await finished();

    expect(state.progress!.status, RunStatus.completed);
    expect(state.progress!.done, 3);
    final runs = await container.read(runsProvider.future);
    expect(runs.single.isValid, isTrue);
    expect(runs.single.contents!.status, RunStatus.completed);
    expect(runs.single.path, state.runFilePath);
  });

  test('only one run at a time; stop, then continue it', () async {
    delay = const Duration(milliseconds: 150);
    await start();
    expect(controller().isActive, isTrue);
    await expectLater(start(), throwsStateError);

    controller().stop();
    final stopped = await finished();
    expect(stopped.progress!.status, RunStatus.stopped);
    expect(controller().isActive, isFalse);

    delay = Duration.zero;
    await controller().resume(
      runFilePath: stopped.runFilePath!,
      datasetPath: '${dir.path}/data.jsonl',
      apiKey: 'sk-test',
    );
    final resumed = await finished();
    expect(resumed.progress!.status, RunStatus.completed);
    expect(resumed.progress!.done, 3);
  });

  group('remembered form', () {
    test('round-trips the non-secret fields and never stores a key', () async {
      await saveRememberedForm(
        dir.path,
        const RememberedForm(
          baseUrl: 'https://api.example.com/v1',
          modelTest: 'm',
          effortTest: ReasoningEffort.high,
          modelGrader: 'g',
          limit: 25,
        ),
      );
      final text = File(formFileIn(dir.path)).readAsStringSync();
      expect(
        (jsonDecode(text) as Map<String, Object?>).keys,
        unorderedEquals([
          'baseUrl',
          'modelTest',
          'effortTest',
          'modelGrader',
          'effortGrader',
          'limit',
        ]),
      );
      final form = await container.read(rememberedFormProvider.future);
      expect(form.baseUrl, 'https://api.example.com/v1');
      expect(form.effortTest, ReasoningEffort.high);
      expect(form.limit, 25);
    });

    test('a corrupt file gives the defaults', () async {
      File(formFileIn(dir.path)).writeAsStringSync('{not json');
      final form = await container.read(rememberedFormProvider.future);
      expect(form.baseUrl, isEmpty);
      expect(form.limit, isNull);
    });
  });
}
