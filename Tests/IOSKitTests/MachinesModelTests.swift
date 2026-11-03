@testable import IOSKit
import Foundation
import Testing

private struct ScriptedSessions: SessionsProviding {
    let error: Error?

    func sessions() async throws -> [SessionSummary] {
        if let error {
            throw error
        }
        return []
    }
}

@MainActor
private func probed(token: String?, error: Error?) async throws -> Reachability {
    let registry = FakeRegistry()
    let machine = try Machine(id: "m1", name: "Studio", baseURL: #require(URL(string: "https://studio.ts.net:8765")))
    try registry.add(machine, token: token)
    let model = MachinesModel(registry: registry) { _, _ in ScriptedSessions(error: error) }
    model.load()
    await model.probe(machine)
    return model.reachability(of: machine)
}

@MainActor
@Test func tokenlessMachineThatAnswersIsReachable() async throws {
    #expect(try await probed(token: nil, error: nil) == .reachable)
}

@MainActor
@Test func refusedCredentialRequiresPairing() async throws {
    #expect(try await probed(token: "stale", error: APIError.status(code: 401, body: "")) == .pairingRequired)
    #expect(try await probed(token: nil, error: APIError.status(code: 403, body: "")) == .pairingRequired)
}

@MainActor
@Test func serverErrorOrTransportFailureIsUnreachable() async throws {
    #expect(try await probed(token: "tok", error: APIError.status(code: 500, body: "")) == .unreachable)
    #expect(try await probed(token: "tok", error: URLError(.cannotConnectToHost)) == .unreachable)
}
