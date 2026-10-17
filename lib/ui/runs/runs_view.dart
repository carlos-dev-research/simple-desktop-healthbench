import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/run_library.dart';
import '../format.dart';
import '../state/providers.dart';
import '../state/runs_controller.dart';
import 'run_actions.dart';
import 'run_detail.dart';
import 'status_chip.dart';

/// The runs in the app's storage, and the selected run's details
/// (spec 003 US3).
class RunsView extends ConsumerWidget {
  const RunsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(runsProvider);
    final selected = ref.watch(selectedRunProvider);
    final entries = runs.value ?? const <RunEntry>[];
    final valid = [
      for (final e in entries)
        if (e.isValid) e,
    ];
    final rejected = [
      for (final e in entries)
        if (!e.isValid) e,
    ];
    final current = valid.where((e) => e.path == selected).firstOrNull;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    // The title gives way first if the pane is tight.
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: 'Runs  ',
                          style: Theme.of(context).textTheme.titleLarge,
                          children: [
                            TextSpan(
                              text: '${valid.length}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.file_open_outlined, size: 18),
                      label: const Text('Import'),
                      onPressed: () => importRunFlow(context, ref),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      icon: const Icon(Icons.refresh),
                      onPressed: () =>
                          ref.read(runsProvider.notifier).refresh(),
                    ),
                  ],
                ),
              ),
              if (runs.isLoading && entries.isEmpty)
                const LinearProgressIndicator(),
              if (runs.hasError)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Could not list runs: ${runs.error}'),
                ),
              Expanded(
                child: valid.isEmpty && !runs.isLoading
                    ? const _EmptyRuns()
                    : ListView.builder(
                        itemCount: valid.length,
                        itemBuilder: (context, i) => _RunTile(
                          entry: valid[i],
                          selected: valid[i].path == selected,
                          onTap: () => ref
                              .read(selectedRunProvider.notifier)
                              .select(valid[i].path),
                        ),
                      ),
              ),
              if (rejected.isNotEmpty) _RejectedFiles(rejected),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: current == null
              ? Center(
                  child: Text(
                    valid.isEmpty ? '' : 'Select a run to see its results.',
                  ),
                )
              : RunDetail(key: ValueKey(current.path), entry: current),
        ),
      ],
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final RunEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = entry.contents!;
    final h = c.header;
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      selected: selected,
      onTap: onTap,
      title: Row(
        children: [
          Expanded(
            child: Text(
              formatDateTime(h.createdAt),
              style: textTheme.titleSmall,
            ),
          ),
          StatusChip(c.status),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${h.modelTest.name} · graded by ${h.modelGrader.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${h.dataset.fileName} · ${c.conversations.length}/'
            '${h.dataset.selectedCount}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: ScoreBar(c.score)),
              const SizedBox(width: 8),
              Text(formatScore(c.score), style: textTheme.labelLarge),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyRuns extends ConsumerWidget {
  const _EmptyRuns();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No runs yet.', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () =>
                ref.read(currentViewProvider.notifier).show(AppView.newRun),
            child: const Text('Start a run'),
          ),
        ],
      ),
    ),
  );
}

class _RejectedFiles extends ConsumerWidget {
  const _RejectedFiles(this.entries);

  final List<RunEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ExpansionTile(
    leading: Icon(
      Icons.warning_amber,
      color: Theme.of(context).colorScheme.error,
    ),
    title: Text('${entries.length} file(s) skipped'),
    children: [
      for (final e in entries)
        ListTile(
          dense: true,
          title: Text(e.fileName),
          subtitle: Text(e.error ?? ''),
          trailing: IconButton(
            tooltip: 'Delete file',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => deleteRunFlow(context, ref, e.path),
          ),
        ),
    ],
  );
}
