import Foundation

extension LibraryModel {

    // MARK: What the Sales view lists (SAL-3)

    /// Listings for photos Istvan has rated. The rest exist only as a count:
    /// a listing says Claude thinks the photo sells, which is an opinion (S8).
    public var visibleListings: [Listing] {
        sales.listings.filter { photo(for: $0.photo)?.isRevealed ?? false }
    }

    public var hiddenListingCount: Int {
        sales.listings.count - visibleListings.count
    }

    public struct PortalGroup: Identifiable {
        public var portalID: String
        public var portal: Portal?
        public var listings: [Listing]
        public var id: String { portalID }
        public var title: String { portal?.displayName ?? portalID }
    }

    /// SAL-4: suggested and prepared listings by portal, portals with an
    /// active account first, then as the skill ordered them.
    public var uploadQueue: [PortalGroup] {
        let queued = visibleListings.filter { $0.status == .suggested || $0.status == .prepared }
        return groups(queued).sorted { left, right in
            let leftActive = left.portal?.hasActiveAccount ?? false
            let rightActive = right.portal?.hasActiveAccount ?? false
            if leftActive != rightActive { return leftActive }
            return portalOrder(left.portalID) < portalOrder(right.portalID)
        }
    }

    /// SAL-11: everything past the queue, by status.
    public var listedByStatus: [(ListingStatus?, [Listing])] {
        let later = visibleListings.filter { $0.status != .suggested && $0.status != .prepared }
        var result: [(ListingStatus?, [Listing])] = []
        for status in [ListingStatus.uploaded, .live, .rejected, .withdrawn] {
            let matching = later.filter { $0.status == status }
            if !matching.isEmpty { result.append((status, matching)) }
        }
        let unknown = later.filter { $0.status == nil }
        if !unknown.isEmpty { result.append((nil, unknown)) }
        return result
    }

    public func listingCounts(for portalID: String) -> [ListingStatus: Int] {
        var counts: [ListingStatus: Int] = [:]
        for listing in visibleListings where listing.portalID == portalID {
            if let status = listing.status { counts[status, default: 0] += 1 }
        }
        return counts
    }

    private func groups(_ listings: [Listing]) -> [PortalGroup] {
        var order: [String] = []
        var byPortal: [String: [Listing]] = [:]
        for listing in listings {
            if byPortal[listing.portalID] == nil { order.append(listing.portalID) }
            byPortal[listing.portalID, default: []].append(listing)
        }
        return order.map { PortalGroup(portalID: $0, portal: sales.portal(id: $0), listings: byPortal[$0] ?? []) }
    }

    private func portalOrder(_ id: String) -> Int {
        sales.portals.firstIndex { $0.id == id } ?? Int.max
    }

    // MARK: Holds, problems and warnings (3.5)

