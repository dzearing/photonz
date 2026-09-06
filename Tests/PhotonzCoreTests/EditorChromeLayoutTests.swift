import CoreGraphics
import PhotonzCore
import Testing

@Suite("EditorChromeLayout")
struct EditorChromeLayoutTests {

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

    @Test func windowFloorIsSaneAndBelowTheCollapseThreshold() {
        // The responsive behavior must be able to kick in ABOVE the floor, so
        // the auto-collapse threshold must sit strictly above the floor.
        #expect(EditorChromeLayout.minWindowWidth > 0)
        #expect(EditorChromeLayout.minWindowHeight > 0)
        #expect(EditorChromeLayout.inspectorAutoCollapseWidth > EditorChromeLayout.minWindowWidth)
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

    @Test func theInspectorToggleSitsInTheTopRightCornerWhileThePanelIsClosed() {
        // With the panel closed the toggle is the only way back, so it floats
        // one corner inset off the top and the right edge of the canvas,
        // wherever the canvas edge is. Same inset as the legend, so the two
        // line up when they stack.
        let canvas = CGSize(width: 1015, height: 808)
        let toggle = EditorChromeLayout.inspectorToggleFrame(canvasSize: canvas,
                                                             isInspectorShown: false)
        #expect(toggle?.minY == EditorChromeLayout.cornerInset)
        #expect(toggle?.maxX == 1015 - EditorChromeLayout.cornerInset)
        #expect(toggle?.width == EditorChromeLayout.inspectorToggleSize)
        #expect(toggle?.height == EditorChromeLayout.inspectorToggleSize)
        #expect(EditorChromeLayout.cornerInset == 12)
        #expect(EditorChromeLayout.inspectorToggleSize == 30)
    }

    @Test func theCanvasCornerIsFreeWhileThePanelIsOpen() {
        // Open, the collapse button lives in the panel's own top-right corner,
        // so nothing of it is left on the canvas and the corner is free for
        // whatever wants it (the measure legend).
        let canvas = CGSize(width: 1015, height: 808)
        #expect(EditorChromeLayout.inspectorToggleFrame(canvasSize: canvas,
                                                        isInspectorShown: true) == nil)
    }
}

/// The grid's capsule sheds in two steps as the picture narrows: the controls
/// go first, then the readout, and the View menu carries the whole feature at
/// any width.
@Suite("The grid's tool bar capsule")
struct GridToolBarCapsuleTests {

    @Test func aWideCanvasGetsTheWholeThing() {
        let wide = EditorChromeLayout.gridSliderMinCanvasWidth + 100
        #expect(EditorChromeLayout.showsGridChip(canvasWidth: wide))
        #expect(EditorChromeLayout.showsGridSlider(canvasWidth: wide))
    }

    @Test func theControlsGoBeforeTheReadoutDoes() {
        let between = (EditorChromeLayout.gridChipMinCanvasWidth
                       + EditorChromeLayout.gridSliderMinCanvasWidth) / 2
        #expect(EditorChromeLayout.showsGridChip(canvasWidth: between))
        #expect(!EditorChromeLayout.showsGridSlider(canvasWidth: between))
    }

    @Test func aCrampedCanvasGetsNeither() {
        let narrow = EditorChromeLayout.gridChipMinCanvasWidth - 1
        #expect(!EditorChromeLayout.showsGridChip(canvasWidth: narrow))
        #expect(!EditorChromeLayout.showsGridSlider(canvasWidth: narrow))
    }

    /// The controls need more room than the readout, never less.
    @Test func theSliderThresholdIsTheWiderOfTheTwo() {
        #expect(EditorChromeLayout.gridSliderMinCanvasWidth
                > EditorChromeLayout.gridChipMinCanvasWidth)
    }
}
