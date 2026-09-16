# Show My Best: implementation notes

| | |
|---|---|
| Version | 0.1, first implementation |
| Date | 2026-09-11 |
| Implements | [requirements-spec.md](requirements-spec.md) v0.1, and the screens wireframed in the `Show My Best Screens` design project |

## 1. How it is built

Swift 6 and SwiftUI, as NFR-1 asks, but as a **SwiftPM package rather than an
Xcode project**: the Mac this was written on has the Command Line Tools and no
Xcode, and a SwiftUI app builds and links perfectly well without one. The app
bundle is assembled by a script.

```bash
Tools/build-app.sh          # builds build/ShowMyBest.app
swift run SelfTest          # runs the checks in §4 below
```

To use it, copy `build/ShowMyBest.app` to `/Applications` and open it. The
first launch asks for the library folder; macOS will also ask once for
permission to read that folder, because the app is not sandboxed and
`~/Pictures` is protected.

`Tools/make-fixture.py <folder>` writes a small stand-in library — four shoots
of flat-colour PNGs plus the four CSVs, including the awkward cases (a photo
with no catalogue row, a row with no photo, an out-of-date critique, a
rights-grab competition, an unparseable date). `ShowMyBest --library <folder>`
opens a folder without disturbing the remembered one.

### Open items now decided

- **OI-1, minimum macOS version: 14.0.** `@Observable` and `onKeyPress` both
  need it, and they carry the state handling and the keyboard-first culling.
  Nothing in the app needs anything newer.
- **OI-5, build and install: an ad-hoc signed bundle, copied by hand.** No
  Apple Developer account is involved, so there is no notarisation and no
  automatic updates. `Tools/build-app.sh` signs with `codesign --sign -`,
  which is enough for the app to run on the Mac that built it.

## 2. Shape of the code

```
Sources/ShowMyBestKit/     no UI, and the whole data contract
  CSV.swift                RFC 4180 over bytes, keeping every record's original text
  Models.swift             PhotoKey, CatalogueRow, Photo, Competition, Submission, dates
  CatalogueStore.swift     reading and writing catalogue.csv under the §4.5 rules
  SupportFiles.swift       backups, the rating log, changes waiting to be written
  LibraryScanner.swift     finding shoots and photos on disk
  SidecarFiles.swift       competitions, matches and submissions (read only)
  LibraryModel.swift       what the app shows: scope, filters, sorting, reloading

Sources/ShowMyBest/        SwiftUI
  ShowMyBestApp.swift      the app, its menus and shortcuts
  Theme.swift              the Broadsheet tokens as colours, type and small views
  RootView.swift           sidebar, notices, first run
  GalleryView.swift        the grid, filters and keyboard rating
  PhotoDetailView.swift    one photo, unrevealed and revealed
  ReviewView.swift         full-screen review and rating
  CompetitionsView.swift   competitions, flags and matched photos
  SubmissionsView.swift    what was entered and how it went

Sources/SelfTest/          the acceptance scenarios, without a UI
```

`ShowMyBestKit` has no SwiftUI in it, which is what lets the acceptance
scenarios run as a plain command-line program.

### Two decisions worth knowing

**The CSV is handled as bytes, not text.** RAT-6 asks for rows the app did not
change to be written back byte for byte. Swift reads `\r\n` as a *single*
`Character`, so character-wise scanning cannot tell a CR from a CRLF — which is
exactly the distinction that has to survive. Each record therefore keeps its
original bytes and the byte ranges of its fields; changing a rating splices the
new value into those bytes and touches nothing else. (This was a real bug
first, caught by the self-test.)

**Claude's evaluation is withheld by the model, not by the views.** `Photo`
exposes `claudeRating`, `claudeRationale`, `claudeCritique` and
`competitionFitNotes` as computed properties that return nothing unless
`istvanRating` is set. A view cannot show Claude's opinion of an unrated photo
even by mistake, and there is no setting that changes this (IND-1, IND-6).
Collections and filters that read Claude's rating go through the same
properties, so they drop unrated photos on their own (IND-3).

## 3. Where each requirement lives

