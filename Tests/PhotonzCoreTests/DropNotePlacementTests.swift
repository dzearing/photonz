import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Where the sentence a drop target says goes while something is in the air
/// over it.
///
/// The one rule it exists to keep is that the words never sit on top of the
/// thing they are about: a swatch covered by its own explanation is a swatch
/// you cannot see light up.
struct DropNotePlacementTests {

    private let window = CGRect(x: 0, y: 0, width: 1400, height: 900)
    private let pill = CGSize(width: 220, height: 30)

    /// A swatch on the right hand panel, which is where nearly every colour in
    /// the app lives.
    private let swatch = CGRect(x: 1320, y: 300, width: 18, height: 18)

    // MARK: - The ordinary case

    @Test func sitsToTheLeftOfAPanelSwatch() {
        let origin = DropNotePlacement.place(note: pill, beside: swatch, in: window)
        // Clear of the swatch, on the canvas side of it.
        #expect(origin.x + pill.width <= swatch.minX)
        #expect(origin.x == swatch.minX - DropNotePlacement.gap - pill.width)
    }

    @Test func linesUpWithTheMiddleOfWhatItIsAbout() {
        let origin = DropNotePlacement.place(note: pill, beside: swatch, in: window)
        #expect(origin.y + pill.height / 2 == swatch.midY)
    }

    @Test func neverOverlapsWhatItIsAbout() {
        // Every corner and edge of the window, and a target the size of the
        // whole panel as well as one the size of a swatch.
        let spots: [CGRect] = [
            CGRect(x: 1320, y: 8, width: 18, height: 18),
            CGRect(x: 1320, y: 870, width: 18, height: 18),
            CGRect(x: 4, y: 300, width: 18, height: 18),
            CGRect(x: 4, y: 4, width: 18, height: 18),
            CGRect(x: 690, y: 860, width: 40, height: 30),
            CGRect(x: 1140, y: 100, width: 260, height: 700)
        ]
        for spot in spots {
            let origin = DropNotePlacement.place(note: pill, beside: spot, in: window)
            let note = CGRect(origin: origin, size: pill)
            #expect(!note.intersects(spot), "the note covered the target at \(spot)")
        }
    }

    // MARK: - Running out of room

    @Test func stepsToTheRightWhenTheLeftWouldFallOffTheWindow() {
        let atTheLeftEdge = CGRect(x: 10, y: 300, width: 18, height: 18)
        let origin = DropNotePlacement.place(note: pill, beside: atTheLeftEdge, in: window)
        #expect(origin.x == atTheLeftEdge.maxX + DropNotePlacement.gap)
    }

    @Test func stepsAboveWhenNeitherSideFits() {
        // A target wide enough that neither side has room for the pill.
        let wide = CGRect(x: 40, y: 400, width: 1320, height: 40)
        let origin = DropNotePlacement.place(note: pill, beside: wide, in: window)
        #expect(origin.y + pill.height <= wide.minY)
        #expect(origin.y == wide.minY - DropNotePlacement.gap - pill.height)
        // Centred on it, so it reads as belonging to it.
        #expect(origin.x + pill.width / 2 == wide.midX)
    }

    @Test func stepsBelowWhenThereIsNoRoomAbove() {
        let wideAndHigh = CGRect(x: 40, y: 10, width: 1320, height: 40)
        let origin = DropNotePlacement.place(note: pill, beside: wideAndHigh, in: window)
        #expect(origin.y == wideAndHigh.maxY + DropNotePlacement.gap)
    }

    @Test func staysInsideTheWindowBesideATargetAtTheTop() {
        let high = CGRect(x: 1320, y: 0, width: 18, height: 18)
        let origin = DropNotePlacement.place(note: pill, beside: high, in: window)
        #expect(origin.y >= window.minY + DropNotePlacement.margin)
    }

    @Test func staysInsideTheWindowBesideATargetAtTheBottom() {
        let low = CGRect(x: 1320, y: 890, width: 18, height: 18)
        let origin = DropNotePlacement.place(note: pill, beside: low, in: window)
        #expect(origin.y + pill.height <= window.maxY - DropNotePlacement.margin)
    }

    // MARK: - Standing clear of the panel, not only the swatch

    /// The real shape of the panel case: the swatch is 18pt wide at the right
    /// edge of a 260pt column, and words that cleared only the swatch would
    /// lie across the row's own label and switch.
    @Test func standsClearOfTheWholePanelTheSwatchLivesIn() {
        let panel = CGRect(x: 1140, y: 0, width: 260, height: 900)
        let origin = DropNotePlacement.place(note: pill, beside: swatch,
                                             clearing: panel, in: window)
        #expect(origin.x + pill.width <= panel.minX)
    }

    /// And it still lines up with the swatch rather than with the middle of
    /// the panel, which is the whole reason the two rects are told apart.
    @Test func stillLinesUpWithTheSwatchAndNotTheWholePanel() {
        let panel = CGRect(x: 1140, y: 0, width: 260, height: 900)
        let origin = DropNotePlacement.place(note: pill, beside: swatch,
                                             clearing: panel, in: window)
        #expect(origin.y + pill.height / 2 == swatch.midY)
    }

    /// A swatch that is nowhere near the panel — the one on the floating tool
    /// bar — is not pushed out past it.
    @Test func aTargetOutsideThePanelKeepsItsOwnStandoff() {
        let panel = CGRect(x: 1140, y: 0, width: 260, height: 900)
        let onTheBar = CGRect(x: 690, y: 850, width: 26, height: 26)
        let alone = DropNotePlacement.place(note: pill, beside: onTheBar, in: window)
        let withPanel = DropNotePlacement.place(note: pill, beside: onTheBar,
                                                clearing: nil, in: window)
        #expect(alone == withPanel)
        #expect(alone.x + pill.width <= onTheBar.minX)
        #expect(panel.minX > onTheBar.maxX)
    }

    /// A window too small for the pill to fit anywhere cannot be satisfied, and
    /// the answer still has to be a number somebody can draw at.
    @Test func answersEvenWhenNothingFits() {
        let tiny = CGRect(x: 0, y: 0, width: 120, height: 60)
        let middle = CGRect(x: 40, y: 20, width: 40, height: 20)
        let origin = DropNotePlacement.place(note: pill, beside: middle, in: tiny)
        #expect(origin.x.isFinite)
        #expect(origin.y.isFinite)
    }

}
