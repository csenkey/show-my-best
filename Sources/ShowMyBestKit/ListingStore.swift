import Foundation

public enum ListingWriteError: Error, CustomStringConvertible {
    case missingFile
    case unreadable(String)
    case missingColumns([String])
    case notFound([ListingKey])
    case writeFailed(String)

    public var description: String {
        switch self {
        case .missingFile: return "listings.csv is not in the library any more"
        case .unreadable(let reason): return "listings.csv: \(reason)"
        case .missingColumns(let columns): return "listings.csv has no \(columns.joined(separator: ", ")) column"
        case .notFound(let keys):
            return "listings.csv no longer has \(keys.map(\.description).joined(separator: "; "))"
        case .writeFailed(let reason): return "listings.csv could not be written: \(reason)"
        }
    }
}

/// The one thing the app writes about selling: how far a listing has got
/// (S5). Same rules as a rating write — read the file fresh, change only the
/// cells that carry the status, replace the file in one step (SAL-32, SAL-33).
public enum ListingStore {
    @discardableResult
    public static func setStatus(
        _ status: ListingStatus,
        for keys: [ListingKey],
        libraryURL: URL,
        support: SupportFiles,
        today: String = ISODate.today()
    ) throws -> Int {
        guard !keys.isEmpty else { return 0 }
        let url = libraryURL.appendingPathComponent("listings.csv")
        guard FileManager.default.fileExists(atPath: url.path) else { throw ListingWriteError.missingFile }

        var document: CSVDocument
        do {
            document = try CSV.parse(data: try Data(contentsOf: url))
        } catch let error as CSVError {
            throw ListingWriteError.unreadable(error.description)
        } catch {
            throw ListingWriteError.unreadable(error.localizedDescription)
        }

        let required = [ListingColumn.portalID, ListingColumn.sourceFolder, ListingColumn.filename, ListingColumn.status]
        let missing = required.filter { !document.hasColumn($0) }
        guard missing.isEmpty else { throw ListingWriteError.missingColumns(missing) }

        // SAL-32: a date column the skill has not written yet goes on the end.
        if let dateColumn = status.dateColumn { document.addColumns([dateColumn]) }

        let portalColumn = document.columnIndex(ListingColumn.portalID)!
        let shootColumn = document.columnIndex(ListingColumn.sourceFolder)!
        let filenameColumn = document.columnIndex(ListingColumn.filename)!
        let statusColumn = document.columnIndex(ListingColumn.status)!
        let dateColumn = status.dateColumn.flatMap { document.columnIndex($0) }

        var positions: [ListingKey: Int] = [:]
        for (position, record) in document.records.enumerated() {
            let key = ListingKey(
                portalID: record.value(at: portalColumn).trimmingCharacters(in: .whitespaces),
                photo: PhotoKey(shoot: record.value(at: shootColumn).trimmingCharacters(in: .whitespaces),
                                filename: record.value(at: filenameColumn).trimmingCharacters(in: .whitespaces))
            )
            if positions[key] == nil { positions[key] = position }
        }

        let lost = keys.filter { positions[$0] == nil }
        guard lost.isEmpty else { throw ListingWriteError.notFound(lost) }

        var changed = 0
        for key in keys {
            let position = positions[key]!
            let current = document.records[position].value(at: statusColumn).trimmingCharacters(in: .whitespaces)
            guard current.lowercased() != status.rawValue else { continue }
            document.records[position].setValue(status.rawValue, at: statusColumn)
            if let dateColumn { document.records[position].setValue(today, at: dateColumn) }
            changed += 1
        }
        guard changed > 0 else { return 0 }

        support.backupIfFirstWriteToday(url)        // SAL-34
        do {
            try AtomicFile.replace(url, with: document.serialized())
        } catch {
            throw ListingWriteError.writeFailed(error.localizedDescription)
        }
        return changed
    }
}
