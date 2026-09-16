import Foundation
import ShowMyBestKit

// The acceptance scenarios in §9 of the requirements, and the write rules they
// rest on, checked without a UI. Xcode is not installed on the build machine,
// so this runs as a plain executable: `swift run SelfTest`.

// Read-only report on a real library instead of the checks.
if let flag = CommandLine.arguments.firstIndex(of: "--inspect"), flag + 1 < CommandLine.arguments.count {
    exit(Inspect.run(CommandLine.arguments[flag + 1]))
}

var failures = 0
var checks = 0

func check(_ condition: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if condition {
        print("  ok   \(name)")
    } else {
        failures += 1
        let extra = detail()
        print("  FAIL \(name)\(extra.isEmpty ? "" : "\n       \(extra)")")
    }
}

func section(_ name: String) { print("\n\(name)") }

func temporaryLibrary(_ catalogue: String, named name: String = "catalogue.csv") -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("show-my-best-selftest-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try! Data(catalogue.utf8).write(to: url.appendingPathComponent(name))
    return url
}

func read(_ url: URL) -> String {
    String(data: try! Data(contentsOf: url.appendingPathComponent("catalogue.csv")), encoding: .utf8)!
}

let header = "filename,source_folder,title,date_taken,istvan_rating,claude_rating,claude_rationale,status\r\n"

// ---------------------------------------------------------------- CSV

section("CSV (FMT-1, RAT-6)")

do {
    let text = header
        + "IMG_0412.JPG,R8_Rovinj_202606,\"Harbour wall, low sun\",2026-06,4,4,\"He said \"\"yes\"\", twice\",available\r\n"
        + "IMG_0998.jpg,SL35_Szeged_202607,Zebegényi hídnál,2026-07,,,,available\r\n"
    let document = try CSV.parse(data: Data(text.utf8))
    check(document.headerNames.count == 8, "header names parse")
    check(document.records.count == 2, "record count")
    check(document.records[0].value(at: 2) == "Harbour wall, low sun", "quoted field with a comma")
    check(document.records[0].value(at: 6) == "He said \"yes\", twice", "escaped quotes inside a field")
    check(document.records[1].value(at: 2) == "Zebegényi hídnál", "Hungarian text (NFR-12)")
    check(document.lineEnding == "\r\n", "CRLF detected (FMT-3)")
    check(String(data: document.serialized(), encoding: .utf8) == text, "round-trip is byte-identical (RAT-6)")
}

do {
    // A file with no final newline, and a field holding a line break.
    let text = "a,b\nx,\"line\nbreak\"\nlast,row"
    let document = try CSV.parse(data: Data(text.utf8))
    check(document.records.count == 2, "a newline inside a quoted field does not end the record")
    check(document.records[1].hasTerminator == false, "unterminated last record noticed")
    check(String(data: document.serialized(), encoding: .utf8) == text, "round-trip without a final newline")
}

do {
    var document = try CSV.parse(data: Data((header + "a.jpg,S,t,2026-01,,3,r,available\r\n").utf8))
    document.records[0].setValue("5", at: 4)
    check(document.records[0].value(at: 4) == "5", "a spliced cell reads back")
    check(String(data: document.serialized(), encoding: .utf8) == header + "a.jpg,S,t,2026-01,5,3,r,available\r\n",
          "splicing changes only that cell")
}

do {
    let broken = header + "a.jpg,S,\"unbalanced,2026-01,,3,r,available\r\n"
    do {
        _ = try CSV.parse(data: Data(broken.utf8))
        check(false, "an unbalanced quote is rejected")
    } catch let error as CSVError {
        check(error.line == 2, "the error names the line (SYN-3)", "got \(error.description)")
    }
}

// ------------------------------------------------------- Rating writes

section("Rating writes (RAT-3, RAT-5, RAT-6, AC-1, AC-9, AC-12)")

