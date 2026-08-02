import SwiftUI
import UIKit
import WarrantKit

/// The approval card. Everything else in this app is supporting material.
///
/// Order is the argument: the amount first, then how long you have, then the rule that paused
/// it, then the agent's own words, then the raw text it read — so the injection is visible to a
/// human eye rather than only to a filter — and only then the two ways out.
struct ApprovalCardView: View {
    let approval: Approval

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var settled: Approval?
    @State private var isSubmitting = false
    @State private var showBinding = true
    @State private var digestRevealed = false
    @State private var failure: WarrantError?
    @State private var showDenySheet = false
    @State private var confirmPocketTap = false
    @State private var appearedAt = Date()
    @State private var hasExpiredLocally = false
    @State private var slideID = UUID()

    private var current: Approval { settled ?? approval }
    private var isExpired: Bool { hasExpiredLocally && !current.status.isTerminal }

    var body: some View {
        Group {
            if let settled, settled.status.isTerminal {
                SealedView(approval: settled)
            } else {
                card
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Approval request").warrantType(.label).foregroundStyle(Ink.ink)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Text(current.shortID).warrantType(.monoSmall).foregroundStyle(Ink.mute)
            }
        }
        .onAppear { appearedAt = Date() }
        .sheet(isPresented: $showDenySheet) {
            DenyView(approval: current) { decided in complete(with: decided) }
        }
        .alert("Deny this now?", isPresented: $confirmPocketTap) {
            Button("Deny", role: .destructive) { showDenySheet = true }
            Button("Keep reading", role: .cancel) {}
        } message: {
            Text("You've only just opened this. Denying is safe and nothing executes, but the agent stops here.")
        }
    }

    // MARK: - Card

    private var card: some View {
        ZStack(alignment: .bottom) {
            Ink.card.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headline
                    whyAsked
                    agentSays
                    ticket
                    binding
                    if let failure { failureNote(failure) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, isExpired ? 170 : 240)
            }

            if isExpired {
                expiredBar
            } else {
                actionBar
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Refund to \(current.recipient)")
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.soft)
                    // The largest thing on the screen, by a wide margin.
                    Text(current.amount.formatted())
                        .warrantType(.amountHuge)
                        .foregroundStyle(Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(current.amount.spelledOut())
                    Text([current.reference, "requested \(current.createdAt.formatted(date: .omitted, time: .shortened))"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.soft)
                }
                Spacer(minLength: 0)
                TimerRing(expiresAt: current.expiresAt, createdAt: current.createdAt)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = current.secondsRemaining(at: context.date)
                Text(remaining == 0
                     ? "The request expired unsigned."
                     : "When this hits zero the request voids itself and is recorded as denied. Silence is a refusal.")
                    .warrantType(.bodySmall)
                    .foregroundStyle(CountdownTone.color(secondsRemaining: remaining))
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: remaining <= 0) { _, expired in
                        // On device, before any tap can race into a window the gateway may
                        // still believe is open.
                        if expired { hasExpiredLocally = true }
                    }
            }

