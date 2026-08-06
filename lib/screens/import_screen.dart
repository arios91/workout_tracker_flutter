import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/age.dart';
import '../logic/legacy_parser.dart';
import '../repositories/import_repository.dart';
import '../theme.dart';

/// Review-and-confirm for the legacy backfill. Writes nothing until confirmed.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.imports});

  final ImportRepository imports;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ParseResult? _parsed;
  bool _alreadyPopulated = false;
  bool _importing = false;
  bool _repairing = false;
  bool _repaired = false;
  String? _error;

  // Confirmed merges. Pre-ticked pairs are the same machine under two names;
  // never merge across machines, so the pulldown family is not offered.
  final _merges = <String, String>{
    'Curl machine': 'Curl M',
    'Reat Delt': 'Rear delt',
    'Ab Machine': 'Ab M',
    'Lat Raise Machine': 'Lat Raise M',
  };
  final _accepted = <String>{
    'Curl machine',
    'Reat Delt',
    'Ab Machine',
    'Lat Raise Machine',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final populated = await widget.imports.hasAnySessions();
      final text = await rootBundle.loadString('docs/legacy-log.tsv');
      if (!mounted) return;
      setState(() {
        _alreadyPopulated = populated;
        _parsed = parseLegacyLog(text);
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _repair() async {
    setState(() => _repairing = true);
    try {
      await widget.imports.rebuildRoutineTemplates();
      if (mounted) setState(() => _repaired = true);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _repairing = false);
    }
  }

  Future<void> _import() async {
    final parsed = _parsed;
    if (parsed == null) return;

    setState(() => _importing = true);
    try {
      await widget.imports.importSessions(
        parsed.sessions,
        dateFor: (s) => formatDate(legacySessionDate(s)),
        nameMerges: {
          for (final entry in _merges.entries)
            if (_accepted.contains(entry.key)) entry.key: entry.value,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _importing = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;

    return Scaffold(
      appBar: AppBar(title: const Text('Import legacy log')),
      body: SafeArea(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
              )
            : parsed == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_alreadyPopulated) ...[
                    const _Warning(
                      'This database already has sessions. Importing now will '
                      'fail where dates collide, and the whole import rolls '
                      'back. Start from a fresh install.',
                    ),
                    const SizedBox(height: 16),
                    _Section(
                      title: 'Repair routine templates',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Sets each routine to the exercises of its most '
                            'recent session. Fixes templates that collected '
                            'every exercise ever done under that routine.\n\n'
                            'Session history is not touched.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _repairing ? null : _repair,
                            child: Text(
                              _repairing ? 'Rebuilding…' : 'Rebuild templates',
                            ),
                          ),
                          if (_repaired)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Templates rebuilt.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  _Section(
                    title: 'What will be written',
                    child: Text(
                      '${parsed.sessions.length} sessions\n'
                      '${_setCount(parsed)} sets\n'
                      '${_exerciseCount(parsed)} exercise entries',
                      style: AppText.notation,
                    ),
                  ),
                  _Section(
                    title: 'Dates are synthesized',
                    child: const Text(
                      'The log has week numbers, not dates. Week 1 Monday is '
                      'taken as 2025-12-29, so Week 1 Chest lands on '
                      '2026-01-01. Column order sets the weekday: Shoulders '
                      'Monday through Arms Friday.\n\n'
                      'Days are approximate wherever a workout actually moved.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  _Section(
                    title: 'Merge these names?',
                    child: Column(
                      children: [
                        for (final entry in _merges.entries)
                          CheckboxListTile(
                            value: _accepted.contains(entry.key),
                            onChanged: (on) => setState(() {
                              if (on ?? false) {
                                _accepted.add(entry.key);
                              } else {
                                _accepted.remove(entry.key);
                              }
                            }),
                            title: Text('${entry.key}  →  ${entry.value}'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        const SizedBox(height: 8),
                        const Text(
                          'Lat pulldown, Plate Lat pulldown and Pulldown M are '
                          'different machines with incompatible scales. They '
                          'stay separate.',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  _Section(
                    title: '${parsed.skipped.length} cells need attention',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final cell in parsed.skipped)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Week ${cell.week} · ${cell.routine}',
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(cell.raw, style: AppText.notation),
                                Text(
                                  cell.reason,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Text(
                          'These are gaps in the original log, not parse '
                          'failures. Nothing is invented to fill them.',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: parsed == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _importing ? null : _import,
                    child: Text(
                      _importing
                          ? 'Importing…'
                          : 'Import ${parsed.sessions.length} sessions',
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

int _setCount(ParseResult parsed) {
  var total = 0;
  for (final session in parsed.sessions) {
    for (final exercise in session.exercises) {
      total += exercise.sets.length;
    }
  }
  return total;
}

int _exerciseCount(ParseResult parsed) {
  var total = 0;
  for (final session in parsed.sessions) {
    total += session.exercises.length;
  }
  return total;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.textPrimary),
      ),
    );
  }
}
