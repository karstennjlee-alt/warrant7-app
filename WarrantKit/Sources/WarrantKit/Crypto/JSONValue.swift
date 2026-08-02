import Foundation

/// A JSON document modelled the way RFC 8785 models one.
///
/// Numbers are held as `Double` on purpose: JCS defines canonical number output in terms of
/// IEEE-754 binary64, so a parse-then-re-emit round trip has to go through a double to match
/// the spec. Integers beyond 2^53 cannot survive that and are rejected at construction rather
/// than silently rounded.
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

public extension JSONValue {
    /// Integer convenience. Traps nothing — values outside the exactly-representable range
    /// throw at canonicalization time via ``CanonicalJSONError/unrepresentableNumber(_:)``.
    static func int(_ value: Int) -> JSONValue { .number(Double(value)) }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

// MARK: - Parsing

public extension JSONValue {
    /// Parse untrusted JSON bytes into the canonicalizable model.
    ///
    /// Uses `JSONSerialization` for the grammar, then narrows `NSNumber` to `Bool`/`Double`.
    static func parse(_ data: Data) throws -> JSONValue {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try convert(object)
    }

    static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }

    private static func convert(_ object: Any) throws -> JSONValue {
        switch object {
        case is NSNull:
            return .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            return .number(number.doubleValue)
        case let string as String:
            return .string(string)
        case let array as [Any]:
            return .array(try array.map(convert))
        case let dictionary as [String: Any]:
            var result: [String: JSONValue] = [:]
            result.reserveCapacity(dictionary.count)
            for (key, value) in dictionary { result[key] = try convert(value) }
            return .object(result)
        default:
            throw CanonicalJSONError.unsupportedValue(String(describing: type(of: object)))
        }
    }

    /// Read a member of an object, or `nil` if this is not an object or the key is absent.
    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members[key]
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    /// Returns a copy of an object with the named members removed. Non-objects pass through.
    func removingKeys(_ keys: some Sequence<String>) -> JSONValue {
        guard case .object(var members) = self else { return self }
        for key in keys { members.removeValue(forKey: key) }
        return .object(members)
    }
}
