/// The dataset library: official HealthBench files downloaded and verified,
/// local files added, and reproducible samples (spec 005).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'dataset.dart';
import 'run_file.dart' show isSamePath;
import 'seeded_random.dart';

/// Where the official files are published (Constitution III.2: the only
/// host the app downloads from).
final Uri officialDatasetHost = Uri.parse(
  'https://openaipublic.blob.core.windows.net/simple-evals/healthbench',
);

/// An official file, pinned by size, SHA-256 and conversation count. The
/// values come from copies whose MD5 matches the host's Content-MD5.
class OfficialDataset {
  const OfficialDataset({
    required this.fileName,
    required this.label,
    required this.description,
    required this.bytes,
    required this.sha256,
    required this.conversations,
  });

  final String fileName;
  final String label;
  final String description;
  final int bytes;
  final String sha256;
  final int conversations;
}

const List<OfficialDataset> officialDatasets = [
  OfficialDataset(
    fileName: '2025-05-07-06-14-12_oss_eval.jsonl',
    label: 'HealthBench (main)',
    description: 'The full benchmark: 5,000 conversations.',
    bytes: 60258154,
    sha256: 'e99dd3c6372c10d6fcc5e385c5fae69d0dd40392dae56836ef9493ae324ecd2f',
    conversations: 5000,
  ),
  OfficialDataset(
    fileName: 'hard_2025-05-08-21-00-10.jsonl',
    label: 'HealthBench Hard',
    description: 'The 1,000 conversations frontier models found hardest.',
    bytes: 12581564,
    sha256: 'b0320430e5cd974e746585594c1dd10b5a3fc2aff9c72b26106c2c4a069d74e9',
    conversations: 1000,
  ),
  OfficialDataset(
    fileName: 'consensus_2025-05-09-20-00-46.jsonl',
    label: 'HealthBench Consensus',
    description:
        'Criteria validated by physician consensus: 3,671 conversations.',
    bytes: 36921504,
    sha256: 'fabe37553327238928b05357d8b309737b5d426d6dee432a3376da618d0969d6',
    conversations: 3671,
  ),
];

enum DatasetOrigin { official, sample, added }

/// A dataset file in the library.
class LibraryDataset {
  const LibraryDataset({
    required this.path,
    required this.conversations,
    required this.bytes,
    required this.sha256,
    required this.origin,
    this.sampleOf,
  });

  final String path;
  final int conversations;
  final int bytes;
  final String sha256;
  final DatasetOrigin origin;

  /// For a sample: the file it was made from.
  final String? sampleOf;

  String get fileName => fileNameOf(path);
}

/// A download that failed verification or transfer.
class DatasetDownloadException implements Exception {
  const DatasetDownloadException(this.reason);

  final String reason;

  @override
  String toString() => 'Download failed: $reason';
}

/// The user cancelled a download.
class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

String _inDir(String dir, String name) => '$dir${Platform.pathSeparator}$name';

// ------------------------------------------------------------------ index

const _indexName = 'library.json';
final RegExp _sampleName = RegExp(r'_N\d+_seed\d+\.jsonl$');

/// What the index remembers about each file (origin is only known here).
class _IndexEntry {
  _IndexEntry(
    this.size,
    this.modified,
    this.sha256,
    this.conversations,
    this.origin,
    this.sampleOf,
  );

  final int size;
  final int modified;
  final String sha256;
  final int conversations;
  final DatasetOrigin origin;
  final String? sampleOf;

  Map<String, Object?> toJson() => {
    'size': size,
    'modified': modified,
    'sha256': sha256,
    'conversations': conversations,
    'origin': origin.name,
    'sampleOf': sampleOf,
  };

  static _IndexEntry? fromJson(Object? json) {
    if (json case {
      'size': final int size,
      'modified': final int modified,
      'sha256': final String sha,
      'conversations': final int count,
      'origin': final String origin,
    }) {
      final known = DatasetOrigin.values.where((o) => o.name == origin);
      if (known.isEmpty) return null;
      final sampleOf = (json as Map<String, Object?>)['sampleOf'];
      return _IndexEntry(
        size,
        modified,
        sha,
        count,
        known.first,
        sampleOf is String ? sampleOf : null,
      );
    }
    return null;
  }
}

Future<Map<String, _IndexEntry>> _readIndex(String dir) async {
  try {
    final json = jsonDecode(await File(_inDir(dir, _indexName)).readAsString());
    if (json is! Map<String, Object?>) return {};
    return {
      for (final MapEntry(:key, :value) in json.entries)
        key: ?_IndexEntry.fromJson(value),
    };
  } on Object {
    return {}; // Missing or corrupt: rebuilt from the files.
  }
}

Future<void> _writeIndex(String dir, Map<String, _IndexEntry> index) async {
  final tmp = File(_inDir(dir, '$_indexName.tmp'));
  await tmp.writeAsString(
    jsonEncode({for (final e in index.entries) e.key: e.value.toJson()}),
  );
  await tmp.rename(_inDir(dir, _indexName));
}

