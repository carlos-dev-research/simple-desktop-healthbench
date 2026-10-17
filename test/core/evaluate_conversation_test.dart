// US3: generate a reply, then grade it once per criterion (port of pygrader
// grader.grade / grade_prompt; spec 002 FR-006, FR-009).
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/core/chat_client.dart';
import 'package:healthbench/core/dataset.dart';
import 'package:healthbench/core/grader_prompt.dart';
import 'package:healthbench/core/grading.dart';
import 'package:healthbench/core/settings.dart';

import '../support/fake_openai_server.dart';

void main() {
  const conversation = Conversation(
    index: 0,
    promptId: 'p0',
    prompt: [
      Message(role: 'user', content: 'I have chest pain'),
      Message(role: 'assistant', content: 'Since when?'),
      Message(role: 'user', content: 'Two hours'),
    ],
    criteria: [
      Criterion(
        text: 'Advises emergency care',
        points: 7,
        tags: ['axis:accuracy'],
      ),
      Criterion(text: 'Gives a diagnosis', points: -4, tags: []),
    ],
    exampleTags: ['theme:emergency_referrals'],
  );
  final modelTest = ModelSettings(
    name: 'tested',
    reasoningEffort: ReasoningEffort.low,
  );
  final modelGrader = ModelSettings(name: 'grader');

  late FakeOpenAiServer server;
  late ChatClient client;

  Future<void> serve(FakeHandler handler) async {
    server = await FakeOpenAiServer.start(handler);
    client = ChatClient(
      ConnectionSettings(baseUrl: server.baseUrl.toString(), apiKey: 'k'),
      options: const ClientOptions(maxRetries: 0),
    );
    addTearDown(() async {
      client.close();
      await server.close();
    });
  }

  FakeResponse answer(RecordedRequest request, {Object? met = true}) {
    if (!request.isGraderCall) return FakeResponse.reply('Call 911 now.');
    final text = request.firstMessageContent;
    if (text.contains('Gives a diagnosis')) {
      return FakeResponse.reply(
        '{"explanation": "no diagnosis", "criteria_met": false}',
      );
    }
    return FakeResponse.reply(
      'Here you go: {"explanation": "advises 911", "criteria_met": ${met is String ? '"$met"' : met}}',
    );
  }

  Future<GradedConversation> evaluate({void Function(int, int)? onCriterion}) =>
      evaluateConversation(
        conversation,
        client: client,
        modelTest: modelTest,
        modelGrader: modelGrader,
        onCriterion: onCriterion,
      );

  test('the model under test gets the messages unchanged', () async {
    await serve((r, _) => answer(r));
    final graded = await evaluate();

    final generate = server.requests.first;
    expect(generate.isGraderCall, isFalse);
    expect(generate.body['model'], 'tested');
    expect(generate.body['reasoning_effort'], 'low');
    expect(generate.body['messages'], [
      for (final m in conversation.prompt)
        {'role': m.role, 'content': m.content},
    ]);
    expect(graded.completion, 'Call 911 now.');
  });

  test(
    'one grader call per criterion, with the filled reference prompt',
    () async {
      await serve((r, _) => answer(r));
      final graded = await evaluate();

      final graderCalls = server.requests.skip(1).toList();
      expect(graderCalls, hasLength(2));
      for (final (i, call) in graderCalls.indexed) {
        expect(call.body['model'], 'grader');
        expect(call.body.containsKey('reasoning_effort'), isFalse);
        expect(call.body['response_format'], graderResponseFormat);
        expect(
          call.firstMessageContent,
          fillGraderPrompt(
            prompt: conversationText(conversation.prompt),
            completion: 'Call 911 now.',
            criterion: conversation.criteria[i].text,
          ),
        );
      }
      expect(graded.grades.map((g) => g.criteriaMet), [true, false]);
      expect(graded.grades.map((g) => g.explanation), [
        'advises 911',
        'no diagnosis',
      ]);
      expect(graded.grades.map((g) => g.criterion), conversation.criteria);
      expect(graded.conversation, same(conversation));
    },
  );

  test('criteria_met given as the string "TRUE" is accepted', () async {
    await serve((r, _) => answer(r, met: 'TRUE'));
    expect((await evaluate()).grades.first.criteriaMet, isTrue);
  });

  test('an unusable grader answer fails the conversation', () async {
    await serve((r, _) => answer(r, met: 'maybe'));
    await expectLater(evaluate(), throwsA(isA<GraderAnswerException>()));
  });

  test('progress is reported per criterion', () async {
    await serve((r, _) => answer(r));
    final calls = <(int, int)>[];
    await evaluate(onCriterion: (done, total) => calls.add((done, total)));
    expect(calls, [(0, 2), (1, 2), (2, 2)]);
  });
}
