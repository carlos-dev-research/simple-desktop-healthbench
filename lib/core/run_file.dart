/// The run file: one append-only JSON-lines file per run
/// (contracts/run-file.md; spec 002 FR-017–FR-020; research R6, R7, R10).
library;

import 'dart:convert';
import 'dart:io';

import 'dataset.dart';
import 'grading.dart';
import 'scoring.dart';
import 'settings.dart';

/// Run-file names: `healthbench-run-YYYYMMDD-HHMMSS[-N].jsonl`.
final RegExp runFileNamePattern = RegExp(
  r'^healthbench-run-\d{8}-\d{6}(-[1-9]\d*)?\.jsonl$',
);

/// Lines longer than this are rejected (research R12).
const int maxRunFileLineLength = 16 * 1024 * 1024;

bool isRunFileName(String fileName) => runFileNamePattern.hasMatch(fileName);

String _two(int n) => n.toString().padLeft(2, '0');

/// The run id (file name without `.jsonl`) for a run started at [time],
/// in local time.
String runIdForTime(DateTime time) {
  final t = time.toLocal();
  return 'healthbench-run-${t.year}${_two(t.month)}${_two(t.day)}'
      '-${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';
}

/// ISO-8601 in local time with the UTC offset, e.g.
/// `2026-10-17T16:30:00.000-05:00`.
String formatTimestamp(DateTime time) {
  final t = time.toLocal();
  final offset = t.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  return '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}'
      'T${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}'
      '.${t.millisecond.toString().padLeft(3, '0')}'
      '$sign${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
}

/// Status of a run. [interrupted] is derived when reading, never written.
enum RunStatus { running, stopped, completed, failed, interrupted }

/// The dataset a run evaluates, identified without any folder path.
class DatasetRef {
  const DatasetRef({
    required this.fileName,
    required this.sha256,
    required this.conversationCount,
    required this.limit,
  });

  final String fileName;
  final String sha256;
  final int conversationCount;

  /// Only the first [limit] conversations are evaluated; `null` = all.
  final int? limit;

  /// How many conversations the run covers.
  int get selectedCount =>
      limit == null || limit! > conversationCount ? conversationCount : limit!;
}

/// The run settings written on the first line. Never contains the API key.
class RunHeader {
  const RunHeader({
    required this.runId,
    required this.app,
    required this.appVersion,
    required this.createdAt,
    required this.baseUrl,
    required this.modelTest,
    required this.modelGrader,
    required this.temperature,
    required this.graderPromptId,
    required this.graderPromptSha256,
    required this.dataset,
  });

  final String runId;
  final String app;
  final String appVersion;
  final DateTime createdAt;
  final Uri baseUrl;
  final ModelSettings modelTest;
  final ModelSettings modelGrader;
  final double temperature;
  final String graderPromptId;
  final String graderPromptSha256;
  final DatasetRef dataset;
}

/// One `status` line.
class StatusEntry {
  const StatusEntry({
    required this.status,
    required this.at,
    required this.graded,
    this.score,
    this.reason,
  });

  final RunStatus status;
  final DateTime at;

  /// Conversation lines in the file when this status was written.
  final int graded;
  final double? score;
  final String? reason;
}

// ---------------------------------------------------------------- encoding

Map<String, Object?> _modelJson(ModelSettings m) => {
  'name': m.name,
  'reasoningEffort': m.reasoningEffort.name,
};

Map<String, Object?> headerJson(RunHeader h) => {
  'type': 'header',
  'runId': h.runId,
  'app': h.app,
  'appVersion': h.appVersion,
  'createdAt': formatTimestamp(h.createdAt),
  'baseUrl': h.baseUrl.toString(),
  'modelTest': _modelJson(h.modelTest),
  'modelGrader': _modelJson(h.modelGrader),
  'temperature': h.temperature,
  'graderPrompt': {'id': h.graderPromptId, 'sha256': h.graderPromptSha256},
  'dataset': {
    'fileName': h.dataset.fileName,
    'sha256': h.dataset.sha256,
    'conversationCount': h.dataset.conversationCount,
    'limit': h.dataset.limit,
  },
};

