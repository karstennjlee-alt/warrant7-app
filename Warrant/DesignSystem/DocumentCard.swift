import SwiftUI

/// A sheet of the stuff: 1pt rule border, 2pt corners, a mono field label across the top strip.
public struct DocumentCard<Content: View>: View {
    let label: String?
    let accent: Color
    @ViewBuilder let content: () -> Content

    public init(label: String? = nil, accent: Color = Ink.rule, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.accent = accent
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label {
                HStack {
                    Text(label)
                        .font(.warrant(.label))
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(accent)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Ink.paperDeep)
                Rectangle()
                    .fill(Ink.rule)
                    .frame(height: Metric.hairline)
            }
            content()
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Metric.documentRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Metric.documentRadius)
                .stroke(Ink.rule, lineWidth: Metric.hairline)
        )
    }
}

/// The line where the document would tear. Dotted, drawn, never a dashed `Divider`.
public struct PerforatedDivider: View {
    var color: Color = Ink.rule

    public init(color: Color = Ink.rule) {
        self.color = color
    }

    public var body: some View {
        Canvas { context, size in
            let dot: CGFloat = 2
            let step: CGFloat = 6
            var x: CGFloat = 0
            while x < size.width {
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: (size.height - dot) / 2, width: dot, height: dot)),
                    with: .color(color)
                )
                x += step
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// The rosette line pattern on security paper. Behind the approval card and nowhere else —
/// if it appeared everywhere it would stop meaning "this is the consequential one".
public struct Guilloche: View {
    var color: Color = Ink.rule
    var opacity: Double = 0.12

    public init(color: Color = Ink.rule, opacity: Double = 0.12) {
        self.color = color
        self.opacity = opacity
    }

    public var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let base = min(size.width, size.height) * 0.46

            // Epitrochoids at slowly drifting radii: the interference between them is what
            // makes the pattern read as engraved rather than as concentric circles.
            for ring in 0..<7 {
                var path = Path()
                let outer = base * (0.55 + Double(ring) * 0.07)
                let inner = outer * 0.34
                let offset = outer * (0.22 + Double(ring) * 0.012)
                let steps = 720

                for step in 0...steps {
                    let t = Double(step) / Double(steps) * 2 * .pi
                    let ratio = (outer - inner) / inner
                    let x = center.x + (outer - inner) * cos(t) + offset * cos(ratio * t)
                    let y = center.y + (outer - inner) * sin(t) - offset * sin(ratio * t)
                    let point = CGPoint(x: x, y: y)
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                context.stroke(path, with: .color(color), lineWidth: 0.5)
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The continuous perforated ledger container.
public struct ReceiptTape<Content: View>: View {
    @ViewBuilder let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            PerforatedDivider()
            content()
            PerforatedDivider()
        }
        .background(Color.white)
        .overlay(
            Rectangle()
                .stroke(Ink.rule, lineWidth: Metric.hairline)
                .padding(.vertical, 3)
        )
    }
}
