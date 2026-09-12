import Foundation
import ShowMyBestKit

/// Read-only report on a real library: AC-8, run without opening the app and
/// without writing a single byte.
///
///     swift run SelfTest --inspect ~/Pictures/6x6Stories/REAL_BEST
enum Inspect {
    static func run(_ path: String) -> Int32 {
        let libraryURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        print("Library: \(libraryURL.path)\n")

        guard let data = try? Data(contentsOf: libraryURL.appendingPathComponent("catalogue.csv")) else {
            print("No catalogue.csv here.")
            return 1
        }

        let document: CSVDocument
        do {
            document = try CSV.parse(data: data)
        } catch let error as CSVError {
            print("catalogue.csv does not parse: \(error.description)")
            return 1
        } catch {
            print("catalogue.csv could not be read: \(error)")
            return 1
        }

        // The one that matters: everything the app does not change must come
        // back out unchanged (RAT-6).
        let roundTrips = document.serialized() == data
        print("catalogue.csv")
        print("  rows              \(document.records.count)")
        print("  columns           \(document.headerNames.count)")
        print("  line ending       \(document.lineEnding == "\r\n" ? "CRLF" : "LF")")
        print("  byte-for-byte     \(roundTrips ? "yes — round-trips exactly" : "NO — THIS IS A BUG")")

        let missingRequired = CatalogueColumn.required.filter { !document.hasColumn($0) }
        print("  required columns  \(missingRequired.isEmpty ? "all present" : "MISSING \(missingRequired.joined(separator: ", "))")")
        let optional = [CatalogueColumn.dateNote, CatalogueColumn.medium,
                        CatalogueColumn.claudeCritique, CatalogueColumn.critiqueForRating]
        let absent = optional.filter { !document.hasColumn($0) }
        if !absent.isEmpty {
            print("  not yet written   \(absent.joined(separator: ", ")) — those features stay hidden (SYN-5)")
        }

        // What the app would show, without touching anything.
        let scanned = LibraryScanner.scan(libraryURL)
        print("\nOn disk")
        print("  shoots            \(scanned.shootNames.count)")
        print("  photos            \(scanned.photoCount)")
        for shoot in scanned.shootNames {
            let count = scanned.shoots[shoot]?.count ?? 0
            let month = LibraryScanner.monthFromShootName(shoot).map { " (\($0))" } ?? " (no _YYYYMM suffix)"
            print(String(format: "    %-34@ %4d%@", shoot as NSString, count, month as NSString))
        }

        let store = CatalogueStore(libraryURL: libraryURL)
        store.reload()
        var onDisk: Set<PhotoKey> = []
        for shoot in scanned.shootNames {
            for url in scanned.shoots[shoot] ?? [] {
                onDisk.insert(PhotoKey(shoot: shoot, filename: url.lastPathComponent))
            }
        }
        let rows = store.rows
        let notCatalogued = onDisk.filter { rows[$0] == nil }
        let missingFiles = store.rowOrder.filter { !onDisk.contains($0) }
        let ratedByIstvan = rows.values.filter { $0.istvanRating != nil }
        let ratedByClaude = rows.values.filter { $0.claudeRating != nil }
        let revealed = rows.values.filter { $0.istvanRating != nil && $0.claudeRating != nil }
        let disagreements = revealed.filter { abs(($0.istvanRating ?? 0) - ($0.claudeRating ?? 0)) >= 2 }
        let unreadableDates = rows.values.filter { !$0.dateTaken.isEmpty && !ISODate.isValid($0.dateTaken) }

        print("\nWhat the gallery would show")
        print("  rated by you      \(ratedByIstvan.count)")
        print("  rated by Claude   \(ratedByClaude.count)")
        print("  revealed (both)   \(revealed.count)")
        print("  disagreements     \(disagreements.count)   (2 or more apart, among revealed)")
        print("  hidden by IND-1   \(ratedByClaude.count - revealed.count)   Claude has rated these, you have not")
        print("  not catalogued    \(notCatalogued.count)")
        print("  missing files     \(missingFiles.count)")
        print("  dates as text     \(unreadableDates.count)   not FMT-6, so shown as written and sorted last (SYN-5)")

        if !missingFiles.isEmpty {
            print("\n  rows with no photo on disk:")
            for key in missingFiles.prefix(10) { print("    \(key)") }
            if missingFiles.count > 10 { print("    … \(missingFiles.count - 10) more") }
        }
        if !notCatalogued.isEmpty {
            print("\n  photos with no catalogue row:")
            for key in notCatalogued.sorted(by: { $0.description < $1.description }).prefix(10) { print("    \(key)") }
            if notCatalogued.count > 10 { print("    … \(notCatalogued.count - 10) more") }
        }

        let sidecars = SidecarLoader.load(libraryURL: libraryURL)
        print("\nSidecar files")
        print("  competitions.csv  \(sidecars.competitionsFileExists ? "\(sidecars.competitions.count) competitions" : "not there yet — the competitions view says so (CMP-8)")")
        print("  matches           \(sidecars.matches.count)")
        print("  submissions.csv   \(sidecars.submissionsFileExists ? "\(sidecars.submissions.count) entries" : "not there yet (SUB-6)")")
        for error in sidecars.errors { print("  ! \(error)") }

        print("\nNothing was written.")
        return roundTrips && missingRequired.isEmpty ? 0 : 1
    }
}
