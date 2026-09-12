#!/usr/bin/env python3
"""Builds a small stand-in photo library for developing against.

    Tools/make-fixture.py /tmp/fixture-library

Writes shoots of flat-colour PNGs plus the four CSV files in the shapes
section 6 of the requirements describes, including the cases the app has to
get right: a photo with no catalogue row, a catalogue row with no photo, film
and digital shoots, a critique that is out of date, a rights-grab competition
and a couple of submissions. No dependencies: the PNGs are written by hand.
"""

import os
import struct
import sys
import zlib


# A 5x7 bitmap font, enough to label each stand-in photo so it is obvious at a
# glance which one is on screen — and that it loaded at all.
GLYPHS = {
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
}


def photo(path, width, height, colour, label):
    """Writes a PNG by hand: a two-tone gradient, a frame, and a big label."""
    dark = tuple(max(0, value - 55) for value in colour)
    light = tuple(min(255, value + 70) for value in colour)
    pixels = [[(0, 0, 0)] * width for _ in range(height)]

    for y in range(height):
        for x in range(width):
            # Diagonal gradient, so scaling and cropping are visible.
            t = (x / width * 0.65) + (y / height * 0.35)
            pixels[y][x] = tuple(
                int(dark[channel] + (light[channel] - dark[channel]) * t) for channel in range(3)
            )

    # A horizon line, so orientation is obvious at a glance (NFR-4).
    horizon = int(height * 0.62)
    for x in range(width):
        for y in range(horizon, min(height, horizon + 3)):
            pixels[y][x] = dark

    # A frame.
    for x in range(width):
        for y in list(range(4)) + list(range(height - 4, height)):
            pixels[y][x] = dark
    for y in range(height):
        for x in list(range(4)) + list(range(width - 4, width)):
            pixels[y][x] = dark

    # The label, centred.
    scale = max(3, min(width // (6 * len(label) + 2), height // 12))
    text_width = (6 * len(label) - 1) * scale
    origin_x = (width - text_width) // 2
    origin_y = (height - 7 * scale) // 2
    ink = (250, 250, 250) if sum(colour) < 400 else (30, 28, 27)
    for index, character in enumerate(label):
        rows = GLYPHS.get(character)
        if not rows:
            continue
        for row, bits in enumerate(rows):
            for column, bit in enumerate(bits):
                if bit != "1":
                    continue
                for dy in range(scale):
                    for dx in range(scale):
                        x = origin_x + (index * 6 + column) * scale + dx
                        y = origin_y + row * scale + dy
                        if 0 <= x < width and 0 <= y < height:
                            pixels[y][x] = ink

    png(path, width, height, pixels)


def png(path, width, height, pixels):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    raw = b"".join(
        b"\x00" + b"".join(bytes(pixel) for pixel in pixels[y]) for y in range(height)
    )
    data = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as handle:
        handle.write(data)


def write_csv(path, header, rows):
    def field(value):
        text = str(value)
        if any(character in text for character in ',"\r\n'):
            return '"' + text.replace('"', '""') + '"'
        return text

    lines = [",".join(header)] + [",".join(field(value) for value in row) for row in rows]
    # CRLF and UTF-8 without a BOM (FMT-2, FMT-3).
    with open(path, "wb") as handle:
        handle.write(("\r\n".join(lines) + "\r\n").encode("utf-8"))


SHOOTS = {
    "R8_Rovinj_202606": [(0x8C, 0x9B, 0xA8), (0x6B, 0x7D, 0x8C), (0xA8, 0x92, 0x7B), (0x7A, 0x8A, 0x6E)],
    "R8_Budapest_202606": [(0x9A, 0x8A, 0x7A), (0x70, 0x68, 0x74), (0x8A, 0x6E, 0x63)],
    "SL35_Szeged_202607": [(0x86, 0x86, 0x80), (0x9E, 0x99, 0x8C), (0x6E, 0x72, 0x6B)],
    "6D_Szeged_202605": [(0x77, 0x82, 0x88), (0x8F, 0x84, 0x76)],
}

CATALOGUE_HEADER = [
    "filename", "source_folder", "title", "date_taken", "date_note", "medium",
    "camera_or_format", "genre_tags", "subject", "istvan_rating", "claude_rating",
    "claude_rationale", "claude_critique", "critique_for_rating",
    "competition_fit_notes", "status", "last_updated",
]


def build(root):
    os.makedirs(root, exist_ok=True)
    filenames = {}
    for shoot_number, (shoot, colours) in enumerate(SHOOTS.items(), start=1):
        folder = os.path.join(root, shoot)
        os.makedirs(folder, exist_ok=True)
        names = []
        for index, colour in enumerate(colours, start=1):
            name = f"IMG_{index:04d}.png"
            # Every third one portrait, so the layout gets both shapes.
            width, height = (420, 620) if index % 3 == 0 else (720, 480)
            photo(os.path.join(folder, name), width, height, colour, f"{shoot_number}-{index}")
            names.append(name)
        filenames[shoot] = names

    # Folders the app must ignore (LIB-4, LIB-9).
    os.makedirs(os.path.join(root, "_contact_sheets"), exist_ok=True)
    photo(os.path.join(root, "_contact_sheets", "sheet.png"), 200, 200, (90, 90, 90), "0")

    rows = []

    def row(shoot, filename, **kwargs):
        values = {key: "" for key in CATALOGUE_HEADER}
        values["filename"] = filename
        values["source_folder"] = shoot
        values["status"] = "available"
        values.update(kwargs)
        rows.append([values[key] for key in CATALOGUE_HEADER])

    r = filenames["R8_Rovinj_202606"]
    row("R8_Rovinj_202606", r[0], title="Harbour wall, low sun", date_taken="2026-06",
        medium="digital", camera_or_format="Canon EOS R8", genre_tags="street, coastal",
        subject="A boy jumping off the harbour wall, boats stacked behind him.",
        istvan_rating="4", claude_rating="4",
        claude_rationale="The jump lands at the right moment and the town reads clearly behind it; the foreground rope is a distraction a jury would notice.",
        claude_critique="You rated this your best from Rovinj and I see why, but the frame is doing two things: the jump and the skyline. A jury will ask which one you meant.",
        critique_for_rating="5",  # out of date on purpose (IND-7, AC-6)
        competition_fit_notes="Strongest travel frame in the shoot.", last_updated="2026-09-10")
    row("R8_Rovinj_202606", r[1], title="Nets drying", date_taken="2026-06", medium="digital",
        camera_or_format="Canon EOS R8", genre_tags="documentary", subject="Nets over a rail.",
        istvan_rating="2", claude_rating="4",
        claude_rationale="Quiet, but the repetition carries it further than the rating you gave.",
        claude_critique="You passed over this quickly. The repetition is the subject and it holds up; ask yourself what you wanted from it that it does not give.",
        critique_for_rating="2", last_updated="2026-09-10")
    # Rated by Istvan, not yet by Claude.
    row("R8_Rovinj_202606", r[2], title="Steps at noon", date_taken="2026-06", medium="digital",
        camera_or_format="Canon EOS R8", genre_tags="street", istvan_rating="3", last_updated="2026-09-10")
    # Claude has rated it, Istvan has not: nothing of Claude's may show (AC-2).
    row("R8_Rovinj_202606", r[3], title="Blue shutters", date_taken="2026-06", medium="digital",
        camera_or_format="Canon EOS R8", genre_tags="street", claude_rating="5",
        claude_rationale="The colour does the work here and the frame is disciplined.",
        competition_fit_notes="Would suit the Szeged street category.", last_updated="2026-09-10")

    b = filenames["R8_Budapest_202606"]
    row("R8_Budapest_202606", b[0], title="Tram at dusk", date_taken="2026-06",
        date_note="EXIF date 2026-01-22 17:20:57, camera clock wrong", medium="digital",
        camera_or_format="Canon EOS R8", genre_tags="street, night", istvan_rating="5",
        claude_rating="5", claude_rationale="The motion and the light agree with each other.",
        claude_critique="This is the one to enter. The only thing a jury may hold against it is how familiar the subject is, so the print has to be immaculate.",
        critique_for_rating="5", last_updated="2026-09-10")
    row("R8_Budapest_202606", b[1], title="Bridge pillar", date_taken="2026-06", medium="digital",
        camera_or_format="Canon EOS R8", genre_tags="architecture", istvan_rating="1",
        claude_rating="2", claude_rationale="Little to hold the eye.", last_updated="2026-09-10")
    # b[2] has no row at all: "Not catalogued" (LIB-7).

    s = filenames["SL35_Szeged_202607"]
    row("SL35_Szeged_202607", s[0], title="Tisza bank at dusk", date_taken="2026-07",
        date_note="scanned 2026-09-10", medium="film", camera_or_format="SL35 negative scan",
        genre_tags="landscape, water", subject="Two anglers on the far bank, mist coming off the water.",
        claude_rating="4", claude_rationale="The mist gives it depth a jury will read quickly.",
        last_updated="2026-09-10")
    row("SL35_Szeged_202607", s[1], title="Zebegényi hídnál", date_taken="2026-07", medium="film",
        camera_or_format="SL35 negative scan", genre_tags="landscape", istvan_rating="5",
        claude_rating="3", claude_rationale="Pleasant, but the horizon splits it in half.",
        claude_critique="You rate this far above where I put it. What carries it for you is the memory of the place; what a jury sees is a horizon cutting the frame in two.",
        critique_for_rating="5", last_updated="2026-09-10")
    row("SL35_Szeged_202607", s[2], title="Reeds", date_taken="2026-07", medium="film",
        camera_or_format="SL35 negative scan", genre_tags="landscape", last_updated="2026-09-10")

    d = filenames["6D_Szeged_202605"]
    row("6D_Szeged_202605", d[0], title="Market morning", date_taken="2026-05", medium="digital",
        camera_or_format="Canon EOS 6D", genre_tags="street", istvan_rating="4", claude_rating="4",
        claude_rationale="Busy, but every face is doing something.", last_updated="2026-09-10")
    row("6D_Szeged_202605", d[1], title="Old sign", date_taken="21/05/2026", medium="digital",
        camera_or_format="Canon EOS 6D", genre_tags="detail", last_updated="2026-09-10")
    # A row whose photo is not on disk (LIB-8).
    row("6D_Szeged_202605", "IMG_0099.png", title="Lost frame", date_taken="2026-05",
        medium="digital", camera_or_format="Canon EOS 6D", istvan_rating="3", claude_rating="3",
        last_updated="2026-09-10")

    write_csv(os.path.join(root, "catalogue.csv"), CATALOGUE_HEADER, rows)

    write_csv(
        os.path.join(root, "competitions.csv"),
        ["competition_id", "name", "organizer", "url", "categories", "opens", "deadline",
         "deadline_note", "entry_fee", "fee_amount", "fee_currency", "tier", "eligibility",
         "capture_date_rule", "previously_unpublished", "prize", "rights_flag", "rights_notes",
         "recommendation_call", "reasoning", "last_checked"],
        [
            ["szeged-photo-salon-2026", "Szeged Photo Salon 2026", "Szeged Photographic Society",
             "https://szegedfotoszalon.hu", "Street;Landscape;Portrait", "", "2026-09-19",
             "23:59 CET", "Free", "0", "", "national", "Amateurs resident in Hungary",
             "Taken after 2024-01-01", "no", "HUF 150,000 + exhibition", "ok",
             "Organizer may show entries in the exhibition and catalogue; you keep everything else",
             "enter",
             "Free, a real regional jury, and last year's shortlist was in reach of work at this level. Two frames per category keeps the effort small.",
             "2026-09-08"],
            ["global-light-award-2027", "Global Light Award 2027", "Light Media Group",
             "https://globallight.example", "Travel;Nature", "", "2026-10-31", "",
             "EUR 8 per image", "8", "EUR", "international", "Open to all", "", "unknown",
             "EUR 10,000 and a group show", "rights-grab",
             "Perpetual worldwide licence, sub-licensable, no fee to you. You can never withdraw it.",
             "skip",
             "The entry terms take a perpetual, sub-licensable licence to every submitted image, including commercial use, and the fee is per image. The prize is real but the odds against 40,000 entries don't pay for the rights you'd sign away.",
             "2026-08-20"],
            ["balaton-nature-prize-2026", "Balaton Nature Prize 2026", "Balaton Trust",
             "https://balatonprize.example", "Landscape;Wildlife", "", "2026-06-21", "",
             "EUR 12", "12", "EUR", "national", "Amateurs", "", "no", "Exhibition", "caution",
             "Organizer may reuse entries in its own promotion for two years.",
             "worth-it-regardless",
             "A small fee for a jury that reads landscape work seriously.", "2026-06-01"],
        ],
    )

    write_csv(
        os.path.join(root, "competition_matches.csv"),
        ["competition_id", "source_folder", "filename", "category", "role", "reason", "matched_on"],
        [
            ["szeged-photo-salon-2026", "R8_Rovinj_202606", r[0], "Street", "primary",
             "You rated 4, I rated 4 — the strongest street frame in the shoot.", "2026-09-08"],
            ["szeged-photo-salon-2026", "SL35_Szeged_202607", s[1], "Landscape", "primary",
             "You rated 5, I rated 3 — we differ by 2, so this is a risk: enter it only if the print carries the mood.", "2026-09-08"],
            ["szeged-photo-salon-2026", "R8_Rovinj_202606", r[3], "Street", "alternate",
             "I rated this 5; you have not rated it yet.", "2026-09-08"],
            ["global-light-award-2027", "R8_Budapest_202606", b[0], "Travel", "primary",
             "You rated 5, I rated 5 — the best frame you have.", "2026-08-20"],
            ["global-light-award-2027", "SL35_Szeged_202607", s[0], "Nature", "alternate",
             "I rated this 4; you have not rated it yet.", "2026-08-20"],
        ],
    )

    write_csv(
        os.path.join(root, "submissions.csv"),
        ["date_submitted", "competition_id", "competition_name", "entry_fee", "deadline",
         "photos_submitted", "category", "recommendation_call", "result", "notes"],
        [
            ["2026-08-14", "", "Hungarian Press Photo", "Free", "2026-08-15",
             f"R8_Rovinj_202606/{r[0]};R8_Budapest_202606/{b[0]}", "Street", "enter", "pending",
             "Results late October"],
            ["2026-07-02", "", "CEWE Photo Award", "Free", "2026-07-03",
             f"R8_Budapest_202606/{b[0]}", "Travel", "enter", "placed", "Category shortlist, 2nd round"],
            ["2026-06-21", "balaton-nature-prize-2026", "Balaton Nature Prize 2026", "EUR 12",
             "2026-06-21", f"SL35_Szeged_202607/{s[1]};6D_Szeged_202605/{d[0]}", "Landscape",
             "worth-it-regardless", "no-award", "Jury favoured wildlife"],
        ],
    )

    print(f"fixture library written to {root}")


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "fixture-library")
