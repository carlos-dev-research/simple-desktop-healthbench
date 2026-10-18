/// The numbers the results views show for a run (spec 003 FR-011, FR-012;
/// ported from the reference dashboard's renderStats, renderHistogram and
/// matches).
library;

import 'grading.dart';
import 'run_file.dart';
import 'scoring.dart';
import 'statistics.dart' as stats;

/// Histogram bin labels: below 0, then ten bins of 0.1 from 0 to 1.
const List<String> histogramLabels = [
  '<0', '0.0', '0.1', '0.2', '0.3', '0.4', '0.5', '0.6', '0.7', '0.8', '0.9', //
];

/// Counts of conversation scores per [histogramLabels] bin. A score of 1.0
/// falls in the last bin; conversations without a score are not counted.
List<int> histogramBins(Iterable<double?> scores) {
  final counts = List<int>.filled(histogramLabels.length, 0);
  for (final score in scores) {
    if (score == null) continue;
    final bin = score < 0 ? 0 : 1 + (score * 10).floor().clamp(0, 9);
    counts[bin]++;
  }
  return counts;
}

/// One conversation as the results list shows it.
class ConversationRow {
  ConversationRow(this.graded)
    : score = conversationScore(graded.grades),
      earned = graded.grades
          .where((g) => g.criteriaMet)
          .fold(0, (sum, g) => sum + g.criterion.points),
      possible = graded.grades
          .where((g) => g.criterion.points > 0)
          .fold(0, (sum, g) => sum + g.criterion.points);

  final GradedConversation graded;
  final double? score;
  final int earned;
  final int possible;

  int get index => graded.conversation.index;

  /// The last user message, as a one-line preview.
  String get preview {
    final prompt = graded.conversation.prompt;
    if (prompt.isEmpty) return '';
    final user = prompt.lastWhere(
      (m) => m.role == 'user',
      orElse: () => prompt.last,
    );
    return user.content.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  late final String _searchText = [
    for (final m in graded.conversation.prompt) m.content,
    graded.completion,
    for (final g in graded.grades) '${g.criterion.text}\n${g.explanation}',
  ].join('\n').toLowerCase();

  /// Case-insensitive search in the messages, the reply, the criteria and
  /// the grader's explanations.
  bool matches(String query) =>
      query.isEmpty || _searchText.contains(query.toLowerCase());
}

enum ConversationSort { original, lowestFirst, highestFirst }

/// [rows] matching [query], in [sort] order. Conversations without a score
/// go last in both score orders.
List<ConversationRow> filterRows(
  List<ConversationRow> rows,
  String query,
  ConversationSort sort,
) {
  final q = query.trim();
  final list = [
    for (final r in rows)
      if (r.matches(q)) r,
  ];
  int byScore(ConversationRow a, ConversationRow b, {required bool asc}) {
    if (a.score == null || b.score == null) {
      if (a.score == b.score) return a.index.compareTo(b.index);
      return a.score == null ? 1 : -1;
    }
    final c = asc ? a.score!.compareTo(b.score!) : b.score!.compareTo(a.score!);
    return c != 0 ? c : a.index.compareTo(b.index);
  }

  switch (sort) {
    case ConversationSort.original:
      list.sort((a, b) => a.index.compareTo(b.index));
    case ConversationSort.lowestFirst:
      list.sort((a, b) => byScore(a, b, asc: true));
    case ConversationSort.highestFirst:
      list.sort((a, b) => byScore(a, b, asc: false));
  }
  return list;
}

/// A run's summary tiles, histogram and conversation rows.
class RunSummary {
  RunSummary._(this.contents, this.rows);

  factory RunSummary.of(RunFileContents contents) => RunSummary._(contents, [
    for (final c in contents.conversations) ConversationRow(c),
  ]);

  final RunFileContents contents;
  final List<ConversationRow> rows;

  RunHeader get header => contents.header;
  RunStatus get status => contents.status;
  double get score => contents.score;
  int get conversationCount => rows.length;
  int get selectedCount => header.dataset.selectedCount;
  int get missingCount => selectedCount - conversationCount;

  /// Continue is possible when conversations are missing and the run is not
  /// being written right now (spec 003 FR-014).
  bool get canContinue => missingCount > 0 && status != RunStatus.running;

  Iterable<Grade> get _grades => [for (final r in rows) ...r.graded.grades];

  late final int criteriaCount = _grades.length;
  late final int positiveCount = _grades
      .where((g) => g.criterion.points > 0)
      .length;
  late final int positiveMet = _grades
      .where((g) => g.criterion.points > 0 && g.criteriaMet)
      .length;
  late final int negativeCount = _grades
      .where((g) => g.criterion.points < 0)
      .length;
  late final int negativeMet = _grades
      .where((g) => g.criterion.points < 0 && g.criteriaMet)
      .length;
  late final List<int> histogram = histogramBins(rows.map((r) => r.score));

  /// Unclipped scores of the conversations that have one (spec 006).
  late final List<double> _scored = [
    for (final r in rows)
      if (r.score case final double s) s,
  ];

  /// Median conversation score (spec 006 FR-001).
  late final double? medianScore = stats.median(_scored);

  /// Sample standard deviation of the conversation scores (FR-002).
  late final double? scoreStdDev = stats.sampleStdDev(_scored);

  /// Bootstrap standard deviation of the run score (FR-003).
  late final double? bootstrapStd = stats.bootstrapStd(_scored);
}
