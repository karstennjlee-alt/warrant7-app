import Testing
import Foundation
@testable import WarrantKit

/// T-01. The single most important test in the suite.
///
/// The device and the gateway must canonicalize identically or honest evidence will look
/// forged on stage. The vectors are read from a fixture file rather than written in Swift, so
/// the web repo's fixture can replace it wholesale without touching this code.
@Suite("T-01 · Canonical JSON golden vectors")
struct GoldenVectorTests {

    struct Vector: Decodable {
        let name: String
        let why: String
        let canonical: String
    }

    static func fixture() throws -> (vectors: [Vector], inputs: [JSONValue]) {
        guard let url = Bundle.module.url(forResource: "canonical-vectors", withExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: "canonical-vectors", withExtension: "json") else {
            throw Failure.fixtureMissing
        }
        let data = try Data(contentsOf: url)
        let vectors = try JSONDecoder().decode(Document.self, from: data).vectors
        // Inputs are arbitrary JSON, so they are read through JSONValue rather than Decodable.
        guard case .array(let raw)? = try JSONValue.parse(data)["vectors"] else {
            throw Failure.fixtureMissing
        }
        let inputs = raw.compactMap { $0["input"] }
        return (vectors, inputs)
    }

    struct Document: Decodable { let vectors: [Vector] }
    enum Failure: Error { case fixtureMissing }

    @Test("Every golden vector canonicalizes byte for byte")
    func goldenVectors() throws {
        let (vectors, inputs) = try Self.fixture()

        #expect(vectors.count >= 8, "T-01 calls for at least eight vectors")
        #expect(vectors.count == inputs.count)

        for (vector, input) in zip(vectors, inputs) {
            let produced = try CanonicalJSON.canonicalize(input)
            #expect(produced == vector.canonical, "vector '\(vector.name)' — \(vector.why)")
        }
    }

    @Test("Canonical output is what gets hashed, as UTF-8")
    func canonicalBytesAreUTF8() throws {
        let value: JSONValue = ["k": "café"]
        let bytes = try CanonicalJSON.canonicalBytes(value)
        #expect(bytes == Data(#"{"k":"café"}"#.utf8))
    }
}

@Suite("RFC 8785 mechanics")
struct CanonicalJSONTests {

    @Test("ECMAScript number serialization", arguments: [
        (0.0, "0"), (-0.0, "0"), (1.0, "1"), (-1.0, "-1"), (1.5, "1.5"), (0.1, "0.1"),
        (100.0, "100"), (240000.0, "240000"), (1e20, "100000000000000000000"), (1e21, "1e+21"),
        (1e-6, "0.000001"), (1e-7, "1e-7"), (9007199254740992.0, "9007199254740992"),
        (5e-324, "5e-324"), (1.7976931348623157e308, "1.7976931348623157e+308")
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

    /// The trap that `JSONEncoder.sortedKeys` falls into: Swift compares strings by scalar
    /// value, JCS by UTF-16 code unit, and they disagree for anything outside the BMP.
    @Test("Naive Swift string sorting would disagree")
    func swiftSortingIsNotUTF16Sorting() {
        #expect(["\u{1F600}", "\u{FB33}"].sorted() == ["\u{FB33}", "\u{1F600}"])
        #expect(CanonicalJSON.sortedKeys(of: ["\u{1F600}": .null, "\u{FB33}": .null])
                == ["\u{1F600}", "\u{FB33}"])
    }

    @Test("Array order is data and is preserved")
    func arraysKeepOrder() throws {
        #expect(try CanonicalJSON.canonicalize(JSONValue.parse(#"["c","a","b"]"#)) == #"["c","a","b"]"#)
    }
}
