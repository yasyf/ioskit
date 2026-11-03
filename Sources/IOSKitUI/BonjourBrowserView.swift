import IOSKit
import Network
import Observation
import SwiftUI
import UIKit

/// DiscoveredMachine is one Bonjour result: the advertised service name and, once
/// resolved, the `http://host:port` URL a pairing scan can prefill.
struct DiscoveredMachine: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    var url: URL?
}

/// BonjourModel browses for the identity's Bonjour advertisers and resolves each to a
/// host and port. The first browse triggers the local-network permission prompt; a
/// denial surfaces as a silent empty result, which the view explains with a Settings
/// deep link rather than a hard error.
@MainActor
@Observable
final class BonjourModel {
    private(set) var services: [DiscoveredMachine] = []

    private var browser: NWBrowser?
    private let serviceType: String
    private let queue = DispatchQueue(label: "ioskit.bonjour")

    init(serviceType: String) {
        self.serviceType = serviceType
    }

    /// start begins browsing; calling it again while a browse is live is a no-op.
    func start() {
        guard browser == nil else { return }
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: NWParameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.ingest(results)
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    /// stop tears the browse down and clears discovered rows.
    func stop() {
        browser?.cancel()
        browser = nil
        services = []
    }

    private nonisolated func ingest(_ results: Set<NWBrowser.Result>) {
        var names: [String] = []
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            names.append(name)
            resolve(result.endpoint, name: name)
        }
        let discovered = names.sorted()
        Task { @MainActor [weak self] in self?.merge(names: discovered) }
    }

    private nonisolated func resolve(_ endpoint: NWEndpoint, name: String) {
        let box = ConnectionBox(NWConnection(to: endpoint, using: .tcp))
        box.connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let url = Self.resolvedURL(from: box.connection.currentPath?.remoteEndpoint) {
                    Task { @MainActor [weak self] in self?.setURL(name: name, url: url) }
                }
                box.connection.cancel()
            case .failed, .cancelled:
                box.connection.stateUpdateHandler = nil
            default:
                break
            }
        }
        box.connection.start(queue: queue)
    }

    private nonisolated static func resolvedURL(from endpoint: NWEndpoint?) -> URL? {
        guard case let .hostPort(host, port)? = endpoint else { return nil }
        return URL(string: "http://\(hostString(host)):\(port.rawValue)")
    }

    private func merge(names: [String]) {
        services = names.map { name in
            services.first { $0.id == name } ?? DiscoveredMachine(id: name, name: name, url: nil)
        }
    }

    private func setURL(name: String, url: URL) {
        guard let index = services.firstIndex(where: { $0.id == name }) else { return }
        services[index].url = url
    }

    private nonisolated static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case let .name(name, _): name
        case let .ipv4(address): "\(address)"
        case let .ipv6(address): "[\(address)]"
        @unknown default: ""
        }
    }
}

/// ConnectionBox carries an NWConnection into the resolver's Sendable state handler.
/// The connection is only ever touched on the browse queue, so the unchecked
/// conformance is sound.
private final class ConnectionBox: @unchecked Sendable {
    let connection: NWConnection

    init(_ connection: NWConnection) {
        self.connection = connection
    }
}

/// BonjourBrowserView lists machines discovered on the local network. A discovered
/// machine still needs its token, so tapping a row opens the QR scanner with the
/// host prefilled for manual token entry as a fallback.
struct BonjourBrowserView: View {
    let pairing: PairingModel
    let identity: AppIdentity

    @State private var model: BonjourModel

    init(pairing: PairingModel, identity: AppIdentity) {
        self.pairing = pairing
        self.identity = identity
        _model = State(initialValue: BonjourModel(serviceType: identity.bonjourType))
    }
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section("Discovered") {
                if model.services.isEmpty {
                    Label("Searching…", systemImage: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.services) { service in
                        row(for: service)
                    }
                }
            }
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                }
            } header: {
                Text("Not Seeing Your Machine?")
            } footer: {
                Text(
                    "Discovery needs Local Network permission. If nothing appears, "
                        + "make sure it's allowed for \(identity.name) in Settings."
                )
            }
        }
        .navigationTitle("Browse Network")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: URL.self) { url in
            PairScannerView(pairing: pairing, prefillURL: url)
        }
        .task { model.start() }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private func row(for service: DiscoveredMachine) -> some View {
        if let url = service.url {
            NavigationLink(value: url) {
                serviceLabel(service, subtitle: url.absoluteString)
            }
        } else {
            HStack {
                serviceLabel(service, subtitle: "Resolving…")
                Spacer()
                ProgressView()
            }
        }
    }

    private func serviceLabel(_ service: DiscoveredMachine, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(service.name)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
