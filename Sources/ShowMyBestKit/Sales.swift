import Foundation

// The selling side (docs/sales-spec.md): the portals the skill researched, the
// photos it proposes for each, and the sales Istvan reported.

public struct Portal: Identifiable {
    public var id: String                 // portal_id
    public var name = ""
    public var kind = ""                  // stock | print-on-demand | gallery | own-shop
    public var url = ""
    public var signupURL = ""
    public var uploadURL = ""
    public var accountStatus = ""         // none | applied | active | rejected | closed
    public var exclusivity = ""           // non-exclusive | exclusive
    public var commission = ""
    public var payout = ""
    public var minMegapixels: Double?
    public var maxLongEdge: Int?
    public var maxKeywords: Int?
    public var maxTitleChars: Int?
    public var editorial = ""
    public var filmScans = ""
    public var termsFlag = ""             // ok | caution | rights-grab
    public var termsNotes = ""
    public var recommendationCall = ""    // join | later | skip
    public var reasoning = ""
    public var lastChecked = ""

    public init(id: String) { self.id = id }

    public var displayName: String { name.isEmpty ? id : name }
    public var hasActiveAccount: Bool { accountStatus.lowercased() == "active" }
    public var isExclusive: Bool { exclusivity.lowercased() == "exclusive" }
    public var acceptsEditorial: Bool { editorial.lowercased() == "yes" }
    public var termsIsGrab: Bool { termsFlag.lowercased() == "rights-grab" }
    public var termsIsCaution: Bool { termsFlag.lowercased() == "caution" }

    public var kindLabel: String {
        switch kind.lowercased() {
        case "stock": return "Stock"
        case "print-on-demand": return "Print on demand"
        case "gallery": return "Gallery"
        case "own-shop": return "Own shop"
        default: return kind
        }
    }

    public var accountLabel: String {
        switch accountStatus.lowercased() {
        case "active": return "Account active"
        case "applied": return "Applied"
        case "rejected": return "Application rejected"
        case "closed": return "Account closed"
        default: return "No account yet"
        }
    }

    public var callLabel: String {
        switch recommendationCall.lowercased() {
        case "join": return "Join"
        case "later": return "Later"
        case "skip": return "Skip"
        default: return recommendationCall
        }
    }

    /// SAL-15: portal terms move more slowly than competitions, so a month.
    public func needsRecheck(on today: Date = Date()) -> Bool {
        guard let checked = ISODate.parse(lastChecked) else { return false }
        return ISODate.days(from: checked, to: today) > 30
    }

    /// SAL-5: the limits a file has to meet, in one line.
    public var requirementsSummary: String {
        var parts: [String] = []
        if let min = minMegapixels { parts.append("at least \(min.formatted(.number.precision(.fractionLength(0...1)))) MP") }
        if let edge = maxLongEdge { parts.append("long edge up to \(edge) px") }
        if let keywords = maxKeywords { parts.append("up to \(keywords) keywords") }
        if let title = maxTitleChars { parts.append("title up to \(title) characters") }
        return parts.joined(separator: " · ")
    }
}

public enum ListingStatus: String, CaseIterable, Identifiable {
    case suggested, prepared, uploaded, live, rejected, withdrawn

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .suggested: return "Suggested"
        case .prepared: return "Prepared"
        case .uploaded: return "Uploaded"
        case .live: return "Live"
        case .rejected: return "Rejected"
        case .withdrawn: return "Withdrawn"
        }
    }

    /// The date column that records reaching this status (SAL-32).
    public var dateColumn: String? {
        switch self {
        case .suggested: return nil
        case .prepared: return ListingColumn.preparedOn
        case .uploaded: return ListingColumn.uploadedOn
        case .live: return ListingColumn.liveOn
        case .rejected, .withdrawn: return ListingColumn.endedOn
        }
    }

    /// On the portal, where a buyer or a competition could find it.
    public var isPublished: Bool { self == .uploaded || self == .live }
    /// Counts for S7 conflicts: files made, or already out there.
    public var isActive: Bool { self == .prepared || isPublished }
}

public enum ListingColumn {
    public static let portalID = "portal_id"
    public static let sourceFolder = "source_folder"
    public static let filename = "filename"
    public static let status = "status"
    public static let preparedOn = "prepared_on"
    public static let uploadedOn = "uploaded_on"
    public static let liveOn = "live_on"
    public static let endedOn = "ended_on"
}

