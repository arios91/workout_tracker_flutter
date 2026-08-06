# CLAUDE.md

Working instructions for this repo. Design rationale lives in `README.md` — read it first, and don't restate it here.

Keep your replies extremely concise and focus on conveying the key information. No unnecessary fluff, no long code snippets.

## What this is

A local-only workout logbook in Flutter. Its entire job: show what I lifted last time, record what I lift today. Deliberate minimalism is the product thesis, not a shortcut.

## Commands

```bash
flutter analyze          # must pass clean — no warnings, no ignores added to silence them
flutter run
dart run build_runner build --delete-conflicting-outputs   # after any Drift schema change
```

Run `flutter analyze` before telling me a task is done. If it fails, fix it or say so — don't report success.

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

`weight` is a decimal (`RealColumn`) — the log contains `@27.5` and `@22.5`.

`superset_group` is **unused**. It exists only so the v2 importer can preserve `Superset` markers from the legacy log. Nothing in the UI reads or writes it.

`routine_exercises` and `session_exercises` are independent on purpose. The session screen is a **merge**: cards come from the template, any with `session_exercises` rows for today show today's numbers, ad-hoc additions have no template row.

**There is no seed data.** The database starts completely empty; routines and exercises are created by the user as they log. Do not add a `seed.dart` or insert default rows on first run.

## Invariants

Violating any of these corrupts data or breaks the core interaction.

1. **Only confirmed sets are written.** Pre-filled values are rendered from lookup at display time and never persisted. There is no draft or pending state.
2. **`weight` and `reps` are NOT NULL.** A partial set is unrepresentable.
3. **Sessions are created lazily**, on the first confirmed set. Opening the app and logging nothing leaves no row.
4. **Sessions pre-fill from the routine template, never from the previous session.** Copying the last session would let one short workout truncate a routine permanently.
5. **History is a per-exercise lookup across all history**, excluding the current session, ordered most-recent-first and paginated. Cards show the **two** most recent prior sessions by default; *show more history* fetches one additional prior session per tap. Always display each one's age.
   **Never filter history by routine or weekday.** The same exercise done on an off-day, as a one-off, or under a different routine is part of its history. The inline card lookup and the exercise history screen share one repository method.
6. **Session date is always a parameter.** Never call `DateTime.now()` at an insert site — the importer backdates thousands of sessions.
7. **Dates are local device dates stored as plain date strings** (`2026-07-30`). Never UTC timestamps.
8. **Week numbers are derived** from the earliest session. Never stored.
9. **Deleting a set renumbers the sets above it** in that exercise, in one transaction. Gaps in `set_number` make the collapse function render nonsense.
10. **Deleting an exercise's last set removes its `session_exercises` row**, reverting the card to its reference line.
11. **Removing an exercise from a routine deletes one `routine_exercises` row** and never touches session history. `ON DELETE RESTRICT` on `exercises`.
12. **Weight is opaque and comparable only within one exercise.** No unit conversion, no cross-exercise arithmetic, ever.
13. **Writes go through a batched transaction path.** Don't build a repository that can only insert one set at a time.
14. **Completion is derived, never stored.** A session is complete if it has sets and isn't today's. No column, no flag, no background sweep. Finishing a workout is navigation only — it does not mark anything.

## The collapse function

Pure function: ordered sets → display notation.

```
[(45,8),(45,8),(45,8),(45,7)]            → "@45 123-8 4-7"
[(120,18),(130,10),(130,10),(130,10)]    → "1@120-18 234@130-10"
[(90,4),(80,7),(80,7),(80,7)]            → "1@90-4 234@80-7"
```

Group consecutive sets sharing weight and reps. Hoist weight to a `@W` prefix if constant throughout, otherwise inline per run. Keep it pure and side-effect free — it renders session cards, history lines, home summaries, and the Excel `Log` sheet.

Tests for this are deferred — see Testing below. When they're written, use table-driven inline cases, not a TSV fixture: the legacy log holds parser input, not collapse output, and contains forms collapse can never emit (`@ 45` spacing, `kg` suffixes). A curated round-trip fixture (`collapse(parse(cell)) == cell`) belongs with the v2 parser.

## Do not add

These were considered and rejected. Do not implement them, suggest them in code, or leave TODOs for them.

- Superset pairing, linked cards, or any UI that reads `superset_group`
- Rest timers
- Streaks, badges, reminders, notifications
- 1RM estimates, volume totals, tonnage
- Body weight or measurement tracking
- Unit selection or conversion
- `is_complete` columns or any stored completion state — see invariant 14
- Prompts to finish a session, or any nagging about unfinished sessions
- Confirmation dialogs when editing a past session
- An "Edit workout" button or read-only session view — see Home screen
- "You've done this 3 times, add it to your routine?" prompts
- In-app charts (planned for a later phase, not now)
- Accounts, servers, sync
- Seed or sample data of any kind

If a task seems to need one of these, stop and ask.

## Home screen

The app's landing screen. A horizontal pager of session cards, most recent on the right.

- **Today's card** shows a summary if today has any sets, otherwise **Start {routine}** (the routine whose `default_weekday` is today) plus **Start other** for the rest. Driven by "has sets," never by whether Finish was tapped.
- **Past cards** show the collapsed exercises plus exercise and set counts. Swipe left to page back.
- **Tapping any card** opens it in `SessionScreen`, fully editable. No Edit button, no read-only mode, no unlock step — the card itself is the affordance.
- **Pager is capped at the 10 most recent sessions**, with an *All sessions* link below for the full list.

