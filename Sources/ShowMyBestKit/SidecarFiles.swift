import Foundation

/// The three files the skill writes and the app only reads: competitions,
/// their photo matches and submissions. A missing file is not an error
/// (SYN-4) — the views say what would create it (CMP-8, SUB-6).
public struct SidecarFiles {
    public var competitions: [Competition] = []
    public var matches: [CompetitionMatch] = []
    public var submissions: [Submission] = []

    public var competitionsFileExists = false
    public var submissionsFileExists = false
    /// One message per file that would not parse (SYN-3).
    public var errors: [String] = []

    public func matches(for competitionID: String) -> [CompetitionMatch] {
        matches.filter { $0.competitionID == competitionID }
    }

    public func matches(for key: PhotoKey) -> [CompetitionMatch] {
        matches.filter { $0.key == key }
    }

    public func competition(id: String) -> Competition? {
        competitions.first { $0.id == id }
    }

    public func submissions(including key: PhotoKey) -> [Submission] {
        submissions.filter { $0.photos.contains(key) }
    }
}

public enum SidecarLoader {
    public static func load(libraryURL: URL) -> SidecarFiles {
        var files = SidecarFiles()
        let fileManager = FileManager.default

        let competitionsURL = libraryURL.appendingPathComponent("competitions.csv")
        if fileManager.fileExists(atPath: competitionsURL.path) {
            files.competitionsFileExists = true
            switch read(competitionsURL) {
            case .success(let document):
                let index = ColumnIndex(document: document)
                files.competitions = document.records.compactMap { record in
                    let id = index.value("competition_id", record)
                    guard !id.isEmpty else { return nil }
                    var competition = Competition(id: id)
                    competition.name = index.value("name", record)
                    competition.organizer = index.value("organizer", record)
                    competition.url = index.value("url", record)
                    competition.categories = index.value("categories", record)
                        .split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    competition.opens = index.value("opens", record)
                    competition.deadline = index.value("deadline", record)
                    competition.deadlineNote = index.value("deadline_note", record)
                    competition.entryFee = index.value("entry_fee", record)
                    competition.feeAmount = Double(index.value("fee_amount", record))
                    competition.feeCurrency = index.value("fee_currency", record)
                    competition.tier = index.value("tier", record)
                    competition.eligibility = index.value("eligibility", record)
                    competition.captureDateRule = index.value("capture_date_rule", record)
                    competition.previouslyUnpublished = index.value("previously_unpublished", record)
                    competition.prize = index.value("prize", record)
                    competition.rightsFlag = index.value("rights_flag", record)
                    competition.rightsNotes = index.value("rights_notes", record)
                    competition.recommendationCall = index.value("recommendation_call", record)
                    competition.reasoning = index.value("reasoning", record)
                    competition.lastChecked = index.value("last_checked", record)
                    return competition
                }
            case .failure(let message):
                files.errors.append("competitions.csv: \(message)")
            }
        }

        let matchesURL = libraryURL.appendingPathComponent("competition_matches.csv")
        if fileManager.fileExists(atPath: matchesURL.path) {
            switch read(matchesURL) {
            case .success(let document):
                let index = ColumnIndex(document: document)
                files.matches = document.records.compactMap { record in
                    let id = index.value("competition_id", record)
                    let filename = index.value("filename", record)
                    guard !id.isEmpty, !filename.isEmpty else { return nil }
                    var match = CompetitionMatch(
                        competitionID: id,
                        key: PhotoKey(shoot: index.value("source_folder", record), filename: filename)
                    )
                    match.category = index.value("category", record)
                    match.role = index.value("role", record)
                    match.reason = index.value("reason", record)
                    match.matchedOn = index.value("matched_on", record)
                    return match
                }
            case .failure(let message):
                files.errors.append("competition_matches.csv: \(message)")
            }
        }

        let submissionsURL = libraryURL.appendingPathComponent("submissions.csv")
        if fileManager.fileExists(atPath: submissionsURL.path) {
            files.submissionsFileExists = true
            switch read(submissionsURL) {
            case .success(let document):
                let index = ColumnIndex(document: document)
                files.submissions = document.records.compactMap { record in
                    let name = index.value("competition_name", record)
                    let date = index.value("date_submitted", record)
                    guard !name.isEmpty || !date.isEmpty else { return nil }
                    var submission = Submission()
                    submission.dateSubmitted = date
                    submission.competitionID = index.value("competition_id", record)
                    submission.competitionName = name
                    submission.entryFee = index.value("entry_fee", record)
                    submission.deadline = index.value("deadline", record)
                    submission.photos = index.value("photos_submitted", record)
                        .split(separator: ";")
                        .compactMap { PhotoKey(reference: $0.trimmingCharacters(in: .whitespaces)) }
                    submission.category = index.value("category", record)
                    submission.recommendationCall = index.value("recommendation_call", record)
                    submission.result = index.value("result", record)
                    submission.notes = index.value("notes", record)
                    return submission
                }
                // SUB-1: newest first.
                files.submissions.sort { $0.dateSubmitted > $1.dateSubmitted }
            case .failure(let message):
                files.errors.append("submissions.csv: \(message)")
            }
        }

        return files
    }

    enum ReadOutcome {
        case success(CSVDocument)
        case failure(String)
    }

    private static func read(_ url: URL) -> ReadOutcome {
        do {
            return .success(try CSV.parse(data: try Data(contentsOf: url)))
        } catch let error as CSVError {
            return .failure(error.description)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
