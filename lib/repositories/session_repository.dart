import 'package:drift/drift.dart';

import '../db/database.dart';
import 'records.dart';

/// Reads and writes for one day's workout.
class SessionRepository {
  SessionRepository(this._db);

  final AppDatabase _db;

  /// Writes confirmed sets in one transaction — invariants 6 and 13.
  Future<void> confirmSets({
    required String date,
    required int routineId,
    required List<PendingSet> sets,
  }) async {
    if (sets.isEmpty) return;

    await _db.transaction(() async {
      // Reaches createdAt only; the workout day is always the `date` argument.
      final now = DateTime.now();
      final sessionId = await _findOrCreateSession(date, routineId, now);

      for (final pending in sets) {
        final sessionExerciseId = await _findOrCreateSessionExercise(
          sessionId,
          pending.exerciseId,
        );
        final setNumber = await _nextSetNumber(sessionExerciseId);

        await _db
            .into(_db.setEntries)
            .insert(
              SetEntriesCompanion.insert(
                sessionExerciseId: sessionExerciseId,
                setNumber: setNumber,
                weight: pending.weight,
                reps: pending.reps,
                createdAt: now,
              ),
            );
      }
    });
  }

  Future<int> _findOrCreateSession(
    String date,
    int routineId,
    DateTime now,
  ) async {
    final existing =
        await (_db.select(_db.sessions)..where(
              (s) => s.date.equals(date) & s.routineId.equals(routineId),
            ))
            .getSingleOrNull();
    if (existing != null) return existing.id;

    return _db
        .into(_db.sessions)
        .insert(
          SessionsCompanion.insert(
            date: date,
            routineId: routineId,
            createdAt: now,
          ),
        );
  }

  Future<int> _findOrCreateSessionExercise(
    int sessionId,
    int exerciseId,
  ) async {
    final existing =
        await (_db.select(_db.sessionExercises)..where(
              (se) =>
                  se.sessionId.equals(sessionId) &
                  se.exerciseId.equals(exerciseId),
            ))
            .getSingleOrNull();
    if (existing != null) return existing.id;

    final max = _db.sessionExercises.position.max();
    final row =
        await (_db.selectOnly(_db.sessionExercises)
              ..addColumns([max])
              ..where(_db.sessionExercises.sessionId.equals(sessionId)))
            .getSingle();

    return _db
        .into(_db.sessionExercises)
        .insert(
          SessionExercisesCompanion.insert(
            sessionId: sessionId,
            exerciseId: exerciseId,
            position: (row.read(max) ?? 0) + 1,
          ),
        );
  }

  Future<int> _nextSetNumber(int sessionExerciseId) async {
    final max = _db.setEntries.setNumber.max();
    final row =
        await (_db.selectOnly(_db.setEntries)
              ..addColumns([max])
              ..where(
                _db.setEntries.sessionExerciseId.equals(sessionExerciseId),
              ))
            .getSingle();
    return (row.read(max) ?? 0) + 1;
  }

  /// Deletes one set and renumbers those above it — invariants 9 and 10.
  Future<void> deleteSet(int setEntryId) async {
    await _db.transaction(() async {
      final row =
          await (_db.select(_db.setEntries)
                ..where((s) => s.id.equals(setEntryId)))
              .getSingleOrNull();
      if (row == null) return;

      await (_db.delete(_db.setEntries)
            ..where((s) => s.id.equals(setEntryId)))
          .go();

      // Shifting down means each target number is already vacated, so
      // UNIQUE (session_exercise_id, set_number) never trips mid-statement.
      await _db.customUpdate(
        'UPDATE set_entries SET set_number = set_number - 1 '
        'WHERE session_exercise_id = ? AND set_number > ?',
        variables: [
          Variable<int>(row.sessionExerciseId),
          Variable<int>(row.setNumber),
        ],
        updates: {_db.setEntries},
      );

      final remaining =
          await (_db.select(_db.setEntries)..where(
                (s) => s.sessionExerciseId.equals(row.sessionExerciseId),
              ))
              .get();
      if (remaining.isEmpty) {
        await (_db.delete(_db.sessionExercises)
              ..where((se) => se.id.equals(row.sessionExerciseId)))
            .go();
      }
    });
  }