Map<String, Object?> statusJson(StatusEntry s) {
  if (s.status == RunStatus.interrupted) {
    throw ArgumentError('"interrupted" is derived and never written');
  }
  return {
    'type': 'status',
    'status': s.status.name,
    'at': formatTimestamp(s.at),
    'graded': s.graded,
    'score': s.score,
    'reason': s.reason,
  };
}

Map<String, Object?> conversationJson(GradedConversation g) => {
  'type': 'conversation',
  'index': g.conversation.index,
  'promptId': g.conversation.promptId,
  'exampleTags': g.conversation.exampleTags,
  'prompt': [for (final m in g.conversation.prompt) m.toJson()],
  'completion': g.completion,
  'rubrics': [
    for (final grade in g.grades)
      {
        'criterion': grade.criterion.text,
        'points': grade.criterion.points,
        'tags': grade.criterion.tags,
        'criteriaMet': grade.criteriaMet,
        'explanation': grade.explanation,
      },
  ],
  'gradedAt': formatTimestamp(g.gradedAt),
};

// ---------------------------------------------------------------- active runs

final Set<String> _activeRuns = {};

String _key(String path) => File(path).absolute.path;

/// Whether a run file is being written by a run in this app (research R14).
bool isRunActive(String path) => _activeRuns.contains(_key(path));

/// Marks [path] active; false if it already was.
bool markRunActive(String path) => _activeRuns.add(_key(path));

void markRunInactive(String path) => _activeRuns.remove(_key(path));

// ---------------------------------------------------------------- reading

/// A run file could not be used. [line] is 1-based, or null for the file.
class RunFileFormatException implements Exception {
  const RunFileFormatException(this.line, this.reason);

  final int? line;
  final String reason;

  @override
  String toString() =>
      line == null ? 'Run file: $reason' : 'Run file line $line: $reason';
}

/// A validated run file.
class RunFileContents {
  const RunFileContents({
    required this.path,
    required this.header,
    required this.conversations,
    required this.statusEntries,
    required this.status,
    required this.score,
    required this.hasIncompleteTail,
    required this.needsNewline,
    required this.validLength,
  });

  final String path;
  final RunHeader header;
  final List<GradedConversation> conversations;
  final List<StatusEntry> statusEntries;

  /// The last status line, or [RunStatus.interrupted] if that says running
  /// and the run is not active in this app.
  final RunStatus status;

  /// Recomputed run score over all graded conversations.
  final double score;

  /// The last line was cut off (ignored; truncated before appending).
  final bool hasIncompleteTail;

  /// The last line is complete but has no trailing newline.
  final bool needsNewline;

  /// Byte length of the file up to and including the last complete line.
  final int validLength;

  String? get failureReason =>
      status == RunStatus.failed ? statusEntries.last.reason : null;

  Set<String> get doneIds => {
    for (final c in conversations) c.conversation.promptId,
  };
}

/// Reads and fully validates a run file (RF-1 … RF-9).
/// Throws [RunFileFormatException].
Future<RunFileContents> readRunFile(String path) async {
  final name = fileNameOf(path);
  if (!isRunFileName(name)) {
    throw const RunFileFormatException(
      null,
      'file name does not match healthbench-run-YYYYMMDD-HHMMSS.jsonl',
    );
  }
  final bytes = await File(path).readAsBytes();
  final lastNewline = bytes.lastIndexOf(0x0A);
  var validLength = lastNewline + 1;
  var hasIncompleteTail = false;
  var needsNewline = false;

  final String text;
  try {
    text = utf8.decode(bytes.sublist(0, validLength));
  } on FormatException {
    throw const RunFileFormatException(null, 'file is not valid UTF-8');
  }
  final lines = text.isEmpty
      ? <String>[]
      : text.substring(0, text.length - 1).split('\n');

  if (validLength < bytes.length) {
    // Text after the last newline: a complete line without its newline, or
    // a line cut off by a crash (RF-9).
    String? tail;
    try {
      tail = utf8.decode(bytes.sublist(validLength));
      if (jsonDecode(tail) is! Map<String, Object?>) tail = null;
    } on FormatException {
      tail = null;
    }
    if (tail == null) {
      hasIncompleteTail = true;
    } else {
      lines.add(tail);
      needsNewline = true;
      validLength = bytes.length;
    }
  }

  if (lines.every((l) => l.trim().isEmpty)) {
    throw const RunFileFormatException(null, 'missing header');
  }

  final reader = _Reader(name.substring(0, name.length - '.jsonl'.length));
  for (var i = 0; i < lines.length; i++) {
    reader.readLine(lines[i], i + 1);
  }
  return reader.finish(
    path: path,
    hasIncompleteTail: hasIncompleteTail,
    needsNewline: needsNewline,
    validLength: validLength,
  );
}

