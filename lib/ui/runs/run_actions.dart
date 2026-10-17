import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dataset.dart';
import '../../core/run_library.dart';
import '../state/providers.dart';
import '../state/runs_controller.dart';

/// Import, export and delete of run files, with their dialogs and messages
/// (spec 004). The core enforces the rules; these only ask and report.

/// Shows a result message. The messenger is taken before any await, because
/// the widget that started the action may be gone by then (a deleted run's
/// detail view is removed).
void _say(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Export: save dialog, then a byte copy (spec 004 US1).
Future<void> exportRunFlow(
  BuildContext context,
  WidgetRef ref,
  String runPath,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final destination = await ref.read(exportLocationProvider)(
    fileNameOf(runPath),
  );
  if (destination == null || !context.mounted) return;
  try {
    await exportRun(runPath, destination);
    _say(messenger, 'Exported to $destination');
  } on RunActiveException catch (e) {
    _say(messenger, e.message);
  } on FileSystemException catch (e) {
    _say(messenger, 'Export failed: ${e.message}');
  }
}

/// Delete: confirm, remove, refresh (spec 004 US2).
Future<void> deleteRunFlow(
  BuildContext context,
  WidgetRef ref,
  String runPath,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final name = fileNameOf(runPath);
  final confirmed = await _confirm(
    context,
    title: 'Delete run?',
    body: '$name will be removed from the app. This can\'t be undone.',
    action: 'Delete',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  try {
    await deleteRun(runPath);
    if (ref.read(selectedRunProvider) == runPath) {
      ref.read(selectedRunProvider.notifier).select(null);
    }
    await ref.read(runsProvider.notifier).refresh();
    _say(messenger, 'Deleted $name');
  } on RunActiveException catch (e) {
    _say(messenger, e.message);
  } on FileSystemException catch (e) {
    _say(messenger, 'Delete failed: ${e.message}');
  }
}

/// Import: open dialog, full check, confirm a replacement, copy in, select
/// it (spec 004 US3).
Future<void> importRunFlow(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final source = await ref.read(importPickerProvider)();
  if (source == null || !context.mounted) return;
  final storage = await ref.read(storageDirectoryProvider.future);
  final check = await checkImport(source, runsDirectoryIn(storage));
  if (!context.mounted) return;

  switch (check) {
    case ImportAlreadyInApp():
      _say(messenger, 'This run is already in the app.');
    case ImportRejected(:final reason):
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Can\'t import this file'),
          content: Text(reason),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    case final ImportReady ready:
      final name = fileNameOf(ready.targetPath);
      if (ready.replacesExisting) {
        final replace = await _confirm(
          context,
          title: 'Replace existing run?',
          body:
              'A run named $name is already in the app. Replace it with '
              'the imported file?',
          action: 'Replace',
          destructive: true,
        );
        if (!replace || !context.mounted) return;
      }
      try {
        final target = await importRun(ready, replace: ready.replacesExisting);
        await ref.read(runsProvider.notifier).refresh();
        ref.read(selectedRunProvider.notifier).select(target);
        _say(messenger, 'Imported $name');
      } on RunActiveException catch (e) {
        _say(messenger, e.message);
      } on StateError catch (e) {
        _say(messenger, e.message);
      } on FileSystemException catch (e) {
        _say(messenger, 'Import failed: ${e.message}');
      }
  }
}
