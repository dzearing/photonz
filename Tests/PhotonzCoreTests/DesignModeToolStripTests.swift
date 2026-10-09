import Foundation
import PhotonzCore
import Testing

/// A mode can put its own tools in front. The Design mode puts the tools the
/// UI entry mock draws for building screens (`ui-entry-wt.html` step 4,
/// UX-PATTERNS D4 "UI design"): Select | Frame, Shape, Pen, Text | Measure.
/// Every other tool folds under More and keeps its key and its row there, so
/// nothing is removed; leaving the mode gives the bar back.
@Suite("Design mode tool strip")
struct DesignModeToolStripTests {

    /// The bar at Next defaults: frames, lens and pen all on.
    private let bar = ToolBarLayout.bar(withFrame: true, withLens: true, withPen: true)

    private let metrics = ToolBarFold.Metrics(slot: 28, gap: 4, hairline: 5, more: 28)

    private var design: WindowMode {
        WindowModes.mode("design") ?? WindowModes.everything
    }

    private func strip(_ room: CGFloat = .greatestFiniteMagnitude,
                       layout: ToolBarLayout? = nil,
                       lit: ToolBarLayout.Entry? = nil) -> ToolBarFold {
        ToolBarFold(layout ?? bar, strip: design.toolStrip ?? [], room: room,
                    metrics: metrics, keeping: lit)
    }

    // MARK: Which modes have one

    @Test("Design asks for the mock's UI tools, in the mock's order and families")
    func designStrip() {
        #expect(design.id == "design")
        #expect(design.toolStrip == [
            [.tool(.select)],
            [.tool(.frame), .group(.shapes), .tool(.pen), .tool(.text)],
            [.tool(.measure)],
        ])
    }

    @Test("Every other mode leaves the window's own bar alone")
    func otherModesHaveNoStrip() {
        for mode in WindowModes.all where mode.id != "design" {
            #expect(mode.toolStrip == nil, "\(mode.id) should not choose tools")
        }
    }

    @Test("Zoom is not a tool, so no mode's strip holds it")
    func noZoomInAnyStrip() {
        for mode in WindowModes.all {
            let entries = (mode.toolStrip ?? []).flatMap { $0 }
            #expect(!entries.contains(.tool(.zoomCallout)))
        }
    }

    // MARK: The fold

    @Test("With room the bar shows exactly the strip, and everything else is under More")
    func roomForTheStrip() {
        let fold = strip()
        #expect(fold.shown == design.toolStrip)
        #expect(fold.folded == [.group(.selection), .tool(.crop), .tool(.arrow),
                                .tool(.highlight), .tool(.lens), .tool(.fill)])
    }

    @Test("Nothing is removed: every slot of the bar is in front or under More, once")
    func nothingRemoved() {
        let fold = strip()
        let all = fold.shownEntries + fold.folded
        #expect(Set(all) == Set(bar.entries))
        #expect(all.count == bar.entries.count)
        for tool in Tool.allCases where bar.entry(for: tool) != nil {
            #expect(fold.entry(for: tool) != nil, "\(tool) lost its slot")
        }
    }

    @Test("A strip tool the release has not switched on is left out, not drawn as a dead slot")
    func flaggedOffToolsAreLeftOut() {
        let noFrameNoPen = ToolBarLayout.bar(withFrame: false, withLens: true, withPen: false)
        let fold = strip(layout: noFrameNoPen)
        #expect(fold.shown == [[.tool(.select)], [.group(.shapes), .tool(.text)],
                               [.tool(.measure)]])
        #expect(!fold.shownEntries.contains(.tool(.frame)))
        #expect(!fold.folded.contains(.tool(.frame)))
    }

    @Test("A narrow window folds the strip from its far end, then the rest follows")
    func narrowFoldsFromTheEnd() {
        // Room for Select | Frame Shapes and More.
        let room = metrics.width(of: [[.tool(.select)], [.tool(.frame), .group(.shapes)]],
                                 more: true)
        let fold = strip(room)
        #expect(fold.shown == [[.tool(.select)], [.tool(.frame), .group(.shapes)]])
        #expect(Array(fold.folded.prefix(3)) == [.tool(.pen), .tool(.text), .tool(.measure)])
        #expect(fold.folded.count == bar.entries.count - 3)
    }

    @Test("A strip tool in hand that would fold takes the place of the last one that fit")
    func litStripToolSwapsIn() {
        let room = metrics.width(of: [[.tool(.select)], [.tool(.frame), .group(.shapes)]],
                                 more: true)
        let fold = strip(room, lit: .tool(.measure))
        // Measure is a family of its own, so its hairline costs room too: it
        // takes the place of Frame and Shapes, and Select stays first.
        #expect(fold.shown == [[.tool(.select)], [.tool(.measure)]])
        #expect(!fold.isFolded(.measure))
    }

    @Test("A tool from outside the strip in hand stays under More, so More lights")
    func litOutsideTheStripStaysFolded() {
        let fold = strip(lit: .tool(.crop))
        #expect(fold.shown == design.toolStrip)
        #expect(fold.isFolded(.crop))
        #expect(fold.lit(activeTool: .crop, bladeInHand: false) == .tool(.crop))
    }

    @Test("Asking for a family member keeps the whole family's slot")
    func stripMemberMeansItsFamily() {
        let fold = ToolBarFold(bar, strip: [[.tool(.rectangle)]],
                               room: .greatestFiniteMagnitude, metrics: metrics)
        #expect(fold.shown == [[.group(.shapes)]])
        #expect(!fold.isFolded(.ellipse))
    }
}
