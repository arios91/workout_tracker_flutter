/// Parses the legacy spreadsheet export into sessions ready for import.
///
/// Spec: `docs/m5-importer.md`. Pure — takes text, returns records.
library;

import 'dart:convert';

/// One set recovered from the log's notation.
typedef ParsedSet = ({int setNumber, double weight, int reps});

/// One exercise cell's worth of sets.
typedef ParsedExercise = ({String name, List<ParsedSet> sets});

/// One routine column within one week block.
typedef ParsedSession = ({
  int week,
  int column,
  String routine,
  List<ParsedExercise> exercises,
});

/// A cell that could not be stored, kept for the review step.
typedef SkippedCell = ({int week, String routine, String raw, String reason});

typedef ParseResult = ({
  List<ParsedSession> sessions,
  List<SkippedCell> skipped,
});

/// Column order is authoritative — it maps to routine, never to weekday.
const routineColumns = ['Shoulders', 'Legs', 'Back', 'Chest', 'Arms'];

/// Not an exercise: a pairing marker between the cells above and below it.
const _supersetMarker = 'superset';

/// Splits the export into sessions, reporting cells it cannot store.
ParseResult parseLegacyLog(String text) {
  // CRLF throughout; LineSplitter handles the line endings.
  final rows = const LineSplitter()
      .convert(text)
      .map((line) => line.split('\t').map((c) => c.trim()).toList())
      .toList();

  final sessions = <ParsedSession>[];
  final skipped = <SkippedCell>[];

  var week = 0;
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final header = _weekNumber(row.isEmpty ? '' : row.first);
    if (header != null) {
      week = header;
      continue;
    }
    if (!_isLabelRow(row)) continue;

    // Cells accumulate per column until the next label row or end of file.
    final columns = <int, List<ParsedExercise>>{};
    for (var j = i + 1; j < rows.length; j++) {
      if (_isLabelRow(rows[j]) || _weekNumber(rows[j].first) != null) break;
      for (var col = 0; col < routineColumns.length; col++) {
        final raw = col < rows[j].length ? rows[j][col] : '';
        if (raw.isEmpty) continue;
        if (raw.toLowerCase() == _supersetMarker) continue;

        final exercise = _parseCell(raw);
        if (exercise == null || exercise.sets.isEmpty) {
          skipped.add((
            week: week,
            routine: routineColumns[col],
            raw: raw,
            reason: _skipReason(raw),
          ));
          continue;
        }
        // Partly recovered: the cell is imported, but the review step must say
        // so rather than let a dropped run pass unnoticed.
        final expected = _runCount(raw);
        if (expected > exercise.sets.length) {
          skipped.add((
            week: week,
            routine: routineColumns[col],
            raw: raw,
            reason:
                'partly imported — kept ${exercise.sets.length} '
                'of $expected sets',
          ));
        }
        (columns[col] ??= []).add(exercise);
      }
    }

    for (final entry in columns.entries) {
      if (entry.value.isEmpty) continue;
      sessions.add((
        week: week,
        column: entry.key,
        routine: routineColumns[entry.key],
        exercises: entry.value,
      ));
    }
  }

  return (sessions: sessions, skipped: skipped);
}

/// Monday of Week 1. Week 1 has only Chest filled, and Chest is column 3, so
/// this puts the first session on Thursday 2026-01-01 — see the plan.
final legacyAnchor = DateTime(2025, 12, 29);

/// The synthesized date for a session — the source has none.
///
/// Column index doubles as the weekday offset: Shoulders=Mon … Arms=Fri.
DateTime legacySessionDate(ParsedSession session, {DateTime? anchor}) {
  final from = anchor ?? legacyAnchor;
  return DateTime(
    from.year,
    from.month,
    from.day + (session.week - 1) * 7 + session.column,
  );
}

int? _weekNumber(String cell) {
  final match = RegExp(r'^Week (\d+)$').firstMatch(cell);
  return match == null ? null : int.parse(match.group(1)!);
}