            if isExpired {
                Pill(text: "Expired — recorded as denied", color: Ink.red)
            }
        }
    }

    private var whyAsked: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                StatusLabel(text: "Why you were asked", color: Ink.ochre)

                if let policy = state.policy {
                    EnvelopeBar(
                        autoLimitMinor: policy.autoLimit.minorUnits,
                        blockLimitMinor: policy.blockLimit.minorUnits,
                        markerMinor: current.amount.minorUnits
                    )
                    Text("Above the \(policy.autoLimit.formatted()) automatic limit, below the \(policy.blockLimit.formatted()) hard stop. Deterministic policy paused it — no model was asked.")
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.soft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(current.whyReviewing)
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var agentSays: some View {
        if let statement = current.agentStatement {
            VStack(alignment: .leading, spacing: 10) {
                Text("What the agent says").fieldLabel()
                Text("“\(statement)”")
                    .warrantType(.body)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text([current.requestedBy, current.reference].compactMap { $0 }.joined(separator: " · "))
                    .warrantType(.monoSmall)
                    .foregroundStyle(Ink.mute)
            }
        }
    }

    /// The raw source, with the injected instruction called out.
    ///
    /// Showing it is the point. A filter that silently strips this would leave the person
    /// approving a number with no idea where it came from.
    @ViewBuilder
    private var ticket: some View {
        if let source = current.sourceText {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("The text it read").fieldLabel()
                    Spacer()
                    Pill(text: "untrusted text", color: Ink.red)
                }

                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(paragraphs(of: source).enumerated()), id: \.offset) { _, paragraph in
                            if paragraph == current.sourceInjection {
                                Text(paragraph)
                                    .warrantType(.mono)
                                    .foregroundStyle(Ink.broken)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 11)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Ink.red.opacity(0.09))
                                    .clipShape(RoundedRectangle(cornerRadius: Metric.fieldRadius, style: .continuous))
                            } else {
                                Text(paragraph)
                                    .warrantType(.body)
                                    .foregroundStyle(Ink.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(15)
                }

                Text("The highlighted line came from the customer, not from your systems. It is an instruction wearing a system voice.")
                    .warrantType(.bodySmall)
                    .foregroundStyle(Ink.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func paragraphs(of text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var binding: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { showBinding.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("What your signature binds to").fieldLabel()
                    Text(showBinding ? "Hide" : "Show")
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.blue)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if showBinding {
                Panel {
                    VStack(alignment: .leading, spacing: 9) {
                        KeyValueRow(key: "resource", value: current.resource)
                        KeyValueRow(key: "amount", value: "\(current.amount.minorUnits) \(current.amount.currencyCode) (minor units)")
                        KeyValueRow(key: "recipient", value: current.recipient)
                        KeyValueRow(key: "impact", value: current.impact)
                        KeyValueRow(key: "reversibility", value: current.reversibility)
                        KeyValueRow(key: "expires", value: WarrantJSON.string(from: current.expiresAt))

                        // Truncated so the card stays readable; tappable so it can be compared
                        // against the console in full. You are approving one action, not a kind.
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy) { digestRevealed.toggle() }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                KeyValueRow(
                                    key: "digest",
                                    value: digestRevealed ? current.boundDigest : current.boundDigestShort
                                )
                                Text(digestRevealed ? "Tap to shorten" : "Tap to reveal in full")
                                    .warrantType(.monoSmall)
                                    .foregroundStyle(Ink.blue)
                                    .padding(.leading, 104)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Bound digest, \(digestRevealed ? "shown in full" : "truncated"). Double tap to toggle.")
                    }
                    .padding(15)
                }

                // Text concatenation only composes when every modifier returns Text, so the
                // code name is its own run rather than a styled span inside the sentence.
                (
                    Text("Change any of it after you sign — amount, recipient, expiry — and execution is refused with ")
                        .font(.warrant(.bodySmall))
                        .foregroundColor(Ink.soft)
                    + Text("DIGEST_MISMATCH")
                        .font(.warrant(.monoSmall))
                        .foregroundColor(Ink.red)
                    + Text(".")
                        .font(.warrant(.bodySmall))
                        .foregroundColor(Ink.soft)
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func failureNote(_ error: WarrantError) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                StatusLabel(text: "Nothing was sent", color: Ink.red)
                Text(error.message)
                    .warrantType(.bodySmall)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }

    // MARK: - Action bars

    private var actionBar: some View {
        VStack(spacing: 10) {
            SlideToApprove(isEnabled: !isSubmitting) { approveSlid() }
                .id(slideID)

            Button("Deny") { denyTapped() }
                .buttonStyle(OutlineButtonStyle(color: Ink.red, border: Ink.brokenLine))
                .disabled(isSubmitting)
                .accessibilityLabel("Deny \(current.amount.spelledOut()) to \(current.recipient)")

            Text("deny is one tap · approving takes a deliberate slide")
                .warrantType(.monoTiny)
                .foregroundStyle(Ink.mute)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Rectangle().fill(Ink.line).frame(height: Metric.hairline) }
    }

    private var expiredBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Silence is a refusal. The refund did not happen and the agent has escalated.")
                .warrantType(.bodySmall)
                .foregroundStyle(Ink.soft)
                .fixedSize(horizontal: false, vertical: true)
            Button("Back to approvals") { dismiss() }
                .buttonStyle(SolidButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card)
        .overlay(alignment: .top) { Rectangle().fill(Ink.line).frame(height: Metric.hairline) }
    }

    // MARK: - Decisions

    private func denyTapped() {
        guard !isSubmitting else { return }
        // Pocket-tap guard, and nothing more: only above the automatic limit, and only in the
        // first three seconds on screen.
        let isLarge = (state.policy.map { current.amount.minorUnits > $0.autoLimit.minorUnits }) ?? false
        if isLarge, Date().timeIntervalSince(appearedAt) < 3 {
            confirmPocketTap = true
        } else {
            showDenySheet = true
        }
    }

    private func approveSlid() {
        guard !isSubmitting else { return }
        isSubmitting = true
        failure = nil

        Task {
            // The system prompt carries the real amount and the real recipient. It is the last
            // honest checkpoint before money moves, and a vaguer one would make the card a lie.
            switch await state.biometrics.authenticate(reason: BiometricGate.reason(for: current)) {
            case .cancelled:
                resetSlide()
                return
            case .failed(let error):
                failure = error
                resetSlide()
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            case .authenticated:
                break
            }

            do {
                if let decided = try await state.coordinator.submit(.approve, for: current) {
                    complete(with: decided)
                } else {
                    resetSlide()   // a second attempt that was correctly dropped
                }
            } catch let error as WarrantError {
                failure = error
                if error == .locallyExpired { hasExpiredLocally = true }
                resetSlide()
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } catch {
                failure = .server
                resetSlide()
            }
        }
    }

    private func resetSlide() {
        isSubmitting = false
        slideID = UUID()
    }

    private func complete(with decided: Approval) {
        settled = decided
        isSubmitting = false
        state.record(decision: decided)
        UINotificationFeedbackGenerator()
            .notificationOccurred(decided.status == .executionFailed ? .error : .success)
        Task {
            await LiveActivityController.end(approvalID: decided.id, status: decided.status)
            await UNUserNotificationAdapter().cancel(id: decided.id)
        }
    }
}
