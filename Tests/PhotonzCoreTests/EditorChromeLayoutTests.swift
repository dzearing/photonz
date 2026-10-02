import CoreGraphics
import PhotonzCore
import Testing

@Suite("EditorChromeLayout")
struct EditorChromeLayoutTests {

    // MARK: The tool bar kept behind View

    /// Out of sight means past the canvas's bottom edge, all of it.
    @Test func theToolBarWaitsBelowTheCanvas() {
        #expect(EditorChromeLayout.toolBarHiddenDrop
                >= EditorChromeLayout.toolBarInset + EditorChromeLayout.toolBarHeight)
    }

    // MARK: Inspector auto-collapse

    @Test func inspectorStaysOpenWhenWide() {
        #expect(EditorChromeLayout.shouldAutoCollapseInspector(windowWidth: 1200) == false)
    }

    @Test func inspectorAutoCollapsesWhenNarrow() {
        #expect(EditorChromeLayout.shouldAutoCollapseInspector(windowWidth: 500) == true)
    }

    @Test func inspectorCollapseUsesAThreshold() {
        let t = EditorChromeLayout.inspectorAutoCollapseWidth
        // At/above the threshold it stays; just below it collapses.
        #expect(EditorChromeLayout.shouldAutoCollapseInspector(windowWidth: t) == false)
        #expect(EditorChromeLayout.shouldAutoCollapseInspector(windowWidth: t - 1) == true)
    }

    // MARK: Clearing the floating tool bar

    @Test func anOverlayAboveTheToolBarClearsIt() {
        // The bar's own band, measured off the running app: 48pt of bar sitting
        // 16pt off the bottom, so anything bottom-centered with less than 64pt
        // of padding is drawn BEHIND it (the measure hint chip was, at 14pt).
        #expect(EditorChromeLayout.aboveToolBar
                > EditorChromeLayout.toolBarInset + EditorChromeLayout.toolBarHeight)
    }

    @Test func theStackKeepsAVisibleGap() {
        // Clearing is not enough: the two must read as a stack, not as one
        // resting on the other.
        let gap = EditorChromeLayout.aboveToolBar
            - (EditorChromeLayout.toolBarInset + EditorChromeLayout.toolBarHeight)
        #expect(gap >= 8)
    }

    @Test func theBarBandIsTheOneMeasuredInTheApp() {
        #expect(EditorChromeLayout.toolBarInset == 16)
        #expect(EditorChromeLayout.toolBarHeight == 48)
    }

    @Test func aFitClearsExactlyTheBarsBand() {
        // The band a fit keeps clear runs from the floor to the bar's top edge:
        // the bar's frame in any canvas starts exactly that far up.
        #expect(EditorChromeLayout.toolBarCovers == 64)
        let canvas = CGSize(width: 900, height: 600)
        let bar = EditorChromeLayout.toolBarFrame(canvasSize: canvas, toolBarWidth: 500)
        #expect(bar.minY == canvas.height - EditorChromeLayout.toolBarCovers)
    }

    @Test func windowFloorIsSaneAndBelowTheCollapseThreshold() {
        // The responsive behavior must be able to kick in ABOVE the floor, so
        // the auto-collapse threshold must sit strictly above the floor.
        #expect(EditorChromeLayout.minWindowWidth > 0)
        #expect(EditorChromeLayout.minWindowHeight > 0)
        #expect(EditorChromeLayout.inspectorAutoCollapseWidth > EditorChromeLayout.minWindowWidth)
    }

    // MARK: One height for every group in the bottom row

    @Test func everyGroupInTheRowIsDrawnAtOneHeight() {
        // The row along the bottom of the canvas is several separate glass
        // capsules. Each used to set its own height from its own padding, and
        // they came out 48, 45 and 35pt tall on the same row (measured in the
        // running app on 2026-09-07), so the row did not line up. One number
        // decides it now.
        #expect(EditorChromeLayout.toolBarGroupHeight == 48)
    }

    @Test func theGroupHeightIsTheHeightThePlacementReservesForTheBar() {
        // Everything that has to clear the bar — the notice pill, the tool
        // settings capsule, the measure legend — measures from
        // `toolBarHeight`. If a group could be taller than that, it would poke
        // through whatever was placed above it.
        #expect(EditorChromeLayout.toolBarHeight == EditorChromeLayout.toolBarGroupHeight)
    }

    // MARK: Double clicking the zoom percentage

    @Test func theZoomMenuWaitsLongEnoughToSeeASecondClick() {
        // A menu opens on the press, so the second click of a double click
        // would land inside the menu. The readout waits to see whether one is
        // coming; the wait is what makes a double click possible at all.
        #expect(EditorChromeLayout.zoomReadoutDoubleClickWindow(systemInterval: 0.5) > 0)
    }

    @Test func theWaitBeforeTheZoomMenuStaysShort() {
        // The system interval is half a second by default, and half a second
        // of nothing after a click reads as a broken control. The wait is
        // capped well under that, so a single click still feels like a click.
        #expect(EditorChromeLayout.zoomReadoutDoubleClickWindow(systemInterval: 0.5) <= 0.25)
        #expect(EditorChromeLayout.zoomReadoutDoubleClickWindow(systemInterval: 1.5) <= 0.25)
    }

    @Test func aFastDoubleClickSettingIsHonoured() {
        // Someone who has set a fast double click gets an even shorter wait:
        // there is no point waiting longer than the machine will ever call a
        // double click.
        #expect(EditorChromeLayout.zoomReadoutDoubleClickWindow(systemInterval: 0.15) == 0.15)
    }

    // MARK: Tool bar fit

    @Test func theBudgetIsTheCanvasLessOneInsetEachSide() {
        #expect(EditorChromeLayout.toolBarBudget(canvasWidth: 435)
                == 435 - 2 * EditorChromeLayout.toolBarInset)
    }

    @Test func aCanvasNarrowerThanItsInsetsHasNoBudget() {
        #expect(EditorChromeLayout.toolBarBudget(canvasWidth: 10) == 0)
    }

    @Test func aBarThatFitsKeepsEveryTool() {
        #expect(EditorChromeLayout.fittedToolCount(current: 13, maximum: 13,
                                                   contentWidth: 400, budget: 900) == 13)
    }

    @Test func aBarThatOverflowsDropsEnoughToolsInOneStep() {
        // The measured case: a 435pt canvas (budget 403) with the full 902pt
        // bar. Stepping one tool per layout pass never converged, because
        // SwiftUI stops feeding the measurement back after a couple of passes.
        // One step has to be able to cross the whole gap.
        let fitted = EditorChromeLayout.fittedToolCount(current: 13, maximum: 13,
                                                        contentWidth: 902, budget: 403)
        // 499pt of overflow is twelve slots' worth, so one step has to shed
        // twelve, not one.
        #expect(fitted <= 1)
        let shed = CGFloat(13 - fitted) * EditorChromeLayout.toolBarSlotWidth
        #expect(902 - shed <= 403)
    }

    @Test func droppingToolsNeverGoesBelowNone() {
        #expect(EditorChromeLayout.fittedToolCount(current: 2, maximum: 13,
                                                   contentWidth: 900, budget: 100) == 0)
    }

    @Test func anOverflowingBarAlwaysDropsAtLeastOneTool() {
        // Even a one-point overflow has to make progress, or the bar sits
        // one point over the edge forever.
        #expect(EditorChromeLayout.fittedToolCount(current: 5, maximum: 13,
                                                   contentWidth: 404, budget: 403) == 4)
    }

    @Test func aBarWithRoomToSpareGrowsBackInOneStep() {
        // 403pt of slack is several slots' worth, so the bar should not need one
        // layout pass per slot to use it.
        let grown = EditorChromeLayout.fittedToolCount(current: 0, maximum: 13,
                                                       contentWidth: 400, budget: 803)
        #expect(grown >= 5)
        #expect(grown <= 13)
    }

    @Test func growingCountsEverySlotAtItsWidest() {
        // Measured on the running app: pulling back to one tool left a 267pt
        // bar in a 403pt budget, and the next three slots cost 151pt, not the
        // 126pt three average slots would. Growing on the average overshot and
        // put the bar back over the edge, where it stuck.
        let grown = EditorChromeLayout.fittedToolCount(current: 1, maximum: 13,
                                                       contentWidth: 267, budget: 403)
        #expect(grown <= 3)
        #expect(grown > 1)
    }

    @Test func shrinkingThenGrowingSettlesInsideTheBudget() {
        // Walk the real trajectory: full bar on a 435pt canvas, then the
        // measured width at each count, and check it lands fitting and stays.
        let widths: [Int: CGFloat] = [13: 895, 1: 267, 2: 334, 3: 376, 4: 418]
        var count = 13
        var seen: [Int] = [count]
        for _ in 0..<6 {
            guard let width = widths[count] else { break }
            let next = EditorChromeLayout.fittedToolCount(current: count, maximum: 13,
                                                          contentWidth: width, budget: 403)
            if next == count { break }
            count = next
            seen.append(count)
        }
        #expect(widths[count].map { $0 <= 403 } == true, "settled at \(count) via \(seen)")
    }

    @Test func growingStopsAtTheFullSetOfTools() {
        #expect(EditorChromeLayout.fittedToolCount(current: 12, maximum: 13,
                                                   contentWidth: 100, budget: 2000) == 13)
    }

    @Test func aBarWithLessThanOneSlotOfSlackStaysPut() {
        // The anti-oscillation rule: only grow when the next tool is sure to
        // fit, so the bar cannot flip between two counts every frame.
        #expect(EditorChromeLayout.fittedToolCount(current: 6, maximum: 13,
                                                   contentWidth: 390, budget: 403) == 6)
    }

    @Test func fittingIsStableOnceItConverges() {
        // Feed the result back in: a converged count must not move again.
        let count = EditorChromeLayout.fittedToolCount(current: 13, maximum: 13,
                                                       contentWidth: 902, budget: 403)
        // At that count the bar measures its residual; re-fitting must hold.
        #expect(EditorChromeLayout.fittedToolCount(current: count, maximum: 13,
                                                   contentWidth: 380, budget: 403) == count)
    }

    // MARK: The zoom slider gives way before the tools do

    @Test func theZoomSliderShowsOnARoomyCanvas() {
        #expect(EditorChromeLayout.showsZoomSlider(canvasWidth: 1135) == true)
    }

    @Test func theZoomSliderGivesWayOnACrampedCanvas() {
        // 700pt window with the inspector docked leaves a 435pt canvas: the
        // slider alone is a quarter of it.
        #expect(EditorChromeLayout.showsZoomSlider(canvasWidth: 435) == false)
    }

    @Test func theZoomSliderThresholdSitsAboveTheNarrowestCanvas() {
        #expect(EditorChromeLayout.zoomSliderMinCanvasWidth > 435)
    }

    // MARK: Tool options give way before the bar leaves the picture

    @Test func toolOptionsLayOutInFullOnARoomyCanvas() {
        #expect(EditorChromeLayout.showsFullToolOptions(canvasWidth: 1135) == true)
    }

    @Test func toolOptionsCompactOnACrampedCanvas() {
        // The measured case: a 700pt window with the inspector docked leaves a
        // 435pt canvas (403pt of budget). With the wand in hand the bar has
        // already shed every tool it has and still measures 473pt, because the
        // Tolerance label, slider and readout are 176pt of it that nothing can
        // shed, so 35pt of capsule hangs off each end of the picture.
        #expect(EditorChromeLayout.showsFullToolOptions(canvasWidth: 435) == false)
    }

    @Test func theToolOptionsThresholdClearsTheIrreducibleBar() {
        // At the threshold the bar with NO tools inline, full options, colors
        // and zoom measures 473pt, so the budget there has to cover it.
        let t = EditorChromeLayout.toolOptionsMinCanvasWidth
        #expect(EditorChromeLayout.toolBarBudget(canvasWidth: t) >= 473)
    }

    @Test func toolOptionsSurviveNarrowerThanTheZoomSlider() {
        // The zoom slider has ⌘0, ⌘1, pinch and a menu, so it can simply go.
        // Tool options have no equivalent, so they compact rather than vanish
        // and they do it later, at a narrower canvas than the slider leaves at.
        #expect(EditorChromeLayout.toolOptionsMinCanvasWidth
                < EditorChromeLayout.zoomSliderMinCanvasWidth)
    }

    @Test func theCompactToolOptionsFitTheMeasuredCrampedBar() {
        // Measured offscreen against the real bar views: 297pt without any
        // options, and the compact Tolerance chip adds 69pt of it.
        let budget = EditorChromeLayout.toolBarBudget(canvasWidth: 435)
        #expect(297 + 69 <= budget)
    }

    // MARK: The grid's chip goes when the zoom slider goes

    @Test func theGridChipShowsOnARoomyCanvas() {
        #expect(EditorChromeLayout.showsGridChip(canvasWidth: 1135) == true)
    }

    @Test func theGridChipGivesWayOnACrampedCanvas() {
        // The measured cramped case: a 700pt window with the inspector docked
        // leaves a 435pt canvas, where the bar has already shed every tool it
        // has. One more capsule there hangs off the end of the picture.
        #expect(EditorChromeLayout.showsGridChip(canvasWidth: 435) == false)
    }

    @Test func theGridChipAndTheZoomSliderLeaveTogether() {
        // Both are chrome for how the canvas is being LOOKED at, and both have
        // a full keyboard and menu equivalent, so they are the first two things
        // the bar sheds and they go at the same width.
        #expect(EditorChromeLayout.gridChipMinCanvasWidth
                == EditorChromeLayout.zoomSliderMinCanvasWidth)
    }

    @Test func theGridChipThresholdClearsTheWidestBarPlusTheChip() {
        // At the threshold the bar with no tools inline, full tool options,
        // colors and zoom measures 473pt, and the chip is under 90pt.
        let t = EditorChromeLayout.gridChipMinCanvasWidth
        #expect(EditorChromeLayout.toolBarBudget(canvasWidth: t) >= 473 + 90)
    }

    // MARK: Crop's options are wider than the wand's, so they give way sooner

    @Test func cropOptionsLayOutInFullOnARoomyCanvas() {
        #expect(EditorChromeLayout.showsFullCropOptions(canvasWidth: 1135) == true)
    }

    @Test func cropOptionsCompactOnACrampedCanvas() {
        // The measured case: a 700pt window with the inspector docked leaves a
        // 435pt canvas (403pt of budget). With crop in hand the bar has already
        // shed every tool it has and still measures 505pt, because the four
        // aspect chips plus the tick and the cross are 231pt of it that nothing
        // can shed, so 51pt of capsule hangs off each end of the picture.
        #expect(EditorChromeLayout.showsFullCropOptions(canvasWidth: 435) == false)
    }

    @Test func theCropThresholdClearsCropsIrreducibleBar() {
        // At the threshold the bar with NO tools inline, all four aspect locks,
        // the tick, the cross, the colors and the zoom menu measures 505pt, so
        // the budget there has to cover it.
        let t = EditorChromeLayout.cropOptionsMinCanvasWidth
        #expect(EditorChromeLayout.toolBarBudget(canvasWidth: t) >= 505)
    }

    @Test func cropGivesWaySoonerThanTheWand() {
        // Crop's options are 231pt of bar to the wand's 176pt, so the canvas
        // that still holds them has to be wider. The wand's threshold does NOT
        // cover crop: the budget at 520 is 488, and crop's bar is 505.
        #expect(EditorChromeLayout.cropOptionsMinCanvasWidth
                > EditorChromeLayout.toolOptionsMinCanvasWidth)
        #expect(EditorChromeLayout.toolBarBudget(
            canvasWidth: EditorChromeLayout.toolOptionsMinCanvasWidth) < 505)
    }

    @Test func theCompactCropOptionsFitTheMeasuredCrampedBar() {
        // Measured offscreen against the real bar views: 274pt without any
        // options, and the compact chip plus the tick and the cross add 118pt.
        let budget = EditorChromeLayout.toolBarBudget(canvasWidth: 435)
        #expect(274 + 118 <= budget)
    }

    @Test func compactCropOptionsLeaveTooLittleSlackToGrowAToolBack() {
        // Freeing 113pt must not hand the fit loop enough room to put a tool
        // back, or the bar would grow, overflow, compact, and flip forever.
        // Measured: the compacted crop bar is 392pt, leaving 11pt of slack
        // against a 68pt widest slot.
        let budget = EditorChromeLayout.toolBarBudget(canvasWidth: 435)
        #expect(EditorChromeLayout.fittedToolCount(current: 0, maximum: 13,
                                                   contentWidth: 392,
                                                   budget: budget) == 0)
    }

    @Test func theFullCropBarDoesNotOscillateJustAboveItsThreshold() {
        // Just above the threshold the full options come back and the bar is
        // 505pt. If that left a full slot of slack the fit loop would put a
        // tool back, overflow, and start the whole cycle over.
        let budget = EditorChromeLayout.toolBarBudget(
            canvasWidth: EditorChromeLayout.cropOptionsMinCanvasWidth)
        #expect(EditorChromeLayout.fittedToolCount(current: 0, maximum: 13,
                                                   contentWidth: 505,
                                                   budget: budget) == 0)
    }

    @Test func compactToolOptionsLeaveTooLittleSlackToGrowAToolBack() {
        // Freeing 107pt must not hand the fit loop enough room to put a tool
        // back, or the bar would grow, overflow, compact, and flip forever.
        // Measured: the compacted bar is 366pt, leaving 37pt of slack against
        // a 68pt widest slot.
        let budget = EditorChromeLayout.toolBarBudget(canvasWidth: 435)
        let compactBar: CGFloat = 366
        #expect(EditorChromeLayout.fittedToolCount(current: 0, maximum: 13,
                                                   contentWidth: compactBar,
                                                   budget: budget) == 0)
    }

    // MARK: Bottom chrome

    @Test func theNoticePillSitsCenteredAboveTheToolBar() {
        let canvas = CGSize(width: 800, height: 600)
        let pill = EditorChromeLayout.bottomNoticeFrame(canvasSize: canvas,
                                                        noticeSize: CGSize(width: 360, height: 34))
        #expect(pill.midX == 400)
        #expect(pill.maxY == 600 - EditorChromeLayout.aboveToolBar)
        #expect(pill.width == 360 && pill.height == 34)
        let bar = EditorChromeLayout.toolBarFrame(canvasSize: canvas, toolBarWidth: 500)
        #expect(bar.midX == 400)
        #expect(bar.maxY == 600 - EditorChromeLayout.toolBarInset)
        #expect(bar.height == EditorChromeLayout.toolBarHeight)
        #expect(bar.width == 500)
        #expect(!pill.intersects(bar))
        #expect(EditorChromeLayout.bottomChrome(canvasSize: canvas, toolBarWidth: 500,
                                                noticeSize: pill.size) == [pill, bar])
    }

    @Test func anUnmeasuredToolBarReservesItsWholeBudget() {
        // Before the bar has been measured (or if it somehow overflows) the
        // reservation is the widest it can be, never wider than the canvas
        // allows: over-reserving only moves the legend up a little sooner.
        let canvas = CGSize(width: 480, height: 400)
        let budget = EditorChromeLayout.toolBarBudget(canvasWidth: 480)
        #expect(EditorChromeLayout.toolBarFrame(canvasSize: canvas, toolBarWidth: 0).width == budget)
        #expect(EditorChromeLayout.toolBarFrame(canvasSize: canvas, toolBarWidth: 9_999).width == budget)
        #expect(EditorChromeLayout.toolBarFrame(canvasSize: canvas, toolBarWidth: 300).width == 300)
    }

    // MARK: The tool settings capsule

    @Test func withNoCapsuleTheStackIsExactlyWhatItWasBefore() {
        // The capsule is a Next flag. With it absent, or with a tool that has
        // nothing to set, every bottom overlay must land where it always did.
        #expect(EditorChromeLayout.aboveToolBar(toolSettingsHeight: 0)
                == EditorChromeLayout.aboveToolBar)
        let canvas = CGSize(width: 800, height: 600)
        #expect(EditorChromeLayout.toolSettingsFrame(canvasSize: canvas,
                                                     width: 300, height: 0) == nil)
        #expect(EditorChromeLayout.toolSettingsFrame(canvasSize: canvas,
                                                     width: 0, height: 44) == nil)
    }

    @Test func theCapsuleSitsCenteredInItsOwnRowAboveTheBar() {
        let canvas = CGSize(width: 800, height: 600)
        let capsule = EditorChromeLayout.toolSettingsFrame(canvasSize: canvas,
                                                           width: 320, height: 44)
        let bar = EditorChromeLayout.toolBarFrame(canvasSize: canvas, toolBarWidth: 500)
        #expect(capsule != nil)
        guard let capsule else { return }
        #expect(capsule.midX == 400)
        #expect(capsule.width == 320 && capsule.height == 44)
        // Its own row: clear of the bar, with the same gap every stacked
        // surface keeps, so the two never read as one control.
        #expect(!capsule.intersects(bar))
        #expect(bar.minY - capsule.maxY == EditorChromeLayout.toolBarStackGap)
    }

    @Test func theCapsuleNeverRunsOffTheEdgeOfThePicture() {
        // A capsule too wide for the canvas is pulled back to the same budget
        // the bar gets, which is what makes it wrap rather than overhang.
        let canvas = CGSize(width: 480, height: 400)
        let budget = EditorChromeLayout.toolBarBudget(canvasWidth: 480)
        let capsule = EditorChromeLayout.toolSettingsFrame(canvasSize: canvas,
                                                           width: 9_999, height: 44)
        #expect(capsule?.width == budget)
        #expect(capsule?.minX == EditorChromeLayout.toolBarInset)
    }

    @Test func aNoticeClearsTheCapsuleAsWellAsTheBar() {
        // Measure is one of the tools WITH a capsule, and its hint pill parks
        // at this exact band, so a hint that only clears the bar lands on top
        // of the capsule the moment the tool is picked up.
        let canvas = CGSize(width: 800, height: 600)
        let capsuleHeight: CGFloat = 44
        let pill = EditorChromeLayout.bottomNoticeFrame(
            canvasSize: canvas, noticeSize: CGSize(width: 360, height: 34),
            toolSettingsHeight: capsuleHeight)
        let capsule = EditorChromeLayout.toolSettingsFrame(canvasSize: canvas,
                                                           width: 320, height: capsuleHeight)
        #expect(capsule != nil)
        #expect(!pill.intersects(capsule!))
        #expect(pill.maxY == capsule!.minY - EditorChromeLayout.toolBarStackGap)
    }

    @Test func theLegendKeepsClearOfTheCapsuleToo() {
        let canvas = CGSize(width: 800, height: 600)
        let notice = CGSize(width: 360, height: 34)
        let chrome = EditorChromeLayout.bottomChrome(
            canvasSize: canvas, toolBarWidth: 500, noticeSize: notice,
            toolSettingsSize: CGSize(width: 320, height: 44))
        #expect(chrome.count == 3)
        // ...and with no capsule it is the two rects it always was.
        #expect(EditorChromeLayout.bottomChrome(canvasSize: canvas, toolBarWidth: 500,
                                                noticeSize: notice).count == 2)
    }

    // MARK: Corner chrome

    @Test func aCornerSlotSitsOneSharedInsetOffBothEdges() {
        // The legend is the only thing parked in a canvas corner now — the
        // panel toggle moved into the window's title bar on 2026-09-06 — but
        // the inset stays the shared one, so anything that joins it lines up.
        #expect(EditorChromeLayout.cornerInset == 12)
        let canvas = CGSize(width: 1015, height: 808)
        let legend = PanelPlacement.frame(for: .topTrailing,
                                          size: CGSize(width: 140, height: 58),
                                          in: canvas,
                                          inset: EditorChromeLayout.cornerInset)
        #expect(legend.minY == EditorChromeLayout.cornerInset)
        #expect(legend.maxX == 1015 - EditorChromeLayout.cornerInset)
    }
}

