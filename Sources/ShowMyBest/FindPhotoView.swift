import SwiftUI
import AppKit
import ShowMyBestKit

/// Find a photo by the name it goes by in conversation (⌘F).
///
/// Type `IMG_9786`, or paste a whole paragraph from Claude and see every photo
/// it mentions. Return opens the highlighted one.
struct FindPhotoView: View {
    @Bindable var model: LibraryModel
    var open: (PhotoKey) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selected = 0
    @FocusState private var fieldHasFocus: Bool

    private var result: PhotoFinder.Result { PhotoFinder.find(query, in: model.photos) }

    var body: some View {
        let result = result
        let photos = result.photos
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
                Kicker("Find a photo")
                TextField("IMG_9786, a title — or paste a whole message from Claude", text: $query, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Broadsheet.body(18))
                    .lineLimit(1...5)
                    .focused($fieldHasFocus)
                    .padding(Broadsheet.Space.two)
                    .background(Broadsheet.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: Broadsheet.radius)
                            .stroke(fieldHasFocus ? Broadsheet.accent : Broadsheet.divider, lineWidth: 1)
                    }
            }
            .padding(Broadsheet.Space.four)

            Divider().overlay(Broadsheet.divider)

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hint
            } else if result.isEmpty {
                Text("Nothing in this library matches.")
                    .font(Broadsheet.italic(15))
                    .foregroundStyle(Broadsheet.secondary)
                    .padding(Broadsheet.Space.four)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                results(result, photos: photos)
            }

            Divider().overlay(Broadsheet.divider)
            HStack {
                Text("↑ ↓ choose · ⏎ open · esc close")
                Spacer()
                if !photos.isEmpty {
                    Text("\(photos.count) photo\(photos.count == 1 ? "" : "s")")
                }
            }
            .font(Broadsheet.body(12))
            .foregroundStyle(Broadsheet.muted)
            .padding(.horizontal, Broadsheet.Space.four)
            .padding(.vertical, Broadsheet.Space.two)
        }
        .background(Broadsheet.bg)
        .foregroundStyle(Broadsheet.text)
        .onAppear { fieldHasFocus = true }
        .onChange(of: query) { _, _ in selected = 0 }
        // The same route review mode uses, so these keys work whatever the
        // text field does with them. Everything else goes on to the field.
        .keyMonitor(isActive: true) { event in
            guard !event.modifierFlags.contains(.command) else { return false }
            let photos = self.result.photos
            switch event.keyCode {
            case Key.escape:
                dismiss()
                return true
            case Key.returnKey, Key.keypadEnter:
                if photos.indices.contains(selected) { open(photos[selected].key) }
                return true
            case Key.downArrow:
                if !photos.isEmpty { selected = min(photos.count - 1, selected + 1) }
                return true
            case Key.upArrow:
                selected = max(0, selected - 1)
                return true
            default:
                return false
            }
        }
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: Broadsheet.Space.two) {
            Text("Any of these work:")
                .font(Broadsheet.body(14))
                .foregroundStyle(Broadsheet.secondary)
            ForEach(["IMG_9786", "IMG_9786.JPG", "R8_Budapest_202606/IMG_9786.JPG", "9786", "Liberty Bridge"], id: \.self) { example in
                Text(example)
                    .font(Broadsheet.mono(13))
                    .foregroundStyle(Broadsheet.text)
            }
            Text("Paste a whole reply from Claude and every photo it names is listed, in the order it mentions them.")
                .font(Broadsheet.italic(14))
                .foregroundStyle(Broadsheet.secondary)
                .padding(.top, Broadsheet.Space.two)
        }
        .padding(Broadsheet.Space.four)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func results(_ result: PhotoFinder.Result, photos: [Photo]) -> some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(result.matches, id: \.name) { match in
                        if match.photos.count > 1 {
                            Text("\(match.name) is in \(match.photos.count) shoots")
                                .font(Broadsheet.italic(13))
                                .foregroundStyle(Broadsheet.secondary)
                                .padding(.horizontal, Broadsheet.Space.four)
                                .padding(.top, Broadsheet.Space.two)
                        }
                        ForEach(match.photos) { photo in
                            row(photo, index: photos.firstIndex { $0.key == photo.key } ?? 0)
                        }
                    }
                    ForEach(result.textMatches) { photo in
                        row(photo, index: photos.firstIndex { $0.key == photo.key } ?? 0)
                    }
                    ForEach(result.notFound, id: \.self) { name in
                        Text("\(name) — not in this library")
                            .font(Broadsheet.body(14))
                            .foregroundStyle(Broadsheet.accent2Text)
                            .padding(.horizontal, Broadsheet.Space.four)
                            .padding(.vertical, Broadsheet.Space.one)
                    }
                }
                .padding(.vertical, Broadsheet.Space.two)
            }
            .onChange(of: selected) { _, index in
                guard photos.indices.contains(index) else { return }
                scroller.scrollTo(photos[index].key, anchor: .center)
            }
        }
    }

    private func row(_ photo: Photo, index: Int) -> some View {
        let isSelected = index == selected
        return HStack(spacing: Broadsheet.Space.three) {
            PhotoImage(url: photo.url, maxPixel: 200)
                .frame(width: 84, height: 56)
                .overlay {
                    if !photo.isOnDisk {
                        Text("missing").font(Broadsheet.body(10)).foregroundStyle(Broadsheet.bg)
                            .padding(2).background(Broadsheet.neutral(700))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(photo.filename)
                    .font(Broadsheet.heading(15))
                Text(photo.title.isEmpty ? photo.shoot : "\(photo.shoot) · \(photo.title)")
                    .font(Broadsheet.body(13))
                    .foregroundStyle(Broadsheet.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Broadsheet.Space.two)
            HStack(spacing: Broadsheet.Space.two) {
                if photo.istvanRating != nil {
                    Stars(rating: photo.istvanRating)
                } else {
                    Text("not rated").font(Broadsheet.italic(12)).foregroundStyle(Broadsheet.muted)
                }
                // Claude's rating only where it is already revealed (IND-1).
                if let claude = photo.claudeRating {
                    Text("C \(claude)").font(Broadsheet.body(12)).foregroundStyle(Broadsheet.accent2Text)
                }
            }
        }
        .padding(.horizontal, Broadsheet.Space.four)
        .padding(.vertical, Broadsheet.Space.one)
        .background(isSelected ? Broadsheet.accentStep(100) : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected { Rectangle().fill(Broadsheet.accent).frame(width: 2) }
        }
        .contentShape(Rectangle())
        .id(photo.key)
        .onTapGesture { open(photo.key) }
    }
}
