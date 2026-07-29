import 'package:flutter/material.dart';

import '../repositories/routine_repository.dart';
import '../theme.dart';

/// Shown on a day with no routine. Naming one is M1's only bootstrap.
class EmptyStateScreen extends StatefulWidget {
  const EmptyStateScreen({
    super.key,
    required this.weekday,
    required this.routines,
  });

  /// ISO weekday the new routine will be assigned to.
  final int weekday;
  final RoutineRepository routines;

  @override
  State<EmptyStateScreen> createState() => _EmptyStateScreenState();
}

class _EmptyStateScreenState extends State<EmptyStateScreen> {
  final _name = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    // The routine stream is watching this weekday, so creating the row swaps
    // this screen for the session screen on its own.
    await widget.routines.createRoutine(
      name: name,
      defaultWeekday: widget.weekday,
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No routine for today.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Name one to start logging.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'routine'),
                onSubmitted: (_) => _create(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _create,
                  child: const Text('Create'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
