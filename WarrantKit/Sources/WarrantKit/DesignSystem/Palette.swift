import SwiftUI

/// Palette from `Warrant Mobile.dc.html`.
///
/// Quiet, near-neutral surfaces with exactly four meaningful colours: green for allowed and
/// verified, red for blocked and denied, ochre for waiting on a human, blue for the one thing
/// you can touch. Everything else is ink at three weights.
///
/// Each value is declared once as a hex literal in ``Ink/Hex`` and wrapped as a `Color` below,
/// so `ContrastTests` measures the same numbers the app renders rather than a copy of them.
public enum Ink {
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
    }

    /// The app canvas.
    public static let canvas = Color(hex: Hex.canvas)
    /// Screens that sit behind cards.
    public static let surface = Color(hex: Hex.surface)
    public static let card = Color(hex: Hex.card)

    public static let ink = Color(hex: Hex.ink)
    public static let soft = Color(hex: Hex.soft)
    public static let mute = Color(hex: Hex.mute)
    public static let line = Color(hex: Hex.line)
    public static let lineStrong = Color(hex: Hex.lineStrong)
    public static let fill = Color(hex: Hex.fill)

    public static let green = Color(hex: Hex.green)   // allowed, executed, verified
    public static let red = Color(hex: Hex.red)       // blocked, denied, failed
    public static let blue = Color(hex: Hex.blue)     // the only interactive accent

    /// Review, pending, expiring.
    ///
    /// A **fill**: the envelope band, status dots, the timer arc. It measures about 3.1:1 on a
    /// light surface — right for a shape, short of the 4.5:1 floor for prose. `ContrastTests`
    /// pins that, so promoting it to body text has to be a deliberate act.
    public static let ochre = Color(hex: Hex.ochre)
    /// The lighter middle band of the policy envelope.
    public static let ochreBand = Color(hex: Hex.ochreBand)

    /// Dark surface for the tamper lab's raw record.
    public static let terminal = Color(hex: Hex.terminal)
    public static let terminalText = Color(hex: Hex.terminalText)
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
