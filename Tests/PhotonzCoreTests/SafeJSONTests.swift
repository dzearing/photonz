import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Writing a reading out as JSON never takes the app down. `JSONSerialization`
/// answers a NaN or an infinity by raising an Objective-C exception, which
/// `try?` does not catch; raised inside a Swift task it left the main thread's
/// executor record pointing at a dead frame, and the probe crashed at the next
/// main-actor check (2026-10-02, a recording drill whose first frame never came
/// wrote NaN; the crash read as MenuBarArranger and MainThreadMeter).
struct SafeJSONTests {

    private func decode(_ data: Data?) throws -> [String: Any] {
        let data = try #require(data)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("A reading that is not a number is written as null, not thrown")
    func notANumberBecomesNull() throws {
        let object: [String: Any] = ["median": Double.nan, "runs": 3]
        let back = try decode(SafeJSON.data(from: object))
        #expect(back["median"] is NSNull)
        #expect(back["runs"] as? Int == 3)
    }

    @Test("Infinity either way, and a CGFloat or Float NaN, are written as null")
    func infinitiesAndOtherFloatsBecomeNull() throws {
        let object: [String: Any] = [
            "up": Double.infinity, "down": -Double.infinity,
            "cg": CGFloat.nan, "float": Float.nan,
        ]
        let back = try decode(SafeJSON.data(from: object))
        for key in ["up", "down", "cg", "float"] { #expect(back[key] is NSNull, "\(key)") }
    }

    @Test("Bad numbers deep in arrays and dictionaries are found, good ones kept as they were")
    func nestedValuesAreCleaned() throws {
        let object: [String: Any] = [
            "readings": [["ms": Double.nan, "landed": true], ["ms": 12.5, "landed": false]],
            "samples": [1.0, Double.nan, 3.0],
        ]
        let back = try decode(SafeJSON.data(from: object))
        let readings = try #require(back["readings"] as? [[String: Any]])
        #expect(readings[0]["ms"] is NSNull)
        #expect(readings[0]["landed"] as? Bool == true)
        #expect(readings[1]["ms"] as? Double == 12.5)
        let samples = try #require(back["samples"] as? [Any])
        #expect(samples.count == 3)
        #expect(samples[1] is NSNull)
        #expect(samples[2] as? Double == 3.0)
    }

    @Test("Something JSON cannot hold at all gives no data instead of raising")
    func unwritableGivesNil() {
        #expect(SafeJSON.data(from: ["when": Date()]) == nil)
        #expect(SafeJSON.data(from: "a bare string is not a top level object") == nil)
    }

    @Test("Writing options are honoured")
    func optionsAreKept() throws {
        let data = try #require(SafeJSON.data(from: ["b": 1, "a": 2], options: [.sortedKeys]))
        #expect(String(decoding: data, as: UTF8.self) == #"{"a":2,"b":1}"#)
    }
}
