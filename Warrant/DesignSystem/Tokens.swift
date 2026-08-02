import SwiftUI

/// The visual world is the **issued document**: security paper, hall passes, notary stamps,
/// perforated receipt tape, ink signatures. Institutional and physical, executed with software
/// precision.
///
/// Light appearance only, declared as `UIUserInterfaceStyle = Light` in Info.plist. The paper
/// metaphor requires paper, and a half-hearted dark mode would read worse than none. This is
/// deliberate — please do not "fix" it by adding a dark palette.
public enum Ink {
    public static let paper = Color(hex: 0xE9EDE6)      // pale safety green
    public static let paperDeep = Color(hex: 0xDDE3D9)
    public static let ink = Color(hex: 0x12161C)
    public static let inkSoft = Color(hex: 0x4C555E)
    public static let rule = Color(hex: 0xB7C0B3)
    public static let seal = Color(hex: 0x1D4B3C)       // ALLOW, EXECUTED, VERIFIED
    public static let stamp = Color(hex: 0xB8332A)      // BLOCK, DENIED, FAILED
    public static let pen = Color(hex: 0x23349B)        // the only interactive accent

    /// REVIEW, PENDING, EXPIRING — as fills, strokes, and rules.
    public static let ochre = Color(hex: 0xB57A21)

    /// The same ochre, darkened, for **text**.
    ///
    /// Measured against `paper`, the specified ochre lands at 3.07:1 — fine for a bar or a
    /// dot, short of the 4.5:1 body-text floor in §11. It carries the countdown under 30
    /// seconds and every REVIEW label, which are precisely the words nobody should have to
    /// squint at. This one measures 4.80:1. Ratios for the whole palette are asserted in
    /// `ContrastTests`, so a future palette edit that breaks the floor fails the build.
    public static let ochreText = Color(hex: 0x8C5D16)

    /// Broken evidence, as distinct from evidence of a bad outcome. Two different reds, two
    /// different meanings, and the ledger legend says so out loud (§5.4).
    public static let brokenEvidence = Color(hex: 0x6E1E18)
}

public extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

public enum Metric {
    /// Every document surface. Paper does not have rounded corners; this is the smallest
    /// radius that still reads as intentional rather than as an aliasing artefact.
    public static let documentRadius: CGFloat = 2
    /// The approval card is a card on a phone and should feel like one.
    public static let cardRadius: CGFloat = 16
    public static let hairline: CGFloat = 1
    public static let gutter: CGFloat = 20
    /// §5.1: at least 56pt tall, never below the 44pt touch minimum.
    public static let decisionButtonHeight: CGFloat = 60
}
