/// How long ago a previous performance was, in words — invariant 5.
String formatAge(String thenDate, String todayDate) {
  final then = parseDate(thenDate);
  final today = parseDate(todayDate);
  final days = today.difference(then).inDays;

  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 14) return '$days days ago';

  final weeks = days ~/ 7;
  if (weeks < 9) return '$weeks weeks ago';

  final months = (days / 30.44).round();
  if (months < 24) return '$months months ago';

  return '${(days / 365.25).round()} years ago';
}

/// Parses a `YYYY-MM-DD` string into a local [DateTime] at midnight.
// Not DateTime.parse: it can attach timezone semantics, and offsetting a
// calendar day by hours changes which day it is.
DateTime parseDate(String date) {
  final parts = date.split('-');
  if (parts.length != 3) {
    throw FormatException('Expected YYYY-MM-DD', date);
  }
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

/// Formats a stored date for a screen header — `Tue 5 Aug`.
String formatHeaderDate(String date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final d = parseDate(date);
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}

/// Formats a [DateTime] as the `YYYY-MM-DD` string the database stores.
String formatDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
