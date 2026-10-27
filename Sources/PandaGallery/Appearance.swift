import AppKit
import SwiftUI

enum GalleryTheme: String, CaseIterable, Identifiable {
    case day, night
    var id: String { rawValue }
    var title: String { self == .day ? "白天" : "黑夜" }
    var symbol: String { self == .day ? "sun.max" : "moon" }
    var colorScheme: ColorScheme { self == .day ? .light : .dark }
    var appearance: NSAppearance? { NSAppearance(named: self == .day ? .aqua : .darkAqua) }
    static func restored(from defaults: UserDefaults) -> Self {
        defaults.string(forKey: "appearanceMode").flatMap(Self.init(rawValue:)) ?? .day
    }
}

enum Palette {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: adaptiveNS(light, dark))
    }
    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    static func adaptiveNS(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            color(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        }
    }
    static let background = adaptive(0xFAFBFB, 0x191B1C)
    static let sidebar = adaptive(0xF2F4F3, 0x202323)
    static let card = adaptive(0xE9EDEB, 0x2A2E2C)
    static let line = adaptive(0xE2E6E3, 0x353A37)
    static let muted = adaptive(0x747D77, 0x99A29C)
    static let text = adaptive(0x29312C, 0xE5EAE6)
    static let mint = adaptive(0x487461, 0xA7CAB6)
    static let selected = adaptive(0xE2ECE6, 0x303E35)
    static let onAccent = adaptive(0xFFFFFF, 0x19291F)
    static let canvas = adaptiveNS(0xF4F6F5, 0x151718)
}
