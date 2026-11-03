import SwiftUI

/// Metrics is the spacing-and-radius scale native blocks lay out on: the spacing ramp
/// mirrors the web `--space-1…8` in points, the radii the squared `--radius-sm/md/lg`.
public enum Metrics {
    public static let space1: CGFloat = 4
    public static let space2: CGFloat = 8
    public static let space3: CGFloat = 12
    public static let space4: CGFloat = 16
    public static let space5: CGFloat = 24
    public static let space6: CGFloat = 32
    public static let space7: CGFloat = 40
    public static let space8: CGFloat = 48

    public static let radiusSm: CGFloat = 2
    public static let radiusMd: CGFloat = 4
    public static let radiusLg: CGFloat = 6
}

/// Voice is one of the four type roles, each a bundled-font-free system face: prose is
/// SF Pro, display is New York (`.serif`), stamp is SF condensed, mono is SF Mono.
/// Mirrors the web `--font-prose/display/stamp/mono`.
public enum Voice {
    case prose
    case display
    case stamp
    case mono

    /// font resolves the voice to a system `Font` at a fixed point size.
    public func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .prose: .system(size: size, weight: weight)
        case .display: .system(size: size, weight: weight, design: .serif)
        case .stamp: .system(size: size, weight: weight).width(.condensed)
        case .mono: .system(size: size, weight: weight, design: .monospaced)
        }
    }

    /// font resolves the voice to a Dynamic-Type text style.
    public func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .prose: .system(style, weight: weight)
        case .display: .system(style, design: .serif, weight: weight)
        case .stamp: .system(style, weight: weight).width(.condensed)
        case .mono: .system(style, design: .monospaced, weight: weight)
        }
    }
}

private struct VoiceModifier: ViewModifier {
    let voice: Voice
    let font: Font
    let tracking: CGFloat

    func body(content: Content) -> some View {
        content
            .font(font)
            .textCase(voice == .stamp ? .uppercase : nil)
            .tracking(tracking)
    }
}

public extension View {
    /// voice applies a `Voice` at a point size; stamp adds tracked uppercase (`--track-caps`).
    func voice(_ voice: Voice, size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(VoiceModifier(
            voice: voice,
            font: voice.font(size: size, weight: weight),
            tracking: voice == .stamp ? size * 0.1 : 0
        ))
    }

    /// voice applies a `Voice` at a Dynamic-Type text style.
    func voice(_ voice: Voice, _ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        modifier(VoiceModifier(
            voice: voice,
            font: voice.font(style, weight: weight),
            tracking: voice == .stamp ? 1.2 : 0
        ))
    }
}
