# Workout Tracker

A logbook, not a fitness app.

It does one thing: tell you what you lifted last time, and record what you lift today. It has no timers, no streaks, no badges, no notifications, and no opinion about whether you trained hard enough.

> **Status:** design complete, implementation in progress. This README describes the intended v1.

---

## Why

I tracked my training in a spreadsheet for thirty-one weeks. Every workout app I tried asked me to do more work than the spreadsheet did — define units, pick a program, start a timer, close out a session, dismiss a notification about my streak.

The spreadsheet won because it did exactly one useful thing well: I could glance at last week's cell and know what to load.

So this app is a port of the spreadsheet, not a replacement for it. The design brief was: **keep everything the sheet got right, fix only the things it got wrong.**

**What the sheet got right**

- One glance gives you last week's numbers
- Zero setup, zero ceremony, no concept of a "finished" workout
- Notation dense enough to read a whole exercise in one line
- Numbers mean whatever I want them to mean

**What the sheet got wrong**

- Google Drive sync failures silently lost entries
- The numbers are trapped inside text — nothing is chartable
- Exercise names drift (`Rear delt`, `Reat Delt`, `rear delt`) and break history lookup
- Finding one lift's history means scrolling thirty-one week-blocks

---

## The notation

The app reads and writes the shorthand I already used. A digit run is a list of *set numbers*:

```
Bench @45 12345-8              five sets of 8 at 45
Incline @45 12-8 345-6         sets 1–2 for 8 reps, sets 3–5 for 6
Tricep M 1@120-18 2345@130-10  weight changes mid-exercise
Leg curl 1@90-4 234@80-7       failed at 90, dropped to 80
Curl M @41kg 1234-10           units only when they'd surprise you
```

Sets are stored as individual rows and *rendered* back into this notation. That's the whole trick: the database stays clean and chartable, the display stays dense and readable.

---

## Core concepts

**Exercises** are canonical. One row per movement, so renaming `Reat Delt` fixes every session retroactively.

**Routines** are permanent templates — mine are Shoulders, Legs, Back, Chest, Arms, but the app ships with none. Each holds an ordered list of exercises, and a *default weekday* that only controls what the app opens on.

**Sessions** are one actual training day: a date plus whichever routine you picked. Don't feel like chest on Thursday? Pick Arms. It logs as Arms, on Thursday's real date.