| Requirements | Implemented in |
|---|---|
| §3 Independent opinions | `Models.swift` (`Photo`), `LibraryModel.viewDependsOnClaude`, `excludedUnratedCount` |
| 4.1 Library and photos | `LibraryScanner.swift`, `LibraryModel.open`, `WelcomeView` |
| 4.2 Gallery | `GalleryView.swift`, `LibraryModel` scope/filters/sorting |
| 4.3 Review mode | `ReviewView.swift` (`ReviewSession`) |
| 4.4 Photo detail | `PhotoDetailView.swift` |
| 4.5 Rating and saving | `CatalogueStore.swift`, `SupportFiles.swift` |
| 4.6 Competitions | `CompetitionsView.swift`, `SidecarFiles.swift` |
| 4.7 Submissions | `SubmissionsView.swift`, `LibraryModel.submissionSummary` |
| 4.8 Reloading and errors | `LibraryModel.pollForChanges`/`reload`, `NoticeBar` |
| §5 Non-functional | `ImageCache.swift` (NFR-4, 5, 7, 8), `Theme.swift` (NFR-9), menus (NFR-10) |

| Selling ([sales-spec.md](sales-spec.md)) | `Sales.swift` (files), `SalesRules.swift` (holds, SAL-17 to SAL-23), `ListingStore.swift` (status writes, SAL-32 to SAL-35), `ListingExporter.swift` (SAL-26 to SAL-31), `LibraryModel+Sales.swift`, `SalesView.swift` |

Requirement IDs appear as comments at the places that carry them, so
`git grep RAT-6` finds the code that implements it.

### How the writing rules are met

- **RAT-4**: `flush()` reads `catalogue.csv` from disk again and applies the
  pending changes to *that* copy. Nothing older is ever written back.
- **RAT-5, RAT-6**: only `istvan_rating` cells are spliced and rows appended;
  everything else is the original bytes.
- **RAT-7**: written to `.catalogue.csv.showmybest-tmp` in the library, then
  `replaceItemAt`. Those two are the only files the app writes there (RAT-13).
- **RAT-9, RAT-10, RAT-11**: pending changes, daily backups (30 kept) and the
  change log live in `~/Library/Application Support/ShowMyBest/libraries/<library>/`.
- **SAL-32, SAL-33**: `listings.csv` is the one other file the app writes in the
  library, and only its `status` and date cells, under the same fresh-read,
  splice and atomic-replace rules. Exports go to `~/Pictures/Show My Best
  Exports/`, never into the library.
- **RAT-12**: on reload, any rating the app logged in the last 7 days that has
  gone back to its *previous* value is restored and reported. It only fires on
  that exact reversal, so a value the app never wrote is left alone.

## 4. What is checked

`swift run SelfTest` runs 135 checks, the selling side among them, with no UI and no Xcode: the CSV
round-trip and splice, the rating writes (RAT-3/5/6), same filename in two
shoots (AC-9), Hungarian text surviving a write (AC-12), the broken-file
refusal and recovery (AC-7), the overwrite restore (AC-4), the reveal rules
(AC-2, AC-3, AC-6) and the competition status arithmetic.

Not covered by it, and worth doing by hand: AC-8 (opening today's real
13-column catalogue), AC-10 (a skill run), AC-11 (the network check), and the
performance figures in NFR-5 to NFR-7, which need the real 5,000-photo library.

## 5. Not done yet

| | |
|---|---|
| CUL-11 | Compare two photos side by side. Marked *Could*; not built. |
| CUL-8 | Zoom is a toggle to a large fixed size that can be panned, not a true 100% pixel zoom. |
| DET-8 | "Open with" opens the photo in the default app rather than offering a chooser. |
| GAL-9 | Multi-select is click and ⌘-click; there is no shift-range selection yet. |
| NFR-11 | VoiceOver labels are on thumbnails and the rating control, not yet everywhere. |
| §7, §8 | The skill changes and the migration are the skill's side of the contract, not the app's. |

The app already follows SYN-5, so it runs against the catalogue as the skill
writes it today: critique markers and the medium filter stay hidden until those
columns exist, and dates it cannot read are shown as text and sorted last.
