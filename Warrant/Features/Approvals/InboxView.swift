import SwiftUI
import WarrantKit

/// The queue. Pending on top, settled beneath.
///
/// Most days this is empty, and that is the product working rather than the product broken —
/// so the empty state says so instead of apologising.
struct InboxView: View {
    var isSidebar = false

    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        VStack(spacing: 0) {
            ScreenHeader(title: "Approvals", subtitle: summary) {
                HStack(spacing: 10) {
                    Text(state.organization.map { $0.role.rawValue.lowercased() } ?? "")
                        .warrantType(.monoSmall)
                        .foregroundStyle(Ink.mute)
                    OverflowLinks()
                }
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if state.isOffline { strip(state.offlineStrip, color: Ink.ochre) }
                    if state.isDemoMode {
                        strip("DEMO DATA · SIGNED AND VERIFIABLE ON THIS DEVICE", color: Ink.blue)
                    }

                    if state.approvals.isEmpty && state.recentDecisions.isEmpty {
                        emptyState
                    }

                    ForEach(state.approvals) { approval in
                        NavigationLink(value: approval.id) {
                            PendingRow(approval: approval)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(state.recentDecisions) { approval in
                        NavigationLink(value: approval.id) {
                            SettledRow(approval: approval)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .padding(.bottom, 30)
            }
            .background(Ink.surface)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: String.self) { id in
            if let approval = state.approval(id: id) {
                ApprovalCardView(approval: approval)
            } else {
                MissingApprovalView()
            }
        }
        .refreshable { await state.refreshApprovals() }
        .onChange(of: state.presentedApprovalID) { _, id in
            guard let id, !isSidebar else { return }
            state.route.append(id)
            state.presentedApprovalID = nil
        }
        .task(id: state.approvals.map(\.id)) {
            await LiveActivityController.reconcile(
                pending: state.approvals,
                orgName: state.organization?.name ?? Brand.name
            )
        }
    }

    private var summary: String {
        if state.approvals.isEmpty {
            return state.recentDecisions.isEmpty
                ? "Nothing waiting on you"
                : "All settled · nothing waiting on you"
        }
        return state.approvals.count == 1
            ? "1 request waiting on you"
            : "\(state.approvals.count) requests waiting on you"
    }

    private func strip(_ text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).warrantType(.monoSmall).foregroundStyle(color)
            Spacer()
        }
        .padding(10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Metric.rowRadius, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Ink.fill)
                .frame(width: 44, height: 44)
            Text("Nothing needs you")
                .warrantType(.title)
                .foregroundStyle(Ink.ink)
                .padding(.top, 6)
            Text("Agents are working inside the automatic limit. You only hear from us when they step outside it.")
                .warrantType(.body)
                .foregroundStyle(Ink.soft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 100)
    }
}

private struct PendingRow: View {
    let approval: Approval

    var body: some View {
        Card(border: Color(hex: 0xD8DCE0)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    StatusLabel(text: "Needs you", color: Ink.ochre)
                    Spacer()
                    Text(approval.id.uppercased())
                        .warrantType(.monoSmall)
                        .foregroundStyle(Ink.mute)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(approval.amount.formatted())
                        .warrantType(.amountRow)
                        .foregroundStyle(Ink.ink)
                    Text("to \(approval.recipient)")
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.soft)
                }
                .padding(.top, 11)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = approval.secondsRemaining(at: context.date)
                    Text("Above the automatic limit · \(CountdownText.format(remaining)) left")
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.soft)
                }
                .padding(.top, 7)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Waiting on you. \(approval.actionLine).")
    }
}

private struct SettledRow: View {
    let approval: Approval

    private var tint: Color {
        switch approval.status {
        case .approvedExecuted: Ink.green
        case .denied, .executionFailed: Ink.red
        default: Ink.ochre
        }
    }

    private var line: String {
        switch approval.status {
        case .approvedExecuted: "Countersigned by you · approval spent"
        case .denied: "Reason: \(approval.denialReason ?? "none given")"
        case .expired: "Nobody signed in time · recorded as a denial"
        case .alreadyDecided: "Answered on another device"
        case .executionFailed: "Approved, but the downstream call did not complete"
        case .pending: approval.whyReviewing
        }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    StatusLabel(text: approval.status.label.capitalized, color: tint)
                    Spacer()
                    Text(approval.id.uppercased())
                        .warrantType(.monoSmall)
                        .foregroundStyle(Ink.mute)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(approval.amount.formatted())
                        .warrantType(.amountRow)
                        .foregroundStyle(Ink.soft)
                    Text("to \(approval.recipient)")
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.soft)
                }
                .padding(.top, 11)

                Text(line)
                    .warrantType(.bodySmall)
                    .foregroundStyle(Ink.soft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A notification can arrive for something that no longer exists. That is a sentence, not an
/// empty screen and not an error dialog.
struct MissingApprovalView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("That request isn't here anymore.")
                .warrantType(.title)
                .foregroundStyle(Ink.ink)
            Text("It was decided, expired, or withdrawn. Nothing was executed by opening this.")
                .warrantType(.body)
                .foregroundStyle(Ink.soft)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.surface)
    }
}
