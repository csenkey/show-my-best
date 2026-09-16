import SwiftUI
import AppKit
import ShowMyBestKit

/// The photo detail (4.4). Before Istvan has rated the photo this shows only
/// what describes it (IND-2); rating it reveals Claude's side (IND-5).
struct PhotoDetailView: View {
    @Bindable var model: LibraryModel
    let key: PhotoKey
    var openPhoto: (PhotoKey) -> Void
    @Environment(\.dismiss) private var dismiss

    private var photo: Photo? { model.photo(for: key) }

    var body: some View {
        VStack(spacing: 0) {
            if let photo {
                titleBar(photo)
                Divider().overlay(Broadsheet.divider)
                ScrollView {
                    VStack(alignment: .leading, spacing: Broadsheet.Space.six) {
                        PhotoImage(url: photo.url, maxPixel: 2400, display: true, contentMode: .fit)
                            .aspectRatio(3.0 / 2.0, contentMode: .fit)
                            .background(Broadsheet.photoGround)

                        HStack(alignment: .top, spacing: Broadsheet.Space.eight) {
                            main(photo)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            side(photo)
                                .frame(width: 250)
                        }
                    }
                    .padding(Broadsheet.Space.six)
                }
            } else {
                Text("This photo is no longer in the library.")
                    .font(Broadsheet.body(15))
                    .padding(Broadsheet.Space.six)
            }
        }
        .background(Broadsheet.bg)
        .foregroundStyle(Broadsheet.text)
        // The detail is a sheet over the gallery, which keeps keyboard focus,
        // so the keys come through a monitor rather than .onKeyPress.
        .keyMonitor(isActive: true) { event in
            guard !event.modifierFlags.contains(.command) else { return false }
            if event.keyCode == Key.escape {
                dismiss()
                return true
            }
            switch event.charactersIgnoringModifiers ?? "" {
            case "1", "2", "3", "4", "5":
                model.setRating(Int(event.charactersIgnoringModifiers ?? ""), for: key)
                return true
            case "0":
                model.setRating(nil, for: key)
                return true
            default:
                return false
            }
        }
    }

    // MARK: Title bar

    private func titleBar(_ photo: Photo) -> some View {
        HStack(spacing: Broadsheet.Space.three) {
            Text("\(photo.filename) — \(photo.shoot)")
                .font(Broadsheet.body(13))
                .foregroundStyle(Broadsheet.secondary)
            Spacer()
            if let url = photo.url {
                Button("Show in Finder") {           // DET-7
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.plain)
                .font(Broadsheet.body(12))
                .foregroundStyle(Broadsheet.accentText)
                Button("Open with…") {               // DET-8
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.plain)
                .font(Broadsheet.body(12))
                .foregroundStyle(Broadsheet.accentText)
            }
            Button("Close") { dismiss() }
                .buttonStyle(.plain)
                .font(Broadsheet.body(12))
                .foregroundStyle(Broadsheet.accentText)
        }
        .padding(.horizontal, Broadsheet.Space.three)
        .frame(height: 38)
        .background(Broadsheet.surface)
    }

    // MARK: The describing half — shown whether or not the photo is rated

    @ViewBuilder
    private func main(_ photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: Broadsheet.Space.four) {
            VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
                Text(photo.title.isEmpty ? photo.filename : photo.title)
                    .font(Broadsheet.heading(30))
                if let subject = photo.row?.subject, !subject.isEmpty {
                    Text(subject)
                        .font(Broadsheet.body(16))
                        .foregroundStyle(Broadsheet.secondary)
                        .frame(maxWidth: 520, alignment: .leading)
                }
                if !photo.tags.isEmpty || !photo.status.isEmpty {
                    HStack(spacing: Broadsheet.Space.two) {
                        ForEach(photo.tags, id: \.self) { TagLabel($0) }
                        if !photo.status.isEmpty { TagLabel(photo.status) }
                    }
                }
            }

