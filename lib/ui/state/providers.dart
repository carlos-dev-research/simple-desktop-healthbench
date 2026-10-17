import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/settings.dart';

/// The app's own storage folder (the sandbox container on macOS;
/// flutter-desktop.md §2.1). Tests override it with a temporary folder.
final storageDirectoryProvider = FutureProvider<String>((ref) async {
  final dir = await getApplicationSupportDirectory();
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

/// Timeouts and retries for runs; tests use short values.
final clientOptionsProvider = Provider<ClientOptions>(
  (ref) => const ClientOptions(),
);

/// Non-secret New-run fields remembered between launches (spec 003 FR-004,
/// research R6). Never contains the API key or the dataset path.
class RememberedForm {
  const RememberedForm({
    this.baseUrl = '',
    this.modelTest = '',
    this.effortTest = ReasoningEffort.low,
    this.modelGrader = '',
    this.effortGrader = ReasoningEffort.low,
    this.limit,
  });

  final String baseUrl;
  final String modelTest;
  final ReasoningEffort effortTest;
  final String modelGrader;
  final ReasoningEffort effortGrader;
  final int? limit;

  Map<String, Object?> toJson() => {
    'baseUrl': baseUrl,
    'modelTest': modelTest,
    'effortTest': effortTest.name,
    'modelGrader': modelGrader,
    'effortGrader': effortGrader.name,
    'limit': limit,
  };

  /// Unknown or malformed values fall back to the defaults.
  factory RememberedForm.fromJson(Object? json) {
    if (json is! Map<String, Object?>) return const RememberedForm();
    String text(String key) => json[key] is String ? json[key]! as String : '';
    ReasoningEffort effort(String key) {
      try {
        return ReasoningEffort.parse(json[key]! as String);
      } on Object {
        return ReasoningEffort.low;
      }
    }

    final limit = json['limit'];
    return RememberedForm(
      baseUrl: text('baseUrl'),
      modelTest: text('modelTest'),
      effortTest: effort('effortTest'),
      modelGrader: text('modelGrader'),
      effortGrader: effort('effortGrader'),
      limit: limit is int && limit > 0 ? limit : null,
    );
  }
}

String formFileIn(String storage) => _join(storage, 'form.json');

/// The remembered fields, or the defaults if none or unreadable.
final rememberedFormProvider = FutureProvider<RememberedForm>((ref) async {
  final storage = await ref.watch(storageDirectoryProvider.future);
  try {
    final text = await File(formFileIn(storage)).readAsString();
    return RememberedForm.fromJson(jsonDecode(text));
  } on Object {
    return const RememberedForm();
  }
});

Future<void> saveRememberedForm(String storage, RememberedForm form) async {
  await Directory(storage).create(recursive: true);
  await File(formFileIn(storage)).writeAsString(jsonEncode(form.toJson()));
}

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
