import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Guides you pin onto the grid: which line the pointer is on, pinning it,
/// picking one up again, and the fact that they belong to the DOCUMENT rather
/// than to the app.
@Suite struct CanvasGuideTests {

    // MARK: - Which line is under the pointer

    @Test func picksTheNearestVerticalLineWhenThePointerIsNearOne() {
        let line = CanvasGuidePick.line(near: CGPoint(x: 31, y: 50),
                                        spacing: 8, origin: .zero, axes: .columnsAndRows)
        #expect(line == CanvasGuideLine(axis: .vertical, position: 32))
    }

    @Test func picksTheNearestHorizontalLineWhenThatOneIsNearer() {
        let line = CanvasGuidePick.line(near: CGPoint(x: 36, y: 49),
                                        spacing: 8, origin: .zero, axes: .columnsAndRows)
        #expect(line == CanvasGuideLine(axis: .horizontal, position: 48))
    }

    @Test func countsFromTheGridsZeroPoint() {
        let line = CanvasGuidePick.line(near: CGPoint(x: 27, y: 100),
                                        spacing: 8, origin: CGPoint(x: 3, y: 0),
                                        axes: .columnsAndRows)
        #expect(line == CanvasGuideLine(axis: .vertical, position: 27))
    }

    @Test func aColumnsOnlyGridOffersNothingToPinAcross() {
        let line = CanvasGuidePick.line(near: CGPoint(x: 36, y: 49),
                                        spacing: 8, origin: .zero, axes: .columns)
        #expect(line == CanvasGuideLine(axis: .vertical, position: 40))
    }

    /// At a crossing both lines are the same distance away, and without a hold
    /// the highlight would flip between them on every pixel of movement.
    @Test func theLitAxisKeepsItUntilTheOtherIsClearlyNearer() {
        let atCrossing = CGPoint(x: 32.4, y: 48.2)
        // Cold, the nearer one wins outright.
        #expect(CanvasGuidePick.line(near: atCrossing, spacing: 8, origin: .zero,
                                     axes: .columnsAndRows)?.axis == .horizontal)
        // Already holding the vertical, and only 0.2pt in it: it keeps it.
        #expect(CanvasGuidePick.line(near: atCrossing, spacing: 8, origin: .zero,
                                     axes: .columnsAndRows,
                                     holding: .vertical, slack: 2)?.axis == .vertical)
        // Move clearly onto the horizontal and it hands over.
        #expect(CanvasGuidePick.line(near: CGPoint(x: 35, y: 48), spacing: 8, origin: .zero,
                                     axes: .columnsAndRows,
                                     holding: .vertical, slack: 2)?.axis == .horizontal)
    }

    @Test func aGridWithNothingToDrawHasNoLineToPin() {
        #expect(CanvasGuidePick.line(near: .zero, spacing: 0, origin: .zero,
                                     axes: .columnsAndRows) == nil)
        #expect(CanvasGuidePick.line(near: CGPoint(x: CGFloat.nan, y: 0), spacing: 8, origin: .zero,
                                     axes: .columnsAndRows) == nil)
    }

    // MARK: - Pinning, picking up, clearing

    @Test func pinningAddsOneGuide() {
        let pinned = CanvasGuides.pinning([], CanvasGuideLine(axis: .vertical, position: 16))
        #expect(pinned.guides.count == 1)
        #expect(pinned.guides[0].axis == .vertical)
        #expect(pinned.guides[0].position == 16)
        #expect(pinned.id == pinned.guides[0].id)
    }

    /// Clicking the same line twice is one guide, not two on top of each other.
    @Test func pinningTheSameLineTwiceKeepsOneGuide() {
        let once = CanvasGuides.pinning([], CanvasGuideLine(axis: .vertical, position: 16))
        let twice = CanvasGuides.pinning(once.guides,
                                         CanvasGuideLine(axis: .vertical, position: 16))
        #expect(twice.guides.count == 1)
        #expect(twice.id == once.id)
    }

    @Test func aGuideAcrossAndAGuideDownAtTheSameNumberAreTwoGuides() {
        var guides = CanvasGuides.pinning([], CanvasGuideLine(axis: .vertical, position: 16)).guides
        guides = CanvasGuides.pinning(guides, CanvasGuideLine(axis: .horizontal, position: 16)).guides
        #expect(guides.count == 2)
    }

    @Test func positionsComeBackPerAxis() {
        var guides: [CanvasGuide] = []
        for line in [CanvasGuideLine(axis: .vertical, position: 16),
                     CanvasGuideLine(axis: .vertical, position: 320),
                     CanvasGuideLine(axis: .horizontal, position: 48)] {
            guides = CanvasGuides.pinning(guides, line).guides
        }
        #expect(CanvasGuides.positions(guides, axis: .vertical) == [16, 320])
        #expect(CanvasGuides.positions(guides, axis: .horizontal) == [48])
    }

    /// Picking one up: the pointer has to be close to the LINE, measured across
    /// it, and the nearest of two crossing guides wins.
    @Test func picksUpTheGuideUnderThePointer() {
        var guides = CanvasGuides.pinning([], CanvasGuideLine(axis: .vertical, position: 100)).guides
        guides = CanvasGuides.pinning(guides, CanvasGuideLine(axis: .horizontal, position: 200)).guides
        let down = CanvasGuides.nearest(guides, to: CGPoint(x: 103, y: 40), within: 6)
        #expect(down?.axis == .vertical)
        let across = CanvasGuides.nearest(guides, to: CGPoint(x: 400, y: 198), within: 6)
        #expect(across?.axis == .horizontal)
        #expect(CanvasGuides.nearest(guides, to: CGPoint(x: 400, y: 40), within: 6) == nil)
    }

    // MARK: - Guides live in the document

    @Test func aDocumentCarriesItsOwnGuidesAndZeroPoint() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        #expect(document.guides.isEmpty)
        #expect(document.gridOrigin == .zero)
        document.guides = CanvasGuides.pinning([],
                                               CanvasGuideLine(axis: .vertical, position: 16)).guides
        document.gridOrigin = CGPoint(x: 24, y: 16)
        let other = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        #expect(other.guides.isEmpty)
        #expect(other.gridOrigin == .zero)
    }

    @Test func guidesSurviveASaveAndAReopen() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        var guides: [CanvasGuide] = []
        for line in [CanvasGuideLine(axis: .vertical, position: 16),
                     CanvasGuideLine(axis: .vertical, position: 384),
                     CanvasGuideLine(axis: .horizontal, position: 48)] {
            guides = CanvasGuides.pinning(guides, line).guides
        }
        document.guides = guides
        document.gridOrigin = CGPoint(x: 24, y: -16)

        let data = try JSONEncoder().encode(document)
        let reopened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(reopened.guides == guides)
        #expect(reopened.gridOrigin == CGPoint(x: 24, y: -16))
    }

    /// A document from before guides existed reads back with none, and one with
    /// none writes no guide keys at all.
    @Test func aDocumentWithNoGuidesIsWhatItAlwaysWas() throws {
        let document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let data = try JSONEncoder().encode(document)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("guides"))
        #expect(!text.contains("gridOrigin"))
        let reopened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(reopened.guides.isEmpty)
        #expect(reopened.gridOrigin == .zero)
    }

    @Test func aZeroPointThatIsNotANumberIsTheCorner() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        document.gridOrigin = CGPoint(x: CGFloat.nan, y: 8)
        let data = try JSONEncoder().encode(document)
        let reopened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(reopened.gridOrigin == .zero)
    }
}

/// The Adjust Grid session: a working copy of everything the mode touches, so
/// Return keeps it in one edit and Escape puts it all back.
@Suite struct CanvasGridAdjustmentTests {

    private func session() -> CanvasGridAdjustment {
        CanvasGridAdjustment(settings: CanvasGridSettings(spacing: 4, minimumCell: 4),
                             origin: CGPoint(x: 3, y: 5),
                             guides: [CanvasGuide(axis: .vertical, position: 16)])
    }

    @Test func startsFromWhatIsAlreadyThere() {
        let session = session()
        #expect(session.origin == CGPoint(x: 3, y: 5))
        #expect(session.minimumCell == 4)
        #expect(session.guides.count == 1)
        #expect(session.selectedGuideID == nil)
    }

    /// The mode switches the grid on, because nobody adjusts a grid they cannot
    /// see, and leaving without keeping it puts that back too.
    @Test func theGridIsOnWhileYouAreAdjustingIt() {
        var session = CanvasGridAdjustment(settings: CanvasGridSettings(isVisible: false),
                                           origin: .zero, guides: [])
        #expect(session.liveSettings.isVisible)
        session.pin(CanvasGuideLine(axis: .vertical, position: 16))
        #expect(!session.cancelledSettings.isVisible)
    }

