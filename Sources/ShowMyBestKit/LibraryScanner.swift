import Foundation

public enum LibraryLocation {
    /// The folder is a library; a shoot is named when Istvan picked one (LIB-2).
    case library(URL, selectedShoot: String?)
    /// Neither the folder nor its parent holds a catalogue (LIB-3).
    case noCatalogue(URL)
}

public enum LibraryLocator {
    public static func resolve(chosen url: URL) -> LibraryLocation {
        let folder = url.standardizedFileURL
        if hasCatalogue(folder) { return .library(folder, selectedShoot: nil) }
        let parent = folder.deletingLastPathComponent()
        if hasCatalogue(parent) { return .library(parent, selectedShoot: folder.lastPathComponent) }
        return .noCatalogue(folder)
    }

    public static func hasCatalogue(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("catalogue.csv").path)
    }
}

public struct ScannedLibrary {
    /// Shoot folder name to the photo files inside it, filename-sorted.
    public var shoots: [String: [URL]] = [:]
    public var shootNames: [String] = []

    public var photoCount: Int { shoots.values.reduce(0) { $0 + $1.count } }
}

public enum LibraryScanner {
    /// LIB-5: the photo extensions, in any letter case.
    static let photoExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tif", "tiff"]

    /// Walks the library one level down. Everything that is not a shoot folder
    /// or a photo inside one is ignored (LIB-9); nothing is ever written or
    /// moved (NFR-3).
    public static func scan(_ libraryURL: URL) -> ScannedLibrary {
        var result = ScannedLibrary()
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return result }

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            // LIB-4: a shoot is a direct subfolder not starting with _ or .
            guard !name.hasPrefix("_"), !name.hasPrefix(".") else { continue }
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let photos = photoFiles(in: entry)
            result.shoots[name] = photos
            result.shootNames.append(name)
        }
        return result
    }

    static func photoFiles(in shootURL: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: shootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }
        return entries
            .filter { photoExtensions.contains($0.pathExtension.lowercased()) }
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// The `_YYYYMM` a shoot folder name ends in, used as the month taken when
    /// the catalogue has no usable date (SKL-21 is the skill's side of this).
    public static func monthFromShootName(_ name: String) -> String? {
        guard let underscore = name.lastIndex(of: "_") else { return nil }
        let suffix = String(name[name.index(after: underscore)...])
        guard suffix.count == 6, suffix.allSatisfy(\.isNumber) else { return nil }
        let year = suffix.prefix(4)
        let month = suffix.suffix(2)
        guard let monthValue = Int(month), (1...12).contains(monthValue) else { return nil }
        return "\(year)-\(month)"
    }
}
