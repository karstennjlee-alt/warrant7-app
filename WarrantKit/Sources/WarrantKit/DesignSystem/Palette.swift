import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Palette from `Warrant Mobile.dc.html`, in two schemes.
///
/// Quiet, near-neutral surfaces with exactly four meaningful colours: green for allowed and
/// verified, red for blocked and denied, ochre for waiting on a human, blue for the one thing
/// you can touch. Everything else is ink at three weights.
///
/// §8 used to say light only, on the grounds that the paper metaphor requires paper and a
/// half-hearted dark mode reads worse than none. The objection was to a *half-hearted* one, so
/// dark is a full second scheme here rather than an inversion: it keeps the same four meanings
/// and the same three ink weights, and every pairing is measured by `ContrastTests` in both
/// schemes rather than in one.
///
/// Each value is declared once as a hex literal in ``Ink/Hex`` and ``Ink/HexDark`` and wrapped
/// as an adaptive `Color` below, so the tests measure the same numbers the app renders rather
/// than a copy of them.
public enum Ink {
    /// Light scheme. Paper.
    public enum Hex {
        public static let canvas: UInt32 = 0xF4F5F2
        public static let surface: UInt32 = 0xF7F8F6
        public static let card: UInt32 = 0xFFFFFF

        public static let ink: UInt32 = 0x14181C
        // Three tokens are nudged a hair darker than the design file, and only these three.
        // Measured against `surface`, the designed values land at 4.44:1 (soft), 4.42:1 (red)
        // and 2.42:1 (mute) — just under §11's 4.5:1 floor for text, and under even the 3:1
        // non-text floor for mute, which carries ids and timestamps people actually read.
        // The corrections are 1–2 units per channel and are not visible side by side;
        // `ContrastTests` measures them, so they cannot drift back.
        public static let soft: UInt32 = 0x6A737F      // design #6B7480
        public static let mute: UInt32 = 0x899099      // design #9AA2AC
        public static let line: UInt32 = 0xE6E8E4
        public static let lineStrong: UInt32 = 0xC2C8CE
        public static let fill: UInt32 = 0xF0F1EE

        public static let green: UInt32 = 0x1B7A5A
        public static let red: UInt32 = 0xCE3F2E       // design #D0402F
        public static let ochre: UInt32 = 0xB8801E
        public static let blue: UInt32 = 0x2B3BD6
        public static let ochreBand: UInt32 = 0xE8B44A

        public static let terminal: UInt32 = 0x14181C
        public static let terminalText: UInt32 = 0xC9D1D9

        /// Type on a filled ink, green or red control.
        public static let onSolid: UInt32 = 0xFFFFFF
        /// A broken link in the chain: the one red that means "this evidence failed", as
        /// distinct from `red`, which means a person or a policy said no.
        public static let broken: UInt32 = 0x6E1E18
        public static let brokenLine: UInt32 = 0xEFC9C4
        public static let brokenFill: UInt32 = 0xFDF3F2
        public static let warnFill: UInt32 = 0xFCF7EC
    }

    /// Dark scheme. Not an inversion — surfaces lift toward the viewer as they matter more,
    /// exactly as they do on paper, and the four meaningful hues are re-picked for a dark
    /// ground rather than reused and dimmed.
    public enum HexDark {
        public static let canvas: UInt32 = 0x0D1013
        public static let surface: UInt32 = 0x151A1F
        public static let card: UInt32 = 0x1C2229

        public static let ink: UInt32 = 0xE8EDF2
        public static let soft: UInt32 = 0xA3AEB9
        public static let mute: UInt32 = 0x7C8791
        public static let line: UInt32 = 0x2A323A
        public static let lineStrong: UInt32 = 0x3D4650
        public static let fill: UInt32 = 0x232B33

        public static let green: UInt32 = 0x4FD39B
        public static let red: UInt32 = 0xFF8071
        // Ochre is held under the 4.5:1 text floor on purpose in both schemes; see
        // `ContrastTests.ochreIsAFill`. On this ground that means a muted brass, not a
        // brighter amber — the brighter value measured 4.68:1 and would have promoted a
        // fill into something that looks like body text.
        public static let ochre: UInt32 = 0xA87C2B
        public static let blue: UInt32 = 0x8D9BFF
        public static let ochreBand: UInt32 = 0xE8B44A