/// The grid's capsule is one thing now: four controls that fit or do not. It
/// used to shed the slider first and keep a readout, back when the slider sat
/// on the bar; the cell is a button today, so there is nothing left to shed.
@Suite("The grid's tool bar capsule")
struct GridToolBarCapsuleTests {

    @Test func aRoomyCanvasGetsIt() {
        #expect(EditorChromeLayout.showsGridChip(
            canvasWidth: EditorChromeLayout.gridChipMinCanvasWidth + 100))
    }

    @Test func aCrampedCanvasDoesNot() {
        #expect(!EditorChromeLayout.showsGridChip(
            canvasWidth: EditorChromeLayout.gridChipMinCanvasWidth - 1))
    }

    /// The grid asks for exactly the room the zoom slider asks for, so the bar
    /// sheds both together rather than in a stutter.
    @Test func itIsTheSameThresholdTheZoomSliderUses() {
        #expect(EditorChromeLayout.gridChipMinCanvasWidth
                == EditorChromeLayout.zoomSliderMinCanvasWidth)
    }

    // MARK: A grid that is not drawn takes one icon and no more

    @Test func aGridThatIsOffIsOneIcon() {
        #expect(EditorChromeLayout.gridChipParts(canvasWidth: 1135,
                                                 isGridVisible: false) == [.settings])
    }

    @Test func aGridThatIsOnCarriesTheCellAndTheGearToo() {
        #expect(EditorChromeLayout.gridChipParts(canvasWidth: 1135,
                                                 isGridVisible: true)
                == [.settings, .cell, .adjust])
    }

    /// The cell and the gear act on lines that are on the picture. With no
    /// lines there they would be room asked for to do nothing.
    @Test func theCellAndTheGearNeedLinesOnThePicture() {
        let off = EditorChromeLayout.gridChipParts(canvasWidth: 1135, isGridVisible: false)
        #expect(!off.contains(.cell))
        #expect(!off.contains(.adjust))
    }

    /// Off and on and off again is the same bar it started as, which is what
    /// keeps everything beside the grid from creeping across the bar.
    @Test func switchingItOffAndOnLeavesTheBarWhereItStarted() {
        let first = EditorChromeLayout.gridChipParts(canvasWidth: 1135, isGridVisible: false)
        _ = EditorChromeLayout.gridChipParts(canvasWidth: 1135, isGridVisible: true)
        let again = EditorChromeLayout.gridChipParts(canvasWidth: 1135, isGridVisible: false)
        #expect(first == again)
    }

    /// A canvas too cramped for the capsule gets nothing, grid or no grid: the
    /// View menu is the whole feature down there.
    @Test func aCrampedCanvasGetsNoneOfIt() {
        #expect(EditorChromeLayout.gridChipParts(canvasWidth: 435,
                                                 isGridVisible: true).isEmpty)
        #expect(EditorChromeLayout.gridChipParts(canvasWidth: 435,
                                                 isGridVisible: false).isEmpty)
    }

    /// The icon never leaves while the capsule is there. It is the only thing
    /// on the bar saying the grid exists, and it is the door to the switch.
    @Test func theIconIsThereWheneverTheCapsuleIs() {
        for showing in [true, false] {
            #expect(EditorChromeLayout.gridChipParts(canvasWidth: 1135,
                                                     isGridVisible: showing)
                .contains(.settings))
        }
    }

    // MARK: The settings always have somewhere to open

    /// On a canvas with the capsule, the settings come out of the grid's own
    /// icon, which is what they point at.
    @Test func aRoomyCanvasOpensThemOffTheGridsIcon() {
        #expect(EditorChromeLayout.gridSettingsAnchor(canvasWidth: 1135) == .gridChip)
    }

    /// And on one without it they come out of the tool bar itself, rather than
    /// out of nothing: the View menu's row used to set a flag that no surface
    /// was reading, so choosing Grid Settings on a narrow window did nothing at
    /// all.
    @Test func aCrampedCanvasOpensThemOffTheToolBar() {
        #expect(EditorChromeLayout.gridSettingsAnchor(canvasWidth: 435) == .toolBar)
    }

    /// There is ALWAYS an answer, and only ever one. The app builds one popover
    /// per anchor and reads this to decide which, so a width that answered
    /// neither would be the original bug back, and a width that answered both
    /// would be two popovers on one flag.
    @Test func everyWidthHasExactlyOneAnchor() {
        for width in stride(from: CGFloat(0), through: 2000, by: 5) {
            let anchor = EditorChromeLayout.gridSettingsAnchor(canvasWidth: width)
            #expect(anchor == (EditorChromeLayout.showsGridChip(canvasWidth: width)
                               ? .gridChip : .toolBar))
        }
    }

    /// The anchor turns over at exactly the width the capsule does, so there is
    /// no band where the icon is on the bar and the settings open somewhere
    /// else.
    @Test func theAnchorTurnsOverWhereTheCapsuleDoes() {
        let t = EditorChromeLayout.gridChipMinCanvasWidth
        #expect(EditorChromeLayout.gridSettingsAnchor(canvasWidth: t) == .gridChip)
        #expect(EditorChromeLayout.gridSettingsAnchor(canvasWidth: t - 1) == .toolBar)
    }
}

