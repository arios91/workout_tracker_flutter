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

  /// Changes one set's numbers in place.
  // set_number is not editable, so ordering is untouched and nothing renumbers.
  Future<void> updateSet({
    required int setEntryId,
    required double weight,
    required int reps,
  }) async {
    await (_db.update(_db.setEntries)..where((s) => s.id.equals(setEntryId)))
        .write(SetEntriesCompanion(weight: Value(weight), reps: Value(reps)));
  }

  /// Deletes one set and renumbers those above it — invariants 9 and 10.
  Future<void> deleteSet(int setEntryId) async {
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.setEntries,
      )..where((s) => s.id.equals(setEntryId))).getSingleOrNull();
      if (row == null) return;

      await (_db.delete(
        _db.setEntries,
      )..where((s) => s.id.equals(setEntryId))).go();

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

      final remaining = await (_db.select(
        _db.setEntries,
      )..where((s) => s.sessionExerciseId.equals(row.sessionExerciseId))).get();
      if (remaining.isEmpty) {
        await (_db.delete(
          _db.sessionExercises,
        )..where((se) => se.id.equals(row.sessionExerciseId))).go();
      }
    });
  }

  /// A day's logged work, or null if nothing is logged — invariant 14.
  ///
  /// Keyed on date alone: the card shows whatever was logged, whichever
  /// routine was picked.
  Stream<SessionSummary?> watchSummary({required String date}) {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.sessions,
            _db.sessionExercises,
            _db.setEntries,
            _db.exercises,
            _db.routines,
          },
        )
        .watch()
        .asyncMap((_) => _buildSummary(date));
  }

  Future<SessionSummary?> _buildSummary(String date) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT s.id AS session_id, s.routine_id, r.name AS routine_name,
             se.position, e.name AS exercise_name,
             t.id AS set_id, t.set_number, t.weight, t.reps
        FROM sessions s
        JOIN routines r ON r.id = s.routine_id
        JOIN session_exercises se ON se.session_id = s.id
        JOIN exercises e ON e.id = se.exercise_id
        JOIN set_entries t ON t.session_exercise_id = se.id
       -- UNIQUE is (date, routine_id), so one date can hold several sessions.
       -- The card shows the latest started; the rest are reachable from the
       -- session list (M3).
       WHERE s.id = (
         SELECT s2.id
           FROM sessions s2
           JOIN session_exercises se2 ON se2.session_id = s2.id
           JOIN set_entries t2 ON t2.session_exercise_id = se2.id
          WHERE s2.date = ?
          ORDER BY s2.created_at DESC, s2.id DESC
          LIMIT 1
       )
       ORDER BY se.position, t.set_number
      ''',
          variables: [Variable<String>(date)],
          readsFrom: {
            _db.sessions,
            _db.sessionExercises,
            _db.setEntries,
            _db.exercises,
            _db.routines,
          },
        )
        .get();

    // The inner join drops set-less rows, so no rows means nothing logged —
    // which is exactly the "not started" state (invariant 14).
    if (rows.isEmpty) return null;

    final exercises = <SummaryExercise>[];
    int? currentPosition;
    var setCount = 0;

    for (final row in rows) {
      final position = row.read<int>('position');
      if (currentPosition != position) {
        exercises.add((
          exerciseName: row.read<String>('exercise_name'),
          sets: <SetRecord>[],
        ));
        currentPosition = position;
      }
      exercises.last.sets.add((
        id: row.read<int>('set_id'),
        setNumber: row.read<int>('set_number'),
        weight: row.read<double>('weight'),
        reps: row.read<int>('reps'),
      ));
      setCount++;
    }

    final first = rows.first;
    return (
      sessionId: first.read<int>('session_id'),
      routineId: first.read<int>('routine_id'),
      routineName: first.read<String>('routine_name'),
      exercises: exercises,
      setCount: setCount,
    );
  }

  /// Template exercises merged with today's sets — invariant 4.
  ///
  /// [extraHistory] holds per-exercise *show more* taps, each worth one
  /// additional prior session beyond the default two.
  Stream<List<SessionCard>> watchSessionCards({
    required String date,
    required int routineId,
    Map<int, int> extraHistory = const {},
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
        .asyncMap(
          (_) => _buildCards(
            date: date,
            routineId: routineId,
            extraHistory: extraHistory,
          ),
        );
  }

  /// Prior sessions shown on a card before any *show more* tap — invariant 5.
  static const defaultHistoryDepth = 2;

  Future<List<SessionCard>> _buildCards({
    required String date,
    required int routineId,
    Map<int, int> extraHistory = const {},
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

    // Deepest card sets the page for all of them; each is then trimmed to its
    // own depth below. One query beats one per card.
    final depths = {
      for (final id in ordered)
        id: defaultHistoryDepth + (extraHistory[id] ?? 0),
    };
    // The extra row is the lookahead that answers "is there more?".
    final history = await historyFor(
      ordered,
      excludingSession: session?.id,
      limit: depths.values.reduce((a, b) => a > b ? a : b) + 1,
    );

    return [
      for (final id in ordered)
        SessionCard(
          exerciseId: id,
          exerciseName: names[id] ?? '',
          todaysSets: todays[id] ?? const [],
          history: (history[id] ?? const []).take(depths[id]!).toList(),
          hasMoreHistory: (history[id] ?? const []).length > depths[id]!,
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
    final query =
        _db.select(_db.sessionExercises).join([
            innerJoin(
              _db.setEntries,
              _db.setEntries.sessionExerciseId.equalsExp(
                _db.sessionExercises.id,
              ),
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
        id: entry.id,
        setNumber: entry.setNumber,
        weight: entry.weight,
        reps: entry.reps,
      ));
    }
    return result;
  }

  Future<Map<int, String>> _exerciseNames(List<int> exerciseIds) async {
    final rows = await (_db.select(
      _db.exercises,
    )..where((e) => e.id.isIn(exerciseIds))).get();
    return {for (final row in rows) row.id: row.name};
  }

  /// Prior sessions per exercise, newest first — invariant 5.
  ///
  /// Backs both the session card and the exercise history screen; never
  /// filters by routine or weekday.
  Future<Map<int, List<ExerciseSession>>> historyFor(
    List<int> exerciseIds, {
    int? excludingSession,
    required int limit,
    int offset = 0,
  }) async {
    if (exerciseIds.isEmpty || limit <= 0) return {};

    final placeholders = List.filled(exerciseIds.length, '?').join(', ');
    final variables = <Variable>[
      for (final id in exerciseIds) Variable<int>(id),
    ];

    var exclusion = '';
    if (excludingSession != null) {
      exclusion = 'AND se.session_id != ?';
      variables.add(Variable<int>(excludingSession));
    }
    variables
      ..add(Variable<int>(offset))
      ..add(Variable<int>(offset + limit));

    // One windowed pass rather than a query per card.
    final rows = await _db
        .customSelect(
          '''
      WITH ranked AS (
        SELECT se.exercise_id, se.id AS session_exercise_id,
               s.id AS session_id, s.date,
               ROW_NUMBER() OVER (
                 PARTITION BY se.exercise_id
                 ORDER BY s.date DESC, s.id DESC
               ) AS rn
          FROM session_exercises se
          JOIN sessions s ON s.id = se.session_id
         WHERE se.exercise_id IN ($placeholders)
           $exclusion
           -- A session_exercises row can outlive its sets (invariant 10 only
           -- clears it on the last delete). Ranking one would spend a slot on
           -- a row the join below drops, silently shortening the page.
           AND EXISTS (
             SELECT 1 FROM set_entries x
              WHERE x.session_exercise_id = se.id
           )
      )
      SELECT r.exercise_id, r.session_id, r.date, r.rn,
             e.id AS set_id, e.set_number, e.weight, e.reps
        FROM ranked r
        JOIN set_entries e ON e.session_exercise_id = r.session_exercise_id
       WHERE r.rn > ? AND r.rn <= ?
       ORDER BY r.exercise_id, r.rn, e.set_number
      ''',
          variables: variables,
          readsFrom: {_db.sessionExercises, _db.sessions, _db.setEntries},
        )
        .get();

    // Grouped by rank, not date: one exercise now yields several sessions.
    final result = <int, List<ExerciseSession>>{};
    final rankSeen = <int, int>{};
    for (final row in rows) {
      final exerciseId = row.read<int>('exercise_id');
      final rank = row.read<int>('rn');
      final sessions = result[exerciseId] ??= [];

      if (rankSeen[exerciseId] != rank) {
        sessions.add((
          sessionId: row.read<int>('session_id'),
          date: row.read<String>('date'),
          sets: <SetRecord>[],
        ));
        rankSeen[exerciseId] = rank;
      }

      sessions.last.sets.add((
        id: row.read<int>('set_id'),
        setNumber: row.read<int>('set_number'),
        weight: row.read<double>('weight'),
        reps: row.read<int>('reps'),
      ));
    }
    return result;
  }
}
