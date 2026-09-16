import Foundation

/// A rating change the app wants on disk but has not managed to write yet
/// (RAT-8, RAT-9).
public struct PendingRating: Codable, Equatable {
    public var shoot: String
    public var filename: String
    public var rating: Int?
    public var queuedAt: String

    public var key: PhotoKey { PhotoKey(shoot: shoot, filename: filename) }

    public init(key: PhotoKey, rating: Int?, queuedAt: String = ISODate.timestamp()) {
        self.shoot = key.shoot
        self.filename = key.filename
        self.rating = rating
        self.queuedAt = queuedAt
    }
}

/// One line of the rating log (RAT-11), also what RAT-12's restore reads back.
public struct RatingLogEntry: Codable {
    public var at: String
    public var shoot: String
    public var filename: String
    public var from: Int?
    public var to: Int?

    public var key: PhotoKey { PhotoKey(shoot: shoot, filename: filename) }
    public var date: Date? { ISODate.parse(at) }
}

public struct RestoredRating {
    public var key: PhotoKey
    public var rating: Int?
    public var foundInstead: Int?
}

/// Reads `catalogue.csv`, and writes Istvan's ratings back to it under the
/// rules in 4.5: fresh read before every write, only `istvan_rating` cells and
/// appended rows change, and the replacement is atomic.
public final class CatalogueStore {
    public let libraryURL: URL
    public let support: SupportFiles

    public private(set) var document: CSVDocument?
    public private(set) var rows: [PhotoKey: CatalogueRow] = [:]
    public private(set) var rowOrder: [PhotoKey] = []
    /// Set when the file on disk cannot be used; the last good data stays
    /// loaded (SYN-3).
    public private(set) var loadError: String?
    public private(set) var pending: [PendingRating] = []
    /// Columns the skill has not added yet, so the app can hide what needs
    /// them (SYN-5).
    public private(set) var missingOptionalColumns: [String] = []

    public var catalogueURL: URL { libraryURL.appendingPathComponent("catalogue.csv") }
    public var hasCritiqueColumns: Bool {
        guard let document else { return false }
        return document.hasColumn(CatalogueColumn.claudeCritique)
            && document.hasColumn(CatalogueColumn.critiqueForRating)
    }
    public var hasMediumColumn: Bool { document?.hasColumn(CatalogueColumn.medium) ?? false }

    public init(libraryURL: URL) {
        self.libraryURL = libraryURL
        self.support = SupportFiles(libraryURL: libraryURL)
        self.pending = support.loadPending()
    }

    // MARK: Reading

    /// Re-reads the file. Returns the ratings RAT-12 had to put back, if any.
    @discardableResult
    public func reload() -> [RestoredRating] {
        do {
            let data = try Data(contentsOf: catalogueURL)
            let document = try CSV.parse(data: data)
            let missingRequired = CatalogueColumn.required.filter { !document.hasColumn($0) }
            guard missingRequired.isEmpty else {
                loadError = "catalogue.csv has no \(missingRequired.joined(separator: ", ")) column"
                return []
            }
            apply(document: document)
            loadError = nil
            let restored = detectOverwrittenRatings()
            if !pending.isEmpty { _ = flush() }
            return restored
        } catch let error as CSVError {
            loadError = "catalogue.csv: \(error.description)"
            return []
        } catch {
            loadError = "catalogue.csv could not be read: \(error.localizedDescription)"
            return []
        }
    }

