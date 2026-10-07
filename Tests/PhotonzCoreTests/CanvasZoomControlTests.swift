import CoreGraphics
import PhotonzCore
import Testing

@Suite("CanvasZoomControl")
struct CanvasZoomControlTests {

    // MARK: When it is up

    /// Nothing has zoomed and nothing is resting on it: there is no control.
    /// Opening a document never zooms through the clock, so this is also what
    /// a freshly opened picture looks like.
    @Test func itIsAwayUntilSomebodyZooms() {
        let clock = CanvasZoomControl.Clock()
        #expect(!clock.isShown(at: 0))
        #expect(!clock.isShown(at: 100))
        #expect(clock.hidesAt == nil)
    }

    /// A zoom puts it up, and it stays for the whole five seconds after.
    @Test func aZoomPutsItUpForFiveSeconds() {
        var clock = CanvasZoomControl.Clock()
        clock.zoomed(at: 10)
        #expect(clock.isShown(at: 10))
        #expect(clock.isShown(at: 14.9))
        #expect(!clock.isShown(at: 15))
        #expect(clock.hidesAt == 15)
    }

    /// Every zoom starts the five seconds again, so a pinch that keeps going
    /// keeps it up for as long as it goes on, and five seconds past its end.
    @Test func eachZoomStartsTheFiveSecondsAgain() {
        var clock = CanvasZoomControl.Clock()
        clock.zoomed(at: 0)
        clock.zoomed(at: 4)
        #expect(clock.isShown(at: 8.5))
        #expect(!clock.isShown(at: 9))
        #expect(clock.hidesAt == 9)
    }

    /// Using one of its own buttons is the same as zooming: five more seconds.
    @Test func usingItStartsTheFiveSecondsAgain() {
        var clock = CanvasZoomControl.Clock()
        clock.zoomed(at: 0)
        clock.used(at: 3)
        #expect(clock.isShown(at: 7.9))
        #expect(!clock.isShown(at: 8))
    }

    // MARK: Resting the pointer on its spot

    /// The pointer over its spot brings it back after it has gone, and keeps
    /// it up however long the pointer stays.
    @Test func thePointerOnItsSpotBringsItBackAndHoldsIt() {
        var clock = CanvasZoomControl.Clock()
        clock.zoomed(at: 0)
        #expect(!clock.isShown(at: 6))
        clock.hold(.pointer, true, at: 6)
        #expect(clock.isShown(at: 6))
        #expect(clock.isShown(at: 600))
        #expect(clock.hidesAt == nil)
    }

    /// Its spot answers the pointer even if nobody has zoomed yet: the spot is
    /// where it lives, whether or not it has been up.
    @Test func itsSpotAnswersBeforeAnyZoom() {
        var clock = CanvasZoomControl.Clock()
        clock.hold(.pointer, true, at: 2)
        #expect(clock.isShown(at: 2))
    }

    /// Leaving starts the five seconds from the moment the pointer left, not
    /// from the last zoom: otherwise it would vanish the instant the pointer
    /// came off it after a long rest.
    @Test func leavingStartsTheFiveSecondsFromTheLeaving() {
        var clock = CanvasZoomControl.Clock()
        clock.zoomed(at: 0)
        clock.hold(.pointer, true, at: 1)
        clock.hold(.pointer, false, at: 30)
        #expect(clock.isShown(at: 34.9))
        #expect(!clock.isShown(at: 35))
        #expect(clock.hidesAt == 35)
    }

    /// Being told the pointer left twice, or arrived twice, changes nothing:
    /// AppKit's tracking area and a walk's pointer can both say so.
    @Test func sayingTheSameThingTwiceChangesNothing() {
        var clock = CanvasZoomControl.Clock()
        clock.hold(.pointer, true, at: 1)
        clock.hold(.pointer, true, at: 2)
        clock.hold(.pointer, false, at: 3)
        clock.hold(.pointer, false, at: 7)
        #expect(clock.hidesAt == 8)
    }

    /// Its zoom stops menu, open, keeps it up: a menu left open longer than
    /// five seconds must not lose the control it hangs from.
    @Test func anOpenMenuHoldsItUp() {
        var clock = CanvasZoomControl.Clock()
        clock.zoomed(at: 0)
        clock.hold(.menu, true, at: 1)
        clock.hold(.pointer, false, at: 1)
        #expect(clock.isShown(at: 20))
        clock.hold(.menu, false, at: 20)
        #expect(clock.isShown(at: 24.9))
        #expect(!clock.isShown(at: 25))
    }

