import SwiftUI
import WarrantKit

/// What a human may move, and beneath it what nobody may move from any device.
struct PolicyView: View {
    @Environment(AppState.self) private var state
    @State private var testAmount: Double = 2_400

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: "Limits",
                subtitle: state.policy.map { "\($0.resource) · v\($0.version) · applies to the next request" } ?? "—"
            )

            ScrollView {
                if let policy = state.policy {
                    VStack(spacing: 12) {
                        envelope(policy)
                        tester(policy)
                        dials(policy)
                        locked
                        if let role = state.organization?.role, !role.canEditPolicy {
                            Text(role.policyReadOnlyReason)
                                .warrantType(.bodySmall)
                                .foregroundStyle(Ink.soft)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(14)
                    .padding(.bottom, 30)
                } else {
                    Text("No policy loaded yet.")
                        .warrantType(.body)
                        .foregroundStyle(Ink.soft)
                        .padding(40)
                }
            }
            .background(Ink.surface)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task { await state.loadPolicy() }
    }

    private func envelope(_ policy: Policy) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                EnvelopeBar(
                    autoLimitMinor: policy.autoLimit.minorUnits,
                    blockLimitMinor: policy.blockLimit.minorUnits,
                    showMarkerLabel: false
                )
                FlowLegend(policy: policy)
            }
            .padding(18)
        }
    }

    /// Shows where an amount lands. It decides nothing: the gateway owns policy, and it
    /// decides the same way whether or not this screen is open.
    private func tester(_ policy: Policy) -> some View {
        let amount = Money(minorUnits: Int(testAmount) * 100, currencyCode: policy.autoLimit.currencyCode)
        let outcome = policy.preview(for: amount)

        return Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("What would happen").fieldLabel()
                    Spacer()
                    Text(outcome.rawValue)
                        .warrantType(.label)
                        .foregroundStyle(color(for: outcome))
                }

                Text(amount.formatted())
                    .warrantType(.amountRow)
                    .foregroundStyle(Ink.ink)

                EnvelopeBar(
                    autoLimitMinor: policy.autoLimit.minorUnits,
                    blockLimitMinor: policy.blockLimit.minorUnits,
                    markerMinor: amount.minorUnits
                )

                Slider(value: $testAmount, in: 0...10_000, step: 50)
                    .tint(color(for: outcome))
                    .accessibilityLabel("Test amount")
                    .accessibilityValue(amount.formatted())

                Text(explanation(outcome, policy: policy))
                    .warrantType(.bodySmall)
                    .foregroundStyle(Ink.soft)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Illustration only. The gateway decides.")
                    .warrantType(.monoSmall)
                    .foregroundStyle(Ink.mute)
            }
            .padding(18)
        }
    }

    private func dials(_ policy: Policy) -> some View {
        VStack(spacing: 12) {
            Dial(name: "Automatic limit", value: policy.autoLimit.formatted(), color: Ink.green,
                 blurb: "At or below this the agent proceeds alone and nobody is paged.")
            Dial(name: "Hard stop", value: policy.blockLimit.formatted(), color: Ink.red,
                 blurb: "Above this it is blocked outright. No human is offered the chance to approve.")
            Dial(name: "Request lifetime", value: "\(policy.expirySeconds)s", color: Ink.ochre,
                 blurb: "After this the request voids itself and is recorded as denied.")
        }
    }

    private var locked: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Fixed in code — no device can change these").fieldLabel()
                ForEach(Self.lockedRules, id: \.self) { rule in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(Ink.green).frame(width: 6, height: 6).padding(.top, 6)
                        Text(rule)
                            .warrantType(.bodySmall)
                            .foregroundStyle(Ink.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let lockedRules = [
        "The agent cannot import, hold, or reach the provider credential. Only the executor can.",
        "Any failure in identity, policy, signing, or digest checking means no execution. Never a default allow.",
        "An approval binds to one exact digest and is spendable once.",
        "No model is ever asked whether an action is safe."
    ]

    private func explanation(_ outcome: PolicyOutcome, policy: Policy) -> String {
        switch outcome {
        case .allow: "At or below \(policy.autoLimit.formatted()) the agent proceeds alone and nobody is interrupted."
        case .review: "Between \(policy.autoLimit.formatted()) and \(policy.blockLimit.formatted()) it waits for a person for \(policy.expirySeconds) seconds."
        case .block: "Above \(policy.blockLimit.formatted()) it is refused outright. Nobody is offered the chance to approve it."
        }
    }

    private func color(for outcome: PolicyOutcome) -> Color {
        switch outcome {
        case .allow: Ink.green
        case .review: Ink.ochre
        case .block: Ink.red
        }
    }
}

private struct FlowLegend: View {
    let policy: Policy

    var body: some View {
        HStack(spacing: 16) {
            item(Ink.green, "Auto up to \(policy.autoLimit.formatted())")
            item(Ink.ochreBand, "Ask a human")
            item(Ink.red, "Blocked past \(policy.blockLimit.formatted())")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func item(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).warrantType(.bodySmall).foregroundStyle(Ink.soft)
        }
    }
}

private struct Dial: View {
    let name: String
    let value: String
    let color: Color
    let blurb: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(name).warrantType(.body).foregroundStyle(Ink.ink)
                    Spacer()
                    Text(value).warrantType(.headline).foregroundStyle(color)
                }
                Text(blurb)
                    .warrantType(.bodySmall)
                    .foregroundStyle(Ink.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(value). \(blurb)")
    }
}
