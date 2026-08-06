import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    required this.onUpdateSet,
    required this.onDeleteSet,
    required this.onRemove,
  });

  final SessionCard card;
  final String today;
  final Future<void> Function(double weight, int reps) onConfirm;
  final VoidCallback onShowMore;
  final Future<void> Function(int setId, double weight, int reps) onUpdateSet;
  final Future<void> Function(int setId) onDeleteSet;
  final VoidCallback onRemove;

  @override
  State<ExerciseCard> createState() => _ExerciseCardState();
}

/// One editable set in edit mode. Commits on submit and on focus loss.
class _SetRow extends StatefulWidget {
  const _SetRow({
    super.key,
    required this.set,
    required this.onUpdate,
    required this.onDelete,
  });

  final SetRecord set;
  final Future<void> Function(double weight, int reps) onUpdate;
  final Future<void> Function() onDelete;

  @override
  State<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<_SetRow> {
  late final _weight = TextEditingController(
    text: formatWeight(widget.set.weight),
  );
  late final _reps = TextEditingController(text: '${widget.set.reps}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  // Tabbing away is as much a commit as submitting.
  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  @override
  void dispose() {
    // Removed first: disposing the node fires the listener, and committing
    // against disposed controllers throws.
    _focus.removeListener(_onFocusChange);
    _weight.dispose();
    _reps.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    final weight = double.tryParse(_weight.text.trim());
    final reps = int.tryParse(_reps.text.trim());
    // Reverting on bad input beats writing a value that isn't a set.
    if (weight == null || reps == null || reps <= 0) {
      _weight.text = formatWeight(widget.set.weight);
      _reps.text = '${widget.set.reps}';
      return;
    }
    if (weight == widget.set.weight && reps == widget.set.reps) return;
    await widget.onUpdate(weight, reps);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Focus(
        focusNode: _focus,
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text('${widget.set.setNumber}', style: AppText.setNumber),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _weight,
                style: AppText.input,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(isDense: true),
                onSubmitted: (_) => _commit(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _reps,
                style: AppText.input,
                keyboardType: TextInputType.number,
                // keyboardType only requests a numeric keyboard; hardware
                // input and paste bypass it.
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(isDense: true),
                onSubmitted: (_) => _commit(),
              ),
            ),
            IconButton(
              // Dropping focus first: otherwise focus loss commits an update
              // against the row being deleted.
              onPressed: () {
                _focus.removeListener(_onFocusChange);
                widget.onDelete();
              },
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Delete set',
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
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
  bool _editing = false;

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
    // Deleting the last set empties the card, so there is nothing left to edit
    // and it reverts to its reference line — invariant 10.
    final editing = _editing && done;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    card.exerciseName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (done && !_editing)
                  IconButton(
                    onPressed: () => setState(() => _editing = true),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Edit sets',
                    color: AppColors.textSecondary,
                  ),
                // Shown even without sets: an untouched template exercise is
                // exactly the one worth removing, and the pencil is absent.
                if (!_editing)
                  IconButton(
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: 'Remove exercise',
                    color: AppColors.textSecondary,
                  ),
              ],
            ),
            if (editing)
              for (final set in card.todaysSets)
                _SetRow(
                  key: ValueKey(set.id),
                  set: set,
                  onUpdate: (weight, reps) =>
                      widget.onUpdateSet(set.id, weight, reps),
                  onDelete: () => widget.onDeleteSet(set.id),
                )
            else ...[
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
            ],
            const SizedBox(height: 12),
            if (editing)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  // Unfocus first: a focused row commits on focus loss, and
                  // collapsing straight away would tear it down before the
                  // write is issued.
                  onPressed: () async {
                    FocusScope.of(context).unfocus();
                    await Future<void>.delayed(Duration.zero);
                    if (mounted) setState(() => _editing = false);
                  },
                  child: const Text('Confirm'),
                ),
              )
            else
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
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
