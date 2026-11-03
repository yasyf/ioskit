import IOSKit
import SwiftUI

/// AddRoute is the add-machine entry the roster's menu opens as a sheet.
private enum AddRoute: String, Identifiable {
    case scan
    case browse
    case manual

    var id: String {
        rawValue
    }
}

/// MachinesView is the app root: the roster of paired machines with a reachability
/// dot, an add-machine menu, swipe-to-forget, and a tailnet pair link opened from
/// anywhere. Tapping a machine opens `destination`.
public struct MachinesView<Destination: View>: View {
    @State private var model: MachinesModel
    @State private var pairing: PairingModel
    @State private var addRoute: AddRoute?
    private let identity: AppIdentity
    private let destination: (Machine) -> Destination

    public init(identity: AppIdentity, @ViewBuilder destination: @escaping (Machine) -> Destination) {
        let registry = KeychainMachineRegistry(identity: identity)
        _model = State(initialValue: MachinesModel(registry: registry))
        _pairing = State(initialValue: PairingModel(registry: registry, identity: identity))
        self.identity = identity
        self.destination = destination
    }

    public var body: some View {
        NavigationStack {
            roster
                .navigationTitle("Machines")
                .toolbar { addMenu }
                .task {
                    model.load()
                    await model.probeAll()
                }
                .refreshable { await model.probeAll() }
        }
        .sheet(item: $addRoute) { route in
            addSheet(route)
        }
        .onOpenURL { pairing.pair(link: $0) }
        .onChange(of: pairing.phase) { _, phase in
            if case .paired = phase {
                addRoute = nil
                pairing.reset()
                model.load()
                Task { await model.probeAll() }
            }
        }
        .alert("Couldn't Pair", isPresented: linkFailure) {
            Button("OK") { pairing.reset() }
        } message: {
            Text(failureMessage)
        }
    }

    private var failureMessage: String {
        if case let .failed(message) = pairing.phase {
            return message
        }
        return ""
    }

    private var linkFailure: Binding<Bool> {
        Binding(
            get: {
                if addRoute == nil, case .failed = pairing.phase {
                    true
                } else {
                    false
                }
            },
            set: { presented in
                if !presented {
                    pairing.reset()
                }
            }
        )
    }

    @ViewBuilder
    private var roster: some View {
        if model.machines.isEmpty {
            ContentUnavailableView {
                Label("No Machines", systemImage: "desktopcomputer")
            } description: {
                Text("Pair a machine running cc-present, or open its tailnet pair link.")
            } actions: {
                Button("Add Machine") { addRoute = .scan }
            }
        } else {
            List {
                ForEach(model.machines) { machine in
                    NavigationLink {
                        destination(machine)
                    } label: {
                        MachineRow(machine: machine, reachability: model.reachability(of: machine))
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.forget(machine)
                        } label: {
                            Label("Forget", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var addMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { addRoute = .scan } label: { Label("Scan QR Code", systemImage: "qrcode.viewfinder") }
                Button { addRoute = .browse } label: { Label("Browse Network", systemImage: "network") }
                Button { addRoute = .manual } label: { Label("Enter Manually", systemImage: "keyboard") }
            } label: {
                Label("Add Machine", systemImage: "plus")
            }
        }
    }

    private func addSheet(_ route: AddRoute) -> some View {
        NavigationStack {
            Group {
                switch route {
                case .scan: PairScannerView(pairing: pairing)
                case .browse: BonjourBrowserView(pairing: pairing, identity: identity)
                case .manual: ManualPairView(pairing: pairing)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismissAdd() }
                }
            }
        }
    }

    private func dismissAdd() {
        addRoute = nil
        pairing.reset()
    }
}

private struct MachineRow: View {
    let machine: Machine
    let reachability: Reachability

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(machine.name)
                    .font(.headline)
                Text(machine.baseURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .pairingRequired = reachability {
                    Text("Forget and pair this machine again.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var dotColor: Color {
        switch reachability {
        case .unknown: .secondary
        case .reachable: .green
        case .unreachable: .red
        case .pairingRequired: .orange
        }
    }
}
