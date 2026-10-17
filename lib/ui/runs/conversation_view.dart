import 'package:flutter/material.dart';

import '../../core/grading.dart';
import '../../core/scoring.dart';
import '../markdown/markdown_view.dart';

/// One graded conversation: every message, the evaluated reply, and the
/// rubric table (spec 003 US3-4).
class ConversationView extends StatelessWidget {
  const ConversationView(this.graded, {super.key});

  final GradedConversation graded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in graded.conversation.prompt)
            _Message(role: m.role, content: m.content),
          _Message(
            role: 'Model response (evaluated)',
            content: graded.completion,
            highlight: true,
          ),
          const SizedBox(height: 8),
          Text('Rubric', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          _RubricTable(graded.grades),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.role,
    required this.content,
    this.highlight = false,
  });

  final String role;
  final String content;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight
            ? colors.secondaryContainer.withValues(alpha: 0.5)
            : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            role,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          MarkdownView(content),
        ],
      ),
    );
  }
}

class _RubricTable extends StatelessWidget {
  const _RubricTable(this.grades);

  final List<Grade> grades;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = theme.textTheme.labelMedium;
    Widget cell(Widget child) =>
        Padding(padding: const EdgeInsets.all(8), child: child);
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(56),
        1: FixedColumnWidth(120),
        2: FlexColumnWidth(3),
        3: FlexColumnWidth(3),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(
          children: [
            cell(Text('Points', style: header)),
            cell(Text('Outcome', style: header)),
            cell(Text('Criterion', style: header)),
            cell(Text('Grader explanation', style: header)),
          ],
        ),
        for (final g in grades)
          TableRow(
            children: [
              cell(
                Text(
                  g.criterion.points > 0
                      ? '+${g.criterion.points}'
                      : '${g.criterion.points}',
                ),
              ),
              cell(OutcomeLabel(outcomeOf(g))),
              cell(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.criterion.text),
                    if (g.criterion.tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          g.criterion.tags.join('  '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              cell(Text(g.explanation, style: theme.textTheme.bodySmall)),
            ],
          ),
      ],
    );
  }
}

/// earned / missed / penalty / avoided, each with its own colour and icon so
/// it doesn't depend on colour alone.
class OutcomeLabel extends StatelessWidget {
  const OutcomeLabel(this.outcome, {super.key});

  final CriterionOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (color, icon) = switch (outcome) {
      CriterionOutcome.earned => (
        dark ? Colors.green.shade300 : Colors.green.shade700,
        Icons.check_circle,
      ),
      CriterionOutcome.missed => (
        colors.onSurfaceVariant,
        Icons.radio_button_unchecked,
      ),
      CriterionOutcome.penalty => (colors.error, Icons.cancel),
      CriterionOutcome.avoided => (colors.tertiary, Icons.shield_outlined),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            outcome.name,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
