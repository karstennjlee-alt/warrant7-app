import SwiftUI
import WarrantKit

// MARK: - Surfaces

/// A white card on the quiet surface: 1pt line, generous radius.
public struct Card<Content: View>: View {
    var radius: CGFloat = Metric.cardRadius
    var border: Color = Ink.line
    var background: Color = Ink.card
    @ViewBuilder let content: () -> Content

    public init(
        radius: CGFloat = Metric.cardRadius,
        border: Color = Ink.line,
        background: Color = Ink.card,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.radius = radius
        self.border = border
        self.background = background
        self.content = content
    }

    public var body: some View {
        content()
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(border, lineWidth: Metric.hairline)
            )
    }
}

/// The inset grey panel used for "why you were asked", the ticket, and the binding rows.
public struct Panel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface)
            .clipShape(RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous))
    }
}

/// The brand mark: a rounded square, tinted by meaning. Drawn, not an SF Symbol.
public struct BrandMark: View {
    var color: Color = Ink.ink
    var size: CGFloat = 16

    public init(color: Color = Ink.ink, size: CGFloat = 16) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3125, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Status

/// A dot and a word. Status is never colour alone — the word carries it for anyone who cannot
/// separate the two reds, and there are two reds that mean very different things.
public struct StatusLabel: View {
    let text: String
    let color: Color
    var mono = false

    public init(text: String, color: Color, mono: Bool = false) {
        self.text = text
        self.color = color
        self.mono = mono
    }

    public var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .warrantType(mono ? .monoSmall : .label)
                .foregroundStyle(color)
        }
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

/// The rounded pill used for verdicts and warnings.
public struct Pill: View {
    let text: String
    let color: Color

    public init(text: String, color: Color) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .warrantType(.label)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(color.opacity(0.09))
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

// MARK: - Rows

/// Label on the left in sans, value on the right in mono. The whole product's typographic rule
/// in one row.
public struct KeyValueRow: View {
    let key: String
    let value: String
    var valueColor: Color = Ink.ink
    var labelWidth: CGFloat = 92

    public init(key: String, value: String, valueColor: Color = Ink.ink, labelWidth: CGFloat = 92) {
        self.key = key
        self.value = value
        self.valueColor = valueColor
        self.labelWidth = labelWidth
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .warrantType(.monoSmall)
                .foregroundStyle(Ink.mute)
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .warrantType(.monoSmall)
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(key): \(value)")
    }
}

// MARK: - Policy envelope

/// Green up to the automatic limit, amber to the hard stop, red beyond — with a marker where
/// this amount lands. The whole reason a person is being asked, in one bar.
public struct EnvelopeBar: View {
    let autoLimitMinor: Int
    let blockLimitMinor: Int
    /// `nil` on the policy screen, where there is no single amount in play.
    var markerMinor: Int?
    var showMarkerLabel = true

    public init(autoLimitMinor: Int, blockLimitMinor: Int, markerMinor: Int? = nil, showMarkerLabel: Bool = true) {
        self.autoLimitMinor = autoLimitMinor
        self.blockLimitMinor = blockLimitMinor
        self.markerMinor = markerMinor
        self.showMarkerLabel = showMarkerLabel
    }

    private var scale: Double {
        max(Double(blockLimitMinor) * 1.35, 650_000)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let autoWidth = width * min(1, Double(autoLimitMinor) / scale)
                let reviewWidth = width * min(1, Double(max(0, blockLimitMinor - autoLimitMinor)) / scale)

                HStack(spacing: 0) {
                    Rectangle().fill(Ink.green).frame(width: autoWidth)
                    Rectangle().fill(Ink.ochreBand).frame(width: reviewWidth)
                    Rectangle().fill(Ink.red)
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)

            if let markerMinor, showMarkerLabel {
                GeometryReader { geometry in
                    let fraction = min(0.88, max(0.12, Double(markerMinor) / scale))
                    Text("▲ \(Money(minorUnits: markerMinor).formatted())")
                        .warrantType(.monoSmall)
                        .foregroundStyle(Ink.ink)
                        .fixedSize()
                        .alignmentGuide(.leading) { $0.width / 2 }
                        .offset(x: geometry.size.width * fraction)
                }
                .frame(height: 20)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Policy envelope")
    }
}

// MARK: - Countdown ring

/// The 78pt ring on the approval card. Driven by `TimelineView` from `expires_at` — a stored
/// or locally-ticked countdown drifts, and a card that disagrees with the gateway about how
/// long is left is the one thing this screen must never do.
public struct TimerRing: View {
    let expiresAt: Date
    let createdAt: Date
    var diameter: CGFloat = 78
    var lineWidth: CGFloat = 5