do {
    let original = header
        + "IMG_0412.JPG,R8_Rovinj_202606,\"Harbour wall, low sun\",2026-06,,4,\"Reads well\",available\r\n"
        + "IMG_2216.JPG,R8_Rovinj_202606,Zebegényi hídnál,2026-06,2,3,r,available\r\n"
        + "IMG_2216.JPG,R8_Budapest_202606,Tram,2026-06,,5,r,available\r\n"
    let library = temporaryLibrary(original)
    let store = CatalogueStore(libraryURL: library)
    store.reload()
    check(store.rows.count == 3, "rows load")

    _ = store.setRating(4, for: PhotoKey(shoot: "R8_Rovinj_202606", filename: "IMG_0412.JPG"))
    let afterFirst = read(library)
    check(afterFirst.contains("\"Harbour wall, low sun\",2026-06,4,4,"), "the rating lands in istvan_rating")
    check(afterFirst.contains("Zebegényi hídnál"), "Hungarian text survives the write (AC-12)")
    check(afterFirst.components(separatedBy: "\r\n").count == original.components(separatedBy: "\r\n").count,
          "no rows added or removed")

    // AC-9: the same filename in two shoots.
    _ = store.setRating(5, for: PhotoKey(shoot: "R8_Budapest_202606", filename: "IMG_2216.JPG"))
    let afterSecond = read(library)
    check(afterSecond.contains("IMG_2216.JPG,R8_Budapest_202606,Tram,2026-06,5,5,r,available"), "the Budapest row changed")
    check(afterSecond.contains("IMG_2216.JPG,R8_Rovinj_202606,Zebegényi hídnál,2026-06,2,3,r,available"),
          "the Rovinj row with the same filename did not (AC-9, LIB-6)")

    // RAT-3 / AC-1: a photo with no row.
    _ = store.setRating(3, for: PhotoKey(shoot: "R8_New_202609", filename: "IMG_9999.JPG"))
    let afterThird = read(library)
    check(afterThird.hasSuffix("IMG_9999.JPG,R8_New_202609,,,3,,,available\r\n"),
          "an uncatalogued photo appends a minimal row (RAT-3)", afterThird)
    check(afterThird.hasPrefix(header), "the header is untouched")

    // Clearing leaves the row in place (RAT-3).
    _ = store.setRating(nil, for: PhotoKey(shoot: "R8_New_202609", filename: "IMG_9999.JPG"))
    check(read(library).hasSuffix("IMG_9999.JPG,R8_New_202609,,,,,,available\r\n"), "clearing empties the cell, keeps the row")

    try? FileManager.default.removeItem(at: library)
}

// ---------------------------------------------------- Broken file (AC-7)

section("Broken catalogue (RAT-8, AC-7)")

do {
    let broken = header + "a.jpg,S,\"unbalanced,2026-01,,3,r,available\r\n"
    let library = temporaryLibrary(broken)
    let store = CatalogueStore(libraryURL: library)
    store.reload()
    check(store.loadError != nil, "the parse failure is reported")
    check(store.loadError?.contains("line 2") == true, "the message names the line (SYN-3)", store.loadError ?? "")

    let result = store.setRating(4, for: PhotoKey(shoot: "S", filename: "a.jpg"))
    if case .failed = result {
        check(true, "the write is refused")
    } else {
        check(false, "the write is refused")
    }
    check(read(library) == broken, "the file is left exactly as it was")
    check(store.pending.count == 1, "the change is held (RAT-8)")

    // Fixing the file lets the held change through.
    try! Data((header + "a.jpg,S,fixed,2026-01,,3,r,available\r\n").utf8).write(to: library.appendingPathComponent("catalogue.csv"))
    store.reload()
    check(read(library).contains("a.jpg,S,fixed,2026-01,4,3,r,available"), "the held change is saved once the file parses")
    check(store.pending.isEmpty, "nothing is left pending")

    try? FileManager.default.removeItem(at: library)
}

// ------------------------------------------- Overwritten rating (AC-4)

section("A skill run overwrites a rating (RAT-12, AC-4)")