DatasetOrigin _inferOrigin(String name, String sha) {
  if (officialDatasets.any((d) => d.fileName == name && d.sha256 == sha)) {
    return DatasetOrigin.official;
  }
  return _sampleName.hasMatch(name)
      ? DatasetOrigin.sample
      : DatasetOrigin.added;
}

Future<LibraryDataset> _record(
  String dir,
  String path, {
  required int conversations,
  required String sha,
  required DatasetOrigin origin,
  String? sampleOf,
}) async {
  final stat = await File(path).stat();
  final index = await _readIndex(dir);
  index[fileNameOf(path)] = _IndexEntry(
    stat.size,
    stat.modified.millisecondsSinceEpoch,
    sha,
    conversations,
    origin,
    sampleOf,
  );
  await _writeIndex(dir, index);
  return LibraryDataset(
    path: path,
    conversations: conversations,
    bytes: stat.size,
    sha256: sha,
    origin: origin,
    sampleOf: sampleOf,
  );
}

/// Every valid dataset in [dir], by name. Unchanged files come from the
/// index; changed or new ones are read again. Partial downloads (`.part`)
/// and invalid files are left out.
Future<List<LibraryDataset>> listLibrary(String dir) async {
  if (!await Directory(dir).exists()) return const [];
  final index = await _readIndex(dir);
  final result = <LibraryDataset>[];
  var changed = false;
  final present = <String>{};
  await for (final entity in Directory(dir).list()) {
    if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
    final name = fileNameOf(entity.path);
    present.add(name);
    final stat = await entity.stat();
    var entry = index[name];
    if (entry == null ||
        entry.size != stat.size ||
        entry.modified != stat.modified.millisecondsSinceEpoch) {
      final Dataset dataset;
      try {
        dataset = await readDataset(entity.path);
      } on DatasetFormatException {
        continue;
      }
      entry = _IndexEntry(
        stat.size,
        stat.modified.millisecondsSinceEpoch,
        dataset.sha256,
        dataset.conversations.length,
        entry?.origin ?? _inferOrigin(name, dataset.sha256),
        entry?.sampleOf,
      );
      index[name] = entry;
      changed = true;
    }
    result.add(
      LibraryDataset(
        path: entity.path,
        conversations: entry.conversations,
        bytes: entry.size,
        sha256: entry.sha256,
        origin: entry.origin,
        sampleOf: entry.sampleOf,
      ),
    );
  }
  if (index.keys.any((k) => !present.contains(k))) {
    index.removeWhere((k, _) => !present.contains(k));
    changed = true;
  }
  if (changed) await _writeIndex(dir, index);
  result.sort((a, b) => a.fileName.compareTo(b.fileName));
  return result;
}

// --------------------------------------------------------------- download

