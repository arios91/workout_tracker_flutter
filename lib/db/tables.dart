import 'package:drift/drift.dart';

/// Every exercise ever named, across all routines and all history.
class Exercises extends Table {
  IntColumn get id => integer().autoIncrement()();

  // Collation on the column, not `.unique()`: that builds a case-sensitive
  // index and lets "Bench" and "bench" coexist as separate exercises.
  TextColumn get name =>
      text().customConstraint('NOT NULL UNIQUE COLLATE NOCASE')();
}

/// A named workout day — "Legs", "Chest".
class Routines extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  /// ISO weekday, 1 = Monday .. 7 = Sunday. Null if not tied to a day.
  IntColumn get defaultWeekday => integer().nullable()();

  IntColumn get position => integer()();
}

/// The template: which exercises a routine contains, in order.
class RoutineExercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get routineId =>
      integer().references(Routines, #id, onDelete: KeyAction.cascade)();
  IntColumn get exerciseId =>
      integer().references(Exercises, #id, onDelete: KeyAction.restrict)();
  IntColumn get position => integer()();

  // M2. Always NULL until then.
  IntColumn get supersetGroup => integer().nullable()();
}

/// One workout on one day. Created lazily — invariant 3.
class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The workout day, `YYYY-MM-DD` — invariant 7.
  TextColumn get date => text().withLength(min: 10, max: 10)();

  IntColumn get routineId =>
      integer().references(Routines, #id, onDelete: KeyAction.restrict)();
  TextColumn get note => text().nullable()();

  // When the row was written, not when the workout happened: for a backdated
  // import these differ by years.
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {date, routineId},
  ];
}

/// What was actually performed in a session, in order.
class SessionExercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId =>
      integer().references(Sessions, #id, onDelete: KeyAction.cascade)();
  IntColumn get exerciseId =>
      integer().references(Exercises, #id, onDelete: KeyAction.restrict)();
  IntColumn get position => integer()();

  // M2. Always NULL until then.
  IntColumn get supersetGroup => integer().nullable()();
}

/// A single confirmed set — invariant 1.
class SetEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionExerciseId => integer().references(
    SessionExercises,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// 1-based and contiguous — invariant 9.
  IntColumn get setNumber => integer()();

  /// Decimal — the log contains 27.5 and 22.5. Invariant 12.
  RealColumn get weight => real()();

  IntColumn get reps => integer()();

  // Audit only; sets order by setNumber, never by this.
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {sessionExerciseId, setNumber},
  ];
}
