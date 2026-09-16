import CoreGraphics
import Testing
@testable import PhotonzCore

@Suite("Measure handle grip")
struct MeasureHandleGripTests {
    @Test("A press right on the dot leaves the handle under the pointer")
    func pressOnTheDot() {
        let grip = MeasureHandleGrip.taken(pressing: CGPoint(x: 800, y: 500),
                                           handle: CGPoint(x: 800, y: 500),
                                           zoom: 1, tolerance: 9)
        #expect(grip == .none)
        #expect(grip.handlePoint(for: CGPoint(x: 806, y: 500)) == CGPoint(x: 806, y: 500))
    }

    @Test("A foot grabbed off its dot moves by what the hand moved, the way the hand moved")
    func theFootFollowsTheHand() {
        // The reproduction from the bug: the press lands 8 points LEFT of the
        // right foot and the hand travels 6 points RIGHT.
        let foot = CGPoint(x: 800, y: 500)
        let grip = MeasureHandleGrip.taken(pressing: CGPoint(x: 792, y: 500),
                                           handle: foot, zoom: 1, tolerance: 9)
        let landed = grip.handlePoint(for: CGPoint(x: 798, y: 500))
        #expect(landed == CGPoint(x: 806, y: 500))
        #expect(landed.x - foot.x == 6)
    }

    @Test("The handle never travels opposite the hand")
    func neverBackwards() {
        let foot = CGPoint(x: 800, y: 500)
        for offset in stride(from: CGFloat(-9), through: 9, by: 1.5) {
            let press = CGPoint(x: foot.x + offset, y: foot.y)
            let grip = MeasureHandleGrip.taken(pressing: press, handle: foot, zoom: 1, tolerance: 9)
            for travel in stride(from: CGFloat(-40), through: 40, by: 5) where travel != 0 {
                let landed = grip.handlePoint(for: CGPoint(x: press.x + travel, y: press.y))
                #expect((landed.x - foot.x).sign == travel.sign)
                #expect(landed.x - foot.x == travel)
            }
        }
    }

    @Test("The grip is measured on screen, so it survives zoom")
    func gripIsInDocumentPointsTakenAtTheZoomOfTheGrab() {
        // 4 document points at 2x is 8 view points: inside the 9 point slack,
        // so the whole of it is kept.
        let grip = MeasureHandleGrip.taken(pressing: CGPoint(x: 96, y: 50),
                                           handle: CGPoint(x: 100, y: 50),
                                           zoom: 2, tolerance: 9)
        #expect(grip.handlePoint(for: CGPoint(x: 106, y: 50)) == CGPoint(x: 110, y: 50))
    }

    @Test("A grip can never be bigger than the slack that allowed the grab")
    func clampedToTheTolerance() {
        let grip = MeasureHandleGrip.taken(pressing: CGPoint(x: 760, y: 500),
                                           handle: CGPoint(x: 800, y: 500),
                                           zoom: 1, tolerance: 9)
        #expect(grip.offset.width == 9)
        #expect(grip.offset.height == 0)
    }

    @Test("A zoom that cannot be reasoned about takes no grip at all")
    func noZoomNoGrip() {
        let grip = MeasureHandleGrip.taken(pressing: CGPoint(x: 792, y: 500),
                                           handle: CGPoint(x: 800, y: 500),
                                           zoom: 0, tolerance: 9)
        #expect(grip == .none)
    }
}