final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

class _Reader {
  _Reader(this.runId);

  final String runId;
  RunHeader? header;
  final conversations = <GradedConversation>[];
  final statuses = <StatusEntry>[];
  final promptIds = <String>{};
  final indexes = <int>{};

  void readLine(String line, int number) {
    if (line.length > maxRunFileLineLength) {
      throw RunFileFormatException(number, 'line is too large');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      throw RunFileFormatException(number, 'not valid JSON');
    }
    if (decoded is! Map<String, Object?>) {
      throw RunFileFormatException(number, 'not a JSON object');
    }
    final type = decoded['type'];
    if (number == 1 && type != 'header') {
      throw const RunFileFormatException(
        1,
        'the first line must be the header',
      );
    }
    switch (type) {
      case 'header':
        if (number != 1) {
          throw RunFileFormatException(number, 'only line 1 may be a header');
        }
        header = _header(_Fields(decoded, 'header', number));
      case 'status':
        statuses.add(_status(_Fields(decoded, 'status', number)));
      case 'conversation':
        conversations.add(
          _conversation(_Fields(decoded, 'conversation', number)),
        );
      default:
        throw RunFileFormatException(number, 'unknown line type "$type"');
    }
  }

  RunHeader _header(_Fields f) {
    f.keys(const {
      'type', 'runId', 'app', 'appVersion', 'createdAt', 'baseUrl', //
      'modelTest', 'modelGrader', 'temperature', 'graderPrompt', 'dataset',
    });
    final id = f.string('runId');
    if (id != runId) {
      f.fail('header runId "$id" does not match the file name');
    }
    final Uri baseUrl;
    try {
      baseUrl = ConnectionSettings.parseBaseUrl(f.string('baseUrl'));
    } on ArgumentError catch (e) {
      f.fail('baseUrl: ${e.message}');
    }
    final prompt = f.object('graderPrompt')..keys(const {'id', 'sha256'});
    final data = f.object('dataset')
      ..keys(const {'fileName', 'sha256', 'conversationCount', 'limit'});
    return RunHeader(
      runId: id,
      app: f.string('app'),
      appVersion: f.string('appVersion'),
      createdAt: f.timestamp('createdAt'),
      baseUrl: baseUrl,
      modelTest: _model(f.object('modelTest')),
      modelGrader: _model(f.object('modelGrader')),
      temperature: f.number('temperature'),
      graderPromptId: prompt.string('id'),
      graderPromptSha256: prompt.hash('sha256'),
      dataset: DatasetRef(
        fileName: data.string('fileName'),
        sha256: data.hash('sha256'),
        conversationCount: data.integer('conversationCount', min: 1),
        limit: data.optionalInteger('limit', min: 1),
      ),
    );
  }

  ModelSettings _model(_Fields f) {
    f.keys(const {'name', 'reasoningEffort'});
    final effort = f.string('reasoningEffort');
    try {
      return ModelSettings(
        name: f.string('name'),
        reasoningEffort: ReasoningEffort.parse(effort),
      );
    } on FormatException {
      f.fail('field "reasoningEffort" has unknown value "$effort"');
    }
  }

