import 'package:flutter/material.dart';

import '../logic/active_session.dart';
import '../logic/age.dart';
import '../repositories/exercise_repository.dart';
import '../repositories/records.dart';
import '../repositories/routine_repository.dart';
import '../repositories/session_repository.dart';
import '../theme.dart';
import '../widgets/add_exercise_sheet.dart';
import '../widgets/exercise_card.dart';
import '../widgets/remove_exercise_dialog.dart';

/// One day's workout. Reused for past sessions — date is always a parameter.
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.date,
    required this.routineId,
    required this.routineName,
    required this.exercises,
    required this.routines,
    required this.sessions,
    required this.isToday,
  });

  final String date;

  /// Only today pre-fills from the routine template — invariant 4.
  final bool isToday;
  final int routineId;
  final String routineName;
  final ExerciseRepository exercises;
  final RoutineRepository routines;
  final SessionRepository sessions;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  // Per-exercise *show more* taps. Ephemeral view state, so it lives here
  // rather than in the database — the stream re-subscribes on change.
  final _extraHistory = <int, int>{};

  Future<void> _addExercise() async {
    final choice = await showModalBottomSheet<AddChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddExerciseSheet(
        exercises: widget.exercises,
        routineName: widget.routineName,
        isToday: widget.isToday,
      ),
    );
    if (choice == null) return;

    final id = await widget.exercises.findOrCreate(choice.name);
    if (choice.toRoutine) {
      await widget.routines.addExerciseToRoutine(
        routineId: widget.routineId,
        exerciseId: id,
      );
    }
    if (choice.toSession) {
      // Today's card would appear via the template merge anyway, but a
      // session-only add needs the row written explicitly.
      await widget.sessions.addExerciseToSession(
        date: widget.date,
        routineId: widget.routineId,
        exerciseId: id,
      );
    }
  }

  Future<void> _removeExercise(SessionCard card) async {
    final choice = await showRemoveExerciseDialog(
      context,
      exerciseName: card.exerciseName,
      routineName: widget.routineName,
      setCount: card.todaysSets.length,
    );
    if (choice == null) return;

    if (choice.fromSession) {
      await widget.sessions.removeExerciseFromSession(
        date: widget.date,
        routineId: widget.routineId,
        exerciseId: card.exerciseId,
      );
    }
    if (choice.fromRoutine) {
      await widget.routines.removeExerciseFromRoutine(
        routineId: widget.routineId,
        exerciseId: card.exerciseId,
      );
    }
  }

  // Navigation only: every set was written on confirm, and nothing marks a
  // session complete (invariant 14).
  Future<void> _finish() async {
    await ActiveSession.clear();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(widget.routineName),
            Text(
              formatHeaderDate(widget.date),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _finish,
              child: const Text('Finish workout'),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<SessionCard>>(
          stream: widget.sessions.watchSessionCards(
            date: widget.date,
            routineId: widget.routineId,
            isToday: widget.isToday,
            extraHistory: _extraHistory,
          ),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${snapshot.error}',
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final cards = snapshot.data!;
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: cards.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (i == cards.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextButton(
                      onPressed: _addExercise,
                      child: const Text('Add exercise'),
                    ),
                  );
                }
                final card = cards[i];
                return ExerciseCard(
                  key: ValueKey(card.exerciseId),
                  card: card,
                  today: widget.date,
                  onShowMore: () => setState(() {
                    _extraHistory.update(
                      card.exerciseId,
                      (taps) => taps + 1,
                      ifAbsent: () => 1,
                    );
                  }),
                  onUpdateSet: (setId, weight, reps) => widget.sessions
                      .updateSet(setEntryId: setId, weight: weight, reps: reps),
                  onDeleteSet: widget.sessions.deleteSet,
                  onRemove: () => _removeExercise(card),
                  onConfirm: (weight, reps) => widget.sessions.confirmSets(
                    date: widget.date,
                    routineId: widget.routineId,
                    sets: [
                      (exerciseId: card.exerciseId, weight: weight, reps: reps),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
