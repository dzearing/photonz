import Foundation
import PhotonzCore
import Testing

/// A walk claims what a field reads in words. For a reading set by a drag a
/// few points long, the exact words depend on where inside a pixel the drag
/// let go, so the same walk read -9.6 dB on one run and -9.7 dB on the next.
/// "±" lets the claim say how near is near enough, and nothing else about the
/// comparison changes.
@Suite("What a field reads, claimed exactly or within a margin")
struct PlaytestReadingTests {

    @Test("Without a margin the words must match, ignoring case")
    func exact() {
        #expect(PlaytestReading.matches(showing: "0.7s", claimed: "0.7s"))
        #expect(PlaytestReading.matches(showing: "On", claimed: "on"))
        #expect(!PlaytestReading.matches(showing: "-9.6 dB", claimed: "-9.3 dB"))
    }

    @Test("With a margin the number may be off by at most that much")
    func margin() {
        #expect(PlaytestReading.matches(showing: "-9.6 dB", claimed: "-9.3 dB ±0.5"))
        #expect(PlaytestReading.matches(showing: "-9.8 dB", claimed: "-9.3 dB ± 0.5"))
        #expect(!PlaytestReading.matches(showing: "-10.1 dB", claimed: "-9.3 dB ±0.5"))
        // The sign counts: a level that went UP is not near one that went down.
        #expect(!PlaytestReading.matches(showing: "9.3 dB", claimed: "-9.3 dB ±0.5"))
        // The app prints a real minus sign in some readouts.
        #expect(PlaytestReading.matches(showing: "\u{2212}9.4 dB", claimed: "-9.3 dB ±0.5"))
    }

    @Test("With a margin the unit still has to be the same")
    func unit() {
        #expect(!PlaytestReading.matches(showing: "-9.4 s", claimed: "-9.3 dB ±0.5"))
        #expect(!PlaytestReading.matches(showing: "Silent", claimed: "-9.3 dB ±0.5"))
    }
}
