---
name: photo-sales-curator
description: "Helps Istvan sell his finished photos: researches stock agencies, print-on-demand sites, fine-art galleries and limited-edition options live on the web, recommends which portals to join, picks which of his catalogued photos suit each one, writes portal-ready titles, descriptions and keywords, and tracks accounts, uploads, rejections and sales in CSV files his Show My Best app reads. Use this whenever Istvan asks about selling, licensing or monetising his photos, stock photography, microstock, prints, print-on-demand, limited editions, galleries, which portal to join, what to upload where, keywords or titles for stock, a rejected upload, or reports a sale or a new portal account — even if he doesn't name a portal."
---

# Photo sales curator

Istvan wants his photos to earn money, not only win competitions. This skill does the thinking behind that: where his work can sell, which photos to offer where, and the words each portal needs. His macOS app **Show My Best** does the hands-on part. It makes the upload-ready files, opens the portal's upload page, and records each upload as he goes. **Istvan uploads the files himself.**

The skill and the app never talk to each other directly. Three CSV files in the library folder are the whole interface: `portals.csv`, `listings.csv` and `sales.csv`. Read `reference/data-contract.md` before writing any of them.

This skill works alongside `photo-competition-curator`, which owns `catalogue.csv`, the competition files and the ratings. This skill reads those files and never writes them.

## 0. Locate the library

The library is `/Users/istvancsenkey-sinko/Pictures/6x6Stories/REAL_BEST`. Use it without asking, requesting folder access if it isn't connected yet. It holds `catalogue.csv` and one folder per shoot (`SL35_…`, `6X6_…` are film scans; `R8_…`, `6D_…`, `IPHONE…` are digital). Folders starting with `_` or `.` are never shoots.

If the folder has moved, or `catalogue.csv` isn't there, ask rather than guess.

## 1. Rules that must not be broken

- **Never create accounts, log in, upload, accept terms or handle passwords** on any portal, even when asked. Istvan does those himself. You research, recommend and write the files.
- **Never write `catalogue.csv`**, the competition files or `submissions.csv`. They belong to the other skill and the app.
- **Only photos Istvan has rated are proposed for sale.** The app hides listings for unrated photos, and your `reason` is an opinion he should only meet after forming his own.
- **Never propose a photo with a hold.** Get candidates from `scripts/sales-candidates.py`, which leaves held photos out. See §3.
- **The app writes `listings.csv` too.** It changes `status`, `prepared_on`, `uploaded_on`, `live_on` and `ended_on` as Istvan works. So:
  - re-read `listings.csv` immediately before every write, and apply your changes to that fresh copy;
  - never move a listing's `status` back to an earlier stage than the file shows (`suggested` → `prepared` → `uploaded` → `live`/`rejected` → `withdrawn`), unless Istvan says it is wrong;
  - never change those date columns except to record what he tells you.
- Write every file through a temporary file and a rename. Keep row order and any columns you don't know. Add new rows and columns at the end. Use RFC 4180, UTF-8 without a BOM, and CRLF.
- **No tax or legal advice.** Point him to the portal's own tax forms (US portals ask for a W-8BEN, for example) and contributor terms, and suggest a local accountant for anything beyond that.

## 2. Researching portals

Search live every time you research. Commissions, exclusivity terms, AI-training clauses and whether a portal still accepts new contributors all change. **Nothing below is a fact to write down without checking.** It is a list of what is worth checking.

What exists, broadly:

| Kind | Examples to evaluate | Suits |
|---|---|---|
| `stock` (microstock, non-exclusive) | Adobe Stock, Shutterstock, Alamy, Dreamstime, iStock/Getty | Volume: clean, useful, searchable photos. Low price per sale |
| `stock` (curated or exclusive) | Stocksy and similar collectives | Distinctive work. Application, exclusivity |
| `print-on-demand` | Fine Art America/Pixels, Saatchi Art prints, Society6, Etsy with a print partner | Strong single images people hang on a wall |
| `gallery` | Curated online galleries, local Hungarian galleries and photo fairs | The best work, often as editions |
| `own-shop` | His own site or shop | Editions and signed prints, full control, needs his own traffic |

For every portal you research, fill in what `portals.csv` asks for:

- commission as the portal states it;
- payout minimum and method, and whether it pays out to Hungary;
- exclusivity;
- file requirements (minimum megapixels, maximum size, keyword and title limits);
- whether it accepts film scans and editorial content;
- the terms flag (`ok`, `caution` or `rights-grab`);
- `last_checked`.

Two things deserve care:

- **Terms.** Read the contributor agreement for exclusivity traps, perpetual or irrevocable licences, and whether contributors' photos are licensed for AI training (and whether he can opt out). Flag them plainly in `terms_flag` and `terms_notes`.
- **Film scans.** About a third of his catalogue is film. Some stock reviewers reject grain, dust or scanner softness. Print buyers often value those qualities. Say what each portal's guidelines say, and put `unknown` when they say nothing.

**Recommend a small starting set**, each with `recommendation_call` (`join`, `later` or `skip`) and the reasoning. A sensible default to test against his actual work: one or two non-exclusive stock agencies to learn what sells, and one print outlet for his strongest images. Editions come later, once there is a body of work he rated 5. `reasoning` is about the portal, never about a specific photo.

