import SwiftUI
import AppKit
import Combine
import ShowMyBestKit

struct RootView: View {
    @Bindable var model: LibraryModel
    @Bindable var review: ReviewSession
    @State private var detailKey: PhotoKey?
    @AppStorage("libraryPath") private var libraryPath = ""

    /// SYN-1: a change made outside the app shows up within two seconds.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if model.libraryURL == nil {
                WelcomeView(model: model, libraryPath: $libraryPath)
            } else {
                library
            }
        }
        .background(Broadsheet.bg)
        .foregroundStyle(Broadsheet.text)
        .tint(Broadsheet.accent)
        .onReceive(ticker) { _ in
            guard !review.isActive else { return }   // SYN-1 keeps the review position
            model.pollForChanges()
        }
        .overlay {
            if review.isActive {
                ReviewView(model: model, session: review)
                    .transition(.opacity)
            }
        }
        .sheet(item: $detailKey) { key in
            PhotoDetailView(model: model, key: key, openPhoto: { detailKey = $0 })
                .frame(minWidth: 900, minHeight: 700)
        }
    }

    private var library: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 208, ideal: 224, max: 300)
        } detail: {
            VStack(spacing: 0) {
                NoticeBar(model: model)
                switch model.screen {
                case .gallery:
                    GalleryView(
                        model: model,
                        openPhoto: { detailKey = $0 },
                        startReview: { startReview() }
                    )
                case .competitions:
                    CompetitionsView(model: model, openPhoto: { detailKey = $0 })
                case .submissions:
                    SubmissionsView(model: model, openPhoto: { detailKey = $0 })
                }
            }
            .background(Broadsheet.bg)
        }
    }

    /// CUL-2: review mode starts on the current scope. Coming from a shoot it
    /// offers the photos in it Istvan has not rated.
    private func startReview() {
        var suggestion: ReviewSession.ScopeChoice = .currentView
        if case .shoot = model.scope { suggestion = .notRatedInShoot }
        review.prepare(model: model, suggested: suggestion)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Bindable var model: LibraryModel

    var body: some View {
        List {
            Section {
                ForEach(LibraryModel.Screen.allCases) { screen in
                    row(title: screen.title, count: nil, isSelected: model.screen == screen) {
                        model.screen = screen
                    }
                }
            }

            Section {
                ForEach(LibraryModel.Collection.allCases) { collection in
                    let isSelected = model.screen == .gallery && model.scope == .collection(collection)
                    row(title: collection.title, count: model.count(for: collection), isSelected: isSelected) {
                        model.screen = .gallery
                        model.scope = .collection(collection)
                    }
                }
            } header: {
                Kicker("Collections")
            }

            Section {
                ForEach(model.shootNames, id: \.self) { shoot in
                    let isSelected = model.screen == .gallery && model.scope == .shoot(shoot)
                    row(title: shoot, count: model.count(forShoot: shoot), isSelected: isSelected) {
                        model.screen = .gallery
                        model.scope = .shoot(shoot)
                    }
                }
            } header: {
                Kicker("Shoots")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if let url = model.libraryURL {
                Text(url.lastPathComponent)
                    .font(Broadsheet.body(12))
                    .foregroundStyle(Broadsheet.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Broadsheet.Space.three)
                    .padding(.vertical, Broadsheet.Space.two)
                    .help(url.path)
            }
        }
    }

    private func row(title: String, count: Int?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Broadsheet.body(14))
                    .foregroundStyle(Broadsheet.text)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(Broadsheet.body(13))
                        .foregroundStyle(Broadsheet.muted)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background {
                if isSelected {
                    HStack(spacing: 0) {
                        Rectangle().fill(Broadsheet.accent).frame(width: 2)
                        Rectangle().fill(Broadsheet.accentStep(100))
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notices

/// SYN-3 and RAT-12 messages: never blocking, always saying what is going on.
struct NoticeBar: View {
    @Bindable var model: LibraryModel

    var body: some View {
        if !model.notices.isEmpty {
            VStack(spacing: 0) {
                ForEach(model.notices) { notice in
                    HStack(alignment: .top, spacing: Broadsheet.Space.three) {
                        Rectangle()
                            .fill(notice.kind == .warning ? Broadsheet.accent2 : Broadsheet.accent)
                            .frame(width: 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notice.title)
                                .font(Broadsheet.heading(15))
                            Text(notice.detail)
                                .font(Broadsheet.body(14))
                                .foregroundStyle(Broadsheet.secondary)
                            if !notice.lines.isEmpty {
                                Text(notice.lines.joined(separator: " · "))
                                    .font(Broadsheet.body(13))
                                    .foregroundStyle(Broadsheet.muted)
                            }
                        }
                        Spacer(minLength: 0)
                        Button("Dismiss") { model.dismiss(notice) }
                            .buttonStyle(.plain)
                            .font(Broadsheet.body(13))
                            .foregroundStyle(Broadsheet.accentText)
                    }
                    .padding(Broadsheet.Space.three)
                    .background(notice.kind == .warning ? Broadsheet.accent2Step(100) : Broadsheet.accentStep(100))
                }
            }
        }
    }
}

// MARK: - Opening a library

struct WelcomeView: View {
    @Bindable var model: LibraryModel
    @Binding var libraryPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: Broadsheet.Space.four) {
            Text("Show My Best")
                .font(Broadsheet.heading(42))

            if let folder = model.folderWithoutCatalogue {
                // LIB-3: the skill makes the catalogue, never the app.
                Kicker("First run — LIB-3")
                Text("No catalogue in this folder")
                    .font(Broadsheet.heading(24))
                Text("\(folder.path) has no catalogue.csv, and neither does the folder above it. "
                     + "Ask Claude to catalogue it first — Show My Best never creates the file.")
                    .font(Broadsheet.body(15))
                    .foregroundStyle(Broadsheet.secondary)
                    .frame(maxWidth: 520, alignment: .leading)
            } else {
                Text("Choose the folder holding catalogue.csv. A shoot folder works too — "
                     + "the library above it opens with that shoot selected.")
                    .font(Broadsheet.body(16))
                    .foregroundStyle(Broadsheet.secondary)
                    .frame(maxWidth: 520, alignment: .leading)
            }

            Button("Choose a folder…") { choose() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Broadsheet.Space.eight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.open(folder: url)
        if let libraryURL = model.libraryURL { libraryPath = libraryURL.path }
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Broadsheet.heading(14))
            .padding(.horizontal, 18)
            .padding(.vertical, Broadsheet.Space.two)
            .background(configuration.isPressed ? Broadsheet.accentStep(700) : Broadsheet.accent)
            .foregroundStyle(Broadsheet.bg)
            .clipShape(RoundedRectangle(cornerRadius: Broadsheet.radius))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Broadsheet.heading(13))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? Broadsheet.text.opacity(0.14) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: Broadsheet.radius).stroke(Broadsheet.divider, lineWidth: 1)
            }
            .foregroundStyle(Broadsheet.text)
    }
}
