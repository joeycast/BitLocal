import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// BitLocal's color tokens (docs/redesign/ui-redesign.md section 3.2).
/// Orange means "this one": pins, the selected merchant, and the one
/// primary action per screen. Everything else uses system semantic colors.
public enum BrandColor {
    /// Pin fill, selected-pin ring, cluster bubble, progress bar, icons ≥ 20pt.
    /// Graphic use only: it is 2.7:1 on white, so pins always get a white stroke.
    public static let brand = Color(light: 0xFC780F, dark: 0xFC780F)

    /// Orange text and small glyphs (links, selected chip labels). ≥ 4.5:1 in both modes.
    public static let brandInk = Color(light: 0xB34D00, dark: 0xFF8A1F)

    /// Primary button background. Deeper in light mode so the white label reads (4.6:1).
    public static let brandFill = Color(light: 0xC25400, dark: 0xFC780F)

    /// Label on `brandFill`: white in light mode, near-black in dark mode (7.8:1).
    public static let onBrandFill = Color(light: 0xFFFFFF, dark: 0x1C1C1E)

    /// Boosted ring on pins and the "Featured" tag.
    public static let boost = Color(light: 0xB8860B, dark: 0xE6B84C)

    /// Open-status text. Always paired with a word, never color alone.
    public static let open = Color.green
    public static let closed = Color.red

    /// Selected list row background (brand at 12%).
    public static let selectionFill = brand.opacity(0.12)
}

extension Color {
    /// A color with separate light and dark appearances, from 0xRRGGBB values.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
        #else
        self.init(rgb: light)
        #endif
    }

    init(rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#elseif canImport(AppKit)
extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif
