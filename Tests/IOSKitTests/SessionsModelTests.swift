@testable import IOSKit
import Foundation
import Testing

/// FakeSessions is a scripted SessionsProviding: it returns a fixed roster or throws
/// a scripted error, and counts calls so a pull-to-refresh reload can be asserted —
/// no network involved.
private final class FakeSessions: SessionsProviding, @unchecked Sendable {
    enum Outcome {
        case roster([SessionSummary])
        case failure(Error)
    }

    let outcome: Outcome
    private(set) var calls = 0

    init(_ outcome: Outcome) {
        self.outcome = outcome
    }

    func sessions() async throws -> [SessionSummary] {
        calls += 1
        switch outcome {
        case let .roster(list): return list
        case let .failure(error): throw error
        }
    }
}

private func summary(subject: String, updatedAt: String, status: String = "open") -> SessionSummary {
    SessionSummary(
        subject: subject,
        slug: subject,
        title: subject.capitalized,
        status: status,
        updatedAt: updatedAt,
        revision: 1
    )
}

@MainActor
@Test func refreshLoadsAndSortsNewestFirst() async {
    let older = summary(subject: "alpha", updatedAt: "2026-07-10T10:00:00Z")
    let newer = summary(subject: "beta", updatedAt: "2026-07-10T12:00:00Z")
    let model = SessionsModel(client: FakeSessions(.roster([older, newer])))

    await model.refresh()

    #expect(model.phase == .loaded)
    #expect(model.sessions.map(\.subject) == ["beta", "alpha"])
}

@MainActor
@Test func refreshOnEmptyRosterReportsEmpty() async {
    let model = SessionsModel(client: FakeSessions(.roster([])))

    await model.refresh()

    #expect(model.phase == .empty)
    #expect(model.sessions.isEmpty)
}

@MainActor
@Test func refreshFailureSurfacesStatusCode() async {
    let model = SessionsModel(client: FakeSessions(.failure(APIError.status(code: 500, body: "boom"))))

    await model.refresh()

    guard case let .failed(message) = model.phase else {
        Issue.record("expected failed, got \(model.phase)")
        return
    }
    #expect(message.contains("500"))
}

@MainActor
@Test func refreshIsCalledEachTime() async {
    let client = FakeSessions(.roster([summary(subject: "alpha", updatedAt: "2026-07-10T10:00:00Z")]))
    let model = SessionsModel(client: client)

    await model.refresh()
    await model.refresh()

    #expect(client.calls == 2)
}
