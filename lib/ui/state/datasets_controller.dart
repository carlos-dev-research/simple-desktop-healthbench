import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dataset_library.dart';
import 'providers.dart';
import 'run_controller.dart';

/// Where library datasets live: `<storage>/datasets` (spec 005 FR-003).
String datasetsDirectoryIn(String storage) =>
    '$storage${Platform.pathSeparator}datasets';

/// The official files offered for download; tests use small pinned fixtures.
final officialDatasetsProvider = Provider<List<OfficialDataset>>(
  (ref) => officialDatasets,
);

/// The download host; tests point it at a local fake host.
final datasetHostProvider = Provider<Uri>((ref) => officialDatasetHost);

/// Chooses a local dataset file to add to the library (spec 005 FR-010).
final addFilePickerProvider = Provider<DatasetPicker>(
  (ref) => () async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'HealthBench dataset', extensions: ['jsonl']),
      ],
    );
    return file?.path;
  },
);

/// Progress of one download, by file name.
class DownloadProgress {
  const DownloadProgress(this.received, this.total);

  final int received;
  final int total;

  double get fraction => total == 0 ? 0 : received / total;
}

/// The dataset library and its operations (spec 005).
class DatasetLibraryController extends AsyncNotifier<List<LibraryDataset>> {
  @override
  Future<List<LibraryDataset>> build() async => listLibrary(await _dir());

  Future<String> _dir() async =>
      datasetsDirectoryIn(await ref.read(storageDirectoryProvider.future));

  Future<void> refresh() async {
    state = await AsyncValue.guard(() async => listLibrary(await _dir()));
  }

  /// Validates and copies a local file in.
  Future<AddResult> addFile(String path) async {
    final result = await addDatasetFile(path, await _dir());
    await refresh();
    return result;
  }

  Future<LibraryDataset> sample(LibraryDataset source, int n, int seed) async {
    final made = await createSample(source, n, seed, await _dir());
    await refresh();
    return made;
  }

  /// Refused while the active run reads this dataset (FR-008).
  Future<void> delete(LibraryDataset dataset) async {
    final inUse = ref.read(runControllerProvider.notifier).activeDatasetPath;
    await deleteDataset(dataset.path, inUse: {?inUse});
    await refresh();
  }
}

final datasetLibraryProvider =
    AsyncNotifierProvider<DatasetLibraryController, List<LibraryDataset>>(
      DatasetLibraryController.new,
    );

/// Downloads in progress, by official file name; cancel with [cancel].
class DownloadsController extends Notifier<Map<String, DownloadProgress>> {
  final Map<String, Completer<void>> _cancels = {};

  @override
  Map<String, DownloadProgress> build() => const {};

  bool isDownloading(String fileName) => _cancels.containsKey(fileName);

  /// Downloads and verifies [dataset]; throws [DatasetDownloadException] or
  /// [DownloadCancelled]. The library is refreshed on success.
  Future<LibraryDataset> download(OfficialDataset dataset) async {
    if (_cancels.containsKey(dataset.fileName)) {
      throw StateError('Already downloading ${dataset.fileName}');
    }
    final cancel = Completer<void>();
    _cancels[dataset.fileName] = cancel;
    state = {...state, dataset.fileName: DownloadProgress(0, dataset.bytes)};
    try {
      final storage = await ref.read(storageDirectoryProvider.future);
      final entry = await downloadOfficial(
        dataset,
        datasetsDirectoryIn(storage),
        host: ref.read(datasetHostProvider),
        cancel: cancel.future,
        onProgress: (received, total) {
          state = {
            ...state,
            dataset.fileName: DownloadProgress(received, total),
          };
        },
      );
      await ref.read(datasetLibraryProvider.notifier).refresh();
      return entry;
    } finally {
      _cancels.remove(dataset.fileName);
      state = {...state}..remove(dataset.fileName);
    }
  }

  void cancel(String fileName) {
    final c = _cancels[fileName];
    if (c != null && !c.isCompleted) c.complete();
  }
}

final downloadsProvider =
    NotifierProvider<DownloadsController, Map<String, DownloadProgress>>(
      DownloadsController.new,
    );
