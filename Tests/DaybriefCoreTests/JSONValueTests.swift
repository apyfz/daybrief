@testable import DaybriefCore
import Foundation
import Testing

@Suite("JSONValue")
struct JSONValueTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Test("decodes each JSON kind into the matching case")
    func decodesEachKind() throws {
        let json = #"""
        {
          "n": null,
          "b": true,
          "i": 42,
          "f": 3.5,
          "s": "hello",
          "arr": [1, "two", false],
          "obj": { "nested": "value" }
        }
        """#
        let value = try decoder.decode(JSONValue.self, from: Data(json.utf8))

        #expect(value["n"]?.isNull == true)
        #expect(value["b"]?.bool == true)
        #expect(value["i"]?.int == 42)
        #expect(value["f"]?.double == 3.5)
        #expect(value["s"]?.string == "hello")
        #expect(value["arr"]?.array?.count == 3)
        #expect(value["arr"]?[0]?.int == 1)
        #expect(value["arr"]?[1]?.string == "two")
        #expect(value["arr"]?[2]?.bool == false)
        #expect(value["obj"]?["nested"]?.string == "value")
    }

    @Test("typed accessors return nil for mismatched cases")
    func accessorsAreTypeSafe() {
        let s: JSONValue = "text"
        #expect(s.int == nil)
        #expect(s.bool == nil)
        #expect(s.array == nil)
        #expect(s.object == nil)

        let f: JSONValue = .number(2.5)
        #expect(f.int == nil) // not a whole number
        #expect(f.double == 2.5)

        #expect((JSONValue.null).isNull)
        #expect(JSONValue.string("x")["missing"] == nil)
        #expect(JSONValue.array(["a"])[5] == nil)
    }

    @Test("encode → decode round-trips a nested value")
    func roundTrips() throws {
        let original: JSONValue = [
            "schema": "json_schema",
            "strict": true,
            "props": ["a", 1, 2.5, .null],
            "nested": ["count": 3],
        ]
        let data = try encoder.encode(original)
        let restored = try decoder.decode(JSONValue.self, from: data)
        #expect(restored == original)
    }

    @Test("integer literals survive a Double round-trip exactly")
    func integerExactness() throws {
        let original: JSONValue = ["big": .number(9_007_199_254_740_992)] // 2^53
        let restored = try decoder.decode(JSONValue.self, from: encoder.encode(original))
        #expect(restored["big"]?.int == 9_007_199_254_740_992)
    }
}
