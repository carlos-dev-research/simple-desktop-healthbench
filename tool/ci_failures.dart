// CI helper: turns failed tests in a `flutter test --file-reporter json:<file>`
// report into GitHub annotations (`::error title=…::…`), so failures are
// readable on the run page without access to the raw logs.
//
//   dart run tool/ci_failures.dart build/test-report.json
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final file = File(args.isEmpty ? 'build/test-report.json' : args.first);
  if (!file.existsSync()) {
    stdout.writeln('::warning::No test report at ${file.path}');
    return;
  }
  final names = <int, String>{};
  final errors = <int, List<String>>{};
  final failed = <int>[];
  for (final line in file.readAsLinesSync()) {
    final Object? event;
    try {
      event = jsonDecode(line);
    } on FormatException {
      continue;
    }
    switch (event) {
      case {
        'type': 'testStart',
        'test': {'id': final int id, 'name': final String name},
      }:
        names[id] = name;
      case {
        'type': 'error',
        'testID': final int id,
        'error': final String error,
      }:
        (errors[id] ??= []).add(error);
      case {
            'type': 'testDone',
            'testID': final int id,
            'result': final String result,
          }
          when result != 'success':
        failed.add(id);
    }
  }
  for (final id in failed) {
    final title = _escape(names[id] ?? 'test $id');
    final message = _escape(
      (errors[id] ?? const ['(no message)'])
          .join('\n')
          .split('\n')
          .take(12)
          .join('\n'),
    );
    stdout.writeln('::error title=$title::$message');
  }
  stdout.writeln('${failed.length} failed test(s) reported');
}

/// GitHub workflow-command escaping.
String _escape(String s) =>
    s.replaceAll('%', '%25').replaceAll('\r', '%0D').replaceAll('\n', '%0A');
