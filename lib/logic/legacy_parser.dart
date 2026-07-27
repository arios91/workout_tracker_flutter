/// One set parsed out of a log cell.
typedef ParsedSet = ({double weight, int reps});

/// One cell: an exercise name and whatever sets were recorded for it.
typedef ParsedCell = ({String exerciseName, List<ParsedSet> sets});

/// A cell placed in the grid. [weekday] is ISO, 1 = Monday.
typedef ParsedEntry = ({int week, int weekday, ParsedCell cell});

typedef ParseResult = ({List<ParsedEntry> entries, List<String> skipped});

final _weekMarker = RegExp(r'^Week\s+(\d+)$', caseSensitive: false);
// Inline notation puts set numbers before the weight (`1@120-18`), so the name
// ends at whichever comes first: the `@`, or the digits leading into it.
final _leadingSetNumbers = RegExp(r'\d+\s*@');
final _weightPart = RegExp(r'@\s*([0-9.]+)\s*(?:kg)?', caseSensitive: false);
final _inlineRun = RegExp(r'(\d+)\s*@\s*([0-9.]+)\s*(?:kg)?\s*-\s*(\d+)');
final _hoistedRun = RegExp(r'(?<![@\d])(\d+)\s*-\s*(\d+)');

/// Parses the legacy weekday-grid TSV.
///
/// Returns entries in file order, plus the cells that could not become sets.
ParseResult parseLegacyLog(String tsv) {
  final entries = <ParsedEntry>[];
  final skipped = <String>[];
  var week = 0;

  for (final line in tsv.split('\n')) {
    final columns = line.replaceAll('\r', '').split('\t');
    if (columns.isEmpty) continue;

    final marker = _weekMarker.firstMatch(columns.first.trim());
    if (marker != null) {
      week = int.parse(marker.group(1)!);
      continue;
    }
    if (week == 0) continue; // header row, before the first Week marker

    for (var col = 0; col < columns.length && col < 6; col++) {
      final raw = columns[col].trim();
      if (raw.isEmpty) continue;
      if (raw.toLowerCase() == 'superset') {
        skipped.add(raw);
        continue;
      }

      final cell = parseCell(raw);
      if (cell == null) {
        skipped.add(raw);
        continue;
      }
      entries.add((week: week, weekday: col + 1, cell: cell));
    }
  }

  return (entries: entries, skipped: skipped);
}

/// Index where the notation begins, or -1 if the cell is a bare name.
int _bodyStart(String raw) {
  final at = raw.indexOf('@');
  if (at == -1) return -1;
  final inline = _leadingSetNumbers.firstMatch(raw);
  if (inline != null && inline.start < at) return inline.start;
  return at;
}

/// Parses one cell. Returns null if it holds no exercise name.
///
/// A cell with no reps yields an empty set list rather than null: the exercise
/// was performed, but a set without reps is unrepresentable (invariant 2), so
/// any weight present is discarded rather than paired with an invented count.
ParsedCell? parseCell(String raw) {
  final bodyStart = _bodyStart(raw);
  final name = (bodyStart == -1 ? raw : raw.substring(0, bodyStart)).trim();
  if (name.isEmpty) return null;

  if (bodyStart == -1) return (exerciseName: name, sets: const []);

  final body = raw.substring(bodyStart);
  final sets = <ParsedSet>[];

  // Inline runs carry their own weight and win over the hoisted form.
  final inline = _inlineRun.allMatches(body).toList();
  if (inline.isNotEmpty) {
    for (final match in inline) {
      final weight = double.parse(match.group(2)!);
      final reps = int.parse(match.group(3)!);
      // Each digit is one set number, so the run length is its digit count.
      for (var i = 0; i < match.group(1)!.length; i++) {
        sets.add((weight: weight, reps: reps));
      }
    }
    return (exerciseName: name, sets: sets);
  }

  final weightMatch = _weightPart.firstMatch(body);
  if (weightMatch == null) return (exerciseName: name, sets: const []);
  final weight = double.parse(weightMatch.group(1)!);

  final tail = body.substring(weightMatch.end);
  for (final match in _hoistedRun.allMatches(tail)) {
    final reps = int.parse(match.group(2)!);
    for (var i = 0; i < match.group(1)!.length; i++) {
      sets.add((weight: weight, reps: reps));
    }
  }

  return (exerciseName: name, sets: sets);
}
