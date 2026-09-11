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
| D13 | Rate first: Istvan can rate photos Claude has not catalogued yet. | The app adds a minimal row for each such photo; the skill fills in the rest on its next run. |
| D14 | Istvan's judgement comes first and is never shaped by Claude. | The app hides Claude's rating, rationale and critique for a photo until Istvan has rated it (answers Q4). |
| D15 | Claude rates independently too, by its own standards, and is never shaped by Istvan's rating. | The skill rates blind: it forms and saves its rating before it looks at Istvan's. See "Critic partner". |
| D16 | Claude acts as a critic partner, not a yes-man. | Every photo Istvan rates 4 or 5 gets a written critique that argues or asks why, whether or not Claude agrees. See "Critic partner". |
| D17 | The critique is one-way. Istvan does not answer it, and nothing he does feeds back into Claude's rating. | He reads critiques to learn from them or to disagree privately. No reply field in the app, no revision of Claude's rating in response to Istvan (answers Q8). |
| D18 | Istvan's rating counts when the skill matches photos to competitions. | Only rating and critique are blind. Matching uses both ratings (answers Q10). See "Competition matching". |
| D19 | In v1 the app writes only Istvan's ratings (including the minimal rows from D13). | Status changes and competition results stay in the Claude chat (answers Q3). |
| D20 | The critique also covers the reverse case: photos Claude rates 4-5 that Istvan rated 1-2. | Claude says why it thinks he dismissed them too quickly (answers Q9). |
| D21 | Shoots starting with `SL35_` or `6X6_` are negative scans, made with the Canon EOS R8 and developed in DarkTable. The finished image is what gets judged. | Film is recognised by folder prefix, not EXIF. Scans are rated by the same standards as digital photos. |

## Critic partner (from D14-D17, D20)

Istvan wants the kind of critique a gallery or a jury gives, not an app that agrees with him.
Two independent opinions are only worth having if neither sees the other before forming its
own.

**Order of opinions for each photo:**

1. Istvan rates in the app. Claude's views on that photo stay hidden until he has.
2. Claude rates in a skill run without seeing Istvan's rating, and saves its rating and
   rationale.
3. Only then does Claude compare the two and write a critique.
4. The app reveals Claude's rating, rationale and critique next to Istvan's.

**Blind rating in the skill.** A model cannot unsee a number once it is in its context, and
with rate first (D13) most new photos will already carry Istvan's rating when Claude meets
them. So the skill must not open `catalogue.csv` directly before rating. Instead it runs a
small script that lists the photos needing a Claude rating *with the `istvan_rating` column
removed*, rates from contact sheets, saves `claude_rating` and `claude_rationale`, and only
then reads Istvan's ratings for the critique step.

**Claude's standards.** Claude rates against what a competition jury or gallery curator would
reward: impact, a distinctive moment or subject, composition, light, technical execution,
originality and story. A 5 is rare. The skill writes these criteria down so ratings stay
consistent between runs.

**Critique rules:**

- Every photo Istvan rates 4 or 5 gets a critique, including ones where Claude agrees. When
  Claude agrees, it still says what a jury could hold against the photo.
- When Claude rates lower, it argues with specifics (what in the frame weakens it) and asks
  what Istvan sees in it.
- Reverse case (D20): a photo Claude rates 4-5 and Istvan rates 1-2 also gets a critique,
  saying why Claude thinks it was dismissed too quickly.
- Claude separates "a photo that matters to you" from "a photo that is strong for a jury". A
  family photo can deserve a 5 from Istvan and a 2 from a jury, and both can be right.
- Claude's rating is set once, blind, and is not revised because of Istvan's rating (D17).
  Istvan's rating only decides which photos get a critique and what the critique addresses.
- Critiques are direct and respectful, like a good portfolio review: no flattery, no
  hedging. Because Istvan will not reply, a critique asks its question rhetorically and
  gives Claude's own answer ("What carries this frame? If it is the child's expression, the
  cluttered background works against it").
- If Istvan later changes his rating, the old critique stays but is marked with the rating it
  was written for. A photo newly raised to 4 or 5 gets a critique on the next run.