Routines and weekdays are separate on purpose. See [Design decisions](#design-decisions).

---

## How logging works

A **set is an atomic (weight, reps) pair.** You confirm one, then the next.

```
Bench
@45 12345-8 · 7 days ago
@45 1234-8 · 14 days ago
                              show more history

weight [ 45 ]    reps [    ]     [ Confirm ]
```

- **Weight pre-fills** from your last set and carries forward. You only touch it when you change the load.
- **Reps start empty** and must be entered. You can't confirm a set you didn't do.
- **Confirmed sets write immediately.** There is no save button and no draft state.
- **You stop when you stop.** Four sets instead of five isn't an event — it's just four rows.

Nothing reaches the database that you didn't deliberately confirm.

**History shows two prior sessions**, each with its age, and *show more* pulls one further back per tap. Two lines instead of one because a single line lies when the last session was an outlier — a deload week reads as your working weight until you see the one before it.

**Reading the session** — a card showing numbers is done; a card showing an age hasn't been started. No checkmarks, no progress bar.

**Adding mid-session** is one tap. It's a one-off by default; a toggle adds it to the routine permanently.

**Finishing** is a button that collapses the session and returns you to the list. It records nothing — every set was already saved. It exists because ending a workout deliberately feels better than just closing the app.

---

## Screens

Four, plus an export button.

| Screen | Purpose |
|---|---|
| **Session** | Today's routine. Where you spend all your time. |
| **Session list** | Reverse chronological. Tap to open any past session *in the same editor*. |
| **Exercise history** | One lift, newest first. The "scroll back through the sheet" move, filtered. |
| **Routine settings** | Edit templates: exercises and order. |

---

## Export

One workbook, two sheets:

- **`Log`** — the original grid. Week rows, routine columns, collapsed notation in each cell.
- **`Data`** — flat, one row per set: `date, week, routine, exercise, set_number, weight, reps`.

The grid keeps the format I've read for thirty-one weeks. The flat sheet is what makes charts possible — drop a pivot on it and you have bench weight over time in four clicks.

Export is also the backup story. See [Known limitations](#known-limitations).

---

## Design decisions

Every non-obvious decision traces to something in thirty-one weeks of real data.

**Routines are decoupled from weekdays.**
In Week 3 I did chest on Friday and arms on Saturday. In Week 25, chest landed on Wednesday. The spreadsheet's columns weren't days — they were routines wearing a day's name. Separating them makes swapping a non-event.

**Sessions pre-fill from the routine template, never from the last session.**
Week 16's Monday has three exercises where Week 15's had five. If each session copied the previous one, a single short workout would truncate the routine permanently and silently.

**History is a per-exercise lookup, never filtered by routine or weekday.**
Decline bench ran Weeks 2–7, disappeared for roughly seventeen weeks, and came back in Week 25. Any lookup keyed to "last session" returns nothing there. And I sometimes repeat a lift on a Saturday — that session belongs in its history like any other.

**Ad-hoc exercises are one-offs by default.**
Calf Machine appears exactly once in thirty-one weeks. Dip Machine appeared in Week 5 and stayed for months. Auto-adding everything would have quietly filled the Legs routine with three leg-press variants I tried once.

**A set is an atomic (weight, reps) pair.**
`Leg curl 1@90-4 234@80-7` — weight changes mid-exercise constantly. Treating weight as an exercise-level field would make the common real case an exception.

**Weight is an opaque number, meaningful only within one exercise.**
`@45` on bench means 45 lb plates per side. `@150` is a machine stack. `@41kg` is a machine labelled in kilos. There is no conversion and no cross-exercise math, because there is no correct answer.

**Completion is derived, not stored.**
A session is complete if it has sets and isn't today's. A stored flag would have to be maintained — what happens when you edit a finished workout, or never tap Finish? Every answer to that leads back toward prompts and nagging.

**No seed data.**
The app ships with nothing. Opening a day with no routine asks for a name once. Seeded routines would bake my split into everyone's install, and editing the seed after first run silently does nothing — a confusing footgun for no benefit.

**Everything writes immediately, locally.**
The gaps in my spreadsheet aren't sloppy logging — they're Google Drive sync failures. Data loss is the specific problem this app exists to solve.

---

## What this deliberately does not do

This list is a feature. Every item was considered and rejected.

- **No rest timers**
- **No streaks, reminders, badges, or notifications**
- **No 1RM estimates, volume totals, or tonnage** — weights aren't comparable across exercises, so these numbers would be meaningless
- **No body weight or measurement tracking**
- **No unit conversion or unit selection**
- **No stored completion state**, and no prompting about unfinished sessions
- **No superset pairing** — paired lifts are just consecutive exercises
- **No "you've done this 3 times, add it to your routine?" nudges**
- **No account, no server, no sync**
- **No in-app charts in v1** — planned for a later phase, pull-only, attached to exercise history

---

## Data model

SQLite via [Drift](https://drift.simonbinder.eu/). Six tables.

```
exercises          id, name UNIQUE COLLATE NOCASE
routines           id, name, default_weekday, position
routine_exercises  id, routine_id, exercise_id, position, superset_group
                   → the template
sessions           id, date, routine_id, note, created_at
                   UNIQUE (date, routine_id)
session_exercises  id, session_id, exercise_id, position, superset_group
                   → what actually happened
set_entries        id, session_exercise_id, set_number,
                   weight NOT NULL, reps NOT NULL, created_at
```

The constraints carry the rules:

- **`weight`/`reps` NOT NULL** — a partial set is unrepresentable
- **`UNIQUE (date, routine_id)`** — reopening Thursday-Chest finds your session; Thursday-Arms starts a new one
- **`NOCASE`** on exercise names — stops `Rear delt` and `rear delt` becoming two lifts
- **`ON DELETE RESTRICT`** on exercises — history can never be orphaned

**Deliberately absent:** no `is_complete`, no draft state, no weights in templates, no units column, no stored volume or 1RM, no `week_number`. Week numbers derive from the earliest session, so importing history renumbers everything automatically.

`superset_group` is unused — it exists so the legacy importer can preserve `Superset` markers from the spreadsheet, in case the feature is ever wanted.

The session screen is a **merge**, not a table read: cards come from `routine_exercises`, any with `session_exercises` rows for today show today's numbers, and ad-hoc additions appear with no template row.

---

## Stack

- **Flutter** — Android and iOS
- **Drift / SQLite** — local-only persistence, reactive queries
- **Excel export** — two-sheet workbook via the share sheet

---

## Roadmap

**v1 — core logbook**
Session logging with per-exercise history, add-as-you-go, routine picker, session list, exercise history, Excel export.

**v2 — spreadsheet importer**
Parses thirty-one weeks of legacy TSV notation and backfills every routine, exercise, and set. Needs a review-and-confirm step, since the source notation has real drift in it. Three hooks are already in place for this: session date is always a parameter rather than `DateTime.now()`, week numbers derive from the earliest session, and writes go through a batched transaction.

**v3 — charts**
Attached to exercise history, never a dashboard. One dot per set, x = date, y = weight, reps as the tap label — because plotting weight alone would show Bench as a flat line for thirty-one weeks while the reps climbed 8 → 15. No trendlines, no projections, no PR badges.

---

## Known limitations

**Local-only means losing the phone loses the data.** The Excel export is the backup, and it is manual by design — reminders are on the anti-scope list. That's a tradeoff I'm accepting, not a solved problem.

**Never merge exercises across machines.** `Lat pulldown`, `Plate Lat pulldown`, and `Pulldown M` are three machines with incompatible scales. Renaming is retroactive and safe for typos; merging them would invent a progression cliff that never happened.