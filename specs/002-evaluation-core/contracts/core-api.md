# Contract: core API (Dart, `lib/core/`)

Public surface used by later features (003 UI, 004 run-file management). Pure Dart.
Names are binding. Private helpers are free.

```dart
// dataset.dart ---------------------------------------------------------------
class Message   { final String role; final String content; }
class Criterion { final String text; final int points; final List<String> tags; }
class Conversation {
  final int index; final String promptId; final List<Message> prompt;
  final List<Criterion> criteria; final List<String> exampleTags;
  final Object? idealCompletionsData;   // kept as raw JSON, not interpreted
}
class Dataset {
  final String fileName; final String sha256;
  final List<Conversation> conversations;   // all conversations in the file
  List<Conversation> select(int? limit);    // the first `limit` (all if null)
}
class DatasetFormatException implements Exception { final int line; final String reason; }
Future<Dataset> readDataset(String path);   // parses off the caller's isolate

// settings.dart --------------------------------------------------------------
enum ReasoningEffort { none, low, medium, high }
class ModelSettings { final String name; final ReasoningEffort reasoningEffort; }
class ConnectionSettings {
  final Uri baseUrl;                       // validated (run-file rule RF-8)
  final String apiKey;                     // memory only; toString() never shows it
}
class ClientOptions {                       // defaults = spec FR-007
  final Duration timeout;                   // 180 s
  final int maxRetries;                     // 4
  final Duration initialBackoff;            // 0.5 s
  final Duration maxBackoff;                // 8 s
}

// chat_client.dart -----------------------------------------------------------
class ChatClient {
  ChatClient(ConnectionSettings connection, {ClientOptions options, http.Client? httpClient});
  Future<String> complete({required ModelSettings model, required List<Map<String, String>> messages,
                           Map<String, Object?>? responseFormat});
  void close();
}
sealed class ChatError implements Exception { String get message; bool get isFatal; }
// AuthenticationError, PermissionDeniedError, NotFoundError (fatal);
// TransientError, RequestError, EmptyReplyError, BadResponseError

// grading.dart ---------------------------------------------------------------
const String graderPromptId = 'pygrader-GRADER.md';
String get graderPromptSha256;
class Grade { final Criterion criterion; final bool criteriaMet; final String explanation; }
class GradedConversation { final Conversation conversation; final String completion;
                           final List<Grade> grades; final DateTime gradedAt; }
Map<String, Object?> extractFirstJsonObject(String text);  // throws GraderAnswerException
Future<GradedConversation> evaluateConversation(Conversation c, {required ChatClient client,
    required ModelSettings modelTest, required ModelSettings modelGrader,
    void Function(int done, int total)? onCriterion});

// scoring.dart ---------------------------------------------------------------
enum CriterionOutcome { earned, missed, penalty, avoided }
CriterionOutcome outcomeOf(Grade g);
double? conversationScore(Iterable<Grade> grades);     // unclipped; null if no positive points
double runScore(Iterable<double?> conversationScores); // mean of non-null values, clipped to [0, 1]; 0 if none

// run_file.dart --------------------------------------------------------------
enum RunStatus { running, stopped, completed, failed, interrupted }
class RunHeader { /* fields of the header line */ }
class RunFileContents { final RunHeader header; final List<GradedConversation> conversations;
                        final RunStatus status; final double? score; final String? failureReason; }
class RunFileFormatException implements Exception { final int? line; final String reason; }
bool isRunFileName(String fileName);
Future<RunFileContents> readRunFile(String path);      // full validation (RF-1 … RF-9)

// runner.dart ----------------------------------------------------------------
class RunProgress {
  final String runId; final RunStatus status; final bool stopRequested;
  final int total, done, failed;                       // done counts lines in the file (including earlier sessions)
  final int criterionDone, criterionTotal;
  final double? score; final List<String> recentErrors; // at most 10, key-redacted
  final Duration elapsed;
}
class EvaluationRun {
  static Future<EvaluationRun> start({required String runsDirectory, required String datasetPath,
      int? limit, required ConnectionSettings connection, required ModelSettings modelTest,
      required ModelSettings modelGrader, ClientOptions options, http.Client? httpClient});
  static Future<EvaluationRun> resume({required String runFilePath, required String datasetPath,
      required String apiKey, ClientOptions options, http.Client? httpClient});
  Stream<RunProgress> get progress;   // broadcast; emits after every criterion and conversation
  void stop();                        // takes effect after the current conversation
  Future<RunProgress> get finished;   // final progress; status completed | stopped | failed
  String? get runFilePath;            // null once a run with nothing graded has been removed (FR-021)
}
class RunStartException implements Exception { final String reason; } // dataset changed, already active, …
```
