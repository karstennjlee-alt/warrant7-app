import SwiftUI
import WarrantKit

/// Status is never colour alone.
///
/// Two of our reds mean different things — `stamp` is a recorded negative outcome, which is
/// valid evidence, and `brokenEvidence` is evidence that failed verification, which is not
/// evidence at all. Anyone who cannot separate those two hues gets the glyph and the word
/// instead, and so does everyone else.
public struct StatusChip: View {
    public enum Kind {
        case allow, review, block, broken, neutral

        var color: Color {
            switch self {
            case .allow: Ink.seal
            case .review: Ink.ochreText
            case .block: Ink.stamp
            case .broken: Ink.brokenEvidence
            case .neutral: Ink.inkSoft
            }
        }
    }

    let kind: Kind
    let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 6) {
            StatusGlyph(kind: kind)
                .frame(width: 11, height: 11)
            Text(text)
                .font(.warrant(.monoSmall))
                .tracking(0.6)
                .textCase(.uppercase)
        }
        .foregroundStyle(kind.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(kind.color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: Metric.documentRadius))
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

/// A distinct drawn mark per state — a check, a bar, a ring, a hatch. Not SF Symbols (§13),
/// and not the same shape recoloured, which would defeat the point.
public struct StatusGlyph: View {
    let kind: StatusChip.Kind

    public init(kind: StatusChip.Kind) {
        self.kind = kind
    }

    public var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            var path = Path()

            switch kind {
            case .allow:
                path.move(to: CGPoint(x: w * 0.12, y: h * 0.55))
                path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.82))
                path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.18))
            case .block:
                path.move(to: CGPoint(x: w * 0.16, y: h * 0.16))
                path.addLine(to: CGPoint(x: w * 0.84, y: h * 0.84))
                path.move(to: CGPoint(x: w * 0.84, y: h * 0.16))
                path.addLine(to: CGPoint(x: w * 0.16, y: h * 0.84))
            case .review:
                path.addEllipse(in: CGRect(x: w * 0.14, y: h * 0.14, width: w * 0.72, height: h * 0.72))
                path.move(to: CGPoint(x: w * 0.5, y: h * 0.30))
                path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.54))
                path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.66))
            case .broken:
                // Hatching: the mark for evidence that cannot be relied on.
                for index in 0..<4 {
                    let x = w * (0.10 + Double(index) * 0.24)
                    path.move(to: CGPoint(x: x, y: h * 0.9))
                    path.addLine(to: CGPoint(x: x + w * 0.22, y: h * 0.1))
                }
            case .neutral:
                path.move(to: CGPoint(x: w * 0.12, y: h * 0.5))
                path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.5))
            }

            context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

public extension StatusChip.Kind {
    init(approval status: ApprovalStatus) {
        switch status {
        case .pending: self = .review
        case .approvedExecuted: self = .allow
        case .denied, .executionFailed: self = .block
        case .expired, .alreadyDecided: self = .neutral
        }
    }

    init(verification code: VerificationCode) {
        switch code {
        case .ok: self = .allow
        case .untrusted: self = .review
        case .keyMismatch: self = .neutral
        default: self = .broken
        }
    }
}