/// The column down the right of the inspector panel: the eyes on the layer
/// rows, the locks beside them, the grip on every section header.
///
/// Reported by the user on 2026-09-07 with a line drawn through the eyes that
/// the grips missed. Measured off the running app before the fix: the eyes'
/// centres were 22.5pt in from the panel's edge, the grips' 19pt, and the lock
/// moved between 44.25 and 46.25 depending on whether the layer was locked,
/// because the closed padlock is a narrower drawing than the open one.
@Suite struct PanelEdgeColumnTests {

    /// The centre line every icon on that edge is drawn to. It is the line the
    /// eyes already made, so nothing in the layers list moved to get it.
    @Test func theCentreLineIsTheOneTheEyesAlreadyMade() {
        #expect(EditorChromeLayout.panelEdgeInset == 14)
        #expect(EditorChromeLayout.panelEdgeIconWidth == 17)
        #expect(EditorChromeLayout.panelEdgeCenterInset == 22.5)
    }

    /// The line is a distance from the panel's own right edge, so widening the
    /// panel carries the whole column with it and nothing has to be re-tuned.
    @Test func theLineFollowsThePanelWhenItIsResized() {
        for width in [220.0, 264.0, 380.0, 480.0] as [CGFloat] {
            #expect(EditorChromeLayout.panelEdgeCenterX(panelWidth: width)
                    == width - 22.5)
        }
    }

    /// A row drawn inside a list's gutter reaches the SAME line as one drawn
    /// against the panel: the gutter is subtracted rather than added to.
    @Test func aRowInsideAGutterReachesTheSameLine() {
        for gutter in [0.0, 6.0, 8.0] as [CGFloat] {
            let trailing = EditorChromeLayout.panelEdgeInset(insideGutter: gutter)
            let centre = gutter + trailing + EditorChromeLayout.panelEdgeIconWidth / 2
            #expect(centre == EditorChromeLayout.panelEdgeCenterInset)
        }
    }

    /// ...which only works while the gutter is the smaller of the two. A list
    /// inset further than the edge itself could not reach the line at all, so
    /// the shared gutter has to stay inside it.
    @Test func theListGutterStaysInsideTheEdgeInset() {
        #expect(EditorChromeLayout.panelListGutter <= EditorChromeLayout.panelEdgeInset)
        #expect(EditorChromeLayout.panelEdgeInset(insideGutter: 40) == 0)
    }

    /// Two icons of different widths in the same slot still share a centre —
    /// the whole reason the slot exists, since the padlock, the eye and the
    /// grip are three different widths.
    @Test func glyphsOfDifferentWidthsShareTheCentre() {
        func centre(ofGlyph width: CGFloat) -> CGFloat {
            // A glyph is centred in the slot, so the slot's centre is its own.
            EditorChromeLayout.panelEdgeInset
                + (EditorChromeLayout.panelEdgeIconWidth - width) / 2 + width / 2
        }
        for width in [10.5, 14.0, 14.5, 17.0] as [CGFloat] {
            #expect(centre(ofGlyph: width) == EditorChromeLayout.panelEdgeCenterInset)
        }
    }
}

