import Foundation
import ImageIO
import ShowMyBestKit

// The one-time migration of §8, for the mechanical parts of it: the new
// columns, the dates, the film labels and the submissions header. MIG-5 —
// rebuilding competitions.csv and competition_matches.csv from the rows that
// have competition_fit_notes — is not here, because it needs each competition
// re-checked online first, which is the skill's job, not a script's.
//
//     swift run Migrate <library>             report what would change
//     swift run Migrate <library> --apply     make the changes
//
// MIG-7: istvan_rating and claude_rating are never touched, and no critique is
// ever written.

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    print("usage: Migrate <library folder> [--apply]")
    exit(2)
}
let libraryURL = URL(fileURLWithPath: (arguments[1] as NSString).expandingTildeInPath)
let apply = arguments.contains("--apply")

// MARK: - Reading what is there

let catalogueURL = libraryURL.appendingPathComponent("catalogue.csv")
guard let originalData = try? Data(contentsOf: catalogueURL) else {
    print("No catalogue.csv in \(libraryURL.path)")
    exit(1)
}
var document: CSVDocument
do {
    document = try CSV.parse(data: originalData)
} catch {
    print("catalogue.csv does not parse: \(error)")
    exit(1)
}

let originalRowCount = document.records.count
let originalKeys: [String] = {
    guard let filename = document.columnIndex("filename"),
          let shoot = document.columnIndex("source_folder") else { return [] }
    return document.records.map { "\($0.value(at: shoot))/\($0.value(at: filename))" }
}()
let originalRatings: [String] = {
    guard let mine = document.columnIndex("istvan_rating"),
          let theirs = document.columnIndex("claude_rating") else { return [] }
    return document.records.map { "\($0.value(at: mine))|\($0.value(at: theirs))" }
}()

// MARK: - MIG-2: the columns the skill has not written yet

let newColumns = ["date_note", "medium", "claude_critique", "critique_for_rating"]
let columnsAdded = newColumns.filter { !document.hasColumn($0) }
document.addColumns(newColumns)

guard let filenameColumn = document.columnIndex("filename"),
      let shootColumn = document.columnIndex("source_folder"),
      let dateColumn = document.columnIndex("date_taken"),
      let noteColumn = document.columnIndex("date_note"),
      let mediumColumn = document.columnIndex("medium"),
      let cameraColumn = document.columnIndex("camera_or_format") else {
    print("catalogue.csv is missing a column the migration needs")
    exit(1)
}

// MARK: - What the file says about each photo

/// SKL-22: the shoot folder prefix decides the medium, and the EXIF camera is
/// ignored for negative scans.
func filmFormat(for shoot: String) -> String? {
    let name = shoot.uppercased()
    if name.hasPrefix("SL35_") { return "SL35 negative scan" }
    if name.hasPrefix("6X6_") { return "6x6 negative scan" }
    return nil
}

struct Exif {
    var taken: String?      // YYYY-MM-DD HH:MM:SS
    var month: String?      // YYYY-MM
    var day: String?        // YYYY-MM-DD
    var camera: String?
}

func exif(for url: URL) -> Exif {
    var result = Exif()
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return result }

    let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
    if let model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces), !model.isEmpty {
        result.camera = model
    }
    let exifDictionary = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
    let raw = (exifDictionary[kCGImagePropertyExifDateTimeOriginal] as? String)
        ?? (tiff[kCGImagePropertyTIFFDateTime] as? String)
    if let raw, raw.count >= 10 {
        // EXIF writes 2026:06:02 17:21:53
        let datePart = String(raw.prefix(10)).replacingOccurrences(of: ":", with: "-")
        result.taken = datePart + String(raw.dropFirst(10))
        result.day = datePart
        result.month = String(datePart.prefix(7))
    }
    return result
}

