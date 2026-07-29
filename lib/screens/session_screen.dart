import 'package:flutter/material.dart';

import '../logic/age.dart';
import '../repositories/exercise_repository.dart';
import '../repositories/records.dart';
import '../repositories/routine_repository.dart';
import '../repositories/session_repository.dart';
import '../theme.dart';
import '../widgets/add_exercise_sheet.dart';
import '../widgets/exercise_card.dart';

/// One day's workout. Reused for past sessions — date is always a parameter.
class SessionScreen extends StatelessWidget {
  const SessionScreen({
    super.key,
    required this.date,
    required this.routineId,
    required this.routineName,
    required this.exercises,
    required this.routines,
    required this.sessions,
  });

  final String date;
  final int routineId;
  final String routineName;
  final ExerciseRepository exercises;
  final RoutineRepository routines;
  final SessionRepository sessions;

  Future<void> _addExercise(BuildContext context) async {
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddExerciseSheet(exercises: exercises),
    );
    if (name == null) return;

    final id = await exercises.findOrCreate(name);
    // M1 has no one-off path: adding always appends to the routine.
    await routines.addExerciseToRoutine(
      routineId: routineId,
      exerciseId: id,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(routineName),
            Text(
              _headerDate(date),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<List<SessionCard>>(
          stream: sessions.watchSessionCards(
            date: date,
            routineId: routineId,
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: cards.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (i == cards.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextButton(
                      onPressed: () => _addExercise(context),
                      child: const Text('Add exercise'),
                    ),
                  );
                }
                final card = cards[i];
                return ExerciseCard(
                  key: ValueKey(card.exerciseId),
                  card: card,
                  today: date,
                  onConfirm: (weight, reps) => sessions.confirmSets(
                    date: date,
                    routineId: routineId,
                    sets: [
                      (
                        exerciseId: card.exerciseId,
                        weight: weight,
                        reps: reps,
                      ),
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

String _headerDate(String date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final d = parseDate(date);
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}
