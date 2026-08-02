import SwiftUI
import WarrantKit

struct SignInView: View {
    @Environment(AppState.self) private var state

    @State private var email = ""
    @State private var sent = false
    @State private var failure: WarrantError?
    @State private var isSending = false

    var body: some View {
        ZStack {
            Ink.card.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 30)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 9) {
                        BrandMark()
                        Text(Brand.name).warrantType(.label).foregroundStyle(Ink.ink)
                    }
                    Text("Approve or deny what your agents are about to do")
                        .warrantType(.verifyHead)
                        .foregroundStyle(Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("And check the evidence afterwards, on this device, without trusting the server that produced it.")
                        .warrantType(.body)
                        .foregroundStyle(Ink.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if state.configuration.isFullyConfigured {
                    form
                } else {
                    unconfigured
                }

                Spacer()

                Text(Brand.claimLine)
                    .warrantType(.bodySmall)
                    .foregroundStyle(Ink.mute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sent {
                Card(border: Ink.green.opacity(0.3), background: Ink.green.opacity(0.06)) {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusLabel(text: "Check your mail", color: Ink.green)
                        Text("We sent a sign-in link to \(email). Open it on this device.")
                            .warrantType(.bodySmall)
                            .foregroundStyle(Ink.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                TextField("you@company.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .warrantType(.body)
                    .padding(16)
                    .background(Ink.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                            .stroke(Ink.line, lineWidth: Metric.hairline)
                    )

                Button(isSending ? "Sending…" : "Send a sign-in link") { send() }
                    .buttonStyle(SolidButtonStyle())
                    .disabled(email.isEmpty || isSending)
            }

            if let failure {
                Text(failure.message)
                    .warrantType(.bodySmall)
                    .foregroundStyle(Ink.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Honest about why there is nothing to sign into, and specific about what is missing.
    private var unconfigured: some View {
        Card(border: Ink.ochre.opacity(0.3), background: Ink.ochre.opacity(0.07)) {
            VStack(alignment: .leading, spacing: 10) {
                StatusLabel(text: "Not connected", color: Ink.ochre)
                Text("No gateway is configured, so \(Brand.name) is running on demo data. The story is complete and the receipts are really signed — you can verify them right here.")
                    .warrantType(.bodySmall)
                    .foregroundStyle(Ink.soft)
                    .fixedSize(horizontal: false, vertical: true)
                Text(state.configuration.missingKeys.joined(separator: " · "))
                    .warrantType(.monoSmall)
                    .foregroundStyle(Ink.mute)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func send() {
        isSending = true
        failure = nil
        Task {
            do {
                try await state.signIn(email: email)
                sent = true
            } catch let error as WarrantError {
                failure = error
            } catch {
                failure = .server
            }
            isSending = false
        }
    }
}
