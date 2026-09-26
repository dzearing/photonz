import Foundation
import PhotonzCore
import Testing

/// A document with time gets the tool bar `video.html` draws: Select, Blade,
/// Title / Text, Shape and Measure, with every other tool folded under More
/// (`docs/design/mocks/shared/UX-PATTERNS.md` D4, `docs/design/modes.md` §2).
@Suite("Video tool bar")
struct VideoToolBarTests {

    private let picture = ToolBarLayout.bar(withFrame: false, withLens: true, withPen: true)

    @Test("A video's bar is the mock's five, in the mock's order")
    func theVideoBarIsTheMocksFive() {
        let fold = ToolBarFold.video(of: picture)
        #expect(fold.shownEntries == [.tool(.select), .blade, .tool(.text), .group(.shapes), .tool(.measure)])
        // Hairlines where the mock draws them: after Select, after Shape.
        #expect(fold.shown.map(\.count) == [1, 3, 1])
    }

    @Test("Every tool the picture bar holds and the video bar does not is under More, in bar order")
    func everythingElseIsUnderMore() {
        let fold = ToolBarFold.video(of: picture)
        #expect(fold.folded == [.group(.selection), .tool(.crop), .tool(.arrow), .tool(.highlight),
                                .tool(.lens), .tool(.pen), .tool(.fill)])
        // Nothing is lost and nothing is twice: every slot of the picture bar
        // is either in front or under More, exactly once.
        let picked = Set(fold.shownEntries).union(fold.folded)
        for entry in picture.entries { #expect(picked.contains(entry)) }
        #expect(Set(fold.shownEntries).isDisjoint(with: fold.folded))
    }

    @Test("A family is never split: naming one member keeps the whole family in front")
    func aFamilyIsNeverSplit() {
        let fold = ToolBarFold(picture, front: [[.tool(.select)], [.tool(.rectangle)]])
        #expect(fold.shownEntries == [.tool(.select), .group(.shapes)])
        #expect(!fold.folded.contains(.group(.shapes)))
        #expect(!fold.isFolded(.line))
        #expect(!fold.isFolded(.ellipse))
    }

    @Test("Trim rides with Crop under More, the slot it has always shared")
    func trimIsUnderMoreWithCrop() {
        let fold = ToolBarFold.video(of: picture)
        #expect(fold.isFolded(.crop))
        #expect(fold.isFolded(.trim))
        #expect(fold.entry(for: .trim) == .tool(.crop))
    }

    @Test("Which tools are folded")
    func whichToolsAreFolded() {
        let fold = ToolBarFold.video(of: picture)
        for tool in [Tool.line, .rectangle, .ellipse, .text, .measure, .select] {
            #expect(!fold.isFolded(tool), "\(tool) is in front")
        }
        for tool in [Tool.arrow, .highlight, .lens, .pen, .fill, .wand, .rectSelect, .crop] {
            #expect(fold.isFolded(tool), "\(tool) is under More")
        }
    }

    @Test("The Blade in hand lights the Blade and nothing else")
    func theBladeLightsAlone() {
        let fold = ToolBarFold.video(of: picture)
        #expect(fold.lit(activeTool: .select, bladeInHand: true) == .blade)
        #expect(fold.lit(activeTool: .text, bladeInHand: true) == .blade)
        #expect(fold.lit(activeTool: .select, bladeInHand: false) == .tool(.select))
        #expect(fold.lit(activeTool: .ellipse, bladeInHand: false) == .group(.shapes))
        // A folded tool in hand lights its slot under More, which is how the
        // bar knows to light the More button.
        #expect(fold.lit(activeTool: .fill, bladeInHand: false) == .tool(.fill))
        #expect(fold.folded.contains(fold.lit(activeTool: .fill, bladeInHand: false) ?? .blade))
    }

    @Test("A bar with no Blade in it never lights one")
    func noBladeNoLight() {
        let fold = ToolBarFold(picture, front: [[.tool(.select)]])
        #expect(fold.lit(activeTool: .select, bladeInHand: true) == .tool(.select))
    }

    @Test("A picture's bar is left exactly as it is")
    func aPictureBarIsUntouched() {
        let fold = ToolBarFold(picture, front: picture.families)
        #expect(fold.shown == picture.families)
        #expect(fold.folded.isEmpty)
    }

    @Test("The letters the timeline takes, and the ones it leaves the canvas")
    func timelineLetters() {
        for letter: Character in ["k", "l", "i", "o", "m", "a", "w", "b"] {
            #expect(!TimelineKeys.leavesToTheCanvas(letter), "\(letter) is the timeline's")
        }
        // V is both: the timeline puts its tool down and the press carries on
        // to the canvas's Select.
        for letter: Character in ["t", "r", "g", "p", "f", "c", "h", "z", "v"] {
            #expect(TimelineKeys.leavesToTheCanvas(letter), "\(letter) reaches its tool")
        }
    }

    @Test("A key that picks a folded tool says where it lives, in a label and not a sentence")
    func underMoreNotice() {
        let notice = CopyConfirmation(subject: .toolUnderMore(tool: "Line"), shownAt: Date())
        #expect(notice.title == "Line")
        #expect(notice.detail == "Under More")
        #expect(notice.title.count + notice.detail.count <= 30)
    }
}
