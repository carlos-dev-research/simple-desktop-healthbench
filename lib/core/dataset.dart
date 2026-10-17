/// HealthBench dataset records (healthbench.md §2; port of pygrader models.py)
/// and reading dataset files (spec 002 US1).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// Lines longer than this are rejected (research R12).
const int maxDatasetLineLength = 8 * 1024 * 1024;

/// A dataset file could not be read. [line] is 1-based (0 = the whole file).
class DatasetFormatException implements Exception {
  const DatasetFormatException(this.line, this.reason);

  final int line;
  final String reason;

  @override
  String toString() =>
      line > 0 ? 'Dataset line $line: $reason' : 'Dataset: $reason';
}

/// A HealthBench dataset file.
class Dataset {
  const Dataset({
    required this.fileName,
    required this.sha256,
    required this.conversations,
  });

  /// File name only, never the folder path (research R8).
  final String fileName;

  /// SHA-256 of the file's bytes, to recognise the same dataset later.
  final String sha256;
  final List<Conversation> conversations;

  /// The first [limit] conversations, or all when [limit] is null.
  List<Conversation> select(int? limit) {
    if (limit == null) return conversations;
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'Must be at least 1');
    }
    return conversations.take(limit).toList();
  }
}

/// Reads and validates a dataset file. Parsing runs on another isolate so the
/// caller stays responsive (NFR-003). Throws [DatasetFormatException].
Future<Dataset> readDataset(String path) async {
  final bytes = await File(path).readAsBytes();
  final digest = sha256.convert(bytes).toString();
  final conversations = await Isolate.run(() => parseDataset(bytes));
  return Dataset(
    fileName: fileNameOf(path),
    sha256: digest,
    conversations: conversations,
  );
}

/// The last component of [path], for `/` and `\` separators.
String fileNameOf(String path) => path.split(RegExp(r'[/\\]')).last;

/// Parses dataset bytes; every line must be valid or the whole read fails.
List<Conversation> parseDataset(List<int> bytes) {
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    throw const DatasetFormatException(0, 'file is not valid UTF-8');
  }
  final conversations = <Conversation>[];
  final seen = <String>{};
  final lines = const LineSplitter().convert(text);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    final number = i + 1;
    if (line.length > maxDatasetLineLength) {
      throw DatasetFormatException(number, 'line is too large');
    }
    final conversation = _parseRecord(line, number, conversations.length);
    if (!seen.add(conversation.promptId)) {
      throw DatasetFormatException(
        number,
        'duplicate prompt_id "${conversation.promptId}"',
      );
    }
    conversations.add(conversation);
  }
  if (conversations.isEmpty) {
    throw const DatasetFormatException(0, 'no conversations in file');
  }
  return conversations;
}

Conversation _parseRecord(String line, int number, int index) {
  Never fail(String reason) => throw DatasetFormatException(number, reason);

  final Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException {
    fail('not valid JSON');
  }
  if (decoded is! Map<String, Object?>) fail('not a JSON object');

  final promptId = decoded['prompt_id'];
  if (promptId is! String || promptId.isEmpty) fail('missing prompt_id');

  final rawPrompt = decoded['prompt'];
  if (rawPrompt is! List<Object?> || rawPrompt.isEmpty) {
    fail('prompt must be a non-empty list of messages');
  }
  final prompt = [
    for (final m in rawPrompt)
      if (m case {'role': final String role, 'content': final String content})
        Message(role: role, content: content)
      else
        fail('prompt messages need a string role and content'),
  ];

  final rawRubrics = decoded['rubrics'];
  if (rawRubrics is! List<Object?> || rawRubrics.isEmpty) {
    fail('rubrics must be a non-empty list');
  }
  final criteria = [for (final r in rawRubrics) _parseCriterion(r, fail)];

  return Conversation(
    index: index,
    promptId: promptId,
    prompt: prompt,
    criteria: criteria,
    exampleTags: _stringList(decoded['example_tags'], 'example_tags', fail),
    idealCompletionsData: switch (decoded['ideal_completions_data']) {
      null => null,
      final Map<String, Object?> data => data,
      _ => fail('ideal_completions_data must be an object or null'),
    },
    canary: switch (decoded['canary']) {
      null => null,
      final String text => text,
      _ => fail('canary must be text'),
    },
  );
}

Criterion _parseCriterion(Object? raw, Never Function(String) fail) {
  var value = raw;
  if (value is String) {
    // Criteria may be stored as JSON text (pygrader Rubric accepts both).
    try {
      value = jsonDecode(value);
    } on FormatException {
      fail('rubric text is not valid JSON');
    }
  }
  if (value is! Map<String, Object?>) fail('rubric is not an object');
  final text = value['criterion'];
  if (text is! String || text.trim().isEmpty) {
    fail('rubric criterion must be non-empty text');
  }
  final points = switch (value['points']) {
    final int p => p,
    final double p when p == p.roundToDouble() && p.isFinite => p.toInt(),
    _ => fail('rubric points must be a whole number'),
  };
  return Criterion(
    text: text,
    points: points,
    tags: _stringList(value['tags'], 'rubric tags', fail),
  );
}

List<String> _stringList(
  Object? value,
  String name,
  Never Function(String) fail,
) {
  if (value == null) return const [];
  if (value is List<Object?> && value.every((t) => t is String)) {
    return value.cast<String>();
  }
  fail('$name must be a list of strings');
}

/// One message of a conversation.
class Message {
  const Message({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// One physician-written rubric criterion. [points] may be negative.
class Criterion {
  const Criterion({
    required this.text,
    required this.points,
    required this.tags,
  });

  final String text;
  final int points;
  final List<String> tags;
}

/// One HealthBench conversation and the criteria for grading the next reply.
class Conversation {
  const Conversation({
    required this.index,
    required this.promptId,
    required this.prompt,
    required this.criteria,
    required this.exampleTags,
    this.idealCompletionsData,
    this.canary,
  });

  /// 0-based position among the dataset's conversations.
  final int index;
  final String promptId;
  final List<Message> prompt;
  final List<Criterion> criteria;
  final List<String> exampleTags;

  /// Optional reference answer data, kept as raw JSON and not interpreted.
  final Object? idealCompletionsData;

  /// The dataset's contamination marker, kept so a run file holds the whole
  /// record (spec 002 FR-018).
  final String? canary;
}
