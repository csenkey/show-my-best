import Foundation

/// Everything the app keeps outside the library: the daily backups (RAT-10),
/// the rating log (RAT-11) and the changes waiting to be written (RAT-9).
/// Each library gets its own folder, so switching libraries keeps them apart.
public final class SupportFiles {
    public let root: URL
    public let backupsURL: URL
    public let logURL: URL
    public let pendingURL: URL

    private let fileManager = FileManager.default
    private static let maximumBackups = 30

    public init(libraryURL: URL) {
        let base: URL
        if let override = ProcessInfo.processInfo.environment["SHOWMYBEST_SUPPORT_ROOT"] {
            base = URL(fileURLWithPath: override, isDirectory: true)   // used by the self-test
        } else {
            base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        }
        let libraries = base.appendingPathComponent("ShowMyBest/libraries", isDirectory: true)
        self.root = libraries.appendingPathComponent(SupportFiles.folderName(for: libraryURL), isDirectory: true)
        self.backupsURL = root.appendingPathComponent("backups", isDirectory: true)
        self.logURL = root.appendingPathComponent("rating-log.jsonl")
        self.pendingURL = root.appendingPathComponent("pending-ratings.json")
        try? fileManager.createDirectory(at: backupsURL, withIntermediateDirectories: true)
    }

    /// Readable, and unique for the path.
    private static func folderName(for libraryURL: URL) -> String {
        let name = libraryURL.lastPathComponent.replacingOccurrences(of: "/", with: "-")
        var hash: UInt64 = 5381
        for byte in libraryURL.standardizedFileURL.path.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return "\(name)-\(String(hash, radix: 36))"
    }

    // MARK: Pending changes (RAT-9)

    public func loadPending() -> [PendingRating] {
        guard let data = try? Data(contentsOf: pendingURL) else { return [] }
        return (try? JSONDecoder().decode([PendingRating].self, from: data)) ?? []
    }

    public func savePending(_ pending: [PendingRating]) {
        if pending.isEmpty {
            try? fileManager.removeItem(at: pendingURL)
            return
        }
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: pendingURL, options: .atomic)
    }

    // MARK: Rating log (RAT-11)

    public func appendLog(_ entries: [RatingLogEntry]) {
        guard !entries.isEmpty else { return }
        let encoder = JSONEncoder()
        var text = ""
        for entry in entries {
            guard let data = try? encoder.encode(entry), let line = String(data: data, encoding: .utf8) else { continue }
            text += line + "\n"
        }
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }

    public func loadLog() -> [RatingLogEntry] {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(RatingLogEntry.self, from: data)
        }
    }

    // MARK: Backups (RAT-10)

    /// Copies a library file aside once a day, before the first write
    /// (RAT-10, SAL-34): `catalogue-2026-09-16.csv`, `listings-2026-09-16.csv`.
    public func backupIfFirstWriteToday(_ fileURL: URL) {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let destination = backupsURL.appendingPathComponent("\(stem)-\(ISODate.today()).\(fileURL.pathExtension)")
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try? fileManager.copyItem(at: fileURL, to: destination)
        pruneBackups(prefix: "\(stem)-")
    }

    private func pruneBackups(prefix: String) {
        guard let files = try? fileManager.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: nil) else { return }
        let copies = files.filter { $0.lastPathComponent.hasPrefix(prefix) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard copies.count > SupportFiles.maximumBackups else { return }
        for file in copies.prefix(copies.count - SupportFiles.maximumBackups) {
            try? fileManager.removeItem(at: file)
        }
    }
}
