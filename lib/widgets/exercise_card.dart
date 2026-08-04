import 'package:flutter/material.dart';

import '../logic/age.dart';
import '../logic/collapse.dart';
import '../repositories/records.dart';
import '../theme.dart';

/// One exercise on the session screen: what was done, and the entry row.
class ExerciseCard extends StatefulWidget {
  const ExerciseCard({
    super.key,
    required this.card,
    required this.today,
    required this.onConfirm,
    required this.onShowMore,
  });

  final SessionCard card;
  final String today;
  final Future<void> Function(double weight, int reps) onConfirm;
  final VoidCallback onShowMore;

  @override
  State<ExerciseCard> createState() => _ExerciseCardState();
}

/// One prior session: collapsed notation and how long ago — invariant 5.
class _HistoryLine extends StatelessWidget {
  const _HistoryLine({required this.session, required this.today});

  final ExerciseSession session;
  final String today;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            collapse(session.sets),
            style: AppText.notation.copyWith(color: AppColors.textMuted),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatAge(session.date, today),
          style: const TextStyle(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _ExerciseCardState extends State<ExerciseCard> {
  final _weight = TextEditingController();
  final _reps = TextEditingController();
  final _repsFocus = FocusNode();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _weight.text = _prefillWeight() ?? '';
  }

  @override
  void didUpdateWidget(ExerciseCard old) {
    super.didUpdateWidget(old);
    // The stream repaints after every confirm; only adopt a new weight when
    // the field is untouched, so it never overwrites what's being typed.
    if (_weight.text.isEmpty) _weight.text = _prefillWeight() ?? '';
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    _repsFocus.dispose();
    super.dispose();
  }

  /// Rendered at display time, never persisted — invariant 1.
  String? _prefillWeight() {
    final sets = widget.card.todaysSets.isNotEmpty
        ? widget.card.todaysSets
        : widget.card.history.firstOrNull?.sets;
    if (sets == null || sets.isEmpty) return null;
    return formatWeight(sets.last.weight);
  }

  Future<void> _confirm() async {
    final weight = double.tryParse(_weight.text.trim());
    final reps = int.tryParse(_reps.text.trim());
    if (weight == null || reps == null || reps <= 0) return;

    setState(() => _saving = true);
    try {
      await widget.onConfirm(weight, reps);
      if (!mounted) return;
      // Weight carries forward; reps are required per set.
      _reps.clear();
      _repsFocus.requestFocus();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final done = card.todaysSets.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.exerciseName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (done) ...[
              const SizedBox(height: 6),
              Text(collapse(card.todaysSets), style: AppText.notation),
            ],
            for (final prior in card.history) ...[
              const SizedBox(height: 6),
              _HistoryLine(session: prior, today: widget.today),
            ],
            if (card.hasMoreHistory)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: widget.onShowMore,
                  child: const Text('show more history'),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _weight,
                    style: AppText.input,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'weight'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _reps,
                    focusNode: _repsFocus,
                    style: AppText.input,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'reps'),
                    onSubmitted: (_) => _confirm(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _confirm,
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
