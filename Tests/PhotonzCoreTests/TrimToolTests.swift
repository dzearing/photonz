import Testing
@testable import PhotonzCore

// Trim in Crop's slot (`docs/design/video-surface.md` §10.2).
//
// Crop and Trim are one family — change the picture's bounds, in space or in
// time — so no slot in the bar moves and no new letter is spent. C hands you
// the one you used last, C again swaps, and in a document with no duration
// there is no Trim to swap to.
@Suite("Crop and Trim as one slot")
struct TrimToolTests {

    @Test("both members answer to C, so nothing anybody has learned moves")
    func bothAnswerToC() {
        #expect(Tool.crop.shortcutKey == "c")
        #expect(Tool.trim.shortcutKey == "c")
        #expect(ToolGroup.bounds.tools == [.crop, .trim])
        #expect(ToolGroup.containing(.trim) == .bounds)
        #expect(ToolGroup.containing(.crop) == .bounds)
    }

    @Test("C walks the pair, and the pair is all C walks")
    func cWalksThePair() {
        #expect(ToolGroup.bounds.tools(answeringTo: "c") == [.crop, .trim])
        #expect(ToolGroup.bounds.tool(forKey: "c", active: .crop, remembered: .crop) == .trim)
        #expect(ToolGroup.bounds.tool(forKey: "c", active: .trim, remembered: .trim) == .crop)
        // Coming from somewhere else hands back the member you used last.
        #expect(ToolGroup.bounds.tool(forKey: "c", active: .select, remembered: .trim) == .trim)
        #expect(ToolGroup.bounds.tool(forKey: "c", active: .select, remembered: .crop) == .crop)
        #expect(ToolGroup.bounds.swapKeys == ["c"])
        #expect(ToolGroup.bounds.cycleKeys == ["c"])
    }

    @Test("a document with no duration is offered Crop and nothing else")
    func filteredToWhatIsOnOffer() {
        let stills: Set<Tool> = [.crop]
        #expect(ToolGroup.bounds.tools(offered: stills) == [.crop])
        #expect(ToolGroup.bounds.tools(answeringTo: "c", offered: stills) == [.crop])
        // C twice does nothing new: there is no second member to swap to.
        #expect(ToolGroup.bounds.tool(forKey: "c", active: .crop, remembered: .crop,
                                      offered: stills) == .crop)
        // And nothing teaches a swap that cannot happen.
        #expect(ToolGroup.bounds.swapKeys(offered: stills).isEmpty)
        // A family filtered down to nothing still stands for its first member
        // rather than vanishing, because a slot that vanishes is a slot that
        // moves.
        #expect(ToolGroup.bounds.tools(offered: []) == [.crop])
    }

    @Test("Trim keeps Crop's slot rather than taking one of its own")
    func keepsCropsSlot() {
        let bar = ToolBarLayout.bar(withFrame: false)
        #expect(bar.entries.contains(.tool(.crop)))
        #expect(bar.entries.contains(.tool(.trim)) == false)
        #expect(bar.entry(for: .crop) == .tool(.crop))
        #expect(bar.entry(for: .trim) == .tool(.crop))
        // The slot is where it always was: fourth in the first family, after
        // Select and the marquee.
        #expect(bar.families.first?.firstIndex(of: .tool(.crop)) == 2)
    }

    @Test("Trim adds nothing to the picture and paints nothing")
    func trimIsNotADrawingTool() {
        #expect(Tool.trim.createsLayers == false)
        #expect(Tool.trim.annotationShape == nil)
        #expect(Tool.trim.colorControl == .hidden)
        #expect(Tool.trim.paints == false)
        #expect(Tool.trim.preservesLayerSelection)
        #expect(Tool.trim.shortcutHint == "C")
    }
}
