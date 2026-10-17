import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dataset.dart';
import '../state/providers.dart';

/// The dataset chosen with the native open dialog, read with the core
/// (spec 003 FR-005). Reports the chosen path and its label, or nulls while
/// none is valid. [initialLabel] shows a choice made earlier in the session.
class DatasetField extends ConsumerStatefulWidget {
  const DatasetField({
    super.key,
    required this.onChanged,
    this.hint,
    this.initialLabel,
  });

  final void Function(String? path, String? label) onChanged;
  final String? initialLabel;

  /// Shown under the button, e.g. which file a run used.
  final String? hint;

  @override
  ConsumerState<DatasetField> createState() => _DatasetFieldState();
}

class _DatasetFieldState extends ConsumerState<DatasetField> {
  late String? _label = widget.initialLabel;
  String? _error;
  bool _reading = false;

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
      setState(() => _label = label);
      widget.onChanged(path, label);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            if (_label != null)
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
