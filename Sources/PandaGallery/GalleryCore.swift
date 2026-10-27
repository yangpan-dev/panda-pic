import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

struct PhotoItem: Identifiable, Equatable {
    let url: URL
    let width: Int
    let height: Int
    let bytes: Int64
    let date: Date
    var id: String { url.standardizedFileURL.path }
    var name: String { url.lastPathComponent }
    var format: String { url.pathExtension.uppercased() }
    var dimensions: String { width > 0 ? "\(width) × \(height)" : "—" }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    init(url: URL) {
        self.url = url.standardizedFileURL.resolvingSymlinksInPath()
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        bytes = Int64(values?.fileSize ?? 0)
        date = values?.contentModificationDate ?? .distantPast
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let w = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
            let h = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
            let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
            width = (5...8).contains(orientation) ? h : w
            height = (5...8).contains(orientation) ? w : h
        } else { width = 0; height = 0 }
    }
}

enum GalleryFiles {
    static let imageExtensions: Set<String> = Set((CGImageSourceCopyTypeIdentifiers() as? [String] ?? []).flatMap {
        UTType($0)?.tags[.filenameExtension] ?? []
    }).union(["jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tif", "tiff", "bmp", "avif", "dng", "cr2", "nef", "arw", "jxl"])

    static func isImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return imageExtensions.contains(ext) || UTType(filenameExtension: ext)?.conforms(to: .image) == true
    }

    /// Opening a FILE discovers its siblings; a folder picker is never needed.
    static func siblings(of file: URL) throws -> [URL] {
        try images(in: file.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent())
    }

    static func images(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            .filter { isImage($0) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func neighbor(index: Int, count: Int, offset: Int, wrap: Bool) -> Int? {
        guard count > 0, (0..<count).contains(index) else { return nil }
        let next = index + offset
        if wrap { return ((next % count) + count) % count }
        return (0..<count).contains(next) ? next : nil
    }
}

enum CropGeometry {
    static func fittedRect(imageSize: CGSize, aspect: CGFloat?, inset: CGFloat = 0.1) -> CGRect {
        let available = 1 - inset * 2
        guard let aspect, aspect > 0, imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(x: inset, y: inset, width: available, height: available)
        }
        let normalizedRatio = aspect * imageSize.height / imageSize.width
        let width = min(available, available * normalizedRatio)
        let height = min(available, available / normalizedRatio)
        return CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }

    static func pixelRect(normalized rect: CGRect, width: Int, height: Int, aspect: CGFloat? = nil) -> CGRect {
        let normalized = rect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !normalized.isNull, normalized.width > 0, normalized.height > 0 else { return .zero }
        let x = max(0, Int((normalized.minX * CGFloat(width)).rounded(.down)))
        let y = max(0, Int((normalized.minY * CGFloat(height)).rounded(.down)))
        let right = min(width, Int((normalized.maxX * CGFloat(width)).rounded(.up)))
        let bottom = min(height, Int((normalized.maxY * CGFloat(height)).rounded(.up)))
        let pixelWidth = max(0, right - x), pixelHeight = max(0, bottom - y)
        // Keep preset ratios exact after integer rounding (a 1:1 crop must be square).
        if let aspect, let ratio = [(1, 1), (4, 3), (3, 2), (16, 9), (2, 3)].first(where: { abs(CGFloat($0.0) / CGFloat($0.1) - aspect) < 0.00001 }) {
            let units = min(pixelWidth / ratio.0, pixelHeight / ratio.1)
            guard units > 0 else { return .zero }
            let w = units * ratio.0, h = units * ratio.1
            return CGRect(x: x + (pixelWidth - w) / 2, y: y + (pixelHeight - h) / 2, width: w, height: h)
        }
        return CGRect(x: x, y: y, width: pixelWidth, height: pixelHeight)
    }
}

enum ImageEngine {
    static let context = CIContext(options: [.cacheIntermediates: false])
    static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ImageError.unreadable }
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
           Double(w) * Double(h) > 100_000_000 { throw ImageError.tooLarge }
        guard let raw = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw ImageError.unreadable }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = props?[kCGImagePropertyOrientation] as? Int32 ?? 1
        if orientation == 1 { return raw }
        let image = CIImage(cgImage: raw).oriented(forExifOrientation: orientation)
        guard let corrected = context.createCGImage(image, from: image.extent) else { throw ImageError.unreadable }
        return corrected
    }

    static func transform(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        let ci = CIImage(cgImage: image).oriented(orientation)
        return context.createCGImage(ci, from: ci.extent)
    }

    static func render(_ state: EditState) -> CGImage? {
        var image = CIImage(cgImage: state.base)
        image = image.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: state.brightness, kCIInputContrastKey: state.contrast, kCIInputSaturationKey: state.saturation])
        if let filter = state.preset.filterName { image = image.applyingFilter(filter) }
        return context.createCGImage(image, from: image.extent)
    }

    static func export(_ image: CGImage, to url: URL, format: ExportFormat, quality: Double = 0.92) throws {
        // Encode before touching the destination; writes are atomic and preserve the original on failure.
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil) else { throw ImageError.exportFailed }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality, kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageError.exportFailed }
        try (data as Data).write(to: url, options: .atomic)
    }
}

enum ImageError: LocalizedError {
    case unreadable, tooLarge, exportFailed
    var errorDescription: String? {
        switch self {
        case .unreadable: return "无法解码这张图片。文件可能损坏，或当前系统不支持此图片格式。"
        case .tooLarge: return "图片超过 1 亿像素，请先使用其他工具缩小后再打开。"
        case .exportFailed: return "图片导出失败，请换一种格式或选择其他保存位置。"
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG", jpeg = "JPEG", tiff = "TIFF", heic = "HEIC"
    var id: String { rawValue }
    var type: UTType { switch self { case .png: return .png; case .jpeg: return .jpeg; case .tiff: return .tiff; case .heic: return .heic } }
    var ext: String { switch self { case .png: return "png"; case .jpeg: return "jpg"; case .tiff: return "tiff"; case .heic: return "heic" } }
    var lossy: Bool { self == .jpeg || self == .heic }
    static var available: [Self] {
        let supported = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return allCases.filter { supported.contains($0.type.identifier) }
    }
}

enum PhotoPreset: String, CaseIterable, Identifiable {
    case original = "原色", vivid = "鲜明", mono = "黑白", warm = "复古", fade = "淡雅", noir = "光影"
    var id: String { rawValue }
    var filterName: String? {
        switch self {
        case .original: return nil
        case .vivid: return "CIPhotoEffectChrome"
        case .mono: return "CIPhotoEffectMono"
        case .warm: return "CIPhotoEffectInstant"
        case .fade: return "CIPhotoEffectFade"
        case .noir: return "CIPhotoEffectNoir"
        }
    }
}

struct EditState {
    var base: CGImage
    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var preset: PhotoPreset = .original
    func matches(_ other: EditState) -> Bool {
        base === other.base && brightness == other.brightness && contrast == other.contrast && saturation == other.saturation && preset == other.preset
    }
}

final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    init() { cache.totalCostLimit = 80 * 1024 * 1024 }
    func image(for url: URL, size: Int = 480) -> NSImage? {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSince1970) ?? 0
        let key = "\(url.path)-\(date)-\(size)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: size, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key, cost: cg.width * cg.height * 4)
        return image
    }
}

struct PhotoAlbum: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var paths: [String] = []
}