## Active session and resume

Cycling to another app mid-workout must return to the workout, not to home.

- **Start Workout** writes the date and routine id to `SharedPreferences`. Not the session id: sessions are created lazily on the first confirmed set (invariant 3), so at Start time there is none.
- **On launch:** if the key is set *and* its date is today, push `SessionScreen` for it directly. Otherwise clear the key and show home.
- **Finish workout** clears the key and pops to home.

This key is UI state only. Nothing about completion, history, or summaries reads it, and it is never a database column (invariant 14).

## Structure

```
lib/db/            Drift tables and database
lib/repositories/  all queries
lib/logic/         pure functions — must not import from db/
lib/screens/       one file per screen
lib/widgets/       shared components
lib/theme.dart
```

Pure logic takes plain Dart records, never Drift row objects. Dependencies flow one direction: screens → repositories → db. `logic/` depends on nothing.

## State

No state management package. Drift streams plus `StreamBuilder` for persisted state; `StatefulWidget` for ephemeral input. Do not add Riverpod, Bloc, Provider, or GetX without asking — the database is the single source of truth, and unconfirmed input must stay local to the widget (invariant 1).

## Navigation

`Navigator.push` with `MaterialPageRoute`. Do not add GoRouter, auto_route, or any routing package — five screens, one level deep, no deep links.

Home is the root. `SessionScreen` takes a date and routine id and is reused for today, past sessions, and edits — there is only one session screen and no read-only viewer.

## Theme

`lib/theme.dart`, Material 3, dark-first (`ThemeMode.system` supported).

Monospace with tabular figures for all numbers and collapsed notation — set rows must column-align. System font for labels and exercise names.

```
accent           #008AC9   focus rings, active borders, accent text
button / pressed #006E9F   filled buttons, pressed state
onPrimary        white
background       #0D1113
surface / input  #181D21
border           #2F373E
text primary     #E4E9ED
text secondary   #7D878F
text muted       #5C666E   set numbers
```

`ColorScheme.fromSeed` must be overridden with `copyWith` — seeding alone returns a washed-out tone-80 derivative, not these values.

One accent color, used only for Confirm. No color-coding of progress or performance. Minimum 56dp tap targets. Respect system text scaling.

## Conventions

- Business logic out of widgets. Queries in a repository layer, pure transforms in plain Dart.
- Prefer small diffs to large rewrites. Don't scaffold beyond what the task asks for.
- No `// ignore:` comments to quiet the analyzer.
- Comment sparingly. Don't restate the function name, and don't re-explain
  invariants — cite them (`// invariant 9`) rather than paraphrasing, or the
  spec ends up duplicated in docstrings and drifts.
  Comment only non-obvious *why*: constraint interactions, ordering that looks
  arbitrary but isn't, workarounds. Never comment *what* the code plainly does.
  Doc comments on public APIs: one line.

## Testing

**Do not write tests during implementation.** Testing is a dedicated milestone once the feature work is done — don't add test files, don't leave test TODOs, and don't scaffold test helpers "for later."

Delete the stock `test/widget_test.dart`; it targets the counter scaffold and will fail once `main.dart` is replaced.

Keep pure logic genuinely pure so it's testable when that milestone arrives: `logic/` must not import from `db/`, and its functions take plain Dart records rather than Drift rows.

## Milestone 1

One vertical slice. Nothing else.

- Drift schema and migration
- **No seed data.** Opening a day with no routine shows an empty state prompting for a name; submitting creates the routine with `default_weekday` set to that day and drops straight into the session.
- Home screen, minimal: today's card only — **Start {routine}** if today has no sets, summary if it does. No pager, no past cards, no *All sessions* link.
- `SessionScreen`: header shows routine and date
- Add an exercise to the session — creates it in `exercises` if new, and **always appends it to the routine**. M1 has no one-off path; routines start empty, so this is the only way to populate them. The permanence toggle lands in M2.
- The Add field autocompletes against existing exercise names. `NOCASE` catches `bench`/`Bench` but not near-misses like `Bench` vs `Bench Press`, and the per-exercise lookup depends on names staying canonical.
- Entry loop: weight pre-filled and carried forward, reps empty and required, Confirm writes one row immediately
- Card shows the single most recent prior session as its reference line, with its age
- Card collapses to notation via the collapse function
- Finish workout: clears the resume key, pops to home
- Resume: relaunching mid-workout returns to `SessionScreen` (see Active session and resume)
- Everything survives app restart

**Explicitly not in M1:** home pager and past cards, routine picker / Start other, exercise history screen, paginated history, routine settings editing, export, importer, charts.

## Roadmap after M1

2. Home pager with past session cards (capped at 10) and *All sessions* list; **Start other** routine picker; add-as-you-go toggle; cards show two prior sessions with paginated *show more history*
3. Exercise history screen (shares the repository method from invariant 5); routine and exercise rename/delete
4. Excel export — `Log` grid sheet + `Data` flat sheet
5. Legacy TSV importer (`docs/legacy-log.tsv`), with a review-and-confirm step. File structure is guaranteed: 5 columns; each week block is `Week N`, a blank row, a routine label row (`Shoulders / Legs / Back / Chest / Arms`), then exercise rows. **Column position maps to routine, never weekday.** File is CRLF — use `LineSplitter`. `Superset` appears on its own line as a marker, not an exercise — never create an exercise from it; optionally record the pairing in `superset_group`.
6. Charts on the exercise history screen
7. Test suite — pure logic first (collapse, week derivation, set renumbering), then repository tests against in-memory Drift