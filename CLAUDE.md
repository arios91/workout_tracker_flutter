# CLAUDE.md

Working instructions for this repo. Design rationale lives in `README.md` — read it first, and don't restate it here.

Keep your replies extremely concise and focus on conveying the key information. No unnecessary fluff, no long code snippets.

## What this is

A local-only workout logbook in Flutter. Its entire job: show what I lifted last time, record what I lift today. Deliberate minimalism is the product thesis, not a shortcut.

## Commands

```bash
flutter analyze          # must pass clean — no warnings, no ignores added to silence them
flutter test             # must pass
flutter run
dart run build_runner build --delete-conflicting-outputs   # after any Drift schema change
```

Run `flutter analyze` and `flutter test` before telling me a task is done. If either fails, fix it or say so — don't report success.

## Stack

- Flutter (Android + iOS)
- Drift / SQLite for persistence — local only, no server, no accounts, no sync
- Reactive Drift streams so the UI updates on write

## Schema

```
exercises          id, name UNIQUE COLLATE NOCASE
routines           id, name, default_weekday, position
routine_exercises  id, routine_id, exercise_id, position, superset_group   -- template
sessions           id, date, routine_id, note, created_at
                   UNIQUE (date, routine_id)
session_exercises  id, session_id, exercise_id, position, superset_group   -- actual
set_entries        id, session_exercise_id, set_number,
                   weight NOT NULL, reps NOT NULL, created_at
```

`routine_exercises` and `session_exercises` are independent on purpose. The session screen is a **merge**: cards come from the template, any with `session_exercises` rows for today show today's numbers, ad-hoc additions have no template row.

## Invariants

Violating any of these corrupts data or breaks the core interaction.

1. **Only confirmed sets are written.** Pre-filled values are rendered from lookup at display time and never persisted. There is no draft or pending state.
2. **`weight` and `reps` are NOT NULL.** A partial set is unrepresentable.
3. **Sessions are created lazily**, on the first confirmed set. Opening the app and logging nothing leaves no row.
4. **Sessions pre-fill from the routine template, never from the previous session.** Copying the last session would let one short workout truncate a routine permanently.
5. **"Last time" is a per-exercise lookup across all history**, excluding the current session, and always displays its age. Never key it to weekday, routine, or last session.
6. **Session date is always a parameter.** Never call `DateTime.now()` at an insert site — the importer backdates thousands of sessions.
7. **Dates are local device dates stored as plain date strings** (`2026-07-30`). Never UTC timestamps.
8. **Week numbers are derived** from the earliest session. Never stored.
9. **Deleting a set renumbers the sets above it** in that exercise, in one transaction. Gaps in `set_number` make the collapse function render nonsense.
10. **Deleting an exercise's last set removes its `session_exercises` row**, reverting the card to its reference line.
11. **Removing an exercise from a routine deletes one `routine_exercises` row** and never touches session history. `ON DELETE RESTRICT` on `exercises`.
12. **Weight is opaque and comparable only within one exercise.** No unit conversion, no cross-exercise arithmetic, ever.
13. **Writes go through a batched transaction path.** Don't build a repository that can only insert one set at a time.

## The collapse function

Pure function: ordered sets → display notation.

```
[(45,8),(45,8),(45,8),(45,7)]            → "@45 123-8 4-7"
[(120,18),(130,10),(130,10),(130,10)]    → "1@120-18 234@130-10"
[(90,4),(80,7),(80,7),(80,7)]            → "1@90-4 234@80-7"
```

Group consecutive sets sharing weight and reps. Hoist weight to a `@W` prefix if constant throughout, otherwise inline per run. Keep it pure and side-effect free — it renders both the session cards and the Excel `Log` sheet. Unit test it against `test/fixtures/sample_weeks.tsv`.

## Do not add

These were considered and rejected. Do not implement them, suggest them in code, or leave TODOs for them.

- Rest timers
- Streaks, badges, reminders, notifications
- 1RM estimates, volume totals, tonnage
- Body weight or measurement tracking
- Unit selection or conversion
- Completion flags, `is_complete` columns, summary screens, end-workout buttons
- "You've done this 3 times, add it to your routine?" prompts
- In-app charts (planned for a later phase, not now)
- Accounts, servers, sync

If a task seems to need one of these, stop and ask.

## Conventions

- Business logic out of widgets. Queries in a repository layer, pure transforms in plain Dart.
- Prefer small diffs to large rewrites. Don't scaffold beyond what the task asks for.
- No `// ignore:` comments to quiet the analyzer.
- Test the pure logic properly: collapse function, week derivation, set renumbering. Don't chase widget-test coverage for its own sake.

## Structure

lib/db/            Drift tables, database, seeds
lib/repositories/  all queries
lib/logic/         pure functions — must not import from db/
lib/screens/       one file per screen
lib/widgets/       shared components

Pure logic takes plain Dart records, never Drift row objects.

## State

No state management package. Drift streams + StreamBuilder for persisted
state; StatefulWidget for ephemeral input. Do not add Riverpod, Bloc,
Provider, or GetX without asking — the database is the source of truth
and unconfirmed input must stay local to the widget.

## Navigation

Navigator.push with MaterialPageRoute. Do not add GoRouter, auto_route,
or any routing package — four screens, one level deep, no deep links.
SessionScreen takes date + routineId and is reused for past sessions;
there is no separate read-only view.

## Milestone 1

One vertical slice. Nothing else.

- Drift schema and migration
- Seed the five routines with default weekdays: Shoulders/Traps (Mon), Legs (Tue), Back (Wed), Chest (Thu), Arms (Fri) — empty exercise lists
- Session screen: opens on today's routine, header shows routine and date
- Add an exercise to the session (creates it in `exercises` if new, appends to the routine)
- Entry loop: weight pre-filled and carried forward, reps empty and required, Confirm writes one row immediately
- Card collapses to notation via the collapse function
- Everything survives app restart

**Explicitly not in M1:** supersets, routine picker, session list, exercise history, routine settings editing, export, importer, charts.

## Roadmap after M1

2. Supersets, add-as-you-go toggle, routine picker for day swaps
3. Session list and exercise history (both open the same session editor)
4. Excel export — `Log` grid sheet + `Data` flat sheet
5. Legacy TSV importer (`docs/legacy-log.tsv`), with a review-and-confirm step
6. Charts on the exercise history screen