bool _isLabelRow(List<String> row) {
  if (row.length < routineColumns.length) return false;
  for (var i = 0; i < routineColumns.length; i++) {
    if (row[i] != routineColumns[i]) return false;
  }
  return true;
}

/// Runs are `N+@W-R` or `N+-R`; a bare `@W` prefix carries to runs without one.
// Anchored on a boundary so `1-12345-8` cannot match `1-12345` and read the
// set numbers as a rep count.
final _runPattern = RegExp(r'(?:^|\s)(\d+)(?:@(\d+(?:\.\d+)?))?-(\d+)(?=\s|$)');
final _prefixWeight = RegExp(r'@\s*(\d+(?:\.\d+)?)');

ParsedExercise? _parseCell(String raw) {
  // `@ 45` spacing and the kg suffix are noise; the scale is per-exercise
  // anyway and only ever compared to itself (invariant 12).
  final cell = raw
      .replaceAll(RegExp(r'@\s+'), '@')
      .replaceAll(RegExp(r'kg', caseSensitive: false), '');

  final name = _exerciseName(cell);
  if (name.isEmpty) return null;

  final carried = _prefixWeight.firstMatch(cell);
  // A weight ahead of the first run is the default; runs may override it.
  final defaultWeight = carried == null
      ? null
      : double.tryParse(carried.group(1)!);

  final sets = <ParsedSet>[];
  for (final match in _runPattern.allMatches(cell)) {
    final digits = match.group(1)!;
    final weight = match.group(2) == null
        ? defaultWeight
        : double.tryParse(match.group(2)!);
    final reps = int.tryParse(match.group(3)!);
    if (weight == null || reps == null || reps <= 0) continue;

    // Each digit is one set number: `12345-8` is five sets, not twelve thousand.
    if (!_isConsecutive(digits)) continue;
    for (final digit in digits.split('')) {
      sets.add((setNumber: int.parse(digit), weight: weight, reps: reps));
    }
  }

  if (sets.isEmpty) return null;
  sets.sort((a, b) => a.setNumber.compareTo(b.setNumber));

  // A dropped run leaves a gap in the original numbering; renumber from 1 so
  // set_number stays contiguous (invariant 9) and collapse renders sensibly.
  return (
    name: name,
    sets: [
      for (var i = 0; i < sets.length; i++)
        (setNumber: i + 1, weight: sets[i].weight, reps: sets[i].reps),
    ],
  );
}

/// Set numbers in a run ascend by one; anything else is a typo, not notation.
bool _isConsecutive(String digits) {
  for (var i = 1; i < digits.length; i++) {
    if (digits.codeUnitAt(i) != digits.codeUnitAt(i - 1) + 1) return false;
  }
  return true;
}

/// Everything before the weight or the first run — `Straight bar pulldown@100`
/// has no separating space, and two cells drop the `@` entirely.
String _exerciseName(String cell) {
  final at = cell.indexOf('@');
  final run = RegExp(r'\s\d').firstMatch(cell);
  var end = cell.length;
  if (at >= 0) end = at;
  if (run != null && run.start < end) end = run.start;
  return cell.substring(0, end).trim();
}

/// Set numbers the cell appears to claim, however malformed the run.
int _runCount(String raw) {
  var total = 0;
  for (final match in RegExp(r'(\d+)(?:@[\d.]+)?-').allMatches(raw)) {
    total += match.group(1)!.length;
  }
  return total;
}

String _skipReason(String raw) {
  if (!raw.contains('@') && !RegExp(r'\d+-\d+').hasMatch(raw)) {
    return 'no sets recorded';
  }
  if (!raw.contains('@')) return 'no weight recorded';
  if (!RegExp(r'-\d').hasMatch(raw)) return 'weight but no reps';
  // `Bench @12345-10` — the weight was dropped and the set run sits where it
  // should be, so there is no way to tell what was lifted.
  if (RegExp(r'@\d+-\d').hasMatch(raw)) return 'weight missing before sets';
  return 'set numbers not consecutive';
}
