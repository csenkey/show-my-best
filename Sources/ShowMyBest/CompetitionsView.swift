import SwiftUI
import AppKit
import ShowMyBestKit

/// The competitions view (4.6): soonest deadline first, the skill's call and
/// its reasoning, the rights flags in plain sight, and the matched photos —
/// but only the ones Istvan has rated (IND-4).
struct CompetitionsView: View {
    @Bindable var model: LibraryModel
    var openPhoto: (PhotoKey) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Broadsheet.divider)
            if !model.sidecars.competitionsFileExists {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Broadsheet.Space.eight) {
                        ForEach(model.visibleCompetitions) { competition in
                            row(competition)
                        }
                    }
                    .padding(Broadsheet.Space.six)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Competitions — \(model.openCompetitionCount) open, soonest first")
                .font(Broadsheet.body(13))
                .foregroundStyle(Broadsheet.secondary)
            Spacer()
            if model.closedCompetitionCount > 0 {
                Toggle(isOn: $model.showClosedCompetitions) {      // CMP-2
                    Text("Show closed (\(model.closedCompetitionCount))")
                        .font(Broadsheet.body(12))
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(.horizontal, Broadsheet.Space.four)
        .frame(height: 38)
        .background(Broadsheet.surface)
    }

    /// CMP-8
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
            Text("No competitions yet")
                .font(Broadsheet.heading(24))
            Text("There is no competitions.csv in the library. Claude writes it the next time it searches for competitions.")
                .font(Broadsheet.body(15))
                .foregroundStyle(Broadsheet.secondary)
                .frame(maxWidth: 520, alignment: .leading)
        }
        .padding(Broadsheet.Space.six)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: One competition

    private func row(_ competition: Competition) -> some View {
        let matched = model.matchedPhotos(for: competition)
        return HStack(alignment: .top, spacing: Broadsheet.Space.eight) {
            VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
                HStack(spacing: Broadsheet.Space.two) {
                    statusTag(competition)
                    if !competition.tier.isEmpty { TagLabel(competition.tier) }
                    if !competition.entryFee.isEmpty { TagLabel(competition.entryFee, style: .outline) }
                    // CMP-4: flags are loud, not buried in the text.
                    if competition.rightsIsGrab { flag("Rights grab") }
                    if competition.rightsIsCaution { flag("Caution") }
                }

                Text(competition.name)
                    .font(Broadsheet.heading(26))

                HStack(spacing: 0) {
                    Text(subtitle(competition))
                        .font(Broadsheet.body(14))
                        .foregroundStyle(Broadsheet.secondary)
                    if !competition.url.isEmpty {
                        Button(" \(displayHost(competition.url)) ↗") {
                            // CMP-6: the only thing that touches the network,
                            // and only because Istvan asked (NFR-2).
                            if let url = URL(string: competition.url) { NSWorkspace.shared.open(url) }
                        }
                        .buttonStyle(.plain)
                        .font(Broadsheet.body(14))
                        .foregroundStyle(Broadsheet.accentText)
                    }
                }

                if !competition.reasoning.isEmpty {
                    Text(callSentence(competition))
                        .font(Broadsheet.body(16))
                        .frame(maxWidth: 620, alignment: .leading)
                        .padding(.top, Broadsheet.Space.one)
                }

                FactRows(rows: facts(competition))
                    .padding(.top, Broadsheet.Space.one)

                if !competition.rightsNotes.isEmpty {
                    HStack(alignment: .top, spacing: Broadsheet.Space.three) {
                        Rectangle().fill(Broadsheet.accent2).frame(width: 2)
                        Text("Rights: \(competition.rightsNotes)")
                            .font(Broadsheet.body(15))
                    }
                    .padding(Broadsheet.Space.three)
                    .background(Broadsheet.accent2Step(100))
                    .frame(maxWidth: 620, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if competition.needsRecheck() {      // CMP-7
                    Text("Last checked \(competition.lastChecked) — over 14 days ago, ask Claude to re-check before entering.")
                        .font(Broadsheet.italic(14))
                        .foregroundStyle(Broadsheet.accent2Text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
                Kicker("Matched photos")
                if matched.shown.isEmpty && matched.hiddenUnrated == 0 {
                    Text("None matched yet.")
                        .font(Broadsheet.body(14))
                        .foregroundStyle(Broadsheet.muted)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Broadsheet.Space.two), count: 3),
                              spacing: Broadsheet.Space.two) {
                        ForEach(matched.shown, id: \.0.id) { match, photo in
                            VStack(alignment: .leading, spacing: 3) {
                                PhotoImage(url: photo.url, maxPixel: 240)
                                    .aspectRatio(1, contentMode: .fit)
                                    .onTapGesture { openPhoto(photo.key) }   // CMP-5
                                Text("\(match.role) · \(match.category)")
                                    .font(Broadsheet.body(11))
                                    .foregroundStyle(Broadsheet.secondary)
                                HStack(spacing: 4) {
                                    Text("You \(photo.istvanRating.map(String.init) ?? "—")")
                                        .foregroundStyle(Broadsheet.accentText)
                                    if let claude = photo.claudeRating {
                                        Text("C \(claude)").foregroundStyle(Broadsheet.accent2Text)
                                    }
                                }
                                .font(Broadsheet.body(11))
                            }
                            .help(match.reason)
                        }
                    }
                }
                if matched.hiddenUnrated > 0 {
                    // IND-4: the count only, never the photos.
                    Text("\(matched.hiddenUnrated) matched photo\(matched.hiddenUnrated == 1 ? "" : "s") you haven't rated yet.")
                        .font(Broadsheet.italic(14))
                        .foregroundStyle(Broadsheet.secondary)
                }
            }
            .frame(width: 330)
        }
    }

    private func statusTag(_ competition: Competition) -> some View {
        let status = competition.status()
        let days = competition.daysLeft()
        switch status {
        case .closingSoon:
            return TagLabel("Closing soon — \(days ?? 0) day\(days == 1 ? "" : "s")", style: .accent2)
        case .open:
            return TagLabel(days.map { "Open — \($0) days" } ?? "Open", style: .neutral)
        case .notOpenYet:
            return TagLabel("Not open yet", style: .neutral)
        case .closed:
            return TagLabel("Closed", style: .neutral)
        }
    }

    private func flag(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Broadsheet.heading(12))
            .tracking(0.7)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Broadsheet.accent2Step(700))
            .foregroundStyle(.white)
    }

    private func subtitle(_ competition: Competition) -> String {
        var parts: [String] = []
        if !competition.organizer.isEmpty { parts.append(competition.organizer) }
        if !competition.categories.isEmpty { parts.append(competition.categories.joined(separator: ", ")) }
        if !competition.deadline.isEmpty {
            var deadline = "deadline \(competition.deadline)"
            if !competition.deadlineNote.isEmpty { deadline += ", \(competition.deadlineNote)" }
            parts.append(deadline)
        }
        return parts.joined(separator: " · ")
    }

    private func callSentence(_ competition: Competition) -> String {
        competition.callLabel.isEmpty ? competition.reasoning : "\(competition.callLabel). \(competition.reasoning)"
    }

    /// CMP-3
    private func facts(_ competition: Competition) -> [(String, String)] {
        var rows: [(String, String)] = []
        if !competition.recommendationCall.isEmpty { rows.append(("Call", competition.callLabel)) }
        if !competition.eligibility.isEmpty { rows.append(("Eligibility", competition.eligibility)) }
        if !competition.captureDateRule.isEmpty { rows.append(("Capture date", competition.captureDateRule)) }
        if !competition.previouslyUnpublished.isEmpty {
            rows.append(("Unpublished", unpublishedText(competition.previouslyUnpublished)))
        }
        if !competition.prize.isEmpty { rows.append(("Prize", competition.prize)) }
        if !competition.lastChecked.isEmpty { rows.append(("Checked", competition.lastChecked)) }
        return rows
    }

    private func unpublishedText(_ value: String) -> String {
        switch value.lowercased() {
        case "yes": return "Required — photos you have posted yourself may not qualify"
        case "no": return "No requirement — your own posts are fine"
        default: return "Unknown — check before entering"
        }
    }

    private func displayHost(_ url: String) -> String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
    }
}
