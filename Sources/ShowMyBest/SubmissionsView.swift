import SwiftUI
import ShowMyBestKit

/// What Istvan entered and how it went (4.7). Read-only: entries are logged by
/// the skill after he confirms them in the Claude chat (D19).
struct SubmissionsView: View {
    @Bindable var model: LibraryModel
    var openPhoto: (PhotoKey) -> Void

    private var submissions: [Submission] { model.sidecars.submissions }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Submissions")
                    .font(Broadsheet.body(13))
                    .foregroundStyle(Broadsheet.secondary)
                Spacer()
            }
            .padding(.horizontal, Broadsheet.Space.four)
            .frame(height: 38)
            .background(Broadsheet.surface)

            Divider().overlay(Broadsheet.divider)

            if submissions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Broadsheet.Space.six) {
                        summary
                        table
                        Text("Read from submissions.csv. Entries are logged by the skill after you confirm them in the Claude chat — this view is read-only.")
                            .font(Broadsheet.italic(14))
                            .foregroundStyle(Broadsheet.muted)
                    }
                    .padding(Broadsheet.Space.six)
                }
            }
        }
    }

    /// SUB-6
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
            Text("Nothing entered yet")
                .font(Broadsheet.heading(24))
            Text(model.sidecars.submissionsFileExists
                 ? "submissions.csv has no entries. Tell Claude what you entered and it records them here."
                 : "There is no submissions.csv in the library yet. Tell Claude what you entered and it writes the file.")
                .font(Broadsheet.body(15))
                .foregroundStyle(Broadsheet.secondary)
                .frame(maxWidth: 520, alignment: .leading)
        }
        .padding(Broadsheet.Space.six)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// SUB-5
    private var summary: some View {
        let totals = model.submissionSummary
        return HStack(alignment: .top, spacing: Broadsheet.Space.eight) {
            figure("\(totals.entries)", "entries")
            figure(feesText(totals.feesByCurrency), "fees paid")
            figure(resultsText(totals.results), "results")
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Broadsheet.heading(34))
            Text(label).font(Broadsheet.body(13)).foregroundStyle(Broadsheet.secondary)
        }
    }

    private func feesText(_ fees: [String: Double]) -> String {
        guard !fees.isEmpty else { return "None" }
        return fees.sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value.formatted(.number.precision(.fractionLength(0...2))))" }
            .joined(separator: " · ")
    }

    private func resultsText(_ results: [String: Int]) -> String {
        let order = ["Won", "Placed", "Pending", "No award"]
        let parts = order.compactMap { label in results[label].map { "\($0) \(label.lowercased())" } }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    // MARK: The table (SUB-1)

    private var table: some View {
        VStack(spacing: 0) {
            headerRow
            ForEach(submissions) { submission in
                row(submission)
                Divider().overlay(Broadsheet.text.opacity(0.08))
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .bottom, spacing: Broadsheet.Space.two) {
            cell("Date", width: 96)
            cell("Competition", width: 210)
            cell("Category", width: 100)
            cell("Photos", width: 130)
            cell("Fee", width: 80)
            cell("Call then", width: 120)
            cell("Result", width: 90)
            cell("Notes", width: nil)
        }
        .font(Broadsheet.kicker())
        .tracking(1)
        .foregroundStyle(Broadsheet.muted)
        .padding(.vertical, Broadsheet.Space.two)
        .overlay(alignment: .bottom) { Rectangle().fill(Broadsheet.divider).frame(height: 1) }
    }

    private func row(_ submission: Submission) -> some View {
        HStack(alignment: .top, spacing: Broadsheet.Space.two) {
            cell(submission.dateSubmitted, width: 96)
            competitionCell(submission)
            cell(submission.category, width: 100)
            HStack(spacing: 4) {
                // SUB-3
                ForEach(submission.photos.prefix(3), id: \.self) { key in
                    PhotoImage(url: model.photo(for: key)?.url, maxPixel: 120)
                        .frame(width: 34, height: 24)
                        .onTapGesture { openPhoto(key) }
                        .help(key.description)
                }
                if submission.photos.count > 3 {
                    Text("+\(submission.photos.count - 3)")
                        .font(Broadsheet.body(11))
                        .foregroundStyle(Broadsheet.muted)
                }
            }
            .frame(width: 130, alignment: .leading)
            cell(submission.entryFee.isEmpty ? "—" : submission.entryFee, width: 80)
            cell(callLabel(submission.recommendationCall), width: 120)
            HStack {
                TagLabel(submission.resultLabel, style: resultStyle(submission.resultLabel))
            }
            .frame(width: 90, alignment: .leading)
            cell(submission.notes, width: nil)
        }
        .font(Broadsheet.body(14))
        .padding(.vertical, Broadsheet.Space.two)
    }

    /// SUB-4: the entry points at its competition.
    private func competitionCell(_ submission: Submission) -> some View {
        Group {
            if let competition = model.sidecars.competition(id: submission.competitionID) {
                Button(competition.name) {
                    model.screen = .competitions
                }
                .buttonStyle(.plain)
                .foregroundStyle(Broadsheet.accentText)
            } else {
                Text(submission.competitionName)
            }
        }
        .font(Broadsheet.body(14))
        .frame(width: 210, alignment: .leading)
    }

    private func cell(_ text: String, width: CGFloat?) -> some View {
        Text(text)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func callLabel(_ call: String) -> String {
        switch call.lowercased() {
        case "enter": return "Enter"
        case "skip": return "Skip"
        case "worth-it-regardless": return "Worth it regardless"
        default: return call.isEmpty ? "—" : call
        }
    }

    private func resultStyle(_ label: String) -> TagStyle {
        switch label {
        case "Won", "Placed": return .accent
        case "Pending": return .outline
        default: return .neutral
        }
    }
}