  StatusEntry _status(_Fields f) {
    f.keys(const {'type', 'status', 'at', 'graded', 'score', 'reason'});
    final name = f.string('status');
    final status = switch (name) {
      'running' => RunStatus.running,
      'stopped' => RunStatus.stopped,
      'completed' => RunStatus.completed,
      'failed' => RunStatus.failed,
      _ => f.fail('field "status" has unknown value "$name"'),
    };
    final graded = f.integer('graded', min: 0);
    if (graded != conversations.length) {
      f.fail(
        'field "graded" is $graded but ${conversations.length} '
        'conversations precede it',
      );
    }
    final score = f.optionalNumber('score');
    if (status == RunStatus.completed && score == null) {
      f.fail('a completed status needs a score');
    }
    if (score != null) {
      final expected = _runScore();
      if ((score - expected).abs() > 1e-9) {
        f.fail('field "score" is $score but the conversations give $expected');
      }
    }
    final reason = f.optionalString('reason');
    if (status == RunStatus.failed && (reason == null || reason.isEmpty)) {
      f.fail('a failed status needs a reason');
    }
    if (status != RunStatus.failed && reason != null) {
      f.fail('only a failed status has a reason');
    }
    return StatusEntry(
      status: status,
      at: f.timestamp('at'),
      graded: graded,
      score: score,
      reason: reason,
    );
  }

  GradedConversation _conversation(_Fields f) {
    f.keys(const {
      'type', 'index', 'promptId', 'exampleTags', 'prompt', 'completion', //
      'rubrics', 'gradedAt',
    });
    final dataset = header!.dataset;
    final index = f.integer('index', min: 0);
    if (index >= dataset.selectedCount) {
      f.fail(
        'field "index" $index is outside the selected '
        '${dataset.selectedCount} conversations',
      );
    }
    final promptId = f.string('promptId');
    if (!promptIds.add(promptId)) f.fail('duplicate promptId "$promptId"');
    if (!indexes.add(index)) f.fail('duplicate index $index');

    final prompt = [
      for (final m in f.objects('prompt'))
        (m..keys(const {'role', 'content'})).let(
          (m) => Message(role: m.string('role'), content: m.string('content')),
        ),
    ];
    final grades = <Grade>[];
    for (final r in f.objects('rubrics')) {
      r.keys(const {
        'criterion',
        'points',
        'tags',
        'criteriaMet',
        'explanation',
      });
      grades.add(
        Grade(
          criterion: Criterion(
            text: r.string('criterion'),
            points: r.integer('points'),
            tags: r.strings('tags'),
          ),
          criteriaMet: r.boolean('criteriaMet'),
          explanation: r.string('explanation', allowEmpty: true),
        ),
      );
    }
    if (grades.isEmpty) f.fail('field "rubrics" is empty');
    return GradedConversation(
      conversation: Conversation(
        index: index,
        promptId: promptId,
        prompt: prompt,
        criteria: [for (final g in grades) g.criterion],
        exampleTags: f.strings('exampleTags'),
      ),
      completion: f.string('completion', allowEmpty: true),
      grades: grades,
      gradedAt: f.timestamp('gradedAt'),
    );
  }

  double _runScore() =>
      runScore(conversations.map((c) => conversationScore(c.grades)));

  RunFileContents finish({
    required String path,
    required bool hasIncompleteTail,
    required bool needsNewline,
    required int validLength,
  }) {
    if (statuses.isEmpty) {
      throw const RunFileFormatException(null, 'no status line');
    }
    var status = statuses.last.status;
    if (status == RunStatus.running && !isRunActive(path)) {
      status = RunStatus.interrupted;
    }
    return RunFileContents(
      path: path,
      header: header!,
      conversations: conversations,
      statusEntries: statuses,
      status: status,
      score: _runScore(),
      hasIncompleteTail: hasIncompleteTail,
      needsNewline: needsNewline,
      validLength: validLength,
    );
  }
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Typed, strict access to one JSON object of a run-file line.
class _Fields {
  _Fields(this.map, this.what, this.line);

  final Map<String, Object?> map;
  final String what;
  final int line;

  Never fail(String reason) =>
      throw RunFileFormatException(line, '$what: $reason');

  void keys(Set<String> allowed) {
    for (final key in map.keys) {
      if (!allowed.contains(key)) fail('unexpected field "$key"');
    }
    for (final key in allowed) {
      if (!map.containsKey(key)) fail('missing field "$key"');
    }
  }

