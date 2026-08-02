import Testing
import Foundation
@testable import WarrantKit

/// §11 sets a 4.5:1 contrast floor for text. A floor nobody measures is a preference, so this
/// measures it against the hex values the app actually renders — and fails the build if a
/// future palette edit drops below it.
///
/// Both schemes are measured. A dark mode that is only eyeballed is exactly the half-hearted
/// one §8 warned about, so every case here runs twice.
@Suite("Palette contrast")
struct ContrastTests {

    /// WCAG 2.1 relative luminance, computed from the sRGB hex rather than from a rendered
    /// `Color`, so it runs on macOS where there is no UIKit.
    static func luminance(_ hex: UInt32) -> Double {
        func linear(_ byte: UInt32) -> Double {
            let channel = Double(byte) / 255
            return channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear((hex >> 16) & 0xFF)
            + 0.7152 * linear((hex >> 8) & 0xFF)
            + 0.0722 * linear(hex & 0xFF)
    }

    static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// One scheme's values, so each test states its expectation once and runs it twice.
    struct Scheme {
        let name: String
        let canvas, surface, card: UInt32
        let ink, soft, mute: UInt32
        let green, red, ochre, blue: UInt32
        let terminal, terminalText: UInt32
        let onSolid, broken, brokenFill: UInt32

        /// The two surfaces text is ever drawn on. `canvas` is app chrome behind the tab bar
        /// and between screens — every screen paints `card` or `surface` before setting any
        /// type — so including it here would be testing a pairing that never renders.
        var surfaces: [(String, UInt32)] { [("card", card), ("surface", surface)] }

        var textColours: [(String, UInt32)] {
            [("ink", ink), ("soft", soft), ("green", green), ("red", red), ("blue", blue)]
        }
    }

    static let light = Scheme(
        name: "light",
        canvas: Ink.Hex.canvas, surface: Ink.Hex.surface, card: Ink.Hex.card,
        ink: Ink.Hex.ink, soft: Ink.Hex.soft, mute: Ink.Hex.mute,
        green: Ink.Hex.green, red: Ink.Hex.red, ochre: Ink.Hex.ochre, blue: Ink.Hex.blue,
        terminal: Ink.Hex.terminal, terminalText: Ink.Hex.terminalText,
        onSolid: Ink.Hex.onSolid, broken: Ink.Hex.broken, brokenFill: Ink.Hex.brokenFill
    )

    static let dark = Scheme(
        name: "dark",
        canvas: Ink.HexDark.canvas, surface: Ink.HexDark.surface, card: Ink.HexDark.card,
        ink: Ink.HexDark.ink, soft: Ink.HexDark.soft, mute: Ink.HexDark.mute,
        green: Ink.HexDark.green, red: Ink.HexDark.red, ochre: Ink.HexDark.ochre, blue: Ink.HexDark.blue,
        terminal: Ink.HexDark.terminal, terminalText: Ink.HexDark.terminalText,
        onSolid: Ink.HexDark.onSolid, broken: Ink.HexDark.broken, brokenFill: Ink.HexDark.brokenFill
    )

    static let schemes = [light, dark]

    @Test("Nothing sets type directly on the canvas colour", arguments: schemes)
    func canvasIsChrome(scheme: Scheme) {
        // Guards the assumption above: if canvas and surface ever converge, the distinction
        // stops being meaningful and this file needs revisiting.
        #expect(scheme.canvas != scheme.surface, "in \(scheme.name)")
    }

    @Test("Every text colour clears 4.5:1 on every surface", arguments: schemes)
    func textColours(scheme: Scheme) {
        for (name, hex) in scheme.textColours {
            for (surfaceName, surface) in scheme.surfaces {
                let measured = Self.ratio(hex, surface)
                #expect(
                    measured >= 4.5,
                    "\(scheme.name): \(name) on \(surfaceName) is \(String(format: "%.2f", measured)):1"
                )
            }
        }
    }

    /// `mute` carries mono metadata — ids, key fragments, timestamps — never prose.
    @Test("The muted tone clears the 3:1 non-text floor", arguments: schemes)
    func mutedTone(scheme: Scheme) {
        let measured = Self.ratio(scheme.mute, scheme.card)
        #expect(measured >= 3.0, "\(scheme.name): \(String(format: "%.2f", measured)):1")
    }

    /// Ochre is a fill, and this test is the reason it stays one in both schemes.
    @Test("Ochre stays a fill rather than drifting into body text", arguments: schemes)
    func ochreIsAFill(scheme: Scheme) {
        let measured = Self.ratio(scheme.ochre, scheme.card)
        #expect(measured >= 3.0, "\(scheme.name): still legible as a shape")
        #expect(measured < 4.5, "\(scheme.name): if this ever passes, ochre may be promoted to body text")
    }

    /// The lab's inverted block has to be readable too.
    @Test("The terminal block clears the floor in reverse", arguments: schemes)
    func terminalBlock(scheme: Scheme) {
        #expect(Self.ratio(scheme.terminalText, scheme.terminal) >= 4.5, "in \(scheme.name)")
    }

    /// Type on a filled ink control. In dark the fill is pale, so white would vanish — this is
    /// the pairing that catches an `onSolid` left behind at white.
    @Test("Type on a solid control clears the floor", arguments: schemes)
    func onSolidControls(scheme: Scheme) {
        for (name, fill) in [("ink", scheme.ink), ("green", scheme.green)] {
            let measured = Self.ratio(scheme.onSolid, fill)
            #expect(
                measured >= 4.5,
                "\(scheme.name): onSolid on \(name) is \(String(format: "%.2f", measured)):1"
            )
        }
    }

    /// A broken link is the one thing on the ledger nobody may miss.
    @Test("A broken link reads on its own tinted card", arguments: schemes)
    func brokenLink(scheme: Scheme) {
        let measured = Self.ratio(scheme.broken, scheme.brokenFill)
        #expect(measured >= 4.5, "\(scheme.name): \(String(format: "%.2f", measured)):1")
    }
}
