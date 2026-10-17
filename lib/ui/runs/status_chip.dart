import 'package:flutter/material.dart';

import '../../core/run_file.dart';

/// A small coloured label for a run's status.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final RunStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status) {
      RunStatus.completed => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      RunStatus.running => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
      ),
      RunStatus.failed => (colors.errorContainer, colors.onErrorContainer),
      RunStatus.stopped || RunStatus.interrupted => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.name,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground),
      ),
    );
  }
}

/// A thin horizontal bar showing a 0–1 value.
class ScoreBar extends StatelessWidget {
  const ScoreBar(this.value, {super.key});

  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1).toDouble(),
        minHeight: 6,
        backgroundColor: colors.surfaceContainerHighest,
      ),
    );
  }
}
