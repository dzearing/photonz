import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Where a walkthrough callout lands. The rule that matters is UX-PATTERNS D14:
/// a callout never covers what it is talking about. A tour that hides the button
/// it is telling you to press is the same mistake as a measurement chip drawn on
/// the label it is accusing, with worse timing.
///
/// Everything here is top left origin, y growing downward.
@Suite("Tutorial callout placement")
struct TutorialCalloutTests {

    private let window = CGRect(x: 0, y: 0, width: 1200, height: 800)
    private let card = CGSize(width: 320, height: 140)

    // MARK: The rule

    @Test func theCalloutNeverCoversTheControlItIsPointingAt() {
        // A control in every part of the window, including all four corners and
        // dead centre.
        //
        // A SURFACE is the one thing not in this list. An anchor that fills the
        // window has no side with room, and the answer there is the card inside
        // it rather than the card off the screen: see
        // `aStepAboutTheWholePictureKeepsItsCardInsideTheWindow`.
        let anchors = [
            CGRect(x: 560, y: 380, width: 80, height: 40),   // middle
            CGRect(x: 0, y: 0, width: 80, height: 40),       // top left corner
            CGRect(x: 1120, y: 0, width: 80, height: 40),    // top right
            CGRect(x: 0, y: 760, width: 80, height: 40),     // bottom left
            CGRect(x: 1120, y: 760, width: 80, height: 40),  // bottom right
            CGRect(x: 400, y: 770, width: 400, height: 30),  // the tool bar
        ]
        for anchor in anchors {
            for side in TutorialSide.allCases {
                let placed = TutorialCalloutLayout.place(anchor: anchor, size: card,
                                                         container: window, preferred: side)
                #expect(!placed.frame.intersects(anchor),
                        "\(side) placement covered the control at \(anchor)")
            }
        }
    }

    @Test func theCalloutStaysInsideTheWindowWhenThereIsAnywhereToPutIt() {
        let anchor = CGRect(x: 560, y: 380, width: 80, height: 40)
        for side in TutorialSide.allCases {
            let placed = TutorialCalloutLayout.place(anchor: anchor, size: card,
                                                     container: window, preferred: side)
            #expect(placed.frame.minX >= window.minX)
            #expect(placed.frame.maxX <= window.maxX)
            #expect(placed.frame.minY >= window.minY)
            #expect(placed.frame.maxY <= window.maxY)
        }
    }

    // MARK: Sides

    @Test func theSideTheStepAskedForIsTakenWhenThereIsRoomThere() {
        let anchor = CGRect(x: 560, y: 380, width: 80, height: 40)
        #expect(TutorialCalloutLayout.place(anchor: anchor, size: card, container: window,
                                            preferred: .above).side == .above)
        #expect(TutorialCalloutLayout.place(anchor: anchor, size: card, container: window,
                                            preferred: .below).side == .below)
        #expect(TutorialCalloutLayout.place(anchor: anchor, size: card, container: window,
                                            preferred: .leading).side == .leading)
        #expect(TutorialCalloutLayout.place(anchor: anchor, size: card, container: window,
                                            preferred: .trailing).side == .trailing)
    }

    @Test func aSideWithNoRoomFlipsToOneThatHasSome() {
        // The floating tool bar: asking for above is right in a tall window and
        // impossible when the bar is at the very top.
        let pinnedToTheTop = CGRect(x: 500, y: 4, width: 200, height: 32)
        let placed = TutorialCalloutLayout.place(anchor: pinnedToTheTop, size: card,
                                                 container: window, preferred: .above)
        #expect(placed.side != .above)
        #expect(!placed.frame.intersects(pinnedToTheTop))
    }

    @Test func automaticPicksTheSideWithTheMostRoom() {
        // A control hard against the right edge: the room is all on the left.
        let anchor = CGRect(x: 1100, y: 380, width: 80, height: 40)
        let placed = TutorialCalloutLayout.place(anchor: anchor, size: card, container: window)
        #expect(placed.side == .above || placed.side == .below || placed.side == .leading)
        #expect(!placed.frame.intersects(anchor))
    }

    @Test func aTieDoesNotFlipTheCalloutBackAndForth() {
        // Dead centre: above and below have identical room. The order has to be
        // stable or a one pixel resize would make the card jump sides.
        let anchor = CGRect(x: 560, y: 380, width: 80, height: 40)
        let first = TutorialCalloutLayout.place(anchor: anchor, size: card, container: window)
        let again = TutorialCalloutLayout.place(anchor: anchor, size: card, container: window)
        #expect(first == again)
    }

    // MARK: The pointer

    @Test func theBeakAimsAtTheMiddleOfTheControl() {
        let anchor = CGRect(x: 560, y: 380, width: 80, height: 40)
        let placed = TutorialCalloutLayout.place(anchor: anchor, size: card,
                                                 container: window, preferred: .above)
        let tip = placed.beakOffset
        #expect(tip != nil)
        if let tip { #expect(abs(placed.frame.minX + tip - anchor.midX) < 0.5) }
    }

    @Test func theBeakStaysOffTheCornersOfTheCard() {
        // A control jammed into the corner drags the card sideways; the beak
        // follows it but stops short of the rounded corner.
        let anchor = CGRect(x: 4, y: 380, width: 24, height: 24)
        let placed = TutorialCalloutLayout.place(anchor: anchor, size: card,
                                                 container: window, preferred: .above)
        if let tip = placed.beakOffset {
            #expect(tip >= TutorialCalloutLayout.beakInset - 0.01)
            #expect(tip <= card.width - TutorialCalloutLayout.beakInset + 0.01)
        }
    }

    @Test func aCalloutThatCannotHonestlyPointAtAnythingDrawsNoBeak() {
        // The control is far off to one side of a card pinned by the window
        // edge: there is no place on the card's edge that lines up with it, so
        // a beak would be pointing at nothing.
        let anchor = CGRect(x: 1150, y: 400, width: 40, height: 40)
        let placed = TutorialCalloutLayout.place(anchor: anchor, size: card,
                                                 container: window, preferred: .leading)
        // Leading has room here, so it keeps its beak; the case under test is
        // the vertical one, where the card is clamped away from the control.
        #expect(placed.beakOffset != nil)

        let tiny = CGRect(x: 0, y: 0, width: 200, height: 600)
        let squeezed = TutorialCalloutLayout.place(anchor: CGRect(x: 150, y: 300, width: 40, height: 40),
                                                   size: CGSize(width: 320, height: 140),
                                                   container: tiny, preferred: .above)
        #expect(!squeezed.frame.intersects(CGRect(x: 150, y: 300, width: 40, height: 40)))
    }

    // MARK: An anchor that is a surface rather than a control

    @Test func aStepAboutTheWholePictureKeepsItsCardInsideTheWindow() {
        // The canvas fills the window bar the panel. There is no room on any
        // side of it, and the old answer was to shove the card off the window
        // edge, where half of it (and one of its buttons) was unreadable.
        let window = CGRect(x: 0, y: 0, width: 1280, height: 840)
        let canvas = CGRect(x: 0, y: 28, width: 960, height: 800)
        let placed = TutorialCalloutLayout.place(anchor: canvas,
                                                 size: CGSize(width: 320, height: 130),
                                                 container: window)
        #expect(placed.frame.maxX <= window.maxX - TutorialCalloutLayout.edge + 0.5)
        #expect(placed.frame.minX >= window.minX + TutorialCalloutLayout.edge - 0.5)
        #expect(placed.frame.maxY <= window.maxY - TutorialCalloutLayout.edge + 0.5)
        #expect(placed.frame.minY >= window.minY + TutorialCalloutLayout.edge - 0.5)
        // Inside the surface it is talking about, and near the top of it,
        // clear of the floating tool bar along the bottom.
        #expect(canvas.contains(placed.frame))
        #expect(placed.frame.minY < canvas.midY)
        // Nothing for a beak to point at: the step is about the whole surface,
        // not about an edge of it.
        #expect(placed.beakOffset == nil)
    }

    @Test func aSurfaceTooSmallToHoldTheCardIsStillTreatedLikeAControl() {
        // The rule is about a surface with room INSIDE it. A panel section
        // barely bigger than the card is still something the card sits beside.
        let window = CGRect(x: 0, y: 0, width: 1280, height: 840)
        let section = CGRect(x: 980, y: 100, width: 300, height: 150)
        let placed = TutorialCalloutLayout.place(anchor: section,
                                                 size: CGSize(width: 320, height: 130),
                                                 container: window, preferred: .leading)
        #expect(!placed.frame.intersects(section))
    }

    // MARK: The one flip between AppKit and this space

    @Test func flippingTwiceGivesBackWhatYouStartedWith() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let rect = CGRect(x: 120, y: 300, width: 80, height: 40)
        #expect(TutorialGeometry.flip(TutorialGeometry.flip(rect, in: screen), in: screen) == rect)
    }

    @Test func flippingPutsTheTopOfTheScreenAtZero() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // A control whose top edge touches the top of the screen.
        let atTheTop = CGRect(x: 0, y: 760, width: 100, height: 40)
        #expect(TutorialGeometry.flip(atTheTop, in: screen).minY == 0)
    }

    @Test func flippingWorksOnAScreenThatDoesNotStartAtZero() {
        // A second display hung above the main one has a negative origin.
        let screen = CGRect(x: 0, y: -1000, width: 1000, height: 800)
        let rect = CGRect(x: 10, y: -400, width: 80, height: 40)
        #expect(TutorialGeometry.flip(TutorialGeometry.flip(rect, in: screen), in: screen) == rect)
    }
}
