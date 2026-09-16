import SwiftUI
import AppKit
import ShowMyBestKit

/// Selling (sales spec 3): what is waiting to go up, what is up, where it can
/// go, and what it has earned. The skill decides what to offer; this view gets
/// the files ready and keeps track of each upload (S2).
struct SalesView: View {
    @Bindable var model: LibraryModel
    var openPhoto: (PhotoKey) -> Void

    @State private var copied: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Broadsheet.divider)
            if !model.sales.anyFileExists {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Broadsheet.Space.six) {
                        switch model.salesSection {
                        case .queue: queue
                        case .listed: listed
                        case .portals: portals
                        case .earnings: earnings
                        }
                    }
                    .padding(Broadsheet.Space.six)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Sales")
                .font(Broadsheet.body(13))
                .foregroundStyle(Broadsheet.secondary)
            Spacer()
            Picker("Section", selection: $model.salesSection) {
                ForEach(LibraryModel.SalesSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 400)
            .disabled(!model.sales.anyFileExists)
        }
        .padding(.horizontal, Broadsheet.Space.four)
        .frame(height: 38)
        .background(Broadsheet.surface)
    }

    /// SAL-2
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
            Text("Nothing for sale yet")
                .font(Broadsheet.heading(24))
            Text("Ask Claude to find portals where your photos could sell. The photo-sales-curator skill researches them, picks photos for each one, and writes portals.csv, listings.csv and later sales.csv into this library. They show up here, ready to prepare and upload.")
                .font(Broadsheet.body(15))
                .foregroundStyle(Broadsheet.secondary)
                .frame(maxWidth: 560, alignment: .leading)
            Text("“Find portals where I could sell my photos, and suggest what to put on them.”")
                .font(Broadsheet.italic(15))
                .padding(.top, Broadsheet.Space.two)
        }
        .padding(Broadsheet.Space.six)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// SAL-3: the count, never the listings.
    @ViewBuilder
    private var hiddenNote: some View {
        let hidden = model.hiddenListingCount
        if hidden > 0 {
            Text("\(hidden) listing\(hidden == 1 ? " is" : "s are") for photos you haven't rated yet, and stay\(hidden == 1 ? "s" : "") hidden until you do.")
                .font(Broadsheet.italic(14))
                .foregroundStyle(Broadsheet.secondary)
        }
    }

    // MARK: - Upload queue (3.2)

    @ViewBuilder
    private var queue: some View {
        hiddenNote
        let groups = model.uploadQueue
        if groups.isEmpty {
            quiet("Nothing waiting to upload. Ask Claude to suggest photos for a portal.")
        }
        ForEach(groups) { group in
            portalGroup(group)
        }
    }

    private func portalGroup(_ group: LibraryModel.PortalGroup) -> some View {
        let assessed = group.listings.map { ($0, model.assessment(for: $0)) }
        let ready = assessed.filter { $0.1.canPrepare }.count
        let prepared = assessed.filter { $0.0.status == .prepared && !$0.1.isHeld }.map(\.0)
        let portal = group.portal
        let isPreparing = model.preparingPortalID == group.portalID
        let folder = ListingExporter.folder(for: group.portalID)

        return VStack(alignment: .leading, spacing: Broadsheet.Space.three) {
            HStack(alignment: .top, spacing: Broadsheet.Space.four) {
                VStack(alignment: .leading, spacing: Broadsheet.Space.one) {
                    HStack(spacing: Broadsheet.Space.two) {
                        if let portal {
                            if !portal.kindLabel.isEmpty { TagLabel(portal.kindLabel) }
                            TagLabel(portal.accountLabel, style: portal.hasActiveAccount ? .accent : .accent2)
                            if portal.isExclusive { TagLabel("Exclusive", style: .outline) }
                            if portal.termsIsGrab { flag("Rights grab") }
                            if portal.termsIsCaution { flag("Caution") }
                        } else {
                            TagLabel("Not in portals.csv", style: .accent2)
                        }
                    }
                    Text(group.title)
                        .font(Broadsheet.heading(26))
                    if let summary = portal?.requirementsSummary, !summary.isEmpty {     // SAL-5
                        Text(summary)
                            .font(Broadsheet.body(14))
                            .foregroundStyle(Broadsheet.secondary)
                    }
                }
                Spacer(minLength: Broadsheet.Space.four)
                VStack(alignment: .trailing, spacing: Broadsheet.Space.two) {
                    HStack(spacing: Broadsheet.Space.two) {
                        if let portal, !portal.hasActiveAccount, !portal.signupURL.isEmpty {
                            Button("Open an account ↗") { open(portal.signupURL) }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        Button(isPreparing ? "Preparing…" : "Prepare \(ready) file\(ready == 1 ? "" : "s")") {
                            Task { await model.prepareFiles(portalID: group.portalID) }       // SAL-7
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(ready == 0 || model.preparingPortalID != nil)
                        .opacity(ready == 0 ? 0.45 : 1)
                    }
                    HStack(spacing: Broadsheet.Space.three) {
                        if FileManager.default.fileExists(atPath: folder.path) {
                            link("Show files") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                        }
                        if let upload = portal?.uploadURL, !upload.isEmpty {
                            link("Open upload page ↗") {                                      // SAL-9
                                open(upload)
                                if FileManager.default.fileExists(atPath: folder.path) {
                                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                                }
                            }
                        }
                        if !prepared.isEmpty {
                            link("Mark \(prepared.count) uploaded") {                          // SAL-10
                                model.setListingStatus(.uploaded, for: prepared)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, Broadsheet.Space.one)
            .overlay(alignment: .bottom) { Rectangle().fill(Broadsheet.divider).frame(height: 1) }

            ForEach(assessed, id: \.0.id) { listing, assessment in
                queueRow(listing, assessment)
                Divider().overlay(Broadsheet.text.opacity(0.08))
            }
        }
        .padding(.bottom, Broadsheet.Space.four)
    }

    /// SAL-6, SAL-8
    private func queueRow(_ listing: Listing, _ assessment: ListingAssessment) -> some View {
        let photo = model.photo(for: listing.photo)
        return HStack(alignment: .top, spacing: Broadsheet.Space.four) {
            thumbnail(photo, width: 150, height: 100)

            VStack(alignment: .leading, spacing: Broadsheet.Space.one) {
                HStack(spacing: Broadsheet.Space.two) {
                    TagLabel(listing.typeLabel)
                    TagLabel(listing.statusLabel, style: statusStyle(listing.status))
                    if let price = priceText(listing) {
                        Text(price).font(Broadsheet.body(13)).foregroundStyle(Broadsheet.secondary)
                    }
                    if !listing.category.isEmpty {
                        Text(listing.category).font(Broadsheet.body(13)).foregroundStyle(Broadsheet.muted)
                    }
                }
                Text(listing.title.isEmpty ? listing.photo.filename : listing.title)
                    .font(Broadsheet.heading(18))
                if !listing.description.isEmpty {
                    Text(listing.description)
                        .font(Broadsheet.body(14))
                        .foregroundStyle(Broadsheet.secondary)
                        .lineLimit(3)
                }
                if !listing.keywords.isEmpty {
                    Text("\(listing.keywords.count) keywords: \(listing.keywords.joined(separator: ", "))")
                        .font(Broadsheet.body(13))
                        .foregroundStyle(Broadsheet.muted)
                        .lineLimit(2)
                        .help(listing.keywords.joined(separator: ", "))
                }
                if !listing.reason.isEmpty {
                    Text(listing.reason)
                        .font(Broadsheet.italic(14))
                        .foregroundStyle(Broadsheet.secondary)
                }
                AssessmentLines(assessment: assessment)
                Text(listing.photo.description + (listing.preparedOn.isEmpty ? "" : " · prepared \(listing.preparedOn)"))
                    .font(Broadsheet.body(12))
                    .foregroundStyle(Broadsheet.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .trailing, spacing: 6) {
                copyButton("title", listing.title, id: "\(listing.id)-title")
                copyButton("description", listing.description, id: "\(listing.id)-description")
                copyButton("keywords", listing.keywords.joined(separator: ", "), id: "\(listing.id)-keywords")
                if listing.status == .prepared {
                    Button("Mark uploaded") { model.setListingStatus(.uploaded, for: [listing]) }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(assessment.isHeld)
                        .opacity(assessment.isHeld ? 0.45 : 1)
                        .padding(.top, Broadsheet.Space.one)
                }
            }
            .frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, Broadsheet.Space.one)
    }

    // MARK: - Listed (3.3)

    @ViewBuilder
    private var listed: some View {
        hiddenNote
        let groups = model.listedByStatus
        if groups.isEmpty {
            quiet("Nothing uploaded yet. Prepare files in the upload queue, upload them on the portal, then mark them uploaded.")
        }
        ForEach(groups, id: \.0?.rawValue) { status, listings in
            VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
                Kicker("\(status?.label ?? "Other status") · \(listings.count)")
                ForEach(listings) { listing in
                    listedRow(listing)
                    Divider().overlay(Broadsheet.text.opacity(0.08))
                }
            }
        }
    }

    private func listedRow(_ listing: Listing) -> some View {
        let photo = model.photo(for: listing.photo)
        let portal = model.sales.portal(id: listing.portalID)
        return HStack(alignment: .top, spacing: Broadsheet.Space.four) {
            thumbnail(photo, width: 96, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Broadsheet.Space.two) {
                    Text(listing.title.isEmpty ? listing.photo.filename : listing.title)
                        .font(Broadsheet.heading(16))
                    TagLabel(listing.typeLabel)
                    if let status = listing.status {
                        TagLabel(status.label, style: statusStyle(status))
                    } else {
                        TagLabel(listing.statusLabel)
                    }
                }
                Text("\(portal?.displayName ?? listing.portalID) · \(dates(listing))")
                    .font(Broadsheet.body(13))
                    .foregroundStyle(Broadsheet.secondary)
                if !listing.notes.isEmpty {
                    Text(listing.notes)
                        .font(Broadsheet.italic(13))
                        .foregroundStyle(Broadsheet.secondary)
                }
                if !listing.portalRef.isEmpty {
                    if listing.portalRef.hasPrefix("http") {
                        link("On \(portal?.displayName ?? "the portal") ↗") { open(listing.portalRef) }
                    } else {
                        Text("Portal reference \(listing.portalRef)")
                            .font(Broadsheet.body(12))
                            .foregroundStyle(Broadsheet.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Broadsheet.Space.two) {                                    // SAL-12
                switch listing.status {
                case .uploaded:
                    Button("Live") { model.setListingStatus(.live, for: [listing]) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Rejected") { model.setListingStatus(.rejected, for: [listing]) }
                        .buttonStyle(SecondaryButtonStyle())
                case .live:
                    Button("Withdrawn") { model.setListingStatus(.withdrawn, for: [listing]) }
                        .buttonStyle(SecondaryButtonStyle())
                case .rejected:
                    Button("Back to queue") { model.setListingStatus(.suggested, for: [listing]) }
                        .buttonStyle(SecondaryButtonStyle())
                        .help("Tell Claude why it was rejected, so it can revise the listing.")
                default:
                    EmptyView()
                }
            }
        }
        .padding(.vertical, Broadsheet.Space.one)
    }

    private func dates(_ listing: Listing) -> String {
        var parts: [String] = []
        if !listing.uploadedOn.isEmpty { parts.append("uploaded \(listing.uploadedOn)") }
        if !listing.liveOn.isEmpty { parts.append("live \(listing.liveOn)") }
        if !listing.endedOn.isEmpty {
            parts.append("\(listing.status == .withdrawn ? "withdrawn" : "ended") \(listing.endedOn)")
        }
        return parts.isEmpty ? "no dates recorded" : parts.joined(separator: " · ")
    }

    // MARK: - Portals (3.4)

    @ViewBuilder
    private var portals: some View {
        if !model.sales.portalsFileExists {
            quiet("There is no portals.csv in the library yet. Claude writes it when it researches where to sell.")
        }
        ForEach(model.sales.portals) { portal in
            portalCard(portal)
        }
    }

    /// SAL-13 to SAL-15
    private func portalCard(_ portal: Portal) -> some View {
        let counts = model.listingCounts(for: portal.id)
        return VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
            HStack(spacing: Broadsheet.Space.two) {
                if !portal.kindLabel.isEmpty { TagLabel(portal.kindLabel) }
                TagLabel(portal.accountLabel, style: portal.hasActiveAccount ? .accent : .neutral)
                if !portal.callLabel.isEmpty {
                    TagLabel(portal.callLabel, style: portal.recommendationCall.lowercased() == "join" ? .accent : .outline)
                }
                if portal.termsIsGrab { flag("Rights grab") }        // SAL-14
                if portal.termsIsCaution { flag("Caution") }
            }
            Text(portal.displayName)
                .font(Broadsheet.heading(26))

            HStack(spacing: Broadsheet.Space.three) {
                if !portal.url.isEmpty { link("\(host(portal.url)) ↗") { open(portal.url) } }
                if !portal.signupURL.isEmpty && !portal.hasActiveAccount { link("Sign up ↗") { open(portal.signupURL) } }
                if !portal.uploadURL.isEmpty { link("Upload page ↗") { open(portal.uploadURL) } }
            }

            if !portal.reasoning.isEmpty {
                Text(portal.callLabel.isEmpty ? portal.reasoning : "\(portal.callLabel). \(portal.reasoning)")
                    .font(Broadsheet.body(16))
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.top, Broadsheet.Space.one)
            }

            FactRows(rows: facts(portal))
                .padding(.top, Broadsheet.Space.one)

            if !portal.termsNotes.isEmpty {
                HStack(alignment: .top, spacing: Broadsheet.Space.three) {
                    Rectangle().fill(Broadsheet.accent2).frame(width: 2)
                    Text("Terms: \(portal.termsNotes)")
                        .font(Broadsheet.body(15))
                }
                .padding(Broadsheet.Space.three)
                .background(Broadsheet.accent2Step(100))
                .frame(maxWidth: 640, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }

            if portal.needsRecheck() {
                Text("Last checked \(portal.lastChecked), over 30 days ago. The terms may have changed, so ask Claude to check again.")
                    .font(Broadsheet.italic(14))
                    .foregroundStyle(Broadsheet.accent2Text)
            }

            let summary = ListingStatus.allCases.compactMap { status in
                counts[status].map { "\($0) \(status.label.lowercased())" }
            }
            if !summary.isEmpty {
                Text("Your listings: \(summary.joined(separator: " · "))")
                    .font(Broadsheet.body(14))
                    .foregroundStyle(Broadsheet.secondary)
            }
        }
        .padding(.bottom, Broadsheet.Space.four)
    }

    private func facts(_ portal: Portal) -> [(String, String)] {
        var rows: [(String, String)] = []
        if !portal.commission.isEmpty { rows.append(("Commission", portal.commission)) }
        if !portal.payout.isEmpty { rows.append(("Payout", portal.payout)) }
        if !portal.exclusivity.isEmpty {
            rows.append(("Exclusivity", portal.isExclusive ? "Exclusive: photos here can't be sold anywhere else" : "Non-exclusive"))
        }
        if !portal.requirementsSummary.isEmpty { rows.append(("Files", portal.requirementsSummary)) }
        if !portal.filmScans.isEmpty { rows.append(("Film scans", yesNo(portal.filmScans))) }
        if !portal.editorial.isEmpty { rows.append(("Editorial", yesNo(portal.editorial))) }
        if !portal.lastChecked.isEmpty { rows.append(("Checked", portal.lastChecked)) }
        return rows
    }

    private func yesNo(_ value: String) -> String {
        switch value.lowercased() {
        case "yes": return "Accepted"
        case "no": return "Not accepted"
        default: return "Unknown"
        }
    }

    // MARK: - Earnings (SAL-16)

    @ViewBuilder
    private var earnings: some View {
        let summary = model.earnings
        HStack(alignment: .top, spacing: Broadsheet.Space.eight) {
            figure("\(model.sales.sales.count)", "sales")
            figure(money(summary.totalsByCurrency), "earned")
        }

        if !summary.byPortal.isEmpty {
            VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
                Kicker("By portal")
                ForEach(summary.byPortal, id: \.portal) { row in
                    HStack {
                        Text(row.portal).font(Broadsheet.body(15)).frame(width: 220, alignment: .leading)
                        Text("\(row.count) sale\(row.count == 1 ? "" : "s")").font(Broadsheet.body(14)).frame(width: 90, alignment: .leading)
                        Text(money(row.totals)).font(Broadsheet.body(14))
                    }
                }
            }
        }

        if !summary.editions.isEmpty {
            VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
                Kicker("Limited editions")
                ForEach(summary.editions, id: \.listing.id) { edition in
                    HStack(spacing: Broadsheet.Space.three) {
                        thumbnail(model.photo(for: edition.listing.photo), width: 72, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(edition.listing.title.isEmpty ? edition.listing.photo.filename : edition.listing.title)
                                .font(Broadsheet.body(15))
                            Text(editionText(edition.listing, sold: edition.sold))
                                .font(Broadsheet.body(13))
                                .foregroundStyle(Broadsheet.secondary)
                        }
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: 0) {
            Kicker("Sales, newest first")
                .padding(.bottom, Broadsheet.Space.two)
            if model.sales.sales.isEmpty {
                quiet(model.sales.salesFileExists
                      ? "sales.csv has no sales yet."
                      : "No sales yet. When something sells, tell Claude and it records the sale in sales.csv.")
            }
            ForEach(model.sales.sales) { sale in
                saleRow(sale)
                Divider().overlay(Broadsheet.text.opacity(0.08))
            }
        }
    }

    private func saleRow(_ sale: Sale) -> some View {
        let photo = model.photo(for: sale.photo)
        return HStack(alignment: .top, spacing: Broadsheet.Space.three) {
            Text(sale.date).frame(width: 96, alignment: .leading)
            thumbnail(photo, width: 72, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(photo?.title.isEmpty == false ? photo!.title : sale.photo.filename)
                Text(sale.photo.description).font(Broadsheet.body(12)).foregroundStyle(Broadsheet.muted)
            }
            .frame(width: 230, alignment: .leading)
            Text(SalesPortalName.of(sale.portalID, model.sales.portals)).frame(width: 150, alignment: .leading)
            Text(saleType(sale)).frame(width: 110, alignment: .leading)
            Text(sale.amount.map { "\(sale.currency) \(amount($0))" } ?? "—").frame(width: 100, alignment: .leading)
            Text(sale.notes).foregroundStyle(Broadsheet.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Broadsheet.body(14))
        .padding(.vertical, Broadsheet.Space.two)
    }

    private func saleType(_ sale: Sale) -> String {
        let type = sale.listingType.isEmpty ? "—" : sale.listingType.capitalized
        return sale.editionNumber.map { "\(type) #\($0)" } ?? type
    }

    private func editionText(_ listing: Listing, sold: Int) -> String {
        var text = listing.editionSize.map { "\(sold) of \($0) sold" } ?? "\(sold) sold"
        text += " · \(model.sales.portal(id: listing.portalID)?.displayName ?? listing.portalID)"
        if let price = priceText(listing) { text += " · \(price)" }
        return text
    }

    // MARK: - Small pieces

    private func thumbnail(_ photo: Photo?, width: CGFloat, height: CGFloat) -> some View {
        PhotoImage(url: photo?.url, maxPixel: 400)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture { if let photo { openPhoto(photo.key) } }
            .help(photo.map { $0.key.description } ?? "The photo is not in the library")
    }

    private func copyButton(_ what: String, _ value: String, id: String) -> some View {
        Button(copied == id ? "Copied" : "Copy \(what)") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copied = id
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if copied == id { copied = nil }
            }
        }
        .buttonStyle(.plain)
        .font(Broadsheet.body(13))
        .foregroundStyle(value.isEmpty ? Broadsheet.muted : Broadsheet.accentText)
        .disabled(value.isEmpty)
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(Broadsheet.body(14))
            .foregroundStyle(Broadsheet.accentText)
    }

    private func quiet(_ text: String) -> some View {
        Text(text)
            .font(Broadsheet.italic(15))
            .foregroundStyle(Broadsheet.secondary)
            .frame(maxWidth: 560, alignment: .leading)
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Broadsheet.heading(34))
            Text(label).font(Broadsheet.body(13)).foregroundStyle(Broadsheet.secondary)
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

    private func statusStyle(_ status: ListingStatus?) -> TagStyle {
        switch status {
        case .prepared, .uploaded: return .outline
        case .live: return .accent
        case .rejected: return .accent2
        default: return .neutral
        }
    }

    private func priceText(_ listing: Listing) -> String? {
        listing.price.map { "\(listing.currency) \(amount($0))".trimmingCharacters(in: .whitespaces) }
    }

    private func amount(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func money(_ totals: [String: Double]) -> String {
        guard !totals.isEmpty else { return "Nothing yet" }
        return totals.sorted { $0.key < $1.key }
            .map { "\($0.key) \(amount($0.value))".trimmingCharacters(in: .whitespaces) }
            .joined(separator: " · ")
    }

    private func host(_ url: String) -> String {
        URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? url
    }

    /// SAL-36: a portal page opens only because Istvan clicked.
    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

private enum SalesPortalName {
    static func of(_ id: String, _ portals: [Portal]) -> String {
        portals.first { $0.id == id }?.displayName ?? id
    }
}

/// A listing's holds, problems and warnings, loudest first. Shared by the
/// queue and the photo detail.
struct AssessmentLines: View {
    let assessment: ListingAssessment

    var body: some View {
        if !assessment.holds.isEmpty || !assessment.problems.isEmpty || !assessment.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(assessment.holds, id: \.self) { line in
                    label("On hold", line, tint: Broadsheet.accent2Text)
                }
                ForEach(assessment.problems, id: \.self) { line in
                    label("Can't prepare", line, tint: Broadsheet.accent2Text)
                }
                ForEach(assessment.warnings, id: \.self) { line in
                    label("Check", line, tint: Broadsheet.secondary)
                }
            }
            .padding(.top, 2)
        }
    }

    private func label(_ kind: String, _ text: String, tint: Color) -> some View {
        (Text("\(kind): ").font(Broadsheet.heading(13)) + Text(text).font(Broadsheet.body(13)))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}
