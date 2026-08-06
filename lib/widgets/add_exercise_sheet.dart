import 'package:flutter/material.dart';

import '../repositories/exercise_repository.dart';
import '../theme.dart';

/// Picks an existing exercise or names a new one.
///
/// Returns the chosen name, or null if dismissed.
class AddExerciseSheet extends StatefulWidget {
  const AddExerciseSheet({super.key, required this.exercises});

  final ExerciseRepository exercises;

  @override
  State<AddExerciseSheet> createState() => _AddExerciseSheetState();
}

class _AddExerciseSheetState extends State<AddExerciseSheet> {
  final _name = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    Navigator.pop(context, trimmed);
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                onPressed: () => _submit(_name.text),
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
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
                  shrinkWrap: true,
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
    );
  }
}