/// The explanation the skill left in brackets after the date, kept so the
/// migration moves it rather than dropping it (MIG-3).
func explanation(in text: String) -> String? {
    guard let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")"), open < close else { return nil }
    let inside = String(text[text.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
    return inside.isEmpty ? nil : inside
}

/// A date already in FMT-6 shape at the front of the old value.
func leadingDate(in text: String) -> String? {
    let normalised = text.replacingOccurrences(of: ":", with: "-")
    let parts = normalised.split(separator: " ")
    guard let first = parts.first else { return nil }
    let candidate = String(first)
    return ISODate.isValid(candidate) && candidate.count >= 7 ? candidate : nil
}

// MARK: - The conversion (MIG-3, MIG-4)

struct Change {
    var key: String
    var oldDate: String
    var newDate: String
    var note: String
    var medium: String
    var camera: String
    var oldCamera: String
}

var changes: [Change] = []
var unresolved: [String] = []
var clockCorrectRows: [String] = []

for index in document.records.indices {
    let record = document.records[index]
    let shoot = record.value(at: shootColumn)
    let filename = record.value(at: filenameColumn)
    let key = "\(shoot)/\(filename)"
    let oldDate = record.value(at: dateColumn).trimmingCharacters(in: .whitespaces)
    let oldCamera = record.value(at: cameraColumn)
    let existingNote = record.value(at: noteColumn)

    guard let folderMonth = LibraryScanner.monthFromShootName(shoot) else {
        // SKL-21: no _YYYYMM to work from, so this one is a question, not a guess.
        unresolved.append("\(key) — the shoot folder name has no _YYYYMM ending")
        continue
    }

    let photoURL = libraryURL.appendingPathComponent(shoot).appendingPathComponent(filename)
    let photo = exif(for: photoURL)
    let carried = explanation(in: oldDate)

    var newDate: String
    var noteParts: [String] = []
    var medium: String
    var camera = oldCamera

    if let format = filmFormat(for: shoot) {
        // SKL-22: a negative scan, judged as the finished image. Its EXIF date
        // is when it was scanned, never when the roll was shot.
        medium = "film"
        camera = format
        newDate = folderMonth
        if let scanned = photo.day { noteParts.append("scanned \(scanned)") }
    } else {
        medium = "digital"
        if let model = photo.camera { camera = model }

        if let carried, carried.lowercased().contains("camera clock correct"), let stated = leadingDate(in: oldDate) {
            // Istvan's decision: an explicit "camera clock correct" beats the
            // folder month, and the difference is written down rather than
            // silently resolved.
            newDate = stated
            noteParts.append("camera clock correct; shoot folder month is \(folderMonth)")
            clockCorrectRows.append("\(key) → \(stated)")
        } else if let exifMonth = photo.month, exifMonth == folderMonth, let day = photo.day {
            // SKL-21: the EXIF date is used only when it falls in that month.
            newDate = day
        } else {
            newDate = folderMonth
            if let taken = photo.taken {
                noteParts.append("EXIF date \(taken)")
            }
        }
    }

    if let carried, !carried.lowercased().contains("camera clock correct") {
        noteParts.append(carried)
    }
    if !existingNote.isEmpty { noteParts.append(existingNote) }

    let note = noteParts.joined(separator: "; ")
    if newDate != oldDate || note != existingNote || medium != record.value(at: mediumColumn) || camera != oldCamera {
        changes.append(Change(key: key, oldDate: oldDate, newDate: newDate, note: note,
                              medium: medium, camera: camera, oldCamera: oldCamera))
    }

    document.records[index].setValue(newDate, at: dateColumn)
    document.records[index].setValue(note, at: noteColumn)
    document.records[index].setValue(medium, at: mediumColumn)
    document.records[index].setValue(camera, at: cameraColumn)
}

// MARK: - MIG-8: check nothing was lost

var problems: [String] = []
if document.records.count != originalRowCount {
    problems.append("row count changed: \(originalRowCount) → \(document.records.count)")
}
let keysNow = document.records.map { "\($0.value(at: shootColumn))/\($0.value(at: filenameColumn))" }
if keysNow != originalKeys { problems.append("photo keys changed") }
if let mine = document.columnIndex("istvan_rating"), let theirs = document.columnIndex("claude_rating") {
    let ratingsNow = document.records.map { "\($0.value(at: mine))|\($0.value(at: theirs))" }
    if ratingsNow != originalRatings { problems.append("a rating changed — MIG-7 says none may") }
}
let badDates = document.records
    .map { $0.value(at: dateColumn) }
    .filter { !$0.isEmpty && !ISODate.isValid($0) }
if !badDates.isEmpty { problems.append("\(badDates.count) dates are still not in FMT-6 format") }
if (try? CSV.parse(data: document.serialized())) == nil { problems.append("the result does not parse") }

// MARK: - Report

print("Library: \(libraryURL.path)")
print(apply ? "Mode:    applying the changes\n" : "Mode:    dry run, nothing is written\n")

print("MIG-2  columns added        \(columnsAdded.isEmpty ? "none needed" : columnsAdded.joined(separator: ", "))")
print("MIG-3  dates converted      \(changes.filter { $0.oldDate != $0.newDate }.count) of \(originalRowCount)")
print("MIG-4  film rows relabelled \(changes.filter { $0.medium == "film" }.count)")
print("       digital rows         \(changes.filter { $0.medium == "digital" }.count)")
if !clockCorrectRows.isEmpty {
    print("\n  kept their own date, folder month overruled (your decision):")
    for row in clockCorrectRows { print("    \(row)") }
}
if !unresolved.isEmpty {
    print("\n  left alone, needs an answer first:")
    for row in unresolved { print("    \(row)") }
}

print("\n  a few converted rows:")
for change in changes.prefix(5) {
    print("    \(change.key)")
    print("      date   \(change.oldDate.isEmpty ? "(empty)" : change.oldDate)")
    print("        →    \(change.newDate)\(change.note.isEmpty ? "" : "   note: \(change.note)")")
    if change.camera != change.oldCamera {
        print("      camera \(change.oldCamera.isEmpty ? "(empty)" : change.oldCamera) → \(change.camera)  (\(change.medium))")
    }
}

print("\nMIG-8  checks               \(problems.isEmpty ? "passed — rows, keys and ratings all unchanged" : "FAILED")")
for problem in problems { print("       ! \(problem)") }

guard problems.isEmpty else {
    print("\nNothing written.")
    exit(1)
}

guard apply else {
    print("\nNothing written. Run again with --apply to make these changes.")
    exit(0)
}

// MARK: - MIG-1: back up first, then write

let backups = libraryURL.appendingPathComponent("_backups", isDirectory: true)
try? FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
let stamp = ISODate.today()
for name in ["catalogue.csv", "submissions.csv", "competitions.csv", "competition_matches.csv"] {
    let source = libraryURL.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: source.path) else { continue }
    let destination = backups.appendingPathComponent("\(name.replacingOccurrences(of: ".csv", with: ""))-\(stamp).csv")
    if !FileManager.default.fileExists(atPath: destination.path) {
        try? FileManager.default.copyItem(at: source, to: destination)
    }
}
print("\nMIG-1  backed up to         _backups/")

