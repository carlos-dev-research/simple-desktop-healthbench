import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/run_file.dart';
import '../../core/runner.dart';
import '../format.dart';
import '../runs/status_chip.dart';

/// Live progress of the active (or last) run (spec 003 US2; maths as the
/// reference run.js, research R5).
class ProgressPanel extends StatefulWidget {
  const ProgressPanel({
    super.key,
    required this.progress,
    this.runFilePath,
    this.modelsLabel,
    this.onStop,
    this.onOpenResults,
  });

  final RunProgress progress;
  final String? runFilePath;
  final String? modelsLabel;
  final VoidCallback? onStop;
  final VoidCallback? onOpenResults;

  @override
  State<ProgressPanel> createState() => _ProgressPanelState();
}

class _ProgressPanelState extends State<ProgressPanel> {
  late DateTime _receivedAt;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _receivedAt = DateTime.now();
    _syncTicker();
  }

  @override
  void didUpdateWidget(ProgressPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.progress, widget.progress)) _receivedAt = DateTime.now();
    _syncTicker();
  }

  /// Ticks once a second while running, so elapsed time moves between events.
  void _syncTicker() {
    final running = widget.progress.status == RunStatus.running;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final theme = Theme.of(context);
    final running = p.status == RunStatus.running;
    final processed = p.done + p.failed;
    final partial = running && p.criterionTotal > 0
        ? p.criterionDone / p.criterionTotal
        : 0.0;
    final fraction = p.total == 0
        ? 0.0
        : ((processed + partial) / p.total).clamp(0.0, 1.0);
    final sinceUpdate = DateTime.now().difference(_receivedAt);
    final elapsed = running && !sinceUpdate.isNegative
        ? p.elapsed + sinceUpdate
        : p.elapsed;
    // Rate from this session only: after Continue, `done` also counts
    // conversations graded earlier (code review #7).
    final thisSession = p.done - p.doneAtSessionStart + p.failed + partial;
    final left = p.total - processed - partial;
    final remaining = running && thisSession > 0
        ? elapsed * (left / thisSession)
        : null;

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Progress', style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
                StatusChip(p.status),
                const SizedBox(width: 12),
                // Buttons shrink (ellipsis) rather than overflow on narrow
                // windows or large text.
                if (running && widget.onStop != null)
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.stop),
                        label: Text(
                          p.stopRequested
                              ? 'Stopping after this conversation…'
                              : 'Stop',
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: p.stopRequested ? null : widget.onStop,
                      ),
                    ),
                  ),
                if (!running && widget.onOpenResults != null && p.done > 0)
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: widget.onOpenResults,
                        child: const Text(
                          'Open results',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [p.runId, ?widget.modelsLabel].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: fraction, minHeight: 8),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$processed of ${p.total}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' conversations'),
                  if (p.failed > 0)
                    TextSpan(
                      text: ' · ${p.failed} failed',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  TextSpan(text: ' · ${(fraction * 100).round()}%'),
                ],
              ),
            ),
            if (running) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: p.criterionTotal == 0
                    ? null
                    : p.criterionDone / p.criterionTotal,
                minHeight: 4,
              ),
              const SizedBox(height: 4),
              Text(
                p.criterionTotal == 0
                    ? 'Conversation ${(processed + 1).clamp(1, p.total)}: generating the model response…'
                    : 'Conversation ${processed + 1}: graded ${p.criterionDone} of ${p.criterionTotal} criteria',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Stat(formatDuration(elapsed), 'Elapsed'),
                _Stat(
                  running ? formatDuration(remaining) : '–',
                  'Estimated time left',
                ),
                _Stat(
                  formatScore(p.score),
                  running ? 'Score so far' : 'Final score',
                ),
                _Stat('${p.done}', 'Conversations graded'),
              ],
            ),
            if (p.failureReason case final reason?) ...[
              const SizedBox(height: 12),
              Text(
                'The run stopped: $reason',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            if (p.recentErrors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Recent errors (those conversations were skipped):',
                style: theme.textTheme.labelLarge,
              ),
              for (final e in p.recentErrors)
                Text('• $e', style: theme.textTheme.bodySmall),
            ],
            if (!running && widget.runFilePath == null && p.done == 0) ...[
              const SizedBox(height: 12),
              const Text('Nothing was saved: no conversation could be graded.'),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.titleLarge),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
