import Foundation

public enum CanonicalJSONError: Error, Equatable, Sendable {
    /// NaN and the infinities have no JSON representation.
    case unrepresentableNumber(Double)
    /// A value `JSONSerialization` produced that this model does not cover.
    case unsupportedValue(String)
}

/// RFC 8785 JSON Canonicalization Scheme.
///
/// Three rules do the work: object members are sorted by the UTF-16 code units of their names,
/// no insignificant whitespace is emitted, and numbers are printed with the ECMAScript
/// `Number::toString` algorithm so that two implementations agree byte for byte.
///
/// The output is what gets hashed. If this is wrong, every digest in the product is wrong, so
/// it is deliberately written out longhand rather than delegated to `JSONEncoder`
/// (whose `.sortedKeys` sorts by `String` ordering, not UTF-16 code units, and whose number
/// output is not ECMAScript's).
public enum CanonicalJSON {

    public static func canonicalize(_ value: JSONValue) throws -> String {
        var output = ""
        try write(value, into: &output)
        return output
    }

    /// The bytes that actually get hashed and signed.
    public static func canonicalBytes(_ value: JSONValue) throws -> Data {
        Data(try canonicalize(value).utf8)
    }

    // MARK: - Serialization

    private static func write(_ value: JSONValue, into output: inout String) throws {
        switch value {
        case .null:
            output += "null"
        case .bool(let flag):
            output += flag ? "true" : "false"
        case .number(let number):
            output += try serializeNumber(number)
        case .string(let string):
            writeString(string, into: &output)
        case .array(let elements):
            output += "["
            for (index, element) in elements.enumerated() {
                if index > 0 { output += "," }
                try write(element, into: &output)
            }
            output += "]"
        case .object(let members):
            output += "{"
            for (index, key) in sortedKeys(of: members).enumerated() {
                if index > 0 { output += "," }
                writeString(key, into: &output)
                output += ":"
                try write(members[key]!, into: &output)
            }
            output += "}"
        }
    }

    /// RFC 8785 §3.2.3: sort by the UTF-16 code units of the member name, not by grapheme or
    /// by Swift's default `String` collation.
    static func sortedKeys(of members: [String: JSONValue]) -> [String] {
        members.keys.sorted { left, right in
            var l = left.utf16.makeIterator()
            var r = right.utf16.makeIterator()
            while true {
                switch (l.next(), r.next()) {
                case (nil, nil): return false
                case (nil, _): return true
                case (_, nil): return false
                case (let a?, let b?):
                    if a != b { return a < b }
                }
            }
        }
    }

    /// RFC 8785 §3.2.2.2: escape only what must be escaped, and use the short forms where they
    /// exist. Everything else, including non-ASCII, is emitted literally as UTF-8.
    static func writeString(_ string: String, into output: inout String) {
        output += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\u{08}": output += "\\b"
            case "\u{09}": output += "\\t"
            case "\u{0A}": output += "\\n"
            case "\u{0C}": output += "\\f"
            case "\u{0D}": output += "\\r"
            default:
                if scalar.value < 0x20 {
                    output += String(format: "\\u%04x", scalar.value)
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        output += "\""
    }

    // MARK: - Numbers

    /// ECMAScript `Number::toString`, which RFC 8785 §3.2.2.3 adopts wholesale.
    ///
    /// Swift's `Double.description` already gives the shortest round-tripping digit string, so
    /// the work here is re-laying-out those digits under ECMAScript's placement rules: plain
    /// decimal in the exponent window `(-6, 21]`, scientific outside it.
    static func serializeNumber(_ value: Double) throws -> String {
        guard value.isFinite else { throw CanonicalJSONError.unrepresentableNumber(value) }
        if value == 0 { return "0" }   // RFC 8785: -0 canonicalizes to "0"
        if value < 0 { return "-" + (try serializeNumber(-value)) }

        let (digits, pointPosition) = shortestDigits(of: value)
        let k = digits.count
        let n = pointPosition   // value == 0.<digits> * 10^n

        if k <= n && n <= 21 {
            return digits + String(repeating: "0", count: n - k)
        }
        if 0 < n && n <= 21 {
            let index = digits.index(digits.startIndex, offsetBy: n)
            return String(digits[..<index]) + "." + String(digits[index...])
        }
        if -6 < n && n <= 0 {
            return "0." + String(repeating: "0", count: -n) + digits
        }
        let exponent = n - 1
        let sign = exponent < 0 ? "-" : "+"
        let mantissa = k == 1
            ? digits
            : String(digits.first!) + "." + String(digits.dropFirst())
        return mantissa + "e" + sign + String(abs(exponent))
    }

    /// Decompose `Double.description` into a bare digit string and the decimal point position,
    /// such that the value equals `0.<digits> * 10^pointPosition`.
    private static func shortestDigits(of value: Double) -> (digits: String, pointPosition: Int) {
        let description = "\(value)"
        let parts = description.split(separator: "e", omittingEmptySubsequences: false)
        let mantissa = String(parts[0])
        let exponent = parts.count > 1 ? Int(parts[1]) ?? 0 : 0

        var digits = ""
        var pointPosition = 0
        var seenPoint = false
        for character in mantissa {
            if character == "." { seenPoint = true; continue }
            digits.append(character)
            if !seenPoint { pointPosition += 1 }
        }
        pointPosition += exponent

        // Leading zeros shift the point left; trailing zeros are not part of the shortest form.
        while digits.count > 1 && digits.hasPrefix("0") {
            digits.removeFirst()
            pointPosition -= 1
        }
        while digits.count > 1 && digits.hasSuffix("0") {
            digits.removeLast()
        }
        return (digits, pointPosition)
    }
}
