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
}
