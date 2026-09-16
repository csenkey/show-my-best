#!/usr/bin/env python3
"""Photos Istvan has rated that could be offered for sale, without the ones on hold.

SSK-3: the skill takes its candidates from this script, so it never proposes a
photo that Show My Best would refuse to prepare.

    scripts/sales-candidates.py <library folder> [--min-rating N] [--portal ID] [--show-held]

--min-rating N   only photos where Istvan's rating or Claude's is at least N
                 (default 3). Istvan's rating must exist either way (S8).
--portal ID      leave out photos that already have a listing on that portal.
--show-held      list the held photos too, each with the reasons.

A photo is held (docs/sales-spec.md, SAL-17, SAL-18, SAL-20) when it is:
  - in a submission whose result is pending;
  - matched to a competition whose deadline has not passed, and not entered;
  - uploaded or live on an exclusive portal.

Edition conflicts (SAL-19) depend on the listing type, so they are shown as a
note rather than a hold: an edition rules out stock, editorial and print of
the same photo, and the reverse.
"""

import csv
import datetime
import os
import struct
import sys

PHOTO_SUFFIXES = (".jpg", ".jpeg", ".png", ".heic", ".tif", ".tiff")
PUBLISHED = {"uploaded", "live"}
ACTIVE = {"prepared", "uploaded", "live"}
OPEN_TYPES = {"stock", "editorial", "print"}


def read_csv(root, name):
    path = os.path.join(root, name)
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8-sig") as handle:
        return [{k: (v or "").strip() for k, v in row.items() if k} for row in csv.DictReader(handle)]


def rating(text):
    try:
        value = int(text)
        return value if 1 <= value <= 5 else None
    except (TypeError, ValueError):
        return None


def pixel_size(path):
    """Width and height from a JPEG or PNG header, without any libraries."""
    try:
        with open(path, "rb") as handle:
            head = handle.read(24)
            if head[:8] == b"\x89PNG\r\n\x1a\n":
                width, height = struct.unpack(">II", head[16:24])
                return width, height
            if head[:2] != b"\xff\xd8":
                return None
            handle.seek(2)
            while True:
                marker = handle.read(2)
                if len(marker) < 2 or marker[0] != 0xFF:
                    return None
                kind = marker[1]
                if kind in (0xD8, 0x01) or 0xD0 <= kind <= 0xD7:
                    continue
                length = struct.unpack(">H", handle.read(2))[0]
                if kind in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                    handle.read(1)
                    height, width = struct.unpack(">HH", handle.read(4))
                    # EXIF orientation does not change the megapixels.
                    return width, height
                handle.seek(length - 2, 1)
    except OSError:
        return None


def main(argv):
    if len(argv) < 2 or argv[1].startswith("-"):
        print(__doc__)
        return 2
    root = os.path.expanduser(argv[1])
    min_rating = 3
    portal_filter = None
    show_held = "--show-held" in argv
    if "--min-rating" in argv:
        min_rating = int(argv[argv.index("--min-rating") + 1])
    if "--portal" in argv:
        portal_filter = argv[argv.index("--portal") + 1]

    today = datetime.date.today().isoformat()
    catalogue = read_csv(root, "catalogue.csv")
    competitions = {row.get("competition_id", ""): row for row in read_csv(root, "competitions.csv")}
    matches = read_csv(root, "competition_matches.csv")
    submissions = read_csv(root, "submissions.csv")
    portals = {row.get("portal_id", ""): row for row in read_csv(root, "portals.csv")}
    listings = read_csv(root, "listings.csv")

    def key(row):
        return f"{row.get('source_folder', '')}/{row.get('filename', '')}"

    filenames = {}
    for row in catalogue:
        filenames.setdefault(row.get("filename", "").lower(), []).append(key(row))

    def references(text):
        """A submission names photos as shoot/filename, or sometimes a bare filename."""
        found = []
        for reference in [part.strip() for part in text.split(";") if part.strip()]:
            if "/" in reference:
                found.append(reference)
            else:
                found.extend(filenames.get(reference.lower(), []))
        return found

    holds = {}

    def hold(photo, reason):
        holds.setdefault(photo, [])
        if reason not in holds[photo]:
            holds[photo].append(reason)

    entered = set()
    for submission in submissions:
        for photo in references(submission.get("photos_submitted", "")):
            entered.add((photo, submission.get("competition_id", ""), submission.get("competition_name", "")))
            if submission.get("result", "").lower() == "pending":
                hold(photo, f"entered in {submission.get('competition_name', '?')}, waiting for results")

    for match in matches:
        photo = key(match)
        competition = competitions.get(match.get("competition_id", ""))
        if not competition:
            continue
        deadline = competition.get("deadline", "")
        if deadline and deadline < today:
            continue
        if any(p == photo and (cid == competition.get("competition_id") or name == competition.get("name"))
               for p, cid, name in entered):
            continue
        name = competition.get("name") or competition.get("competition_id")
        hold(photo, f"matched to {name}, closes {deadline or '(no deadline on record)'}")

    listed = {}
    for listing in listings:
        photo = key(listing)
        listed.setdefault(photo, []).append(listing)
        status = listing.get("status", "").lower()
        portal = portals.get(listing.get("portal_id", ""), {})
        if status in PUBLISHED and portal.get("exclusivity", "").lower() == "exclusive":
            hold(photo, f"{status} on exclusive portal {portal.get('name') or listing.get('portal_id')}")

    shown = 0
    held_count = 0
    for row in catalogue:
        photo = key(row)
        mine = rating(row.get("istvan_rating"))
        claude = rating(row.get("claude_rating"))
        if mine is None:
            continue   # S8: never proposed before Istvan has rated it
        if max(mine, claude or 0) < min_rating:
            continue
        if row.get("status", "").lower() == "retired":
            continue
        existing = listed.get(photo, [])
        if portal_filter and any(listing.get("portal_id") == portal_filter for listing in existing):
            continue
        is_held = photo in holds
        if is_held:
            held_count += 1
            if not show_held:
                continue

        size = pixel_size(os.path.join(root, row.get("source_folder", ""), row.get("filename", "")))
        megapixels = f"{size[0] * size[1] / 1_000_000:.1f} MP" if size else "size unknown"

        notes = []
        active = [listing for listing in existing if listing.get("status", "").lower() in ACTIVE]
        if any(listing.get("listing_type", "").lower() == "edition" for listing in active):
            notes.append("has an edition: no stock, editorial or print")
        if any(listing.get("listing_type", "").lower() in OPEN_TYPES for listing in active):
            notes.append("has stock/editorial/print: no edition")

        facts = [
            f"istvan={mine}",
            f"claude={claude if claude is not None else '-'}",
            f"medium={row.get('medium') or '?'}",
            megapixels,
        ]
        for name in ("title", "genre_tags", "subject"):
            if row.get(name):
                facts.append(f"{name}={row[name]}")
        if existing:
            facts.append("listed=" + ",".join(f"{l.get('portal_id')}:{l.get('listing_type')}:{l.get('status') or 'suggested'}"
                                              for l in existing))
        if notes:
            facts.append("note=" + "; ".join(notes))
        if is_held:
            facts.append("HELD=" + "; ".join(holds[photo]))
        print(f"{photo}\t" + " | ".join(facts))
        shown += 1

    print(f"\n{shown} photo(s) listed.", file=sys.stderr)
    if held_count and not show_held:
        print(f"{held_count} rated photo(s) left out because they are on hold; --show-held lists them.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
