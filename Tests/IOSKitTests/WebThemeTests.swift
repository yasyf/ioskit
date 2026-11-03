import IOSKitWeb
import Foundation
import Testing

@Suite("Single-block theme query")
struct WebThemeTests {
    private let base = URL(string: "http://192.168.1.42:8790/p/sess-1?block=ex-rating")!

    @Test("a dark appearance appends theme=dark after the existing query")
    func darkAppendsThemeDark() {
        #expect(
            base.appendingTheme(dark: true).absoluteString
                == "http://192.168.1.42:8790/p/sess-1?block=ex-rating&theme=dark"
        )
    }

    @Test("a light appearance appends theme=light after the existing query")
    func lightAppendsThemeLight() {
        #expect(
            base.appendingTheme(dark: false).absoluteString
                == "http://192.168.1.42:8790/p/sess-1?block=ex-rating&theme=light"
        )
    }

    @Test("the theme flips with the appearance")
    func themeFlipsWithAppearance() {
        #expect(base.appendingTheme(dark: true) != base.appendingTheme(dark: false))
    }
}
