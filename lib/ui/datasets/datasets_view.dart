import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dataset.dart';
import '../../core/dataset_library.dart';
import '../state/datasets_controller.dart';

/// Official downloads, the dataset library, samples and added files
/// (spec 005).
class DatasetsView extends ConsumerWidget {
  const DatasetsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(datasetLibraryProvider);
    final entries = library.value ?? const <LibraryDataset>[];
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Datasets', style: theme.textTheme.titleLarge),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add file…'),
              onPressed: () => _addFile(context, ref),
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () =>
                  ref.read(datasetLibraryProvider.notifier).refresh(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Official HealthBench files', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final official in ref.watch(officialDatasetsProvider))
          _OfficialTile(official: official, library: entries),
        const SizedBox(height: 16),
        Text('Library', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        if (library.isLoading && entries.isEmpty)
          const LinearProgressIndicator(),
        if (!library.isLoading && entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No datasets yet. Download an official file above, or add one of your own.',
            ),
          ),
        for (final dataset in entries) _LibraryTile(dataset),
      ],
    );
  }
}

String formatBytes(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).toStringAsFixed(0)} KB';

void _say(ScaffoldMessengerState messenger, String message) => messenger
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

Future<void> _addFile(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final path = await ref.read(addFilePickerProvider)();
  if (path == null) return;
  try {
    final result = await ref
        .read(datasetLibraryProvider.notifier)
        .addFile(path);
    _say(
      messenger,
      result.alreadyPresent
          ? 'Already in the library as ${result.entry.fileName}'
          : 'Added ${result.entry.fileName} (${result.entry.conversations} conversations)',
    );
  } on DatasetFormatException catch (e) {
    _say(messenger, 'Not a valid HealthBench file: $e');
  } on Object catch (e) {
    _say(messenger, 'Could not add the file: $e');
  }
}

class _OfficialTile extends ConsumerWidget {
  const _OfficialTile({required this.official, required this.library});

  final OfficialDataset official;
  final List<LibraryDataset> library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = library.any(
      (d) => d.fileName == official.fileName && d.sha256 == official.sha256,
    );
    final progress = ref.watch(downloadsProvider)[official.fileName];
    final theme = Theme.of(context);
    final Widget trailing;
    if (downloaded) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 18),
          const SizedBox(width: 6),
          Text('Downloaded · ${official.conversations} conversations'),
        ],
      );
    } else if (progress != null) {
      trailing = SizedBox(
        width: 260,
        child: Row(
          children: [
            Expanded(child: LinearProgressIndicator(value: progress.fraction)),
            const SizedBox(width: 8),
            Text('${(progress.fraction * 100).round()}%'),
            TextButton(
              onPressed: () => ref
                  .read(downloadsProvider.notifier)
                  .cancel(official.fileName),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    } else {
      trailing = FilledButton.tonalIcon(
        icon: const Icon(Icons.download, size: 18),
        label: const Text('Download'),
        onPressed: () => _download(context, ref),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(official.label),
      subtitle: Text(
        '${official.description} · ${official.fileName} · ${formatBytes(official.bytes)}',
      ),
      trailing: trailing,
    );
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(downloadsProvider.notifier).download(official);
      _say(messenger, 'Downloaded and verified ${official.label}');
    } on DownloadCancelled {
      _say(messenger, 'Download cancelled');
    } on DatasetDownloadException catch (e) {
      _say(messenger, '$e');
    } on Object catch (e) {
      _say(messenger, 'Download failed: $e');
    }
  }
}

class _LibraryTile extends ConsumerWidget {
  const _LibraryTile(this.dataset);

  final LibraryDataset dataset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final origin = switch (dataset.origin) {
      DatasetOrigin.official => 'Official',
      DatasetOrigin.sample =>
        'Sample of ${dataset.sampleOf ?? 'another dataset'}',
      DatasetOrigin.added => 'Added file',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(dataset.fileName),
      subtitle: SelectableText(
        '$origin · ${dataset.conversations} conversations · '
        '${formatBytes(dataset.bytes)} · SHA-256 ${dataset.sha256.substring(0, 12)}…',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _SampleDialog(dataset),
            ),
            child: const Text('Sample…'),
          ),
          IconButton(
            tooltip: 'Delete dataset',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete dataset?'),
        content: Text(
          '${dataset.fileName} will be removed from the library. Runs made with '
          'it stay viewable; continuing them will need the dataset again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(datasetLibraryProvider.notifier).delete(dataset);
      _say(messenger, 'Deleted ${dataset.fileName}');
    } on StateError catch (e) {
      _say(messenger, e.message);
    } on Object catch (e) {
      _say(messenger, 'Delete failed: $e');
    }
  }
}

/// N and seed for a new sample (spec 005 US3). Default seed 40, as the
/// reference toolkit used.
class _SampleDialog extends ConsumerStatefulWidget {
  const _SampleDialog(this.source);

  final LibraryDataset source;

  @override
  ConsumerState<_SampleDialog> createState() => _SampleDialogState();
}

class _SampleDialogState extends ConsumerState<_SampleDialog> {
  late final _n = TextEditingController(
    text:
        '${widget.source.conversations < 100 ? widget.source.conversations : 100}',
  );
  final _seed = TextEditingController(text: '40');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _n.dispose();
    _seed.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final n = int.tryParse(_n.text.trim());
    final seed = int.tryParse(_seed.text.trim());
    final max = widget.source.conversations;
    if (n == null || n < 1 || n > max) {
      setState(() => _error = 'Size must be a whole number from 1 to $max');
      return;
    }
    if (seed == null || seed < 0) {
      setState(() => _error = 'Seed must be a whole number of 0 or more');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final made = await ref
          .read(datasetLibraryProvider.notifier)
          .sample(widget.source, n, seed);
      navigator.pop();
      _say(messenger, 'Created ${made.fileName}');
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return AlertDialog(
      title: const Text('Create a sample'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A random subset of ${widget.source.fileName} '
              '(${widget.source.conversations} conversations). The same size and seed '
              'always give the same sample.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _n,
              inputFormatters: digits,
              decoration: const InputDecoration(
                labelText: 'Size (conversations)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _seed,
              inputFormatters: digits,
              decoration: const InputDecoration(labelText: 'Seed'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
