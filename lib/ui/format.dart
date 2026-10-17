/// Display formatting shared by the views.
library;

/// A score with three decimals, or a dash when there is none.
String formatScore(double? score) =>
    score == null ? '–' : score.toStringAsFixed(3);

/// `part` of `total` as a whole percentage.
String formatPercent(int part, int total) =>
    total == 0 ? '–' : '${(100 * part / total).round()}%';

/// h:mm:ss, or m:ss under an hour.
String formatDuration(Duration? d) {
  if (d == null) return '–';
  final seconds = d.inSeconds;
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Local date and time as YYYY-MM-DD HH:MM.
String formatDateTime(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}
