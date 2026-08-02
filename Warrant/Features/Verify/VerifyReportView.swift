import SwiftUI
import WarrantKit

/// The verdict screen: one stamp, one sentence, then every record with its own answer.
///
/// It reads an exported bundle and a public key, and nothing else. It holds no database
/// handle, no credential, and no opinion.
struct VerifyReportView: View {
    let runner: VerificationRunner

    @Environment(\.dismiss) private var dismiss

    private var isFailed: Bool {
        guard let report = runner.report else { return false }
        return !report.isVerified
    }

    private var tint: Color { isFailed ? Ink.red : Ink.green }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let report = runner.report {
                    verdict(report)
                    rows(report)
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Recomputing on this device…")
                            .warrantType(.bodySmall)
                            .foregroundStyle(Ink.soft)
                    }
                }

                Text("The verifier reads an exported bundle and the public key. It holds no database handle, no credential, and no opinion.")
                    .warrantType(.bodySmall)
                    .foregroundStyle(Ink.mute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 26)
        }
        .background(Ink.card)
        .navigationTitle("Verifier")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if runner.report != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: runner.shareText()) { Text("Share").warrantType(.bodySmall) }
                }
            }
        }
    }

    private func verdict(_ report: VerificationReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Pill(
                text: report.isVerified ? "Chain verified"
                    : report.isKeyMismatch ? "Wrong key"
                    : "Verification failed",
                color: tint
            )

            Text(headline(report))
                .warrantType(.verifyHead)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(blurb(report))
                .warrantType(.body)
                .foregroundStyle(Ink.soft)
                .fixedSize(horizontal: false, vertical: true)

            Text(subline(report))
                .warrantType(.monoSmall)
                .foregroundStyle(Ink.mute)
        }
    }

    private func headline(_ report: VerificationReport) -> String {
        if report.isKeyMismatch { return "Nothing verifies under this key" }
        if let first = report.firstFailure { return "Record \(String(format: "%02d", first)) has been altered" }
        return "Every record checks out"
    }

    private func blurb(_ report: VerificationReport) -> String {
        if report.isKeyMismatch {
            return VerificationCode.keyMismatch.message
        }
        if report.firstFailure != nil {
            let detail = report.records.first { !$0.isOK }?.code.message ?? ""
            return "\(detail) Every record after it is untrusted. The edit created and reversed nothing — the ledger simply announced it."
        }
        return "Each digest recomputed here, each link re-checked here, each signature valid under the public key you supplied."
    }

    private func subline(_ report: VerificationReport) -> String {
        let key = runner.bundle.map { String($0.publicKeyBase64.prefix(8)) } ?? "—"
        if let first = report.firstFailure {
            return "first bad link at \(String(format: "%02d", first)) · key \(key)"
        }
        return "\(report.records.count) records · key \(key)"
    }

    private func rows(_ report: VerificationReport) -> some View {
        VStack(spacing: 0) {
            ForEach(runner.visibleRecords) { record in
                HStack(spacing: 10) {
                    Text(String(format: "%02d", record.sequence))
                        .warrantType(.monoSmall)
                        .foregroundStyle(Ink.mute)
                        .frame(width: 22, alignment: .leading)
                    Text(record.event)
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.ink)
                    Spacer()
                    Text(shortVerdict(record.code))
                        .warrantType(.label)
                        .foregroundStyle(color(for: record.code))
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(background(for: record.code))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Ink.fill).frame(height: Metric.hairline)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                .stroke(Ink.line, lineWidth: Metric.hairline)
        )
    }

    private func shortVerdict(_ code: VerificationCode) -> String {
        switch code {
        case .ok: "OK"
        case .untrusted: "Untrusted"
        case .signatureInvalid: "Signature invalid"
        case .hashMismatch: "Digest mismatch"
        case .chainBroken: "Chain broken"
        case .sequenceGap: "Record missing"
        case .keyMismatch: "Wrong key"
        case .malformed: "Malformed"
        }
    }

    private func color(for code: VerificationCode) -> Color {
        if code.isOK { return Ink.green }
        if case .untrusted = code { return Ink.ochre }
        return Ink.red
    }

    private func background(for code: VerificationCode) -> Color {
        if code.isOK { return Ink.card }
        if case .untrusted = code { return Ink.warnFill }
        return Ink.brokenFill
    }
}
