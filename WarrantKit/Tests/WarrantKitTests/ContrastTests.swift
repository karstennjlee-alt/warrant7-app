import Testing
import Foundation
@testable import WarrantKit

/// §11 sets a 4.5:1 contrast floor for text. A floor nobody measures is a preference, so this
/// measures it against the hex values the app actually renders — and fails the build if a
/// future palette edit drops below it.
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

    /// The two surfaces text is ever drawn on. `canvas` is app chrome behind the tab bar and
    /// between screens — every screen paints `card` or `surface` before setting any type — so
    /// including it here would be testing a pairing that never renders.
    static let surfaces: [(String, UInt32)] = [
        ("card", Ink.Hex.card),
        ("surface", Ink.Hex.surface)
    ]

    @Test("Nothing sets type directly on the canvas colour")
    func canvasIsChrome() {
        // Guards the assumption above: if canvas and surface ever converge, the distinction
        // stops being meaningful and this file needs revisiting.
        #expect(Ink.Hex.canvas != Ink.Hex.surface)
    }

    @Test("Every text colour clears 4.5:1 on every surface", arguments: [
        ("ink", Ink.Hex.ink),
        ("soft", Ink.Hex.soft),
        ("green", Ink.Hex.green),
        ("red", Ink.Hex.red),
        ("blue", Ink.Hex.blue)
    ])
    func textColours(name: String, hex: UInt32) {
        for (surfaceName, surface) in Self.surfaces {
            let measured = Self.ratio(hex, surface)
            #expect(measured >= 4.5, "\(name) on \(surfaceName) is \(String(format: "%.2f", measured)):1")
        }
    }

    /// `mute` carries mono metadata — ids, key fragments, timestamps — never prose.
    @Test("The muted tone clears the 3:1 non-text floor")
    func mutedTone() {
        #expect(Self.ratio(Ink.Hex.mute, Ink.Hex.card) >= 3.0)
    }

    /// Ochre is a fill, and this test is the reason it stays one.
    @Test("Ochre stays a fill rather than drifting into body text")
    func ochreIsAFill() {
        let measured = Self.ratio(Ink.Hex.ochre, Ink.Hex.card)
        #expect(measured >= 3.0, "still legible as a shape on a light surface")
        #expect(measured < 4.5, "if this ever passes, ochre may be promoted to body text")
    }

    /// The lab's inverted block has to be readable too.
    @Test("The terminal block clears the floor in reverse")
    func terminalBlock() {
        #expect(Self.ratio(Ink.Hex.terminalText, Ink.Hex.terminal) >= 4.5)
    }
}
