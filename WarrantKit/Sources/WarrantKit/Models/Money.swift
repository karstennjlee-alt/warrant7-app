import Foundation

/// An amount in integer minor units. There is no floating-point money anywhere in the model
/// layer — `$2,400.00` is `240_000`, and it only becomes a string at the view boundary.
public struct Money: Sendable, Hashable, Codable {
    public let minorUnits: Int
    public let currencyCode: String

    public init(minorUnits: Int, currencyCode: String = "USD") {
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode
    }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currencyCode == rhs.currencyCode, "cannot compare across currencies")
        return lhs.minorUnits < rhs.minorUnits
    }
}

extension Money: Comparable {}

public extension Money {
    /// Locale-aware formatting, for display only.
    func formatted(locale: Locale = .autoupdatingCurrent) -> String {
        let amount = Decimal(minorUnits) / 100
        return amount.formatted(.currency(code: currencyCode).locale(locale))
    }
}
