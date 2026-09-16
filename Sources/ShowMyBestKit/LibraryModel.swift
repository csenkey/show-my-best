import Foundation
import Observation

@MainActor
@Observable
public final class LibraryModel {

    // MARK: Types

    public enum Screen: String, CaseIterable, Identifiable {
        case gallery, competitions, submissions, sales
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .gallery: return "Gallery"
            case .competitions: return "Competitions"
            case .submissions: return "Submissions"
            case .sales: return "Sales"
            }
        }
    }

    /// The sidebar collections (GAL-2).
    public enum Collection: String, CaseIterable, Identifiable, Hashable {
        case all, notRatedByMe, myBest, claudePicks, disagreements, critiques, waitingForClaude, notCatalogued, missingFiles
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .all: return "All photos"
            case .notRatedByMe: return "Not rated by me"
            case .myBest: return "My best (4–5)"
            case .claudePicks: return "Claude's picks"
            case .disagreements: return "Disagreements"
            case .critiques: return "Critiques"
            case .waitingForClaude: return "Waiting for Claude"
            case .notCatalogued: return "Not catalogued"
            case .missingFiles: return "Missing files"
            }
        }

        /// IND-3: these read Claude's rating, so they can only contain photos
        /// Istvan has already rated.
        public var dependsOnClaude: Bool {
            switch self {
            case .claudePicks, .disagreements, .critiques: return true
            default: return false
            }
        }
    }

    public enum Scope: Hashable {
        case collection(Collection)
        case shoot(String)

        public var title: String {
            switch self {
            case .collection(let collection): return collection.title
            case .shoot(let name): return name
            }
        }
    }

    public enum SortOrder: String, CaseIterable, Identifiable {
        case dateTaken, shootThenFilename, myRating, claudeRating
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .dateTaken: return "Date taken"
            case .shootThenFilename: return "Shoot, then filename"
            case .myRating: return "My rating"
            case .claudeRating: return "Claude's rating"
            }
        }
        public var dependsOnClaude: Bool { self == .claudeRating }
    }

    /// GAL-3, combinable. `myRating` uses 0 for "unrated".
    public struct Filters: Equatable {
        public var myRating: Set<Int> = []
        public var claudeRating: Set<Int> = []
        public var tag: String?
        public var medium: String?
        public var cameraOrFormat: String?
        public var status: String?

        public init() {}

        public var isEmpty: Bool {
            myRating.isEmpty && claudeRating.isEmpty && tag == nil && medium == nil
                && cameraOrFormat == nil && status == nil
        }

        public var dependsOnClaude: Bool { !claudeRating.isEmpty }
    }

    public struct Notice: Identifiable, Equatable {
        public enum Kind { case info, warning }
        public var id = UUID()
        public var kind: Kind
        public var title: String
        public var detail: String
        public var lines: [String] = []
    }

    // MARK: State

    public private(set) var libraryURL: URL?
    /// Set when the chosen folder has no catalogue (LIB-3).
    public private(set) var folderWithoutCatalogue: URL?
    public private(set) var photos: [Photo] = []
    public private(set) var shootNames: [String] = []
    public private(set) var sidecars = SidecarFiles()
    /// Portals, listings and sales (sales spec 4).
    public private(set) var sales = SalesFiles()
    public private(set) var notices: [Notice] = []
    public private(set) var lastReloadedAt: Date?

    public var screen: Screen = .gallery
    public var scope: Scope = .collection(.all)
    public var sortOrder: SortOrder = .dateTaken
    public var filters = Filters()
    public var selection: Set<PhotoKey> = []
    public var thumbnailSize: Double = 190
    public var showClosedCompetitions = false
    public var afterRatingMovesOn = true      // CUL-5, default from OI-3
    /// Bumped to ask the window to open Find Photo; the view watches it.
    public var findPhotoRequests = 0
    public var salesSection: SalesSection = .queue
    /// The portal whose files are being prepared right now, if any.
    public var preparingPortalID: String?
    /// Written into every exported file as creator and copyright holder (SAL-28).
    public var creatorName = "Istvan Csenkey-Sinko"

    /// SAL-1
    public enum SalesSection: String, CaseIterable, Identifiable {
        case queue, listed, portals, earnings
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .queue: return "Upload queue"
            case .listed: return "Listed"
            case .portals: return "Portals"
            case .earnings: return "Earnings"
            }
        }
    }

    private var store: CatalogueStore?
    private var photosByKey: [PhotoKey: Int] = [:]
    private var fingerprint: String = ""
    private var retryingParse = false
    /// The last directory listing, reused while rating so a keypress does not
    /// walk the library again (G3, NFR-5).
    @ObservationIgnored private var lastScan = ScannedLibrary()

    /// `visiblePhotos` is read several times per redraw and sorts as it goes,
    /// so the answer is kept until something it depends on changes.
    private struct ViewKey: Equatable {
        var scope: Scope
        var sortOrder: SortOrder
        var filters: Filters
        var generation: Int
    }
    @ObservationIgnored private var cachedVisible: [Photo] = []
    @ObservationIgnored private var cachedVisibleKey: ViewKey?
    @ObservationIgnored private var generation = 0
    /// Photo dimensions for SAL-21, read from file headers once per reload.
    @ObservationIgnored var pixelSizes: [PhotoKey: PixelSize?] = [:]

    public init() {}

    // MARK: Opening a library

    public var catalogueError: String? { store?.loadError }
    public var hasCritiqueColumns: Bool { store?.hasCritiqueColumns ?? false }
    public var hasMediumColumn: Bool { store?.hasMediumColumn ?? false }
    public var pendingRatingCount: Int { store?.pending.count ?? 0 }
    public var pendingRatings: [PendingRating] { store?.pending ?? [] }
    public var backupsURL: URL? { store?.support.backupsURL }
    public var ratingLogURL: URL? { store?.support.logURL }

    public func open(folder url: URL) {
        switch LibraryLocator.resolve(chosen: url) {
        case .library(let libraryURL, let shoot):
            self.folderWithoutCatalogue = nil
            self.libraryURL = libraryURL
            self.store = CatalogueStore(libraryURL: libraryURL)
            self.notices = []
            self.scope = shoot.map { Scope.shoot($0) } ?? .collection(.all)
            reload()
        case .noCatalogue(let folder):
            self.folderWithoutCatalogue = folder
            self.libraryURL = nil
            self.store = nil
            self.photos = []
            self.shootNames = []
        }
    }

    public func closeLibrary() {
        libraryURL = nil
        store = nil
        photos = []
        shootNames = []
        sidecars = SidecarFiles()
        sales = SalesFiles()
    }

    // MARK: Reloading (SYN-1, SYN-6)

    public func reload() {
        guard let store, let libraryURL else { return }
        let restored = store.reload()
        let scanned = LibraryScanner.scan(libraryURL)
        sidecars = SidecarLoader.load(libraryURL: libraryURL)
        sales = SalesLoader.load(libraryURL: libraryURL)
        pixelSizes = [:]
        merge(scanned: scanned, store: store)
        fingerprint = currentFingerprint()
        lastReloadedAt = Date()

        notices.removeAll { $0.kind == .warning }
        if let error = store.loadError {
            // SYN-2: a file being written can look broken for a moment.
            if !retryingParse {
                retryingParse = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    self.retryingParse = false
                    self.reload()
                }
            } else {
                notices.append(Notice(
                    kind: .warning,
                    title: error,
                    detail: store.pending.isEmpty
                        ? "Showing the last good data. Nothing is being written until the file parses again."
                        : "Showing the last good data. \(store.pending.count) rating change\(store.pending.count == 1 ? " is" : "s are") held and will be saved as soon as the file parses again.",
                    lines: store.pending.map { pending in
                        "\(pending.key) → \(pending.rating.map(String.init) ?? "cleared")"
                    }
                ))
            }
        }
        for error in sidecars.errors + sales.errors {
            notices.append(Notice(kind: .warning, title: error, detail: "Showing the last good data for this file."))
        }
        if !restored.isEmpty {
            // RAT-12: say which photos were put back.
            notices.append(Notice(
                kind: .info,
                title: "\(restored.count) rating\(restored.count == 1 ? "" : "s") put back",
                detail: "A skill run wrote over ratings you saved this week. They have been restored from the change log.",
                lines: restored.map { "\($0.key) → \($0.rating.map(String.init) ?? "cleared")" }
            ))
        }
    }

    private func merge(scanned: ScannedLibrary, store: CatalogueStore) {
        lastScan = scanned
        generation += 1
        var photos: [Photo] = []
        var seen: Set<PhotoKey> = []

        for shoot in scanned.shootNames {
            for url in scanned.shoots[shoot] ?? [] {
                let key = PhotoKey(shoot: shoot, filename: url.lastPathComponent)
                seen.insert(key)
                photos.append(Photo(key: key, url: url, row: store.rows[key]))
            }
        }
        // LIB-8: rows whose file is gone are kept and listed, never removed.
        for key in store.rowOrder where !seen.contains(key) {
            photos.append(Photo(key: key, url: nil, row: store.rows[key]))
        }

        // A rating that has not reached the file yet still shows as Istvan set
        // it, and reveals Claude's view with it (IND-5).
        for index in photos.indices {
            guard let pending = store.pending.last(where: { $0.key == photos[index].key }) else { continue }
            if photos[index].row != nil {
                photos[index].row?.istvanRating = pending.rating
            } else {
                var row = CatalogueRow(key: photos[index].key, recordIndex: -1)
                row.istvanRating = pending.rating
                row.status = "available"
                photos[index].row = row
            }
        }

        self.photos = photos
        self.shootNames = scanned.shootNames
        self.photosByKey = Dictionary(uniqueKeysWithValues: photos.enumerated().map { ($1.key, $0) })
    }

    public func photo(for key: PhotoKey) -> Photo? {
        guard let index = photosByKey[key] else { return nil }
        return photos[index]
    }

    // MARK: Watching for outside changes

    /// A cheap signature of everything the app reads, polled once a second so a
    /// change outside the app shows up within two (SYN-1).
    private func currentFingerprint() -> String {
        guard let libraryURL else { return "" }
        let fileManager = FileManager.default
        var parts: [String] = []
        for name in ["catalogue.csv", "competitions.csv", "competition_matches.csv", "submissions.csv",
                     "portals.csv", "listings.csv", "sales.csv"] {
            let url = libraryURL.appendingPathComponent(name)
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let date = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = (attributes?[.size] as? Int) ?? 0
            parts.append("\(name):\(date):\(size)")
        }
        for shoot in shootNames + [""] {
            let url = shoot.isEmpty ? libraryURL : libraryURL.appendingPathComponent(shoot)
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let date = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            parts.append("\(shoot):\(date)")
        }
        return parts.joined(separator: "|")
    }

    public func pollForChanges() {
        guard libraryURL != nil else { return }
        let current = currentFingerprint()
        guard current != fingerprint else { return }
        reload()
    }

    // MARK: Rating (RAT-1, RAT-2)

    public func setRating(_ rating: Int?, for keys: some Sequence<PhotoKey>) {
        guard let store else { return }
        var changed = false
        for key in keys {
            guard store.effectiveRating(for: key) != rating else { continue }
            _ = store.setRating(rating, for: key)
            changed = true
        }
        guard changed else { return }
        // The files on disk have not moved, only the catalogue: re-merge
        // against the listing already in hand.
        merge(scanned: lastScan, store: store)
        fingerprint = currentFingerprint()
        notices.removeAll { $0.kind == .warning }
        if let error = store.loadError {
            notices.append(Notice(
                kind: .warning,
                title: error,
                detail: "\(store.pending.count) rating change\(store.pending.count == 1 ? " is" : "s are") held and will be saved as soon as the file parses again.",
                lines: store.pending.map { "\($0.key) → \($0.rating.map(String.init) ?? "cleared")" }
            ))
        }
    }

    public func setRating(_ rating: Int?, for key: PhotoKey) {
        setRating(rating, for: [key])
    }

    /// GAL-8, GAL-9: 1–5 and 0 act on everything selected.
    public func rateSelection(_ rating: Int?) {
        guard !selection.isEmpty else { return }
        setRating(rating, for: selection)
    }

    func post(_ notice: Notice) {
        notices.append(notice)
    }

    public func dismiss(_ notice: Notice) {
        notices.removeAll { $0.id == notice.id }
    }

    // MARK: Scope, filters, sorting

    public func count(for collection: Collection) -> Int {
        photos.filter { matches(collection: collection, $0) }.count
    }

    public func count(forShoot shoot: String) -> Int {
        photos.filter { $0.shoot == shoot && $0.isOnDisk }.count
    }

    private func matches(collection: Collection, _ photo: Photo) -> Bool {
        switch collection {
        case .all: return photo.isOnDisk
        case .notRatedByMe: return photo.isOnDisk && photo.istvanRating == nil
        case .myBest: return (photo.istvanRating ?? 0) >= 4
        // The three below read Claude's rating, and `Photo` only hands it over
        // for revealed photos, so unrated photos cannot appear here (IND-3).
        case .claudePicks: return (photo.claudeRating ?? 0) >= 4
        case .disagreements: return (photo.disagreement ?? 0) >= 2
        case .critiques: return photo.hasCritique
        case .waitingForClaude: return photo.isWaitingForClaude
        case .notCatalogued: return photo.isOnDisk && !photo.isCatalogued
        case .missingFiles: return !photo.isOnDisk
        }
    }

    private func matches(filters: Filters, _ photo: Photo) -> Bool {
        if !filters.myRating.isEmpty {
            let value = photo.istvanRating ?? 0
            guard filters.myRating.contains(value) else { return false }
        }
        if !filters.claudeRating.isEmpty {
            guard let claude = photo.claudeRating, filters.claudeRating.contains(claude) else { return false }
        }
        if let tag = filters.tag {
            guard photo.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return false }
        }
        if let medium = filters.medium {
            guard (photo.row?.medium ?? "").caseInsensitiveCompare(medium) == .orderedSame else { return false }
        }
        if let camera = filters.cameraOrFormat {
            guard (photo.row?.cameraOrFormat ?? "") == camera else { return false }
        }
        if let status = filters.status {
            guard photo.status.caseInsensitiveCompare(status) == .orderedSame else { return false }
        }
        return true
    }

    /// True when the current view is ordered or filtered by Claude's rating, so
    /// unrated photos have to be left out (IND-3).
    public var viewDependsOnClaude: Bool {
        if case .collection(let collection) = scope, collection.dependsOnClaude { return true }
        return sortOrder.dependsOnClaude || filters.dependsOnClaude
    }

    /// The photos on screen, and how many unrated ones IND-3 kept out.
    public var visiblePhotos: [Photo] {
        let key = ViewKey(scope: scope, sortOrder: sortOrder, filters: filters, generation: generation)
        if key == cachedVisibleKey { return cachedVisible }
        let result = computeVisiblePhotos()
        cachedVisibleKey = key
        cachedVisible = result
        return result
    }

    private func computeVisiblePhotos() -> [Photo] {
        var result: [Photo]
        switch scope {
        case .collection(let collection):
            result = photos.filter { matches(collection: collection, $0) }
        case .shoot(let shoot):
            result = photos.filter { $0.shoot == shoot && $0.isOnDisk }
        }
        result = result.filter { matches(filters: filters, $0) }
        if viewDependsOnClaude {
            result = result.filter(\.isRevealed)
        }
        return sorted(result)
    }

    public var excludedUnratedCount: Int {
        guard viewDependsOnClaude else { return 0 }
        var candidates: [Photo]
        switch scope {
        case .collection(let collection):
            candidates = collection.dependsOnClaude
                ? photos.filter { $0.isOnDisk }
                : photos.filter { matches(collection: collection, $0) }
        case .shoot(let shoot):
            candidates = photos.filter { $0.shoot == shoot && $0.isOnDisk }
        }
        return candidates.filter { !$0.isRevealed }.count
    }

    private func sorted(_ photos: [Photo]) -> [Photo] {
        switch sortOrder {
        case .shootThenFilename:
            return photos.sorted { left, right in
                left.shoot == right.shoot
                    ? left.filename.localizedStandardCompare(right.filename) == .orderedAscending
                    : left.shoot < right.shoot
            }
        case .dateTaken:
            // SYN-5: dates the app cannot read are shown as text and sort last.
            return photos.sorted { left, right in
                let leftDate = ISODate.parse(left.row?.dateTaken ?? "")
                let rightDate = ISODate.parse(right.row?.dateTaken ?? "")
                switch (leftDate, rightDate) {
                case (let l?, let r?):
                    return l == r ? left.filename.localizedStandardCompare(right.filename) == .orderedAscending : l > r
                case (nil, .some): return false
                case (.some, nil): return true
                default: return left.key.description < right.key.description
                }
            }
        case .myRating:
            return photos.sorted { left, right in
                let l = left.istvanRating ?? 0, r = right.istvanRating ?? 0
                return l == r ? left.key.description < right.key.description : l > r
            }
        case .claudeRating:
            return photos.sorted { left, right in
                let l = left.claudeRating ?? 0, r = right.claudeRating ?? 0
                return l == r ? left.key.description < right.key.description : l > r
            }
        }
    }

    // MARK: Filter vocabulary, taken from what the library actually holds

    public var availableTags: [String] {
        Array(Set(photos.flatMap(\.tags))).sorted()
    }

    public var availableCameras: [String] {
        Array(Set(photos.compactMap { $0.row?.cameraOrFormat }).filter { !$0.isEmpty }).sorted()
    }

    public var availableStatuses: [String] {
        Array(Set(photos.map(\.status)).filter { !$0.isEmpty }).sorted()
    }

    // MARK: Competitions (CMP-1, CMP-2)

    public var visibleCompetitions: [Competition] {
        sidecars.competitions
            .filter { showClosedCompetitions || $0.status() != .closed }
            .sorted { left, right in
                switch (left.deadlineDate, right.deadlineDate) {
                case (let l?, let r?): return l < r
                case (nil, .some): return false
                case (.some, nil): return true
                default: return left.name < right.name
                }
            }
    }

    public var openCompetitionCount: Int {
        sidecars.competitions.filter { $0.status() != .closed }.count
    }

    public var closedCompetitionCount: Int {
        sidecars.competitions.filter { $0.status() == .closed }.count
    }

    /// CMP-5 with IND-4: the matched photos Istvan has rated, and a count of
    /// the ones he has not — never the photos themselves.
    public func matchedPhotos(for competition: Competition) -> (shown: [(CompetitionMatch, Photo)], hiddenUnrated: Int) {
        var shown: [(CompetitionMatch, Photo)] = []
        var hidden = 0
        for match in sidecars.matches(for: competition.id) {
            guard let photo = photo(for: match.key) else { continue }
            if photo.isRevealed {
                shown.append((match, photo))
            } else {
                hidden += 1
            }
        }
        shown.sort { left, right in
            left.0.isPrimary == right.0.isPrimary
                ? left.0.category < right.0.category
                : left.0.isPrimary
        }
        return (shown, hidden)
    }

    /// DET-4: the competitions a revealed photo is matched to.
    public func matches(for photo: Photo) -> [(CompetitionMatch, Competition?)] {
        guard photo.isRevealed else { return [] }
        return sidecars.matches(for: photo.key).map { ($0, sidecars.competition(id: $0.competitionID)) }
    }

    // MARK: Submissions (SUB-5)

    public struct SubmissionSummary {
        public var entries = 0
        public var feesByCurrency: [String: Double] = [:]
        public var results: [String: Int] = [:]
    }

    /// The photos a submission names (SUB-3). A `shoot/filename` reference is
    /// exact; a bare filename is looked up the way Find Photo does it, and
    /// lists every shoot that has that name rather than guessing between them.
    public func photos(for submission: Submission) -> [Photo] {
        var seen: Set<PhotoKey> = []
        var result: [Photo] = []
        for reference in submission.photoReferences {
            let found: [Photo]
            if let key = PhotoKey(reference: reference), let photo = photo(for: key) {
                found = [photo]
            } else {
                found = PhotoFinder.find(reference, in: photos).photos
            }
            for photo in found where seen.insert(photo.key).inserted {
                result.append(photo)
            }
        }
        return result
    }

    /// DET-5: the entries that include this photo.
    public func submissions(including key: PhotoKey) -> [Submission] {
        sidecars.submissions.filter { submission in
            photos(for: submission).contains { $0.key == key }
        }
    }

    public var submissionSummary: SubmissionSummary {
        var summary = SubmissionSummary()
        summary.entries = sidecars.submissions.count
        for submission in sidecars.submissions {
            summary.results[submission.resultLabel, default: 0] += 1
            if let fee = EntryFee.parse(submission.entryFee) {
                summary.feesByCurrency[fee.currency, default: 0] += fee.value
            }
        }
        return summary
    }
}
