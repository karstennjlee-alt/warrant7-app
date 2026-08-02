import SwiftUI
import UniformTypeIdentifiers
import WarrantKit

/// The offline proof, and the reason the phone is more than a companion app.
///
/// Works signed out, works in airplane mode, holds no database handle and no credential. Hand
/// someone the device, let them scan a bundle off a laptop, and watch it check against a key
/// they can compare with their own eyes.
struct VerifyView: View {
    @Environment(AppState.self) private var state
    @State private var runner = VerificationRunner()
    @State private var showFileImporter = false
    @State private var showScanner = false
    @State private var showReport = false
    @State private var keyOverride = ""
    @State private var showKeyField = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: "Verify",
                subtitle: "Import a bundle and a public key. This device does the checking."
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    offlineNote
                    importOptions
                    keySection

                    if let failure = runner.failure {
                        Text(failure)
                            .warrantType(.bodySmall)
                            .foregroundStyle(Ink.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }

                    Text(Brand.claimLine)
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.mute)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                }
                .padding(14)
                .padding(.bottom, 30)
            }
            .background(Ink.surface)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showReport) {
            VerifyReportView(runner: runner)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json, .plainText]) { result in
            switch result {
            case .success(let url): loadFile(url)
            case .failure: runner.fail("Couldn't open that file.")
            }
        }
        .sheet(isPresented: $showScanner) {
            BundleScannerView { text in
                showScanner = false
                load(Data(text.utf8))
            }
        }
    }

    /// The affordance that makes the point: turn the network off first, on purpose.
    private var offlineNote: some View {
        Card(border: Ink.blue.opacity(0.25), background: Ink.blue.opacity(0.06)) {
            VStack(alignment: .leading, spacing: 8) {
                StatusLabel(text: "Verify offline", color: Ink.blue)
                Text("Put this phone in airplane mode before you tap. Nothing here needs a network, and watching it work without one is the whole claim.")
                    .warrantType(.bodySmall)
                    .foregroundStyle(Ink.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var importOptions: some View {
        VStack(spacing: 10) {
            ImportRow(title: "Scan a bundle", detail: "Point the camera at a code on a screen") {
                showScanner = true
            }
            ImportRow(title: "Choose a file", detail: "From Files, iCloud Drive, or an AirDrop you accepted") {
                showFileImporter = true
            }
            ImportRow(title: "Paste from the clipboard", detail: "If you copied the bundle JSON") {
                guard let text = UIPasteboard.general.string else {
                    runner.fail("There's nothing on the clipboard to check.")
                    return
                }
                load(Data(text.utf8))
            }
            ImportRow(title: "This organization's receipts", detail: "The bundle already cached on this device") {
                Task {
                    guard let bundle = await state.bundle() else {
                        runner.fail("There's nothing cached to check yet.")
                        return
                    }
                    await verify(bundle)
                }
            }
        }
    }

    private var keySection: some View {
        Card {
            DisclosureGroup(isExpanded: $showKeyField) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste a public key to check against, instead of the one inside the bundle.")
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.soft)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("base64 Ed25519 public key", text: $keyOverride)
                        .warrantType(.monoSmall)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Ink.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Metric.fieldRadius, style: .continuous))
                    if let stored = (try? PublicKeyStore().base64()) ?? nil {
                        Text("Stored: \(PublicKeyStore.readable(stored))")
                            .warrantType(.monoSmall)
                            .foregroundStyle(Ink.mute)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 10)
            } label: {
                Text("Use a different public key")
                    .warrantType(.bodySmall)
                    .foregroundStyle(Ink.blue)
            }
            .tint(Ink.blue)
            .padding(16)
        }
    }

    // MARK: - Loading

    private func loadFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            runner.fail("Couldn't read that file.")
            return
        }
        load(data)
    }

    private func load(_ data: Data) {
        do {
            let bundle = try EvidenceBundle.parse(data)
            Task { await verify(bundle) }
        } catch let error as EvidenceBundle.ImportFailure {
            runner.fail(error.message)
        } catch {
            runner.fail("That doesn't look like an evidence bundle.")
        }
    }

    private func verify(_ bundle: EvidenceBundle) async {
        let key = keyOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        showReport = true
        if key.isEmpty {
            await runner.run(bundle: bundle)
        } else {
            await runner.runWithOverride(bundle: bundle, publicKeyBase64: key)
        }
    }
}

private struct ImportRow: View {
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).warrantType(.body).foregroundStyle(Ink.ink)
                        Text(detail)
                            .warrantType(.bodySmall)
                            .foregroundStyle(Ink.soft)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Text("→").warrantType(.body).foregroundStyle(Ink.mute)
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}
