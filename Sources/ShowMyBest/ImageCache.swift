import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Thumbnails and display-sized copies of the photos.
///
/// Everything is decoded through ImageIO with the file's own orientation and
/// colour profile (NFR-4). Thumbnails are cached in the user's Caches folder,
/// never in the library (NFR-8, RAT-13), and keyed by the file's modification
/// date and size so an edited photo makes a new one. Decoding happens off the
/// main thread so the gallery stays responsive (NFR-5).
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "showmybest.images", qos: .userInitiated, attributes: .concurrent)
    private let directory: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = caches.appendingPathComponent("ShowMyBest/thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 400
    }

    /// A thumbnail at `maxPixel` on its longest side, from memory, then the
    /// disk cache, then the photo itself.
    func thumbnail(for url: URL, maxPixel: Int) async -> NSImage? {
        let key = cacheKey(for: url, maxPixel: maxPixel)
        if let cached = memory.object(forKey: key as NSString) { return cached }

        return await withCheckedContinuation { continuation in
            queue.async {
                if let image = self.loadFromDisk(key: key) {
                    self.memory.setObject(image, forKey: key as NSString)
                    continuation.resume(returning: image)
                    return
                }
                guard let image = self.decode(url: url, maxPixel: maxPixel) else {
                    continuation.resume(returning: nil)
                    return
                }
                self.saveToDisk(image, key: key)
                self.memory.setObject(image, forKey: key as NSString)
                continuation.resume(returning: image)
            }
        }
    }

    /// A display-sized copy for the detail and review views. Kept in memory
    /// only: these are large and a disk copy would not pay for itself.
    func displayImage(for url: URL, maxPixel: Int = 3200) async -> NSImage? {
        let key = "display-\(cacheKey(for: url, maxPixel: maxPixel))"
        if let cached = memory.object(forKey: key as NSString) { return cached }
        return await withCheckedContinuation { continuation in
            queue.async {
                guard let image = self.decode(url: url, maxPixel: maxPixel) else {
                    continuation.resume(returning: nil)
                    return
                }
                self.memory.setObject(image, forKey: key as NSString)
                continuation.resume(returning: image)
            }
        }
    }

    /// NFR-7: the neighbours of the photo on screen, decoded before they are
    /// asked for.
    func prefetch(_ urls: [URL], maxPixel: Int) {
        for url in urls {
            Task.detached(priority: .utility) { _ = await self.displayImage(for: url, maxPixel: maxPixel) }
        }
    }

    // MARK: Decoding

    private func decode(url: URL, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // NFR-4: orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// DET-6: the camera settings recorded in the file.
    static func metadata(for url: URL) -> [(String, String)] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return [] }

        var facts: [(String, String)] = []
        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        if let width, let height { facts.append(("Dimensions", "\(width) × \(height)")) }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        if let aperture = exif[kCGImagePropertyExifFNumber] as? Double {
            facts.append(("Aperture", String(format: "ƒ/%.1f", aperture)))
        }
        if let shutter = exif[kCGImagePropertyExifExposureTime] as? Double, shutter > 0 {
            let text = shutter < 1 ? "1/\(Int((1 / shutter).rounded()))" : String(format: "%.1f", shutter)
            facts.append(("Shutter", "\(text) s"))
        }
        if let isoValues = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let iso = isoValues.first {
            facts.append(("ISO", "\(iso)"))
        }
        if let focal = exif[kCGImagePropertyExifFocalLength] as? Double {
            facts.append(("Focal length", "\(Int(focal.rounded())) mm"))
        }
        if let lens = exif[kCGImagePropertyExifLensModel] as? String, !lens.isEmpty {
            facts.append(("Lens", lens))
        }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        if let model = tiff[kCGImagePropertyTIFFModel] as? String, !model.isEmpty {
            facts.append(("Camera (file)", model.trimmingCharacters(in: .whitespaces)))
        }
        return facts
    }

    // MARK: Disk cache

    private func cacheKey(for url: URL, maxPixel: Int) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes?[.size] as? Int) ?? 0
        var hash: UInt64 = 5381
        for byte in "\(url.path)|\(modified)|\(size)|\(maxPixel)".utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return String(hash, radix: 36)
    }

    private func loadFromDisk(key: String) -> NSImage? {
        let url = directory.appendingPathComponent("\(key).jpg")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func saveToDisk(_ image: NSImage, key: String) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let url = directory.appendingPathComponent("\(key).jpg")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }
}

/// A photo that loads itself, at whatever size it is asked for.
///
/// The frame belongs to the placeholder, and the photo is drawn as an overlay
/// on it. That is deliberate: an overlay can never change the size of the
/// view it sits on. Drawn inside a ZStack instead, a `.fill` photo reported
/// its full, uncropped size to layout — `.clipped()` hides the overflow but
/// does not shrink the frame — so a portrait photo made its cell grow the
/// moment it loaded. In a scroll view that growth, above the visible area,
/// shoved the scroll position down, and scrolling up bounced back before it
/// could reach the top.
struct PhotoImage: View {
    let url: URL?
    var maxPixel: Int = 400
    var display = false
    var contentMode: ContentMode = .fill

    @State private var image: NSImage?

    var body: some View {
        Rectangle()
            .fill(Broadsheet.neutral(300))
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
            }
            .clipped()
        .task(id: url) {
            image = nil
            guard let url else { return }
            image = display
                ? await ImageCache.shared.displayImage(for: url, maxPixel: maxPixel)
                : await ImageCache.shared.thumbnail(for: url, maxPixel: maxPixel)
        }
    }
}