**Data:** new columns in `catalogue.csv`, written by the skill: `claude_critique` and
`critique_for_rating` (Istvan's rating at the time the critique was written, so the app can
show when a critique is out of date).

## Competition matching (from D18)

Blindness applies to forming opinions, not to deciding what to submit. Once both ratings
exist, the skill uses both:

- A photo is a candidate for a competition if either Istvan or Claude rated it 4 or 5.
- Every recommendation shows both ratings.
- When the ratings differ by 2 or more, the recommendation says so and names the risk, in
  the same spirit as the critique ("You rated 5, Claude 3: a jury is likely to see a pleasant
  family moment rather than a distinctive image").
- Istvan makes the final call on what to enter.

## Write rules for `catalogue.csv` (from D12)

Both the app and the skill write `catalogue.csv`. A skill run can take minutes and rewrites
the whole file, so without rules a rating given in the app during a run could be lost.

**The app:**

- Writes only the `istvan_rating` cell. It never changes any other column, removes or
  reorders columns, or reorders rows.
- Rate first (D13): for a photo with no row yet, adds one row at the end with `filename`,
  `source_folder`, `istvan_rating` and `status = available`, and every other column empty.
  An empty `claude_rating` tells the skill the photo still needs cataloguing.
- Saves each rating within about a second, not in a batch on quit.
- Before each save, re-reads the file from disk, finds the row by `source_folder` +
  `filename`, changes that one cell, and keeps everything else as it is (column order,
  unknown columns, quoting, CRLF line endings).
- Writes to a temporary file in the same folder, then renames it over `catalogue.csv`, so a
  reader never sees a half-written file.
- Keeps a backup copy before its first write each day, in the app's own Application Support
  folder rather than the library, so the skill never sees it.
- Keeps its own log of the ratings it wrote. If a later reload shows a rating reverted to the
  value it had before the app wrote it, the app restores it and tells Istvan. Safety net for
  the case where a skill run overwrote it anyway.

**The skill (change to `photo-competition-curator`):**

- Re-reads `catalogue.csv` immediately before writing, instead of writing back a copy read
  at the start of the run.
- For every existing row, takes `istvan_rating` from the file on disk, never from its own
  earlier copy.
- Fills in rows the app added (empty `claude_rating`) instead of adding duplicates, rating
  them blind as described under "Critic partner".
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
  `negative-scan`. A "film vs digital" filter would be wrong today. Resolved by D21: film is
  recognised by the `SL35_` and `6X6_` folder prefixes.
- **EXIF dates are unreliable.** The film scans all carry September 2026 scan dates, although
  their folders end in `202607` to `202609`. R8 photos show January to March 2026 while their
  folders end in `202606` to `202608`, so the R8 clock is off by months, not only the year.
  The folder's `YYYYMM` looks like the more reliable shoot month (to confirm, spec OI-6).
- **Folder prefixes do not mean one camera.** `6D_Vivas_pecs_202605` has 10 R8 photos and
  `R8_Rovinj_202606` has 30 6D photos. For digital shoots the camera must come from each
  photo's EXIF data.
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

**Q2. Can the app rate photos that are not in the catalogue yet?** *Resolved:* yes, rate
first (D13).

**Q3. Besides ratings, should the app edit anything else?** *Resolved:* no, not in v1 (D19).

**Q4. In review mode, hide Claude's rating until Istvan has rated?** *Resolved:* yes (D14).

**Q8. Can Istvan answer a critique in the app?** *Resolved:* no. The critique is one-way
(D17).

**Q9. Should the critique also cover the reverse case?** *Resolved:* yes (D20).

**Q10. Does Istvan's rating count when matching photos to competitions?** *Resolved:* yes
(D18).

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

Discovery is complete. The requirements are in
[requirements-spec.md](requirements-spec.md).

1. Review the requirements specification.
2. Write the design document (app architecture, CSV handling, file watching, thumbnails).
3. Update the `photo-competition-curator` skill to the requirements in the spec.
