// Safe Markdown rendering of model output (spec 003 US5-1, FR-015;
// Constitution IV).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthbench/ui/markdown/markdown_view.dart';

Future<void> pump(WidgetTester tester, String markdown) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: MarkdownView(markdown))),
  ),
);

Finder text(String s) => find.textContaining(s, findRichText: true);

/// Every TextSpan in the tree, flattened.
List<TextSpan> spans(WidgetTester tester) => [
  for (final rich in tester.widgetList<RichText>(find.byType(RichText)))
    ..._flatten(rich.text),
];

Iterable<TextSpan> _flatten(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _flatten(child);
    }
  }
}

void main() {
  testWidgets('headings, paragraphs, emphasis, code and lists', (tester) async {
    await pump(tester, '''
# Plan

Some **bold** and *italic* and `code` and ~~gone~~.

- apple
- banana
  1. nested

```
fenced block
```
''');
    expect(text('Plan'), findsOneWidget);
    expect(text('bold'), findsOneWidget);
    expect(text('apple'), findsOneWidget);
    expect(text('banana'), findsOneWidget);
    expect(text('nested'), findsOneWidget);
    expect(text('fenced block'), findsOneWidget);

    final all = spans(tester);
    TextSpan spanOf(String t) => all.firstWhere((s) => s.text == t);
    expect(spanOf('bold').style?.fontWeight, FontWeight.bold);
    expect(spanOf('italic').style?.fontStyle, FontStyle.italic);
    expect(spanOf('gone').style?.decoration, TextDecoration.lineThrough);
    expect(spanOf('code').style?.fontFamily, 'monospace');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tables render their cells', (tester) async {
    await pump(tester, '''
| Month | Focus |
|-------|-------|
| 1 | Stabilize |
| 2 | **Therapy** |
''');
    expect(find.byType(Table), findsOneWidget);
    expect(text('Month'), findsOneWidget);
    expect(text('Stabilize'), findsOneWidget);
    expect(text('Therapy'), findsOneWidget);
  });

  testWidgets('raw HTML is shown as text, never interpreted', (tester) async {
    await pump(tester, 'Hi <b>there</b>\n\n<script>alert("x")</script>\n');
    expect(text('<b>there</b>'), findsOneWidget);
    expect(text('<script>alert("x")</script>'), findsOneWidget);
  });

  testWidgets('links are shown but not tappable; images are text only', (
    tester,
  ) async {
    await pump(
      tester,
      'See [the guide](https://example.com) ![a chart](https://example.com/x.png)',
    );
    expect(text('the guide'), findsOneWidget);
    expect(text('[image: a chart]'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    final recognizers = spans(tester)
        .map((s) => s.recognizer)
        .whereType<GestureRecognizer>();
    expect(recognizers, isEmpty);
  });

  testWidgets('a very wide table does not overflow', (tester) async {
    final row = List.filled(12, 'a long cell value').join(' | ');
    await pump(
      tester,
      '| ${List.filled(12, 'h').join(' | ')} |\n|${List.filled(12, '---').join('|')}|\n| $row |\n',
    );
    expect(tester.takeException(), isNull);
  });
}
