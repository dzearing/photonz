import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The foreground/background pair and the two keys that paint with it.
///
/// Since the colour capsule appears only for the tools that paint
/// (`Tool.colorControl`), the pair has no swatches on the bar under Select,
/// crop, the marquees or the wand — but ⌥⌫ still fills with the foreground
/// there, ⌫ on a locked background still clears to the background, and growing
/// the canvas outward still paints the new space with the background. What
/// those keys can do, and which part of the picture the background colour is
/// about to land on, is decided here so the menu row and the key press cannot
/// drift apart.
@Suite("Fill colors")
struct FillColorsTests {
    // MARK: - When the fill keys have something to paint

    @Test func aPickedLayerIsSomethingToFill() {
        #expect(FillColors.canFill(hasPickedLayer: true, targetsPixels: false, hasRegion: false))
    }

    @Test func aPixelRegionIsSomethingToFillEvenWithNoLayerPicked() {
        #expect(FillColors.canFill(hasPickedLayer: false, targetsPixels: true, hasRegion: true))
    }

    @Test func nothingPickedAndNoRegionMeansNothingToFill() {
        #expect(!FillColors.canFill(hasPickedLayer: false, targetsPixels: false, hasRegion: false))
    }

    /// A marquee left over from a tool that does not act on pixels is not a
    /// fill target: the same rule `CanvasKeys` presses ⌥⌫ under.
    @Test func aRegionThatDoesNotTargetPixelsIsNotAFillTarget() {
        #expect(!FillColors.canFill(hasPickedLayer: false, targetsPixels: false, hasRegion: true))
    }

    @Test func aPickedLayerCountsWhateverTheRegionIsDoing() {
        #expect(FillColors.canFill(hasPickedLayer: true, targetsPixels: true, hasRegion: true))
        #expect(FillColors.canFill(hasPickedLayer: true, targetsPixels: false, hasRegion: true))
    }

    // MARK: - The space a canvas resize is about to paint

    private let canvas = CGRect(x: 0, y: 0, width: 400, height: 300)

    @Test func growingToTheRightAddsOneStripOnTheRight() {
        let added = FillColors.newSpace(canvas: canvas,
                                        proposed: CGRect(x: 0, y: 0, width: 560, height: 300))
        #expect(added == [CGRect(x: 400, y: 0, width: 160, height: 300)])
    }

    /// Space added on the LEFT arrives as a proposed rect with a negative
    /// origin, which is how the canvas drag reports it.
    @Test func growingToTheLeftAddsOneStripOnTheLeft() {
        let added = FillColors.newSpace(canvas: canvas,
                                        proposed: CGRect(x: -60, y: 0, width: 460, height: 300))
        #expect(added == [CGRect(x: -60, y: 0, width: 60, height: 300)])
    }

    @Test func growingDownwardAddsOneStripBelow() {
        let added = FillColors.newSpace(canvas: canvas,
                                        proposed: CGRect(x: 0, y: 0, width: 400, height: 380))
        #expect(added == [CGRect(x: 0, y: 300, width: 400, height: 80)])
    }

    /// A corner handle grows two sides at once, and the strips must not
    /// overlap — a translucent preview would show a darker square in the
    /// corner if they did.
    @Test func aCornerDragAddsTwoStripsThatDoNotOverlap() {
        let added = FillColors.newSpace(canvas: canvas,
                                        proposed: CGRect(x: 0, y: 0, width: 500, height: 400))
        #expect(added.count == 2)
        #expect(added.contains(CGRect(x: 0, y: 300, width: 500, height: 100)))
        #expect(added.contains(CGRect(x: 400, y: 0, width: 100, height: 300)))
        for (i, a) in added.enumerated() {
            for b in added[(i + 1)...] { #expect(!a.intersects(b)) }
        }
    }

    /// ⇧ makes the drag symmetric, so both sides grow and the picture stays
    /// centred: four strips, a picture frame around the old canvas.
    @Test func growingOnEverySideAddsFourStrips() {
        let added = FillColors.newSpace(canvas: canvas,
                                        proposed: CGRect(x: -50, y: -40, width: 500, height: 380))
        #expect(added.count == 4)
        let area = added.reduce(0) { $0 + $1.width * $1.height }
        #expect(area == CGFloat(500 * 380 - 400 * 300))
        for (i, a) in added.enumerated() {
            for b in added[(i + 1)...] { #expect(!a.intersects(b)) }
        }
    }

    @Test func trimmingPaintsNothing() {
        #expect(FillColors.newSpace(canvas: canvas,
                                    proposed: CGRect(x: 0, y: 0, width: 200, height: 300)).isEmpty)
        #expect(FillColors.newSpace(canvas: canvas,
                                    proposed: CGRect(x: 50, y: 50, width: 100, height: 100)).isEmpty)
    }

    @Test func aCanvasThatHasNotMovedPaintsNothing() {
        #expect(FillColors.newSpace(canvas: canvas, proposed: canvas).isEmpty)
    }

    /// Trimming one side while growing another paints only the side that grew.
    @Test func trimmingOneSideWhileGrowingAnotherPaintsOnlyTheSideThatGrew() {
        let added = FillColors.newSpace(canvas: canvas,
                                        proposed: CGRect(x: 100, y: 0, width: 400, height: 300))
        #expect(added == [CGRect(x: 400, y: 0, width: 100, height: 300)])
    }

    /// A proposed rect that shares no ground with the canvas at all is all new.
    @Test func aProposalThatMissesTheCanvasIsAllNewSpace() {
        let proposed = CGRect(x: 600, y: 600, width: 100, height: 100)
        #expect(FillColors.newSpace(canvas: canvas, proposed: proposed) == [proposed])
    }

    @Test func anEmptyProposalPaintsNothing() {
        #expect(FillColors.newSpace(canvas: canvas,
                                    proposed: CGRect(x: 10, y: 10, width: 0, height: 50)).isEmpty)
    }
}
