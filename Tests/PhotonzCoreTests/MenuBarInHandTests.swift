import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What the menu bar's rows act on when nothing was right-clicked: the tool
/// each letter picks, the marker at the playhead, the caption word under it.
///
/// A right-click acts on the thing under the pointer. The menu bar has no
/// pointer, so each of its rows acts on the thing IN HAND: the one picked, else
/// the one the playhead is standing on, the rule the Clip menu already keeps.
@Suite("The menu bar acts on the thing in hand")
struct MenuBarInHandTests {

    // MARK: Edit ▸ Tools

    @Test("Edit > Tools lists every tool on the bar, in bar order, families opened out")
    func toolsInBarOrder() {
        let layout = ToolBarLayout.bar(withFrame: true, withLens: true, withPen: true)
        let tools = ToolMenu.tools(layout, bounds: [.crop, .trim])
        #expect(tools == [.select, .rectSelect, .ellipseSelect, .wand, .crop, .trim, .measure,
                          .arrow, .line, .rectangle, .ellipse, .highlight, .text, .lens,
                          .frame, .pen, .fill])
    }

    @Test("A picture has no Trim to pick: the crop slot is Crop alone")
    func pictureHasNoTrim() {
        let tools = ToolMenu.tools(ToolBarLayout.bar(withFrame: false), bounds: [.crop])
        #expect(!tools.contains(.trim))
        #expect(tools.contains(.crop))
        #expect(tools.contains(.zoomCallout))
    }

    @Test("Each letter is printed on exactly one row, the one a press would pick right now")
    func oneRowPerLetter() {
        let tools = ToolMenu.tools(ToolBarLayout.bar(withFrame: true, withLens: true, withPen: true),
                                   bounds: [.crop, .trim])
        let printed = tools.compactMap { tool in
            ToolMenu.printedKey(for: tool, among: tools, active: .select, remembered: { $0.tools[0] })
        }
        #expect(printed.count == Set(printed).count)
        #expect(Set(printed) == ["v", "m", "w", "c", "i", "a", "l", "r", "o", "h", "t", "k", "f", "p", "g"])
    }

    @Test("M is on the marquee a press of M hands you: the other one, once one is in hand")
    func marqueeLetterFollowsThePress() {
        let tools = ToolMenu.tools(ToolBarLayout.bar(withFrame: false), bounds: [.crop])
        let remembered: (ToolGroup) -> Tool = { $0.tools[0] }
        #expect(ToolMenu.printedKey(for: .rectSelect, among: tools, active: .select, remembered: remembered) == "m")
        #expect(ToolMenu.printedKey(for: .ellipseSelect, among: tools, active: .select, remembered: remembered) == nil)
        #expect(ToolMenu.printedKey(for: .ellipseSelect, among: tools, active: .rectSelect, remembered: remembered) == "m")
        #expect(ToolMenu.printedKey(for: .rectSelect, among: tools, active: .rectSelect, remembered: remembered) == nil)
        // The wand keeps its own W whatever the marquee is doing.
        #expect(ToolMenu.printedKey(for: .wand, among: tools, active: .rectSelect, remembered: remembered) == "w")
    }

    @Test("C is on Crop in a picture, and on whichever of Crop and Trim C hands you in a video")
    func boundsLetter() {
        let picture = ToolMenu.tools(ToolBarLayout.bar(withFrame: false), bounds: [.crop])
        #expect(ToolMenu.printedKey(for: .crop, among: picture, active: .crop, remembered: { $0.tools[0] }) == "c")
        let video = ToolMenu.tools(ToolBarLayout.bar(withFrame: false), bounds: [.crop, .trim])
        let rememberTrim: (ToolGroup) -> Tool = { $0 == .bounds ? .trim : $0.tools[0] }
        #expect(ToolMenu.printedKey(for: .trim, among: video, active: .select, remembered: rememberTrim) == "c")
        #expect(ToolMenu.printedKey(for: .crop, among: video, active: .select, remembered: rememberTrim) == nil)
        #expect(ToolMenu.printedKey(for: .crop, among: video, active: .trim, remembered: rememberTrim) == "c")
    }

    @Test("The tool a key picks is what the row does, so a click and a press agree")
    func keyPicks() {
        let tools = ToolMenu.tools(ToolBarLayout.bar(withFrame: false), bounds: [.crop])
        #expect(ToolMenu.tool(forKey: "m", among: tools, active: .rectSelect, remembered: { $0.tools[0] }) == .ellipseSelect)
        #expect(ToolMenu.tool(forKey: "v", among: tools, active: .rectSelect, remembered: { $0.tools[0] }) == .select)
        #expect(ToolMenu.tool(forKey: "q", among: tools, active: .select, remembered: { $0.tools[0] }) == nil)
    }

    // MARK: Sequence ▸ Remove Marker

    private static func talk() -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1280, height: 800))
        var clip = Layer(name: "Clip", content: .text(TextContent(string: "picture")),
                         frame: CGRect(x: 0, y: 0, width: 1280, height: 800))
        clip.time = LayerTime(inMS: 0, outMS: 10_000)
        document.addLayer(clip)
        return document
    }

    @Test("The marker at the playhead is the one within a frame of it, the nearest when two are")
    func markerAtThePlayhead() {
        var document = Self.talk()
        document.addMarker(atMS: 2_000)
        document.addMarker(atMS: 2_030)
        document.addMarker(atMS: 5_000)
        let near = document.markers[1].id
        #expect(document.marker(nearMS: 2_020, withinMS: 34) == near)
        #expect(document.marker(nearMS: 5_000, withinMS: 34) == document.markers[2].id)
        #expect(document.marker(nearMS: 3_000, withinMS: 34) == nil)
        #expect(Self.talk().marker(nearMS: 0, withinMS: 34) == nil)
    }

    // MARK: Sequence ▸ Caption Word

    private static func word(_ text: String, _ startMS: Int, _ endMS: Int) -> TranscribedWord {
        TranscribedWord(text, startMS: startMS, endMS: endMS, confidence: 0.9)
    }

    private static func captioned() -> PhotonzDocument {
        var document = talk()
        document.landCaptions([
            CaptionCue(words: [word("Fodons", 1_000, 1_500), word("opens", 1_500, 1_900),
                               word("alot", 1_900, 2_400)], inMS: 1_000, outMS: 2_500),
            CaptionCue(words: [word("the", 3_000, 3_200), word("video", 3_200, 3_700)],
                       inMS: 3_000, outMS: 3_800),
        ])
        return document
    }

    @Test("The caption word in hand is the one being said at the playhead")
    func wordAtThePlayhead() {
        let document = Self.captioned()
        let first = document.captionLayers[0].id
        let second = document.captionLayers[1].id
        #expect(document.captionWord(atMS: 1_000) == CaptionWordRef(cueID: first, index: 0))
        #expect(document.captionWord(atMS: 1_600) == CaptionWordRef(cueID: first, index: 1))
        #expect(document.captionWord(atMS: 3_250) == CaptionWordRef(cueID: second, index: 1))
    }

    @Test("Past the last word of a caption that is still up, the word is the last one said")
    func wordAfterTheLastSaid() {
        let document = Self.captioned()
        #expect(document.captionWord(atMS: 2_450) == CaptionWordRef(cueID: document.captionLayers[0].id, index: 2))
    }

    @Test("With no caption up there is no word in hand")
    func noCaptionNoWord() {
        let document = Self.captioned()
        #expect(document.captionWord(atMS: 2_700) == nil)
        #expect(document.captionWord(atMS: 500) == nil)
        #expect(Self.talk().captionWord(atMS: 1_000) == nil)
    }
}
