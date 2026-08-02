import SwiftUI
import WarrantKit

/// The receipt, immediately after a decision.
///
/// The whole claim is that you can check this later without trusting us, so the digest, the
/// previous hash and the signature are on screen the moment the decision lands — not buried
/// three taps away in an audit view nobody opens.
struct SealedView: View {
    let approval: Approval

    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var isDenied: Bool {
        approval.status == .denied || approval.status == .expired
    }

    private var tint: Color {
        switch approval.status {
        case .approvedExecuted: Ink.green
        case .denied, .executionFailed: Ink.red
        default: Ink.ochre
        }
    }

    private var record: ReceiptRecord? {
        approval.receiptSequence.flatMap { sequence in
            state.receipts.first { $0.sequence == sequence }
        } ?? state.receipts.last
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 12) {
                    receiptCard
                    agentNextCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Ink.surface)

            footer
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { appeared = true }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(headline).warrantType(.label).foregroundStyle(tint)
            Spacer()
            Text(approval.shortID).warrantType(.monoSmall).foregroundStyle(Ink.mute)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Ink.card)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.line).frame(height: Metric.hairline) }
    }

    private var receiptCard: some View {
        Card(radius: Metric.panelRadius) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .warrantType(.headline)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(blurb)
                    .warrantType(.bodySmall)
                    .foregroundStyle(Ink.soft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)

                divider

                VStack(alignment: .leading, spacing: 9) {
                    KeyValueRow(key: "decision", value: approval.status.label)
                    if let reason = approval.denialReason {
                        KeyValueRow(key: "reason", value: reason)
                    }
                    KeyValueRow(key: "approver", value: approval.decidedBy ?? state.user?.displayName ?? "—")
                    if let record {
                        KeyValueRow(key: "digest", value: record.hashShort)
                        KeyValueRow(key: "prev hash", value: String(record.previousHash.prefix(38)) + "…")
                        KeyValueRow(key: "sequence", value: String(format: "%02d", record.sequence))
                    }
                    KeyValueRow(key: "executed", value: approval.status == .approvedExecuted ? "true" : "false")
                }

                divider

                Text("Signed · Ed25519").fieldLabel()
                Text(record?.signature ?? "—")
                    .warrantType(.monoSmall)
                    .foregroundStyle(Ink.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.top, 7)

                if let approver = approval.decidedBy {
                    Text("Countersigned by \(approver)")
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.soft)
                        .padding(.top, 11)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    private var agentNextCard: some View {
        Card(radius: Metric.panelRadius) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What the agent did next").fieldLabel()
                Text(agentNext)
                    .warrantType(.body)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Approvals") { state.route = NavigationPath() }
                .buttonStyle(OutlineButtonStyle())
            Button("See receipts") {
                state.route = NavigationPath()
                state.selectedTab = .receipts
            }
            .buttonStyle(SolidButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Ink.card)
        .overlay(alignment: .top) { Rectangle().fill(Ink.line).frame(height: Metric.hairline) }
    }

    private var divider: some View {
        Rectangle().fill(Ink.line).frame(height: Metric.hairline).padding(.vertical, 17)
    }

    // MARK: - Copy

    private var headline: String {
        switch approval.status {
        case .approvedExecuted: "Approved"
        case .denied: "Denied"
        case .expired: "Expired"
        case .alreadyDecided: "Already decided"
        case .executionFailed: "Execution failed"
        case .pending: "Pending"
        }
    }

    private var title: String {
        switch approval.status {
        case .approvedExecuted: "Refund executed once"
        case .denied: "The refund did not happen"
        case .expired: "The request expired unsigned"
        case .alreadyDecided: "Someone answered this first"
        case .executionFailed: "The action failed after you approved it"
        case .pending: approval.actionLine
        }
    }

    private var blurb: String {
        switch approval.status {
        case .approvedExecuted:
            "The executor consumed the one-use approval and moved \(approval.amount.formatted()). A second attempt on it is refused."
        case .denied:
            "\(Brand.name) returned a denial to \(approval.requestedBy). The agent could never reach the credential in the first place."
        case .expired:
            "Nobody signed inside the window, so the action did not happen and the agent has been told."
        case .alreadyDecided:
            "One approval can only be spent once, and this one was already spent on another device."
        case .executionFailed:
            "The approval was valid, but the downstream call did not complete. Nothing was retried automatically."
        case .pending:
            approval.whyReviewing
        }
    }

    private var agentNext: String {
        switch approval.status {
        case .approvedExecuted:
            "“Refund of \(approval.amount.formatted()) issued to \(approval.recipient), reference rf_9041. The customer has been notified.”"
        case .denied, .expired:
            "“Understood — I can't issue this refund. I've opened case ESC-2210 for a human agent and told the customer we'll follow up within one business day.”"
        default:
            "“Waiting on a person before doing anything else.”"
        }
    }
}