/// The column down the LEFT of the inspector panel: where every row, every
/// section heading and every slider begins.
///
/// Reported by the user on 2026-09-08: the rows in Appearance started further
/// in than the panel's own margin, so the section's content did not line up
/// with its heading or with the sections above and below it. Measured off the
/// running app before the fix, from the panel's own left edge: a section
/// heading's chevron at 14, its title at 25.5, Position & Size's first field
/// label at 14 — and, in Appearance, the Opacity label, every part name and
/// the Corner Radius label all at 38. The 38 was 14 plus the width of the tick
/// column, left behind when the tick moved to the front of the row: an indent
/// standing in for a control the row did not have.
@Suite struct PanelStartColumnTests {

    /// One margin, both edges. The number a ruler on a screenshot measures from
    /// the panel's left edge to the start of anything inside it.
    @Test func bothEdgesOfAPanelUseTheOneMargin() {
        #expect(EditorChromeLayout.panelEdgeInset == 14)
        #expect(EditorChromeLayout.panelStartInset == EditorChromeLayout.panelEdgeInset)
    }

    /// A row's leading control — a tick, a chevron — is drawn INSIDE the row,
    /// in a column the row holds open whether or not it has one to put there.
    /// So a row with a tick and a row without still begin on the margin.
    @Test func aLeadingControlSitsInsideTheRowRatherThanPushingItIn() {
        let column = EditorChromeLayout.panelRowLeadingColumn
        let gap = EditorChromeLayout.panelRowGap
        #expect(column > 0 && gap > 0)
        // Whatever is in the column, the row starts at the margin.
        #expect(EditorChromeLayout.panelStartInset == 14)
        // ...and what follows the column starts one column and one gap in.
        #expect(EditorChromeLayout.panelSubsectionIndent == column + gap)
    }

