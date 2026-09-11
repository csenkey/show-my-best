import SwiftUI
import AppKit
import Observation
import ShowMyBestKit

/// Review mode's state (4.3). The photo list is fixed when review starts, so
/// rating a photo out of the scope does not make it vanish under the cursor
/// (CUL-7).
@MainActor
@Observable
final class ReviewSession {
    enum ScopeChoice: Hashable {
        case notRatedInShoot, allInShoot, currentView, notRatedInView
    }

    var isActive = false
    var isChoosingScope = false
    var choice: ScopeChoice = .currentView
    var offeredChoices: [ScopeChoice] = []
    var keys: [PhotoKey] = []
    var index = 0
    var showInfo = false
    var showFilmstrip = true
    var showOverlay = true
    var isZoomed = false
    var lastRating: String?

    /// CUL-10: one step back, saved like any other rating change.
    private var undoStack: [(PhotoKey, Int?)] = []
    private var didEnterFullScreen = false

    var currentKey: PhotoKey? { keys.indices.contains(index) ? keys[index] : nil }

    func prepare(model: LibraryModel, suggested: ScopeChoice) {
        offeredChoices = {
            if case .shoot = model.scope { return [.notRatedInShoot, .allInShoot, .currentView] }
            return [.notRatedInView, .currentView]
        }()
        choice = offeredChoices.contains(suggested) ? suggested : (offeredChoices.first ?? .currentView)
        isChoosingScope = true
        isActive = true
    }

    func photos(_ model: LibraryModel, for choice: ScopeChoice) -> [Photo] {
        // CUL-1: whatever the scope, the order is the gallery's sort order,
        // which `visiblePhotos` already applies.
        let visible = model.visiblePhotos
        switch choice {
        case .currentView:
            return visible
        case .notRatedInView:
            return visible.filter { $0.istvanRating == nil }
        case .allInShoot, .notRatedInShoot:
            guard case .shoot(let shoot) = model.scope else { return visible }
            let inShoot = model.visiblePhotos.filter { $0.shoot == shoot }
            let base = inShoot.isEmpty ? model.photos.filter { $0.shoot == shoot && $0.isOnDisk } : inShoot
            return choice == .allInShoot ? base : base.filter { $0.istvanRating == nil }
        }
    }

    func title(_ choice: ScopeChoice, model: LibraryModel) -> String {
        let count = photos(model, for: choice).count
        switch choice {
        case .notRatedInShoot, .notRatedInView: return "Not rated by me (\(count))"
        case .allInShoot: return "All in shoot (\(count))"
        case .currentView: return "Current view (\(count))"
        }
    }

    func start(_ model: LibraryModel) {
        keys = photos(model, for: choice).map(\.key)
        index = 0
        undoStack = []
        lastRating = nil
        isChoosingScope = false
        guard !keys.isEmpty else {
            finish()
            return
        }
        if let window = NSApp.keyWindow, !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            didEnterFullScreen = true
        }
    }

    func finish() {
        isActive = false
        isChoosingScope = false
        keys = []
        if didEnterFullScreen, let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        didEnterFullScreen = false
    }

    func move(by offset: Int) {
        guard !keys.isEmpty else { return }
        index = max(0, min(keys.count - 1, index + offset))
        lastRating = nil
        isZoomed = false
    }

    func rate(_ rating: Int?, model: LibraryModel) {
        guard let key = currentKey else { return }
        undoStack.append((key, model.photo(for: key)?.istvanRating))
        model.setRating(rating, for: key)
        lastRating = rating.map { "just rated \($0) — saved" } ?? "rating cleared — saved"
        // CUL-5
        if model.afterRatingMovesOn, index < keys.count - 1 {
            move(by: 1)
            lastRating = nil
        } else if !model.afterRatingMovesOn {
            showInfo = true
        }
    }

    func undo(model: LibraryModel) {
        guard let (key, previous) = undoStack.popLast() else { return }
        model.setRating(previous, for: key)
        if let position = keys.firstIndex(of: key) { index = position }
        lastRating = "undone"
    }
}

// MARK: - The view

struct ReviewView: View {
    @Bindable var model: LibraryModel
    @Bindable var session: ReviewSession

