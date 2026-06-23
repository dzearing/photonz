import Foundation
import Testing
import PhotonzCore

@Suite("RGBA hex parsing")
struct RGBATests {

    @Test func parsesSixDigitHex() throws {
        let c = try #require(RGBA(hex: "#FF3B30"))
        #expect(abs(c.r - 1.0) < 0.001)
        #expect(abs(c.g - 59.0 / 255.0) < 0.001)
        #expect(abs(c.b - 48.0 / 255.0) < 0.001)
        #expect(c.a == 1)
    }

    @Test func parsesWithoutLeadingHash() throws {
        let c = try #require(RGBA(hex: "00FF00"))
        #expect(c.r == 0 && abs(c.g - 1) < 0.001 && c.b == 0)
    }

    @Test func parsesLowercase() throws {
        let c = try #require(RGBA(hex: "#ff3b30"))
        #expect(abs(c.r - 1.0) < 0.001)
    }

    @Test func parsesEightDigitHexAsRGBA() throws {
        let c = try #require(RGBA(hex: "#FF000080"))
        #expect(abs(c.r - 1.0) < 0.001)
        #expect(abs(c.a - 128.0 / 255.0) < 0.001)
    }

    @Test func rejectsMalformedStrings() {
        #expect(RGBA(hex: "") == nil)
        #expect(RGBA(hex: "#12345") == nil)
        #expect(RGBA(hex: "#GGGGGG") == nil)
        #expect(RGBA(hex: "#1234567") == nil)
        #expect(RGBA(hex: "not a color") == nil)
    }

    // 13.2: the canonical serializer the eyedropper/recents pipeline round-trips
    // through — uppercase, six-digit, alpha dropped.
    @Test func hexStringIsCanonicalUppercase() throws {
        #expect(RGBA(hex: "#ff3b30")?.hexString == "#FF3B30")
        #expect(RGBA(hex: "00FF00")?.hexString == "#00FF00")
        #expect(RGBA(hex: "#000000")?.hexString == "#000000")
        // Alpha is dropped on serialization.
        #expect(RGBA(hex: "#FF000080")?.hexString == "#FF0000")
    }

    @Test func hexStringRoundTripsFromParse() throws {
        for hex in ["#FF3B30", "#FF9500", "#FFD60A", "#34C759", "#007AFF", "#AF52DE", "#FFFFFF", "#000000"] {
            let parsed = try #require(RGBA(hex: hex))
            #expect(parsed.hexString == hex)
        }
    }

    @Test func hexStringClampsOutOfRangeComponents() {
        // Components outside 0...1 must not overflow the byte formatting.
        #expect(RGBA(r: -0.5, g: 2.0, b: 0.5).hexString == "#00FF80")
        #expect(RGBA(r: 1.5, g: -1, b: 1).hexString == "#FF00FF")
    }
}
