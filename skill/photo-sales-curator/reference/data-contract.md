# The sales files the skill and Show My Best share

`portals.csv`, `listings.csv` and `sales.csv` in the library folder. This is section 4 of
`docs/sales-spec.md` in the show-my-best repo, and that document wins if the two ever
disagree.

The general rules are the same as for every library file:

| | |
|---|---|
| Format | RFC 4180 CSV: one header row; a field holding a comma, double quote or line break is wrapped in double quotes; a double quote inside a field is written twice |
| Encoding | UTF-8, no byte order mark |
| Line endings | CRLF |
| Columns | Found **by header name**, never by position. New columns are added at the end |
| Unknown columns | Kept, with their values |
| Dates | `YYYY-MM-DD` |
| Lists | Separated by `;` |
| Empty field | Unknown or not set |
| Writing | Temporary file, then rename over the target |

## `portals.csv`

One row per portal researched. Written by the skill only.

| Column | Content | Required |
|---|---|---|
| `portal_id` | Lowercase words joined by hyphens, e.g. `adobe-stock`. Unique | Yes |
| `name` | Portal name | Yes |
| `kind` | `stock`, `print-on-demand`, `gallery` or `own-shop` | Yes |
| `url` | Home or contributor page | Yes |
| `signup_url` | Where an account is opened | |
| `upload_url` | Where files are uploaded | |
| `account_status` | `none`, `applied`, `active`, `rejected` or `closed`, as Istvan reports it | Yes |
| `exclusivity` | `non-exclusive` or `exclusive` | Yes |
| `commission` | What Istvan earns per sale, as the portal states it | |
| `payout` | Minimum payout and method | |
| `min_megapixels` | Number | |
| `max_long_edge_px` | Number; empty for full size. The app downsizes exports to it | |
| `max_keywords` | Number | |
| `max_title_chars` | Number | |
| `editorial` | `yes` or `no` | |
| `film_scans` | `yes`, `no` or `unknown` | |
| `terms_flag` | `ok`, `caution` or `rights-grab` | Yes |
| `terms_notes` | What the terms claim: exclusivity, perpetual licences, AI training | |
| `recommendation_call` | `join`, `later` or `skip` | Yes |
| `reasoning` | About the portal only, never about a specific photo | |
| `last_checked` | Date verified online. The app asks for a re-check after 30 days | Yes |

## `listings.csv`

One row per photo offered on a portal; `portal_id` + `source_folder` + `filename` is unique.

| Column | Content | Written by |
|---|---|---|
| `portal_id` | Refers to `portals.csv` | Skill |
| `source_folder` | Shoot folder | Skill |
| `filename` | Filename exactly as on disk | Skill |
| `listing_type` | `stock`, `editorial`, `print` or `edition` | Skill |
| `title` | English, within `max_title_chars` | Skill |
| `description` | Description or caption | Skill |
| `keywords` | Separated by `;`, most important first, within `max_keywords` | Skill |
| `category` | The portal's category | Skill |
| `price` | Number, for prints and editions | Skill |
| `currency` | ISO 4217 | Skill |
| `edition_size` | Number, for `edition` | Skill |
| `print_sizes` | Separated by `;` | Skill |
| `reason` | Why this photo suits this portal. Hidden in the app until Istvan has rated the photo | Skill |
| `status` | `suggested` → `prepared` → `uploaded` → `live` or `rejected` → `withdrawn` | Skill **and app**. Never move it backwards |
| `suggested_on` | Date proposed | Skill |
| `prepared_on` | Date files were made | **App** |
| `uploaded_on` | Date marked uploaded | App; skill when told |
| `live_on` | Date accepted | App; skill when told |
| `ended_on` | Date rejected or withdrawn | App; skill when told |
| `portal_ref` | The portal's ID or link once live | Skill |
| `notes` | Free text, e.g. the rejection reason | Skill |

The app refuses to prepare or mark uploaded a listing with a **hold**:

- the photo is entered in a competition whose result is pending;
- the photo is matched to a competition that has not closed;
- a stock, editorial or print listing, while the photo has an edition prepared, uploaded or live (and the reverse);
- the photo is uploaded or live on an exclusive portal (and the reverse).

It also won't prepare a photo whose file is missing or below `min_megapixels`.

## `sales.csv`

One row per sale Istvan reports. Written by the skill only.

| Column | Content | Required |
|---|---|---|
| `date` | Date of the sale | Yes |
| `portal_id` | Refers to `portals.csv` | Yes |
| `source_folder` | Shoot folder | Yes |
| `filename` | Filename | Yes |
| `listing_type` | As in `listings.csv` | |
| `edition_number` | Which print of an edition | |
| `amount` | What Istvan earned, as a number | Yes |
| `currency` | ISO 4217 | Yes |
| `notes` | Licence, print size, anything else | |
