import Foundation
import Observation

/// MachineRegistry is the persistence seam the pairing flow writes through and the
/// roster reads from: the Machine record in the JSON store and its bearer token in
/// the Keychain, moved as one unit. KeychainMachineRegistry is the production
/// conformer; tests inject an in-memory fake so no filesystem or Keychain is touched.
public protocol MachineRegistry: Sendable {
    func load() throws -> [Machine]
    func add(_ machine: Machine, token: String?) throws
    func remove(_ machine: Machine) throws
    func token(for machineID: String) throws -> String?
}

/// KeychainMachineRegistry stores the roster in Application Support and each token
/// in the Keychain, keeping the secret out of the JSON record.
public struct KeychainMachineRegistry: MachineRegistry {
    private let identity: AppIdentity

    public init(identity: AppIdentity) {
        self.identity = identity
    }

    public func load() throws -> [Machine] {
        try store().load()
    }

    public func add(_ machine: Machine, token: String?) throws {
        if let token {
            try tokens.setToken(token, machineID: machine.id)
        } else {
            try tokens.deleteToken(machineID: machine.id)
        }
        var machines = try store().load()
        machines.removeAll { $0.id == machine.id }
        machines.append(machine)
        try store().save(machines)
    }

    public func remove(_ machine: Machine) throws {
        var machines = try store().load()
        machines.removeAll { $0.id == machine.id }
        try store().save(machines)
        try tokens.deleteToken(machineID: machine.id)
    }

    public func token(for machineID: String) throws -> String? {
        try tokens.token(machineID: machineID)
    }

    private var tokens: TokenStore {
        TokenStore(service: identity.keychainService)
    }

    private func store() throws -> MachineStore {
        try MachineStore(directory: MachineStore.defaultDirectory(namespace: identity.storageNamespace))
    }
}

/// SessionsClientFactory builds the probe client for a machine, given its bearer
/// token. Production returns an HTTPClient; tests return a fake.
public typealias SessionsClientFactory = @Sendable (Machine, String?) -> any SessionsProviding

/// Reachability is the machine-row status dot: unknown until the first probe
/// resolves, then reachable, unreachable, or requiring a fresh pairing.
public enum Reachability: Sendable, Equatable {
    case unknown
    case reachable
    case unreachable
    case pairingRequired
}

/// MachinesModel owns the paired-machine roster and a lightweight reachability probe
/// per machine. The probe hits /api/sessions, so a green dot means the daemon is up
/// and accepts this phone, by token or by tailnet identity.
@MainActor
@Observable
public final class MachinesModel {
    public private(set) var machines: [Machine] = []
    public private(set) var reachability: [String: Reachability] = [:]
    public private(set) var loadError: String?

    private let registry: any MachineRegistry
    private let clientFactory: SessionsClientFactory

    public init(registry: any MachineRegistry, clientFactory: @escaping SessionsClientFactory = MachinesModel.defaultClientFactory) {
        self.registry = registry
        self.clientFactory = clientFactory
    }

    public nonisolated static let defaultClientFactory: SessionsClientFactory = { machine, token in
        HTTPClient(baseURL: machine.baseURL, bearerToken: token)
    }

    /// load refreshes the roster from the registry.
    public func load() {
        do {
            machines = try registry.load()
            loadError = nil
        } catch {
            loadError = "Couldn't load your machines."
        }
    }

    /// forget drops a machine from the roster and deletes its Keychain token.
    public func forget(_ machine: Machine) {
        do {
            try registry.remove(machine)
        } catch {
            loadError = "Couldn't forget this machine."
            return
        }
        reachability.removeValue(forKey: machine.id)
        load()
    }

    /// probeAll probes every machine concurrently.
    public func probeAll() async {
        await withTaskGroup(of: Void.self) { group in
            for machine in machines {
                group.addTask { await self.probe(machine) }
            }
        }
    }