do {
    let original = header + "a.jpg,S,t,2026-01,,3,r,available\r\n"
    let library = temporaryLibrary(original)
    let store = CatalogueStore(libraryURL: library)
    store.reload()
    _ = store.setRating(4, for: PhotoKey(shoot: "S", filename: "a.jpg"))
    check(read(library).contains(",4,3,"), "the rating is saved")

    // A stale writer puts the file back the way it was.
    try! Data(original.utf8).write(to: library.appendingPathComponent("catalogue.csv"))
    let restored = store.reload()
    check(restored.count == 1, "the lost rating is noticed")
    check(restored.first?.rating == 4, "it is restored to what the app saved")
    check(read(library).contains(",4,3,"), "and written back to the file")

    try? FileManager.default.removeItem(at: library)
}

// ------------------------------------------ Independent opinions (§3)

section("Independent opinions (IND-1, IND-5, IND-7)")

do {
    var row = CatalogueRow(key: PhotoKey(shoot: "S", filename: "a.jpg"), recordIndex: 0)
    row.claudeRating = 5
    row.claudeRationale = "A jury would stop for this."
    row.claudeCritique = "The frame is doing two things."
    row.critiqueForRating = 5
    row.competitionFitNotes = "Fits CEWE Travel."

    var photo = Photo(key: row.key, url: URL(fileURLWithPath: "/tmp/a.jpg"), row: row)
    check(photo.isRevealed == false, "an unrated photo is not revealed")
    check(photo.claudeRating == nil, "Claude's rating is withheld (IND-1)")
    check(photo.claudeRationale.isEmpty, "the rationale is withheld")
    check(photo.claudeCritique.isEmpty, "the critique is withheld")
    check(photo.competitionFitNotes.isEmpty, "the fit notes are withheld (AC-2)")
    check(photo.hasCritique == false, "no critique marker either")

    photo.row?.istvanRating = 5
    check(photo.isRevealed, "rating reveals the photo (IND-5, AC-3)")
    check(photo.claudeRating == 5, "Claude's rating appears")
    check(photo.critiqueIsOutOfDate == false, "a critique written for this rating is current")

    photo.row?.istvanRating = 3
    check(photo.critiqueIsOutOfDate, "changing the rating marks the critique out of date (IND-7, AC-6)")
    check(photo.critiqueWrittenForRating == 5, "and says which rating it was written for")

    photo.row?.istvanRating = nil
    check(photo.claudeRating == nil, "clearing the rating hides it again (IND-5)")
}

// --------------------------------------------------------- Competitions

section("Competitions (CMP-2, CMP-7)")

do {
    var competition = Competition(id: "x")
    let calendar = Calendar.current
    let today = Date()
    competition.deadline = ISODate.today()
    check(competition.status(on: today) == .closingSoon, "a deadline today is closing soon")

    let far = calendar.date(byAdding: .day, value: 50, to: today)!
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    competition.deadline = formatter.string(from: far)
    check(competition.status(on: today) == .open, "50 days out is open")
    check(competition.daysLeft(on: today) == 50, "days left counted")

    let past = calendar.date(byAdding: .day, value: -1, to: today)!
    competition.deadline = formatter.string(from: past)
    check(competition.status(on: today) == .closed, "a passed deadline is closed")

    competition.lastChecked = formatter.string(from: calendar.date(byAdding: .day, value: -20, to: today)!)
    check(competition.needsRecheck(on: today), "details older than 14 days ask for a re-check (CMP-7)")
}

section("Dates (FMT-6, SYN-5)")

do {
    check(ISODate.isValid("2026-06"), "YYYY-MM")
    check(ISODate.isValid("2026-06-21"), "YYYY-MM-DD")
    check(ISODate.isValid("2026-06-21T17:20:57"), "YYYY-MM-DDTHH:MM:SS")
    check(ISODate.isValid("2026"), "YYYY")
    check(!ISODate.isValid("21/06/2026"), "anything else is text, sorted last")
    check(LibraryScanner.monthFromShootName("R8_Rovinj_202606") == "2026-06", "the shoot folder month (SKL-21)")
    check(LibraryScanner.monthFromShootName("NoMonth") == nil, "a folder with no month suffix")
}

