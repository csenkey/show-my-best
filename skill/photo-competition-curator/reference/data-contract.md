# The files the skill and Show My Best share

These four CSVs in the library folder are the only interface between this skill
and the Show My Best app. Both sides must follow this exactly; it is §6 of
`docs/requirements-spec.md` in the show-my-best repo, and that document wins if
the two ever disagree.

## Rules for every file

| | |
|---|---|
| Format | RFC 4180 CSV: one header row; a field holding a comma, double quote or line break is wrapped in double quotes; a double quote inside a field is written twice |
| Encoding | UTF-8, no byte order mark. Hungarian characters must survive a read and write unchanged |
| Line endings | CRLF. Readers also accept LF, but write CRLF |
| Columns | Found **by header name**, never by position. New columns are added at the end |
| Unknown columns | Every writer keeps columns it does not recognise, with their values |
| Dates | ISO 8601: `YYYY-MM-DD`, `YYYY-MM-DDTHH:MM:SS` (local, no zone), `YYYY-MM` or `YYYY` |
| Photo references | `source_folder/filename`, e.g. `R8_Rovinj_202606/IMG_0412.JPG`. Lists are joined with `;` and no spaces |
| Empty field | Means unknown or not set |
| Writing | Write a temporary file, then rename over the target, so no reader sees half a file |

## `catalogue.csv`

One row per photo; `source_folder` + `filename` is unique.

| Column | Content | Written by |
|---|---|---|
| `filename` | Filename exactly as on disk | Skill; the app for rows it adds |
| `source_folder` | Shoot folder name | Skill; the app for rows it adds |
| `title` | Short descriptive title | Skill |
| `date_taken` | When the photo was taken. For film: when the film was exposed, not when it was scanned | Skill |
| `date_note` | Free text about the date, e.g. `EXIF date 2013-03-06 01:48:16; 6D clock was wrong` | Skill |
| `medium` | `digital` or `film` | Skill |
| `camera_or_format` | Digital: the EXIF camera model. Film: `SL35 negative scan` or `6x6 negative scan` | Skill |
| `genre_tags` | Tags separated by `, ` | Skill |
| `subject` | Short description of what is in the photo | Skill |
| `istvan_rating` | `1`–`5` or empty | **The app only. Never write this column** |
| `claude_rating` | `1`–`5`, empty until rated | Skill |
| `claude_rationale` | One sentence explaining the rating | Skill |
| `claude_critique` | 2–4 sentences, at most 600 characters | Skill |
| `critique_for_rating` | Istvan's rating at the moment the critique was written | Skill |
| `competition_fit_notes` | Readable summary of the photo's matches | Skill |
| `status` | `available`, `submitted`, `published` or `retired` | Skill; the app writes `available` on rows it adds |
| `last_updated` | `YYYY-MM-DD` the skill last changed the row | Skill |

## `competitions.csv`

One row per competition researched. Judgements about *photos* never go here —
they go in `competition_matches.csv`, so the app can hide them for photos
Istvan has not rated yet.

`competition_id` (lowercase words and digits joined by hyphens, e.g.
`cewe-photo-award-2026-27`, unique) · `name` · `organizer` · `url` ·
`categories` (joined with `;`) · `opens` · `deadline` (`YYYY-MM-DD`) ·
`deadline_note` · `entry_fee` (as the organizer states it) · `fee_amount`
(number, `0` when free) · `fee_currency` (ISO 4217, empty when free) · `tier`
(`local`/`national`/`international`) · `eligibility` · `capture_date_rule` ·
`previously_unpublished` (`yes`/`no`/`unknown`) · `prize` · `rights_flag`
(`ok`/`caution`/`rights-grab`) · `rights_notes` · `recommendation_call`
(`enter`/`skip`/`worth-it-regardless`) · `reasoning` · `last_checked`

Required: `competition_id`, `name`, `url`, `deadline`, `rights_flag`,
`recommendation_call`, `last_checked`.

## `competition_matches.csv`

One row per photo matched to a competition; `competition_id` +
`source_folder` + `filename` is unique.

`competition_id` · `source_folder` · `filename` · `category` · `role`
(`primary`/`alternate`) · `reason` · `matched_on`

The `reason` names both ratings, and when they differ by 2 or more it says so
and what the risk is.

## `submissions.csv`

One row per entry Istvan confirmed he made.

`date_submitted` · `competition_id` (empty if the competition is not in
`competitions.csv`) · `competition_name` · `entry_fee` · `deadline` ·
`photos_submitted` (references joined with `;`) · `category` ·
`recommendation_call` · `result` (`pending`/`won`/`placed`/`no-award`) ·
`notes`