    /// probe asks the machine for its sessions with whatever token it holds. A
    /// refused credential requests re-pairing; transport failures are unreachable.
    public func probe(_ machine: Machine) async {
        let token: String?
        do {
            token = try registry.token(for: machine.id)
        } catch {
            reachability[machine.id] = .pairingRequired
            return
        }
        do {
            _ = try await clientFactory(machine, token).sessions()
            reachability[machine.id] = .reachable
        } catch let APIError.status(code, _) where code == 401 || code == 403 {
            reachability[machine.id] = .pairingRequired
        } catch {
            reachability[machine.id] = .unreachable
        }
    }

    public func reachability(of machine: Machine) -> Reachability {
        reachability[machine.id] ?? .unknown
    }
}

/// PairingModel is the shared pairing state machine every add-machine path drives:
/// a scanned QR payload, a tailnet link, or a manually typed host/port/token all
/// converge on `commit`, which persists the machine through the registry. The phase
/// advances idle → paired on success or idle → failed with a display reason, and
/// `reset` returns it to idle when a sheet is dismissed or a scan is retried.
@MainActor
@Observable
public final class PairingModel {
    /// Phase is the outcome of the current pairing attempt.
    public enum Phase: Equatable {
        case idle
        case paired(Machine)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle

    private let registry: any MachineRegistry
    private let identity: AppIdentity

    public init(registry: any MachineRegistry, identity: AppIdentity) {
        self.registry = registry
        self.identity = identity
    }

    /// reset clears the phase back to idle.
    public func reset() {
        phase = .idle
    }

    /// pair(scanned:) decodes a scanned QR string into a PairPayload and pairs it,
    /// mapping a wrong version or unparseable string to a failure reason.
    public func pair(scanned string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let payload = try JSONDecoder().decode(PairPayload.self, from: Data(trimmed.utf8))
            pair(payload: payload)
        } catch let PairError.unsupportedVersion(version) {
            phase = .failed("This pairing code is version \(version); update the app to pair with it.")
        } catch {
            phase = .failed("That QR code isn't a pairing code.")
        }
    }

    public func pair(link: URL) {
        do {
            try pair(payload: PairPayload(link: link, scheme: identity.pairScheme))
        } catch {
            phase = .failed("That link doesn't name a machine to pair.")
        }
    }

    /// pair(payload:) pairs a decoded handshake, naming the machine from its URL.
    public func pair(payload: PairPayload) {
        commit(Machine(name: Self.name(for: payload.url), baseURL: payload.url), token: payload.token)
    }

    /// pairManual validates typed fields and pairs them, failing with a per-field
    /// reason when a value is missing or malformed.
    public func pairManual(host: String, port: String, token: String) {
        switch Self.parseManual(host: host, port: port, token: token) {
        case let .success(draft):
            commit(Machine(name: Self.name(for: draft.url), baseURL: draft.url), token: draft.token)
        case let .failure(error):
            phase = .failed(error.message)
        }
    }

    private func commit(_ machine: Machine, token: String?) {
        do {
            try registry.add(machine, token: token)
            phase = .paired(machine)
        } catch {
            phase = .failed("Couldn't save this machine.")
        }
    }

    public nonisolated static func name(for url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }

    /// PairDraft is a validated manual entry ready to persist.
    public struct PairDraft: Equatable, Sendable {
        public let url: URL
        public let token: String
    }

    /// PairFormError is a manual-entry validation failure carrying its display reason.
    public struct PairFormError: Error, Equatable {
        public let message: String
    }

    /// parseManual validates a typed host, port, and token into a PairDraft. It is a
    /// pure function so the pairing rules can be exercised directly in tests.
    public nonisolated static func parseManual(host: String, port: String, token: String) -> Result<PairDraft, PairFormError> {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            return .failure(PairFormError(message: "Enter the machine's host."))
        }
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let portValue = Int(trimmedPort), (1 ... 65535).contains(portValue) else {
            return .failure(PairFormError(message: "Enter a port between 1 and 65535."))
        }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            return .failure(PairFormError(message: "Enter the pairing token."))
        }
        var components = URLComponents()
        components.scheme = "http"
        components.host = trimmedHost
        components.port = portValue
        guard let url = components.url, url.host() != nil else {
            return .failure(PairFormError(message: "That host and port don't form a valid address."))
        }
        return .success(PairDraft(url: url, token: trimmedToken))
    }
}
