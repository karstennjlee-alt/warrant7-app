import SwiftUI
import WarrantKit

struct SignInView: View {
    @Environment(AppState.self) private var state

    @State private var email = ""
    @State private var password = ""
    @State private var sent = false
    @State private var failure: WarrantError?
    @State private var isSending = false
    /// Password by default. The magic link needs SMTP and a redirect allowlist pointing at
    /// something this handset can open; until both are set it is a sign-in that never arrives.
    @State private var useMagicLink = false

    var body: some View {
        ZStack {
            Ink.card.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 30)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        BrandMark(size: 52)
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
                field {
                    TextField("you@company.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if !useMagicLink {
                    field {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    }
                }

                Button(buttonTitle) { submit() }
                    .buttonStyle(SolidButtonStyle())
                    .disabled(email.isEmpty || (!useMagicLink && password.isEmpty) || isSending)

                Button(useMagicLink ? "Use a password instead" : "Email me a link instead") {
                    useMagicLink.toggle()
                    failure = nil
                }
                .buttonStyle(.plain)
                .warrantType(.bodySmall)
                .foregroundStyle(Ink.blue)
                .padding(.top, 2)
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

    private var buttonTitle: String {
        if isSending { return useMagicLink ? "Sending…" : "Signing in…" }
        return useMagicLink ? "Send a sign-in link" : "Sign in"
    }

    @ViewBuilder
    private func field<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .warrantType(.body)
            .padding(16)
            .background(Ink.surface)
            .clipShape(RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                    .stroke(Ink.line, lineWidth: Metric.hairline)
            )
    }

    private func submit() {
        isSending = true
        failure = nil
        Task {
            do {
                if useMagicLink {
                    try await state.signIn(email: email)
                    sent = true
                } else {
                    try await state.signIn(email: email, password: password)
                }
            } catch let error as WarrantError {
                failure = error
            } catch {
                // Supabase says "Invalid login credentials"; the person needs the plain version.
                failure = .signInFailed
            }
            isSending = false
        }
    }
}