        // The lab's raw record is already an inverted block on paper, so it barely moves.
        public static let terminal: UInt32 = 0x0B0E11
        public static let terminalText: UInt32 = 0xC9D1D9

        public static let onSolid: UInt32 = 0x0D1013
        public static let broken: UInt32 = 0xFF9A8C
        public static let brokenLine: UInt32 = 0x4A2622
        public static let brokenFill: UInt32 = 0x2A1A18
        public static let warnFill: UInt32 = 0x2A2418
    }

    /// The app canvas.
    public static let canvas = Color(light: Hex.canvas, dark: HexDark.canvas)
    /// Screens that sit behind cards.
    public static let surface = Color(light: Hex.surface, dark: HexDark.surface)
    public static let card = Color(light: Hex.card, dark: HexDark.card)

    public static let ink = Color(light: Hex.ink, dark: HexDark.ink)
    public static let soft = Color(light: Hex.soft, dark: HexDark.soft)
    public static let mute = Color(light: Hex.mute, dark: HexDark.mute)
    public static let line = Color(light: Hex.line, dark: HexDark.line)
    public static let lineStrong = Color(light: Hex.lineStrong, dark: HexDark.lineStrong)
    public static let fill = Color(light: Hex.fill, dark: HexDark.fill)

    public static let green = Color(light: Hex.green, dark: HexDark.green)   // allowed, executed, verified
    public static let red = Color(light: Hex.red, dark: HexDark.red)         // blocked, denied, failed
    public static let blue = Color(light: Hex.blue, dark: HexDark.blue)      // the only interactive accent

    /// Review, pending, expiring.
    ///
    /// A **fill**: the envelope band, status dots, the timer arc. It measures about 3.1:1 on a
    /// light surface and 4.3:1 on a dark one — right for a shape, short of the 4.5:1 floor for
    /// prose in both. `ContrastTests` pins that, so promoting it to body text has to be a
    /// deliberate act.
    public static let ochre = Color(light: Hex.ochre, dark: HexDark.ochre)
    /// The lighter middle band of the policy envelope.
    public static let ochreBand = Color(light: Hex.ochreBand, dark: HexDark.ochreBand)

    /// Dark surface for the tamper lab's raw record.
    public static let terminal = Color(light: Hex.terminal, dark: HexDark.terminal)
    public static let terminalText = Color(light: Hex.terminalText, dark: HexDark.terminalText)

    /// Type on a filled control. White on paper, near-black once the fill itself is pale.
    public static let onSolid = Color(light: Hex.onSolid, dark: HexDark.onSolid)

    /// A broken link in the chain, and the tinted card it sits in.
    public static let broken = Color(light: Hex.broken, dark: HexDark.broken)
    public static let brokenLine = Color(light: Hex.brokenLine, dark: HexDark.brokenLine)
    public static let brokenFill = Color(light: Hex.brokenFill, dark: HexDark.brokenFill)
    /// The wash behind an `UNTRUSTED_DEPENDS_ON_n` row: doubtful, not failed.
    public static let warnFill = Color(light: Hex.warnFill, dark: HexDark.warnFill)
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

    /// Resolves per scheme at render time, so a single token serves both and no view has to
    /// ask which one it is in.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #else
        // `swift test` runs on macOS, where the tests measure the hex values directly.
        self.init(hex: light)
        #endif
    }
}

public enum Metric {
    public static let cardRadius: CGFloat = 16
    public static let panelRadius: CGFloat = 18
    public static let rowRadius: CGFloat = 14
    public static let buttonRadius: CGFloat = 14
    public static let fieldRadius: CGFloat = 12
    public static let hairline: CGFloat = 1
    public static let gutter: CGFloat = 16

    /// The slide track, and the thumb that runs along it.
    public static let slideTrackHeight: CGFloat = 62
    public static let slideThumb: CGFloat = 52
    /// Deny, and every other full-width control. Comfortably past the 44pt touch minimum.
    public static let buttonHeight: CGFloat = 56
}
