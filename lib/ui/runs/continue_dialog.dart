import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/run_file.dart';
import '../../core/runner.dart';
import '../new_run/dataset_field.dart';
import '../state/providers.dart';
import '../state/run_controller.dart';

/// Asks for the API key (prefilled with this session's key, if any;
/// Constitution 1.1.0 III.1) and the dataset, then continues the run
/// (spec 003 US4, FR-014).
Future<void> showContinueDialog(BuildContext context, RunFileContents run) =>
    showDialog<void>(context: context, builder: (_) => _ContinueDialog(run));

class _ContinueDialog extends ConsumerStatefulWidget {
  const _ContinueDialog(this.run);

  final RunFileContents run;

  @override
  ConsumerState<_ContinueDialog> createState() => _ContinueDialogState();
}

class _ContinueDialogState extends ConsumerState<_ContinueDialog> {
  // The session's key from the New-run form; memory only, never stored.
  late final _key = TextEditingController(
    text: ref.read(newRunFormProvider).apiKey,
  );
  String? _datasetPath;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_key.text.trim().isEmpty || _datasetPath == null) {
      setState(() => _error = 'Enter the API key and choose the dataset.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(runControllerProvider.notifier)
          .resume(
            runFilePath: widget.run.path,
            datasetPath: _datasetPath!,
            apiKey: _key.text.trim(),
          );
      if (!mounted) return;
      ref.read(currentViewProvider.notifier).show(AppView.newRun);
      Navigator.of(context).pop();
    } on RunStartException catch (e) {
      setState(() => _error = e.reason);
    } on Object catch (e) {
      setState(() => _error = e is ArgumentError ? '${e.message}' : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final header = widget.run.header;
    return AlertDialog(
      title: const Text('Continue run'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.run.conversations.length} of '
              '${header.dataset.selectedCount} conversations are graded. '
              'The rest will be evaluated with the run\'s settings '
              '(${header.modelTest.name}, ${header.baseUrl.host}).',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _key,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'API key',
                helperText: 'Kept for this session only; never saved',
              ),
            ),
            const SizedBox(height: 16),
            DatasetField(
              hint: 'This run used ${header.dataset.fileName}',
              matchSha256: header.dataset.sha256,
              onChanged: (path, _) => setState(() => _datasetPath = path),
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
          onPressed: _busy ? null : _continue,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
