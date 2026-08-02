import SwiftUI
import UIKit
import WarrantKit

/// Two faces, one rule.
///
/// **Anything the system computed is set in JetBrains Mono. Anything a human wrote is set in
/// Instrument Sans.** Amounts, digests, signatures, timestamps, state names, event types and
/// sequence numbers are mono. Explanations, labels and buttons are not.
public enum WarrantType {
    case screenTitle    // 24 / 600
    case amountHuge     // 46 / 500 — the approval card
    case amountRow      // 27 / 500 — an inbox row
    case headline       // 22 / 500
    case verifyHead     // 26 / 400
    case title          // 19 / 500
    case body           // 15 / 400
    case bodySmall      // 13.5 / 400
    case label          // 12.5 / 500
    case monoAmount     // 16 / 500
    case mono           // 13 / 400
    case monoSmall      // 11.5 / 400
    case monoTiny       // 10 / 400

    var family: Family {
        switch self {
        case .monoAmount, .mono, .monoSmall, .monoTiny: .mono
        default: .sans
        }
    }

    var size: CGFloat {
        switch self {
        case .screenTitle: 24
        case .amountHuge: 46
        case .amountRow: 27
        case .headline: 22
        case .verifyHead: 26
        case .title: 19
        case .body: 15
        case .bodySmall: 13.5
        case .label: 12.5
        case .monoAmount: 16
        case .mono: 13
        case .monoSmall: 11.5
        case .monoTiny: 10
        }
    }

    var weight: Weight {
        switch self {
        case .screenTitle: .semibold
        case .amountHuge, .amountRow, .headline, .title, .label, .monoAmount: .medium
        case .verifyHead, .body, .bodySmall, .mono, .monoSmall, .monoTiny: .regular
        }
    }

    /// Optical tightening, as the design specifies per size. Larger type gets tighter.
    var tracking: CGFloat {
        switch self {
        case .amountHuge: size * -0.040
        case .amountRow: size * -0.030
        case .verifyHead: size * -0.028
        case .screenTitle: size * -0.025
        case .headline: size * -0.020
        default: size * -0.011
        }
    }

    /// Which metric drives Dynamic Type. Amounts scale on `.body` so that the largest
    /// accessibility sizes grow them without shoving the rest of the card off screen.
    var textStyle: UIFont.TextStyle {
        switch self {
        case .amountHuge, .screenTitle, .verifyHead: .title2
        case .amountRow, .headline: .title3
        case .title: .headline
        case .body, .monoAmount: .body
        case .bodySmall, .mono: .callout
        case .label, .monoSmall, .monoTiny: .caption1
        }
    }

    enum Family { case sans, mono }
    enum Weight { case regular, medium, semibold }

    var postScriptName: String {
        switch (family, weight) {
        case (.sans, .semibold): "InstrumentSans-SemiBold"
        case (.sans, .medium): "InstrumentSans-Medium"
        case (.sans, .regular): "InstrumentSans-Regular"
        case (.mono, .regular): "JetBrainsMono-Regular"
        case (.mono, _): "JetBrainsMono-Medium"
        }
    }
}

public extension Font {
    /// Scales with Dynamic Type through `UIFontMetrics`, so the largest accessibility sizes
    /// grow the text rather than clipping it.
    static func warrant(_ style: WarrantType) -> Font {
        Font(WarrantFonts.uiFont(style))
    }
}

public extension View {
    /// Font plus the tracking that belongs to it, so the two never drift apart.
    func warrantType(_ style: WarrantType) -> some View {
        self.font(.warrant(style)).tracking(style.tracking)
    }

    /// Small, muted, sentence case — the design's field labels.
    func fieldLabel() -> some View {
        self.warrantType(.label).foregroundStyle(Ink.mute)
    }
}

public enum WarrantFonts {
    static func uiFont(_ style: WarrantType) -> UIFont {
        let base = UIFont(name: style.postScriptName, size: style.size) ?? fallback(style)
        return UIFontMetrics(forTextStyle: style.textStyle).scaledFont(for: base)
    }

    /// A missing font should degrade, not disappear.
    private static func fallback(_ style: WarrantType) -> UIFont {
        let weight: UIFont.Weight = switch style.weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
        return style.family == .mono
            ? .monospacedSystemFont(ofSize: style.size, weight: weight)
            : .systemFont(ofSize: style.size, weight: weight)
    }

    /// Called once at launch so a missing font shows up in the console rather than as a
    /// mysteriously plain screen.
    public static func verifyRegistration() {
        let expected = [
            "InstrumentSans-Regular", "InstrumentSans-Medium", "InstrumentSans-SemiBold",
            "JetBrainsMono-Regular", "JetBrainsMono-Medium"
        ]
        let missing = expected.filter { UIFont(name: $0, size: 12) == nil }
        if !missing.isEmpty {
            print("[Warrant] fonts not registered, falling back to system: \(missing.joined(separator: ", "))")
        }
    }
}
