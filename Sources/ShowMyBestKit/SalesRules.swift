import Foundation

/// What stands between a listing and the portal (sales spec 3.5). Worked out
/// fresh from the files every time, never stored, so a hold lifts on its own
/// the moment the data behind it changes.
public struct ListingAssessment {
    /// Stops preparing and marking uploaded.
    public var holds: [String] = []
    /// Stops preparing: the file itself would not do.
    public var problems: [String] = []
    /// Shown, nothing more.
    public var warnings: [String] = []

    public init() {}

    public var isHeld: Bool { !holds.isEmpty }
    public var canPrepare: Bool { holds.isEmpty && problems.isEmpty }
    /// Everything that keeps a listing out of an export, for SAL-7's message.
    public var blockingReasons: [String] { holds + problems }
}

/// The facts about one photo the rules need, gathered by the caller so the
/// rules stay free of file access and the library model.
public struct PhotoSalesContext {
    /// Submissions that include the photo.
    public var submissions: [Submission] = []
    /// Its competition matches, with the competition when it is known.
    public var matches: [(CompetitionMatch, Competition?)] = []
    /// Competitions by id, for the submissions above.
    public var competitions: [String: Competition] = [:]
    /// Every listing for the photo, on any portal.
    public var listings: [Listing] = []
    public var fileExists = true
    /// Pixel dimensions, when the file could be read.
    public var pixelSize: PixelSize?

    public init() {}
}

public struct PixelSize: Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var megapixels: Double { Double(width * height) / 1_000_000 }
    public var longEdge: Int { max(width, height) }
}

public enum SalesRules {
    /// Listing types an edition cannot live alongside (S7): an open print run or
    /// a cheap licence of the same picture undercuts the numbered prints.
    static let openTypes: Set<String> = ["stock", "editorial", "print"]

    public static func assess(
        _ listing: Listing,
        portals: [Portal],
        context: PhotoSalesContext,
        today: Date = Date()
    ) -> ListingAssessment {
        var result = ListingAssessment()
        let portal = portals.first { $0.id == listing.portalID }
        let others = context.listings.filter { $0.key != listing.key }

        // SAL-17: entered, and the jury has not spoken.
        for submission in context.submissions where submission.result.lowercased() == "pending" {
            result.holds.append("Entered in \(submission.competitionName), waiting for results")
        }

        // SAL-18: matched to a competition that is still open.
        for (match, competition) in context.matches {
            guard let competition, competition.status(on: today) != .closed else { continue }
            // Entered already: pending is SAL-17's to say, and a recorded
            // result means the hold is over even before the deadline (S3).
            let entered = context.submissions.contains {
                (!match.competitionID.isEmpty && $0.competitionID == match.competitionID)
                    || (!competition.name.isEmpty && $0.competitionName == competition.name)
            }
            guard !entered else { continue }
            let name = competition.name.isEmpty ? competition.id : competition.name
            if competition.deadline.isEmpty {
                result.holds.append("Matched to \(name), which has no deadline on record")
            } else {
                result.holds.append("Matched to \(name), closes on \(competition.deadline)")
            }
        }

        // SAL-19: editions against open prints and licences.
        let type = listing.listingType.lowercased()
        if listing.isEdition {
            for other in others where openTypes.contains(other.listingType.lowercased()) && (other.status?.isActive ?? false) {
                result.holds.append("\(other.typeLabel) listing on \(portalName(other.portalID, portals)) is \(other.statusLabel.lowercased()), and an edition must stay limited")
            }
        } else if openTypes.contains(type) {
            for other in others where other.isEdition && (other.status?.isActive ?? false) {
                result.holds.append("Sold as a limited edition on \(portalName(other.portalID, portals))")
            }
        }

        // SAL-20: exclusivity, both ways.
        for other in others where other.status?.isPublished ?? false {
            let otherPortal = portals.first { $0.id == other.portalID }
            if otherPortal?.isExclusive == true {
                result.holds.append("Exclusive to \(otherPortal!.displayName)")
            } else if portal?.isExclusive == true {
                result.holds.append("\(portal!.displayName) is exclusive, and this photo is already on \(portalName(other.portalID, portals))")
            }
        }

        // SAL-21: the file.
        if portal == nil {
            result.problems.append("No portal \"\(listing.portalID)\" in portals.csv")
        }
        if !context.fileExists {
            result.problems.append("The photo file is missing")
        } else if let portal, let minimum = portal.minMegapixels, let size = context.pixelSize, size.megapixels < minimum {
            result.problems.append("Too small for \(portal.displayName): \(megapixels(size.megapixels)) MP, needs at least \(megapixels(minimum))")
        }

        // SAL-22: limits the skill should have kept to.
        if let portal {
            if let maximum = portal.maxKeywords, listing.keywords.count > maximum {
                result.warnings.append("\(listing.keywords.count) keywords; \(portal.displayName) takes \(maximum)")
            }
            if let maximum = portal.maxTitleChars, listing.title.count > maximum {
                result.warnings.append("Title is \(listing.title.count) characters; \(portal.displayName) takes \(maximum)")
            }
            if listing.isEditorial, portal.editorial.lowercased() == "no" {
                result.warnings.append("\(portal.displayName) does not take editorial photos")
            }
        }

        // SAL-23: a win can come with strings attached.
        for submission in context.submissions where ["won", "placed"].contains(submission.result.lowercased()) {
            guard let competition = context.competitions[submission.competitionID],
                  competition.rightsIsGrab || competition.rightsIsCaution else { continue }
            result.warnings.append("Check what \(competition.name) may do with winning entries")
        }

        return result
    }

    /// SAL-24: the portals where a photo is out in public.
    public static func publishedPortals(for listings: [Listing], portals: [Portal]) -> [String] {
        listings.filter { $0.status?.isPublished ?? false }.map { portalName($0.portalID, portals) }
    }

    static func portalName(_ id: String, _ portals: [Portal]) -> String {
        portals.first { $0.id == id }?.displayName ?? id
    }

    static func megapixels(_ value: Double) -> String {
        // Small sizes need the second decimal, or 0.26 against 0.3 reads as equal.
        value.formatted(.number.precision(.fractionLength(0...(value < 10 ? 2 : 1))))
    }
}
