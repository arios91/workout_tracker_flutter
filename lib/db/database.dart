import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Exercises,
    Routines,
    RoutineExercises,
    Sessions,
    SessionExercises,
    SetEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For an in-memory or otherwise pre-built executor.
  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 1;

  /// Table names and row counts, for verifying the database opened.
  Future<List<({String name, int rows})>> tableCounts() async {
    final tables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ).get();

    final counts = <({String name, int rows})>[];
    for (final table in tables) {
      final name = table.read<String>('name');
      // Identifiers can't be bound as parameters; these come from
      // sqlite_master, not from user input.
      final row = await customSelect('SELECT COUNT(*) AS c FROM "$name"')
          .getSingle();
      counts.add((name: name, rows: row.read<int>('c')));
    }
    return counts;
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      // SQLite disables foreign keys per connection by default. Without this
      // every ON DELETE action in tables.dart is inert: cascades don't fire
      // and the RESTRICT guarding exercise history doesn't guard anything.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'workout_tracker.sqlite'));

    // sqlite3 3.x bundles its own native libraries; no separate libs package.
    sqlite3.tempDirectory = (await getTemporaryDirectory()).path;

    return NativeDatabase.createInBackground(file);
  });
}
