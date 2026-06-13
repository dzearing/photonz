import CoreGraphics
import Testing
@testable import PhotonzCore

/// Arrow-key nudge deltas (macOS convention: 1pt, ⇧ for 10pt).
@Suite("Nudge")
struct NudgeTests {

    @Test func arrowKeysMapToUnitDeltas() {
        #expect(Nudge.delta(keyCode: 123, large: false) == CGVector(dx: -1, dy: 0))  // ←
        #expect(Nudge.delta(keyCode: 124, large: false) == CGVector(dx: 1, dy: 0))   // →
        #expect(Nudge.delta(keyCode: 125, large: false) == CGVector(dx: 0, dy: 1))   // ↓ (model y grows down)
        #expect(Nudge.delta(keyCode: 126, large: false) == CGVector(dx: 0, dy: -1))  // ↑
    }

    @Test func shiftMakesTenPointNudges() {
        #expect(Nudge.delta(keyCode: 123, large: true) == CGVector(dx: -10, dy: 0))
        #expect(Nudge.delta(keyCode: 126, large: true) == CGVector(dx: 0, dy: -10))
    }

    @Test func otherKeysDoNotNudge() {
        #expect(Nudge.delta(keyCode: 53, large: false) == nil)  // Esc
        #expect(Nudge.delta(keyCode: 0, large: false) == nil)   // A
    }
}