section("Find by name")

do {
    func photo(_ shoot: String, _ filename: String, title: String = "") -> Photo {
        var row = CatalogueRow(key: PhotoKey(shoot: shoot, filename: filename), recordIndex: 0)
        row.title = title
        return Photo(key: row.key, url: URL(fileURLWithPath: "/tmp/\(filename)"), row: row)
    }
    let library = [
        photo("R8_Budapest_202606", "IMG_9786.JPG", title: "Liberty Bridge"),
        photo("R8_Rovinj_202606", "IMG_2216.JPG"),
        photo("R8_Budapest_202606", "IMG_2216.JPG"),
        photo("SL35_Szeged_202607", "IMG_0998.jpg", title: "Zebegényi hídnál"),
        photo("6X6_Balaton_202607", "IMG_1083.jpg"),
    ]
    func keys(_ result: PhotoFinder.Result) -> [String] { result.photos.map(\.key.description) }

    check(keys(PhotoFinder.find("IMG_9786", in: library)) == ["R8_Budapest_202606/IMG_9786.JPG"],
          "a bare camera stem")
    check(keys(PhotoFinder.find("img_9786.jpg", in: library)) == ["R8_Budapest_202606/IMG_9786.JPG"],
          "a filename, ignoring case")
    check(keys(PhotoFinder.find("IMG-9786", in: library)) == ["R8_Budapest_202606/IMG_9786.JPG"],
          "a stem written with a hyphen")
    check(keys(PhotoFinder.find("9786", in: library)) == ["R8_Budapest_202606/IMG_9786.JPG"],
          "just the number")

    let reference = PhotoFinder.find("R8_Budapest_202606/IMG_9786.JPG", in: library)
    check(reference.matches.count == 1 && keys(reference) == ["R8_Budapest_202606/IMG_9786.JPG"],
          "a full shoot/filename reference, not counted twice", "\(reference.matches.map(\.name))")

    check(keys(PhotoFinder.find("IMG_2216", in: library)).count == 2,
          "the same filename in two shoots shows both (LIB-6)")
    check(keys(PhotoFinder.find("R8_Rovinj_202606/IMG_2216.JPG", in: library)) == ["R8_Rovinj_202606/IMG_2216.JPG"],
          "a reference picks the one shoot")

    let pasted = PhotoFinder.find("""
        Urgent — closes in 2 days (Mon, Sept 14). Your pick: IMG_9786 "Liberty Bridge".
        Landscapes → IMG_0998, and IMG_4444 as a backup. Again IMG_9786. Checked 2026-09-12.
        """, in: library)
    check(pasted.matches.map(\.name) == ["IMG_9786", "IMG_0998"],
          "a pasted message finds every photo it names, in order, each once", "\(pasted.matches.map(\.name))")
    check(pasted.notFound == ["IMG_4444"], "and says which names are not in the library", "\(pasted.notFound)")
    check(pasted.textMatches.isEmpty, "and does not read a year as a filename")

    check(keys(PhotoFinder.find("zebegenyi", in: library)) == ["SL35_Szeged_202607/IMG_0998.jpg"],
          "a title, ignoring case and accents")
    check(keys(PhotoFinder.find("liberty", in: library)) == ["R8_Budapest_202606/IMG_9786.JPG"],
          "part of a title")
    check(PhotoFinder.find("   ", in: library).isEmpty, "an empty query finds nothing")
}

section("Entry fees (SUB-5)")

do {
    func fee(_ text: String) -> String {
        guard let amount = EntryFee.parse(text) else { return "free/none" }
        return "\(amount.currency) \(amount.value)"
    }
    check(fee("$27") == "USD 27.0", "a dollar sign", fee("$27"))
    check(fee("US$25.50") == "USD 25.5", "US$ with cents", fee("US$25.50"))
    check(fee("27 USD") == "USD 27.0", "the code after the amount", fee("27 USD"))
    check(fee("EUR 18 per single image") == "EUR 18.0", "the code before, with words after", fee("EUR 18 per single image"))
    check(fee("€18-21 per single image") == "EUR 18.0", "a range counts its lower figure", fee("€18-21 per single image"))
    check(fee("£14") == "GBP 14.0", "a pound sign", fee("£14"))
    check(fee("HUF 5,000") == "HUF 5000.0", "a thousands separator", fee("HUF 5,000"))
    check(fee("Free") == "free/none", "free")
    check(fee("Free, up to 3 images") == "free/none", "a number with no currency is not a fee", fee("Free, up to 3 images"))
    check(fee("") == "free/none", "empty")
}

