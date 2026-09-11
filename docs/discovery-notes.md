# Show My Best: discovery notes

Running record of the product discussion. These notes feed the later requirements
specification and design document. Last updated: 2026-09-11.

## Context

The `photo-competition-curator` Claude skill already maintains, in
`~/Pictures/6x6Stories/REAL_BEST` on Istvan's Mac:

- `catalogue.csv`: one row per finished photo, with columns `filename`, `title`, `date_taken`,
  `camera_or_format`, `genre_tags`, `subject`, `istvan_rating`, `claude_rating`,
  `claude_rationale`, `competition_fit_notes`, `status`, `last_updated`, `source_folder`.
- `submissions.csv`: one row per competition entry, with columns `date_submitted`,
  `competition_name`, `entry_fee`, `deadline`, `photos_submitted`, `category`,
  `recommendation_call`, `result`, `notes`.
- `_contact_sheets/`: montage images the skill uses to review many photos at once.
- One subfolder per shoot, prefixed by camera or film (`R8_`, `6D_`, `SL35_`, ...).

Show My Best is a viewer and rating tool around that output.

## Decisions so far

| # | Decision | Notes |
|---|----------|-------|
| D1 | Native macOS app (SwiftUI). | Best feel on the Mac. No shared codebase with mobile. |
| D2 | Mobile is out of scope for v1. | |
| D3 | "Location" means a folder on disk, not a geographic place. | Point the app at REAL_BEST or a single shoot subfolder. |
| D4 | The app does not call Claude. No Agent SDK, no API, no network. | The skill runs separately in the Claude app. The CSV files are the only link between the two. |
| D5 | The skill creates all data files. | Catalogue rows, Claude ratings, competitions and submissions come from skill runs. |
| D6 | Istvan rates photos in the app, and the rating is saved so the skill can build on it. | The app writes Istvan's ratings; it never writes Claude's columns. |
| D7 | v1 includes a dedicated review/cull mode. | Full-screen, one photo at a time, keyboard-driven (1-5 to rate, arrows to move). |
| D8 | v1 shows gallery, photo detail, competitions and submissions. | Earlier "full wrap" choice, now read-only apart from ratings (see Q3). |
| D9 | The skill gets a persisted `competitions.csv`. | Today competition search results only live in the chat, so there is nothing for a Competitions view to read. Requires a skill change. |
| D10 | The app watches the folder and reloads when a skill run changes the files. | macOS FSEvents. |
| D11 | The app makes its own thumbnails. | It does not depend on `_contact_sheets/`. |
| D12 | Istvan's ratings are written into `catalogue.csv` (`istvan_rating` column). No separate ratings file. | Both the app and the skill write this file, so both follow the write rules below. |

## Write rules for `catalogue.csv` (from D12)

Both the app and the skill write `catalogue.csv`. A skill run can take minutes and rewrites
the whole file, so without rules a rating given in the app during a run could be lost.

**The app:**

- Writes only the `istvan_rating` cell. It never changes any other column, adds or removes
  columns, or reorders rows.
- Saves each rating within about a second, not in a batch on quit.
- Before each save, re-reads the file from disk, finds the row by `source_folder` +
  `filename`, changes that one cell, and keeps everything else as it is (column order,
  unknown columns, quoting, CRLF line endings).
- Writes to a temporary file in the same folder, then renames it over `catalogue.csv`, so a
  reader never sees a half-written file.
- Keeps a backup copy before its first write each day, in a folder starting with `_` so it is
  ignored by both the app and the skill.
- Keeps its own log of the ratings it wrote. If a later reload shows a rating reverted to the
  value it had before the app wrote it, the app restores it and tells Istvan. Safety net for
  the case where a skill run overwrote it anyway.

**The skill (change to `photo-competition-curator`):**

- Re-reads `catalogue.csv` immediately before writing, instead of writing back a copy read
  at the start of the run.
- For every existing row, takes `istvan_rating` from the file on disk, never from its own
  earlier copy.
- Writes to a temporary file and renames it, like the app.

A rating given in the few seconds between the skill's final re-read and its write can still
be lost. The app's log catches that case.

## Findings from the real data (2026-09-11)