    public func assessment(for listing: Listing) -> ListingAssessment {
        let key = listing.photo
        var context = PhotoSalesContext()
        context.submissions = submissions(including: key)
        context.matches = sidecars.matches(for: key).map { ($0, sidecars.competition(id: $0.competitionID)) }
        context.competitions = Dictionary(sidecars.competitions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        context.listings = sales.listings(for: key)
        let url = photo(for: key)?.url
        context.fileExists = url != nil
        context.pixelSize = url.flatMap { pixelSize(for: key, url: $0) }
        return SalesRules.assess(listing, portals: sales.portals, context: context)
    }

    private func pixelSize(for key: PhotoKey, url: URL) -> PixelSize? {
        if let cached = pixelSizes[key] { return cached }
        let size = ListingExporter.pixelSize(of: url)
        pixelSizes[key] = size
        return size
    }

    /// SAL-24: where a photo is out in public, for competitions that want
    /// unpublished work.
    public func publishedPortals(for key: PhotoKey) -> [String] {
        SalesRules.publishedPortals(for: sales.listings(for: key), portals: sales.portals)
    }

    /// SAL-25: a revealed photo's listings.
    public func listings(for photo: Photo) -> [Listing] {
        guard photo.isRevealed else { return [] }
        return sales.listings(for: photo.key)
    }

    // MARK: Preparing files (3.6)

    public struct PrepareOutcome {
        public var portalID: String
        public var folder: URL
        public var prepared: [Listing] = []
        public var skipped: [(Listing, String)] = []
        public var failed: [(Listing, String)] = []
    }

    /// SAL-7: exports every queued listing for the portal that nothing holds
    /// back, then marks them prepared (SAL-31). The decoding runs off the main
    /// thread, so the window stays live while large scans are resized.
    public func prepareFiles(portalID: String) async {
        guard preparingPortalID == nil, let libraryURL else { return }
        let portal = sales.portal(id: portalID)
        let queued = visibleListings.filter {
            $0.portalID == portalID && ($0.status == .suggested || $0.status == .prepared)
        }
        var outcome = PrepareOutcome(portalID: portalID, folder: ListingExporter.folder(for: portalID))

        var jobs: [(listing: Listing, source: URL, year: String)] = []
        for listing in queued {
            let assessment = assessment(for: listing)
            guard assessment.canPrepare, let source = photo(for: listing.photo)?.url else {
                outcome.skipped.append((listing, assessment.blockingReasons.first ?? "The photo file is missing"))
                continue
            }
            jobs.append((listing, source, copyrightYear(for: listing.photo)))
        }
        guard !jobs.isEmpty else {
            post(prepareNotice(outcome, portal: portal))
            return
        }

        preparingPortalID = portalID
        let names = ListingExporter.fileNames(for: jobs.map(\.listing.key))
        let folder = outcome.folder
        let creator = creatorName
        let maxLongEdge = portal?.maxLongEdge

        let results: [(Listing, String?)] = await Task.detached(priority: .userInitiated) {
            jobs.map { job in
                let name = names[job.listing.key] ?? job.source.lastPathComponent
                do {
                    try ListingExporter.export(job.listing, from: job.source, to: folder.appendingPathComponent(name),
                                               maxLongEdge: maxLongEdge, creator: creator, copyrightYear: job.year)
                    return (job.listing, nil)
                } catch {
                    return (job.listing, String(describing: error))
                }
            }
        }.value

        for (listing, error) in results {
            if let error { outcome.failed.append((listing, error)) } else { outcome.prepared.append(listing) }
        }

        if !outcome.prepared.isEmpty {
            do {
                try ListingStore.setStatus(.prepared, for: outcome.prepared.map(\.key),
                                           libraryURL: libraryURL, support: SupportFiles(libraryURL: libraryURL))
            } catch {
                post(Notice(kind: .warning, title: String(describing: error),
                            detail: "The files were made, but their status could not be saved. Nothing else changed."))
            }
        }
        preparingPortalID = nil
        reload()

        // SAL-30: the sheet covers every listing now prepared for the portal,
        // including ones made on an earlier day.
        let preparedNow = sales.listings.filter { $0.portalID == portalID && $0.status == .prepared }
        let sheetNames = ListingExporter.fileNames(for: preparedNow.map(\.key))
        try? ListingExporter.writeMetadataSheet(preparedNow.map { (sheetNames[$0.key] ?? $0.photo.filename, $0) }, to: folder)

        post(prepareNotice(outcome, portal: portal))
    }

    private func prepareNotice(_ outcome: PrepareOutcome, portal: Portal?) -> Notice {
        let name = portal?.displayName ?? outcome.portalID
        let count = outcome.prepared.count
        var lines = outcome.skipped.map { "Not prepared: \($0.0.photo) — \($0.1)" }
        lines += outcome.failed.map { "Failed: \($0.0.photo) — \($0.1)" }
        return Notice(
            kind: .info,
            title: count == 0
                ? "No files prepared for \(name)"
                : "\(count) file\(count == 1 ? "" : "s") ready for \(name)",
            detail: count == 0
                ? "Everything in the queue for \(name) is held back."
                : "In \(outcome.folder.path), with title, description and keywords embedded.",
            lines: lines
        )
    }

    private func copyrightYear(for key: PhotoKey) -> String {
        let taken = photo(for: key)?.row?.dateTaken ?? ""
        let year = String(taken.prefix(4))
        if year.count == 4, Int(year) != nil { return year }
        return String(Calendar.current.component(.year, from: Date()))
    }

    // MARK: Status changes (3.7)

    /// SAL-10, SAL-12. Holds are checked again here, not just in the view:
    /// the data may have changed since the button was drawn.
    public func setListingStatus(_ status: ListingStatus, for listings: [Listing]) {
        guard let libraryURL, !listings.isEmpty else { return }
        var allowed = listings
        if status == .uploaded {
            allowed = listings.filter { !assessment(for: $0).isHeld }
            let held = listings.count - allowed.count
            if held > 0 {
                post(Notice(kind: .info, title: "\(held) listing\(held == 1 ? " is" : "s are") on hold",
                            detail: "Only listings without a hold can be marked uploaded."))
            }
        }
        guard !allowed.isEmpty else { return }
        do {
            try ListingStore.setStatus(status, for: allowed.map(\.key),
                                       libraryURL: libraryURL, support: SupportFiles(libraryURL: libraryURL))
        } catch {
            post(Notice(kind: .warning, title: String(describing: error), detail: "Nothing was changed."))   // SAL-35
        }
        reload()
    }

    // MARK: Earnings (SAL-16)

    public struct EarningsSummary {
        public var totalsByCurrency: [String: Double] = [:]
        public var byPortal: [(portal: String, count: Int, totals: [String: Double])] = []
        public var editions: [(listing: Listing, sold: Int)] = []
    }

    public var earnings: EarningsSummary {
        var summary = EarningsSummary()
        var portals: [String: (count: Int, totals: [String: Double])] = [:]
        for sale in sales.sales {
            let amount = sale.amount ?? 0
            summary.totalsByCurrency[sale.currency, default: 0] += amount
            var entry = portals[sale.portalID] ?? (0, [:])
            entry.count += 1
            entry.totals[sale.currency, default: 0] += amount
            portals[sale.portalID] = entry
        }
        summary.byPortal = portals
            .map { (portal: SalesRules.portalName($0.key, sales.portals), count: $0.value.count, totals: $0.value.totals) }
            .sorted { $0.count > $1.count }
        summary.editions = visibleListings.filter(\.isEdition).map { listing in
            let sold = sales.sales.filter {
                $0.photo == listing.photo && $0.portalID == listing.portalID && $0.listingType.lowercased() == "edition"
            }.count
            return (listing, sold)
        }
        return summary
    }
}