    var body: some View {
        ZStack {
            if session.isChoosingScope {
                scopeChooser
            } else {
                reviewing
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(session.isChoosingScope ? Broadsheet.bg : Broadsheet.photoGround)
    }

    // MARK: Step 1 — what to review (CUL-2)

    private var scopeChooser: some View {
        VStack(alignment: .leading, spacing: Broadsheet.Space.four) {
            Text("Review \(model.scope.title)")
                .font(Broadsheet.heading(24))

            HStack(spacing: 0) {
                ForEach(session.offeredChoices, id: \.self) { choice in
                    let isOn = session.choice == choice
                    Text(session.title(choice, model: model))
                        .font(Broadsheet.body(13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isOn ? Broadsheet.accent : Color.clear)
                        .foregroundStyle(isOn ? Broadsheet.bg : Broadsheet.text)
                        .contentShape(Rectangle())
                        .onTapGesture { session.choice = choice }
                }
            }
            .overlay { RoundedRectangle(cornerRadius: Broadsheet.radius).stroke(Broadsheet.divider, lineWidth: 1) }
            .clipShape(RoundedRectangle(cornerRadius: Broadsheet.radius))

            Text("Order follows the gallery sort: \(model.sortOrder.title.lowercased()). "
                 + "The list is fixed for the session — rating a photo doesn't drop it out.")
                .font(Broadsheet.body(14))
                .foregroundStyle(Broadsheet.secondary)
                .frame(maxWidth: 560, alignment: .leading)

            HStack(spacing: Broadsheet.Space.three) {
                Button("Start review") { session.start(model) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(session.photos(model, for: session.choice).isEmpty)
                Button("Cancel") { session.finish() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.escape, modifiers: [])

                Picker("After rating:", selection: $model.afterRatingMovesOn) {   // CUL-5
                    Text("move to next").tag(true)
                    Text("stay and show Claude's view").tag(false)
                }
                .pickerStyle(.menu)
                .font(Broadsheet.body(13))
                .frame(width: 320)
            }
        }
        .padding(Broadsheet.Space.eight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Step 2 and 3 — the photo, and the info panel

    private var reviewing: some View {
        let photo = session.currentKey.flatMap { model.photo(for: $0) }
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack {
                    if let photo {
                        // CUL-8: fit, or 100% inside a scroll view to pan.
                        if session.isZoomed {
                            ScrollView([.horizontal, .vertical]) {
                                PhotoImage(url: photo.url, maxPixel: 4000, display: true, contentMode: .fit)
                                    .frame(width: 2400, height: 1600)
                            }
                        } else {
                            PhotoImage(url: photo.url, maxPixel: 3200, display: true, contentMode: .fit)
                                .padding(Broadsheet.Space.four)
                        }
                    }
                    if session.showOverlay, let photo {
                        overlay(photo)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if session.showInfo, let photo {
                    infoPanel(photo)
                        .frame(width: 320)
                }
            }

            progressBar

            if session.showFilmstrip {
                filmstrip
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { press in handle(press) }
        .task(id: session.index) {
            // NFR-7: get the neighbours ready.
            let urls = [session.index - 1, session.index + 1]
                .filter { session.keys.indices.contains($0) }
                .compactMap { model.photo(for: session.keys[$0])?.url }
            ImageCache.shared.prefetch(urls, maxPixel: 3200)
        }
    }

    /// CUL-4: filename, shoot, rating, position — and the keys, which are the
    /// whole interface here.
    private func overlay(_ photo: Photo) -> some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(photo.filename)
                    Text("\(photo.shoot) · \(session.index + 1) of \(session.keys.count)")
                }
                .font(Broadsheet.body(13))
                Spacer()
            }
            Spacer()
            HStack(alignment: .bottom) {
                HStack(spacing: Broadsheet.Space.two) {
                    Text(starsText(photo.istvanRating))
                        .font(Broadsheet.body(20))
                    if let note = session.lastRating {
                        Text(note)
                            .font(Broadsheet.body(12))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                Spacer()
                Text("1–5 rate · 0 clear · ← → move · Z zoom\nI info · F filmstrip · H overlay · ⌘Z undo · Esc leave")
                    .font(Broadsheet.body(12))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
        .padding(Broadsheet.Space.four)
    }

    private func starsText(_ rating: Int?) -> String {
        String(repeating: "★", count: rating ?? 0) + String(repeating: "☆", count: 5 - (rating ?? 0))
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            let fraction = session.keys.isEmpty ? 0 : Double(session.index + 1) / Double(session.keys.count)
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.18))
                Rectangle().fill(Broadsheet.accent).frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 5)
    }

    /// CUL-9
    private var filmstrip: some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(session.keys.enumerated()), id: \.element) { position, key in
                        PhotoImage(url: model.photo(for: key)?.url, maxPixel: 160)
                            .frame(width: 64, height: 44)
                            .overlay {
                                if position == session.index {
                                    Rectangle().stroke(Broadsheet.accent, lineWidth: 2)
                                }
                            }
                            .id(key)
                            .onTapGesture {
                                session.index = position
                                session.lastRating = nil
                            }
                    }
                }
                .padding(Broadsheet.Space.two)
            }
            .background(Color.black.opacity(0.35))
            .onChange(of: session.index) { _, _ in
                guard let key = session.currentKey else { return }
                withAnimation(.easeOut(duration: 0.15)) { scroller.scrollTo(key, anchor: .center) }
            }
        }
        .frame(height: 64)
    }

