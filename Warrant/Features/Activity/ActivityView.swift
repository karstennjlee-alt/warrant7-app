import SwiftUI
import WarrantKit

/// What the agent did, in plain sentences.
///
/// Never hidden model reasoning, never a credential, in any state including errors. This feed
/// is read by people deciding whether to trust the system.
struct ActivityView: View {
    @Environment(AppState.self) private var state
    @State private var expanded: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if state.activity.isEmpty {
                    Text("Nothing yet. Steps appear here as your agents work.")
                        .warrantType(.body)
                        .foregroundStyle(Ink.soft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 70)
                } else {
                    ForEach(groups, id: \.requestID) { group in
                        Card {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Text("Request").fieldLabel()
                                    Spacer()
                                    Text(group.requestID.uppercased())
                                        .warrantType(.monoSmall)
                                        .foregroundStyle(Ink.mute)
                                }
                                .padding(.horizontal, 15)
                                .padding(.top, 14)
                                .padding(.bottom, 10)

                                ForEach(group.events) { event in
                                    EventRow(event: event)
                                }

                                Button {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        expanded = expanded == group.requestID ? nil : group.requestID
                                    }
                                } label: {
                                    HStack {
                                        Text(expanded == group.requestID ? "Hide the pass" : "Show the pass")
                                            .warrantType(.bodySmall)
                                            .foregroundStyle(Ink.blue)
                                        Spacer()
                                    }
                                    .padding(15)
                                }
                                .buttonStyle(.plain)

                                if expanded == group.requestID, let pass = hallPass(for: group) {
                                    HallPassView(pass: pass)
                                        .padding(.horizontal, 15)
                                        .padding(.bottom, 15)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(Ink.surface)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await state.loadActivity() }
        .task { await state.loadActivity() }
    }

    private struct Group {
        let requestID: String
        let events: [ActionEvent]
    }

    private var groups: [Group] {
        Dictionary(grouping: state.activity, by: \.requestID)
            .map { Group(requestID: $0.key, events: $0.value.sorted { $0.timestamp < $1.timestamp }) }
            .sorted { ($0.events.last?.timestamp ?? .distantPast) > ($1.events.last?.timestamp ?? .distantPast) }
    }

    private func hallPass(for group: Group) -> HallPass? {
        guard let last = group.events.last(where: { $0.amount != nil }) ?? group.events.last else { return nil }
        let approval = state.approval(id: group.requestID)
        return HallPass(
            passNumber: group.requestID.uppercased(),
            bearer: last.actor,
            permitted: approval?.resource ?? "refund.create",
            destination: approval?.recipient ?? "—",
            amount: last.amount ?? Money(minorUnits: 0),
            validUntil: approval?.expiresAt ?? last.timestamp,
            binding: approval?.boundDigestShort ?? "—"
        )
    }
}

private struct EventRow: View {
    let event: ActionEvent

    private var tint: Color {
        switch event.kind {
        case .allowed, .executed: Ink.green
        case .blocked, .denied, .failed: Ink.red
        case .review: Ink.ochre
        case .requested, .expired: Ink.mute
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                .warrantType(.monoSmall)
                .foregroundStyle(Ink.mute)
                .frame(width: 68, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(event.line)
                    .warrantType(.body)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                StatusLabel(text: event.kind.rawValue, color: tint, mono: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
    }
}

/// The hall pass itself: who, what, where, how much, until when, bound to what.
private struct HallPassView: View {
    let pass: HallPass

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 9) {
                Text("Hall pass").fieldLabel()
                KeyValueRow(key: "pass no.", value: pass.passNumber)
                KeyValueRow(key: "bearer", value: pass.bearer)
                KeyValueRow(key: "permitted", value: pass.permitted)
                KeyValueRow(key: "destination", value: pass.destination)
                KeyValueRow(key: "amount", value: pass.amount.formatted())
                KeyValueRow(key: "valid until", value: WarrantJSON.string(from: pass.validUntil))
                KeyValueRow(key: "binding", value: pass.binding)
            }
            .padding(15)
        }
    }
}
