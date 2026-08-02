import SwiftUI

/// The notary stamp: a serrated double ring, drawn.
///
/// Deliberately not an SF Symbol (§13). This mark is the brand, and it has to look struck
/// rather than rendered — which means uneven edges and uneven ink, both of which a system
/// glyph would smooth away.
public struct StampShape: Shape {
    public var teeth: Int = 48
    public var toothDepth: CGFloat = 0.028

    public init(teeth: Int = 48, toothDepth: CGFloat = 0.028) {
        self.teeth = teeth
        self.toothDepth = toothDepth
    }

    public func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()

        // Serrated outer edge.
        let steps = teeth * 2
        for step in 0...steps {
            let angle = (Double(step) / Double(steps)) * 2 * .pi - .pi / 2
            let scale = step.isMultiple(of: 2) ? 1.0 : 1.0 - toothDepth
            let point = CGPoint(
                x: center.x + cos(angle) * radius * scale,
                y: center.y + sin(angle) * radius * scale
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()

        // Inner rule, the way a real stamp has a second ring inside the border.
        path.addEllipse(in: CGRect(
            x: center.x - radius * 0.80, y: center.y - radius * 0.80,
            width: radius * 1.60, height: radius * 1.60
        ))
        return path
    }
}

/// A struck stamp with its label, mottled so the ink looks uneven.
public struct Stamp: View {
    let text: String
    let color: Color
    /// Seeds rotation and mottling, so two stamps on screen are never identical twins.
    let seed: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var impressed = false

    public init(text: String, color: Color, seed: String = "") {
        self.text = text
        self.color = color
        self.seed = seed
    }

    /// 2 to 7 degrees, chosen by the approval id rather than at random, so the same decision
    /// always looks the same — including in a screenshot taken twice.
    private var angle: Double {
        let hash = abs(seed.hashValue)
        let magnitude = 2.0 + Double(hash % 500) / 100.0
        return hash.isMultiple(of: 2) ? magnitude : -magnitude
    }

    public var body: some View {
        ZStack {
            StampShape()
                .stroke(color, style: StrokeStyle(lineWidth: 2.5))
            Text(text)
                .font(.warrant(.label))
                .tracking(1.2)
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
        }
        .frame(width: 132, height: 132)
        // Uneven ink. A stamp that presses perfectly flat looks printed, not pressed.
        .overlay(InkMottle(seed: seed).blendMode(.destinationOut))
        .compositingGroup()
        .rotationEffect(.degrees(angle))
        .scaleEffect(impressed || reduceMotion ? 1.0 : 1.35)
        .opacity(impressed || reduceMotion ? 1 : 0)
        .onAppear {
            guard !reduceMotion else { impressed = true; return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.62)) {
                impressed = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

/// Speckle that eats away at the ink, so coverage is imperfect the way a rubber stamp's is.
private struct InkMottle: View {
    let seed: String

    var body: some View {
        Canvas { context, size in
            var generator = SplitMix64(seed: UInt64(abs(seed.hashValue)) | 1)
            for _ in 0..<220 {
                let x = Double(generator.next() % 1000) / 1000 * size.width
                let y = Double(generator.next() % 1000) / 1000 * size.height
                let radius = 0.6 + Double(generator.next() % 180) / 100
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                    with: .color(.white.opacity(0.55))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// Deterministic from a seed, so a stamp is identical every time it is drawn. `Double.random`
/// would make the same decision look different on every redraw, which reads as a glitch.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
