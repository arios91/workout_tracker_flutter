import 'package:flutter/material.dart';

import 'db/database.dart';
import 'logic/active_session.dart';
import 'logic/age.dart';
import 'repositories/exercise_repository.dart';
import 'repositories/routine_repository.dart';
import 'repositories/session_repository.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final today = formatDate(DateTime.now());
  final stored = await ActiveSession.read();
  // A key from an earlier day is stale: resuming it would reopen yesterday's
  // workout. Invariant 7 — plain local date strings, compared as strings.
  final resume = stored?.date == today ? stored : null;
  if (stored != null && resume == null) await ActiveSession.clear();

  runApp(WorkoutTrackerApp(resume: resume));
}

class WorkoutTrackerApp extends StatefulWidget {
  const WorkoutTrackerApp({super.key, this.resume});

  /// The workout to reopen on launch, if one was left in progress today.
  final ({String date, int routineId})? resume;

  @override
  State<WorkoutTrackerApp> createState() => _WorkoutTrackerAppState();
}

class _WorkoutTrackerAppState extends State<WorkoutTrackerApp> {
  // Held here rather than built in build(): a new instance would open another
  // connection on every rebuild.
  late final AppDatabase _db = AppDatabase();
  late final _exercises = ExerciseRepository(_db);
  late final _routines = RoutineRepository(_db);
  late final _sessions = SessionRepository(_db);

  // Read once at startup, not at any insert site — invariant 6.
  final DateTime _now = DateTime.now();

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Workout Tracker',
      debugShowCheckedModeBanner: false,
      // Dark only, permanently — no light palette exists.
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      // Home is the unconditional root; SessionScreen is only ever pushed.
      home: HomeScreen(
        today: formatDate(_now),
        weekday: _now.weekday,
        resume: widget.resume,
        exercises: _exercises,
        routines: _routines,
        sessions: _sessions,
      ),
    );
  }
}
