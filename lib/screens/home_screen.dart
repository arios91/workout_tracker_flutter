import 'package:flutter/material.dart';

import '../logic/active_session.dart';
import '../logic/age.dart';
import '../logic/collapse.dart';
import '../repositories/exercise_repository.dart';
import '../repositories/records.dart';
import '../repositories/routine_repository.dart';
import '../repositories/session_repository.dart';
import '../theme.dart';
import 'session_screen.dart';

/// The landing screen. M1 shows today's card only — no pager, no past cards.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.today,
    required this.weekday,
    required this.exercises,
    required this.routines,
    required this.sessions,
    this.resume,
  });

  final String today;
  final int weekday;
  final ExerciseRepository exercises;
  final RoutineRepository routines;
  final SessionRepository sessions;

  /// A workout left in progress today, reopened once on launch.
  final ({String date, int routineId})? resume;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Pushed after the first frame so home stays beneath it and back works.
    final resume = widget.resume;
    if (resume != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resume(resume));
    }
  }

  Future<void> _resume(({String date, int routineId}) resume) async {
    final routine = await widget.routines.byId(resume.routineId);
    // Deleted out from under the key: drop it rather than resume nothing.
    if (routine == null) {
      await ActiveSession.clear();
      return;
    }
    if (!mounted) return;
    _openSession(routineId: routine.id, routineName: routine.name);
  }

  Future<void> _openSession({
    required int routineId,
    required String routineName,
  }) async {
    await ActiveSession.write(date: widget.today, routineId: routineId);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionScreen(
          date: widget.today,
          routineId: routineId,
          routineName: routineName,
          exercises: widget.exercises,
          routines: widget.routines,
          sessions: widget.sessions,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workout')),
      body: SafeArea(
        child: StreamBuilder<SessionSummary?>(
          stream: widget.sessions.watchSummary(date: widget.today),
          builder: (context, summarySnapshot) {
            if (!summarySnapshot.hasData &&
                summarySnapshot.connectionState != ConnectionState.active) {
              return const Center(child: CircularProgressIndicator());
            }

            final summary = summarySnapshot.data;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  formatHeaderDate(widget.today),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                if (summary != null)
                  _SummaryCard(
                    summary: summary,
                    onTap: () => _openSession(
                      routineId: summary.routineId,
                      routineName: summary.routineName,
                    ),
                  )
                else
                  _NotStartedCard(
                    weekday: widget.weekday,
                    routines: widget.routines,
                    onStart: (routine) => _openSession(
                      routineId: routine.id,
                      routineName: routine.name,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Today, once sets exist: what was lifted, collapsed.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.onTap});

  final SessionSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.routineName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              for (final exercise in summary.exercises) ...[
                Text(
                  exercise.exerciseName,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(collapse(exercise.sets), style: AppText.notation),
                const SizedBox(height: 10),
              ],
              Text(
                _counts(summary),
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _counts(SessionSummary summary) {
  final exercises = summary.exercises.length;
  final exerciseLabel = exercises == 1 ? 'exercise' : 'exercises';
  final setLabel = summary.setCount == 1 ? 'set' : 'sets';
  return '$exercises $exerciseLabel · ${summary.setCount} $setLabel';
}

/// Resolves the weekday's routine, then offers the start picker.
class _NotStartedCard extends StatelessWidget {
  const _NotStartedCard({
    required this.weekday,
    required this.routines,
    required this.onStart,
  });

  final int weekday;
  final RoutineRepository routines;
  final void Function(({int id, String name}) routine) onStart;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<({int id, String name})?>(
      stream: routines.watchRoutineForWeekday(weekday),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.active) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        return _StartCard(
          weekday: weekday,
          routines: routines,
          suggested: snapshot.data,
          onStart: onStart,
        );
      },
    );
  }
}

/// Offered when a day has no routine yet. Picking one creates it on Start.
// Not seed data: nothing is written until a choice is confirmed, so an install
// that never starts a workout keeps an empty database.
const _routineChoices = ['Shoulders', 'Legs', 'Back', 'Chest', 'Arms'];

const _otherChoice = 'Other';

/// Today, before anything is logged: pick a routine and start.
class _StartCard extends StatefulWidget {
  const _StartCard({
    required this.weekday,
    required this.routines,
    required this.suggested,
    required this.onStart,
  });

  final int weekday;
  final RoutineRepository routines;

  /// The routine assigned to this weekday, if any — preselected.
  final ({int id, String name})? suggested;
  final void Function(({int id, String name}) routine) onStart;

  @override
  State<_StartCard> createState() => _StartCardState();
}

class _StartCardState extends State<_StartCard> {
  final _otherName = TextEditingController();
  late String _choice = widget.suggested?.name ?? _routineChoices.first;
  bool _starting = false;

  @override
  void didUpdateWidget(_StartCard old) {
    super.didUpdateWidget(old);
    // The weekday's routine arrives after the first frame; adopt it unless a
    // choice has already been made by hand.
    final suggested = widget.suggested?.name;
    if (suggested != null && old.suggested == null) {
      _choice = suggested;
    }
  }

  @override
  void dispose() {
    _otherName.dispose();
    super.dispose();
  }

  /// Choices are the five defaults plus whatever the user has already named.
  List<String> get _options {
    final suggested = widget.suggested?.name;
    return [
      ..._routineChoices,
      if (suggested != null && !_routineChoices.contains(suggested)) suggested,
      _otherChoice,
    ];
  }

  Future<void> _start() async {
    final isOther = _choice == _otherChoice;
    final name = isOther ? _otherName.text.trim() : _choice;
    if (name.isEmpty) return;

    setState(() => _starting = true);
    // Assigning the weekday only when the day has none keeps Start from
    // silently reassigning an existing routine's default.
    final routine = await widget.routines.findOrCreate(
      name,
      defaultWeekday: widget.suggested == null ? widget.weekday : null,
    );
    if (!mounted) return;
    setState(() => _starting = false);
    widget.onStart(routine);
  }

  @override
  Widget build(BuildContext context) {
    final isOther = _choice == _otherChoice;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Start a workout',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _choice,
              decoration: const InputDecoration(labelText: 'routine'),
              dropdownColor: AppColors.surface,
              items: [
                for (final option in _options)
                  DropdownMenuItem(value: option, child: Text(option)),
              ],
              onChanged: _starting
                  ? null
                  : (value) {
                      if (value != null) setState(() => _choice = value);
                    },
            ),
            if (isOther) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _otherName,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'routine name'),
                onSubmitted: (_) => _start(),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _starting ? null : _start,
              child: Text(isOther ? 'Start' : 'Start $_choice'),
            ),
          ],
        ),
      ),
    );
  }
}