When Istvan says he opened an account, applied or was turned down, update `account_status`.

## 3. Choosing photos

Run:

```
scripts/sales-candidates.py <library> [--min-rating 3] [--portal <portal_id>] [--show-held]
```

It lists photos Istvan has rated, with both ratings, medium, title, tags, subject, megapixels and existing listings. It leaves out photos with a hold:

- entered in a competition with no result yet;
- matched to a competition that is still open;
- uploaded or live on an exclusive portal.

With `--portal` it also leaves out photos already listed on that portal. `--show-held` lists the held photos with their reasons, for when he asks why a photo isn't offered.

Sellability is **not** competition strength. Judge each kind of listing on its own terms:

- **Stock** (`stock`/`editorial`): a clear subject a buyer would search for, clean technique at full size (sharp where it matters, no noise, dust or haloes), simple composition, room for text, and a recognisable place or concept. A 3-rated photo of a well-lit Budapest landmark can outsell a 5-rated moody abstract. Check the megapixels against the portal's minimum.
- **Prints** (`print`): photos someone would live with on a wall. Draw mainly from his 4s and 5s. The film work often belongs here.
- **Editions** (`edition`): only photos Istvan rated 5, or rated 4 when your rating is also 4 or 5. Small editions, and never reopened.

**An edition excludes open prints and stock of the same photo, and the reverse.** Cheap copies undercut numbered prints. The app enforces this as a hold. Don't propose a combination it would block.

**Releases.** Anything with recognisable people, private property, logos, trademarks or artworks is `editorial` unless Istvan confirms he has a release. Editorial goes only to portals with `editorial` = `yes`. Ask him when you can't tell from the photo.

Look at the photos themselves, not just the catalogue text. Build a contact sheet into `_contact_sheets/`, never into a folder without the underscore.

## 4. Writing listings

One row in `listings.csv` per photo per portal, with `status` = `suggested` and `suggested_on` = today. Leave the columns the app writes (`prepared_on`, `uploaded_on`, `live_on`, `ended_on`) empty.

- **Title:** plain and descriptive, in English, within `max_title_chars`. What and where: "Chain Bridge and Buda Castle at dusk, Budapest".
- **Description:** one or two sentences a buyer would search with: subject, place, time of day, mood. For editorial, follow the portal's own caption format, which you should look up rather than assume.
- **Keywords:** separated by `;`, most important first, within `max_keywords`. Aim for fewer, accurate keywords rather than padding. Cover subject, place (city, region, country), concepts, mood, season, colour or black-and-white, and orientation. **No trademarks, camera or film brand names, or anything not visible in the frame.**
- **Category:** the portal's own category name.
- **Prices** (prints and editions): reason openly from comparable work on that portal and the print size, and state it as a suggestion. Don't present a price as market fact. `edition_size` is a number, and `print_sizes` are separated by `;`.
- **Reason:** why this photo suits this portal, in one or two sentences. It is shown to Istvan in the app.

Show Istvan the proposed listings as a short table (portal, photo, type, title, keyword count, price if any) before writing them. Let him strike any.

## 5. The upload loop with the app

1. You write the `suggested` listings.
2. In Show My Best, under Sales ▸ Upload queue, he clicks **Prepare files**. The app writes sRGB JPEGs with the title, description and keywords embedded into `~/Pictures/Show My Best Exports/<portal_id>/`, plus a `metadata.csv`, and marks them `prepared`.
3. He uploads them on the portal, then clicks **Mark uploaded**.
4. When the portal reviews them, he marks each listing **Live** or **Rejected** in the app, or tells you.

When he tells you about an outcome:

- **Accepted:** set `status` = `live` and `live_on`, and record `portal_ref` (the item's ID or link) if he gives it.
- **Rejected:** set `status` = `rejected`, `ended_on`, and put the portal's stated reason in `notes`. **Learn from it.** If a portal rejects film grain, or keyword spam, or "limited commercial value", adjust what you propose there next. If a rejected listing can be fixed (better keywords, a release, a different type), say so, and when he puts it back in the queue from the app, revise that row.

## 6. Sales

Log a sale in `sales.csv` only when Istvan reports it:

- `date`, `portal_id`, the photo (`source_folder` and `filename`), `listing_type`;
- `edition_number` for editions;
- `amount` as he earned it (after the portal's cut), in the currency he was paid, as a number;
- `notes` for the licence type or print size.

Before logging an edition sale, check that the edition isn't already sold out.

When he asks how it's going, summarise from `sales.csv`: sales by portal, per currency, and which kinds of photos sell. Use that to steer the next round of listings.

## 7. What a session should leave him with

- `portals.csv` refreshed for every portal you researched, with calls and reasoning.
- New `suggested` listings he agreed to, with titles, descriptions and keywords within each portal's limits.
- Status, account and sales updates he reported.
- A short plain-language summary: what to do next in the app (for example "Sales ▸ Upload queue ▸ Adobe Stock ▸ Prepare 12 files"), and anything waiting on him, such as opening an account, confirming a release or answering a question about a photo.

## 8. When something is unclear

If you can't tell whether a photo needs a release, or whether a portal's terms allow something, or which shoot a filename belongs to, or whether a sale was of an edition: ask. Never guess, and never fill a gap with an assumed fact about a portal.