  String string(String key, {bool allowEmpty = false}) {
    final value = map[key];
    if (value is! String || (!allowEmpty && value.isEmpty)) {
      fail('field "$key" must be ${allowEmpty ? 'a' : 'a non-empty'} string');
    }
    return value;
  }

  String? optionalString(String key) =>
      map[key] == null ? null : string(key, allowEmpty: true);

  String hash(String key) {
    final value = string(key);
    if (!_sha256.hasMatch(value)) {
      fail('field "$key" must be a sha256 (64 lowercase hex characters)');
    }
    return value;
  }

  int integer(String key, {int? min}) {
    final value = map[key];
    if (value is! int) fail('field "$key" must be an integer');
    if (min != null && value < min) fail('field "$key" must be at least $min');
    return value;
  }

  int? optionalInteger(String key, {int? min}) =>
      map[key] == null ? null : integer(key, min: min);

  double number(String key) {
    final value = map[key];
    if (value is! num) fail('field "$key" must be a number');
    return value.toDouble();
  }

  double? optionalNumber(String key) => map[key] == null ? null : number(key);

  bool boolean(String key) {
    final value = map[key];
    if (value is! bool) fail('field "$key" must be true or false');
    return value;
  }

  DateTime timestamp(String key) {
    final value = string(key);
    final parsed = value.contains('T') ? DateTime.tryParse(value) : null;
    if (parsed == null) fail('field "$key" must be an ISO-8601 timestamp');
    return parsed;
  }

  List<String> strings(String key) {
    final value = map[key];
    if (value is! List<Object?> || !value.every((v) => v is String)) {
      fail('field "$key" must be a list of strings');
    }
    return value.cast<String>();
  }

  _Fields object(String key) {
    final value = map[key];
    if (value is! Map<String, Object?>) fail('field "$key" must be an object');
    return _Fields(value, '$what.$key', line);
  }

  List<_Fields> objects(String key) {
    final value = map[key];
    if (value is! List<Object?>) fail('field "$key" must be a list');
    return [
      for (final (i, item) in value.indexed)
        if (item is Map<String, Object?>)
          _Fields(item, '$what.$key[$i]', line)
        else
          fail('field "$key" must contain objects'),
    ];
  }
}

// ---------------------------------------------------------------- writing

/// Appends lines to a run file, flushing each one to disk before returning
/// (NFR-004).
class RunFileWriter {
  RunFileWriter._(this.path, this._file);

  final String path;
  final RandomAccessFile _file;

  /// The run id: the file name without `.jsonl`.
  String get runId {
    final name = fileNameOf(path);
    return name.substring(0, name.length - '.jsonl'.length);
  }

  /// Creates a new, empty run file named after [startedAt] in [directory],
  /// adding `-2`, `-3`, … if that name is taken.
  static Future<RunFileWriter> createNew(
    String directory,
    DateTime startedAt,
  ) async {
    await Directory(directory).create(recursive: true);
    final base = runIdForTime(startedAt);
    for (var n = 1; ; n++) {
      final name = n == 1 ? '$base.jsonl' : '$base-$n.jsonl';
      final file = File('$directory${Platform.pathSeparator}$name');
      try {
        await file.create(exclusive: true);
      } on FileSystemException {
        if (await file.exists()) continue;
        rethrow;
      }
      return RunFileWriter._(file.path, await file.open(mode: FileMode.append));
    }
  }

  /// Opens an existing, validated run file for appending: an incomplete last
  /// line is truncated, and a missing final newline is added (RF-9).
  static Future<RunFileWriter> reopen(RunFileContents contents) async {
    final file = await File(contents.path).open(mode: FileMode.append);
    if (contents.hasIncompleteTail) {
      await file.truncate(contents.validLength);
    }
    await file.setPosition(await file.length());
    if (contents.needsNewline) {
      await file.writeString('\n');
      await file.flush();
    }
    return RunFileWriter._(contents.path, file);
  }

  Future<void> write(Map<String, Object?> line) async {
    await _file.writeString('${jsonEncode(line)}\n');
    await _file.flush();
  }

  Future<void> close() => _file.close();
}
