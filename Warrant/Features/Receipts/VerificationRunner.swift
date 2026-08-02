import Foundation
import Observation
import SwiftUI
import WarrantKit

/// Runs verification on device and reveals the result record by record.
///
/// The staggered reveal is not decoration. Verification that appears instantly is
/// indistinguishable from a boolean the server handed us; watching it walk the chain is what
/// makes it legible as work the phone actually did.
@MainActor
@Observable
final class VerificationRunner {
    private(set) var report: VerificationReport?
    private(set) var revealed = 0
    private(set) var isRunning = false
    private(set) var bundle: EvidenceBundle?
    private(set) var failure: String?

    private let verifier = ChainVerifier()

    var visibleRecords: [RecordReport] {
        guard let report else { return [] }
        return Array(report.records.prefix(revealed))
    }

    var isComplete: Bool {
        guard let report else { return false }
        return revealed >= report.records.count
    }

    func run(bundle: EvidenceBundle, staggered: Bool = true) async {
        isRunning = true
        failure = nil
        revealed = 0
        self.bundle = bundle

        // The whole verification happens here, on this device, from the bundle and the key.
        // No network call, no server verdict, nothing taken on trust.
        let result = verifier.verify(bundle: bundle)
        report = result

        if staggered {
            for index in result.records.indices {
                revealed = index + 1
                try? await Task.sleep(for: .milliseconds(80))
            }
        } else {
            revealed = result.records.count
        }
        isRunning = false
    }

    func runWithOverride(bundle: EvidenceBundle, publicKeyBase64: String) async {
        await run(bundle: EvidenceBundle(
            organization: bundle.organization,
            exportedAt: bundle.exportedAt,
            publicKeyBase64: publicKeyBase64,
            records: bundle.records
        ))
    }

    func reset() {
        report = nil
        revealed = 0
        bundle = nil
        failure = nil
    }

    func fail(_ message: String) {
        failure = message
        report = nil
        isRunning = false
    }

    /// A plain-text report to share. Deliberately free of anything that looks like a
    /// credential, in every state (§9.6).
    func shareText() -> String {
        guard let report, let bundle else { return "" }
        var lines = [
            "\(Brand.name) — verification report",
            "Organization: \(bundle.organization)",
            "Records: \(report.records.count)",
            "Result: \(report.isVerified ? "VERIFIED" : "FAILED")",
            ""
        ]
        for record in report.records {
            lines.append("\(String(format: "%02d", record.sequence))  \(record.event)  \(record.code.label)")
        }
        lines.append("")
        lines.append(Brand.claimLine)
        return lines.joined(separator: "\n")
    }
}
