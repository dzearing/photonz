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

    @Test func windowFloorIsSaneAndBelowTheCollapseThreshold() {
        // The responsive behavior must be able to kick in ABOVE the floor, so
        // the auto-collapse threshold must sit strictly above the floor.
        #expect(EditorChromeLayout.minWindowWidth > 0)
        #expect(EditorChromeLayout.minWindowHeight > 0)
        #expect(EditorChromeLayout.inspectorAutoCollapseWidth > EditorChromeLayout.minWindowWidth)
    }
}
