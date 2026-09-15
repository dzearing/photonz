import CoreGraphics
import Testing
@testable import PhotonzCore

/// Typing an exact position or size, once it is a thing you ASK for rather than
/// four boxes sitting open at the top of the panel for every layer forever.
///
/// The rules that used to be spread between the panel's availability test and
/// the section's own header live here now, because the command has to answer
/// the same two questions the section answered — is there anything to place,
/// and whose numbers are these — before anything is on screen.
@Suite struct ExactPlacementTests {

    // MARK: Whose numbers

    @Test func oneLayerPickedIsTheSubject() {
        #expect(ExactPlacement.subject(pickedLayers: 1, hasMarquee: false) == .layers(1))
    }

    @Test func severalLayersPickedAreOneSubject() {
        #expect(ExactPlacement.subject(pickedLayers: 4, hasMarquee: false) == .layers(4))
    }

    @Test func nothingPickedHasNothingToPlace() {
        #expect(ExactPlacement.subject(pickedLayers: 0, hasMarquee: false) == nil)
    }

    /// The same rule the arrow keys use: while a marquee is live it owns the
    /// numbers, so the command must not offer the layer underneath it.
    @Test func aLiveMarqueeTakesTheNumbersOffTheLayer() {
        #expect(ExactPlacement.subject(pickedLayers: 1, hasMarquee: true) == .marquee)
        #expect(ExactPlacement.subject(pickedLayers: 0, hasMarquee: true) == .marquee)
    }

    // MARK: What it calls itself

    @Test func theCommandIsNamedForWhatItOpens() {
        #expect(ExactPlacement.menuItem == "Position and Size\u{2026}")
        #expect(!ExactPlacement.menuItem.contains("—"))
    }

    @Test func aMarqueeSaysItIsTheSelectionRatherThanALayer() {
        #expect(ExactPlacement.heading(for: .marquee) == "Selection")
    }

    @Test func oneLayerJustSaysPositionAndSize() {
        #expect(ExactPlacement.heading(for: .layers(1)) == "Position and Size")
    }

    /// Several layers are ONE subject and the heading says how many, because
    /// typing a width here reaches all of them and a heading that said nothing
    /// would let somebody resize four things thinking they had one.
    @Test func severalLayersSayHowMany() {
        #expect(ExactPlacement.heading(for: .layers(4)) == "Position and Size, 4 layers")
    }

    // MARK: Where the popover points

    let viewport = Viewport(documentSize: CGSize(width: 900, height: 600),
                            viewSize: CGSize(width: 800, height: 600),
                            zoom: 2, origin: CGPoint(x: 40, y: 20))
    let visible = CGRect(x: 0, y: 0, width: 800, height: 600)

    @Test func itPointsAtTheBoxYouPicked() {
        let anchor = ExactPlacement.anchor(around: CGRect(x: 10, y: 15, width: 100, height: 50),
                                           viewport: viewport, canvas: visible)
        #expect(anchor == CGRect(x: 60, y: 50, width: 200, height: 100))
    }

    /// A layer half off the edge of what you can see: the popover points at the
    /// part that IS on screen, so the arrow lands on the picture rather than
    /// somewhere past the window.
    @Test func aBoxHangingOffTheEdgeIsClippedToWhatIsOnScreen() {
        let anchor = ExactPlacement.anchor(around: CGRect(x: -200, y: 0, width: 300, height: 40),
                                           viewport: viewport, canvas: visible)
        #expect(anchor.minX == 0)
        #expect(anchor.maxX == 240)
    }

    /// Scrolled right away from the layer: there is nothing on screen to point
    /// at, so it points at the middle of the canvas instead of off the window.
    @Test func aBoxCompletelyOutOfViewFallsBackToTheMiddle() {
        let anchor = ExactPlacement.anchor(around: CGRect(x: 4000, y: 4000, width: 10, height: 10),
                                           viewport: viewport, canvas: visible)
        #expect(anchor.midX == visible.midX)
        #expect(anchor.midY == visible.midY)
    }

    /// A hairline at low zoom still has to be somewhere a popover can hang off,
    /// so the anchor never comes back with no size in it.
    @Test func aVanishinglySmallBoxStillHasSomethingToPointAt() {
        let tiny = Viewport(documentSize: CGSize(width: 9000, height: 6000),
                            viewSize: CGSize(width: 800, height: 600),
                            zoom: 0.05, origin: .zero)
        let anchor = ExactPlacement.anchor(around: CGRect(x: 100, y: 100, width: 2, height: 2),
                                           viewport: tiny, canvas: visible)
        #expect(anchor.width >= ExactPlacement.smallestAnchor)
        #expect(anchor.height >= ExactPlacement.smallestAnchor)
    }

    /// The union, not the first one: four buttons picked put the popover over
    /// all four rather than over whichever happened to be first.
    @Test func severalBoxesArePointedAtTogether() {
        let box = ExactPlacement.box(around: [CGRect(x: 10, y: 10, width: 20, height: 20),
                                              CGRect(x: 100, y: 40, width: 30, height: 10)])
        #expect(box == CGRect(x: 10, y: 10, width: 120, height: 40))
    }

    @Test func noBoxesIsNoBox() {
        #expect(ExactPlacement.box(around: []) == nil)
    }
}