/// `portal_id` + `source_folder` + `filename`: unique in `listings.csv`.
public struct ListingKey: Hashable, CustomStringConvertible {
    public var portalID: String
    public var photo: PhotoKey

    public init(portalID: String, photo: PhotoKey) {
        self.portalID = portalID
        self.photo = photo
    }

    public var description: String { "\(portalID): \(photo)" }
}

public struct Listing: Identifiable {
    public var key: ListingKey
    public var listingType = ""           // stock | editorial | print | edition
    public var title = ""
    public var description = ""
    public var keywords: [String] = []
    public var category = ""
    public var price: Double?
    public var currency = ""
    public var editionSize: Int?
    public var printSizes: [String] = []
    /// Claude's judgement of the photo: only for photos Istvan rated (S8).
    public var reason = ""
    /// Nil for a value the app does not know; the raw text is kept.
    public var status: ListingStatus?
    public var statusText = ""
    public var suggestedOn = ""
    public var preparedOn = ""
    public var uploadedOn = ""
    public var liveOn = ""
    public var endedOn = ""
    public var portalRef = ""
    public var notes = ""

    public init(key: ListingKey) { self.key = key }

    public var id: String { key.description }
    public var photo: PhotoKey { key.photo }
    public var portalID: String { key.portalID }

    public var isEdition: Bool { listingType.lowercased() == "edition" }
    public var isEditorial: Bool { listingType.lowercased() == "editorial" }

    public var typeLabel: String {
        switch listingType.lowercased() {
        case "stock": return "Stock"
        case "editorial": return "Editorial"
        case "print": return "Print"
        case "edition": return editionSize.map { "Edition of \($0)" } ?? "Edition"
        default: return listingType
        }
    }

    public var statusLabel: String { status?.label ?? (statusText.isEmpty ? "—" : statusText) }
}

public struct Sale: Identifiable {
    public var id = UUID()
    public var date = ""
    public var portalID = ""
    public var photo: PhotoKey
    public var listingType = ""
    public var editionNumber: Int?
    public var amount: Double?
    public var currency = ""
    public var notes = ""

    public init(photo: PhotoKey) { self.photo = photo }
}

/// The three sales files. Like the competition files, a missing one is not an
/// error (SAL-2).
public struct SalesFiles {
    public var portals: [Portal] = []
    public var listings: [Listing] = []
    public var sales: [Sale] = []

    public var portalsFileExists = false
    public var listingsFileExists = false
    public var salesFileExists = false
    public var errors: [String] = []

    public init() {}

    public var anyFileExists: Bool { portalsFileExists || listingsFileExists || salesFileExists }

    public func portal(id: String) -> Portal? { portals.first { $0.id == id } }

    public func listings(for photo: PhotoKey) -> [Listing] { listings.filter { $0.photo == photo } }

    public func listing(_ key: ListingKey) -> Listing? { listings.first { $0.key == key } }
}