    /// The fades the user asked for: quick in, a little slower out.
    @Test func theFadesAreShort() {
        #expect(CanvasZoomControl.fadeInSeconds == 0.2)
        #expect(CanvasZoomControl.fadeOutSeconds == 0.3)
        #expect(CanvasZoomControl.holdSeconds == 5)
    }

    // MARK: Where it sits

    private let canvas = CGSize(width: 1000, height: 700)
    private let size = CGSize(width: 160, height: 32)

    /// With nothing in the corner, it sits 12pt in from the right and bottom.
    @Test func itSitsInTheBottomRightCorner() {
        let frame = CanvasZoomControl.frame(canvasSize: canvas, size: size, avoiding: [])
        #expect(abs(frame.maxX - 988) < 0.001, "right edge \(frame.maxX)")
        #expect(abs(frame.maxY - 688) < 0.001, "bottom edge \(frame.maxY)")
        #expect(frame.size == size)
    }

    /// The tool bar in the middle of a wide canvas is nowhere near the corner,
    /// so it does not move it.
    @Test func aCentredBarOnAWideCanvasLeavesItInTheCorner() {
        let bar = EditorChromeLayout.toolBarFrame(canvasSize: canvas, toolBarWidth: 500)
        let frame = CanvasZoomControl.frame(canvasSize: canvas, size: size, avoiding: [bar])
        #expect(abs(frame.maxY - 688) < 0.001, "bottom edge \(frame.maxY)")
        #expect(!frame.intersects(bar))
    }

    /// On a narrow canvas the bar reaches the corner, and the control rises
    /// above it, a stack gap clear, never over it.
    @Test func aBarThatReachesTheCornerLiftsItAbove() {
        let narrow = CGSize(width: 600, height: 500)
        let bar = EditorChromeLayout.toolBarFrame(canvasSize: narrow, toolBarWidth: 520)
        let frame = CanvasZoomControl.frame(canvasSize: narrow, size: size, avoiding: [bar])
        #expect(!frame.intersects(bar))
        #expect(frame.maxY == bar.minY - EditorChromeLayout.toolBarStackGap)
        #expect(abs(frame.maxX - 588) < 0.001, "right edge \(frame.maxX)")
    }

    /// With the tool settings capsule up as well and also in the way, it
    /// clears that too, whichever order they are handed in.
    @Test func itClearsEverythingStackedInTheWay() {
        let narrow = CGSize(width: 600, height: 500)
        let bar = EditorChromeLayout.toolBarFrame(canvasSize: narrow, toolBarWidth: 520)
        let capsule = CGRect(x: 60, y: bar.minY - 12 - 40, width: 480, height: 40)
        for avoiding in [[bar, capsule], [capsule, bar]] {
            let frame = CanvasZoomControl.frame(canvasSize: narrow, size: size, avoiding: avoiding)
            #expect(!frame.intersects(bar))
            #expect(!frame.intersects(capsule))
            #expect(frame.maxY == capsule.minY - EditorChromeLayout.toolBarStackGap)
        }
    }

    /// A bar that stops just short of the corner still counts if it would
    /// touch: the two must read as two surfaces, not one.
    @Test func aBarThatWouldTouchItCountsAsInTheWay() {
        let bar = CGRect(x: 300, y: 636, width: 1000 - 12 - 160 - 4 - 300, height: 48)
        let frame = CanvasZoomControl.frame(canvasSize: canvas, size: size, avoiding: [bar])
        #expect(frame.maxY == bar.minY - EditorChromeLayout.toolBarStackGap)
    }

    /// A canvas too short to lift it anywhere keeps it inside the canvas
    /// rather than pushing it off the top.
    @Test func itNeverLeavesTheTopOfTheCanvas() {
        let tiny = CGSize(width: 300, height: 90)
        let bar = CGRect(x: 0, y: 30, width: 300, height: 48)
        let frame = CanvasZoomControl.frame(canvasSize: tiny, size: size, avoiding: [bar])
        #expect(frame.minY >= 0)
    }

    /// The slot it reserves for the measure legend is the corner it sits in,
    /// at least as big as the control, so the legend never parks under it.
    @Test func theReservedSlotCoversTheControl() {
        let slot = CanvasZoomControl.reservedFrame(canvasSize: canvas, avoiding: [])
        let frame = CanvasZoomControl.frame(canvasSize: canvas, size: size, avoiding: [])
        #expect(slot.contains(frame))
    }
}
