# M5 — Legacy TSV importer

Notes for the one-time backfill of `docs/legacy-log.tsv`. Not loaded during other milestones.

All counts below were measured against the committed file, not estimated.

## Source shape

31 week blocks, 302 rows, 5 columns, CRLF throughout (use `LineSplitter`).

Each block:

```
Week N
                                    <- blank row
Shoulders  Legs  Back  Chest  Arms  <- routine label row
<exercise cells...>
```

The label row is at a consistent offset of 2 from `Week N`, but scan forward for the first all-labels row rather than hardcoding it.

**Column position maps to routine, never weekday.** The original sheet used weekday columns and the routine drifted between them; the file has been restructured so column index is authoritative.

551 non-empty exercise cells total.

## Notation

```
Bench @45 12345-8              five sets of 8 at 45
Incline @45 12-8 345-6         sets 1–2 for 8, sets 3–5 for 6
Tricep M 1@120-18 2345@130-10  weight changes mid-exercise
Leg curl 1@90-4 234@80-7       failed at 90, dropped to 80
Curl M @41kg 1234-10           unit suffix
```

Digit runs are **set numbers**, not counts. `12345-8` is five sets, not twelve thousand.

**Longest digit run in the file is 6.** No run reaches 7+, so the parser never has to disambiguate a tenth set (`...910`). Don't build for it.

## Edge cases, with counts

| Case | Count | Handling |
|---|---|---|
| `Superset` marker lines | 60 | Not an exercise. Never create an exercise named "Superset". Optionally record the pairing in `superset_group`. |
| Cells with `@ 45` spacing | 4 | Normalize — strip whitespace after `@`. |
| `kg` suffix | 13 | Strip the suffix, store the bare number. See below. |
| Has `@` but no reps (`Low Row @90`) | 13 | **Cannot be stored** — `weight`/`reps` are NOT NULL. Skip and report. |
| Trailing dash (`34@30-`) | 1 | Truncated mid-entry. Skip the incomplete run, keep the complete ones. |
| Missing `@` entirely | 2 | `Decline bench 45 12-10 34-9`, `Shrug 12345-15`. First is a dropped `@`; second has no weight at all and can't be stored. |

These gaps are Google Drive sync failures, not intentional logging. Skipping them is correct — do not invent values.

## The kg question, resolved

Only two exercise names carry `kg`: `Curl M` (12 cells) and `Curl Machine` (1 cell). **Neither ever appears without the suffix**, so stripping it is safe — the scale is internally consistent per exercise, and weight is only ever compared to itself (invariant 12).

Note those two names are the same machine. The importer should map them to one canonical exercise, or you get two histories for one lift.

## Name normalization

Exercise names drift in the source (`Rear delt` / `Reat Delt`, `Lat Raise M` / `Lateral Raise Machine`). `NOCASE UNIQUE` catches case differences only. The review-and-confirm step should surface near-duplicate names for manual merge before committing anything.

**Never merge across machines.** `Lat pulldown`, `Plate Lat pulldown`, and `Pulldown M` are different machines with incompatible scales.

## Free text

Zero cells contain no digits — earlier notes claimed "Tired day, feeling off" existed as a free-text cell; it does not appear in the restructured file. If any narrative text is added later it belongs in `sessions.note`, never as an exercise.

## Dates — the unsolved problem

**The source has no dates.** It has week numbers and routine columns. Sessions require a real date (invariant 7), so the importer must synthesize one.

Needs a decision before implementation. Options:

- Ask for a start date (the Monday of Week 1), then assign each session `start + (week-1)*7 + routine_default_weekday`. Reconstructs a plausible calendar; the specific days will be wrong wherever the actual workout moved.
- Ask for a start date and assign every session in a week to sequential days regardless of routine.
- Import with dates as an explicit approximation and flag it in the UI.

The dates don't affect history lookup (per-exercise, ordered by date) or week derivation (relative to earliest session). They only matter for display honesty.

## Mechanics

- Session date is a parameter, never `DateTime.now()` (invariant 6)
- One batched transaction, not per-set inserts (invariant 13)
- Week numbers are derived from the earliest session — importing history renumbers everything automatically (invariant 8)
- Creates routines and exercises as encountered; the app ships with none
- Review-and-confirm step lists: skipped cells with reasons, near-duplicate names, and the date assumption — before anything is written