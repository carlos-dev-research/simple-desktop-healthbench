import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dataset.dart';
import '../../core/runner.dart';
import '../../core/settings.dart';
import '../state/providers.dart';
import '../state/run_controller.dart';
import '../state/runs_controller.dart';
import 'dataset_field.dart';
import 'progress_panel.dart';

/// The New-run form and the live progress panel (spec 003 US1, US2).
class NewRunView extends ConsumerStatefulWidget {
  const NewRunView({super.key});

  @override
  ConsumerState<NewRunView> createState() => _NewRunViewState();
}

class _NewRunViewState extends ConsumerState<NewRunView> {
  final _form = GlobalKey<FormState>();
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _modelTest = TextEditingController();
  final _modelGrader = TextEditingController();
  final _limit = TextEditingController();
  var _effortTest = ReasoningEffort.low;
  var _effortGrader = ReasoningEffort.low;
  var _showKey = false;
  var _starting = false;
  String? _datasetPath;
  String? _datasetLabel;
  String? _datasetError;
  String? _startError;

  @override
  void dispose() {
    for (final c in [_baseUrl, _apiKey, _modelTest, _modelGrader, _limit]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Restores the session's form (spec 003 FR-004, amended): values survive
  /// switching views and are gone when the app quits.
  @override
  void initState() {
    super.initState();
    final form = ref.read(newRunFormProvider);
    _baseUrl.text = form.baseUrl;
    _apiKey.text = form.apiKey;
    _modelTest.text = form.modelTest;
    _modelGrader.text = form.modelGrader;
    _limit.text = form.limit;
    _effortTest = form.effortTest;
    _effortGrader = form.effortGrader;
    _datasetPath = form.datasetPath;
    _datasetLabel = form.datasetLabel;
    for (final c in [_baseUrl, _apiKey, _modelTest, _modelGrader, _limit]) {
      c.addListener(_save);
    }
  }

  /// Keeps the session's form in step with the fields.
  void _save() => ref
      .read(newRunFormProvider.notifier)
      .update(
        (f) => f.copyWith(
          baseUrl: _baseUrl.text,
          apiKey: _apiKey.text,
          modelTest: _modelTest.text,
          effortTest: _effortTest,
          modelGrader: _modelGrader.text,
          effortGrader: _effortGrader,
          limit: _limit.text,
        ),
      );

  String? _validateBaseUrl(String? value) {
    try {
      ConnectionSettings.parseBaseUrl(value ?? '');
      return null;
    } on ArgumentError catch (e) {
      return '${e.message}';
    }
  }

  String? _required(String? value, String what) =>
      (value ?? '').trim().isEmpty ? '$what is required' : null;

  String? _validateLimit(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final n = int.tryParse(text);
    return n == null || n < 1 ? 'Enter a whole number of at least 1' : null;
  }

  Future<void> _start() async {
    final valid = _form.currentState!.validate();
    setState(() {
      _datasetError = _datasetPath == null ? 'Choose a dataset file' : null;
      _startError = null;
    });
    if (!valid || _datasetPath == null) return;

    final limitText = _limit.text.trim();
    final limit = limitText.isEmpty ? null : int.parse(limitText);
    setState(() => _starting = true);
    try {
      await ref
          .read(runControllerProvider.notifier)
          .start(
            datasetPath: _datasetPath!,
            limit: limit,
            connection: ConnectionSettings(
              baseUrl: _baseUrl.text.trim(),
              apiKey: _apiKey.text.trim(),
            ),
            modelTest: ModelSettings(
              name: _modelTest.text.trim(),
              reasoningEffort: _effortTest,
            ),
            modelGrader: ModelSettings(
              name: _modelGrader.text.trim(),
              reasoningEffort: _effortGrader,
            ),
          );
    } on RunStartException catch (e) {
      _showStartError(e.reason);
    } on DatasetFormatException catch (e) {
      _showStartError('$e');
    } on FileSystemException catch (e) {
      // A moved or deleted dataset is the usual cause (code review #8).
      _showStartError(
        e.path == _datasetPath
            ? 'Could not read the dataset file: ${e.osError?.message ?? e.message}. Choose it again.'
            : 'Could not save the run: ${e.message}',
      );
    } on StateError catch (e) {
      _showStartError(e.message);
    } on ArgumentError catch (e) {
      _showStartError('${e.message}');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// The view may have been left while the run was starting (code review #8).
  void _showStartError(String message) {
    if (mounted) setState(() => _startError = message);
  }

  void _openResults(String? path) {
    ref.read(selectedRunProvider.notifier).select(path);
    ref.read(currentViewProvider.notifier).show(AppView.runs);
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(runControllerProvider);
    final running = active.isRunning;

    final form = _buildForm(context, running);
    final panel = active.progress == null
        ? null
        : ProgressPanel(
            progress: active.progress!,
            runFilePath: active.runFilePath,
            modelsLabel: active.modelsLabel,
            onStop: () => ref.read(runControllerProvider.notifier).stop(),
            onOpenResults: () => _openResults(active.runFilePath),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: form,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: panel ?? const SizedBox.shrink(),
                ),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (panel != null) ...[panel, const SizedBox(height: 16)],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: form,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildForm(BuildContext context, bool running) {
    final theme = Theme.of(context);
    InputDecoration field(String label, {String? helper}) =>
        InputDecoration(labelText: label, helperText: helper);
    Widget effort(
      String label,
      ReasoningEffort value,
      ValueChanged<ReasoningEffort> onChanged,
    ) => SizedBox(
      width: 150,
      child: DropdownButtonFormField<ReasoningEffort>(
        initialValue: value,
        isExpanded: true,
        // The closed field shows the short name; the menu explains "none".
        selectedItemBuilder: (context) => [
          for (final e in ReasoningEffort.values)
            Text(e.name, overflow: TextOverflow.ellipsis),
        ],
        decoration: InputDecoration(labelText: label),
        items: [
          for (final e in ReasoningEffort.values)
            DropdownMenuItem(
              value: e,
              child: Text(
                e == ReasoningEffort.none ? 'none (don\'t send)' : e.name,
              ),
            ),
        ],
        onChanged: (e) => setState(() => onChanged(e!)),
      ),
    );

    return Form(
      key: _form,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): () {
            if (!running && !_starting) _start();
          },
        },
        child: FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New evaluation run', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _baseUrl,
                decoration: field(
                  'Base URL',
                  helper: 'Any OpenAI-compatible endpoint, e.g. https://api.groq.com/openai/v1',
                ),
                validator: _validateBaseUrl,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _apiKey,
                obscureText: !_showKey,
                autocorrect: false,
                enableSuggestions: false,
                decoration:
                    field(
                      'API key',
                      helper: 'Kept in memory only; never saved',
                    ).copyWith(
                      suffixIcon: IconButton(
                        tooltip: _showKey ? 'Hide' : 'Show',
                        icon: Icon(
                          _showKey ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () => setState(() => _showKey = !_showKey),
                      ),
                    ),
                validator: (v) => _required(v, 'The API key'),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _modelTest,
                      decoration: field('Model under test'),
                      validator: (v) => _required(v, 'The model'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  effort('Reasoning effort', _effortTest, (e) {
                    _effortTest = e;
                    _save();
                  }),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _modelGrader,
                      decoration: field('Grader model'),
                      validator: (v) => _required(v, 'The grader model'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  effort('Reasoning effort', _effortGrader, (e) {
                    _effortGrader = e;
                    _save();
                  }),
                ],
              ),
              const SizedBox(height: 16),
              DatasetField(
                initialLabel: _datasetLabel,
                initialPath: _datasetPath,
                onChanged: (path, label) {
                  setState(() {
                    _datasetPath = path;
                    _datasetLabel = label;
                    if (path != null) _datasetError = null;
                  });
                  ref
                      .read(newRunFormProvider.notifier)
                      .update((f) => f.withDataset(path, label));
                },
              ),
              if (_datasetError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _datasetError!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: 260,
                child: TextFormField(
                  controller: _limit,
                  decoration: field(
                    'Max conversations (optional)',
                    helper: 'Only the first N',
                  ),
                  keyboardType: TextInputType.number,
                  validator: _validateLimit,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start run'),
                    onPressed: running || _starting ? null : _start,
                  ),
                  const SizedBox(width: 12),
                  if (_starting)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (running)
                    Text(
                      'A run is in progress.',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
              if (_startError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _startError!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
