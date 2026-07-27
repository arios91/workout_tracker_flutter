/// Plain data crossing the repository boundary — no Drift types.
library;

import '../logic/set_record.dart';

export '../logic/set_record.dart' show SetRecord;

/// A set about to be written; the repository assigns its set number.
typedef PendingSet = ({int exerciseId, double weight, int reps});

/// The most recent previous performance of an exercise, from any session.
typedef LastTime = ({String date, List<SetRecord> sets});

/// One exercise on the session screen.
class SessionCard {
  const SessionCard({
    required this.exerciseId,
    required this.exerciseName,
    required this.todaysSets,
    required this.lastTime,
    required this.inRoutine,
  });

  final int exerciseId;
  final String exerciseName;

  // Empty means not started today, in which case the card renders lastTime
  // instead. There is no separate completion state.
  final List<SetRecord> todaysSets;

  /// Null if never performed.
  final LastTime? lastTime;

  /// False for an ad-hoc addition not in the routine template.
  final bool inRoutine;
}
