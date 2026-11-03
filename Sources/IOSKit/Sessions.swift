import Foundation
import Observation

/// SessionSummary is one row of GET /api/sessions: the artifact's subject, its URL
/// slug, title, open/closed status, last-touched timestamp (RFC 3339), and current
/// revision.
public struct SessionSummary: Decodable, Equatable, Hashable, Sendable, Identifiable {
    public let subject: String
    public let slug: String
    public let title: String
    public let status: String
    public let updatedAt: String
    public let revision: Int

    public var id: String {
        subject
    }

    public init(subject: String, slug: String, title: String, status: String, updatedAt: String, revision: Int) {
        self.subject = subject
        self.slug = slug
        self.title = title
        self.status = status
        self.updatedAt = updatedAt
        self.revision = revision
    }
}

/// SessionsProviding is the one call a session list needs from the network: the
/// daemon's roster of live artifacts. HTTPClient is the production conformer; tests
/// inject a fake so the view model runs without a socket.
public protocol SessionsProviding: Sendable {
    func sessions() async throws -> [SessionSummary]
}

extension HTTPClient: SessionsProviding {}

/// SessionsModel loads one machine's roster and exposes it as a phase the view
/// renders. Refresh sorts newest-first and maps failures to a display string.
@MainActor
@Observable
public final class SessionsModel {
    /// Phase is the load state the list renders: the first fetch shows a spinner,
    /// an empty roster its own placeholder, a failure a retry affordance.
    public enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    public private(set) var sessions: [SessionSummary] = []

    private let client: any SessionsProviding

    public init(client: any SessionsProviding) {
        self.client = client
    }

    /// refresh fetches the roster, keeping the prior list visible while a pull-to-
    /// refresh reload is in flight so the rows don't flash empty.
    public func refresh() async {
        if sessions.isEmpty {
            phase = .loading
        }
        do {
            let fetched = try await client.sessions()
            sessions = fetched
                .map { (session: $0, date: parseTimestamp($0.updatedAt) ?? .distantPast) }
                .sorted { $0.date > $1.date }
                .map(\.session)
            phase = sessions.isEmpty ? .empty : .loaded
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        if case let APIError.status(code, _) = error {
            return "The machine returned an error (\(code))."
        }
        return "Couldn't reach this machine."
    }
}

/// parseTimestamp decodes an RFC 3339 instant, tolerating the fractional-seconds
/// the daemon may or may not include.
public func parseTimestamp(_ raw: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: raw) {
        return date
    }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: raw)
}

/// relativeTimestamp renders an RFC 3339 instant as a relative phrase ("3m ago"),
/// falling back to the raw string when it doesn't parse.
public func relativeTimestamp(_ raw: String, relativeTo now: Date = Date()) -> String {
    guard let date = parseTimestamp(raw) else { return raw }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: now)
}
