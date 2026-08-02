import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import UserNotifications
import WarrantKit

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showKeyQR = false
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                organization
                publicKey
                notifications
                if state.isDemoMode || state.organization?.isDemo == true { demo }
                NavigationLink { AboutView() } label: {
                    Card {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("About \(Brand.name)").warrantType(.body).foregroundStyle(Ink.ink)
                                Text("What this does, and what it does not claim")
                                    .warrantType(.bodySmall)
                                    .foregroundStyle(Ink.soft)
                            }
                            Spacer()
                            Text("→").warrantType(.body).foregroundStyle(Ink.mute)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)

                Button("Sign out") { Task { await state.signOut() } }
                    .buttonStyle(OutlineButtonStyle(color: Ink.red, border: Color(hex: 0xE6D2CF)))
                    .padding(.top, 6)
            }
            .padding(14)
            .padding(.bottom, 30)
        }
        .background(Ink.surface)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { notificationStatus = await UNUserNotificationAdapter.authorizationState() }
        .sheet(isPresented: $showKeyQR) {
            if let key = state.publicKeyBase64 { PublicKeyQRView(base64: key) }
        }
    }

    private var organization: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                Text("Organization").fieldLabel()
                KeyValueRow(key: "name", value: state.organization?.name ?? "—")
                KeyValueRow(key: "your role", value: state.organization?.role.rawValue ?? "—")
                if let email = state.user?.email {
                    KeyValueRow(key: "signed in", value: email)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The key someone checks your evidence against, so it has to be easy to read aloud and
    /// easy to hand over.
    private var publicKey: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                StatusLabel(text: "Organization public key", color: Ink.green)

                if let key = state.publicKeyBase64 {
                    Text(PublicKeyStore.readable(key))
                        .warrantType(.monoSmall)
                        .foregroundStyle(Ink.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button(copied ? "Copied" : "Copy") {
                            UIPasteboard.general.string = key
                            copied = true
                        }
                        .buttonStyle(.bordered)
                        .tint(Ink.blue)

                        Button("Show as a code") { showKeyQR = true }
                            .buttonStyle(.bordered)
                            .tint(Ink.blue)
                    }
                    .warrantType(.bodySmall)

                    Text("This is the public half. It can check a signature and cannot make one — which is why it is safe to hand to anyone who wants to verify your evidence.")
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.soft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No key stored yet. Load the ledger once and it will be kept here.")
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var notifications: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Notifications").fieldLabel()
                KeyValueRow(key: "status", value: statusText)

                if notificationStatus == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Ink.blue)
                    Text("Without notifications you'll still see approvals when the app is open — nothing is missed silently, it just waits for you.")
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.soft)
                        .fixedSize(horizontal: false, vertical: true)
                } else if notificationStatus == .notDetermined {
                    Button("Allow notifications") {
                        Task {
                            _ = await UNUserNotificationAdapter().requestAuthorization()
                            notificationStatus = await UNUserNotificationAdapter.authorizationState()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Ink.blue)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "allowed"
        case .denied: "turned off"
        default: "not asked yet"
        }
    }

    private var demo: some View {
        Card(border: Ink.blue.opacity(0.25), background: Ink.blue.opacity(0.06)) {
            VStack(alignment: .leading, spacing: 10) {
                StatusLabel(text: "Demo", color: Ink.blue)
                Button("Reset the demo") { Task { await state.resetDemo() } }
                    .buttonStyle(.bordered)
                    .tint(Ink.blue)
                Text("Puts the three-act story back to the start. The receipts are regenerated and really re-signed.")
                    .warrantType(.bodySmall)
                    .foregroundStyle(Ink.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PublicKeyQRView: View {
    let base64: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let image = Self.qr(from: base64) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .padding(18)
                        .background(Ink.card)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Ink.line, lineWidth: Metric.hairline)
                        )
                }
                Text(PublicKeyStore.readable(base64))
                    .warrantType(.monoSmall)
                    .foregroundStyle(Ink.mute)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Ink.card)
            .navigationTitle("Public key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Ink.blue)
                }
            }
        }
    }

    static func qr(from text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(Brand.tagline)
                    .warrantType(.headline)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusLabel(text: "What we claim", color: Ink.green)
                        Text(Brand.claimLine)
                            .warrantType(.body)
                            .foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What we don't claim").fieldLabel()
                        Text("""
                        This is tamper evident, not tamper proof. Records can be changed — what they cannot do is change without verification failing on a device that never trusted the server.

                        It also cannot prove what an agent did not do. It proves what was requested, which rule applied, who answered, and what happened next.
                        """)
                            .warrantType(.body)
                            .foregroundStyle(Ink.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("\(Brand.name) is a working title.")
                    .warrantType(.monoSmall)
                    .foregroundStyle(Ink.mute)
            }
            .padding(16)
        }
        .background(Ink.surface)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
