import 'package:drift/drift.dart';

import '../db/database.dart';

/// Queries over routines and their exercise templates.
class RoutineRepository {
  RoutineRepository(this._db);

  final AppDatabase _db;

  /// Creates a routine, appended at the end of the list.
  Future<int> createRoutine({required String name, int? defaultWeekday}) async {
    final position = await _nextPosition();
    return _db
        .into(_db.routines)
        .insert(
          RoutinesCompanion.insert(
            name: name.trim(),
            defaultWeekday: Value(defaultWeekday),
            position: position,
          ),
        );
  }

  Future<int> _nextPosition() async {
    final max = _db.routines.position.max();
    final row = await (_db.selectOnly(
      _db.routines,
    )..addColumns([max])).getSingle();
    return (row.read(max) ?? 0) + 1;
  }

  /// Finds a routine by name, or creates it. Matching is case-insensitive.
  Future<({int id, String name})> findOrCreate(
    String name, {
    int? defaultWeekday,
  }) async {
    final trimmed = name.trim();
    return _db.transaction(() async {
      final existing =
          await (_db.select(_db.routines)
                ..where((r) => r.name.lower().equals(trimmed.toLowerCase()))
                ..limit(1))
              .getSingleOrNull();
      if (existing != null) {
        return (id: existing.id, name: existing.name);
      }

      final id = await createRoutine(
        name: trimmed,
        defaultWeekday: defaultWeekday,
      );
      return (id: id, name: trimmed);
    });
  }

  /// Every routine, in list order.
  Stream<List<({int id, String name})>> watchAll() {
    final query = _db.select(_db.routines)
      ..orderBy([(r) => OrderingTerm(expression: r.position)]);
    return query.watch().map(
      (rows) => [for (final row in rows) (id: row.id, name: row.name)],
    );
  }

  /// The routine assigned to this weekday, or null if the day has none.
  Stream<({int id, String name})?> watchRoutineForWeekday(int isoWeekday) {
    final query = _db.select(_db.routines)
      ..where((r) => r.defaultWeekday.equals(isoWeekday))
      ..orderBy([(r) => OrderingTerm(expression: r.position)])
      ..limit(1);
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : (id: row.id, name: row.name),
    );
  }

  /// Appends an exercise to a routine's template. No-op if already present.
  Future<void> addExerciseToRoutine({
    required int routineId,
    required int exerciseId,
  }) async {
    await _db.transaction(() async {
      final existing =
          await (_db.select(_db.routineExercises)..where(
                (re) =>
                    re.routineId.equals(routineId) &
                    re.exerciseId.equals(exerciseId),
              ))
              .getSingleOrNull();
      if (existing != null) return;

      final max = _db.routineExercises.position.max();
      final row =
          await (_db.selectOnly(_db.routineExercises)
                ..addColumns([max])
                ..where(_db.routineExercises.routineId.equals(routineId)))
              .getSingle();
      final position = (row.read(max) ?? 0) + 1;

      await _db
          .into(_db.routineExercises)
          .insert(
            RoutineExercisesCompanion.insert(
              routineId: routineId,
              exerciseId: exerciseId,
              position: position,
            ),
          );
    });
  }
}
