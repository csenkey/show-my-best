import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

public enum ExportError: Error, CustomStringConvertible {
    case unreadable(String)
    case encodeFailed(String)

    public var description: String {
        switch self {
        case .unreadable(let name): return "\(name) could not be read"
        case .encodeFailed(let name): return "\(name) could not be written"
        }
    }
}

/// Makes the files Istvan uploads (sales spec 3.6). The photo in the library
/// is only ever read (NFR-3); the copy is a fresh JPEG with the listing's
/// words embedded where portals look for them.
public enum ListingExporter {

    /// S6: `~/Pictures/Show My Best Exports`, outside the library.
    public static var exportsRoot: URL {
        if let override = ProcessInfo.processInfo.environment["SHOWMYBEST_EXPORTS_ROOT"] {
            return URL(fileURLWithPath: override, isDirectory: true)   // used by the self-test
        }
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
        return pictures.appendingPathComponent("Show My Best Exports", isDirectory: true)
    }

    public static func folder(for portalID: String) -> URL {
        exportsRoot.appendingPathComponent(portalID, isDirectory: true)
    }

    /// SAL-29: named after the original; a name two shoots share gets the
    /// shoot added to both, so neither overwrites the other.
    public static func fileNames(for keys: [ListingKey]) -> [ListingKey: String] {
        var stems: [String: Int] = [:]
        for key in keys {
            stems[stem(key.photo.filename).lowercased(), default: 0] += 1
        }
        var names: [ListingKey: String] = [:]
        for key in keys {
            let base = stem(key.photo.filename)
            let shared = (stems[base.lowercased()] ?? 0) > 1
            names[key] = shared ? "\(base)-\(key.photo.shoot).jpg" : "\(base).jpg"
        }
        return names
    }

    public static func pixelSize(of url: URL) -> PixelSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return PixelSize(width: width, height: height)
    }

    /// SAL-27, SAL-28: sRGB JPEG at quality 95, upright, never enlarged, with
    /// IPTC and XMP metadata (ImageIO writes both from the IPTC dictionary).
    public static func export(
        _ listing: Listing,
        from sourceURL: URL,
        to destinationURL: URL,
        maxLongEdge: Int?,
        creator: String,
        copyrightYear: String
    ) throws {
        let name = sourceURL.lastPathComponent
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw ExportError.unreadable(name) }

        let longEdge = max(width, height)
        let target = min(longEdge, maxLongEdge ?? longEdge)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,     // upright
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: target,
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let image = sRGB(decoded)
        else { throw ExportError.unreadable(name) }

        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let temporaryURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).showmybest-tmp")
        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw ExportError.encodeFailed(destinationURL.lastPathComponent) }

        let notice = "© \(copyrightYear) \(creator)"
        var iptc: [CFString: Any] = [
            kCGImagePropertyIPTCByline: [creator],
            kCGImagePropertyIPTCCopyrightNotice: notice,
        ]
        if !listing.title.isEmpty { iptc[kCGImagePropertyIPTCObjectName] = listing.title }
        if !listing.description.isEmpty { iptc[kCGImagePropertyIPTCCaptionAbstract] = listing.description }
        if !listing.keywords.isEmpty { iptc[kCGImagePropertyIPTCKeywords] = listing.keywords }

        var tiff = (properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]
        tiff[kCGImagePropertyTIFFArtist] = creator
        tiff[kCGImagePropertyTIFFCopyright] = notice
        tiff[kCGImagePropertyTIFFOrientation] = 1
        let caption = listing.description.isEmpty ? listing.title : listing.description
        if !caption.isEmpty { tiff[kCGImagePropertyTIFFImageDescription] = caption }

        // Camera settings stay; the pixel counts of the original would now be
        // wrong, and GPS is left out on purpose (SAL-28).
        var exif = (properties[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
        exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
        exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension)

        let metadata: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.95,
            kCGImagePropertyOrientation: 1,
            kCGImagePropertyIPTCDictionary: iptc,
            kCGImagePropertyTIFFDictionary: tiff,
            kCGImagePropertyExifDictionary: exif,
        ]
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw ExportError.encodeFailed(destinationURL.lastPathComponent)
        }
        do {
            try AtomicFile.move(temporaryURL, to: destinationURL)
        } catch {
            throw ExportError.encodeFailed(destinationURL.lastPathComponent)
        }
    }

    /// SAL-30: one row per prepared file, for portals that read a metadata
    /// sheet. Keywords are comma-separated here, as those sheets expect.
    public static func writeMetadataSheet(_ entries: [(name: String, listing: Listing)], to folder: URL) throws {
        var text = "filename,title,description,keywords,category,listing_type\r\n"
        for entry in entries.sorted(by: { $0.name < $1.name }) {
            let fields = [
                entry.name, entry.listing.title, entry.listing.description,
                entry.listing.keywords.joined(separator: ", "), entry.listing.category, entry.listing.listingType,
            ]
            text += fields.map(CSV.escape).joined(separator: ",") + "\r\n"
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try AtomicFile.replace(folder.appendingPathComponent("metadata.csv"), with: Data(text.utf8))
    }

    // MARK: Helpers

    private static func stem(_ filename: String) -> String {
        (filename as NSString).deletingPathExtension
    }

    /// Redraws into 8-bit sRGB: what every portal asks for, whatever profile
    /// or bit depth the export from DarkTable carried.
    private static func sRGB(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