    @Test func pinningSelectsWhatYouJustPinned() {
        var session = session()
        session.pin(CanvasGuideLine(axis: .horizontal, position: 48))
        #expect(session.guides.count == 2)
        #expect(session.selectedGuideID == session.guides.last?.id)
    }

    @Test func clickingALineThatAlreadyHasAGuidePicksThatOneUp() {
        var session = session()
        let existing = session.guides[0].id
        session.pin(CanvasGuideLine(axis: .vertical, position: 16))
        #expect(session.guides.count == 1)
        #expect(session.selectedGuideID == existing)
    }

    @Test func theSelectedGuideMovesAndDeletes() {
        var session = session()
        session.select(session.guides[0].id)
        session.moveSelectedGuide(to: CanvasGuideLine(axis: .vertical, position: 320))
        #expect(session.guides[0].position == 320)
        session.deleteSelectedGuide()
        #expect(session.guides.isEmpty)
        #expect(session.selectedGuideID == nil)
    }

    @Test func backspaceWithNothingSelectedDeletesNothing() {
        var session = session()
        session.deleteSelectedGuide()
        #expect(session.guides.count == 1)
    }

    @Test func clearingRemovesEveryGuide() {
        var session = session()
        session.pin(CanvasGuideLine(axis: .horizontal, position: 48))
        session.clearGuides()
        #expect(session.guides.isEmpty)
        #expect(session.selectedGuideID == nil)
        #expect(session.hasGuides == false)
    }

    /// Return keeps the zero point, the cell and the guides; Escape puts all
    /// three back exactly as they were on the way in.
    @Test func leavingKeepsEverythingOrPutsEverythingBack() {
        var session = session()
        session.origin = CGPoint(x: 40, y: 12)
        session.minimumCell = 16
        session.pin(CanvasGuideLine(axis: .horizontal, position: 48))

        #expect(session.committedSettings.minimumCell == 16)
        #expect(session.committedOrigin == CGPoint(x: 40, y: 12))
        #expect(session.committedGuides.count == 2)

        #expect(session.cancelledSettings.minimumCell == 4)
        #expect(session.cancelledOrigin == CGPoint(x: 3, y: 5))
        #expect(session.cancelledGuides.count == 1)
        #expect(session.cancelledGuides[0].position == 16)
    }

    @Test func arrowKeysStepTheZeroPoint() {
        var session = session()
        session.nudge(CGVector(dx: 1, dy: 0))
        #expect(session.origin == CGPoint(x: 4, y: 5))
        session.nudge(CGVector(dx: 0, dy: -10))
        #expect(session.origin == CGPoint(x: 4, y: -5))
    }

    /// What the canvas draws while you are in the mode: the grid you came in
    /// with, counted from the zero point you are holding.
    @Test func theCanvasDrawsTheGridYouAreHolding() {
        var session = session()
        session.origin = CGPoint(x: 12, y: 20)
        session.minimumCell = 8
        #expect(session.liveSettings.minimumCell == 8)
        #expect(session.liveSettings.drawnSpacing == 8)
    }
}

/// The cell slider stops on sizes real UI is built in, so it cannot be left on
/// a number that makes the grid draw one thing and a drag land on another.
@Suite struct CanvasGridCellStopTests {

    @Test func theFirstStopIsNoFloorAtAll() {
        #expect(CanvasGridCellStops.cell(at: 0) == CanvasGridSettings.noMinimumCell)
    }

    @Test func everyStopIsANumberSomebodyWouldType() {
        #expect(CanvasGridCellStops.all == [1, 2, 4, 8, 12, 16, 24, 32, 48, 64])
    }

    @Test func aCellLandsOnTheNearestStop() {
        #expect(CanvasGridCellStops.index(of: 16) == 5)
        #expect(CanvasGridCellStops.index(of: 14) == 5)
        #expect(CanvasGridCellStops.index(of: 13) == 4)
        #expect(CanvasGridCellStops.index(of: 1000) == CanvasGridCellStops.all.count - 1)
        #expect(CanvasGridCellStops.index(of: CGFloat.nan) == 0)
    }

    @Test func anIndexOffTheEndClampsRatherThanCrashes() {
        #expect(CanvasGridCellStops.cell(at: -5) == 1)
        #expect(CanvasGridCellStops.cell(at: 99) == 64)
    }
}
