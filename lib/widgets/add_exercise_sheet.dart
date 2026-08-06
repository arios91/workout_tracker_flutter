import 'package:flutter/material.dart';

import '../repositories/exercise_repository.dart';
import '../theme.dart';

/// An exercise to add, and where to add it.
typedef AddChoice = ({String name, bool toSession, bool toRoutine});

/// Picks an existing exercise or names a new one.
///
/// Returns the choice, or null if dismissed.
class AddExerciseSheet extends StatefulWidget {
  const AddExerciseSheet({
    super.key,
    required this.exercises,
    required this.routineName,
    required this.isToday,
  });

  final ExerciseRepository exercises;
  final String routineName;

  /// Past dates do not read the template, so the routine option is explained
  /// differently there.
  final bool isToday;

  @override
  State<AddExerciseSheet> createState() => _AddExerciseSheetState();
}

class _AddExerciseSheetState extends State<AddExerciseSheet> {
  final _name = TextEditingController();
  String _query = '';
  bool _toSession = true;
  // Off by default: adding to today is the common case, and changing the
  // routine should be deliberate.
  bool _toRoutine = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (!_toSession && !_toRoutine) return;
    Navigator.pop(context, (
      name: trimmed,
      toSession: _toSession,
      toRoutine: _toRoutine,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      // Fixed, not shrink-to-fit: a sheet that resizes with the match count
      // drags the field and buttons around while you type.
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'exercise'),
                    onChanged: (value) => setState(() => _query = value),
                    onSubmitted: _submit,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _toSession || _toRoutine
                      ? () => _submit(_name.text)
                      : null,
                  child: const Text('Add'),
                ),
              ],
            ),
            CheckboxListTile(
              value: _toSession,
              onChanged: (on) => setState(() => _toSession = on ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: const Text('to this session'),
            ),
            CheckboxListTile(
              value: _toRoutine,
              onChanged: (on) => setState(() => _toRoutine = on ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text('to the ${widget.routineName} routine'),
              subtitle: widget.isToday
                  ? null
                  : const Text(
                      'affects future workouts, not this date',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<({int id, String name})>>(
                stream: widget.exercises.watchAll(),
                builder: (context, snapshot) {
                  final all = snapshot.data ?? const [];
                  // Substring, not prefix: typing "bench" must surface "Incline
                  // bench" too, or near-duplicates get created unseen.
                  final query = _query.trim().toLowerCase();
                  final matches = query.isEmpty
                      ? all
                      : all
                            .where((e) => e.name.toLowerCase().contains(query))
                            .toList();
                  if (matches.isEmpty) return const SizedBox.shrink();
                  return ListView.separated(
                    itemCount: matches.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, i) => ListTile(
                      title: Text(
                        matches[i].name,
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                      onTap: () => _submit(matches[i].name),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
