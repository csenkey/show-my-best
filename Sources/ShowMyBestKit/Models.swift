import Foundation

/// Shoot folder name plus filename: unique within a library (LIB-6).
public struct PhotoKey: Hashable, Codable, Identifiable, CustomStringConvertible {
    public let shoot: String
    public let filename: String

    public init(shoot: String, filename: String) {
        self.shoot = shoot
        self.filename = filename
    }

    /// The `source_folder/filename` reference form (FMT-7).
    public init?(reference: String) {
        guard let slash = reference.lastIndex(of: "/") else { return nil }
        let shoot = String(reference[reference.startIndex..<slash])
        let filename = String(reference[reference.index(after: slash)...])
        guard !shoot.isEmpty, !filename.isEmpty else { return nil }
        self.init(shoot: shoot, filename: filename)
    }

    public var description: String { "\(shoot)/\(filename)" }
    public var id: String { description }
}

/// The catalogue columns (6.2). Values the app never writes stay as read.
public enum CatalogueColumn {
    public static let filename = "filename"
    public static let sourceFolder = "source_folder"
    public static let title = "title"
    public static let dateTaken = "date_taken"
    public static let dateNote = "date_note"
    public static let medium = "medium"
    public static let cameraOrFormat = "camera_or_format"
    public static let genreTags = "genre_tags"
    public static let subject = "subject"
    public static let istvanRating = "istvan_rating"
    public static let claudeRating = "claude_rating"
    public static let claudeRationale = "claude_rationale"
    public static let claudeCritique = "claude_critique"
    public static let critiqueForRating = "critique_for_rating"
    public static let competitionFitNotes = "competition_fit_notes"
    public static let status = "status"
    public static let lastUpdated = "last_updated"

    /// Without these the file is unreadable for rating (RAT-8, FMT-10).
    public static let required = [filename, sourceFolder, istvanRating, claudeRating, status]
}

/// One row of `catalogue.csv`, decoded.
public struct CatalogueRow {
    public var key: PhotoKey
    public var title = ""
    public var dateTaken = ""
    public var dateNote = ""
    public var medium = ""
    public var cameraOrFormat = ""
    public var genreTags = ""
    public var subject = ""
    public var istvanRating: Int?
    public var claudeRating: Int?
    public var claudeRationale = ""
    public var claudeCritique = ""
    public var critiqueForRating: Int?
    public var competitionFitNotes = ""
    public var status = ""
    public var lastUpdated = ""
    /// Position in the document, so a write can find the record again.
    public var recordIndex: Int

    public init(key: PhotoKey, recordIndex: Int) {
        self.key = key
        self.recordIndex = recordIndex
    }

