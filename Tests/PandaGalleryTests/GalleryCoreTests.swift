import Testing
import ImageIO
import UniformTypeIdentifiers
@testable import PandaGallery

private final class ImageFixture {
    let directory: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PandaGalleryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
    func image(width: Int = 12, height: Int = 8) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        return try #require(context.makeImage())
    }
}

@Suite struct GalleryCoreTests {
    @Test func appearanceDefaultsToDayAndRestoresExplicitChoice() throws {
        let suite = "PandaGalleryAppearanceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(GalleryTheme.restored(from: defaults) == .day)
        defaults.set("night", forKey: "appearanceMode")
        #expect(GalleryTheme.restored(from: defaults) == .night)
        defaults.set("day", forKey: "appearanceMode")
        #expect(GalleryTheme.restored(from: defaults) == .day)
        defaults.set("unrecognized", forKey: "appearanceMode")
        #expect(GalleryTheme.restored(from: defaults) == .day)
    }

    @Test func singleFileDiscoversSiblingsWithoutFolderSelection() throws {
        let fixture = try ImageFixture()
        let image = try fixture.image()
        for name in ["photo10.png", "photo2.PNG", "photo1.png", ".hidden.png"] { try ImageEngine.export(image, to: fixture.directory.appendingPathComponent(name), format: .png) }
        try Data("text".utf8).write(to: fixture.directory.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(at: fixture.directory.appendingPathComponent("fake.png"), withIntermediateDirectories: true)
        let openedFile = fixture.directory.appendingPathComponent("photo2.PNG")
        let siblings = try GalleryFiles.siblings(of: openedFile)
        #expect(siblings.map(\.lastPathComponent) == ["photo1.png", "photo2.PNG", "photo10.png"])
        #expect(siblings.firstIndex(of: openedFile.standardizedFileURL.resolvingSymlinksInPath()) == 1)
        #expect(PhotoItem(url: openedFile).id == siblings[1].path)
        #expect(siblings[2].lastPathComponent == "photo10.png")
    }

    @Test func navigationHonorsBoundariesAndSlideshowWrap() {
        #expect(GalleryFiles.neighbor(index: 0, count: 3, offset: -1, wrap: false) == nil)
        #expect(GalleryFiles.neighbor(index: 2, count: 3, offset: 1, wrap: false) == nil)
        #expect(GalleryFiles.neighbor(index: 0, count: 3, offset: -1, wrap: true) == 2)
        #expect(GalleryFiles.neighbor(index: 2, count: 3, offset: 1, wrap: true) == 0)
        #expect(GalleryFiles.neighbor(index: 0, count: 0, offset: 1, wrap: true) == nil)
    }

    @Test func aspectCropFitsAndPreservesPixelRatio() {
        for aspect: CGFloat in [1, 4 / 3, 3 / 2, 16 / 9, 2 / 3] {
            let rect = CropGeometry.fittedRect(imageSize: CGSize(width: 4000, height: 3000), aspect: aspect)
            #expect(rect.minX >= 0 && rect.maxX <= 1)
            #expect(rect.minY >= 0 && rect.maxY <= 1)
            #expect(abs(rect.width * 4000 / (rect.height * 3000) - aspect) < 0.000001)
        }
    }

    @Test func cropClampsBoundsAndRejectsEmptyRegion() {
        let rect = CropGeometry.pixelRect(normalized: CGRect(x: -0.2, y: 0.25, width: 0.7, height: 0.9), width: 400, height: 200)
        #expect(rect == CGRect(x: 0, y: 50, width: 200, height: 150))
        #expect(CropGeometry.pixelRect(normalized: CGRect(x: 2, y: 2, width: 1, height: 1), width: 400, height: 200) == .zero)
    }

    @Test func pixelCropPreservesExactPresetRatiosAfterRounding() {
        for (w, h) in [(1, 1), (4, 3), (3, 2), (16, 9), (2, 3)] {
            let aspect = CGFloat(w) / CGFloat(h)
            let normalized = CropGeometry.fittedRect(imageSize: CGSize(width: 1400, height: 933), aspect: aspect)
            let pixels = CropGeometry.pixelRect(normalized: normalized, width: 1400, height: 933, aspect: aspect)
            #expect(Int(pixels.width) * h == Int(pixels.height) * w)
            #expect(pixels.minX >= 0 && pixels.maxX <= 1400)
            #expect(pixels.minY >= 0 && pixels.maxY <= 933)
        }
    }

    @Test func rotateCropAndExportPreserveOriginalFile() throws {
        let fixture = try ImageFixture()
        let image = try fixture.image()
        let original = fixture.directory.appendingPathComponent("original.png")
        try ImageEngine.export(image, to: original, format: .png)
        let sourceBytes = try Data(contentsOf: original)
        let rotated = try #require(ImageEngine.transform(image, orientation: .right))
        #expect(rotated.width == 8 && rotated.height == 12)
        let cropped = try #require(rotated.cropping(to: CGRect(x: 0, y: 0, width: 4, height: 6)))
        var state = EditState(base: cropped); state.brightness = 0.1; state.preset = .mono
        let rendered = try #require(ImageEngine.render(state))
        let output = fixture.directory.appendingPathComponent("edited.png")
        try ImageEngine.export(rendered, to: output, format: .png)
        let decoded = try ImageEngine.load(output)
        #expect(decoded.width == 4 && decoded.height == 6)
        #expect(try Data(contentsOf: original) == sourceBytes)
        #expect(try Data(contentsOf: output) != sourceBytes)
    }

    @Test func exifOrientationAppliedExactlyOnce() throws {
        let fixture = try ImageFixture()
        let file = fixture.directory.appendingPathComponent("phone.jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try fixture.image(), [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let loaded = try ImageEngine.load(file)
        #expect(loaded.width == 8 && loaded.height == 12)
        let metadata = PhotoItem(url: file)
        #expect(metadata.width == 8 && metadata.height == 12)
        let output = fixture.directory.appendingPathComponent("corrected.png")
        try ImageEngine.export(loaded, to: output, format: .png)
        let roundtrip = try ImageEngine.load(output)
        #expect(roundtrip.width == 8 && roundtrip.height == 12)
    }

    @Test func corruptFileFailsCleanlyAndExportsAreAvailable() throws {
        let fixture = try ImageFixture()
        let broken = fixture.directory.appendingPathComponent("broken.png")
        try Data("broken image".utf8).write(to: broken)
        #expect(throws: (any Error).self) { try ImageEngine.load(broken) }
        #expect(ExportFormat.available.contains(.png))
        #expect(ExportFormat.available.contains(.jpeg))
    }
}
