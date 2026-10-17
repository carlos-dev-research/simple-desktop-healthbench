import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

/// Renders Markdown from model output safely (spec 003 US5-1, research R3):
/// the parsed tree is drawn with plain widgets, so raw HTML stays literal
/// text, links are not tappable, and images are shown as their description.
/// Nothing is ever loaded from the network.
class MarkdownView extends StatelessWidget {
  const MarkdownView(this.data, {super.key});

  final String data;

  @override
  Widget build(BuildContext context) {
    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parse(data);
    final renderer = _Renderer(Theme.of(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: renderer.blocks(nodes),
    );
  }
}

const _blockTags = {
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', 'pre', //
  'blockquote', 'hr', 'table', 'thead', 'tbody', 'tr', 'div', 'section',
};

class _Renderer {
  _Renderer(this.theme);

  final ThemeData theme;
  TextTheme get _text => theme.textTheme;
  ColorScheme get _colors => theme.colorScheme;

  static const _gap = SizedBox(height: 8);

  List<Widget> blocks(List<md.Node> nodes) {
    final out = <Widget>[];
    final inline = <md.Node>[];
    void flushInline() {
      if (inline.isEmpty) return;
      out.add(_paragraph(List.of(inline), _text.bodyMedium));
      inline.clear();
    }

    for (final node in nodes) {
      if (node is md.Element && _blockTags.contains(node.tag)) {
        flushInline();
        out.add(_block(node));
      } else {
        inline.add(node);
      }
    }
    flushInline();
    return [
      for (final (i, w) in out.indexed) ...[if (i > 0) _gap, w],
    ];
  }

  Widget _block(md.Element e) {
    final children = e.children ?? const <md.Node>[];
    switch (e.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final style = switch (e.tag) {
          'h1' => _text.headlineSmall,
          'h2' => _text.titleLarge,
          'h3' => _text.titleMedium,
          _ => _text.titleSmall,
        };
        return _paragraph(
          children,
          style?.copyWith(fontWeight: FontWeight.w600),
        );
      case 'p':
        return _paragraph(children, _text.bodyMedium);
      case 'ul' || 'ol':
        return _list(e);
      case 'pre':
        return _codeBlock(e.textContent);
      case 'blockquote':
        return Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: _colors.outlineVariant, width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: blocks(children),
          ),
        );
      case 'hr':
        return const Divider();
      case 'table':
        return _table(e);
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: blocks(children),
        );
    }
  }

  Widget _paragraph(List<md.Node> nodes, TextStyle? style) =>
      Text.rich(TextSpan(style: style, children: _inline(nodes)));

  List<InlineSpan> _inline(List<md.Node> nodes, [TextStyle? style]) => [
    for (final node in nodes) _span(node, style),
  ];

  InlineSpan _span(md.Node node, TextStyle? style) {
    if (node is md.Text) return TextSpan(text: node.text, style: style);
    if (node is! md.Element) {
      return TextSpan(text: node.textContent, style: style);
    }
    final base = style ?? const TextStyle();
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'strong':
        return TextSpan(
          children: _inline(
            children,
            base.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      case 'em':
        return TextSpan(
          children: _inline(
            children,
            base.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      case 'del':
        return TextSpan(
          children: _inline(
            children,
            base.copyWith(decoration: TextDecoration.lineThrough),
          ),
        );
      case 'code':
        return TextSpan(
          text: node.textContent,
          style: base.copyWith(
            fontFamily: 'monospace',
            backgroundColor: _colors.surfaceContainerHighest,
          ),
        );
      case 'a':
        // Shown, never opened: no gesture recognizer (Constitution IV).
        return TextSpan(
          children: _inline(
            children,
            base.copyWith(
              color: _colors.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        );
      case 'img':
        final alt = node.attributes['alt'] ?? '';
        return TextSpan(
          text: '[image: $alt]',
          style: base.copyWith(fontStyle: FontStyle.italic),
        );
      case 'br':
        return TextSpan(text: '\n', style: style);
      case 'input':
        return TextSpan(
          text: node.attributes['checked'] != null ? '☑ ' : '☐ ',
          style: style,
        );
      default:
        return TextSpan(children: _inline(children, style));
    }
  }

  Widget _list(md.Element list) {
    final ordered = list.tag == 'ol';
    final start = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    final items = [
      for (final child in list.children ?? const <md.Node>[])
        if (child is md.Element && child.tag == 'li') child,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, item) in items.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    ordered ? '${start + i}.' : '•',
                    style: _text.bodyMedium,
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: blocks(item.children ?? const []),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _codeBlock(String code) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Text(
        code.endsWith('\n') ? code.substring(0, code.length - 1) : code,
        style: _text.bodySmall?.copyWith(fontFamily: 'monospace'),
      ),
    ),
  );

  Widget _table(md.Element table) {
    final rows = <(md.Element, bool)>[];
    void collect(md.Element e, {required bool header}) {
      for (final child in e.children ?? const <md.Node>[]) {
        if (child is! md.Element) continue;
        if (child.tag == 'tr') {
          rows.add((child, header));
        } else {
          collect(child, header: header || child.tag == 'thead');
        }
      }
    }

    collect(table, header: false);
    final columns = rows.fold<int>(
      0,
      (max, r) =>
          (r.$1.children?.length ?? 0) > max ? r.$1.children!.length : max,
    );
    if (columns == 0) return const SizedBox.shrink();

    TableRow buildRow(md.Element tr, bool header) {
      final cells = [
        for (final c in tr.children ?? const <md.Node>[])
          if (c is md.Element) c,
      ];
      return TableRow(
        decoration: header
            ? BoxDecoration(color: _colors.surfaceContainerHigh)
            : null,
        children: [
          for (var i = 0; i < columns; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              // Cells wrap at a readable width; the table scrolls sideways.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: i < cells.length
                    ? _paragraph(
                        cells[i].children ?? const [],
                        header
                            ? _text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              )
                            : _text.bodyMedium,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: _colors.outlineVariant),
        children: [for (final (tr, header) in rows) buildRow(tr, header)],
      ),
    );
  }
}
