// FR-008 / Constitution III: the API key never reaches a file, a progress
// report or an error message, even when the server echoes it back.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/run_file.dart';
import 'package:healthbench/core/runner.dart';
import 'package:healthbench/core/settings.dart';

import '../support/fake_openai_server.dart';
import '../support/fixtures.dart';

const _key = 'sk-live-THIS-MUST-NEVER-BE-WRITTEN-42';

void main() {
  test('a run where the server echoes the key leaks it nowhere', () async {
    final dir = tempDir(addTearDown);
    final datasetPath = '${dir.path}/data.jsonl';
    writeDataset(datasetPath, 4);

    // p1: rejected with the key in the message (skipped); p2: rejected as
    // unauthorised with the key in the message (fatal); p0 succeeds.
    final server = await FakeOpenAiServer.start((r, _) {
      final key = r.headers['authorization']!.replaceFirst('Bearer ', '');
      final text = r.firstMessageContent;
      if (text.contains('Question for p1')) {
        return FakeResponse.error(400, 'Bad request for key $key');
      }
      if (text.contains('Question for p2')) {
        return FakeResponse.error(401, 'Incorrect API key provided: $key');
      }
      return r.isGraderCall
          ? FakeResponse.grade(met: true, explanation: 'fine')
          : FakeResponse.reply('reply');
    });
    addTearDown(server.close);

    final run = await EvaluationRun.start(
      runsDirectory: '${dir.path}/runs',
      datasetPath: datasetPath,
      connection: ConnectionSettings(
        baseUrl: server.baseUrl.toString(),
        apiKey: _key,
      ),
      modelTest: ModelSettings(name: 'm'),
      modelGrader: ModelSettings(name: 'g'),
      options: const ClientOptions(maxRetries: 0),
    );
    final events = <RunProgress>[];
    run.progress.listen(events.add);
    final done = await run.finished;

    expect(done.status, RunStatus.failed);
    expect(done.recentErrors, hasLength(2)); // the key *was* echoed twice

    final texts = [
      for (final e in [...events, done]) ...[
        ...e.recentErrors,
        ?e.failureReason,
      ],
    ];
    expect(texts, isNotEmpty);
    for (final text in texts) {
      expect(text, isNot(contains(_key)));
    }
    expect(texts.any((t) => t.contains('***')), isTrue);

    final fileText = File(run.runFilePath!).readAsStringSync();
    expect(fileText, isNot(contains(_key)));
    expect(fileText, contains('Incorrect API key provided: ***'));
  });
}
