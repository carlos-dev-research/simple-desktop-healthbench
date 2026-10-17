import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/settings.dart';

/// The app's own storage folder (the sandbox container on macOS;
/// flutter-desktop.md §2.1). Tests override it with a temporary folder.
final storageDirectoryProvider = FutureProvider<String>((ref) async {
  final dir = await getApplicationSupportDirectory();
  // Earlier versions remembered form fields in form.json; the form is now
  // session-only (spec 003 FR-004, amended), so remove a leftover file.
  try {
    await File(_join(dir.path, 'form.json')).delete();
  } on FileSystemException {
    // Not there: nothing to clean up.
  }
  return dir.path;
});

String _join(String a, String b) => '$a${Platform.pathSeparator}$b';

/// Where run files live: `<storage>/runs`.
String runsDirectoryIn(String storage) => _join(storage, 'runs');

/// Chooses a dataset file; returns its path, or null if cancelled.
typedef DatasetPicker = Future<String?> Function();

/// The native open dialog, filtered to `.jsonl` (spec 003 FR-005).
final datasetPickerProvider = Provider<DatasetPicker>(
  (ref) => () async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'HealthBench dataset', extensions: ['jsonl']),
      ],
    );
    return file?.path;
  },
);

/// Chooses a run file to import; returns its path, or null if cancelled
/// (spec 004 US3).
final importPickerProvider = Provider<DatasetPicker>(
  (ref) => () async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'HealthBench run', extensions: ['jsonl']),
      ],
    );
    return file?.path;
  },
);

/// Asks where to save an exported run; returns the path, or null if
/// cancelled (spec 004 US1).
typedef ExportLocation = Future<String?> Function(String suggestedName);

final exportLocationProvider = Provider<ExportLocation>(
  (ref) => (suggestedName) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'HealthBench run', extensions: ['jsonl']),
      ],
    );
    return location?.path;
  },
);

/// Timeouts and retries for runs; tests use short values.
final clientOptionsProvider = Provider<ClientOptions>(
  (ref) => const ClientOptions(),
);

/// Everything typed or chosen in the New-run form. Held in memory for the
/// app session only, so it survives switching views but is gone when the
/// app quits; never written to disk (spec 003 FR-004, amended).
class NewRunForm {
  const NewRunForm({
    this.baseUrl = '',
    this.apiKey = '',
    this.modelTest = '',
    this.effortTest = ReasoningEffort.low,
    this.modelGrader = '',
    this.effortGrader = ReasoningEffort.low,
    this.datasetPath,
    this.datasetLabel,
    this.limit = '',
  });

  final String baseUrl;
  final String apiKey;
  final String modelTest;
  final ReasoningEffort effortTest;
  final String modelGrader;
  final ReasoningEffort effortGrader;

  /// The chosen dataset file and its "name · N conversations" label.
  final String? datasetPath;
  final String? datasetLabel;

  /// As typed; validated when the run starts.
  final String limit;

  NewRunForm copyWith({
    String? baseUrl,
    String? apiKey,
    String? modelTest,
    ReasoningEffort? effortTest,
    String? modelGrader,
    ReasoningEffort? effortGrader,
    String? limit,
  }) => NewRunForm(
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    modelTest: modelTest ?? this.modelTest,
    effortTest: effortTest ?? this.effortTest,
    modelGrader: modelGrader ?? this.modelGrader,
    effortGrader: effortGrader ?? this.effortGrader,
    datasetPath: datasetPath,
    datasetLabel: datasetLabel,
    limit: limit ?? this.limit,
  );

  /// The same form with a different dataset choice (null clears it).
  NewRunForm withDataset(String? path, String? label) => NewRunForm(
    baseUrl: baseUrl,
    apiKey: apiKey,
    modelTest: modelTest,
    effortTest: effortTest,
    modelGrader: modelGrader,
    effortGrader: effortGrader,
    datasetPath: path,
    datasetLabel: label,
    limit: limit,
  );
}

class NewRunFormController extends Notifier<NewRunForm> {
  @override
  NewRunForm build() => const NewRunForm();

  void update(NewRunForm Function(NewRunForm) change) => state = change(state);
}

final newRunFormProvider = NotifierProvider<NewRunFormController, NewRunForm>(
  NewRunFormController.new,
);

/// The two main views (spec 003 FR-001).
enum AppView { runs, newRun }

class CurrentView extends Notifier<AppView> {
  @override
  AppView build() => AppView.runs;

  void show(AppView view) => state = view;
}

final currentViewProvider = NotifierProvider<CurrentView, AppView>(
  CurrentView.new,
);