public enum SalesLoader {
    public static func load(libraryURL: URL) -> SalesFiles {
        var files = SalesFiles()
        let fileManager = FileManager.default

        let portalsURL = libraryURL.appendingPathComponent("portals.csv")
        if fileManager.fileExists(atPath: portalsURL.path) {
            files.portalsFileExists = true
            switch SidecarLoader.read(portalsURL) {
            case .success(let document):
                let index = ColumnIndex(document: document)
                files.portals = document.records.compactMap { record in
                    let id = index.value("portal_id", record)
                    guard !id.isEmpty else { return nil }
                    var portal = Portal(id: id)
                    portal.name = index.value("name", record)
                    portal.kind = index.value("kind", record)
                    portal.url = index.value("url", record)
                    portal.signupURL = index.value("signup_url", record)
                    portal.uploadURL = index.value("upload_url", record)
                    portal.accountStatus = index.value("account_status", record)
                    portal.exclusivity = index.value("exclusivity", record)
                    portal.commission = index.value("commission", record)
                    portal.payout = index.value("payout", record)
                    portal.minMegapixels = number(index.value("min_megapixels", record))
                    portal.maxLongEdge = number(index.value("max_long_edge_px", record)).map { Int($0) }
                    portal.maxKeywords = number(index.value("max_keywords", record)).map { Int($0) }
                    portal.maxTitleChars = number(index.value("max_title_chars", record)).map { Int($0) }
                    portal.editorial = index.value("editorial", record)
                    portal.filmScans = index.value("film_scans", record)
                    portal.termsFlag = index.value("terms_flag", record)
                    portal.termsNotes = index.value("terms_notes", record)
                    portal.recommendationCall = index.value("recommendation_call", record)
                    portal.reasoning = index.value("reasoning", record)
                    portal.lastChecked = index.value("last_checked", record)
                    return portal
                }
            case .failure(let message):
                files.errors.append("portals.csv: \(message)")
            }
        }

        let listingsURL = libraryURL.appendingPathComponent("listings.csv")
        if fileManager.fileExists(atPath: listingsURL.path) {
            files.listingsFileExists = true
            switch SidecarLoader.read(listingsURL) {
            case .success(let document):
                let index = ColumnIndex(document: document)
                var seen: Set<ListingKey> = []
                files.listings = document.records.compactMap { record in
                    let portalID = index.value(ListingColumn.portalID, record)
                    let filename = index.value(ListingColumn.filename, record)
                    guard !portalID.isEmpty, !filename.isEmpty else { return nil }
                    let key = ListingKey(portalID: portalID,
                                         photo: PhotoKey(shoot: index.value(ListingColumn.sourceFolder, record), filename: filename))
                    // The key is unique; if the skill ever repeats one, the
                    // first row is the one the app shows and writes.
                    guard seen.insert(key).inserted else { return nil }
                    var listing = Listing(key: key)
                    listing.listingType = index.value("listing_type", record)
                    listing.title = index.value("title", record)
                    listing.description = index.value("description", record)
                    listing.keywords = list(index.value("keywords", record))
                    listing.category = index.value("category", record)
                    listing.price = number(index.value("price", record))
                    listing.currency = index.value("currency", record)
                    listing.editionSize = number(index.value("edition_size", record)).map { Int($0) }
                    listing.printSizes = list(index.value("print_sizes", record))
                    listing.reason = index.value("reason", record)
                    let statusText = index.value(ListingColumn.status, record)
                    listing.statusText = statusText
                    listing.status = statusText.isEmpty ? .suggested : ListingStatus(rawValue: statusText.lowercased())
                    listing.suggestedOn = index.value("suggested_on", record)
                    listing.preparedOn = index.value(ListingColumn.preparedOn, record)
                    listing.uploadedOn = index.value(ListingColumn.uploadedOn, record)
                    listing.liveOn = index.value(ListingColumn.liveOn, record)
                    listing.endedOn = index.value(ListingColumn.endedOn, record)
                    listing.portalRef = index.value("portal_ref", record)
                    listing.notes = index.value("notes", record)
                    return listing
                }
            case .failure(let message):
                files.errors.append("listings.csv: \(message)")
            }
        }

        let salesURL = libraryURL.appendingPathComponent("sales.csv")
        if fileManager.fileExists(atPath: salesURL.path) {
            files.salesFileExists = true
            switch SidecarLoader.read(salesURL) {
            case .success(let document):
                let index = ColumnIndex(document: document)
                files.sales = document.records.compactMap { record in
                    let filename = index.value("filename", record)
                    let date = index.value("date", record)
                    guard !filename.isEmpty || !date.isEmpty else { return nil }
                    var sale = Sale(photo: PhotoKey(shoot: index.value("source_folder", record), filename: filename))
                    sale.date = date
                    sale.portalID = index.value("portal_id", record)
                    sale.listingType = index.value("listing_type", record)
                    sale.editionNumber = number(index.value("edition_number", record)).map { Int($0) }
                    sale.amount = number(index.value("amount", record))
                    sale.currency = index.value("currency", record).uppercased()
                    sale.notes = index.value("notes", record)
                    return sale
                }
                files.sales.sort { $0.date > $1.date }     // SAL-16: newest first
            case .failure(let message):
                files.errors.append("sales.csv: \(message)")
            }
        }

        return files
    }

    /// Accepts a decimal comma too: a Hungarian spreadsheet writes `12,5`.
    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed) ?? Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    static func list(_ text: String) -> [String] {
        text.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
