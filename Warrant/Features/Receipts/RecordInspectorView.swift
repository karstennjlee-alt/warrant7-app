import SwiftUI
import WarrantKit

/// The full canonical payload, the exact bytes that were hashed, and the recomputation.
///
/// This screen exists so "verified" is not a word anyone has to take on faith. Everything here
/// was computed on this device from the record itself.
struct RecordInspectorView: View {
    let record: ReceiptRecord
    let verdict: VerificationCode?

    @Environment(\.dismiss) private var dismiss
    @State private var canonical = ""
    @State private var recomputed = ""

    private var matches: Bool { !recomputed.isEmpty && recomputed == record.hash }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let verdict {
                        Pill(text: verdict.label, color: verdict.isOK ? Ink.green : Ink.red)
                        Text(verdict.message)
                            .warrantType(.body)
                            .foregroundStyle(Ink.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 9) {
                            KeyValueRow(key: "event", value: record.event)
                            KeyValueRow(key: "actor", value: record.actor)
                            KeyValueRow(key: "resource", value: record.resource)
                            if let amount = record.amount {
                                KeyValueRow(key: "amount", value: "\(amount.minorUnits) \(amount.currencyCode)")
                            }
                            KeyValueRow(key: "at", value: WarrantJSON.string(from: record.timestamp))
                        }
                        .padding(16)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("The exact bytes that were hashed").fieldLabel()
                            Text("RFC 8785 canonical form, UTF-8. Members sorted by UTF-16 code unit, no whitespace, ECMAScript number formatting.")
                                .warrantType(.bodySmall)
                                .foregroundStyle(Ink.soft)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(canonical)
                                .warrantType(.monoSmall)
                                .foregroundStyle(Ink.ink)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(canonical.utf8.count) bytes")
                                .warrantType(.monoSmall)
                                .foregroundStyle(Ink.mute)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recomputation").fieldLabel()
                            KeyValueRow(key: "previous", value: record.previousHash, labelWidth: 84)
                            KeyValueRow(key: "as signed", value: record.hash, labelWidth: 84)
                            KeyValueRow(
                                key: "recomputed",
                                value: recomputed.isEmpty ? "computing…" : recomputed,
                                valueColor: matches ? Ink.green : Ink.red,
                                labelWidth: 84
                            )
                            Text(matches
                                 ? "SHA-256 of the previous hash followed by those canonical bytes, computed here, matches what was signed."
                                 : "The recomputation does not match. This record no longer hashes to its signed digest.")
                                .warrantType(.bodySmall)
                                .foregroundStyle(Ink.soft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Signature · Ed25519").fieldLabel()
                            Text(record.signature)
                                .warrantType(.monoSmall)
                                .foregroundStyle(Ink.green)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .background(Ink.surface)
            .navigationTitle("Record \(String(format: "%02d", record.sequence))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Ink.blue)
                }
            }
            .task { compute() }
        }
    }

    private func compute() {
        canonical = (try? CanonicalJSON.canonicalize(record.body)) ?? ""
        guard let previous = Digest256(hex: record.previousHash),
              let bytes = try? CanonicalJSON.canonicalBytes(record.body) else { return }
        recomputed = Digest256.chained(previous: previous, canonical: bytes).hex
    }
}