    private func apply(document: CSVDocument) {
        var rows: [PhotoKey: CatalogueRow] = [:]
        var order: [PhotoKey] = []
        let index = ColumnIndex(document: document)

        for (position, record) in document.records.enumerated() {
            let filename = index.value(CatalogueColumn.filename, record)
            let shoot = index.value(CatalogueColumn.sourceFolder, record)
            guard !filename.isEmpty else { continue }
            let key = PhotoKey(shoot: shoot, filename: filename)
            var row = CatalogueRow(key: key, recordIndex: position)
            row.title = index.value(CatalogueColumn.title, record)
            row.dateTaken = index.value(CatalogueColumn.dateTaken, record)
            row.dateNote = index.value(CatalogueColumn.dateNote, record)
            row.medium = index.value(CatalogueColumn.medium, record)
            row.cameraOrFormat = index.value(CatalogueColumn.cameraOrFormat, record)
            row.genreTags = index.value(CatalogueColumn.genreTags, record)
            row.subject = index.value(CatalogueColumn.subject, record)
            row.istvanRating = rating(index.value(CatalogueColumn.istvanRating, record))
            row.claudeRating = rating(index.value(CatalogueColumn.claudeRating, record))
            row.claudeRationale = index.value(CatalogueColumn.claudeRationale, record)
            row.claudeCritique = index.value(CatalogueColumn.claudeCritique, record)
            row.critiqueForRating = rating(index.value(CatalogueColumn.critiqueForRating, record))
            row.competitionFitNotes = index.value(CatalogueColumn.competitionFitNotes, record)
            row.status = index.value(CatalogueColumn.status, record)
            row.lastUpdated = index.value(CatalogueColumn.lastUpdated, record)
            // A duplicate photo key should not happen; the first row wins.
            if rows[key] == nil {
                rows[key] = row
                order.append(key)
            }
        }

        self.document = document
        self.rows = rows
        self.rowOrder = order
        self.missingOptionalColumns = [
            CatalogueColumn.dateNote, CatalogueColumn.medium,
            CatalogueColumn.claudeCritique, CatalogueColumn.critiqueForRating,
        ].filter { !document.hasColumn($0) }
    }

