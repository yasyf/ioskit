import SwiftUI

/// PrimaryButtonStyle is the filled accent call-to-action — Send, Submit, Next: pencil
/// ink under the accent foreground, squared to the control radius. Replaces
/// `.borderedProminent` tinted `accentInk`.
public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}

    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .voice(.prose, size: 15, weight: .semibold)
            .foregroundStyle(Palette.accentFg)
            .padding(.horizontal, Metrics.space4)
            .padding(.vertical, Metrics.space2)
            .frame(minHeight: 44)
            .background(Palette.accentInk, in: RoundedRectangle(cornerRadius: Metrics.radiusMd))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.82 : 1)
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// GhostButtonStyle is the quiet, borderless companion — Cancel, Back, Skip, and the
/// bare "Add feedback"/"Add note" affordances: tinted text with a faint pressed wash.
/// Defaults to the pencil accent; pass `tint` for a recessive control.
public struct GhostButtonStyle: ButtonStyle {
    var tint: Color

    public init(tint: Color = Palette.accentInk) {
        self.tint = tint
    }

    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .voice(.prose, size: 14, weight: .semibold)
            .foregroundStyle(tint)
            .padding(.horizontal, Metrics.space3)
            .padding(.vertical, Metrics.space2)
            .background(
                configuration.isPressed ? tint.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: Metrics.radiusMd)
            )
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// VerdictButtonStyle is the hand-drawn Approve/Reject pill unified from the duplicated
/// ApprovalBlockView and TriageBlockView implementations: an outlined pill that fills
/// with its verdict ink when active and flips the label to the accent foreground.
public struct VerdictButtonStyle: ButtonStyle {
    let tint: Color
    let active: Bool

    public init(tint: Color, active: Bool) {
        self.tint = tint
        self.active = active
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(active ? Palette.accentFg : tint)
            .background(active ? tint : Color.clear, in: RoundedRectangle(cornerRadius: Metrics.radiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusMd)
                    .strokeBorder(tint.opacity(active ? 0 : 0.55), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// VerdictLabel is the glyph-and-word content of a verdict pill, shared by every
/// VerdictButtonStyle call site so the two verdict surfaces read identically.
public struct VerdictLabel: View {
    let glyph: String
    let title: String

    public init(glyph: String, title: String) {
        self.glyph = glyph
        self.title = title
    }

    public var body: some View {
        HStack(spacing: Metrics.space1) {
            Image(systemName: glyph)
                .font(.system(size: 13, weight: .bold))
            Text(title)
                .voice(.prose, size: 15, weight: .semibold)
        }
    }
}
