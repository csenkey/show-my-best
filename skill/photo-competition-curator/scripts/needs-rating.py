#!/usr/bin/env python3
"""The photos that still need a rating from Claude — with nothing of Istvan's in the output.

SKL-8: before rating, the skill gets its worklist from this script rather than
from the catalogue directly, because reading catalogue.csv would show it
Istvan's ratings and the whole point is to rate blind (D15).

    scripts/needs-rating.py <library folder> [--all]

Prints one photo per line as `source_folder/filename` followed by the
descriptive columns only. istvan_rating, claude_critique and critique_for_rating
are never printed, whatever the flags.

--all lists every catalogued photo (for a re-rating Istvan has explicitly
asked for), instead of only those with no claude_rating.
"""

import csv
import os
import sys

WITHHELD = {"istvan_rating", "claude_critique", "critique_for_rating"}
SHOWN = ["title", "date_taken", "date_note", "medium", "camera_or_format", "genre_tags", "subject"]
PHOTO_SUFFIXES = (".jpg", ".jpeg", ".png", ".heic", ".tif", ".tiff")


def main(root, everything):
    catalogue = os.path.join(root, "catalogue.csv")
    rows = {}
    if os.path.exists(catalogue):
        with open(catalogue, newline="", encoding="utf-8") as handle:
            for row in csv.DictReader(handle):
                key = f"{row.get('source_folder','')}/{row.get('filename','')}"
                rows[key] = row

    # SKL-1: a folder whose name starts with _ or . is never a shoot.
    on_disk = []
    for shoot in sorted(os.listdir(root)):
        if shoot.startswith(("_", ".")):
            continue
        folder = os.path.join(root, shoot)
        if not os.path.isdir(folder):
            continue
        for filename in sorted(os.listdir(folder)):
            if filename.startswith(".") or not filename.lower().endswith(PHOTO_SUFFIXES):
                continue
            on_disk.append(f"{shoot}/{filename}")

    printed = 0
    for key in on_disk:
        row = rows.get(key)
        rated = bool((row or {}).get("claude_rating", "").strip())
        if rated and not everything:
            continue
        facts = []
        if row:
            facts = [f"{name}={row.get(name,'').strip()}" for name in SHOWN if row.get(name, "").strip()]
        else:
            facts = ["(no catalogue row yet)"]
        print(f"{key}\t" + "; ".join(facts))
        printed += 1

    print(f"\n{printed} photo(s) need a rating from Claude.", file=sys.stderr)
    print(f"Withheld from this output by SKL-8: {', '.join(sorted(WITHHELD))}", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    main(os.path.expanduser(sys.argv[1]), "--all" in sys.argv)
