import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/run_file.dart';
import '../../core/run_library.dart';
import '../../core/run_summary.dart';
import '../format.dart';
import 'continue_dialog.dart';
import 'conversation_view.dart';
import 'histogram.dart';
import 'run_actions.dart';
import 'status_chip.dart';

/// One run: header, summary tiles, histogram and its conversations
/// (spec 003 US3-2, US3-3, US4-1).
class RunDetail extends ConsumerStatefulWidget {
  const RunDetail({super.key, required this.entry});

  final RunEntry entry;

  @override
  ConsumerState<RunDetail> createState() => _RunDetailState();
}

class _RunDetailState extends ConsumerState<RunDetail> {
  late RunSummary _summary = RunSummary.of(widget.entry.contents!);
  String _query = '';
  ConversationSort _sort = ConversationSort.original;
  late List<ConversationRow> _rows = _summary.rows;

  @override
  void didUpdateWidget(RunDetail old) {
    super.didUpdateWidget(old);
    if (!identical(old.entry.contents, widget.entry.contents)) {
      _summary = RunSummary.of(widget.entry.contents!);
      _applyFilter();
    }
  }

  void _applyFilter() => _rows = filterRows(_summary.rows, _query, _sort);

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final header = summary.header;
    final theme = Theme.of(context);
    return SelectionArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverList.list(
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        header.runId,
                        style: theme.textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(summary.status),
                    const Spacer(),
                    // Not while the run is being written (spec 004 FR-001).
                    if (summary.status != RunStatus.running) ...[
                      IconButton(
                        tooltip: 'Export',
                        icon: const Icon(Icons.save_alt),
                        onPressed: () =>
                            exportRunFlow(context, ref, widget.entry.path),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () =>
                            deleteRunFlow(context, ref, widget.entry.path),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (summary.canContinue)
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.play_arrow),
                        label: Text('Continue (${summary.missingCount} left)'),
                        onPressed: () =>
                            showContinueDialog(context, summary.contents),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${header.modelTest.name} (${header.modelTest.reasoningEffort.name}) '
                  'graded by ${header.modelGrader.name} '
                  '(${header.modelGrader.reasoningEffort.name}) · '
                  '${header.dataset.fileName} · started '
                  '${formatDateTime(header.createdAt)}',
                  style: theme.textTheme.bodySmall,
                ),
                if (summary.contents.failureReason case final reason?)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'The run stopped: $reason',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Tile(
                      summary.bootstrapStd == null
                          ? formatScore(summary.score)
                          : '${formatScore(summary.score)} ± ${formatScore(summary.bootstrapStd)}',
                      'Run score',
                      tooltip:
                          'Mean of the conversation scores, clipped to 0–1. '
                          '± is the bootstrap standard deviation.',
                    ),
                    _Tile(
                      '${summary.conversationCount}/${summary.selectedCount}',
                      'Conversations graded',
                    ),
                    _Tile('${summary.criteriaCount}', 'Rubric criteria graded'),
                    _Tile(
                      formatScore(summary.medianScore),
                      'Median score',
                      tooltip: 'The middle conversation score.',
                    ),
                    _Tile(
                      formatScore(summary.scoreStdDev),
                      'Std dev (conversations)',
                      tooltip:
                          'How spread out the conversation scores are '
                          '(sample standard deviation).',
                    ),
                    _Tile(
                      formatScore(summary.bootstrapStd),
                      'Bootstrap std (run score)',
                      tooltip:
                          'How much the run score would move with a different '
                          'sample of conversations: standard deviation over '
                          '1,000 resamples, as OpenAI reports for HealthBench.',
                    ),
                    _Tile(
                      formatPercent(summary.positiveMet, summary.positiveCount),
                      'Positive criteria met '
                      '(${summary.positiveMet}/${summary.positiveCount})',
                    ),
                    _Tile(
                      formatPercent(summary.negativeMet, summary.negativeCount),
                      'Penalties triggered '
                      '(${summary.negativeMet}/${summary.negativeCount})',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Score per conversation',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ScoreHistogram(summary.histogram),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Conversations', style: theme.textTheme.titleSmall),
                    const SizedBox(width: 8),
                    Text(
                      '${_rows.length} of ${summary.conversationCount}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 240,
                      child: TextField(
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search, size: 18),
                          hintText: 'Search',
                        ),
                        onChanged: (q) => setState(() {
                          _query = q;
                          _applyFilter();
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<ConversationSort>(
                      value: _sort,
                      onChanged: (s) => setState(() {
                        _sort = s!;
                        _applyFilter();
                      }),
                      items: const [
                        DropdownMenuItem(
                          value: ConversationSort.original,
                          child: Text('Original order'),
                        ),
                        DropdownMenuItem(
                          value: ConversationSort.lowestFirst,
                          child: Text('Lowest score first'),
                        ),
                        DropdownMenuItem(
                          value: ConversationSort.highestFirst,
                          child: Text('Highest score first'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          SliverList.builder(
            itemCount: _rows.length,
            itemBuilder: (context, i) => _ConversationTile(
              key: ValueKey(_rows[i].graded.conversation.promptId),
              row: _rows[i],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.value, this.label, {this.tooltip});

  final String value;
  final String label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = Container(
      width: 168,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Long values (e.g. "0.463 ± 0.031") shrink instead of overflowing.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: theme.textTheme.headlineSmall),
          ),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
    return tooltip == null ? tile : Tooltip(message: tooltip, child: tile);
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({super.key, required this.row});

  final ConversationRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      // Children are only built when the tile is opened.
      title: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              '#${row.index + 1}',
              style: theme.textTheme.labelMedium,
            ),
          ),
          Expanded(
            child: Text(
              row.preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${row.earned}/${row.possible} pts',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 56,
            child: Text(
              formatScore(row.score),
              textAlign: TextAlign.right,
              style: theme.textTheme.labelLarge,
            ),
          ),
        ],
      ),
      children: [ConversationView(row.graded)],
    );
  }
}