/// FMT-9: every writer replaces a file in one step.
func writeAtomically(_ data: Data, to url: URL) throws {
    let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).migrate-tmp")
    try data.write(to: temporary, options: .atomic)
    if FileManager.default.fileExists(atPath: url.path) {
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    } else {
        try FileManager.default.moveItem(at: temporary, to: url)
    }
}

try writeAtomically(document.serialized(), to: catalogueURL)
print("MIG-3  catalogue.csv written")

// MARK: - MIG-6: the submissions header, which has no entries to migrate

let submissionsURL = libraryURL.appendingPathComponent("submissions.csv")
let submissionsHeader = [
    "date_submitted", "competition_id", "competition_name", "entry_fee", "deadline",
    "photos_submitted", "category", "recommendation_call", "result", "notes",
]
if let data = try? Data(contentsOf: submissionsURL), let existing = try? CSV.parse(data: data) {
    if existing.records.isEmpty {
        try writeAtomically(Data((submissionsHeader.joined(separator: ",") + "\r\n").utf8), to: submissionsURL)
        print("MIG-6  submissions.csv header replaced (it had no entries)")
    } else {
        print("MIG-6  SKIPPED — submissions.csv has \(existing.records.count) entries; migrate them by hand")
    }
}

print("""

MIG-5 is not done here: competitions.csv and competition_matches.csv have to be
built from the rows with competition_fit_notes, and each competition re-checked
online first. Ask the photo-competition-curator skill to do that.
""")
