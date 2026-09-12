import SwiftUI
import AppKit
import ShowMyBestKit

struct GalleryView: View {
    @Bindable var model: LibraryModel
    var openPhoto: (PhotoKey) -> Void
    var startReview: () -> Void

    @FocusState private var gridHasFocus: Bool
    @State private var anchor: PhotoKey?

    private var photos: [Photo] { model.visiblePhotos }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Broadsheet.divider)
            FilterBar(model: model)
            Divider().overlay(Broadsheet.divider)
            grid
            Divider().overlay(Broadsheet.divider)
            statusBar
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Broadsheet.Space.three) {
            Text(model.scope.title)
                .font(Broadsheet.heading(17))
            Text("\(photos.count) photo\(photos.count == 1 ? "" : "s")")
                .font(Broadsheet.body(13))
                .foregroundStyle(Broadsheet.muted)

            Spacer()

            Text("Thumb size")
                .font(Broadsheet.body(12))
                .foregroundStyle(Broadsheet.muted)
            Slider(value: $model.thumbnailSize, in: 110...360)      // GAL-7
                .frame(width: 110)
                .controlSize(.small)

            Button("Review mode ⇧⌘R") { startReview() }             // CUL-2
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        .padding(.horizontal, Broadsheet.Space.four)
        .padding(.vertical, Broadsheet.Space.two)
        .background(Broadsheet.surface)
    }

    // MARK: Grid

    private var grid: some View {
        GeometryReader { geometry in
            let columnCount = max(1, Int(geometry.size.width - Broadsheet.Space.four * 2) / Int(model.thumbnailSize + Broadsheet.Space.three))
            ScrollViewReader { scroller in
                ScrollView {
                    if photos.isEmpty {
                        emptyScope
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Broadsheet.Space.four)
                    } else {
                        if model.excludedUnratedCount > 0 {
                            // IND-3: say how many unrated photos were left out.
                            Text(indNote)
                                .font(Broadsheet.italic(14))
                                .foregroundStyle(Broadsheet.accent2Text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Broadsheet.Space.four)
                                .padding(.top, Broadsheet.Space.three)
                        }
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: Broadsheet.Space.three), count: columnCount),
                            spacing: Broadsheet.Space.three
                        ) {
                            ForEach(photos) { photo in
                                ThumbnailCell(
                                    photo: photo,
                                    size: model.thumbnailSize,
                                    isSelected: model.selection.contains(photo.key),
                                    showCritiqueMarkers: model.hasCritiqueColumns
                                )
                                .id(photo.key)
                                .onTapGesture(count: 2) { openPhoto(photo.key) }   // GAL-10
                                .onTapGesture {
                                    select(photo.key, extending: NSEvent.modifierFlags.contains(.command))
                                    gridHasFocus = true
                                }
                            }
                        }
                        .padding(Broadsheet.Space.four)
                    }
                }
                .onChange(of: anchor) { _, key in
                    guard let key else { return }
                    withAnimation(.easeOut(duration: 0.12)) { scroller.scrollTo(key, anchor: .center) }
                }
            }
        }
        .background(Broadsheet.bg)
        .focusable()
        .focusEffectDisabled()
        .focused($gridHasFocus)
        .onKeyPress { press in handle(press) }
        .onAppear { gridHasFocus = true }
    }

    private var indNote: String {
        let count = model.excludedUnratedCount
        let reason: String
        switch model.scope {
        case .collection(let collection) where collection.dependsOnClaude:
            reason = collection.title
        default:
            reason = model.sortOrder.dependsOnClaude ? "Sorted by Claude's rating" : "Filtered by Claude's rating"
        }
        return "\(reason) — \(count) photo\(count == 1 ? "" : "s") you haven't rated \(count == 1 ? "is" : "are") left out."
    }

    @ViewBuilder
    private var emptyScope: some View {
        VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
            Text("Nothing here")
                .font(Broadsheet.heading(24))
            if case .collection(.missingFiles) = model.scope {
                Text("Every catalogue row has its photo on disk.")
                    .font(Broadsheet.body(15))
                    .foregroundStyle(Broadsheet.secondary)
            } else if model.excludedUnratedCount > 0 {
                Text(indNote)
                    .font(Broadsheet.body(15))
                    .foregroundStyle(Broadsheet.secondary)
            } else if !model.filters.isEmpty {
                Text("No photo matches these filters.")
                    .font(Broadsheet.body(15))
                    .foregroundStyle(Broadsheet.secondary)
            } else {
                Text("No photos in this scope.")
                    .font(Broadsheet.body(15))
                    .foregroundStyle(Broadsheet.secondary)
            }
        }
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: Broadsheet.Space.four) {
            if model.selection.count == 1, let key = model.selection.first {
                Text("1 selected · \(key.filename)")
            } else if model.selection.count > 1 {
                Text("\(model.selection.count) selected")
            } else {
                Text("Nothing selected")
            }
            Text("1–5 rate · 0 clear · ⏎ open · ⌘R reload")
            Spacer()
            if model.pendingRatingCount > 0 {
                Text("\(model.pendingRatingCount) change\(model.pendingRatingCount == 1 ? "" : "s") waiting to be saved")
                    .foregroundStyle(Broadsheet.accent2Text)
            } else if let reloaded = model.lastReloadedAt {
                Text("Reloaded \(Self.relative.localizedString(for: reloaded, relativeTo: Date()))")
                    .foregroundStyle(Broadsheet.accentText)
            }
        }
        .font(Broadsheet.body(12))
        .foregroundStyle(Broadsheet.secondary)
        .padding(.horizontal, Broadsheet.Space.four)
        .padding(.vertical, Broadsheet.Space.two)
        .background(Broadsheet.surface)
    }

    private static let relative = RelativeDateTimeFormatter()

    // MARK: Selection and keys

    private func select(_ key: PhotoKey, extending: Bool) {
        if extending {
            if model.selection.contains(key) {
                model.selection.remove(key)
            } else {
                model.selection.insert(key)
            }
        } else {
            model.selection = [key]
        }
        anchor = key
    }

    private func move(by offset: Int) {
        guard !photos.isEmpty else { return }
        let current = anchor.flatMap { key in photos.firstIndex { $0.key == key } } ?? 0
        let next = max(0, min(photos.count - 1, current + offset))
        select(photos[next].key, extending: false)
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .leftArrow: move(by: -1); return .handled
        case .rightArrow: move(by: 1); return .handled
        case .upArrow: move(by: -columnCountEstimate); return .handled
        case .downArrow: move(by: columnCountEstimate); return .handled
        case .return:
            if let key = anchor ?? model.selection.first { openPhoto(key) }   // GAL-10
            return .handled
        default:
            break
        }
        // GAL-8, GAL-9: rate everything selected.
        switch press.characters {
        case "1", "2", "3", "4", "5":
            model.rateSelection(Int(press.characters))
            return .handled
        case "0":
            model.rateSelection(nil)
            return .handled
        default:
            return .ignored
        }
    }

    /// Good enough for up and down: the grid is laid out from this same number.
    private var columnCountEstimate: Int {
        max(1, Int((NSApp.keyWindow?.contentView?.bounds.width ?? 1200) - 260) / Int(model.thumbnailSize + Broadsheet.Space.three))
    }
}

