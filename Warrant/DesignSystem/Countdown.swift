import SwiftUI
import UIKit
import WarrantKit

/// Colour by urgency. Ochre under 30 seconds, stamp under 10 — and nothing else changes,
/// because a countdown that pulses and flashes is an anxiety machine, not information.
public enum CountdownTone {
    public static func color(secondsRemaining: TimeInterval) -> Color {
        if secondsRemaining <= 10 { return Ink.stamp }
        if secondsRemaining <= 30 { return Ink.ochreText }
        return Ink.ink
    }
}

/// Driven by `TimelineView` from `expires_at`, never by a local `Timer`.
///
/// A local timer drifts when the app is backgrounded, and a countdown that says nine seconds
/// when the server says zero is the one thing this screen cannot get wrong.
public struct CountdownText: View {
    let expiresAt: Date
    var style: WarrantType = .mono

    @State private var lastHapticThreshold: Int?
    @State private var lastAnnounced: Int?

    public init(expiresAt: Date, style: WarrantType = .mono) {
        self.expiresAt = expiresAt
        self.style = style
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, expiresAt.timeIntervalSince(context.date))
            Text(Self.format(remaining))
                .font(.warrant(style))
                .foregroundStyle(CountdownTone.color(secondsRemaining: remaining))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .onChange(of: Int(remaining)) { _, seconds in
                    tick(at: seconds)
                    announce(seconds)
                }
                .accessibilityLabel("Expires in \(Self.spoken(remaining))")
        }
    }

    public static func format(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func spoken(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.down))
        if total >= 60 {
            let minutes = total / 60
            let seconds = total % 60
            return seconds == 0
                ? "\(minutes) minute\(minutes == 1 ? "" : "s")"
                : "\(minutes) minute\(minutes == 1 ? "" : "s") \(seconds) second\(seconds == 1 ? "" : "s")"
        }
        return "\(total) second\(total == 1 ? "" : "s")"
    }

    /// One tick at each threshold. Not a heartbeat.
    private func tick(at seconds: Int) {
        guard seconds == 30 || seconds == 10, lastHapticThreshold != seconds else { return }
        lastHapticThreshold = seconds
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// VoiceOver hears the countdown at 60, 30 and 10 — not continuously, which would make
    /// the rest of the card unreadable.
    private func announce(_ seconds: Int) {
        guard [60, 30, 10].contains(seconds), lastAnnounced != seconds else { return }
        lastAnnounced = seconds
        UIAccessibility.post(notification: .announcement, argument: "\(seconds) seconds left to decide")
    }
}

/// The ring form, for inbox rows and anywhere the number would be too loud.
public struct CountdownRing: View {
    let expiresAt: Date
    let createdAt: Date
    var lineWidth: CGFloat = 3

    public init(expiresAt: Date, createdAt: Date, lineWidth: CGFloat = 3) {
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.lineWidth = lineWidth
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = max(1, expiresAt.timeIntervalSince(createdAt))
            let remaining = max(0, expiresAt.timeIntervalSince(context.date))
            let fraction = min(1, max(0, remaining / total))

            ZStack {
                Circle()
                    .stroke(Ink.rule.opacity(0.5), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        CountdownTone.color(secondsRemaining: remaining),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(CountdownText.format(remaining))
                    .font(.warrant(.monoSmall))
                    .foregroundStyle(CountdownTone.color(secondsRemaining: remaining))
                    .monospacedDigit()
            }
        }
        .accessibilityHidden(true)
    }
}
