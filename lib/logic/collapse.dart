import 'set_record.dart';

/// Renders ordered sets into the log's display notation.
///
/// Spec: CLAUDE.md "The collapse function".
String collapse(List<SetRecord> sets) {
  if (sets.isEmpty) return '';

  final runs = _runs(sets);
  final uniformWeight = sets.every((s) => s.weight == sets.first.weight);

  if (uniformWeight) {
    final weight = _formatWeight(sets.first.weight);
    final body = runs.map((r) => '${r.numbers}-${r.reps}').join(' ');
    return '@$weight $body';
  }

  return runs
      .map((r) => '${r.numbers}@${_formatWeight(r.weight)}-${r.reps}')
      .join(' ');
}

List<_Run> _runs(List<SetRecord> sets) {
  final runs = <_Run>[];

  for (final set in sets) {
    final current = runs.isEmpty ? null : runs.last;
    if (current != null &&
        current.weight == set.weight &&
        current.reps == set.reps) {
      current.numbers += _setNumber(set.setNumber);
    } else {
      runs.add(
        _Run(
          numbers: _setNumber(set.setNumber),
          weight: set.weight,
          reps: set.reps,
        ),
      );
    }
  }

  return runs;
}

// Set numbers concatenate bare (`123` is sets 1-3), which is ambiguous past 9.
String _setNumber(int n) => n < 10 ? '$n' : '($n)';

// Weights are decimal but usually whole; `45` reads better than `45.0`.
String _formatWeight(double weight) {
  if (weight == weight.roundToDouble()) return weight.toInt().toString();
  return weight.toString();
}

class _Run {
  _Run({required this.numbers, required this.weight, required this.reps});

  String numbers;
  final double weight;
  final int reps;
}
