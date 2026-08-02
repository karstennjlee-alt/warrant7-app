import SwiftUI
import WarrantKit

/// Refusal, recorded.
///
/// A denial is a first-class signed event with a reason the agent can act on — not the absence
/// of an approval. No biometrics here, on purpose: the safe action stays the fast one.
struct DenyView: View {
    let approval: Approval
    let onSettled: (Approval) -> Void

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var reason: DenialReason?
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var failure: WarrantError?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    (
                        Text("Refusing ")
                            .font(.warrant(.body))
                            .foregroundColor(Ink.soft)
                        + Text(approval.amount.formatted())
                            .font(.warrant(.body))
                            .foregroundColor(Ink.ink)
                        + Text(" to \(approval.recipient). Your reason goes into the receipt and back to the agent.")
                            .font(.warrant(.body))
                            .foregroundColor(Ink.soft)
                    )
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 8) {
                        ForEach(DenialReason.allCases, id: \.self) { option in
                            Button {
                                reason = option
                            } label: {
                                HStack(spacing: 11) {
                                    RadioMark(selected: reason == option)
                                    Text(option.label)
                                        .warrantType(.body)
                                        .foregroundStyle(Ink.ink)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(15)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(reason == option ? Ink.surface : Ink.card)
                                .clipShape(RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                                        .stroke(reason == option ? Ink.ink : Ink.line, lineWidth: Metric.hairline)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(reason == option ? [.isSelected, .isButton] : .isButton)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note to the agent — optional").fieldLabel()
                        TextEditor(text: $note)
                            .warrantType(.body)
                            .frame(minHeight: 84)
                            .scrollContentBackground(.hidden)
                            .padding(9)
                            .background(Ink.card)
                            .clipShape(RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                                    .stroke(Ink.line, lineWidth: Metric.hairline)
                            )
                            .overlay(alignment: .topLeading) {
                                if note.isEmpty {
                                    Text("e.g. Call the customer before any refund above the order value.")
                                        .warrantType(.body)
                                        .foregroundStyle(Ink.mute)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 17)
                                        .allowsHitTesting(false)
                                }
                            }
                    }

                    if let failure {
                        Text(failure.message)
                            .warrantType(.bodySmall)
                            .foregroundStyle(Ink.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
            .background(Ink.card)
            .navigationTitle("Deny this request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }.foregroundStyle(Ink.ink)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(reason == nil ? "Pick a reason first" : "Deny and sign") { submit() }
                    .buttonStyle(SolidButtonStyle(
                        color: reason == nil ? Ink.fill : Ink.red,
                        foreground: reason == nil ? Ink.mute : .white
                    ))
                    .disabled(reason == nil || isSubmitting)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(Ink.card)
                    .overlay(alignment: .top) { Rectangle().fill(Ink.line).frame(height: Metric.hairline) }
            }
        }
    }

    private func submit() {
        guard let reason, !isSubmitting else { return }
        isSubmitting = true
        failure = nil

        Task {
            do {
                if let decided = try await state.coordinator.submit(
                    .deny(reason: reason, note: note.isEmpty ? nil : note), for: approval
                ) {
                    dismiss()
                    onSettled(decided)
                } else {
                    isSubmitting = false
                }
            } catch let error as WarrantError {
                failure = error
                isSubmitting = false
            } catch {
                failure = .server
                isSubmitting = false
            }
        }
    }
}

private struct RadioMark: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(selected ? Ink.red : Color(hex: 0xD6DAD5), lineWidth: 1.5)
            if selected {
                Circle().fill(Ink.red).padding(4)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}