  /// Template exercises merged with today's sets — invariant 4.
  Stream<List<SessionCard>> watchSessionCards({
    required String date,
    required int routineId,
  }) {
    // Sentinel query: any write to these tables re-runs the whole assembly.
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.routineExercises,
            _db.sessionExercises,
            _db.setEntries,
            _db.sessions,
            _db.exercises,
          },
        )
        .watch()
        .asyncMap((_) => _buildCards(date: date, routineId: routineId));
  }

  Future<List<SessionCard>> _buildCards({
    required String date,
    required int routineId,
  }) async {
    final session =
        await (_db.select(_db.sessions)..where(
              (s) => s.date.equals(date) & s.routineId.equals(routineId),
            ))
            .getSingleOrNull();

    final templateIds = await _templateExerciseIds(routineId);
    final todays = session == null
        ? <int, List<SetRecord>>{}
        : await _todaysSets(session.id);

    // Template order first, then anything logged today that isn't in it.
    final ordered = <int>[
      ...templateIds,
      ...todays.keys.where((id) => !templateIds.contains(id)),
    ];
    if (ordered.isEmpty) return [];

    final names = await _exerciseNames(ordered);
    final lastTimes = await _lastTimes(ordered, excludingSession: session?.id);

    return [
      for (final id in ordered)
        SessionCard(
          exerciseId: id,
          exerciseName: names[id] ?? '',
          todaysSets: todays[id] ?? const [],
          lastTime: lastTimes[id],
          inRoutine: templateIds.contains(id),
        ),
    ];
  }

  Future<List<int>> _templateExerciseIds(int routineId) async {
    final query = _db.select(_db.routineExercises)
      ..where((re) => re.routineId.equals(routineId))
      ..orderBy([(re) => OrderingTerm(expression: re.position)]);
    final rows = await query.get();
    return rows.map((r) => r.exerciseId).toList();
  }

  Future<Map<int, List<SetRecord>>> _todaysSets(int sessionId) async {
    final query = _db.select(_db.sessionExercises).join([
      innerJoin(
        _db.setEntries,
        _db.setEntries.sessionExerciseId.equalsExp(_db.sessionExercises.id),
      ),
    ])
      ..where(_db.sessionExercises.sessionId.equals(sessionId))
      ..orderBy([
        OrderingTerm(expression: _db.sessionExercises.position),
        OrderingTerm(expression: _db.setEntries.setNumber),
      ]);

    final result = <int, List<SetRecord>>{};
    for (final row in await query.get()) {
      final exerciseId = row.readTable(_db.sessionExercises).exerciseId;
      final entry = row.readTable(_db.setEntries);
      (result[exerciseId] ??= []).add((
        setNumber: entry.setNumber,
        weight: entry.weight,
        reps: entry.reps,
      ));
    }
    return result;
  }

  Future<Map<int, String>> _exerciseNames(List<int> exerciseIds) async {
    final rows =
        await (_db.select(_db.exercises)
              ..where((e) => e.id.isIn(exerciseIds)))
            .get();
    return {for (final row in rows) row.id: row.name};
  }

  /// Most recent prior performance of each exercise — invariant 5.
  Future<Map<int, LastTime>> _lastTimes(
    List<int> exerciseIds, {
    int? excludingSession,
  }) async {
    if (exerciseIds.isEmpty) return {};

    final placeholders = List.filled(exerciseIds.length, '?').join(', ');
    final variables = <Variable>[
      for (final id in exerciseIds) Variable<int>(id),
    ];

    var exclusion = '';
    if (excludingSession != null) {
      exclusion = 'AND se.session_id != ?';
      variables.add(Variable<int>(excludingSession));
    }

    // One windowed pass rather than a query per card.
    final rows = await _db.customSelect(
      '''
      WITH ranked AS (
        SELECT se.exercise_id, se.id AS session_exercise_id, s.date,
               ROW_NUMBER() OVER (
                 PARTITION BY se.exercise_id
                 ORDER BY s.date DESC, s.id DESC
               ) AS rn
          FROM session_exercises se
          JOIN sessions s ON s.id = se.session_id
         WHERE se.exercise_id IN ($placeholders)
           $exclusion
      )
      SELECT r.exercise_id, r.date, e.set_number, e.weight, e.reps
        FROM ranked r
        JOIN set_entries e ON e.session_exercise_id = r.session_exercise_id
       WHERE r.rn = 1
       ORDER BY r.exercise_id, e.set_number
      ''',
      variables: variables,
      readsFrom: {
        _db.sessionExercises,
        _db.sessions,
        _db.setEntries,
      },
    ).get();

    final dates = <int, String>{};
    final sets = <int, List<SetRecord>>{};
    for (final row in rows) {
      final exerciseId = row.read<int>('exercise_id');
      dates[exerciseId] = row.read<String>('date');
      (sets[exerciseId] ??= []).add((
        setNumber: row.read<int>('set_number'),
        weight: row.read<double>('weight'),
        reps: row.read<int>('reps'),
      ));
    }

    return {
      for (final entry in dates.entries)
        entry.key: (date: entry.value, sets: sets[entry.key] ?? const []),
    };
  }
}