/// Downloads [dataset] from [host] into [dir]: streamed to `<name>.part`
/// with [onProgress], then accepted only if its size, SHA-256 and
/// conversation count match the pinned values and the dataset reader
/// accepts it. [cancel] aborts it. A failed or cancelled download never
/// leaves a file behind (FR-002).
Future<LibraryDataset> downloadOfficial(
  OfficialDataset dataset,
  String dir, {
  Uri? host,
  http.Client? client,
  Future<void>? cancel,
  void Function(int received, int total)? onProgress,
}) async {
  await Directory(dir).create(recursive: true);
  final base = host ?? officialDatasetHost;
  final url = base.replace(path: '${base.path}/${dataset.fileName}');
  final part = File(_inDir(dir, '${dataset.fileName}.part'));
  final http.Client http0 = client ?? http.Client();
  try {
    final request = http.AbortableRequest('GET', url, abortTrigger: cancel);
    final http.StreamedResponse response;
    try {
      response = await http0.send(request);
    } on http.RequestAbortedException {
      throw const DownloadCancelled();
    } on http.ClientException catch (e) {
      throw DatasetDownloadException('could not connect (${e.message})');
    } on SocketException catch (e) {
      throw DatasetDownloadException('could not connect (${e.message})');
    }
    if (response.statusCode != 200) {
      throw DatasetDownloadException(
        'the server answered HTTP ${response.statusCode}',
      );
    }
    final sink = part.openWrite();
    var received = 0;
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > dataset.bytes) {
          throw const DatasetDownloadException(
            'the file is larger than expected',
          );
        }
        sink.add(chunk);
        hasher.add(chunk);
        onProgress?.call(received, dataset.bytes);
      }
    } on http.RequestAbortedException {
      throw const DownloadCancelled();
    } on http.ClientException catch (e) {
      throw DatasetDownloadException('the connection broke (${e.message})');
    } finally {
      await sink.close();
    }
    hasher.close();
    if (received != dataset.bytes) {
      throw DatasetDownloadException(
        'expected ${dataset.bytes} bytes, got $received',
      );
    }
    if (digest.value.toString() != dataset.sha256) {
      throw const DatasetDownloadException(
        'the file does not match the official SHA-256',
      );
    }
    final Dataset parsed;
    try {
      parsed = await readDataset(part.path);
    } on DatasetFormatException catch (e) {
      throw DatasetDownloadException('the file is not a valid dataset ($e)');
    }
    if (parsed.conversations.length != dataset.conversations) {
      throw DatasetDownloadException(
        'expected ${dataset.conversations} conversations, got ${parsed.conversations.length}',
      );
    }
    final target = _inDir(dir, dataset.fileName);
    await part.rename(target);
    return await _record(
      dir,
      target,
      conversations: parsed.conversations.length,
      sha: parsed.sha256,
      origin: DatasetOrigin.official,
    );
  } finally {
    if (await part.exists()) await part.delete();
    if (client == null) http0.close();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

// -------------------------------------------------------------- add a file

/// The result of adding a local file.
class AddResult {
  const AddResult(this.entry, {required this.alreadyPresent});

  final LibraryDataset entry;

  /// The identical file (same SHA-256) was already in the library.
  final bool alreadyPresent;
}

/// Validates [sourcePath] with the dataset reader, then copies it into the
/// library (the original is untouched). A name already taken by a different
/// file gets a `-2`, `-3`, … suffix (FR-010). Throws [DatasetFormatException].
Future<AddResult> addDatasetFile(String sourcePath, String dir) async {
  final dataset = await readDataset(sourcePath);
  await Directory(dir).create(recursive: true);
  for (final existing in await listLibrary(dir)) {
    if (existing.sha256 == dataset.sha256) {
      return AddResult(existing, alreadyPresent: true);
    }
  }
  var name = fileNameOf(sourcePath);
  if (!name.endsWith('.jsonl')) name = '$name.jsonl';
  final stem = name.substring(0, name.length - '.jsonl'.length);
  var target = _inDir(dir, name);
  for (var n = 2; await File(target).exists(); n++) {
    target = _inDir(dir, '$stem-$n.jsonl');
  }
  final staged = File('$target.adding');
  try {
    await File(sourcePath).copy(staged.path);
    await staged.rename(target);
  } finally {
    if (await staged.exists()) await staged.delete();
  }
  final entry = await _record(
    dir,
    target,
    conversations: dataset.conversations.length,
    sha: dataset.sha256,
    origin: DatasetOrigin.added,
  );
  return AddResult(entry, alreadyPresent: false);
}

// ----------------------------------------------------------------- samples

/// A random sample of [n] conversations from [source], chosen with the
/// seeded SplitMix64 generator (partial Fisher–Yates) so the same source,
/// [n] and [seed] always give a byte-identical file. The chosen records are
/// written as their original lines, in their original order. Named
/// `<source>_N<n>_seed<seed>.jsonl` (FR-006, FR-007).
Future<LibraryDataset> createSample(
  LibraryDataset source,
  int n,
  int seed,
  String dir,
) async {
  if (n < 1 || n > source.conversations) {
    throw ArgumentError.value(
      n,
      'n',
      'Must be between 1 and ${source.conversations}',
    );
  }
  final stem = source.fileName.substring(
    0,
    source.fileName.length - '.jsonl'.length,
  );
  final target = _inDir(dir, '${stem}_N${n}_seed$seed.jsonl');
  if (await File(target).exists()) {
    final listed = await listLibrary(dir);
    return listed.firstWhere((d) => d.fileName == fileNameOf(target));
  }
  final sourcePath = source.path;
  final text = await Isolate.run(() => _sampleText(sourcePath, n, seed));
  final staged = File('$target.sampling');
  try {
    await staged.writeAsString(text);
    await staged.rename(target);
  } finally {
    if (await staged.exists()) await staged.delete();
  }
  final bytes = utf8.encode(text);
  return _record(
    dir,
    target,
    conversations: n,
    sha: sha256.convert(bytes).toString(),
    origin: DatasetOrigin.sample,
    sampleOf: source.fileName,
  );
}

String _sampleText(String path, int n, int seed) {
  final lines = [
    for (final line in const LineSplitter().convert(
      File(path).readAsStringSync(),
    ))
      if (line.trim().isNotEmpty) line,
  ];
  final indexes = List<int>.generate(lines.length, (i) => i);
  final rng = SplitMix64(seed);
  for (var i = 0; i < n; i++) {
    final j = i + rng.nextIntBelow(lines.length - i);
    final swap = indexes[i];
    indexes[i] = indexes[j];
    indexes[j] = swap;
  }
  final chosen = indexes.sublist(0, n)..sort();
  return '${chosen.map((i) => lines[i]).join('\n')}\n';
}

// ------------------------------------------------------------------ delete

/// Removes a dataset from the library. Refused for a dataset in [inUse]
/// (for example the active run's) (FR-008).
Future<void> deleteDataset(String path, {Set<String> inUse = const {}}) async {
  if (inUse.any((p) => isSamePath(p, path))) {
    throw StateError('This dataset is used by the run in progress');
  }
  await File(path).delete();
  final dir = File(path).parent.path;
  final index = await _readIndex(dir);
  if (index.remove(fileNameOf(path)) != null) await _writeIndex(dir, index);
}
