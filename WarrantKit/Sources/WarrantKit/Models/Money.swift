import Foundation

/// An amount in integer minor units. There is no floating-point money anywhere in the model
/// layer — `$2,400.00` is `240_000`, and it becomes a string only at the view boundary.
///
/// Minor units are not always hundredths. JPY and KRW have no fractional part at all, so the
/// exponent is looked up per currency rather than assumed to be 2.
public struct Money: Sendable, Hashable, Codable {
    public let minorUnits: Int
    public let currencyCode: String

    public init(minorUnits: Int, currencyCode: String = "USD") {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode
    }

    /// Number of decimal places this currency subdivides into: 2 for USD, 0 for JPY, 3 for KWD.
    public var fractionDigits: Int {
        Self.fractionDigits(for: currencyCode)
    }

    public var decimalAmount: Decimal {
        Decimal(minorUnits) / pow(Decimal(10), fractionDigits)
    }

    private static let overrides: [String: Int] = [
        "JPY": 0, "KRW": 0, "VND": 0, "CLP": 0, "ISK": 0, "XAF": 0, "XOF": 0, "XPF": 0,
        "BIF": 0, "DJF": 0, "GNF": 0, "KMF": 0, "MGA": 0, "PYG": 0, "RWF": 0, "UGX": 0,
        "UYI": 0, "VUV": 0,
        "BHD": 3, "IQD": 3, "JOD": 3, "KWD": 3, "LYD": 3, "OMR": 3, "TND": 3
    ]

    static func fractionDigits(for code: String) -> Int {
        overrides[code.uppercased()] ?? 2
    }
}

extension Money: Comparable {
    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currencyCode == rhs.currencyCode, "cannot compare across currencies")
        return lhs.minorUnits < rhs.minorUnits
    }
}

public extension Money {
    /// Display only. Never call this anywhere a value is compared, hashed, or transmitted.
    func formatted(locale: Locale = .autoupdatingCurrent) -> String {
        decimalAmount.formatted(
            .currency(code: currencyCode)
                .precision(.fractionLength(fractionDigits))
                .locale(locale)
        )
    }

    /// Spelled out for VoiceOver, so the approval button announces its consequence rather
    /// than reading a glyph salad. `240_000` → "two thousand four hundred dollars".
    func spelledOut(locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currencyPlural
        formatter.locale = locale
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = fractionDigits

        let spell = NumberFormatter()
        spell.numberStyle = .spellOut
        spell.locale = locale

        let whole = minorUnits / Int(pow(10.0, Double(fractionDigits)))
        let unitName = formatter.string(from: NSNumber(value: 1))?
            .replacingOccurrences(of: "1", with: "")
            .trimmingCharacters(in: .whitespaces) ?? currencyCode
        let pluralName = formatter.string(from: NSNumber(value: 2))?
            .replacingOccurrences(of: "2", with: "")
            .trimmingCharacters(in: .whitespaces) ?? currencyCode

        let spelled = spell.string(from: NSNumber(value: whole)) ?? "\(whole)"
        return "\(spelled) \(whole == 1 ? unitName : pluralName)"
    }
}
