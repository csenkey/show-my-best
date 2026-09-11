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
The skill documents columns with `|` separators but names the files `.csv`, and rationale
text contains commas. Agree on delimiter, quoting, encoding, date format and a schema
version, then update the skill to match.

**Q6. Photo identity.**
Filenames like `DSC_0421.jpg` can repeat across shoots, so rows should be keyed by
`source_folder` + `filename`. Confirm this against the real files.

**Q7. Competitions schema.**
Define `competitions.csv` columns (name, organizer, URL, fee, deadline, eligibility, theme,
prize, rights flags, "previously unpublished" rule, recommendation call, reasoning, matched
photos).

## Next steps

1. Answer Q1-Q4.
2. Inspect the real `catalogue.csv` and `submissions.csv` to settle Q5 and Q6.
3. Write the requirements specification.
4. Write the design document, including the data contract and the matching skill changes.
