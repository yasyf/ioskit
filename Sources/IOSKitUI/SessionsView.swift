import IOSKit
import SwiftUI

/// SessionsView lists one machine's sessions, newest first, and opens `destination`
/// for a tapped row.
public struct SessionsView<Destination: View>: View {
    let machine: Machine
    let noun: String
    private let destination: (SessionSummary) -> Destination

    @State private var model: SessionsModel

    public init(machine: Machine, client: HTTPClient, noun: String, @ViewBuilder destination: @escaping (SessionSummary) -> Destination) {
        self.machine = machine
        self.noun = noun
        self.destination = destination
        _model = State(initialValue: SessionsModel(client: client))
    }

    public var body: some View {
        content
            .navigationTitle(machine.name)
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.refresh() }
            .refreshable { await model.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Loading \(noun)s…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView(
                "No \(noun.capitalized)s",
                systemImage: "rectangle.on.rectangle.slash",
                description: Text("This machine has no live \(noun)s yet.")
            )
        case let .failed(message):
            ContentUnavailableView {
                Label("Can't Load \(noun.capitalized)s", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.refresh() } }
            }
        case .loaded:
            List(model.sessions) { session in
                NavigationLink {
                    destination(session)
                } label: {
                    SessionRow(session: session)
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.title.isEmpty ? session.slug : session.title)
                    .font(.headline)
                Spacer()
                if session.status != "open" {
                    Text(session.status.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            HStack {
                Text(session.slug)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(relativeTimestamp(session.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
