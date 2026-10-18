import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dataset.dart';
import '../../core/dataset_library.dart';
import '../state/datasets_controller.dart';
import '../state/providers.dart';

/// The dataset for a run: picked from the library (spec 005 FR-004) or
/// chosen with the native open dialog and read with the core (spec 003
/// FR-005). Reports the chosen path and its label, or nulls while none is
/// valid. [initialLabel] shows a choice made earlier in the session.
/// [matchSha256] pre-selects the library dataset with that fingerprint, as
/// Continue does (spec 005 FR-005).
class DatasetField extends ConsumerStatefulWidget {
  const DatasetField({
    super.key,
    required this.onChanged,
    this.hint,
    this.initialLabel,
    this.initialPath,
    this.matchSha256,
  });

  final void Function(String? path, String? label) onChanged;
  final String? initialLabel;
  final String? initialPath;
  final String? matchSha256;

  /// Shown under the button, e.g. which file a run used.
  final String? hint;

  @override
  ConsumerState<DatasetField> createState() => _DatasetFieldState();
}

class _DatasetFieldState extends ConsumerState<DatasetField> {
  late String? _label = widget.initialLabel;
  late String? _path = widget.initialPath;
  String? _error;
  bool _reading = false;

  static String _labelOf(LibraryDataset d) =>
      '${d.fileName} · ${d.conversations} conversations';

  @override
  void initState() {
    super.initState();
    final sha = widget.matchSha256;
    if (sha != null) {
      // Pre-select the run's dataset once the library is loaded.
      ref.listenManual(datasetLibraryProvider, (_, next) {
        if (_path != null) return;
        final match = next.value?.where((d) => d.sha256 == sha).firstOrNull;
        if (match == null) return;
        // May fire while the parent is still building: select after this
        // frame, so the parent's setState is allowed.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _path == null) _select(match.path, _labelOf(match));
        });
      }, fireImmediately: true);
    }
  }

  void _select(String path, String label) {
    setState(() {
      _path = path;
      _label = label;
      _error = null;
    });
    widget.onChanged(path, label);
  }

  Future<void> _choose() async {
    final path = await ref.read(datasetPickerProvider)();
    if (path == null || !mounted) return;
    setState(() {
      _reading = true;
      _error = null;
      _label = null;
    });
    widget.onChanged(null, null);
    try {
      final dataset = await readDataset(path);
      if (!mounted) return;
      final label =
          '${dataset.fileName} · ${dataset.conversations.length} conversations';
      _select(path, label);
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e is DatasetFormatException
            ? '$e'
            : 'Could not read the file: $e',
      );
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = ref.watch(datasetLibraryProvider).value ?? const [];
    final inLibrary = library.any((d) => d.path == _path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (library.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            key: ValueKey(inLibrary ? _path : null),
            initialValue: inLibrary ? _path : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Dataset from the library',
            ),
            items: [
              for (final d in library)
                DropdownMenuItem(
                  value: d.path,
                  child: Text(_labelOf(d), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (path) {
              final d = library.firstWhere((d) => d.path == path);
              _select(d.path, _labelOf(d));
            },
          ),
          const SizedBox(height: 8),
          Text('or', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose dataset file…'),
              onPressed: _reading ? null : _choose,
            ),
            const SizedBox(width: 12),
            if (_reading)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (_label != null && !inLibrary)
              Flexible(child: Text(_label!, overflow: TextOverflow.ellipsis)),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (widget.hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(widget.hint!, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}
