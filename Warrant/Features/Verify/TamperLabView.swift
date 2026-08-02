import SwiftUI
import WarrantKit

/// Act three: hand the phone to someone and let them edit stored data.
///
/// The failure they see is a real SHA-256 recomputation on this device, not a scripted red
/// screen. Nothing here can retroactively execute anything — the worst a forger achieves is a
/// ledger that announces it has been forged.
struct TamperLabView: View {
    @Environment(AppState.self) private var state

    @State private var amountText = ""
    @State private var recomputed = ""
    @State private var runner = VerificationRunner()
    @State private var showVerifier = false

    private var record: ReceiptRecord? {
        state.receipts.last
    }

    private var isTampered: Bool {
        guard let record, let original = record.amount?.minorUnits else { return false }
        return amountText != String(original)
    }

    private var matches: Bool {
        guard let record else { return true }
        return recomputed == record.hash
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: "Tamper lab",
                subtitle: "Hand the phone to someone. Let them edit stored data."
            )

            ScrollView {
                if let record {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Record \(String(format: "%02d", record.sequence)) exactly as it sits in storage. Change the amount and the hash is recomputed here, live.")
                            .warrantType(.body)
                            .foregroundStyle(Ink.soft)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)

                        rawRecord(record)
                        comparison(record)
                        controls(record)

                        Text("Nothing here can retroactively execute anything. The worst a forger achieves is a ledger that announces it has been forged.")
                            .warrantType(.bodySmall)
                            .foregroundStyle(Ink.mute)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    .padding(14)
                    .padding(.bottom, 30)
                } else {
                    Text("Load the ledger once and this becomes editable.")
                        .warrantType(.body)
                        .foregroundStyle(Ink.soft)
                        .padding(40)
                }
            }
            .background(Ink.surface)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showVerifier) {
            VerifyReportView(runner: runner)
        }
        .task {
            await state.loadReceipts()
            reset()
        }
        .onChange(of: amountText) { _, _ in recompute() }
    }

    /// The record as stored, in a dark terminal block — with one field you can actually edit.
    private func rawRecord(_ record: ReceiptRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("{\"actor\":\"\(record.actor)\",")
            HStack(spacing: 6) {
                Text(" \"amount_minor\":")
                TextField("", text: $amountText)
                    .keyboardType(.numberPad)
                    .warrantType(.mono)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .frame(width: 108)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(isTampered ? Ink.red.opacity(0.28) : Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isTampered ? Ink.red : Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .accessibilityLabel("Stored amount in minor units")
                Text(",")
            }
            Text(" \"currency\":\"\(record.amount?.currencyCode ?? "USD")\",\"event\":\"\(record.event)\",")
            Text(" \"prev\":\"\(String(record.previousHash.prefix(28)))…\",")
            Text(" \"resource\":\"\(record.resource)\",\"seq\":\(record.sequence),")
            Text(" \"ts\":\"\(WarrantJSON.string(from: record.timestamp))\"}")
        }
        .warrantType(.mono)
        .foregroundStyle(Ink.terminalText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Ink.terminal)
        .clipShape(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
    }

    private func comparison(_ record: ReceiptRecord) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                KeyValueRow(key: "as signed", value: record.hash, labelWidth: 84)
                KeyValueRow(
                    key: "recomputed",
                    value: recomputed.isEmpty ? "computing…" : recomputed,
                    valueColor: matches ? Ink.green : Ink.red,
                    labelWidth: 84
                )
                HStack(spacing: 8) {
                    Circle().fill(matches ? Ink.green : Ink.red).frame(width: 6, height: 6)
                    Text(matches
                         ? "Match — record \(String(format: "%02d", record.sequence)) is intact"
                         : "Mismatch — record \(String(format: "%02d", record.sequence)) and everything after it is untrusted")
                        .warrantType(.bodySmall)
                        .foregroundStyle(matches ? Ink.green : Ink.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func controls(_ record: ReceiptRecord) -> some View {
        HStack(spacing: 10) {
            Button("Restore") { reset() }
                .buttonStyle(OutlineButtonStyle())
                .frame(maxWidth: .infinity)

            Button("Re-run verifier") { runVerifier() }
                .buttonStyle(SolidButtonStyle(color: Ink.blue))
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - The real computation

    private func reset() {
        amountText = record?.amount.map { String($0.minorUnits) } ?? ""
        recompute()
    }

    /// Rebuild the record body with whatever is in the field and hash it, exactly the way the
    /// verifier does. This is the same code path, not a simulation of it.
    private func recompute() {
        guard let record,
              case .object(var members) = record.body,
              let previous = Digest256(hex: record.previousHash) else { return }

        members["amount_minor"] = .number(Double(Int(amountText) ?? 0))
        guard let canonical = try? CanonicalJSON.canonicalBytes(.object(members)) else { return }
        recomputed = Digest256.chained(previous: previous, canonical: canonical).hex
    }

    private func runVerifier() {
        Task {
            guard var bundle = await state.bundle(), let record else { return }

            if isTampered {
                var records = bundle.records
                if let index = records.firstIndex(where: { Int($0["seq"]?.numberValue ?? -1) == record.sequence }),
                   case .object(var members) = records[index] {
                    members["amount_minor"] = .number(Double(Int(amountText) ?? 0))
                    records[index] = .object(members)
                }
                bundle = EvidenceBundle(
                    organization: bundle.organization,
                    exportedAt: bundle.exportedAt,
                    publicKeyBase64: bundle.publicKeyBase64,
                    records: records
                )
            }

            showVerifier = true
            await runner.run(bundle: bundle)
        }
    }
}
