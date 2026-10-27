import Foundation

enum ThumbnailSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String {
        switch self { case .small: return "小"; case .medium: return "中"; case .large: return "大" }
    }
    var minimumWidth: Double {
        switch self { case .small: return 180; case .medium: return 240; case .large: return 320 }
    }
    static func restored(from defaults: UserDefaults) -> Self {
        if let value = defaults.string(forKey: "thumbnailSize"), let size = Self(rawValue: value) { return size }
        let previous = defaults.double(forKey: "gridSize")
        guard previous.isFinite, previous > 0 else { return .medium }
        return allCases.min { abs($0.minimumWidth - previous) < abs($1.minimumWidth - previous) } ?? .medium
    }
}