    public init(expiresAt: Date, createdAt: Date, diameter: CGFloat = 78, lineWidth: CGFloat = 5) {
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.diameter = diameter
        self.lineWidth = lineWidth
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = max(1, expiresAt.timeIntervalSince(createdAt))
            let remaining = max(0, expiresAt.timeIntervalSince(context.date))
            let fraction = min(1, max(0, remaining / total))
            let tint = CountdownTone.color(secondsRemaining: remaining)

            ZStack {
                Circle().stroke(Ink.fill, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(CountdownText.format(remaining))
                    .warrantType(.monoAmount)
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            .frame(width: diameter, height: diameter)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Slide to approve

/// Deny is one tap. Approving takes a deliberate slide, and then Face ID.
///
/// The gesture is not theatre: it makes the risky action impossible to trigger by brushing the
/// screen, which is exactly the asymmetry the product argues for everywhere else.
public struct SlideToApprove: View {
    let isEnabled: Bool
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var trackWidth: CGFloat = 0
    @State private var isDragging = false

    public init(isEnabled: Bool = true, onComplete: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.onComplete = onComplete
    }

    private var maxOffset: CGFloat {
        max(0, trackWidth - Metric.slideThumb - 10)
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.fill)

                Capsule()
                    .fill(Ink.green.opacity(0.14))
                    .frame(width: offset + Metric.slideThumb + 10)

                Text("Slide to approve")
                    .warrantType(.body)
                    .foregroundStyle(Ink.soft)
                    .frame(maxWidth: .infinity)
                    .opacity(maxOffset > 0 ? max(0, 1 - Double(offset / (maxOffset * 0.5))) : 1)

                Circle()
                    .fill(isEnabled ? Ink.green : Ink.lineStrong)
                    .frame(width: Metric.slideThumb, height: Metric.slideThumb)
                    .overlay(
                        Text("→")
                            .warrantType(.title)
                            .foregroundStyle(.white)
                    )
                    .offset(x: offset + 5)
                    .gesture(drag)
            }
            .onAppear { trackWidth = geometry.size.width }
            .onChange(of: geometry.size.width) { _, width in trackWidth = width }
        }
        .frame(height: Metric.slideTrackHeight)
        .accessibilityElement()
        .accessibilityLabel("Slide to approve")
        .accessibilityHint("Approving asks for Face ID.")
        .accessibilityAddTraits(.isButton)
        // VoiceOver cannot slide, so the gesture must not be the only way through.
        .accessibilityAction { if isEnabled { onComplete() } }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled else { return }
                isDragging = true
                // Track the finger directly: the thumb centres under it, clamped to the rail.
                offset = min(maxOffset, max(0, value.location.x - Metric.slideThumb / 2))
            }
            .onEnded { _ in
                isDragging = false
                guard isEnabled else { return }
                // 88% of the way is a commitment; anything less springs back.
                if offset > maxOffset * 0.88 {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.15)) { offset = maxOffset }
                    onComplete()
                } else {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
                        offset = 0
                    }
                }
            }
    }

    public func reset() {
        offset = 0
    }
}

// MARK: - Buttons

public struct SolidButtonStyle: ButtonStyle {
    var color: Color = Ink.ink
    var foreground: Color = .white

    public init(color: Color = Ink.ink, foreground: Color = .white) {
        self.color = color
        self.foreground = foreground
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .warrantType(.body)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: Metric.buttonHeight)
            .background(configuration.isPressed ? color.opacity(0.86) : color)
            .clipShape(RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous))
            .contentShape(Rectangle())
    }
}

public struct OutlineButtonStyle: ButtonStyle {
    var color: Color = Ink.ink
    var border: Color = Ink.line

    public init(color: Color = Ink.ink, border: Color = Ink.line) {
        self.color = color
        self.border = border
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .warrantType(.body)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: Metric.buttonHeight)
            .background(configuration.isPressed ? color.opacity(0.06) : Ink.card)
            .clipShape(RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                    .stroke(border, lineWidth: Metric.hairline)
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Screen header

/// The title block every screen opens with: name, then one line of plain explanation.
public struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    public init(title: String, subtitle: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .warrantType(.screenTitle)
                    .foregroundStyle(Ink.ink)
                Spacer()
                trailing()
            }
            Text(subtitle)
                .warrantType(.bodySmall)
                .foregroundStyle(Ink.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(Ink.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line).frame(height: Metric.hairline)
        }
    }
}
