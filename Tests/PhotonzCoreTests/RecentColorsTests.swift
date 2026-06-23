import Foundation
import Testing
import PhotonzCore

@Suite("RecentColors")
struct RecentColorsTests {

    @Test func startsEmpty() {
        #expect(RecentColors().colors.isEmpty)
    }

    @Test func recordPrependsMostRecent() {
        var recents = RecentColors()
        recents.record(hex: "#FF0000")
        recents.record(hex: "#00FF00")
        #expect(recents.colors == ["#00FF00", "#FF0000"])
    }

    @Test func recordingExistingMovesToFrontWithoutDuplicating() {
        var recents = RecentColors()
        recents.record(hex: "#FF0000")
        recents.record(hex: "#00FF00")
        recents.record(hex: "#FF0000")
        #expect(recents.colors == ["#FF0000", "#00FF00"])
    }

    @Test func dedupeIsCaseInsensitive() {
        var recents = RecentColors()
        recents.record(hex: "#ff0000")
        recents.record(hex: "#FF0000")
        #expect(recents.colors.count == 1)
        // Canonicalized to uppercase.
        #expect(recents.colors == ["#FF0000"])
    }

    @Test func capsAtTen() {
        var recents = RecentColors()
        for i in 0..<15 {
            recents.record(hex: String(format: "#%06X", i * 0x010101))
        }
        #expect(recents.colors.count == 10)
        // The 10 most recent survive; the oldest five are evicted.
        #expect(recents.colors.first == String(format: "#%06X", 14 * 0x010101))
    }

    @Test func malformedHexIsIgnored() {
        var recents = RecentColors()
        recents.record(hex: "not a color")
        recents.record(hex: "#12345")
        recents.record(hex: "")
        #expect(recents.colors.isEmpty)
    }

    @Test func eightDigitAlphaHexIsRecordedCanonicallyAsSixDigits() {
        var recents = RecentColors()
        recents.record(hex: "#FF000080")
        // Canonicalized via RGBA → opaque six-digit form.
        #expect(recents.colors == ["#FF0000"])
    }

    @Test func roundTripsThroughCodable() throws {
        var recents = RecentColors()
        recents.record(hex: "#FF0000")
        recents.record(hex: "#007AFF")
        let data = try JSONEncoder().encode(recents)
        let decoded = try JSONDecoder().decode(RecentColors.self, from: data)
        #expect(decoded.colors == recents.colors)
    }
}