    public var tags: [String] {
        genreTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// A photo as the app shows it: what is on disk, what the catalogue says, or both.
public struct Photo: Identifiable {
    public var key: PhotoKey
    /// Nil when the row has no file on disk (LIB-8).
    public var url: URL?
    /// Nil when the file has no catalogue row (LIB-7).
    public var row: CatalogueRow?

    public init(key: PhotoKey, url: URL? = nil, row: CatalogueRow? = nil) {
        self.key = key
        self.url = url
        self.row = row
    }

    public var id: PhotoKey { key }
    public var filename: String { key.filename }
    public var shoot: String { key.shoot }
    public var isCatalogued: Bool { row != nil }
    public var isOnDisk: Bool { url != nil }

    public var istvanRating: Int? { row?.istvanRating }
    public var title: String { row?.title ?? "" }

    /// The heart of the product (D14): Claude's evaluation exists for the app
    /// only once Istvan has rated the photo (IND-1, IND-5).
    public var isRevealed: Bool { istvanRating != nil }

    /// Claude's rating, or nil when the photo is not revealed. Every read of
    /// Claude's evaluation goes through these, so there is no path that shows
    /// it for an unrated photo (IND-6).
    public var claudeRating: Int? { isRevealed ? row?.claudeRating : nil }
    public var claudeRationale: String { isRevealed ? (row?.claudeRationale ?? "") : "" }
    public var claudeCritique: String { isRevealed ? (row?.claudeCritique ?? "") : "" }
    public var competitionFitNotes: String { isRevealed ? (row?.competitionFitNotes ?? "") : "" }

    public var hasCritique: Bool { !claudeCritique.isEmpty }

    /// A critique written against a different rating than today's (IND-7).
    public var critiqueIsOutOfDate: Bool {
        guard hasCritique, let written = row?.critiqueForRating else { return false }
        return written != istvanRating
    }

    public var critiqueWrittenForRating: Int? { isRevealed ? row?.critiqueForRating : nil }

    /// Rated by Istvan, not yet rated by Claude.
    public var isWaitingForClaude: Bool { isRevealed && row?.claudeRating == nil }

    /// Both ratings present and two or more apart.
    public var disagreement: Int? {
        guard let mine = istvanRating, let theirs = claudeRating else { return nil }
        return abs(mine - theirs)
    }

    public var isFilm: Bool { (row?.medium ?? "").lowercased() == "film" }
    public var tags: [String] { row?.tags ?? [] }
    public var status: String { row?.status ?? "" }
}

// MARK: - Competitions

public struct Competition: Identifiable {
    public var id: String            // competition_id
    public var name = ""
    public var organizer = ""
    public var url = ""
    public var categories: [String] = []
    public var opens: String = ""
    public var deadline: String = ""
    public var deadlineNote = ""
    public var entryFee = ""
    public var feeAmount: Double?
    public var feeCurrency = ""
    public var tier = ""
    public var eligibility = ""
    public var captureDateRule = ""
    public var previouslyUnpublished = ""
    public var prize = ""
    public var rightsFlag = ""
    public var rightsNotes = ""
    public var recommendationCall = ""
    public var reasoning = ""
    public var lastChecked = ""

    public init(id: String) { self.id = id }

    public enum Status {
        case notOpenYet, open, closingSoon, closed

        public var label: String {
            switch self {
            case .notOpenYet: return "Not open yet"
            case .open: return "Open"
            case .closingSoon: return "Closing soon"
            case .closed: return "Closed"
            }
        }
    }

    public var deadlineDate: Date? { ISODate.parse(deadline) }
    public var opensDate: Date? { ISODate.parse(opens) }

    /// Worked out from the dates, never stored (CMP-2).
    public func status(on today: Date = Date()) -> Status {
        guard let deadline = deadlineDate else { return .open }
        let daysLeft = ISODate.days(from: today, to: deadline)
        if daysLeft < 0 { return .closed }
        if let opens = opensDate, ISODate.days(from: today, to: opens) > 0 { return .notOpenYet }
        return daysLeft <= 7 ? .closingSoon : .open
    }

    public func daysLeft(on today: Date = Date()) -> Int? {
        guard let deadline = deadlineDate else { return nil }
        return ISODate.days(from: today, to: deadline)
    }

    /// CMP-7: details older than a fortnight are worth re-checking.
    public func needsRecheck(on today: Date = Date()) -> Bool {
        guard let checked = ISODate.parse(lastChecked) else { return false }
        return ISODate.days(from: checked, to: today) > 14
    }

    public var rightsIsGrab: Bool { rightsFlag.lowercased() == "rights-grab" }
    public var rightsIsCaution: Bool { rightsFlag.lowercased() == "caution" }

    public var callLabel: String {
        switch recommendationCall.lowercased() {
        case "enter": return "Enter"
        case "skip": return "Skip"
        case "worth-it-regardless": return "Worth it regardless"
        default: return recommendationCall
        }
    }

    public var isFree: Bool {
        if let amount = feeAmount { return amount == 0 }
        return entryFee.lowercased().contains("free")
    }
}

public struct CompetitionMatch: Identifiable {
    public var competitionID: String
    public var key: PhotoKey
    public var category = ""
    public var role = ""             // primary | alternate
    public var reason = ""
    public var matchedOn = ""

    public init(competitionID: String, key: PhotoKey) {
        self.competitionID = competitionID
        self.key = key
    }

    public var id: String { "\(competitionID)|\(key)" }
    public var isPrimary: Bool { role.lowercased() == "primary" }
}

public struct Submission: Identifiable {
    public var id = UUID()
    public var dateSubmitted = ""
    public var competitionID = ""
    public var competitionName = ""
    public var entryFee = ""
    public var deadline = ""
    /// `photos_submitted` exactly as written, one name per entry. FMT-7 asks
    /// for `shoot/filename`, but a bare filename turns up too, so these are
    /// resolved against the library rather than parsed as keys here — see
    /// `LibraryModel.photos(for:)`.
    public var photoReferences: [String] = []
    public var category = ""
    public var recommendationCall = ""
    public var result = ""
    public var notes = ""

    public init() {}

    /// SUB-2: the four fixed values, shown as labels.
    public var resultLabel: String {
        switch result.lowercased() {
        case "pending": return "Pending"
        case "won": return "Won"
        case "placed": return "Placed"
        case "no-award": return "No award"
        default: return result.isEmpty ? "—" : result
        }
    }
}

// MARK: - Dates

/// FMT-6 dates: `YYYY`, `YYYY-MM`, `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM:SS`.
public enum ISODate {
    public static func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let datePart = trimmed.split(separator: "T").first.map(String.init) ?? trimmed
        let parts = datePart.split(separator: "-").map(String.init)
        guard let year = Int(parts.first ?? ""), parts[0].count == 4 else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = parts.count > 1 ? Int(parts[1]) : 1
        components.day = parts.count > 2 ? Int(parts[2]) : 1
        guard components.month != nil, components.day != nil else { return nil }
        return Calendar.current.date(from: components)
    }

    /// True when the text is a date the app can sort by; anything else is shown
    /// as written and sorted last (SYN-5).
    public static func isValid(_ text: String) -> Bool { parse(text) != nil }

    public static func days(from: Date, to: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    public static func today() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    public static func timestamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
