import CoreGraphics
import PhotonzCore
import Testing

@Suite("EditorWindowFit")
struct EditorWindowFitTests {
    // A generous desktop work area, so "grow to fit" has room. Content-size
    // terms (chrome already subtracted by the caller).
    private let bigMax = CGSize(width: 2400, height: 1400)
    private let floor = CGSize(width: EditorChromeLayout.minWindowWidth,
                               height: EditorChromeLayout.minWindowHeight)
    private let pad = EditorWindowFit.edgePadding

    // MARK: Step 1 & 2 — prefer 100%, grow the window to fit

    @Test func smallImageGrowsToImagePlusPaddingAt100Percent() {
        // 400×300 image, no side pane → the window is exactly image + 100 on
        // each edge, shown at 100%.
        let plan = EditorWindowFit.plan(
            imagePointSize: CGSize(width: 400, height: 300),
            sidePaneWidth: 0, maxContentSize: bigMax, minContentSize: floor)
        #expect(plan.imageScale == 1)
        #expect(plan.contentSize == CGSize(width: 400 + pad * 2, height: 300 + pad * 2))
    }

    @Test func sidePaneWidthIsAddedToTheWindowNotThePadding() {
        // Same image with a 264+1pt inspector docked: the window widens by
        // exactly the pane; the canvas padding is unchanged.
        let pane: CGFloat = 265
        let plan = EditorWindowFit.plan(
            imagePointSize: CGSize(width: 400, height: 300),
            sidePaneWidth: pane, maxContentSize: bigMax, minContentSize: floor)
        #expect(plan.imageScale == 1)
        #expect(plan.contentSize.width == 400 + pad * 2 + pane)
        #expect(plan.contentSize.height == 300 + pad * 2)
    }

    @Test func neverUpscalesATinyImage() {
        // A 50×50 image never shows above 100%; the window just meets the floor.
        let plan = EditorWindowFit.plan(
            imagePointSize: CGSize(width: 50, height: 50),
            sidePaneWidth: 0, maxContentSize: bigMax, minContentSize: floor)
        #expect(plan.imageScale == 1)
        #expect(plan.contentSize == floor)
    }

    @Test func windowNeverGrowsPastTheUsableMaximum() {
        // An image that fits at 100% but only just: the window is image+padding,
        // still within the max.
        let img = CGSize(width: bigMax.width - pad * 2 - 10, height: 300)
        let plan = EditorWindowFit.plan(
            imagePointSize: img, sidePaneWidth: 0,
            maxContentSize: bigMax, minContentSize: floor)
        #expect(plan.imageScale == 1)
        #expect(plan.contentSize.width <= bigMax.width)
    }

    // MARK: Step 3 — reduce zoom only when a maxed window can't fit 100%

    @Test func reducesZoomWhenImageTooWideEvenAtMaxWindow() {
        // A 4000×400 image can't show at 100% (needs 4200 wide, max is 1440).
        // The window maxes its width and the zoom drops so the image fits with
        // ~100px on each side of the canvas.
        let max = CGSize(width: 1440, height: 900)
        let img = CGSize(width: 4000, height: 400)
        let plan = EditorWindowFit.plan(
            imagePointSize: img, sidePaneWidth: 0,
            maxContentSize: max, minContentSize: floor)
        #expect(plan.imageScale < 1)
        // Width is the binding constraint → window maxes width.
        #expect(plan.contentSize.width == max.width)
        // The scaled image fits the canvas area with the padding on each side.
        let canvasW = plan.contentSize.width - pad * 2
        #expect(abs(img.width * plan.imageScale - canvasW) < 0.001)
    }

    @Test func reducedZoomAccountsForTheSidePane() {
        // With the inspector docked, the canvas area is narrower, so the fit
        // zoom is smaller than without it.
        let max = CGSize(width: 1440, height: 900)
        let img = CGSize(width: 4000, height: 400)
        let withoutPane = EditorWindowFit.plan(
            imagePointSize: img, sidePaneWidth: 0,
            maxContentSize: max, minContentSize: floor).imageScale
        let withPane = EditorWindowFit.plan(
            imagePointSize: img, sidePaneWidth: 265,
            maxContentSize: max, minContentSize: floor).imageScale
        #expect(withPane < withoutPane)
    }

    @Test func hugeImageMaxesTheBindingAxisAndHugsTheOther() {
        // A 5000×4000 image on a 1440×900 desktop overflows both axes; height
        // binds, so the window is full height and hugs the reduced image width.
        let max = CGSize(width: 1440, height: 900)
        let img = CGSize(width: 5000, height: 4000)
        let plan = EditorWindowFit.plan(
            imagePointSize: img, sidePaneWidth: 0,
            maxContentSize: max, minContentSize: floor)
        #expect(plan.imageScale < 1)
        #expect(plan.contentSize.height == max.height)
        #expect(plan.contentSize.width <= max.width)
        // Reduced image fits the canvas with padding on both axes.
        #expect(img.width * plan.imageScale <= plan.contentSize.width - pad * 2 + 0.001)
        #expect(img.height * plan.imageScale <= plan.contentSize.height - pad * 2 + 0.001)
    }

    @Test func wideShortImageDoesNotForceAFullHeightWindow() {
        // A wide-but-short image overflows width only: the window maxes width
        // but stays close to the image's own height rather than the screen's.
        let max = CGSize(width: 1440, height: 900)
        let img = CGSize(width: 4000, height: 200)
        let plan = EditorWindowFit.plan(
            imagePointSize: img, sidePaneWidth: 0,
            maxContentSize: max, minContentSize: floor)
        #expect(plan.contentSize.width == max.width)
        #expect(plan.contentSize.height < max.height)
    }

    // MARK: Floor & degenerate inputs

    @Test func windowNeverGoesBelowTheFloor() {
        let plan = EditorWindowFit.plan(
            imagePointSize: CGSize(width: 10, height: 10),
            sidePaneWidth: 0, maxContentSize: bigMax, minContentSize: floor)
        #expect(plan.contentSize.width >= floor.width)
        #expect(plan.contentSize.height >= floor.height)
    }

    @Test func zeroSizedImageIsHandledGracefully() {
        let plan = EditorWindowFit.plan(
            imagePointSize: .zero, sidePaneWidth: 0,
            maxContentSize: bigMax, minContentSize: floor)
        #expect(plan.contentSize.width.isFinite)
        #expect(plan.contentSize.height.isFinite)
        #expect(plan.imageScale > 0)
    }
}
