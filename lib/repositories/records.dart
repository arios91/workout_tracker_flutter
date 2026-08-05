/// Plain data crossing the repository boundary — no Drift types.
library;

import '../logic/set_record.dart';

export '../logic/set_record.dart' show SetRecord;

/// A set about to be written; the repository assigns its set number.
typedef PendingSet = ({int exerciseId, double weight, int reps});

/// One prior performance of an exercise, from any session.
// sessionId is carried so the history screen can open the session it names.
typedef ExerciseSession = ({
  int sessionId,
  String date,
  List<SetRecord> sets,
});

/// One exercise's contribution to a session summary.
typedef SummaryExercise = ({String exerciseName, List<SetRecord> sets});

/// A whole session at a glance, for the home card.
// Sets are carried rather than pre-collapsed: collapse is a display function
// and stays out of the repository.
typedef SessionSummary = ({
  int sessionId,
  int routineId,
  String routineName,
  List<SummaryExercise> exercises,
  int setCount,
});

/// One exercise on the session screen.
class SessionCard {
  const SessionCard({
    required this.exerciseId,
    required this.exerciseName,
    required this.todaysSets,
    required this.history,
    required this.hasMoreHistory,
    required this.inRoutine,
  });

  final int exerciseId;
  final String exerciseName;

  // Empty means not started today, in which case the card renders [history]
  // instead. There is no separate completion state.
  final List<SetRecord> todaysSets;

  /// Prior sessions, newest first. Empty if never performed.
  final List<ExerciseSession> history;

  /// Whether older sessions exist beyond [history] — drives *show more*.
  final bool hasMoreHistory;

  /// False for an ad-hoc addition not in the routine template.
  final bool inRoutine;
}
