import SwiftUI

/// Palette maps the shared "Blue Pencil" design tokens — the `light-dark()`
/// pairs the web renderer typesets with (web/src/styles/tokens.css) — onto
/// theme-aware SwiftUI colors, so native blocks match the web token for token.
/// Derived tones (`chipBg`, `line`, `borderStrong`, `was`) resolve the web
/// `color-mix()` recipes per scheme, so they are literal here rather than mixed live.
public enum Palette {
    public static let ink = Color(hexLight: 0x1F2430, hexDark: 0xECE7DB)
    public static let monoBg = Color(hexLight: 0xF1F1EF, hexDark: 0x0F0D0A)
    public static let chipBg = Color(hexLight: 0xEEEDEA, hexDark: 0x23201C)
    public static let line = Color(hexLight: 0xDCDCDA, hexDark: 0x34312C)
    public static let borderStrong = Color(hexLight: 0xBDBEBF, hexDark: 0x524E49)
    public static let muted = Color(hexLight: 0x5C6472, hexDark: 0xA69D8D)
    public static let was = Color(hexLight: 0x747B86, hexDark: 0x90887A)
    public static let approve = Color(hexLight: 0x1E7B4F, hexDark: 0x54C787)
    public static let reject = Color(hexLight: 0xBF3B2F, hexDark: 0xEF7F6C)
    public static let warn = Color(hexLight: 0x8F6400, hexDark: 0xD9A64A)
    public static let accentInk = Color(hexLight: 0x3D56C5, hexDark: 0x96A8F8)
    public static let accentFg = Color(hexLight: 0xFFFFFF, hexDark: 0x161310)

    /// cardLift is the +2 elevation tier — sheets, dialogs, the submit bar — one warm
    /// step above the card. Mirrors the web `--card-lift`.
    public static let cardLift = Color(hexLight: 0xFFFFFF, hexDark: 0x262119)

    /// edgeLift is the dark-elevation top highlight: a hairline ~5% white that catches the
    /// light on a raised surface's top edge, invisible in light mode. Apply via
    /// `View.edgeLift()` over a `cardLift` ground. Mirrors the web `--edge-lift`.
    public static let edgeLift = Color(whiteLight: 1, alphaLight: 0, whiteDark: 1, alphaDark: 0.05)

    /// factTone maps a fact tone (`good`, `warn`, `bad`) onto its signal color, and any
    /// other tone onto `fallback`.
    public static func factTone(_ tone: String?, fallback: Color = ink) -> Color {
        switch tone {
        case "good": approve
        case "warn": warn
        case "bad": reject
        default: fallback
        }
    }
}

public extension View {
    /// edgeLift overlays the dark-elevation top highlight — a hairline ~5% white inset
    /// along a raised surface's top edge, matching the web `--edge-lift`; a no-op in light.
    func edgeLift(cornerRadius: CGFloat = Metrics.radiusLg) -> some View {
        overlay(alignment: .top) {
            Palette.edgeLift
                .frame(height: 1)
                .padding(.horizontal, cornerRadius)
                .allowsHitTesting(false)
        }
    }
}

private extension Color {
    init(hexLight: UInt32, hexDark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? hexDark : hexLight)
        })
    }

    init(whiteLight: Double, alphaLight: Double, whiteDark: Double, alphaDark: Double) {
        self.init(uiColor: UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            return UIColor(white: dark ? whiteDark : whiteLight, alpha: dark ? alphaDark : alphaLight)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
