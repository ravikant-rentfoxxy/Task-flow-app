import 'package:intl/intl.dart';

/// Backend timestamps are epoch-ms, usually as numeric strings (PostgreSQL BIGINT).
int? parseTimestamp(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.isFinite ? value.toInt() : null;
  if (value is DateTime) return value.millisecondsSinceEpoch;
  if (value is String) {
    final s = value.trim();
    if (s.isEmpty) return null;
    final n = int.tryParse(s);
    if (n != null) return n;
    return DateTime.tryParse(s)?.millisecondsSinceEpoch;
  }
  return null;
}

DateTime? toDate(dynamic value) {
  final ts = parseTimestamp(value);
  return ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts);
}

int? asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

bool asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == 't' || v == '1';
  return false;
}

String? asStr(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s;
}

String fmtDateTime(DateTime? d) => d == null ? '—' : DateFormat('d MMM, h:mm a').format(d);

String fmtDate(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy').format(d);

String fmtShortDate(DateTime? d) => d == null ? '—' : DateFormat('d MMM').format(d);

String fmtTime(DateTime? d) => d == null ? '—' : DateFormat('h:mm a').format(d);

String fmtDayLabel(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('EEE, d MMM').format(d);
}

String timeAgo(DateTime? d, {DateTime? now}) {
  if (d == null) return '';
  final diff = (now ?? DateTime.now()).difference(d);
  final m = diff.inMinutes;
  if (m < 1) return 'just now';
  if (m < 60) return '${m}m ago';
  final h = m ~/ 60;
  if (h < 24) return '${h}h ago';
  return '${h ~/ 24}d ago';
}

/// Remaining time until [deadline], e.g. `25m left`, `3h 5m left`, `breached`.
String countdown(DateTime? deadline, {DateTime? now}) {
  if (deadline == null) return '';
  final diff = deadline.difference(now ?? DateTime.now());
  if (diff.inMilliseconds <= 0) return 'breached';
  final m = diff.inMinutes;
  if (m < 60) return '${m}m left';
  final h = m ~/ 60;
  if (h < 48) return '${h}h ${m % 60}m left';
  return '${h ~/ 24}d left';
}

String initials(String? name) {
  final parts = (name ?? '?').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final letters = parts.take(2).map((w) => w[0]).join();
  return letters.isEmpty ? '?' : letters.toUpperCase();
}

/// "Suresh Kumar (Sales Head)" -> "Suresh Kumar".
String displayName(String? name) {
  if (name == null || name.isEmpty) return 'User';
  return name.split(' (').first;
}

String firstName(String? name) => displayName(name).split(' ').first;

String htmlToPlainText(String? html) {
  if (html == null || html.trim().isEmpty) return '';
  return html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n\s*\n+'), '\n')
      .trim();
}

String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

String formatBytes(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Start/end of the local day as epoch-ms bounds.
({int from, int to}) todayBounds([DateTime? now]) {
  final n = now ?? DateTime.now();
  final start = DateTime(n.year, n.month, n.day);
  final end = DateTime(n.year, n.month, n.day, 23, 59, 59, 999);
  return (from: start.millisecondsSinceEpoch, to: end.millisecondsSinceEpoch);
}

({int from, int to})? rangeBounds(DateTime? from, DateTime? to) {
  if (from == null || to == null) return null;
  final start = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
  if (start.isAfter(end)) return null;
  return (from: start.millisecondsSinceEpoch, to: end.millisecondsSinceEpoch);
}