section("Submission photos (SUB-3, DET-5)")

// LibraryModel is main-actor isolated, and so is top-level code.
do {
    let library = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("show-my-best-selftest-\(UUID().uuidString)", isDirectory: true)
    let fileManager = FileManager.default
    for (shoot, file) in [("SL35_Balaton_Szeged_202608", "IMG_0944.jpg"), ("6X6_Szeged_202607", "IMG_1031.jpg"),
                          ("R8_Rovinj_202606", "IMG_2216.JPG"), ("R8_Budapest_202606", "IMG_2216.JPG")] {
        let folder = library.appendingPathComponent(shoot, isDirectory: true)
        try! fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        fileManager.createFile(atPath: folder.appendingPathComponent(file).path, contents: Data())
    }
    try! Data((header
        + "IMG_0944.jpg,SL35_Balaton_Szeged_202608,t,2026-08,4,4,r,available\r\n"
        + "IMG_1031.jpg,6X6_Szeged_202607,t,2026-07,5,4,r,available\r\n").utf8)
        .write(to: library.appendingPathComponent("catalogue.csv"))
    try! Data(("date_submitted,competition_id,competition_name,entry_fee,deadline,photos_submitted,category,recommendation_call,result,notes\r\n"
        + "2026-09-16,x,Exposure One,$27,2026-09-21,IMG_0944.jpg,Film,enter,pending,\r\n"
        + "2026-09-16,x,Exposure One,$27,2026-09-21,6X6_Szeged_202607/IMG_1031.jpg,Fine Art,enter,pending,\r\n"
        + "2026-09-17,y,Other,Free,2026-10-01,IMG_2216.JPG;IMG_9999.jpg,Street,enter,pending,\r\n").utf8)
        .write(to: library.appendingPathComponent("submissions.csv"))

    let model = LibraryModel()
    model.open(folder: library)
    let entries = model.sidecars.submissions.sorted { $0.photoReferences.first ?? "" < $1.photoReferences.first ?? "" }
    @MainActor func keys(_ submission: Submission) -> [String] { model.photos(for: submission).map(\.key.description) }

    let bare = entries.first { $0.photoReferences == ["IMG_0944.jpg"] }
    check(bare.map(keys) == ["SL35_Balaton_Szeged_202608/IMG_0944.jpg"],
          "a bare filename, as the skill wrote it, finds its photo", "\(bare.map(keys) ?? [])")
    let full = entries.first { $0.photoReferences == ["6X6_Szeged_202607/IMG_1031.jpg"] }
    check(full.map(keys) == ["6X6_Szeged_202607/IMG_1031.jpg"], "a shoot/filename reference")
    let ambiguous = entries.first { $0.photoReferences.contains("IMG_2216.JPG") }
    check(ambiguous.map(keys)?.count == 2,
          "a filename in two shoots shows both rather than guessing", "\(ambiguous.map(keys) ?? [])")

    let including = model.submissions(including: PhotoKey(shoot: "SL35_Balaton_Szeged_202608", filename: "IMG_0944.jpg"))
    check(including.count == 1, "the photo's detail finds the entry it was submitted in (DET-5)")

    let summary = model.submissionSummary
    check(summary.feesByCurrency == ["USD": 54], "fees paid adds up $27 twice", "\(summary.feesByCurrency)")

    try? fileManager.removeItem(at: library)
}

await salesChecks()

print("\n\(checks - failures)/\(checks) checks passed")
if failures > 0 {
    print("\(failures) FAILED")
    exit(1)
}
