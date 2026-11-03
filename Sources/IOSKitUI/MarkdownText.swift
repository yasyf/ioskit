import MarkdownUI
import SwiftUI

/// MarkdownText is the shared markdown primitive. It renders a markdown string in
/// one of three styles: `plain` prose, `clamped` (line-limited to 10 lines with a
/// "Show more" affordance when it overflows, mirroring web/src/components/Clamped.tsx),
/// or `struck` (the muted, strikethrough "was:" treatment, always unclamped).
public struct MarkdownText: View {
    /// Style selects how the markdown is presented.
    public enum Style {
        case plain
        case clamped
        case struck
    }

    let markdown: String
    var style: Style = .plain

    public init(_ markdown: String, style: Style = .plain) {
        self.markdown = markdown
        self.style = style
    }

    public var body: some View {
        switch style {
        case .plain:
            Markdown(markdown)
        case .clamped:
            ClampedMarkdown(markdown: markdown, lineLimit: 10)
        case .struck:
            Markdown(markdown)
                .markdownTextStyle {
                    ForegroundColor(Palette.was)
                    StrikethroughStyle(.init(pattern: .solid, color: nil))
                }
        }
    }
}

/// ClampedMarkdown caps its markdown at `lineLimit` lines while collapsed, fading
/// the trailing edge and offering a toggle when the content overflows. Expansion
/// state resets whenever the markdown changes, matching the web Clamped component.
private struct ClampedMarkdown: View {
    let markdown: String
    let lineLimit: Int

    @State private var expanded = false
    @State private var contentHeight: CGFloat = 0

    private var clampHeight: CGFloat {
        UIFont.preferredFont(forTextStyle: .body).lineHeight * CGFloat(lineLimit)
    }

    private var overflowing: Bool {
        contentHeight > clampHeight + 1
    }

    private var collapsed: Bool {
        !expanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Markdown(markdown)
                .frame(maxHeight: collapsed ? clampHeight : nil, alignment: .top)
                .clipped()
                .mask(alignment: .top) {
                    if collapsed, overflowing {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.65),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        Rectangle()
                    }
                }
                .background(alignment: .top) {
                    Markdown(markdown)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(key: MarkdownHeightKey.self, value: proxy.size.height)
                            }
                        }
                }
                .onPreferenceChange(MarkdownHeightKey.self) { height in
                    contentHeight = height
                }

            if overflowing {
                Button(expanded ? "Show less" : "Show more") {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                }
                .buttonStyle(.plain)
                .voice(.mono, size: 12, weight: .semibold)
                .foregroundStyle(Palette.accentInk)
                // Expansion is a read-only affordance, so it stays live inside a
                // history round's `.disabled(true)` subtree. `.disabled(false)` can't
                // undo that — SwiftUI ANDs nested disabled states — so write the
                // isEnabled environment key directly to override the ancestor.
                .environment(\.isEnabled, true)
            }
        }
        .onChange(of: markdown) { _, _ in
            expanded = false
        }
    }
}

private struct MarkdownHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview("Markdown styles") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            MarkdownText("A **plain** paragraph with `inline code`, a [link](https://example.com), and _emphasis_.")

            MarkdownText(
                """
                ## Clamped block

                This block runs long enough to overflow the ten-line clamp so the fade and
                the *Show more* toggle appear.

                - First consideration worth reading
                - Second consideration
                - Third consideration
                - Fourth consideration
                - Fifth consideration
                - Sixth consideration
                - Seventh consideration
                - Eighth consideration
                - Ninth consideration
                - Tenth consideration
                - Eleventh consideration, past the clamp
                """,
                style: .clamped
            )

            MarkdownText("~~This whole block wears the was: treatment~~ — muted and struck.", style: .struck)
        }
        .padding()
    }
}
