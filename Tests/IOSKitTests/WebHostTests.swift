@testable import IOSKitWeb
import CoreGraphics
import Foundation
import Testing

@Suite("WebHost message plumbing")
struct WebHostTests {
    @Test("a well-formed height body yields its px value")
    func heightReadsPxFromBody() {
        #expect(WebHost.Coordinator.height(fromMessageBody: ["px": 214]) == 214)
        #expect(WebHost.Coordinator.height(fromMessageBody: ["px": 88.5]) == 88.5)
    }

    @Test("a body of the wrong shape yields nil")
    func heightRejectsMalformedBody() {
        #expect(WebHost.Coordinator.height(fromMessageBody: "214") == nil)
        #expect(WebHost.Coordinator.height(fromMessageBody: ["height": 214]) == nil)
        #expect(WebHost.Coordinator.height(fromMessageBody: ["px": "214"]) == nil)
    }

    @Test("a meaningfully different positive height is applied")
    func clampAcceptsMeaningfulChange() {
        #expect(WebHost.Coordinator.clampedHeight(current: 140, proposed: 320) == 320)
        #expect(WebHost.Coordinator.clampedHeight(current: 140, proposed: 141) == 141)
    }

    @Test("a sub-point or non-positive proposal is dropped")
    func clampDropsChurnAndNonPositive() {
        #expect(WebHost.Coordinator.clampedHeight(current: 140, proposed: 140.4) == nil)
        #expect(WebHost.Coordinator.clampedHeight(current: 140, proposed: 140) == nil)
        #expect(WebHost.Coordinator.clampedHeight(current: 140, proposed: 0) == nil)
        #expect(WebHost.Coordinator.clampedHeight(current: 140, proposed: -5) == nil)
    }

    @Test("an http(s) new-window request yields its url for external open")
    func externalURLForHttpLinks() throws {
        let https = try #require(URL(string: "https://example.com/docs"))
        let http = try #require(URL(string: "http://example.com"))
        #expect(WebHost.Coordinator.externalURL(for: URLRequest(url: https)) == https)
        #expect(WebHost.Coordinator.externalURL(for: URLRequest(url: http)) == http)
    }

    @Test("a non-http scheme is not opened externally")
    func externalURLRejectsOtherSchemes() throws {
        for raw in ["mailto:a@example.com", "ftp://example.com/x", "tel:+15551234567"] {
            let url = try #require(URL(string: raw))
            #expect(WebHost.Coordinator.externalURL(for: URLRequest(url: url)) == nil)
        }
    }
}
