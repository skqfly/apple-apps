import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - App Theme & Dynamic Accent

/// Manages the user's selected accent color and persists it across launches.
@Observable
final class AppTheme: @unchecked Sendable {
    static let shared = AppTheme()

    /// Pre-configured designer palettes for one-tap switching.
    struct Preset: Identifiable, Hashable {
        let id: String
        let name: String
        let hex: String
        let color: Color
    }

    static let presets: [Preset] = [
        Preset(id: "emerald", name: "翡翠绿", hex: "#296B58", color: Color(red: 0.1608, green: 0.4196, blue: 0.4431)),
        Preset(id: "teal", name: "极光青", hex: "#0E8A8A", color: Color(red: 0.055, green: 0.541, blue: 0.541)),
        Preset(id: "blue", name: "克莱因蓝", hex: "#2A64D9", color: Color(red: 0.165, green: 0.392, blue: 0.851)),
        Preset(id: "violet", name: "丁香紫", hex: "#7852FF", color: Color(red: 0.471, green: 0.322, blue: 1.000)),
        Preset(id: "sunset", name: "晚霞橙", hex: "#E65A28", color: Color(red: 0.902, green: 0.353, blue: 0.157)),
        Preset(id: "rose", name: "绯樱红", hex: "#E53E6D", color: Color(red: 0.898, green: 0.243, blue: 0.427)),
        Preset(id: "amber", name: "琥珀金", hex: "#D97706", color: Color(red: 0.851, green: 0.467, blue: 0.024)),
        Preset(id: "slate", name: "石墨灰", hex: "#374151", color: Color(red: 0.216, green: 0.255, blue: 0.318))
    ]

    private let defaultsKey = "customThemeAccentHex"
    private let lock = NSLock()

    var selectedHex: String {
        didSet {
            UserDefaults.standard.set(selectedHex, forKey: defaultsKey)
            updateAccentColor()
        }
    }

    private var _accentColor: Color = Color(red: 0.1608, green: 0.4196, blue: 0.4431)

    var accentColor: Color {
        lock.lock()
        defer { lock.unlock() }
        return _accentColor
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: defaultsKey) ?? "#296B58"
        self.selectedHex = stored
        if let resolved = Color(hex: stored) {
            self._accentColor = resolved
        } else {
            self._accentColor = Self.presets[0].color
        }
    }

    func selectPreset(_ preset: Preset) {
        selectedHex = preset.hex
        Haptics.selection()
    }

    func selectCustomColor(_ color: Color) {
        if let hex = color.toHex() {
            selectedHex = hex
            Haptics.selection()
        }
    }

    func resetToDefault() {
        selectedHex = Self.presets[0].hex
        Haptics.medium()
    }

    private func updateAccentColor() {
        lock.lock()
        if let resolved = Color(hex: selectedHex) {
            _accentColor = resolved
        } else {
            _accentColor = Self.presets[0].color
        }
        lock.unlock()
    }
}

// MARK: - Color Hex Conversion

extension Color {
    init?(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6 || clean.count == 8 else { return nil }
        var rgbValue: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&rgbValue) else { return nil }

        let r, g, b, a: Double
        if clean.count == 6 {
            r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
            g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
            b = Double(rgbValue & 0x0000FF) / 255.0
            a = 1.0
        } else {
            r = Double((rgbValue & 0xFF000000) >> 24) / 255.0
            g = Double((rgbValue & 0x00FF0000) >> 16) / 255.0
            b = Double((rgbValue & 0x0000FF00) >> 8) / 255.0
            a = Double(rgbValue & 0x000000FF) / 255.0
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }

    func toHex() -> String? {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
        #else
        return nil
        #endif
    }
}