Inspected `REAL_BEST` on Istvan's Mac.

- **Size:** 329 photos in 13 shoot folders (R8, 6D and SL35 prefixes). Every photo on disk
  has a catalogue row and every row has a photo, so disk and catalogue are in sync today.
- **File format:** standard comma-separated CSV, UTF-8 without BOM, CRLF line endings,
  double-quote quoting for fields containing commas, no line breaks inside fields. The `|`
  in the skill text is only how the columns are documented.
- **Photo identity:** 3 filenames appear in two shoots each (`IMG_2216.JPG`, `IMG_2346.JPG`,
  `IMG_0155.JPG`). `source_folder` + `filename` is unique, so that is the key (answers Q6).
- **Istvan's ratings:** `istvan_rating` is empty on all 329 rows. Rating in the app fills a
  real gap.
- **Claude's ratings:** 9 photos rated 5, 70 rated 4, 169 rated 3, 81 rated 2. A "best"
  view of 4-5 holds 79 photos.
- **Status:** all 329 are `available`. `submissions.csv` has a header and no entries yet.
- **`date_taken` is free text, not a date.** Examples: `2026:06:02 17:21:53 (camera clock
  correct)`, `2026 (year corrected from EXIF 2013 - 6D clock was badly wrong per Istvan; ...)`.
  The app cannot sort or filter by date reliably. Proposed skill change: split into a
  machine-readable date (ISO 8601, year-only allowed) and a separate `date_note`.
- **Film scans are labelled as digital.** The SL35 folders (88 photos) have
  `camera_or_format = Canon EOS R8`, the camera used to scan the negatives. The skill intends
  `negative-scan`. A "film vs digital" filter would be wrong today. Proposed skill change:
  label scans as film and keep the scanning camera separately if needed.
- **Competition matches are prose.** 60 rows have `competition_fit_notes`, with several
  competitions separated by ` | ` and deadlines written inside sentences ("closes 12 Oct
  2026"). The app can show the text but cannot sort by deadline or list competitions. This
  confirms D9 (`competitions.csv`).
- **Genre tags** are free-form but settle on about 25 values (documentary, family,
  landscape, portrait, street, wildlife, ...), which works for filter chips.
- **Working files the app should ignore:** `_meta.csv`, `_meta_new*.csv` (EXIF dumps with
  width, height and orientation) and `_contact_sheets/` (montages plus `ratings*.txt`).
  Rule: skip anything starting with `_` or `.`.
- **Image types:** 328 JPEGs (`.JPG` and `.jpg`) and 1 PNG.

## Open questions

**Q1. Where do Istvan's ratings get written?** *Resolved:* into `catalogue.csv` (D12).

**Q2. Can the app rate photos that are not in the catalogue yet?**
With D12, a photo in a new shoot folder has no row to put the rating in. Options: the app
shows uncatalogued photos but rating is disabled until Claude has catalogued the shoot; or
the app adds a minimal row (`filename`, `source_folder`, `istvan_rating`, `status =
available`) that the skill fills in on its next run. The second means the app also adds rows,
not just edits one cell.

**Q3. Besides ratings, should the app edit anything else?**
Candidates: a photo's `status` (for example `retired`), or a submission's `result`. Each one
adds another field the app writes.

**Q4. In review mode, hide Claude's rating until Istvan has rated?**
Seeing Claude's score first pulls Istvan's score toward it, which weakens the two-opinion
check the skill uses (it flags disagreements of more than 2 points).

**Q5. File format contract.**
Encoding and quoting are settled by the real files (standard CSV, see findings). Still to
agree: a machine-readable `date_taken`, film vs digital labelling, and a schema version.
Then update the skill to match.

**Q6. Photo identity.** *Resolved:* key is `source_folder` + `filename` (see findings).

**Q7. Competitions schema.**
Define `competitions.csv` columns (name, organizer, URL, fee, deadline, eligibility, theme,
prize, rights flags, "previously unpublished" rule, recommendation call, reasoning, matched
photos).

## Next steps

1. Answer Q2-Q4.
2. Agree the skill changes: write rules, `competitions.csv`, date format, film labelling.
3. Write the requirements specification.
4. Write the design document, including the data contract and the matching skill changes.
