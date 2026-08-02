import ActivityKit
import SwiftUI
import WidgetKit
import WarrantKit

/// A pending approval is a live, expiring, single-outcome event — which is precisely what
/// ActivityKit is for. The countdown is always derived from `expiresAt`, never stored, so it
/// cannot drift away from what the gateway believes.
struct ApprovalLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ApprovalActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Ink.canvas)
                .activitySystemActionForegroundColor(Ink.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StampGlyph(status: context.state.status)
                        .frame(width: 22, height: 22)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...context.state.expiresAt, countsDown: true)
                        .font(.system(.body, design: .monospaced))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 62)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.attributes.actionLine)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)
                        Text(context.attributes.amount.formatted())
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.status == .pending {
                        HStack(spacing: 10) {
                            Button(intent: DenyApprovalIntent(approvalID: context.attributes.approvalID)) {
                                Text("Deny").frame(maxWidth: .infinity)
                            }
                            .tint(Ink.red)

                            Button(intent: ApproveApprovalIntent(approvalID: context.attributes.approvalID)) {
                                Text("Approve once").frame(maxWidth: .infinity)
                            }
                            .tint(Ink.green)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text(context.state.status.label)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                StampGlyph(status: context.state.status)
                    .frame(width: 16, height: 16)
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.expiresAt, countsDown: true)
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                StampGlyph(status: context.state.status)
                    .frame(width: 16, height: 16)
            }
            .widgetURL(URL(string: "\(Brand.scheme)://approval/\(context.attributes.approvalID)"))
            .keylineTint(tint(for: context.state.status))
        }
    }

    private func tint(for status: ApprovalStatus) -> Color {
        switch status {
        case .pending: Ink.ochre
        case .approvedExecuted: Ink.green
        case .denied, .executionFailed: Ink.red
        case .expired, .alreadyDecided: Ink.soft
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<ApprovalActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StampGlyph(status: context.state.status).frame(width: 16, height: 16)
                Text(context.attributes.orgName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(context.attributes.boundDigestShort)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text(context.attributes.actionLine)
                .font(.system(size: 19, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if context.state.status == .pending {
                ProgressView(timerInterval: Date()...context.state.expiresAt, countsDown: true)
                    .tint(Ink.ochre)
                    .font(.system(.caption, design: .monospaced))

                HStack(spacing: 10) {
                    Button(intent: DenyApprovalIntent(approvalID: context.attributes.approvalID)) {
                        Text("Deny").frame(maxWidth: .infinity)
                    }
                    .tint(Ink.red)

                    Button(intent: ApproveApprovalIntent(approvalID: context.attributes.approvalID)) {
                        Text("Approve once").frame(maxWidth: .infinity)
                    }
                    .tint(Ink.green)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text(context.state.status.label)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }
}

/// The brand mark, tinted by status. Drawn, not an SF Symbol.
struct StampGlyph: View {
    let status: ApprovalStatus

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            RoundedRectangle(cornerRadius: side * 0.3125, style: .continuous)
                .fill(color)
                .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch status {
        case .pending: Ink.ochre
        case .approvedExecuted: Ink.green
        case .denied, .executionFailed: Ink.red
        case .expired, .alreadyDecided: Ink.soft
        }
    }
}
