import Foundation

/// Finding photos by the names they go by in conversation.
///
/// Claude refers to photos by filename — `IMG_9786`, `IMG_9786.JPG`, or the
/// full `R8_Budapest_202606/IMG_9786.JPG` reference (FMT-7) — usually several
/// in one paragraph. So a query is read for every name in it, and a whole
/// pasted message finds every photo it mentions. Only when a query holds no
/// name at all is it treated as text to look for in titles, filenames and
/// shoots.
public enum PhotoFinder {

    public struct Match {
        /// The name as it was written in the query.
        public var name: String
        /// More than one when the same filename is in several shoots (LIB-6).
        public var photos: [Photo]
    }

    public struct Result {
        public var matches: [Match] = []
        /// Names from the query that are not in the library, so a typo or a
        /// photo that was moved does not just silently vanish from the list.
        public var notFound: [String] = []
        /// Title, filename and shoot matches, when the query named no photo.
        public var textMatches: [Photo] = []

        public var isEmpty: Bool { matches.isEmpty && notFound.isEmpty && textMatches.isEmpty }

        /// Every photo found, in the order they were mentioned, each once.
        public var photos: [Photo] {
            var seen: Set<PhotoKey> = []
            return (matches.flatMap(\.photos) + textMatches).filter { seen.insert($0.key).inserted }
        }
    }

    private static let extensions = "jpe?g|png|heic|tiff?"

    /// `shoot/filename.ext`
    private static let referencePattern = try! NSRegularExpression(
        pattern: "([A-Za-z0-9][A-Za-z0-9_\\-]*)/([A-Za-z0-9_\\-]+\\.(?:\(extensions)))",
        options: [.caseInsensitive]
    )
    /// `filename.ext`
    private static let filenamePattern = try! NSRegularExpression(
        pattern: "(?<![A-Za-z0-9_/\\-])([A-Za-z0-9_\\-]+\\.(?:\(extensions)))(?![A-Za-z0-9])",
        options: [.caseInsensitive]
    )
    /// `IMG_9786`, `DSC_0012`, `IMG-0412`: camera stems, written without an extension.
    private static let stemPattern = try! NSRegularExpression(
        pattern: "(?<![A-Za-z0-9_/\\-])([A-Za-z]{2,6}[_\\-]\\d{2,})(?![A-Za-z0-9_\\-.])",
        options: []
    )

    public static func find(_ query: String, in photos: [Photo]) -> Result {
        var result = Result()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return result }

        let names = names(in: trimmed)
        if !names.isEmpty {
            for name in names {
                let found = photos.filter { matches(name, $0) }
                if found.isEmpty {
                    result.notFound.append(name.text)
                } else {
                    result.matches.append(Match(name: name.text, photos: sortedByShoot(found)))
                }
            }
            return result
        }

        // A bare number is almost always the end of a camera filename:
        // typing "9786" should find IMG_9786. Only for a query that is nothing
        // but the number, though — inside a pasted message, "2026" is a year.
        if trimmed.allSatisfy(\.isNumber), trimmed.count >= 3 {
            let found = photos.filter { stem(of: $0.filename).hasSuffix(trimmed) }
            if found.isEmpty {
                result.notFound.append(trimmed)
            } else {
                result.matches.append(Match(name: trimmed, photos: sortedByShoot(found)))
            }
            return result
        }

        guard trimmed.count >= 2 else { return result }
        let needle = fold(trimmed)
        result.textMatches = sortedByShoot(photos.filter { photo in
            fold(photo.filename).contains(needle)
                || fold(photo.title).contains(needle)
                || fold(photo.shoot).contains(needle)
        })
        return result
    }

    // MARK: Reading names out of the query

    private enum Name {
        case reference(shoot: String, filename: String, text: String)
        case filename(String)
        case stem(String)

        var text: String {
            switch self {
            case .reference(_, _, let text): return text
            case .filename(let name), .stem(let name): return name
            }
        }
    }

    /// Every photo name in the query, in the order written, each once. A
    /// longer form wins over a shorter one inside it: the stem inside
    /// `R8_Budapest_202606/IMG_9786.JPG` is not counted again.
    private static func names(in query: String) -> [Name] {
        let whole = NSRange(query.startIndex..., in: query)
        var claimed: [NSRange] = []
        var found: [(location: Int, name: Name)] = []

        func unclaimed(_ range: NSRange) -> Bool {
            !claimed.contains { NSIntersectionRange($0, range).length > 0 }
        }

        for match in referencePattern.matches(in: query, range: whole) {
            guard let shootRange = Range(match.range(at: 1), in: query),
                  let fileRange = Range(match.range(at: 2), in: query),
                  let textRange = Range(match.range, in: query) else { continue }
            claimed.append(match.range)
            found.append((match.range.location, .reference(
                shoot: String(query[shootRange]), filename: String(query[fileRange]), text: String(query[textRange])
            )))
        }
        for match in filenamePattern.matches(in: query, range: whole) where unclaimed(match.range) {
            guard let range = Range(match.range(at: 1), in: query) else { continue }
            claimed.append(match.range)
            found.append((match.range.location, .filename(String(query[range]))))
        }
        for match in stemPattern.matches(in: query, range: whole) where unclaimed(match.range) {
            guard let range = Range(match.range(at: 1), in: query) else { continue }
            claimed.append(match.range)
            found.append((match.range.location, .stem(String(query[range]))))
        }

        var seen: Set<String> = []
        return found
            .sorted { $0.location < $1.location }
            .map(\.name)
            .filter { seen.insert($0.text.lowercased()).inserted }
    }

    private static func matches(_ name: Name, _ photo: Photo) -> Bool {
        switch name {
        case .reference(let shoot, let filename, _):
            return photo.shoot.caseInsensitiveCompare(shoot) == .orderedSame
                && photo.filename.caseInsensitiveCompare(filename) == .orderedSame
        case .filename(let filename):
            return photo.filename.caseInsensitiveCompare(filename) == .orderedSame
        case .stem(let stemText):
            // Separators are loose in conversation: IMG_9786 and IMG-9786.
            return normalisedStem(stem(of: photo.filename)) == normalisedStem(stemText)
        }
    }

    // MARK: Helpers

    private static func stem(of filename: String) -> String {
        guard let dot = filename.lastIndex(of: ".") else { return filename }
        return String(filename[..<dot])
    }

    private static func normalisedStem(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "-", with: "_")
    }

    /// Case and accents both ignored, so "zebegeny" finds "Zebegényi hídnál".
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func sortedByShoot(_ photos: [Photo]) -> [Photo] {
        photos.sorted {
            $0.shoot == $1.shoot
                ? $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
                : $0.shoot < $1.shoot
        }
    }
}
