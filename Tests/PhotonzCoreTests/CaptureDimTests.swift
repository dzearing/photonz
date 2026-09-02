import Testing
import CoreGraphics
@testable import PhotonzCore

@Suite("The dim over a capture overlay")
struct CaptureDimTests {
    // The overlay draws its selection in top-left points, the way a screen
    // reads; the dim it opens lives in a layer that counts up from the bottom.
    // Getting this backwards puts the hole in the mirror image of where the
    // pointer is, which nothing but a photograph of a live screen would catch.

    let display = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func aSelectionAtTheTopOfTheScreenOpensAtTheTopOfTheDim() {
        let hole = CaptureDim.hole(for: CGRect(x: 40, y: 0, width: 100, height: 50), in: display)
        #expect(hole == CGRect(x: 40, y: 750, width: 100, height: 50))
    }

    @Test func aSelectionAtTheBottomOfTheScreenOpensAtTheBottomOfTheDim() {
        let hole = CaptureDim.hole(for: CGRect(x: 40, y: 750, width: 100, height: 50), in: display)
        #expect(hole == CGRect(x: 40, y: 0, width: 100, height: 50))
    }

    @Test func flippingTwiceIsWhereItStarted() {
        let selection = CGRect(x: 123, y: 456, width: 78, height: 90)
        guard let hole = CaptureDim.hole(for: selection, in: display) else {
            Issue.record("a selection well inside the display must open a hole")
            return
        }
        #expect(CaptureDim.hole(for: hole, in: display) == selection)
    }

    @Test func aSelectionRunningOffTheDisplayOpensOnlyThePartThatIsOnIt() {
        // A drag can be reported past the edge of the display it started on.
        let hole = CaptureDim.hole(for: CGRect(x: -30, y: -20, width: 100, height: 50), in: display)
        #expect(hole == CGRect(x: 0, y: 770, width: 70, height: 30))
    }

    @Test func aSelectionCompletelyOffTheDisplayOpensNothing() {
        #expect(CaptureDim.hole(for: CGRect(x: 2000, y: 100, width: 50, height: 50),
                                in: display) == nil)
    }

    @Test func anEmptySelectionOpensNothing() {
        // The moment a press lands, before it has travelled anywhere.
        #expect(CaptureDim.hole(for: CGRect(x: 100, y: 100, width: 0, height: 0),
                                in: display) == nil)
    }
}
