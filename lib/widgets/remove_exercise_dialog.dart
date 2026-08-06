import 'package:flutter/material.dart';

import '../theme.dart';

/// What the user confirmed removing.
typedef RemoveChoice = ({bool fromSession, bool fromRoutine});

/// Confirms removing an exercise, separating today's sets from the template.
///
/// Returns null if cancelled.
Future<RemoveChoice?> showRemoveExerciseDialog(
  BuildContext context, {
  required String exerciseName,
  required String routineName,
  required int setCount,
}) {
  return showDialog<RemoveChoice>(
    context: context,
    builder: (_) => _RemoveExerciseDialog(
      exerciseName: exerciseName,
      routineName: routineName,
      setCount: setCount,
    ),
  );
}

class _RemoveExerciseDialog extends StatefulWidget {
  const _RemoveExerciseDialog({
    required this.exerciseName,
    required this.routineName,
    required this.setCount,
  });

  final String exerciseName;
  final String routineName;
  final int setCount;

  @override
  State<_RemoveExerciseDialog> createState() => _RemoveExerciseDialogState();
}

class _RemoveExerciseDialogState extends State<_RemoveExerciseDialog> {
  // Nothing to delete from the session when no sets were logged.
  late bool _fromSession = widget.setCount > 0;
  bool _fromRoutine = true;

  @override
  Widget build(BuildContext context) {
    final sets = widget.setCount;
    return AlertDialog(
      title: Text('Remove ${widget.exerciseName}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Option(
            value: _fromSession,
            // Unlogged exercises have nothing to remove from the session.
            onChanged: sets == 0
                ? null
                : (on) => setState(() => _fromSession = on),
            title: 'from this session',
            subtitle: sets == 0
                ? 'not logged today'
                : 'deletes ${sets == 1 ? "1 set" : "$sets sets"}',
          ),
          _Option(
            value: _fromRoutine,
            onChanged: (on) => setState(() => _fromRoutine = on),
            title: 'from the ${widget.routineName} routine',
            subtitle: 'stops it appearing on future workouts',
          ),
          const SizedBox(height: 8),
          const Text(
            'Past sessions keep their sets either way.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _fromSession || _fromRoutine
              ? () => Navigator.of(
                  context,
                ).pop((fromSession: _fromSession, fromRoutine: _fromRoutine))
              : null,
          child: const Text('Remove'),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.subtitle,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return CheckboxListTile(
      value: value,
      onChanged: enabled ? (on) => onChanged!(on ?? false) : null,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? AppColors.textPrimary : AppColors.textMuted,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
    );
  }
}
