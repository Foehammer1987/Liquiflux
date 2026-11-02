/// Display formatting shared by every app.
String formatDuration(int? ms) {
  if (ms == null || ms <= 0) return '';
  final m = (ms / 60000).round();
  final h = m ~/ 60;
  return h > 0 ? '${h}h ${m % 60}m' : '${m}m';
}

String formatBytes(num n) {
  if (n <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  var v = n.toDouble();
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i >= 3 ? 2 : 0)} ${units[i]}';
}

/// "18m", "2h 5m", "1d 3h" from now until [t].
String? formatTimeUntil(DateTime? t, {DateTime? now}) {
  if (t == null) return null;
  final ms = t.difference(now ?? DateTime.now()).inMilliseconds;
  if (ms <= 60000) return 'under 1m';
  final m = (ms / 60000).round();
  final d = m ~/ 1440;
  final h = (m % 1440) ~/ 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m % 60}m';
  return '${m}m';
}

/// "7:42 PM" today, "Tue 7:42 PM" otherwise.
String formatClock(DateTime t, {DateTime? now}) {
  final local = t.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final h12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final clock = '$h12:${local.minute.toString().padLeft(2, '0')} ${local.hour < 12 ? 'AM' : 'PM'}';
  final sameDay = local.year == n.year && local.month == n.month && local.day == n.day;
  if (sameDay) return clock;
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[local.weekday - 1]} $clock';
}

String formatAgo(DateTime t, {DateTime? now}) {
  final s = (now ?? DateTime.now()).difference(t).inSeconds;
  if (s < 60) return 'Just now';
  if (s < 3600) return '${s ~/ 60}m ago';
  if (s < 86400) return '${s ~/ 3600}h ago';
  return '${s ~/ 86400}d ago';
}

String yearOf(String? iso) => iso != null && iso.length >= 4 ? iso.substring(0, 4) : '';

/// "September 22, 2011"
String formatDate(DateTime d) {
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

/// "Nov 18, 2026"
String formatShortDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

// Line breaks, other control characters, bidi overrides and zero-width marks: nothing a
// name needs, and a way to spoof or break the text around it.
final _unprintable = RegExp(r'[\p{Cc}\p{Zl}\p{Zp}\u200B\u200E\u200F\u202A-\u202E\u2066-\u2069\uFEFF]+', unicode: true);

/// Text from someone else (a room member's name, a room's title) made safe to show: one
/// line, no control characters, at most [max] characters; [fallback] when nothing is left.
String cleanLabel(String? s, {int max = 60, String fallback = ''}) {
  if (s == null) return fallback;
  // Long input is cut before the clean-up so a huge string costs no more than a short one.
  final head = s.length > max * 4 ? s.substring(0, max * 4) : s;
  final t = head.replaceAll(_unprintable, ' ').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  if (t.isEmpty) return fallback;
  final runes = t.runes;
  return runes.length <= max ? t : '${String.fromCharCodes(runes.take(max - 1)).trimRight()}…';
}