            if photo.isRevealed {
                revealed(photo)
            }
        }
    }

    /// Everything below is Claude's, and only exists once Istvan has rated the
    /// photo (IND-1).
    @ViewBuilder
    private func revealed(_ photo: Photo) -> some View {
        if !photo.claudeRationale.isEmpty {
            block("Claude's rationale") {
                Text(photo.claudeRationale)
                    .font(Broadsheet.body(16))
            }
        }

        if photo.hasCritique {
            VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
                HStack(spacing: Broadsheet.Space.two) {
                    Kicker("Critique")
                    if photo.critiqueIsOutOfDate, let written = photo.critiqueWrittenForRating {
                        // IND-7
                        TagLabel("Out of date — written when you rated this \(written)", style: .accent2)
                    }
                }
                HStack(spacing: Broadsheet.Space.three) {
                    Rectangle().fill(Broadsheet.accent2).frame(width: 2)
                    Text(photo.claudeCritique)
                        .font(Broadsheet.italic(17))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }

        let matches = model.matches(for: photo)
        if !matches.isEmpty {
            block("Matched competitions") {         // DET-4
                VStack(alignment: .leading, spacing: Broadsheet.Space.three) {
                    ForEach(matches, id: \.0.id) { match, competition in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: Broadsheet.Space.two) {
                                Text(competition?.name ?? match.competitionID)
                                    .font(Broadsheet.body(16))
                                TagLabel(match.isPrimary ? "primary" : "alternate",
                                         style: match.isPrimary ? .accent : .neutral)
                                if let competition {
                                    Text(deadlineText(match, competition))
                                        .font(Broadsheet.body(14))
                                        .foregroundStyle(Broadsheet.secondary)
                                }
                            }
                            if !match.reason.isEmpty {
                                Text(match.reason)
                                    .font(Broadsheet.body(14))
                                    .foregroundStyle(Broadsheet.secondary)
                            }
                        }
                    }
                    if !photo.competitionFitNotes.isEmpty {
                        Text(photo.competitionFitNotes)
                            .font(Broadsheet.italic(14))
                            .foregroundStyle(Broadsheet.muted)
                    }
                }
            }
        }

        let submissions = model.submissions(including: photo.key)
        if !submissions.isEmpty {
            block("Submitted") {                    // DET-5
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(submissions) { submission in
                        HStack(spacing: Broadsheet.Space.two) {
                            Text("\(submission.dateSubmitted) · \(submission.competitionName)")
                                .font(Broadsheet.body(15))
                            TagLabel(submission.resultLabel, style: resultStyle(submission.resultLabel))
                        }
                    }
                }
            }
        }
    }

    private func deadlineText(_ match: CompetitionMatch, _ competition: Competition) -> String {
        var parts: [String] = []
        if !match.category.isEmpty { parts.append(match.category) }
        if !competition.deadline.isEmpty {
            if let days = competition.daysLeft(), days >= 0 {
                parts.append("closes \(competition.deadline) (\(days) day\(days == 1 ? "" : "s"))")
            } else {
                parts.append("closed \(competition.deadline)")
            }
        }
        return "· " + parts.joined(separator: " · ")
    }

    private func resultStyle(_ label: String) -> TagStyle {
        switch label {
        case "Won", "Placed": return .accent
        case "Pending": return .outline
        default: return .neutral
        }
    }

    // MARK: The ratings column

    @ViewBuilder
    private func side(_ photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: Broadsheet.Space.four) {
            VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
                Kicker("My rating")
                RatingBoxes(rating: photo.istvanRating) { model.setRating($0, for: key) }   // DET-2
                Text(ratingStatus(photo))
                    .font(Broadsheet.body(13))
                    .foregroundStyle(Broadsheet.secondary)
            }

            Divider().overlay(Broadsheet.divider)

            VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
                Kicker("Claude's view")
                if !photo.isRevealed {
                    // IND-1: nothing of Claude's, and no way to ask for it.
                    Text("Hidden until you rate this photo. Rating, rationale, critique and competition matches all appear then.")
                        .font(Broadsheet.italic(15))
                        .foregroundStyle(Broadsheet.secondary)
                } else if let claude = photo.claudeRating {
                    Text("\(claude)")
                        .font(Broadsheet.heading(44))
                        .foregroundStyle(Broadsheet.accent2Text)
                    Text("Rated blind\(photo.row?.lastUpdated.isEmpty == false ? " · \(photo.row!.lastUpdated)" : "")")
                        .font(Broadsheet.body(13))
                        .foregroundStyle(Broadsheet.secondary)
                } else {
                    Text("Waiting for Claude — this photo has no rating from the skill yet.")
                        .font(Broadsheet.italic(15))
                        .foregroundStyle(Broadsheet.secondary)
                }
            }

            Divider().overlay(Broadsheet.divider)

            FactRows(rows: facts(photo), valueFont: Broadsheet.body(13))
        }
    }

    private func ratingStatus(_ photo: Photo) -> String {
        if model.pendingRatings.contains(where: { $0.key == photo.key }) {
            return "Held — waiting for catalogue.csv to be readable"
        }
        return photo.istvanRating == nil ? "Not rated · press 1–5" : "Saved to catalogue.csv"
    }

    /// DET-1 and DET-6: what the catalogue says, then what the file says.
    private func facts(_ photo: Photo) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let row = photo.row {
            if !row.dateTaken.isEmpty {
                let suffix = row.dateNote.isEmpty ? "" : " — \(row.dateNote)"
                rows.append(("Taken", row.dateTaken + suffix))
            }
            if !row.medium.isEmpty { rows.append(("Medium", row.medium == "film" ? "Film · negative scan" : "Digital")) }
            if !row.cameraOrFormat.isEmpty { rows.append(("Camera", row.cameraOrFormat)) }
        }
        rows.append(("Shoot", photo.shoot))
        if !photo.isCatalogued { rows.append(("Catalogue", "No row yet — rating one adds it")) }
        if !photo.isOnDisk { rows.append(("File", "Missing from disk")) }
        if let url = photo.url {
            let settings = ImageCache.metadata(for: url)
            let compact = settings.filter { $0.0 != "Camera (file)" }.map(\.1).joined(separator: " · ")
            if !compact.isEmpty { rows.append(("File", compact)) }
        }
        return rows
    }

    private func block(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
            Kicker(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