    /// CUL-6: the photo's description, and Claude's view only if it is revealed.
    private func infoPanel(_ photo: Photo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Broadsheet.Space.three) {
                HStack {
                    Kicker("Info — I")
                    Spacer()
                    Text("\(session.index + 1) of \(session.keys.count)")
                        .font(Broadsheet.body(12))
                        .foregroundStyle(Broadsheet.muted)
                }
                Text(photo.title.isEmpty ? photo.filename : photo.title)
                    .font(Broadsheet.heading(20))

                FactRows(rows: [
                    ("Taken", photo.row?.dateTaken ?? "—"),
                    ("Camera", photo.row?.cameraOrFormat ?? "—"),
                    ("Tags", photo.tags.isEmpty ? "—" : photo.tags.joined(separator: ", ")),
                ], valueFont: Broadsheet.body(13))

                Divider().overlay(Broadsheet.divider)

                HStack(alignment: .bottom, spacing: Broadsheet.Space.six) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Mine").font(Broadsheet.body(11)).foregroundStyle(Broadsheet.muted)
                        Text(photo.istvanRating.map(String.init) ?? "—")
                            .font(Broadsheet.heading(30))
                            .foregroundStyle(Broadsheet.accentText)
                    }
                    if photo.isRevealed {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Claude").font(Broadsheet.body(11)).foregroundStyle(Broadsheet.muted)
                            Text(photo.claudeRating.map(String.init) ?? "—")
                                .font(Broadsheet.heading(30))
                                .foregroundStyle(Broadsheet.accent2Text)
                        }
                    }
                }

                if photo.isRevealed {
                    if !photo.claudeRationale.isEmpty {
                        Text(photo.claudeRationale).font(Broadsheet.body(14))
                    }
                    if photo.hasCritique {
                        HStack(alignment: .top, spacing: Broadsheet.Space.two) {
                            Rectangle().fill(Broadsheet.accent2).frame(width: 2)
                            VStack(alignment: .leading, spacing: 4) {
                                if photo.critiqueIsOutOfDate, let written = photo.critiqueWrittenForRating {
                                    TagLabel("Written when you rated this \(written)", style: .accent2)
                                }
                                Text(photo.claudeCritique).font(Broadsheet.italic(14))
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Rate this photo to see Claude's view of it.")
                        .font(Broadsheet.italic(14))
                        .foregroundStyle(Broadsheet.secondary)
                }
            }
            .padding(Broadsheet.Space.four)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Broadsheet.bg)
        .foregroundStyle(Broadsheet.text)
    }

    // MARK: Keys (CUL-3)

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.command), press.characters == "z" {
            session.undo(model: model)                       // CUL-10
            return .handled
        }
        switch press.key {
        case .escape: session.finish(); return .handled
        case .leftArrow: session.move(by: -1); return .handled
        case .rightArrow: session.move(by: 1); return .handled
        case .delete, .deleteForward: session.rate(nil, model: model); return .handled
        default: break
        }
        switch press.characters.lowercased() {
        case "1", "2", "3", "4", "5":
            session.rate(Int(press.characters), model: model)
            return .handled
        case "0":
            session.rate(nil, model: model)
            return .handled
        case "i": session.showInfo.toggle(); return .handled
        case "f": session.showFilmstrip.toggle(); return .handled
        case "h": session.showOverlay.toggle(); return .handled
        case "z": session.isZoomed.toggle(); return .handled
        default: return .ignored
        }
    }
}
