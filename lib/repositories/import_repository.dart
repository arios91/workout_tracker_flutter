import 'package:drift/drift.dart';

import '../db/database.dart';
import '../logic/legacy_parser.dart';

/// Backfills the legacy log. One-time — see `docs/m5-importer.md`.
class ImportRepository {
  ImportRepository(this._db);

  final AppDatabase _db;

  /// True once any session exists, so the importer can refuse to run twice.
  Future<bool> hasAnySessions() async {
    final count = _db.sessions.id.count();
    final row = await (_db.selectOnly(
      _db.sessions,
    )..addColumns([count])).getSingle();
    return (row.read(count) ?? 0) > 0;
  }

  /// Writes every parsed session in one transaction — invariant 13.
  ///
  /// [dateFor] supplies each session's date; the importer never reads the
  /// clock (invariant 6). [nameMerges] folds confirmed near-duplicates.
  Future<void> importSessions(
    List<ParsedSession> sessions, {
    required String Function(ParsedSession) dateFor,
    Map<String, String> nameMerges = const {},
  }) async {
    await _db.transaction(() async {
      // createdAt is when the row was written, not when the workout happened.
      final now = DateTime.now();
      final routineIds = <String, int>{};
      final exerciseIds = <String, int>{};

      for (final session in sessions) {
        final routineId = await _routineId(
          routineIds,
          session.routine,
          // Column index is the weekday offset from Monday.
          weekday: session.column + 1,
        );

        final sessionId = await _db
            .into(_db.sessions)
            .insert(
              SessionsCompanion.insert(
                date: dateFor(session),
                routineId: routineId,
                createdAt: now,
              ),
            );

        var position = 0;
        for (final exercise in session.exercises) {
          final name = nameMerges[exercise.name] ?? exercise.name;
          final exerciseId = await _exerciseId(exerciseIds, name);

          final sessionExerciseId = await _db
              .into(_db.sessionExercises)
              .insert(
                SessionExercisesCompanion.insert(
                  sessionId: sessionId,
                  exerciseId: exerciseId,
                  position: ++position,
                ),
              );

          await _db.batch((batch) {
            batch.insertAll(_db.setEntries, [
              for (final set in exercise.sets)
                SetEntriesCompanion.insert(
                  sessionExerciseId: sessionExerciseId,
                  setNumber: set.setNumber,
                  weight: set.weight,
                  reps: set.reps,
                  createdAt: now,
                ),
            ]);
          });
        }
      }
    });

    // Templates come from each routine's latest session, not the union of all
    // of them — appending per exercise would leave 32 weeks of accumulation.
    await rebuildRoutineTemplates();
  }

  Future<int> _routineId(
    Map<String, int> cache,
    String name, {
    required int weekday,
  }) async {
    final cached = cache[name];
    if (cached != null) return cached;

    final existing =
        await (_db.select(_db.routines)
              ..where((r) => r.name.lower().equals(name.toLowerCase()))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return cache[name] = existing.id;

    final position = cache.length + 1;
    return cache[name] = await _db
        .into(_db.routines)
        .insert(
          RoutinesCompanion.insert(
            name: name,
            defaultWeekday: Value(weekday),
            position: position,
          ),
        );
  }

  Future<int> _exerciseId(Map<String, int> cache, String name) async {
    final key = name.toLowerCase();
    final cached = cache[key];
    if (cached != null) return cached;

    // NOCASE on the column does the case-insensitive matching.
    final existing =
        await (_db.select(_db.exercises)
              ..where((e) => e.name.equals(name))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return cache[key] = existing.id;

    return cache[key] = await _db
        .into(_db.exercises)
        .insert(ExercisesCompanion.insert(name: name));
  }

  /// Resets every routine's template to the exercises of its latest session.
  ///
  /// Repairs templates that accumulated the union of every imported session.
  // Touches routine_exercises only — session history is never rewritten
  // (invariant 11).
  Future<void> rebuildRoutineTemplates() async {
    await _db.transaction(() async {
      final routines = await _db.select(_db.routines).get();

      for (final routine in routines) {
        final latest = await _db
            .customSelect(
              '''
          SELECT se.exercise_id
            FROM sessions s
            JOIN session_exercises se ON se.session_id = s.id
           WHERE s.routine_id = ?
             AND s.id = (
               SELECT s2.id
                 FROM sessions s2
                 JOIN session_exercises se2 ON se2.session_id = s2.id
                 JOIN set_entries t2 ON t2.session_exercise_id = se2.id
                WHERE s2.routine_id = ?
                GROUP BY s2.id
                ORDER BY s2.date DESC, s2.id DESC
                LIMIT 1
             )
           ORDER BY se.position
          ''',
              variables: [Variable<int>(routine.id), Variable<int>(routine.id)],
              readsFrom: {_db.sessions, _db.sessionExercises, _db.setEntries},
            )
            .get();

        // No sessions yet: leave whatever the user built by hand.
        if (latest.isEmpty) continue;

        await (_db.delete(
          _db.routineExercises,
        )..where((re) => re.routineId.equals(routine.id))).go();

        var position = 0;
        for (final row in latest) {
          await _db
              .into(_db.routineExercises)
              .insert(
                RoutineExercisesCompanion.insert(
                  routineId: routine.id,
                  exerciseId: row.read<int>('exercise_id'),
                  position: ++position,
                ),
              );
        }
      }
    });
  }
}