// MARK: - Thumbnail

struct ThumbnailCell: View {
    let photo: Photo
    let size: CGFloat
    let isSelected: Bool
    var showCritiqueMarkers: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            PhotoImage(url: photo.url, maxPixel: Int(size * 2))
                .aspectRatio(3.0 / 2.0, contentMode: .fit)
                .overlay {
                    if isSelected {
                        Rectangle().stroke(Broadsheet.accent, lineWidth: 2).padding(-2)
                    }
                }
                .overlay {
                    if !photo.isOnDisk {
                        Text("File missing")
                            .font(Broadsheet.body(12))
                            .foregroundStyle(Broadsheet.bg)
                            .padding(4)
                            .background(Broadsheet.neutral(700))
                    }
                }

            HStack(spacing: 6) {
                Stars(rating: photo.istvanRating)
                // GAL-5: Claude's rating only for photos Istvan has rated.
                if let claude = photo.claudeRating {
                    Text("C \(claude)")
                        .font(Broadsheet.body(12))
                        .foregroundStyle(Broadsheet.accent2Text)
                }
                if showCritiqueMarkers, photo.hasCritique {
                    Text(photo.critiqueIsOutOfDate ? "◇" : "◆")
                        .font(Broadsheet.body(12))
                        .foregroundStyle(photo.critiqueIsOutOfDate ? Broadsheet.muted : Broadsheet.text)
                        .help(photo.critiqueIsOutOfDate ? "Critique out of date" : "Has a critique")
                }
                if let gap = photo.disagreement, gap >= 2 {
                    TagLabel("differ by \(gap)", style: .accent2)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)

            // GAL-6
            if photo.isOnDisk, !photo.isCatalogued {
                TagLabel("Not catalogued")
            } else if photo.isWaitingForClaude {
                TagLabel("Waiting for Claude")
            }
        }
        .frame(width: size, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// NFR-11: ratings and markers read out loud.
    private var accessibilityText: String {
        var parts = [photo.filename, photo.shoot]
        parts.append(photo.istvanRating.map { "my rating \($0)" } ?? "not rated by me")
        if let claude = photo.claudeRating { parts.append("Claude's rating \(claude)") }
        if photo.hasCritique { parts.append(photo.critiqueIsOutOfDate ? "critique out of date" : "has a critique") }
        if !photo.isCatalogued { parts.append("not catalogued") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Filters (GAL-3, GAL-4)

struct FilterBar: View {
    @Bindable var model: LibraryModel

    var body: some View {
        HStack(spacing: Broadsheet.Space.two) {
            ratingMenu(
                title: "My rating",
                selection: $model.filters.myRating,
                includeUnrated: true
            )
            // IND-3: filtering by Claude's rating can only narrow the rated ones.
            ratingMenu(
                title: "Claude's rating",
                selection: $model.filters.claudeRating,
                includeUnrated: false
            )
            optionalMenu(title: "Genre", options: model.availableTags, selection: $model.filters.tag)
            if model.hasMediumColumn {   // SYN-5: hidden until the column exists
                optionalMenu(title: "Medium", options: ["digital", "film"], selection: $model.filters.medium)
            }
            optionalMenu(title: "Camera", options: model.availableCameras, selection: $model.filters.cameraOrFormat)
            optionalMenu(title: "Status", options: model.availableStatuses, selection: $model.filters.status)

            if !model.filters.isEmpty {
                Button("Clear filters") { model.filters = LibraryModel.Filters() }
                    .buttonStyle(.plain)
                    .font(Broadsheet.body(13))
                    .foregroundStyle(Broadsheet.accentText)
            }

            Spacer()

            Picker("Sort", selection: $model.sortOrder) {
                ForEach(LibraryModel.SortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 210)
            .font(Broadsheet.body(13))
        }
        .padding(.horizontal, Broadsheet.Space.four)
        .padding(.vertical, Broadsheet.Space.two)
    }

    private func ratingMenu(title: String, selection: Binding<Set<Int>>, includeUnrated: Bool) -> some View {
        Menu {
            if includeUnrated {
                toggle("Unrated", value: 0, selection: selection)
                Divider()
            }
            ForEach((1...5).reversed(), id: \.self) { value in
                toggle(String(repeating: "★", count: value), value: value, selection: selection)
            }
            if !selection.wrappedValue.isEmpty {
                Divider()
                Button("Any") { selection.wrappedValue = [] }
            }
        } label: {
            Text(label(title, detail: summary(selection.wrappedValue)))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func toggle(_ title: String, value: Int, selection: Binding<Set<Int>>) -> some View {
        Button {
            if selection.wrappedValue.contains(value) {
                selection.wrappedValue.remove(value)
            } else {
                selection.wrappedValue.insert(value)
            }
        } label: {
            Text(selection.wrappedValue.contains(value) ? "✓ \(title)" : title)
        }
    }

    private func optionalMenu(title: String, options: [String], selection: Binding<String?>) -> some View {
        Menu {
            Button("Any") { selection.wrappedValue = nil }
            Divider()
            ForEach(options, id: \.self) { option in
                Button(selection.wrappedValue == option ? "✓ \(option)" : option) {
                    selection.wrappedValue = option
                }
            }
        } label: {
            Text(label(title, detail: selection.wrappedValue))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(options.isEmpty)
    }

    private func label(_ title: String, detail: String?) -> AttributedString {
        var text = AttributedString("\(title): \(detail ?? "any")")
        text.font = Broadsheet.body(13)
        return text
    }

    private func summary(_ values: Set<Int>) -> String? {
        guard !values.isEmpty else { return nil }
        return values.sorted().map { $0 == 0 ? "unrated" : "\($0)" }.joined(separator: ", ")
    }
}