    /// The ONE reason anything steps in further: it is a subsection folded
    /// under the row above it. It steps in by exactly the leading column, so
    /// its content starts under its parent's NAME and the fold reads as a
    /// bracket rather than as a second margin.
    @Test func theOnlyIndentIsASubsectionAndItLandsUnderItsParentsName() {
        #expect(EditorChromeLayout.panelSubsectionIndent == 24)
        #expect(EditorChromeLayout.panelSubsectionStartInset
                == EditorChromeLayout.panelStartInset + 24)
    }

    /// The indent is a distance from the panel's own left edge, so resizing the
    /// panel carries it and nothing has to be re-tuned — the mirror of the
    /// promise the right hand column already makes.
    @Test func theMarginFollowsThePanelWhenItIsResized() {
        for width in [220.0, 264.0, 380.0, 480.0] as [CGFloat] {
            let content = width - EditorChromeLayout.panelStartInset
                - EditorChromeLayout.panelEdgeInset
            #expect(content == width - 28)
        }
    }

    // MARK: One glass bar

    @Test func theOneBarAlwaysHasItsToolsAndNeverAZoom() {
        // The tool bar holds tools. Zoom is not a tool (the user, 2026-09-29):
        // it is pinch, Cmd +/-, Cmd 0, Cmd 1 and the View menu, never a
        // control on this bar, whatever else is on it.
        #expect(EditorChromeLayout.toolBarSections(showsColor: false) == [.tools])
        for color in [false, true] {
            #expect(!EditorChromeLayout.toolBarSections(showsColor: color)
                .map(\.rawValue).contains("zoom"))
        }
    }

    @Test func theOneBarPutsTheColourPairAfterTheTools() {
        // The mock's order: the tool strip and More, then the colour pair and
        // its swap.
        #expect(EditorChromeLayout.toolBarSections(showsColor: true) == [.tools, .color])
    }

    @Test func theOneBarCarriesNoGrid() {
        // The grid is a way of looking at the picture, so it is the View
        // menu's (Show Grid, Grid Settings, Snap to Grid, Adjust Grid), not a
        // section of the bar that holds tools (the placement contract).
        for color in [false, true] {
            #expect(!EditorChromeLayout.toolBarSections(showsColor: color)
                .map(\.rawValue).contains("grid"))
        }
        #expect(EditorChromeLayout.gridChipParts(canvasWidth: 1600, isGridVisible: true,
                                                 oneGlass: true).isEmpty)
    }

    @Test func onTheOneBarTheGridsSettingsRiseOutOfTheBar() {
        // With no grid icon on the bar, the View menu's Grid Settings opens
        // its popover off the bar as a whole, at every width.
        for width in stride(from: CGFloat(0), through: 2000, by: 50) {
            #expect(EditorChromeLayout.gridSettingsAnchor(canvasWidth: width, oneGlass: true)
                    == .toolBar)
        }
    }

    @Test func aHairlineSitsBetweenEveryPairOfSectionsAndNowhereElse() {
        // A hairline before a section exactly when something came before it:
        // never at the ends of the bar, never two in a row where a section
        // is missing.
        let sections = EditorChromeLayout.toolBarSections(showsColor: true)
        let hairlines = sections.indices.filter {
            EditorChromeLayout.toolBarHasHairline(before: $0)
        }
        #expect(hairlines == [1])
        #expect(!EditorChromeLayout.toolBarHasHairline(before: 0))
    }

    @Test func theOneBarSpacesItsHairlinesLikeTheMock() {
        // The hairline between sections sits as far from its neighbours as
        // the one between tool families does, so the whole bar reads with one
        // rhythm.
        let one = EditorChromeLayout.ToolBarSpacing.oneGlass
        // Tool edge to hairline is the tools' gap plus the hairline's own
        // margin, and the hairline between sections sits exactly that far
        // from its neighbours plus the section step, the way the mock's
        // `.tsep` sits in its strip and in its bar.
        #expect(one.toolGap + one.hairlineMargin == 6)
        #expect(one.sectionGap == 8)
    }

    // MARK: The one bar is as tight as the mock

    @Test func theOneBarPacksItsToolsAsTightlyAsTheMock() {
        // video.html's `.tool` is 30pt wide with 2pt between, so a glyph every
        // 32pt. The app's tools are 28pt circles, so 4pt between keeps the same
        // step. Before this the one bar kept the separate capsules' 14pt.
        let one = EditorChromeLayout.ToolBarSpacing.oneGlass
        #expect(one.toolGap == 4)
        #expect(one.slotWidth == 32)
    }

    @Test func theOneBarDrawsTheMocksHairlines() {
        // The mock's `.tsep` is 18pt tall; the separate capsules keep 20.
        #expect(EditorChromeLayout.ToolBarSpacing.oneGlass.hairlineHeight == 18)
        #expect(EditorChromeLayout.ToolBarSpacing.capsules.hairlineHeight == 20)
    }

    // MARK: The one bar is as short as the mock

    @Test func theOneBarIsAsTallAsTheMocksBar() {
        // video.html's `.tbar` is a 28pt row with 4pt of padding above and
        // below inside a 1pt edge: 38pt. The one bar was 48pt, the separate
        // capsules' height, and covered 10pt more of the picture than drawn.
        let one = EditorChromeLayout.ToolBarSpacing.oneGlass
        #expect(one.height == 38)
        #expect(one.height == EditorChromeLayout.toolBarControlSize + 2 * (4 + 1))
    }

    @Test func separateCapsulesKeepTheirHeight() {
        // Current's capsules are not this task's: 48pt, as measured.
        let capsules = EditorChromeLayout.ToolBarSpacing.capsules
        #expect(capsules.height == 48)
        #expect(capsules.height == EditorChromeLayout.toolBarGroupHeight)
        #expect(capsules.height == EditorChromeLayout.toolBarHeight)
    }

    @Test func theOneBarsEndsSitWhereTheMocksDo() {
        // The mock's bar runs 8pt of padding plus its 1pt edge past its end
        // tools. The separate tools capsule keeps 18pt.
        #expect(EditorChromeLayout.ToolBarSpacing.oneGlass.endPadding == 9)
    }

    @Test func theOneBarsZoomSliderIsTheMocksLength() {
        // `.zslider` is 92pt; the separate zoom capsule keeps 110pt.
        #expect(EditorChromeLayout.ToolBarSpacing.oneGlass.zoomSliderWidth == 92)
        #expect(EditorChromeLayout.ToolBarSpacing.capsules.zoomSliderWidth == 110)
    }

    @Test func aFitClearsTheShorterBarsBandAndNoMore() {
        // A fitted picture keeps clear of the bar in use: 16pt off the floor
        // plus 38pt of bar, so a picture gains back the 10pt the bar gave up.
        let one = EditorChromeLayout.ToolBarSpacing.oneGlass
        #expect(EditorChromeLayout.toolBarCovers(bar: one) == 54)
        #expect(EditorChromeLayout.toolBarCovers(bar: .capsules) == EditorChromeLayout.toolBarCovers)
        let canvas = CGSize(width: 900, height: 600)
        let bar = EditorChromeLayout.toolBarFrame(canvasSize: canvas, toolBarWidth: 500, bar: one)
        #expect(bar.height == 38)
        #expect(bar.maxY == canvas.height - EditorChromeLayout.toolBarInset)
        #expect(bar.minY == canvas.height - EditorChromeLayout.toolBarCovers(bar: one))
    }

    @Test func whatStacksAboveTheShorterBarStaysClearOfIt() {
        // The notice pill, the crop and trim capsules and the tool settings
        // capsule all stack one gap above the bar in use, never inside it and
        // never floating 10pt higher than they need to.
        let one = EditorChromeLayout.ToolBarSpacing.oneGlass
        #expect(EditorChromeLayout.aboveToolBar(toolSettingsHeight: 0, bar: one) == 66)   // 16 + 38 + 12
        #expect(EditorChromeLayout.aboveToolBar(toolSettingsHeight: 44, bar: one) == 122) // + 44 + 12
        #expect(EditorChromeLayout.aboveToolBar(toolSettingsHeight: 44, bar: .capsules)
                == EditorChromeLayout.aboveToolBar(toolSettingsHeight: 44))

        let canvas = CGSize(width: 800, height: 600)
        let bar = EditorChromeLayout.toolBarFrame(canvasSize: canvas, toolBarWidth: 400, bar: one)
        let settings = EditorChromeLayout.toolSettingsFrame(canvasSize: canvas, width: 300,
                                                            height: 44, bar: one)
        #expect(settings?.maxY == bar.minY - EditorChromeLayout.toolBarStackGap)
        let chrome = EditorChromeLayout.bottomChrome(canvasSize: canvas, toolBarWidth: 400,
                                                     noticeSize: CGSize(width: 200, height: 30),
                                                     toolSettingsSize: CGSize(width: 300, height: 44),
                                                     bar: one)
        #expect(chrome.count == 3)
        #expect(chrome.last == bar)
        for (index, rect) in chrome.enumerated() {
            for other in chrome[(index + 1)...] { #expect(!rect.intersects(other)) }
        }
        #expect(chrome[0].maxY == 600 - EditorChromeLayout.aboveToolBar(toolSettingsHeight: 44, bar: one))
    }

    @Test func separateCapsulesKeepTheirSpacing() {
        // Current's row of capsules is not this task's: its numbers stay.
        let capsules = EditorChromeLayout.ToolBarSpacing.capsules
        #expect(capsules.toolGap == 14)
        #expect(capsules.endPadding == 18)
        #expect(capsules.slotWidth == EditorChromeLayout.toolBarSlotWidth)
        #expect(capsules.widestSlotWidth == EditorChromeLayout.toolBarWidestSlotWidth)
        #expect(EditorChromeLayout.ToolBarSpacing.bar(oneGlass: false) == capsules)
        #expect(EditorChromeLayout.ToolBarSpacing.bar(oneGlass: true) == .oneGlass)
    }

    @Test func theTightBarShedsEnoughToolsInOneStep() {
        // With 32pt slots, counting the old 42pt ones sheds too few: 100pt
        // over is three old slots but only 96pt of the new ones, and the bar
        // would sit 4pt past the edge until another layout pass that SwiftUI
        // may never send.
        let one = EditorChromeLayout.ToolBarSpacing.oneGlass
        let fitted = EditorChromeLayout.fittedToolCount(current: 13, maximum: 13,
                                                        contentWidth: 503, budget: 403,
                                                        spacing: one)
        #expect(CGFloat(503) - CGFloat(13 - fitted) * one.slotWidth <= 403)
    }

    @Test func theTightBarGrowsBackOnItsOwnWidestSlot() {
        // 60pt of slack holds the widest tight slot (58pt) but not an old one
        // (68pt), so the tight bar puts a tool back where the old sums would not.
        let one = EditorChromeLayout.ToolBarSpacing.oneGlass
        #expect(one.widestSlotWidth == 58)
        #expect(EditorChromeLayout.fittedToolCount(current: 6, maximum: 13,
                                                   contentWidth: 343, budget: 403,
                                                   spacing: one) == 7)
    }
}
