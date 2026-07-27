import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../db/database.dart';

/// Queries over the global exercise list.
class ExerciseRepository {
  ExerciseRepository(this._db);

  final AppDatabase _db;

  /// Id of the exercise with this name, creating it if new. Case-insensitive.
  Future<int> findOrCreate(String name) async {
    final trimmed = name.trim();

    final existing = await _findByName(trimmed);
    if (existing != null) return existing;

    try {
      return await _db
          .into(_db.exercises)
          .insert(ExercisesCompanion.insert(name: trimmed));
    } on SqliteException {
      // Lost a race to a concurrent insert of the same name; read back winner.
      final winner = await _findByName(trimmed);
      if (winner != null) return winner;
      rethrow;
    }
  }

  Future<int?> _findByName(String name) async {
    final query = _db.select(_db.exercises)
      ..where((e) => e.name.equals(name))
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row?.id;
  }

  /// Every exercise, alphabetically.
  Stream<List<({int id, String name})>> watchAll() {
    final query = _db.select(_db.exercises)
      ..orderBy([(e) => OrderingTerm(expression: e.name)]);
    return query.watch().map(
      (rows) => rows.map((r) => (id: r.id, name: r.name)).toList(),
    );
  }
}
