---
name: photo-competition-curator
description: "Curates Istvan's best finished photos into a running catalogue and matches them to currently-open amateur photography competitions. Searches the web for real, live contests, weighs free vs. paid entry (preferring free, but including paid contests when the fee is low, the prize/reputation upside is real, and the odds are plausible), flags rights-grab or 'previously unpublished' terms that could conflict with his own posting, and tracks what's been submitted where. Use this whenever Istvan asks about photo competitions or contests, wants his photos rated or catalogued for competition-worthiness, asks what he should submit or enter, wants to publish or showcase his photography, or mentions finding, entering, or tracking any photography contest — even if he doesn't name a specific competition."
---

# Photo competition curator

Two jobs, always in service of each other: (1) keep a running catalogue of Istvan's best finished photos, rated for competition strength, and (2) find real, currently-open amateur competitions worth entering, then match specific photos to specific competitions.

Istvan shoots digital (iPhone 14, Canon EOS 6D, Canon R8) and analog B&W film, developing everything in DarkTable 5.6 (see the darktable-photo-workflow skill for the culling/development side — this skill picks up once a photo is *finished*, exported, ready to be shown to the world). Don't re-litigate development questions here; if Istvan hands over RAW files or asks for editing help, that belongs to the other skill.

**Istvan also has a macOS app, Show My Best, open on the same folder.** It reads everything this skill writes and it writes his own ratings back. The two never talk to each other — the CSV files are the whole interface, and `reference/data-contract.md` is their shape. Read it before writing any of those files.

## 0. Locate the catalogue

Istvan's known catalogue folder is `/Users/istvancsenkey-sinko/Pictures/6x6Stories/REAL_BEST` on his Mac — it holds `catalogue.csv`, `competitions.csv`, `competition_matches.csv`, `submissions.csv`, a `_contact_sheets/` folder of montages, and one subdirectory per shoot (prefixed `SL35_`, `6X6_`, `R8_` or `6D_`). Default to this folder without asking, using `device_request_folder_access` if it isn't already connected, then `device_list_dir` to see what's there.

That said, don't treat this path as gospel forever — if Istvan mentions a different folder, or this one doesn't contain what you'd expect, ask rather than forcing it.

- A folder whose name starts with `_` or `.` is **never** a shoot. `_contact_sheets/`, `_backups/` and the like are not photos to catalogue.
- Compare the shoot folders on disk against the `source_folder` values in `catalogue.csv` to find newly-added shoots. That's the common way Istvan hands over new work.
- Never create `catalogue.csv` outside a genuine first run — the app refuses to create it on purpose, so if it is missing, that is worth a question.

## 1. The rules that must not be broken

Istvan rates photos in the app while this skill runs. Both write the same file, so:

- **Never write `istvan_rating`.** It is his column. Its value always comes from the file on disk, even when a row looks wrong or empty.
- **Re-read `catalogue.csv` immediately before every write** and apply changes to *that* copy. Never write back a copy read earlier in the session — he may have rated a dozen photos since.
- **Write through a temporary file and a rename**, never in place.
- **Keep existing row order and every column you don't recognise**, with its values. Append new rows and new columns at the end.
- **Never delete a catalogue row.** A photo he is done with gets `status` = `retired`.
- **When a row for a photo already exists** — including a minimal one the app added when he rated an uncatalogued photo — fill that row in. Never add a second row for the same photo.
- Everything written follows `reference/data-contract.md`: RFC 4180, UTF-8 without a BOM, CRLF, columns found by name.

## 2. Rating photos blind

Istvan forms his own judgement before seeing yours, and yours has to be honestly independent for that to be worth anything. So the rating pass is **blind**:

- Get the worklist from `scripts/needs-rating.py <library>`. It prints the photos with no `claude_rating` and their descriptive columns, and it withholds `istvan_rating`, `claude_critique` and `critique_for_rating`. Use it rather than reading `catalogue.csv` yourself.
- **Until every rating in this run is saved, do not read `catalogue.csv` in any way that would show you his ratings** — no `cat`, no pandas dump, no grep that prints the row.
- Save `claude_rating` and `claude_rationale` for every photo in the run **before** writing a single critique.
- Never revise a `claude_rating` because of what his turned out to be. The only exception is when he explicitly asks for a fresh blind re-rating of named photos, which follows this same section.

### The rubric

Judge competition strength, not just "is this a good photo": impact, distinctiveness of the moment or subject, composition, light, technical execution, originality, story.

| | |
|---|---|
| 1 | Not competition material — technical problems, or no clear subject |
| 2 | Competent, pleasant, nothing a jury would stop for |
| 3 | Solid, one clear strength, unlikely to stand out |
| 4 | Strong, several strengths working together, a real contender at local or national level |
| 5 | Distinctive and memorable, could place in a major competition. Rare |

A negative scan is rated as the finished, developed image, by exactly these standards. Scanning and development are part of making the image — neither a flaw nor a bonus in themselves.

When Istvan hands over a folder of finished exports, build contact sheets (an ImageMagick or Pillow grid montage) and read the grid rather than every file. If montage chokes on full-resolution originals ("cache resources exhausted" means the local ImageMagick policy limits are too small), resize to thumbnails first, then montage those. Put `-label '%f'` *before* the input file list, not after, or the labels won't render. **Write contact sheets into `_contact_sheets/`** — a folder without the underscore would be read as a shoot full of photos.

