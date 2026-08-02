import Testing
import Foundation
@testable import WarrantKit

@Suite("RFC 8785 canonicalization")
struct CanonicalJSONTests {

    @Test("ECMAScript number serialization", arguments: [
        (0.0, "0"),
        (-0.0, "0"),
        (1.0, "1"),
        (-1.0, "-1"),
        (1.5, "1.5"),
        (0.1, "0.1"),
        (100.0, "100"),
        (240000.0, "240000"),
        (1e20, "100000000000000000000"),
        (1e21, "1e+21"),
        (1e-6, "0.000001"),
        (1e-7, "1e-7"),
        (9007199254740992.0, "9007199254740992"),
        (5e-324, "5e-324"),
        (1.7976931348623157e308, "1.7976931348623157e+308")
    ])
    func numbers(value: Double, expected: String) throws {
        #expect(try CanonicalJSON.serializeNumber(value) == expected)
    }

    @Test("NaN and infinity have no JSON form")
    func nonFiniteNumbersThrow() {
        #expect(throws: CanonicalJSONError.unrepresentableNumber(.infinity)) {
            try CanonicalJSON.serializeNumber(.infinity)
        }
        #expect(throws: (any Error).self) {
            try CanonicalJSON.serializeNumber(.nan)
        }
    }

    /// The RFC 8785 sorting example. The emoji is the point of it: its UTF-16 lead surrogate
    /// (0xD83D) sorts *before* U+FB33, while a naive scalar-value comparison puts it after.
    @Test("Members sort by UTF-16 code units, not scalar value")
    func utf16KeyOrdering() throws {
        let input: JSONValue = [
            "\u{20AC}": "Euro Sign",
            "\r": "Carriage Return",
            "\u{FB33}": "Hebrew Letter Dalet With Dagesh",
            "1": "One",
            "\u{1F600}": "Emoji: Grinning Face",
            "\u{0080}": "Control",
            "\u{00F6}": "Latin Small Letter O With Diaeresis"
        ]

        let expected = #"{"\r":"Carriage Return","1":"One","\#u{0080}":"Control","ö":"Latin Small Letter O With Diaeresis","€":"Euro Sign","😀":"Emoji: Grinning Face","דּ":"Hebrew Letter Dalet With Dagesh"}"#

        #expect(try CanonicalJSON.canonicalize(input) == expected)
    }

    @Test("Naive Swift string sorting would disagree")
    func swiftSortingIsNotUTF16Sorting() {
        let keys = ["\u{1F600}", "\u{FB33}"]
        #expect(keys.sorted() == ["\u{FB33}", "\u{1F600}"])
        #expect(CanonicalJSON.sortedKeys(of: ["\u{1F600}": .null, "\u{FB33}": .null])
                == ["\u{1F600}", "\u{FB33}"])
    }

    @Test("Only the mandated escapes are applied")
    func stringEscaping() throws {
        let control = "a\"b\\c\u{08}\u{09}\u{0A}\u{0C}\u{0D}\u{01}\u{00E9}"
        let expected = #"{"k":"a\"b\\c\b\t\n\f\r\u0001\#u{00E9}"}"#
        #expect(try CanonicalJSON.canonicalize(["k": .string(control)]) == expected)
    }

    @Test("No insignificant whitespace survives a round trip")
    func whitespaceIsDropped() throws {
        let parsed = try JSONValue.parse("""
        {
          "b" : [ 1 , 2 ,  { "z" : true , "a" : null } ],
          "a" : "x"
        }
        """)
        #expect(try CanonicalJSON.canonicalize(parsed) == #"{"a":"x","b":[1,2,{"a":null,"z":true}]}"#)
    }

    @Test("Array order is data and is preserved")
    func arraysKeepOrder() throws {
        let parsed = try JSONValue.parse(#"["c","a","b"]"#)
        #expect(try CanonicalJSON.canonicalize(parsed) == #"["c","a","b"]"#)
    }

    @Test("Booleans parse as booleans, not as 0 and 1")
    func boolsSurviveNSNumberBridging() throws {
        let parsed = try JSONValue.parse(#"{"t":true,"f":false,"n":1,"z":0}"#)
        #expect(try CanonicalJSON.canonicalize(parsed) == #"{"f":false,"n":1,"t":true,"z":0}"#)
    }
}
