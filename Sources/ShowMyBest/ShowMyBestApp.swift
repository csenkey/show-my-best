import SwiftUI
import AppKit
import ShowMyBestKit

@main
struct ShowMyBestApp: App {
    @State private var model = LibraryModel()
    /// LIB-1: the library is remembered across launches.
    @AppStorage("libraryPath") private var libraryPath = ""

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 1000, minHeight: 680)
                .task {
                    // --library <path> opens a folder without touching the
                    // remembered one; used when developing against a fixture.
                    let arguments = ProcessInfo.processInfo.arguments
                    if let flag = arguments.firstIndex(of: "--library"), flag + 1 < arguments.count {
                        model.open(folder: URL(fileURLWithPath: arguments[flag + 1]))
                    } else if !libraryPath.isEmpty {
                        model.open(folder: URL(fileURLWithPath: libraryPath))
                    }
                }
        }
        .defaultSize(width: 1320, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Library…") { chooseLibrary() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .newItem) {
                Button("Reload") { model.reload() }          // SYN-6
                    .keyboardShortcut("r")
                    .disabled(model.libraryURL == nil)
                Divider()
                Button("Show Backups in Finder") {           // RAT-10
                    if let url = model.backupsURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                .disabled(model.backupsURL == nil)
                Button("Show Rating Log in Finder") {        // RAT-11
                    if let url = model.ratingLogURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                .disabled(model.ratingLogURL == nil)
            }
            CommandGroup(replacing: .toolbar) {
                Picker("View", selection: Binding(get: { model.screen }, set: { model.screen = $0 })) {
                    ForEach(LibraryModel.Screen.allCases) { screen in
                        Text(screen.title).tag(screen)
                    }
                }
                Divider()
                Button("Bigger Thumbnails") { model.thumbnailSize = min(360, model.thumbnailSize + 30) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Smaller Thumbnails") { model.thumbnailSize = max(110, model.thumbnailSize - 30) }
                    .keyboardShortcut("-", modifiers: .command)
            }
        }
    }

    /// LIB-1, LIB-2: Istvan picks the library, or a shoot inside it.
    private func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose your photo library folder — the one holding catalogue.csv."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.open(folder: url)
        if let libraryURL = model.libraryURL {
            libraryPath = libraryURL.path
        }
    }
}