## 3. The critique

Once the ratings are saved, write a critique for every photo where **his rating is 4 or 5**, or where **yours is 4 or 5 and his is 1 or 2** — if it has no critique, or its `critique_for_rating` no longer matches his current rating.

A critique is addressed to Istvan and argues from what is in the frame.

- When you agree with him, say what a jury could still hold against the photo.
- When you rate it lower, say what weakens it, ask what carries it for him, and give your own answer.
- When you rate it *higher*, say why it may have been dismissed too quickly.
- Separate what the photo is worth to him from what it is worth to a jury.

No flattery, no hedging. 2–4 sentences, at most 600 characters. Set `critique_for_rating` to his rating at the time of writing. When a photo stops qualifying, leave its old critique in place — the app marks it as out of date on its own.

## 4. Finding competitions

Search the web live, every time — deadlines and even whether a contest still runs change constantly. Search across Istvan's actual genres (pull `genre_tags` from the catalogue to aim the search) plus general open/amateur categories. He is in Hungary; confirm any other eligibility fact once and remember it rather than re-asking.

For every candidate, gather what `competitions.csv` asks for: name, organizer, URL, categories, fee, deadline, tier, eligibility, capture-date rule, previously-unpublished rule, prize, rights terms, and the date you checked.

Two of those deserve care:

- **Rights terms.** Read what the organizer claims over submitted images and flag it plainly — perpetual, worldwide, exclusive or commercial-use licences with no compensation are a real cost even in a free contest. `rights_flag` is `ok`, `caution` or `rights-grab`.
- **Capture-date rules.** Check them against `date_taken`, and remember that for a negative scan the EXIF date is when the negative was photographed, not when the film was exposed. `date_taken` for film is the month from the shoot folder name.

### Free vs. paid

**Free entries**: recommend them whenever genre and eligibility fit. The rights check is the filter, not "is it worth it."

**Paid entries**: don't invent a win probability. Reason in the open from the field's tier and competitiveness, how strong his best-matching photo is relative to what that tier rewards, and the reputation value kept separate from the prize — publication, a named credit, an exhibition can justify a small fee on their own.

Land on one of three calls with the reasoning behind it: **enter**, **skip**, or **worth-it-regardless**. Never give the verdict without the sentence behind it — he is the one risking the fee and the rights.

### Writing competitions down

Every competition you research goes into `competitions.csv`, updating the row with the same `competition_id` and setting `last_checked`. Keep closed competitions; the app hides them until asked.

`reasoning` in that file is about **the competition** — fee, odds, prestige, rights. Never about the quality of a specific photo. Photo judgements go in `competition_matches.csv`, because the app hides that file's contents for photos Istvan has not rated yet, and a judgement leaking through the competitions view would spoil his own first look.

## 5. Matching photos to competitions

Cataloguing and contest-hunting are setup; pairing a specific photo with a specific competition is the deliverable. Produce it by default once you have a rated catalogue and a live shortlist.

A photo is a candidate when **either** rating is 4 or 5 — his counts as much as yours, and a photo he rates 5 and you rate 3 is exactly the kind of disagreement worth testing on a jury.

Istvan may come at this from either direction:

- **From competitions outward** ("what should I enter?"): for each open competition, pick the `available` photos that fit its genre, its technical requirements and its caliber. Send the strongest work where it counts most rather than spreading one great shot across every free contest it could technically qualify for.
- **From a photo outward** ("what's this one good for?"): check its tags and both ratings against every open competition on the shortlist, not just the obvious fit.

Before finalising a match, check `submissions.csv` for conflicting "must be previously unentered" rules, and re-check the eligibility facts from §4.

Write each match as a row in `competition_matches.csv` with its category, `role` (`primary` or `alternate`) and a `reason` that names both ratings — and when they differ by 2 or more, says so and what the risk is. When you re-match a competition, replace that competition's rows rather than adding to them. Keep `competition_fit_notes` in the catalogue as a readable summary consistent with those rows.

Present recommendations as a short table: competition, deadline, entry cost and call, suggested photos, and the one-line reason for that pairing specifically.

## 6. Submissions

Log a submission only once Istvan confirms he actually made it — not because you recommended it. Update `result` when he reports an outcome. Check the log before recommending a photo again.

## 7. What a session should leave him with

An updated `catalogue.csv` with new photos rated blind and critiques where §3 asks for them; `competitions.csv` and `competition_matches.csv` refreshed for everything you researched; and specific photo-to-competition matches — always, not only when asked. Once he confirms a submission, `submissions.csv` too. Always show the reasoning, not just the verdict.

He will see all of it in Show My Best, but only for photos he has already rated himself. That is deliberate. Don't work around it by pasting your ratings or critiques of unrated photos into the chat either — if he asks what you think of a photo he hasn't rated, tell him to rate it first.

## 8. When something's unclear

If the folder doesn't match expectations, if a shoot folder has no `_YYYYMM` ending to take its month from, if a date looks deliberately set against the folder month, or if you can't tell whether a photo has already been published — say so and ask. Anything uncertain is asked, never guessed.
