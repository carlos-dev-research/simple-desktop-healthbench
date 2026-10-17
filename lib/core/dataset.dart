/// HealthBench dataset records (healthbench.md §2; port of pygrader models.py).
library;

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
  });

  /// 0-based position among the dataset's conversations.
  final int index;
  final String promptId;
  final List<Message> prompt;
  final List<Criterion> criteria;
  final List<String> exampleTags;

  /// Optional reference answer data, kept as raw JSON and not interpreted.
  final Object? idealCompletionsData;
}
