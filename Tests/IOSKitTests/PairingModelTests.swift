@testable import IOSKit
import Foundation
import Testing

/// FakeRegistry is an in-memory MachineRegistry: no filesystem, no Keychain, so the
/// pairing state machine runs in isolation. `addError`, when set, makes the persist
/// step fail so the failure branch is exercised.
final class FakeRegistry: MachineRegistry, @unchecked Sendable {
    var machines: [Machine] = []
    var tokens: [String: String] = [:]
    var addError: Error?

    func load() throws -> [Machine] {
        machines
    }

    func add(_ machine: Machine, token: String?) throws {
        if let addError {
            throw addError
        }
        machines.removeAll { $0.id == machine.id }
        machines.append(machine)
        tokens[machine.id] = token
    }

    func remove(_ machine: Machine) throws {
        machines.removeAll { $0.id == machine.id }
        tokens.removeValue(forKey: machine.id)
    }

    func token(for machineID: String) throws -> String? {
        tokens[machineID]
    }
}

struct FakeError: Error {}

let testIdentity = AppIdentity(
    name: "Test",
    storageNamespace: "ioskit-tests",
    bonjourType: "_ioskit-tests._tcp",
    pairScheme: "ccpresent"
)

@MainActor
@Test func pairPayloadPersistsMachineAndToken() throws {
    let registry = FakeRegistry()
    let model = PairingModel(registry: registry, identity: testIdentity)
    let url = try #require(URL(string: "http://192.168.1.5:8765"))

    model.pair(payload: PairPayload(version: 1, url: url, token: "secret"))

    let machine = try requirePaired(model)
    #expect(machine.baseURL == url)
    #expect(machine.name == "192.168.1.5:8765")
    #expect(registry.machines.count == 1)
    #expect(registry.tokens[machine.id] == "secret")
}

@MainActor
@Test func pairScannedDecodesJSONPayload() throws {
    let registry = FakeRegistry()
    let model = PairingModel(registry: registry, identity: testIdentity)

    model.pair(scanned: #"{"v":1,"url":"http://10.0.0.2:8765","token":"abc"}"#)

    let machine = try requirePaired(model)
    #expect(machine.baseURL == URL(string: "http://10.0.0.2:8765"))
    #expect(registry.tokens[machine.id] == "abc")
}

@MainActor
@Test func pairScannedRejectsGarbage() {
    let model = PairingModel(registry: FakeRegistry(), identity: testIdentity)

    model.pair(scanned: "not a qr code")

    guard case .failed = model.phase else {
        Issue.record("expected failed, got \(model.phase)")
        return
    }
}

@MainActor
@Test func pairScannedRejectsUnsupportedVersion() {
    let model = PairingModel(registry: FakeRegistry(), identity: testIdentity)

    model.pair(scanned: #"{"v":2,"url":"http://10.0.0.2:8765","token":"abc"}"#)

    guard case let .failed(message) = model.phase else {
        Issue.record("expected failed, got \(model.phase)")
        return
    }
    #expect(message.contains("version 2"))
}

@MainActor
@Test func pairLinkPersistsTokenlessMachine() throws {
    let registry = FakeRegistry()
    let model = PairingModel(registry: registry, identity: testIdentity)

    model.pair(link: #require(URL(string: "ccpresent://pair?url=https%3A%2F%2Fstudio.tail1234.ts.net%3A8765")))

    let machine = try requirePaired(model)
    #expect(machine.baseURL == URL(string: "https://studio.tail1234.ts.net:8765"))
    #expect(machine.name == "studio.tail1234.ts.net:8765")
    #expect(registry.tokens[machine.id] == nil)
}

@MainActor
@Test func pairLinkRejectsAnotherAppsLink() throws {
    let model = PairingModel(registry: FakeRegistry(), identity: testIdentity)

    model.pair(link: #require(URL(string: "longrunning://pair?url=https%3A%2F%2Fstudio.ts.net")))

    guard case .failed = model.phase else {
        Issue.record("expected failed, got \(model.phase)")
        return
    }
}

@MainActor
@Test func manualPairValidatesAndPersists() throws {
    let registry = FakeRegistry()
    let model = PairingModel(registry: registry, identity: testIdentity)

    model.pairManual(host: "localhost", port: "8765", token: "tok")

    let machine = try requirePaired(model)
    #expect(machine.baseURL == URL(string: "http://localhost:8765"))
    #expect(registry.tokens[machine.id] == "tok")
}

@MainActor
@Test func manualPairRejectsBadPort() {
    let model = PairingModel(registry: FakeRegistry(), identity: testIdentity)

    model.pairManual(host: "localhost", port: "notaport", token: "tok")

    guard case .failed = model.phase else {
        Issue.record("expected failed, got \(model.phase)")
        return
    }
}

@MainActor
@Test func manualPairRejectsEmptyToken() {
    let model = PairingModel(registry: FakeRegistry(), identity: testIdentity)

    model.pairManual(host: "localhost", port: "8765", token: "   ")

    guard case .failed = model.phase else {
        Issue.record("expected failed, got \(model.phase)")
        return
    }
}

@MainActor
@Test func commitFailurePropagates() {
    let registry = FakeRegistry()
    registry.addError = FakeError()
    let model = PairingModel(registry: registry, identity: testIdentity)

    model.pairManual(host: "localhost", port: "8765", token: "tok")

    guard case .failed = model.phase else {
        Issue.record("expected failed, got \(model.phase)")
        return
    }
    #expect(registry.machines.isEmpty)
}

@MainActor
@Test func resetReturnsToIdle() {
    let model = PairingModel(registry: FakeRegistry(), identity: testIdentity)
    model.pair(scanned: "garbage")

    model.reset()

    #expect(model.phase == .idle)
}

@Test func parseManualRejectsOutOfRangePort() {
    #expect(isFailure(PairingModel.parseManual(host: "h", port: "0", token: "t")))
    #expect(isFailure(PairingModel.parseManual(host: "h", port: "70000", token: "t")))
    #expect(isFailure(PairingModel.parseManual(host: "", port: "80", token: "t")))
}

private func isFailure(_ result: Result<PairingModel.PairDraft, PairingModel.PairFormError>) -> Bool {
    if case .failure = result {
        return true
    }
    return false
}

@MainActor
private func requirePaired(_ model: PairingModel) throws -> Machine {
    guard case let .paired(machine) = model.phase else {
        Issue.record("expected paired, got \(model.phase)")
        throw FakeError()
    }
    return machine
}
