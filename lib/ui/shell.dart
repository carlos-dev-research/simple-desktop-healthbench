import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_info.dart';
import 'new_run/new_run_view.dart';
import 'runs/runs_view.dart';
import 'state/providers.dart';
import 'state/run_controller.dart';

/// Navigation between the two main views: "Evals" at the top, the version
/// very small at the bottom (spec 001 FR-002, amended), and the notes that
/// put results in context (spec 003 FR-001, FR-016).
class Shell extends ConsumerWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(currentViewProvider);
    final running = ref.watch(runControllerProvider.select((s) => s.isRunning));
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Row(
        children: [
          Column(
            children: [
              Expanded(
                child: NavigationRail(
                  selectedIndex: view.index,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (i) => ref
                      .read(currentViewProvider.notifier)
                      .show(AppView.values[i]),
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('Evals', style: textTheme.titleMedium),
                  ),
                  destinations: [
                    const NavigationRailDestination(
                      icon: Icon(Icons.table_rows_outlined),
                      selectedIcon: Icon(Icons.table_rows),
                      label: Text('Runs'),
                    ),
                    NavigationRailDestination(
                      icon: running
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(Icons.play_circle_outline),
                      selectedIcon: const Icon(Icons.play_circle),
                      label: const Text('New run'),
                    ),
                  ],
                ),
              ),
              // The version, very small, at the bottom of the rail.
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'v$appVersion',
                  style: textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: switch (view) {
                    AppView.runs => const RunsView(),
                    AppView.newRun => const NewRunView(),
                  },
                ),
                const _Notes(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Notes extends StatelessWidget {
  const _Notes();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: theme.colorScheme.surfaceContainerLow,
      child: Text(
        'Model output is unreviewed and is not medical advice. Scores from '
        'subsets or from graders other than OpenAI\'s are not comparable to '
        'published HealthBench numbers.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
