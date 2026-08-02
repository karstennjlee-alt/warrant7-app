import SwiftUI
import WarrantKit

struct LedgerView: View {
    var highlight: Int?

    @Environment(AppState.self) private var state
    @State private var runner = VerificationRunner()
    @State private var inspected: ReceiptRecord?
    @State private var showVerifier = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Receipts", subtitle: "Each record hashes the one before it.") {
                Text("\(state.receipts.count) records")
                    .warrantType(.monoSmall)
                    .foregroundStyle(Ink.mute)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(state.receipts) { record in
                        Button { inspected = record } label: {
                            LedgerRow(
                                record: record,
                                verdict: verdict(for: record),
                                isHighlighted: record.sequence == highlight
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    legend.padding(.top, 8)
                }
                .padding(14)
                .padding(.bottom, 40)
            }
            .background(Ink.surface)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Button(runner.isRunning ? "Checking…" : "Verify with public key") {
                Task {
                    guard let bundle = await state.bundle() else {
                        runner.fail("There's nothing cached to check yet.")
                        return
                    }
                    showVerifier = true
                    await runner.run(bundle: bundle)
                }
            }
            .buttonStyle(SolidButtonStyle(color: Ink.blue))
            .disabled(runner.isRunning || state.receipts.isEmpty)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Ink.surface.opacity(0.94))
        }
        .sheet(item: $inspected) { record in
            RecordInspectorView(record: record, verdict: verdict(for: record))
        }
        .navigationDestination(isPresented: $showVerifier) {
            VerifyReportView(runner: runner)
        }
        .task { await state.loadReceipts() }
    }

    private func verdict(for record: ReceiptRecord) -> VerificationCode? {
        guard let report = runner.report,
              let index = report.records.firstIndex(where: { $0.sequence == record.sequence }),
              index < runner.revealed else { return nil }
        return report.records[index].code
    }

    /// The distinction people confuse, stated rather than left to hue.
    private var legend: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Two different reds").fieldLabel()
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Ink.red).frame(width: 6, height: 6).padding(.top, 6)
                    Text("A denial or a block is a **recorded outcome**. That is valid evidence that something did not happen.")
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Color(hex: 0x6E1E18)).frame(width: 6, height: 6).padding(.top, 6)
                    Text("A failed check is **broken evidence**. That record proves nothing, and neither does anything after it.")
                        .warrantType(.bodySmall)
                        .foregroundStyle(Ink.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LedgerRow: View {
    let record: ReceiptRecord
    let verdict: VerificationCode?
    let isHighlighted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isBroken: Bool {
        guard let verdict else { return false }
        if case .untrusted = verdict { return false }
        return !verdict.isOK
    }

    private var eventColor: Color {
        if isBroken { return Color(hex: 0x6E1E18) }
        return record.isNegativeOutcome ? Ink.red : Ink.ink
    }

    var body: some View {
        Card(
            radius: Metric.rowRadius,
            border: isBroken ? Color(hex: 0xEFC9C4) : Ink.line,
            background: isBroken ? Color(hex: 0xFDF3F2) : (isHighlighted ? Ink.blue.opacity(0.05) : Ink.card)
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Circle().fill(eventColor).frame(width: 6, height: 6)
                    Text(record.event).warrantType(.mono).foregroundStyle(eventColor)
                    if let amount = record.amount {
                        Text(amount.formatted()).warrantType(.bodySmall).foregroundStyle(Ink.soft)
                    }
                    Spacer(minLength: 0)
                    Text("\(String(format: "%02d", record.sequence)) · \(record.timestamp.formatted(date: .omitted, time: .shortened))")
                        .warrantType(.monoTiny)
                        .foregroundStyle(Ink.mute)
                }

                Text(record.hashShort)
                    .warrantType(.monoSmall)
                    .foregroundStyle(Ink.mute)
                    .padding(.top, 7)

                if let verdict {
                    Text(verdict.label)
                        .warrantType(.monoSmall)
                        .foregroundStyle(verdictColor(verdict))
                        .padding(.top, 5)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: verdict)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Record \(record.sequence), \(record.event)\(verdict.map { ", \($0.label)" } ?? "")")
    }

    private func verdictColor(_ code: VerificationCode) -> Color {
        if code.isOK { return Ink.green }
        if case .untrusted = code { return Ink.ochre }
        return Color(hex: 0x6E1E18)
    }
}
