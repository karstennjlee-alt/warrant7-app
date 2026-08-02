import SwiftUI
import UIKit

/// The rule that carries the whole visual system:
///
/// **Anything the system computed is set in mono. Anything a human wrote is set in Public Sans.**
///
/// Amounts, hashes, digests, signatures, timestamps, state names, event types and sequence
/// numbers are mono. Explanations, labels and buttons are Public Sans. Archivo Expanded is
/// reserved for the action line and screen titles — the institutional voice.
public enum WarrantType {
    case actionLine     // the one sentence, largest thing on screen
    case title
    case headline
    case body
    case callout
    case label          // small uppercase field labels
    case monoLarge      // amounts
    case mono           // digests, timestamps, state names
    case monoSmall

    var family: Family {
        switch self {
        case .actionLine, .title: .display
        case .headline, .body, .callout, .label: .text
        case .monoLarge, .mono, .monoSmall: .mono
        }
    }

    var size: CGFloat {
        switch self {
        case .actionLine: 34
        case .title: 26
        case .headline: 19
        case .body: 16
        case .callout: 14
        case .label: 11
        case .monoLarge: 30
        case .mono: 14
        case .monoSmall: 11
        }
    }

    var weight: Weight {
        switch self {
        case .actionLine: .bold
        case .title: .semibold
        case .headline: .semibold
        case .body: .regular
        case .callout: .regular
        case .label: .medium
        case .monoLarge: .medium
        case .mono: .regular
        case .monoSmall: .medium
        }
    }

    /// Which metric drives Dynamic Type scaling. Amounts scale with `.body` rather than with
    /// `.largeTitle` so that a large accessibility size grows them without pushing the action
    /// line off screen.
    var textStyle: UIFont.TextStyle {
        switch self {
        case .actionLine: .largeTitle
        case .title: .title2
        case .headline: .headline
        case .body, .monoLarge: .body
        case .callout, .mono: .callout
        case .label, .monoSmall: .caption1
        }
    }

    enum Family { case display, text, mono }
    enum Weight { case regular, medium, semibold, bold }

    var postScriptName: String {
        switch (family, weight) {
        case (.display, .bold): "ArchivoExpanded-Bold"
        case (.display, _): "ArchivoExpanded-SemiBold"
        case (.text, .semibold): "PublicSans-SemiBold"
        case (.text, .medium): "PublicSans-Medium"
        case (.text, _): "PublicSans-Regular"
        case (.mono, .medium), (.mono, .semibold), (.mono, .bold): "JetBrainsMono-Medium"
        case (.mono, _): "JetBrainsMono-Regular"
        }
    }
}

public extension Font {
    /// Scales with Dynamic Type through `UIFontMetrics`, so the largest accessibility sizes
    /// grow the text instead of clipping it.
    static func warrant(_ style: WarrantType) -> Font {
        Font(WarrantFonts.uiFont(style))
    }
}

public enum WarrantFonts {
    static func uiFont(_ style: WarrantType) -> UIFont {
        let base = UIFont(name: style.postScriptName, size: style.size) ?? fallback(style)
        return UIFontMetrics(forTextStyle: style.textStyle).scaledFont(for: base)
    }

    /// If a bundled font failed to register, fall back to a system face with the right shape
    /// rather than rendering nothing. A missing font should degrade, not disappear.
    private static func fallback(_ style: WarrantType) -> UIFont {
        let weight: UIFont.Weight = switch style.weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
        if style.family == .mono {
            return UIFont.monospacedSystemFont(ofSize: style.size, weight: weight)
        }
        return UIFont.systemFont(ofSize: style.size, weight: weight)
    }

    /// Called once at launch so a missing font shows up in the console rather than as a
    /// mysteriously plain screen.
    public static func verifyRegistration() {
        let expected = [
            "ArchivoExpanded-SemiBold", "ArchivoExpanded-Bold",
            "PublicSans-Regular", "PublicSans-Medium", "PublicSans-SemiBold",
            "JetBrainsMono-Regular", "JetBrainsMono-Medium"
        ]
        let missing = expected.filter { UIFont(name: $0, size: 12) == nil }
        if !missing.isEmpty {
            print("[Warrant] fonts not registered, falling back to system: \(missing.joined(separator: ", "))")
        }
    }
}

public extension View {
    /// Field labels: small, uppercase, tracked out, in the muted ink.
    func fieldLabel() -> some View {
        self.font(.warrant(.label))
            .tracking(0.08 * 11)
            .textCase(.uppercase)
            .foregroundStyle(Ink.inkSoft)
    }
}
