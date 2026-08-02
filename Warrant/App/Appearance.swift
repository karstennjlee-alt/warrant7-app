import SwiftUI

/// Light, dark, or whatever the phone is doing.
///
/// §8 called for light only, on the grounds that a half-hearted dark mode reads worse than
/// none. Dark is a full second scheme in ``Ink`` rather than an inversion, and it is measured
/// by `ContrastTests` on the same floors, so the objection no longer applies. The default
/// stays `.system`: the phone already knows, and a product about not surprising people is a
/// poor place to override it.
public enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` hands the decision back to the system, which is not the same as picking light.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