    private func rating(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), (1...5).contains(value) else { return nil }
        return value
    }

    /// The rating the app believes in: what is pending if anything is, else the
    /// file. Keeps the interface honest while a write is held up (RAT-8).
    public func effectiveRating(for key: PhotoKey) -> Int? {
        if let queued = pending.last(where: { $0.key == key }) { return queued.rating }
        return rows[key]?.istvanRating
    }

    // MARK: Writing

    public enum FlushResult {
        case nothingToDo
        case written(count: Int)
        case failed(reason: String)
    }

    /// Queues a rating change and tries to write it straight away (RAT-2).
    @discardableResult
    public func setRating(_ rating: Int?, for key: PhotoKey) -> FlushResult {
        pending.removeAll { $0.key == key }
        pending.append(PendingRating(key: key, rating: rating))
        support.savePending(pending)
        return flush()
    }

    /// RAT-4: read the file again, apply the pending changes to that copy, and
    /// replace the file in one step (RAT-7).
    @discardableResult
    public func flush() -> FlushResult {
        guard !pending.isEmpty else { return .nothingToDo }

        let fresh: CSVDocument
        do {
            let data = try Data(contentsOf: catalogueURL)
            fresh = try CSV.parse(data: data)
        } catch let error as CSVError {
            let reason = "catalogue.csv: \(error.description)"
            loadError = reason
            return .failed(reason: reason)
        } catch {
            let reason = "catalogue.csv could not be read: \(error.localizedDescription)"
            loadError = reason
            return .failed(reason: reason)
        }

        let missingRequired = CatalogueColumn.required.filter { !fresh.hasColumn($0) }
        guard missingRequired.isEmpty else {
            let reason = "catalogue.csv has no \(missingRequired.joined(separator: ", ")) column"
            loadError = reason
            return .failed(reason: reason)
        }
        guard let ratingColumn = fresh.columnIndex(CatalogueColumn.istvanRating),
              let filenameColumn = fresh.columnIndex(CatalogueColumn.filename),
              let shootColumn = fresh.columnIndex(CatalogueColumn.sourceFolder) else {
            return .failed(reason: "catalogue.csv is missing a required column")
        }

        var document = fresh
        var positions: [PhotoKey: Int] = [:]
        for (position, record) in document.records.enumerated() {
            let key = PhotoKey(
                shoot: record.value(at: shootColumn).trimmingCharacters(in: .whitespaces),
                filename: record.value(at: filenameColumn).trimmingCharacters(in: .whitespaces)
            )
            if positions[key] == nil { positions[key] = position }
        }

        support.backupIfFirstWriteToday(catalogueURL)

        var logEntries: [RatingLogEntry] = []
        for change in pending {
            let text = change.rating.map(String.init) ?? ""
            if let position = positions[change.key] {
                let previous = rating(document.records[position].value(at: ratingColumn))
                guard previous != change.rating else { continue }
                document.records[position].setValue(text, at: ratingColumn)
                logEntries.append(RatingLogEntry(at: ISODate.timestamp(), shoot: change.key.shoot,
                                                 filename: change.key.filename, from: previous, to: change.rating))
            } else {
                // RAT-3: a photo the skill has not catalogued gets a minimal row.
                if let last = document.records.indices.last {
                    document.records[last].appendTerminator(document.lineEnding)
                }
                let record = document.makeRecord([
                    CatalogueColumn.filename: change.key.filename,
                    CatalogueColumn.sourceFolder: change.key.shoot,
                    CatalogueColumn.istvanRating: text,
                    CatalogueColumn.status: "available",
                ])
                document.records.append(record)
                positions[change.key] = document.records.count - 1
                logEntries.append(RatingLogEntry(at: ISODate.timestamp(), shoot: change.key.shoot,
                                                 filename: change.key.filename, from: nil, to: change.rating))
            }
        }

        do {
            try writeAtomically(document.serialized())
        } catch {
            return .failed(reason: "catalogue.csv could not be written: \(error.localizedDescription)")
        }

        support.appendLog(logEntries)
        pending.removeAll()
        support.savePending(pending)
        apply(document: document)
        loadError = nil
        return .written(count: logEntries.count)
    }

    /// RAT-7: a temporary file beside the catalogue, then an atomic replace, so
    /// no reader ever sees half a file.
    private func writeAtomically(_ data: Data) throws {
        try AtomicFile.replace(catalogueURL, with: data)
    }

    // MARK: RAT-12 — putting back ratings something else overwrote

    private func detectOverwrittenRatings() -> [RestoredRating] {
        let log = support.loadLog()
        guard !log.isEmpty else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast

        var latest: [PhotoKey: RatingLogEntry] = [:]
        for entry in log {
            guard let date = entry.date, date >= cutoff else { continue }
            latest[entry.key] = entry   // the log is in order, so the last wins
        }

        var restored: [RestoredRating] = []
        for (key, entry) in latest {
            guard let row = rows[key] else { continue }
            guard row.istvanRating != entry.to else { continue }
            // Only when it went back to exactly what it was before the app
            // changed it: anything else is a value the app did not write.
            guard row.istvanRating == entry.from else { continue }
            guard !pending.contains(where: { $0.key == key }) else { continue }
            pending.append(PendingRating(key: key, rating: entry.to))
            restored.append(RestoredRating(key: key, rating: entry.to, foundInstead: row.istvanRating))
        }
        if !restored.isEmpty { support.savePending(pending) }
        return restored
    }
}

/// A temporary file beside the target, then a replace in one step (FMT-9).
/// RAT-13 and SAL-32: the catalogue and the listings are the only files the
/// app writes in the library.
enum AtomicFile {
    static func replace(_ url: URL, with data: Data) throws {
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).showmybest-tmp")
        try data.write(to: temporaryURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: url)
        }
    }

    /// Puts a finished temporary file in place, replacing what is there.
    static func move(_ temporaryURL: URL, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: url)
        }
    }
}

/// Column positions looked up by name, never by position (FMT-4).
struct ColumnIndex {
    private var indices: [String: Int] = [:]

    init(document: CSVDocument) {
        for (position, name) in document.headerNames.enumerated() where indices[name] == nil {
            indices[name] = position
        }
    }

    func value(_ column: String, _ record: CSVRecord) -> String {
        guard let position = indices[column] else { return "" }
        return record.value(at: position).trimmingCharacters(in: .whitespaces)
    }
}
