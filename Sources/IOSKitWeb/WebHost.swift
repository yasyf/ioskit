import SwiftUI
import UIKit
import WebKit

public enum WebLoadPhase: Equatable, Sendable {
    case loading
    case loaded
    case failed
}

public extension URL {
    /// appendingTheme adds the `theme` query item — `"dark"` or `"light"` — that a
    /// page reads before first render, so a WKWebView renders in the host app's
    /// appearance instead of resolving the page's `light-dark()` to light.
    func appendingTheme(dark: Bool) -> URL {
        appending(queryItems: [URLQueryItem(name: "theme", value: dark ? "dark" : "light")])
    }
}

/// WebHost hosts a page in a WKWebView. With a `height` binding it sizes itself to
/// the page: the inner scroll is off and the height follows the `heightMessage`
/// frame (`{px: Number}`), with a KVO fallback on the scroll content size. Without
/// one it is an ordinary scrolling page. It carries the app's appearance to the page
/// as a `theme` query param and reloads on a mid-session flip; `handlers` receive the
/// bodies the page posts to each named message.
public struct WebHost: UIViewRepresentable {
    let url: URL
    let height: Binding<CGFloat>?
    let phase: Binding<WebLoadPhase>?
    let heightMessage: String?
    let handlers: [String: @MainActor (Any) -> Void]
    @Environment(\.colorScheme) private var colorScheme

    public init(
        url: URL,
        height: Binding<CGFloat>? = nil,
        phase: Binding<WebLoadPhase>? = nil,
        heightMessage: String? = nil,
        handlers: [String: @MainActor (Any) -> Void] = [:]
    ) {
        self.url = url
        self.height = height
        self.phase = phase
        self.heightMessage = heightMessage
        self.handlers = handlers
    }

    private var themedURL: URL {
        url.appendingTheme(dark: colorScheme == .dark)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(height: height, phase: phase, heightMessage: heightMessage, handlers: handlers)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        for name in context.coordinator.messageNames {
            controller.add(context.coordinator, name: name)
        }
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        if height != nil {
            webView.scrollView.isScrollEnabled = false
            webView.scrollView.bounces = false
            context.coordinator.observe(webView)
        }
        context.coordinator.load(webView, url: themedURL)
        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(webView, url: themedURL)
    }

    public static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.tearDown(webView)
    }

    @MainActor
    public final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        private let height: Binding<CGFloat>?
        private let phase: Binding<WebLoadPhase>?
        private let heightMessage: String?
        private let handlers: [String: @MainActor (Any) -> Void]
        private var observation: NSKeyValueObservation?
        private var loadedURL: URL?

        init(height: Binding<CGFloat>?, phase: Binding<WebLoadPhase>?, heightMessage: String?, handlers: [String: @MainActor (Any) -> Void]) {
            self.height = height
            self.phase = phase
            self.heightMessage = heightMessage
            self.handlers = handlers
        }

        var messageNames: [String] {
            Array(handlers.keys) + (heightMessage.map { [$0] } ?? [])
        }

        /// load points the web view at `url`, skipping the load when it already holds
        /// that URL so a SwiftUI update (a height change) never re-fetches — only an
        /// appearance flip, which flips the `theme` query, reloads.
        func load(_ webView: WKWebView, url: URL) {
            guard loadedURL != url else { return }
            loadedURL = url
            webView.load(URLRequest(url: url))
        }

        func observe(_ webView: WKWebView) {
            observation = webView.scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, change in
                guard let contentHeight = change.newValue?.height else { return }
                MainActor.assumeIsolated {
                    self?.apply(contentHeight)
                }
            }
        }

        func tearDown(_ webView: WKWebView) {
            observation?.invalidate()
            observation = nil
            let controller = webView.configuration.userContentController
            for name in messageNames {
                controller.removeScriptMessageHandler(forName: name)
            }
        }

        public func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == heightMessage {
                guard let px = Self.height(fromMessageBody: message.body) else { return }
                apply(px)
                return
            }
            handlers[message.name]?(message.body)
        }

        public func webView(_: WKWebView, didFinish _: WKNavigation!) {
            phase?.wrappedValue = .loaded
        }

        public func webView(_: WKWebView, didFail _: WKNavigation!, withError _: Error) {
            phase?.wrappedValue = .failed
        }

        public func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
            phase?.wrappedValue = .failed
        }

        /// A `target="_blank"` link asks the page to open a window; the host never
        /// shows one, so route an http(s) target to the system browser and return nil
        /// so no orphan web view is created.
        public func webView(_: WKWebView, createWebViewWith _: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
            if let url = Self.externalURL(for: navigationAction.request) {
                UIApplication.shared.open(url)
            }
            return nil
        }

        /// externalURL is the http(s) target a new-window navigation hands to the system
        /// browser, or nil for a scheme that should not escape the webview.
        nonisolated static func externalURL(for request: URLRequest) -> URL? {
            guard let url = request.url, let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return nil }
            return url
        }

        private func apply(_ newHeight: CGFloat) {
            guard let height, let next = Self.clampedHeight(current: height.wrappedValue, proposed: newHeight) else { return }
            height.wrappedValue = next
        }

        /// height(fromMessageBody:) reads the `px` number a height frame carries, or
        /// nil for a body outside the expected `{px: Number}` shape.
        nonisolated static func height(fromMessageBody body: Any) -> CGFloat? {
            guard let payload = body as? [String: Any], let px = payload["px"] as? NSNumber else { return nil }
            return CGFloat(truncating: px)
        }

        /// clampedHeight is the height to apply, or nil when the proposal is
        /// non-positive or within a point of the current — sub-point churn is dropped.
        nonisolated static func clampedHeight(current: CGFloat, proposed: CGFloat) -> CGFloat? {
            guard proposed > 0, abs(proposed - current) >= 1 else { return nil }
            return proposed
        }
    }
}
