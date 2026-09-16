import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import ShowMyBestKit

// The selling side: docs/sales-spec.md, sections 3 to 6.

private let portalsHeader = "portal_id,name,kind,url,signup_url,upload_url,account_status,exclusivity,commission,payout,min_megapixels,max_long_edge_px,max_keywords,max_title_chars,editorial,film_scans,terms_flag,terms_notes,recommendation_call,reasoning,last_checked\r\n"
private let listingsHeader = "portal_id,source_folder,filename,listing_type,title,description,keywords,category,price,currency,edition_size,print_sizes,reason,status,suggested_on,portal_ref,notes\r\n"

private func scratchFolder(_ name: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("show-my-best-selftest-\(name)-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A real image file, so the exporter has pixels and metadata to work with.
private func writeImage(_ url: URL, width: Int, height: Int, withGPS: Bool = false) {
    let space = CGColorSpace(name: CGColorSpace.displayP3)!
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    var properties: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifFNumber: 8.0, kCGImagePropertyExifISOSpeedRatings: [100]],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "Canon EOS R8"],
    ]
    if withGPS {
        properties[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: 47.49, kCGImagePropertyGPSLatitudeRef: "N"]
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    CGImageDestinationFinalize(destination)
}

@MainActor
func salesChecks() async {
    let support = scratchFolder("support")
    let exports = scratchFolder("exports")
    setenv("SHOWMYBEST_SUPPORT_ROOT", support.path, 1)
    setenv("SHOWMYBEST_EXPORTS_ROOT", exports.path, 1)
    defer {
        unsetenv("SHOWMYBEST_SUPPORT_ROOT")
        unsetenv("SHOWMYBEST_EXPORTS_ROOT")
        try? FileManager.default.removeItem(at: support)
        try? FileManager.default.removeItem(at: exports)
    }

    // ------------------------------------------------------------ reading

    section("Sales files (sales spec 4)")

    do {
        let library = scratchFolder("sales-read")
        try! Data((portalsHeader
            + "adobe-stock,Adobe Stock,stock,https://stock.adobe.com,https://contributor.stock.adobe.com,https://contributor.stock.adobe.com/uploads,none,non-exclusive,33%,,4,,49,200,yes,unknown,caution,AI training licence,join,Big market,2026-07-01\r\n").utf8)
            .write(to: library.appendingPathComponent("portals.csv"))
        try! Data((listingsHeader
            + "adobe-stock,R8_Budapest_202606,IMG_9786.JPG,stock,Liberty Bridge,Tram at dusk,budapest;bridge; tram ,Travel,,,,,Clean,,2026-09-16,,\r\n"
            + "adobe-stock,R8_Budapest_202606,IMG_0001.JPG,print,Other,,,,\"12,5\",EUR,,30x40;50x70,,Shipped,,,\r\n").utf8)
            .write(to: library.appendingPathComponent("listings.csv"))
        try! Data("date,portal_id,source_folder,filename,listing_type,edition_number,amount,currency,notes\r\n2026-09-01,adobe-stock,R8_Budapest_202606,IMG_9786.JPG,stock,,0.99,usd,\r\n2026-09-10,adobe-stock,R8_Budapest_202606,IMG_9786.JPG,stock,,1.2,USD,\r\n".utf8)
            .write(to: library.appendingPathComponent("sales.csv"))

        let files = SalesLoader.load(libraryURL: library)
        check(files.errors.isEmpty, "the three files parse", "\(files.errors)")
        let portal = files.portals.first
        check(portal?.minMegapixels == 4 && portal?.maxKeywords == 49 && portal?.maxLongEdge == nil,
              "portal limits read as numbers, empty as none")
        check(portal?.needsRecheck(on: ISODate.parse("2026-09-16")!) == true, "checked over 30 days ago asks for a re-check (SAL-15)")
        check(files.listings.first?.keywords == ["budapest", "bridge", "tram"], "keywords split on ; and trimmed")
        check(files.listings.first?.status == .suggested, "an empty status is suggested")
        check(files.listings.last?.status == nil && files.listings.last?.statusLabel == "Shipped",
              "an unknown status is kept as written")
        check(files.listings.last?.price == 12.5, "a decimal comma reads as a number")
        check(files.listings.last?.printSizes == ["30x40", "50x70"], "print sizes")
        check(files.sales.first?.date == "2026-09-10" && files.sales.first?.currency == "USD",
              "sales newest first, currency upper-cased")
        try? FileManager.default.removeItem(at: library)
    }

    // ------------------------------------------------------------ writing

    section("Listing status writes (SAL-32 to SAL-35, SAC-3)")

    do {
        let library = scratchFolder("sales-write")
        let url = library.appendingPathComponent("listings.csv")
        let original = listingsHeader
            + "adobe-stock,R8_Budapest_202606,IMG_9786.JPG,stock,\"Liberty Bridge, dusk\",Zebegényi hídnál,budapest;bridge,Travel,,,,,\"He said \"\"sell\"\"\",prepared,2026-09-16,,\r\n"
            + "adobe-stock,R8_Rovinj_202606,IMG_2216.JPG,stock,Harbour,,,,,,,,,suggested,2026-09-16,,\r\n"
        try! Data(original.utf8).write(to: url)
        let files = SupportFiles(libraryURL: library)
        let key = ListingKey(portalID: "adobe-stock", photo: PhotoKey(shoot: "R8_Budapest_202606", filename: "IMG_9786.JPG"))

        let changed = try? ListingStore.setStatus(.uploaded, for: [key], libraryURL: library, support: files, today: "2026-09-17")
        let written = String(data: try! Data(contentsOf: url), encoding: .utf8)!
        check(changed == 1, "one listing changed")
        let expectedHeader = listingsHeader.replacingOccurrences(of: "\r\n", with: ",uploaded_on\r\n")
        let expected = expectedHeader
            + "adobe-stock,R8_Budapest_202606,IMG_9786.JPG,stock,\"Liberty Bridge, dusk\",Zebegényi hídnál,budapest;bridge,Travel,,,,,\"He said \"\"sell\"\"\",uploaded,2026-09-16,,,2026-09-17\r\n"
            + "adobe-stock,R8_Rovinj_202606,IMG_2216.JPG,stock,Harbour,,,,,,,,,suggested,2026-09-16,,,\r\n"
        check(written == expected, "only status and uploaded_on change; the missing column is added at the end",
              written.debugDescription)
        check(FileManager.default.fileExists(atPath: files.backupsURL.appendingPathComponent("listings-\(ISODate.today()).csv").path),
              "the file is backed up before the first write of the day (SAL-34)")

        let again = try? ListingStore.setStatus(.uploaded, for: [key], libraryURL: library, support: files)
        check(again == 0 && String(data: try! Data(contentsOf: url), encoding: .utf8) == expected,
              "setting the same status again writes nothing")

        let gone = ListingKey(portalID: "adobe-stock", photo: PhotoKey(shoot: "X", filename: "none.jpg"))
        do {
            try ListingStore.setStatus(.live, for: [key, gone], libraryURL: library, support: files)
            check(false, "a listing that is not in the file refuses the write")
        } catch {
            check(String(data: try! Data(contentsOf: url), encoding: .utf8) == expected,
                  "a listing that is not in the file refuses the whole write (SAL-35)")
        }
        try? FileManager.default.removeItem(at: library)
    }

    // ------------------------------------------------------------ rules

    section("Holds, problems and warnings (SAL-17 to SAL-23, SAC-1, SAC-4)")

    do {
        let today = ISODate.parse("2026-09-16")!
        let photo = PhotoKey(shoot: "R8_Budapest_202606", filename: "IMG_9786.JPG")
        var stockPortal = Portal(id: "adobe-stock")
        stockPortal.name = "Adobe Stock"
        stockPortal.minMegapixels = 4
        stockPortal.maxKeywords = 2
        var galleryPortal = Portal(id: "gallery")
        galleryPortal.name = "Gallery"
        galleryPortal.exclusivity = "exclusive"
        let portals = [stockPortal, galleryPortal]

        var stock = Listing(key: ListingKey(portalID: "adobe-stock", photo: photo))
        stock.listingType = "stock"
        stock.status = .suggested
        stock.keywords = ["a", "b", "c"]

        var entered = Submission()
        entered.competitionID = "exposure-one"
        entered.competitionName = "Exposure One"
        entered.result = "pending"
        var competition = Competition(id: "exposure-one")
        competition.name = "Exposure One"
        competition.deadline = "2026-09-21"
        competition.rightsFlag = "caution"

        var context = PhotoSalesContext()
        context.listings = [stock]
        context.pixelSize = PixelSize(width: 6000, height: 4000)
        context.submissions = [entered]
        context.matches = [(CompetitionMatch(competitionID: "exposure-one", key: photo), competition)]
        context.competitions = ["exposure-one": competition]

        var result = SalesRules.assess(stock, portals: portals, context: context, today: today)
        check(result.holds == ["Entered in Exposure One, waiting for results"],
              "entered and pending: held once, not again for the match (SAC-1)", "\(result.holds)")
        check(!result.canPrepare, "a held listing cannot be prepared")
        check(result.warnings == ["3 keywords; Adobe Stock takes 2"], "too many keywords is a warning only (SAL-22)", "\(result.warnings)")

        context.submissions[0].result = "no-award"
        result = SalesRules.assess(stock, portals: portals, context: context, today: today)
        check(result.holds.isEmpty, "the hold lifts once the result is in, even before the deadline", "\(result.holds)")

        context.submissions[0].result = "placed"
        result = SalesRules.assess(stock, portals: portals, context: context, today: today)
        check(result.warnings.contains("Check what Exposure One may do with winning entries"),
              "a placing in a caution competition is flagged (SAL-23)")

        context.submissions = []
        result = SalesRules.assess(stock, portals: portals, context: context, today: today)
        check(result.holds == ["Matched to Exposure One, closes on 2026-09-21"], "matched to an open competition (SAL-18)", "\(result.holds)")
        result = SalesRules.assess(stock, portals: portals, context: context, today: ISODate.parse("2026-09-22")!)
        check(result.holds.isEmpty, "the match stops holding once the competition closes without an entry")

        context.matches = []
        var edition = Listing(key: ListingKey(portalID: "gallery", photo: photo))
        edition.listingType = "edition"
        edition.status = .live
        context.listings = [stock, edition]
        result = SalesRules.assess(stock, portals: portals, context: context, today: today)
        check(result.holds.contains("Sold as a limited edition on Gallery"), "a live edition holds a stock listing (SAC-4)", "\(result.holds)")
        check(result.holds.contains("Exclusive to Gallery"), "live on an exclusive portal holds every other portal (SAL-20)")

        edition.status = .suggested
        stock.status = .uploaded
        context.listings = [stock, edition]
        result = SalesRules.assess(edition, portals: portals, context: context, today: today)
        check(result.holds.count == 2, "and the reverse: an uploaded stock licence holds the edition, and so does exclusivity",
              "\(result.holds)")

        stock.status = .suggested
        context.listings = [stock]
        context.pixelSize = PixelSize(width: 2000, height: 1500)
        result = SalesRules.assess(stock, portals: portals, context: context, today: today)
        check(result.problems == ["Too small for Adobe Stock: 3 MP, needs at least 4"], "below the portal's megapixels (SAL-21)",
              "\(result.problems)")
        context.fileExists = false
        result = SalesRules.assess(stock, portals: portals, context: context, today: today)
        check(result.problems == ["The photo file is missing"], "a missing file")
    }

    // ------------------------------------------------------------ exporting

    section("Preparing files (SAL-26 to SAL-31)")

    do {
        let folder = scratchFolder("export-source")
        let source = folder.appendingPathComponent("IMG_9786.JPG")
        writeImage(source, width: 3000, height: 2000, withGPS: true)
        let sourceBytes = try! Data(contentsOf: source)

        var listing = Listing(key: ListingKey(portalID: "adobe-stock", photo: PhotoKey(shoot: "R8_Budapest_202606", filename: "IMG_9786.JPG")))
        listing.title = "Liberty Bridge at dusk"
        listing.description = "Tram crossing the Danube — Zebegényi hídnál"
        listing.keywords = ["budapest", "bridge", "tram"]
        let destination = exports.appendingPathComponent("direct/IMG_9786.jpg")
        do {
            try ListingExporter.export(listing, from: source, to: destination, maxLongEdge: 1200,
                                       creator: "Istvan Csenkey-Sinko", copyrightYear: "2026")
            check(true, "the export succeeds")
        } catch {
            check(false, "the export succeeds", "\(error)")
        }

        let exported = CGImageSourceCreateWithURL(destination as CFURL, nil)
        let properties = exported.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
        check(properties[kCGImagePropertyPixelWidth] as? Int == 1200 && properties[kCGImagePropertyPixelHeight] as? Int == 800,
              "scaled to the portal's long edge (SAL-27)")
        check((properties[kCGImagePropertyProfileName] as? String)?.contains("sRGB") == true,
              "converted to sRGB", "\(properties[kCGImagePropertyProfileName] ?? "no profile")")
        let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        check(iptc[kCGImagePropertyIPTCKeywords] as? [String] == ["budapest", "bridge", "tram"], "IPTC keywords embedded (SAL-28)")
        check(iptc[kCGImagePropertyIPTCObjectName] as? String == "Liberty Bridge at dusk", "IPTC title")
        check(iptc[kCGImagePropertyIPTCCaptionAbstract] as? String == listing.description, "IPTC description, Hungarian intact")
        check(iptc[kCGImagePropertyIPTCCopyrightNotice] as? String == "© 2026 Istvan Csenkey-Sinko", "copyright notice")
        let xmp = exported.flatMap { CGImageSourceCopyMetadataAtIndex($0, 0, nil) }
        check(xmp.flatMap { CGImageMetadataCopyTagWithPath($0, nil, "dc:subject" as CFString) } != nil, "XMP keywords too")
        check(properties[kCGImagePropertyGPSDictionary] == nil, "GPS left out")
        check((properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifFNumber] as? Double == 8,
              "camera settings kept")
        check(try! Data(contentsOf: source) == sourceBytes, "the original is untouched (NFR-3)")

        try? ListingExporter.export(listing, from: source, to: exports.appendingPathComponent("full/IMG_9786.jpg"),
                                    maxLongEdge: 9000, creator: "I", copyrightYear: "2026")
        let full = ListingExporter.pixelSize(of: exports.appendingPathComponent("full/IMG_9786.jpg"))
        check(full == PixelSize(width: 3000, height: 2000), "never enlarged")

        let names = ListingExporter.fileNames(for: [
            ListingKey(portalID: "p", photo: PhotoKey(shoot: "R8_Rovinj_202606", filename: "IMG_2216.JPG")),
            ListingKey(portalID: "p", photo: PhotoKey(shoot: "R8_Budapest_202606", filename: "IMG_2216.jpg")),
            ListingKey(portalID: "p", photo: PhotoKey(shoot: "R8_Budapest_202606", filename: "IMG_9786.JPG")),
        ])
        check(Set(names.values) == ["IMG_2216-R8_Rovinj_202606.jpg", "IMG_2216-R8_Budapest_202606.jpg", "IMG_9786.jpg"],
              "a shared name gets the shoot added to both (SAL-29)", "\(names.values.sorted())")
        try? FileManager.default.removeItem(at: folder)
    }

    // ------------------------------------------------------------ end to end

    section("The Sales view's model (SAL-3, SAC-2, SAC-5, SAL-24)")

    do {
        let library = scratchFolder("sales-model")
        let shoot = library.appendingPathComponent("R8_Budapest_202606", isDirectory: true)
        try! FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        writeImage(shoot.appendingPathComponent("IMG_0001.JPG"), width: 2600, height: 1800)   // 4.7 MP
        writeImage(shoot.appendingPathComponent("IMG_0002.JPG"), width: 2600, height: 1800)
        writeImage(shoot.appendingPathComponent("IMG_0003.JPG"), width: 1600, height: 1200)   // 1.9 MP: too small
        writeImage(shoot.appendingPathComponent("IMG_0004.JPG"), width: 2600, height: 1800)   // not rated
        let catalogue = "filename,source_folder,title,date_taken,istvan_rating,claude_rating,claude_rationale,status\r\n"
            + "IMG_0001.JPG,R8_Budapest_202606,One,2025-06,4,4,r,available\r\n"
            + "IMG_0002.JPG,R8_Budapest_202606,Two,2026-06,3,4,r,available\r\n"
            + "IMG_0003.JPG,R8_Budapest_202606,Three,2026-06,5,4,r,available\r\n"
            + "IMG_0004.JPG,R8_Budapest_202606,Four,2026-06,,5,r,available\r\n"
        try! Data(catalogue.utf8).write(to: library.appendingPathComponent("catalogue.csv"))
        try! Data((portalsHeader
            + "adobe-stock,Adobe Stock,stock,https://stock.adobe.com,,,active,non-exclusive,,,4,,49,,yes,yes,ok,,join,,2026-09-16\r\n").utf8)
            .write(to: library.appendingPathComponent("portals.csv"))
        let listingsText = listingsHeader
            + "adobe-stock,R8_Budapest_202606,IMG_0001.JPG,stock,One,,a;b,,,,,,,suggested,,,\r\n"
            + "adobe-stock,R8_Budapest_202606,IMG_0002.JPG,stock,Two,,a;b,,,,,,,live,,,\r\n"
            + "adobe-stock,R8_Budapest_202606,IMG_0003.JPG,stock,Three,,a;b,,,,,,,suggested,,,\r\n"
            + "adobe-stock,R8_Budapest_202606,IMG_0004.JPG,stock,Four,,a;b,,,,,,,suggested,,,\r\n"
        try! Data(listingsText.utf8).write(to: library.appendingPathComponent("listings.csv"))
        try! Data("competition_id,name,url,deadline,previously_unpublished,rights_flag,recommendation_call,last_checked\r\nfresh,Fresh Eyes,https://x,2099-01-01,yes,ok,enter,2026-09-16\r\n".utf8)
            .write(to: library.appendingPathComponent("competitions.csv"))
        try! Data("competition_id,source_folder,filename,role\r\nfresh,R8_Budapest_202606,IMG_0002.JPG,primary\r\n".utf8)
            .write(to: library.appendingPathComponent("competition_matches.csv"))
        let catalogueBefore = try! Data(contentsOf: library.appendingPathComponent("catalogue.csv"))

        let model = LibraryModel()
        model.open(folder: library)
        check(model.visibleListings.count == 3 && model.hiddenListingCount == 1,
              "a listing for an unrated photo is only a count (SAC-5)")
        check(model.uploadQueue.first?.listings.map(\.photo.filename) == ["IMG_0001.JPG", "IMG_0003.JPG"],
              "the queue holds suggested listings for rated photos (SAL-4)")
        check(model.publishedPortals(for: PhotoKey(shoot: "R8_Budapest_202606", filename: "IMG_0002.JPG")) == ["Adobe Stock"],
              "a live photo is published on its portal (SAL-24)")

        await model.prepareFiles(portalID: "adobe-stock")
        let folder = exports.appendingPathComponent("adobe-stock")
        let made = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.filter { !$0.hasPrefix(".") }.sorted() ?? []
        check(made == ["IMG_0001.jpg", "metadata.csv"], "only the photo that passes is exported, with the sheet (SAC-2)", "\(made)")
        check(model.sales.listings.first { $0.photo.filename == "IMG_0001.JPG" }?.status == .prepared,
              "and it is marked prepared (SAL-31)")
        check(model.sales.listings.first { $0.photo.filename == "IMG_0003.JPG" }?.status == .suggested,
              "the small one stays suggested")
        check(model.notices.last?.lines.contains { $0.contains("IMG_0003.JPG") && $0.contains("Too small") } == true,
              "and the notice says why it was left out (SAL-7)", "\(model.notices.last?.lines ?? [])")
        check(try! Data(contentsOf: library.appendingPathComponent("catalogue.csv")) == catalogueBefore,
              "the catalogue is untouched")
        let sheet = (try? String(contentsOf: folder.appendingPathComponent("metadata.csv"), encoding: .utf8)) ?? ""
        check(sheet.contains("IMG_0001.jpg,One,,\"a, b\",,stock"), "the metadata sheet lists the prepared file (SAL-30)", sheet)

        let prepared = model.uploadQueue.first?.listings.filter { $0.status == .prepared } ?? []
        model.setListingStatus(.uploaded, for: prepared)
        check(model.sales.listings.first { $0.photo.filename == "IMG_0001.JPG" }?.uploadedOn == ISODate.today(),
              "marked uploaded, with today's date (SAL-10)")
        check(model.listedByStatus.map { $0.0 } == [.uploaded, .live], "Listed groups by status (SAL-11)")
        try? FileManager.default.removeItem(at: library)
    }
}
