import SwiftUI
import UIKit
import WarrantKit

/// Colour by urgency: ochre under 60 seconds, red under 20, and nothing else changes.
///
/// No pulsing, no flashing, no rising tone. The countdown is information about a deadline, not
/// a device for making someone anxious enough to tap something.
public enum CountdownTone {
    public static func color(secondsRemaining: TimeInterval) -> Color {
        if secondsRemaining <= 20 { return Ink.red }
        if secondsRemaining <= 60 { return Ink.ochre }
        return Ink.green
    }
}

/// Driven by `TimelineView` from `expires_at`, never by a local `Timer`.
public struct CountdownText: View {
    let expiresAt: Date
    var style: WarrantType = .mono

    @State private var lastHaptic: Int?
    @State private var lastAnnounced: Int?

    public init(expiresAt: Date, style: WarrantType = .mono) {
        self.expiresAt = expiresAt
        self.style = style
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, expiresAt.timeIntervalSince(context.date))
            Text(Self.format(remaining))
                .warrantType(style)
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
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    public static func spoken(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.down))
        guard total >= 60 else { return "\(total) second\(total == 1 ? "" : "s")" }
        let minutes = total / 60
        let seconds = total % 60
        let minutePart = "\(minutes) minute\(minutes == 1 ? "" : "s")"
        return seconds == 0 ? minutePart : "\(minutePart) \(seconds) second\(seconds == 1 ? "" : "s")"
    }

    /// One tick at each threshold. Not a heartbeat.
    private func tick(at seconds: Int) {
        guard seconds == 60 || seconds == 20, lastHaptic != seconds else { return }
        lastHaptic = seconds
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// VoiceOver hears the countdown at 60, 30 and 10 — not continuously, which would make the
    /// rest of the card unreadable.
    private func announce(_ seconds: Int) {
        guard [60, 30, 10].contains(seconds), lastAnnounced != seconds else { return }
        lastAnnounced = seconds
        UIAccessibility.post(notification: .announcement, argument: "\(seconds) seconds left to decide")
    }
}
