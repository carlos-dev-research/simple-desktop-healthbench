import 'package:flutter/material.dart';

import '../../core/run_summary.dart';

/// Bar chart of conversation scores in the reference's 11 bins
/// (spec 003 US3-2, research R4).
class ScoreHistogram extends StatelessWidget {
  const ScoreHistogram(this.counts, {super.key});

  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label:
          'Histogram of conversation scores: '
          '${[for (final (i, c) in counts.indexed) '${histogramLabels[i]}: $c'].join(', ')}',
      child: SizedBox(
        height: 180,
        child: CustomPaint(
          size: Size.infinite,
          painter: _HistogramPainter(
            counts: counts,
            bar: theme.colorScheme.primary,
            axis: theme.colorScheme.outlineVariant,
            label: theme.textTheme.labelSmall!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  _HistogramPainter({
    required this.counts,
    required this.bar,
    required this.axis,
    required this.label,
  });

  final List<int> counts;
  final Color bar;
  final Color axis;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 18.0;
    const top = 16.0;
    final plotHeight = size.height - bottom - top;
    final slot = size.width / counts.length;
    final max = counts.fold<int>(1, (m, c) => c > m ? c : m);

    canvas.drawLine(
      Offset(0, top + plotHeight),
      Offset(size.width, top + plotHeight),
      Paint()..color = axis,
    );
    for (final (i, count) in counts.indexed) {
      final height = plotHeight * count / max;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          i * slot + 3,
          top + plotHeight - height,
          slot - 6,
          height,
        ),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, Paint()..color = bar);
      final centre = i * slot + slot / 2;
      if (count > 0) {
        _text(canvas, '$count', centre, top + plotHeight - height - 14);
      }
      _text(canvas, histogramLabels[i], centre, top + plotHeight + 3);
    }
  }

  void _text(Canvas canvas, String text, double centreX, double y) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: label),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(centreX - painter.width / 2, y));
  }

  @override
  bool shouldRepaint(_HistogramPainter old) =>
      old.counts != counts || old.bar != bar || old.label != label;
}
