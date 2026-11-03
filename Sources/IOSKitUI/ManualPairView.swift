import IOSKit
import SwiftUI

/// ManualPairView collects a host, port, and token by hand — the fallback when a QR
/// scan isn't possible and the token entry for a Bonjour-discovered machine.
struct ManualPairView: View {
    let pairing: PairingModel
    var prefillHost: String = ""
    var prefillPort: String = ""

    @State private var host = ""
    @State private var port = ""
    @State private var token = ""

    var body: some View {
        Form {
            Section("Machine") {
                TextField("Host", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Port", text: $port)
                    .keyboardType(.numberPad)
            }
            Section("Pairing Token") {
                TextField("Token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if case let .failed(message) = pairing.phase {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button("Pair") {
                    pairing.pairManual(host: host, port: port, token: token)
                }
                .disabled(!canSubmit)
            }
        }
        .navigationTitle("Enter Manually")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if host.isEmpty {
                host = prefillHost
            }
            if port.isEmpty {
                port = prefillPort
            }
        }
    }

    private var canSubmit: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
