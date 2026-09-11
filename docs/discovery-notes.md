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

**Q1. Where do Istvan's ratings get written?**
The app and a skill run would both write data. A skill run can take minutes: if it reads
`catalogue.csv` at the start and rewrites the whole file at the end, ratings made in the app
in between are lost. Options:

- *A. Write straight into `catalogue.csv` (`istvan_rating` column).* The app re-reads the
  file just before saving, changes only that cell, and replaces the file atomically. The skill
  must re-read the file before writing and keep `istvan_rating` untouched. Simple to read, but
  protection against lost ratings depends on the skill following its instructions.
- *B. Write to a separate `ratings.csv` that only the app writes* (`source_folder`,
  `filename`, `istvan_rating`, `rated_at`). The skill reads it and copies ratings into the
  catalogue. Each file has exactly one writer, so nothing can be overwritten. It also allows
  rating a fresh shoot *before* Claude has catalogued it, which matches the natural workflow
  of culling first and asking Claude second.

**Q2. Can the app rate photos that are not in the catalogue yet?**
Follows from Q1: easy with B, needs the app to add partial catalogue rows with A.

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

1. Answer Q1-Q4.
2. Agree the skill changes: `competitions.csv`, date format, film labelling.
3. Write the requirements specification.
4. Write the design document, including the data contract and the matching skill changes.
