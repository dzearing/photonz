import CoreGraphics
import Testing
@testable import PhotonzCore

/// Every row and control in the panel keeps the panel's side margin
/// (`every-panel-follows-the-design-system`, 2026-09-24).
///
/// The user found the four video sections drawn with no horizontal inset, so
/// their values ran into both edges of the panel, and nothing had compared a
/// section against the margin every other section keeps. This is the rule a
/// walk measures the running panel with.
@Suite("Every row keeps the panel's side margin")
struct PanelMarginRuleTests {

    /// A 280pt panel at x 1000 in the window.
    let panel = CGRect(x: 1000, y: 40, width: 280, height: 700)

    func row(_ name: String, from left: CGFloat, to right: CGFloat, y: CGFloat = 100) -> PanelMarginRule.Item {
        PanelMarginRule.Item(name: name, frame: CGRect(x: panel.minX + left, y: y,
                                                       width: right - left, height: 22))
    }

    @Test func aRowOnBothMarginsPasses() {
        let items = [row("Opacity", from: 14, to: 266)]
        #expect(PanelMarginRule.breaches(of: items, in: panel).isEmpty)
    }

    @Test func aRowFurtherInThanTheMarginPasses() {
        // A subsection steps in; a short control ends well short of the edge.
        let items = [row("Shadow ▸ Blur", from: 38, to: 200)]
        #expect(PanelMarginRule.breaches(of: items, in: panel).isEmpty)
    }

    @Test func aRowFlushWithTheLeftEdgeIsCaught() {
        let breaches = PanelMarginRule.breaches(of: [row("Scale", from: 0, to: 266)], in: panel)
        #expect(breaches == [PanelMarginRule.Breach(name: "Scale", side: .leading, inset: 0)])
    }

    @Test func aRowFlushWithTheRightEdgeIsCaught() {
        let breaches = PanelMarginRule.breaches(of: [row("Centre", from: 14, to: 280)], in: panel)
        #expect(breaches == [PanelMarginRule.Breach(name: "Centre", side: .trailing, inset: 0)])
    }

    @Test func aRowPastTheEdgeReadsAsANegativeInset() {
        // The value that ran out of the panel: its box ends 20pt past the edge.
        let breaches = PanelMarginRule.breaches(of: [row("Speed", from: 14, to: 300)], in: panel)
        #expect(breaches == [PanelMarginRule.Breach(name: "Speed", side: .trailing, inset: -20)])
    }

    @Test func aPointIsRoundingNotABreach() {
        // A text box reports its 1pt bezel to accessibility.
        let items = [row("Position Y", from: 13, to: 267)]
        #expect(PanelMarginRule.breaches(of: items, in: panel).isEmpty)
    }

    @Test func twoPointsShortIsABreach() {
        let breaches = PanelMarginRule.breaches(of: [row("Level", from: 12, to: 266)], in: panel)
        #expect(breaches == [PanelMarginRule.Breach(name: "Level", side: .leading, inset: 12)])
    }

    @Test func somethingWithNoSizeIsNotMeasured() {
        // A marker whose view has not been laid out yet, or is folded away.
        let folded = PanelMarginRule.Item(name: "Folded", frame: CGRect(x: panel.minX, y: 100, width: 0, height: 0))
        #expect(PanelMarginRule.breaches(of: [folded], in: panel).isEmpty)
    }

    @Test func somethingOutsideThePanelIsNotItsBusiness() {
        // A sheet's button, the Settings window, a control over the canvas.
        let elsewhere = PanelMarginRule.Item(name: "Cancel", frame: CGRect(x: 200, y: 300, width: 80, height: 22))
        #expect(PanelMarginRule.breaches(of: [elsewhere], in: panel).isEmpty)
    }

    @Test func bothSidesOfOneRowAreBothReported() {
        let breaches = PanelMarginRule.breaches(of: [row("Reframe", from: 2, to: 279)], in: panel)
        #expect(breaches.map(\.side) == [.leading, .trailing])
    }

    @Test func theMarginIsThePanelsOwn() {
        #expect(PanelMarginRule.margin == EditorChromeLayout.panelEdgeInset)
    }

    @Test func aBreachSaysWhatAPersonWouldMeasure() {
        let breach = PanelMarginRule.Breach(name: "Scale", side: .leading, inset: 0)
        #expect(breach.sentence == "\"Scale\" starts 0pt from the panel's left edge, not 14pt")
        let spill = PanelMarginRule.Breach(name: "Speed", side: .trailing, inset: -20)
        #expect(spill.sentence == "\"Speed\" runs 20pt past the panel's right edge")
    }

    @Test func aPanelTheWidthOfItsDockIsFine() {
        #expect(PanelMarginRule.overflow(panelWidth: 264, dockWidth: 264) == nil)
        #expect(PanelMarginRule.overflow(panelWidth: 264.6, dockWidth: 264) == nil)
    }

    @Test func aSectionThatStretchesThePanelIsCaught() {
        // A Frame picked on 2026-09-24: a section 12pt too wide for the dock,
        // centred in it, so 6pt spilled over the canvas and 6pt off the window.
        let overflow = PanelMarginRule.overflow(panelWidth: 276, dockWidth: 264)
        #expect(overflow == 12)
        #expect(PanelMarginRule.overflowSentence(12, dockWidth: 264)
                == "the panel is 12pt wider than its 264pt dock: a section in it is too wide "
                    + "to fit, so the panel spills over the canvas and off the window")
    }
}
