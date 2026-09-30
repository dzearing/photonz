import Foundation
import PhotonzCore
import Testing

/// The tool bar shows every tool that fits the room it has and folds only the
/// rest under More, the way Photoshop, Final Cut and Keynote do. A document
/// with time puts the video's own tools first (Select, Blade, Title / Text,
/// Shape, Measure: `video.html`, UX-PATTERNS D4), so they are the last to
/// fold; a picture folds from the end of its own bar.
@Suite("Tool bar fold")
struct VideoToolBarTests {

    private let picture = ToolBarLayout.bar(withFrame: false, withLens: true, withPen: true)

    /// Every slot 28pt, 4pt apart, a 5pt hairline (1pt line and 2pt each
    /// side), and a 28pt More: the one glass bar's numbers.
    private let metrics = ToolBarFold.Metrics(slot: 28, gap: 4, hairline: 5, more: 28)

    /// The room a video's front five and More take, drawn as the mock draws
    /// them: Select | Blade Text Shape | Measure | More.
    private var roomForTheFive: CGFloat {
        metrics.width(of: [[.tool(.select)], [.blade, .tool(.text), .group(.shapes)],
                           [.tool(.measure)]], more: true)
    }

    private func video(room: CGFloat, lit: ToolBarLayout.Entry? = nil) -> ToolBarFold {
        ToolBarFold(picture, leading: ToolBarFold.videoLeading, room: room, metrics: metrics,
                    keeping: lit)
    }

    // MARK: Measuring

    @Test("A row's width is its slots, the gaps between everything, its hairlines and More")
    func widthOfARow() {
        // Two slots: 28 + 4 + 28.
        #expect(metrics.width(of: [[.tool(.select), .tool(.crop)]], more: false) == 60)
        // A hairline between two families is one more child: 28 + 4 + 5 + 4 + 28.
        #expect(metrics.width(of: [[.tool(.select)], [.tool(.crop)]], more: false) == 69)
        // More is a child too.
        #expect(metrics.width(of: [[.tool(.select)]], more: true) == 60)
        #expect(metrics.width(of: [], more: true) == 28)
        #expect(metrics.width(of: [], more: false) == 0)
    }

    @Test("A slot measured wider than the rest counts at its measured width")
    func measuredSlots() {
        var wide = metrics
        wide.widths[.group(.selection)] = 40
        #expect(wide.width(of: .group(.selection)) == 40)
        #expect(wide.width(of: .tool(.select)) == 28)
    }

    // MARK: Filling the room

    @Test("With room for everything a video shows every tool and has no More")
    func roomForEverything() {
        let fold = video(room: 2000)
        #expect(fold.folded.isEmpty)
        // The video's own tools first, as the mock draws them, then the rest
        // of the bar in its own families.
        #expect(fold.shown == [
            [.tool(.select)], [.blade, .tool(.text), .group(.shapes)], [.tool(.measure)],
            [.group(.selection), .tool(.crop)],
            [.tool(.arrow), .tool(.highlight), .tool(.lens), .tool(.pen)],
            [.tool(.fill)],
        ])
    }

    @Test("With room for everything a picture shows its own bar, untouched")
    func aRoomyPictureIsTheWholeBar() {
        let fold = ToolBarFold(picture, room: 2000, metrics: metrics)
        #expect(fold.shown == picture.families)
        #expect(fold.folded.isEmpty)
    }

    @Test("A room that holds exactly every slot needs no More")
    func exactlyEverything() {
        let all = metrics.width(of: picture.families, more: false)
        #expect(ToolBarFold(picture, room: all, metrics: metrics).folded.isEmpty)
        // A point less and something folds, and the More it needs fits too.
        let less = ToolBarFold(picture, room: all - 1, metrics: metrics)
        #expect(!less.folded.isEmpty)
        #expect(metrics.width(of: less.shown, more: true) <= all - 1)
    }

    @Test("The room for the mock's five shows the five and folds the rest, in bar order")
    func theMocksFive() {
        let fold = video(room: roomForTheFive)
        #expect(fold.shownEntries == [.tool(.select), .blade, .tool(.text), .group(.shapes), .tool(.measure)])
        #expect(fold.shown.map(\.count) == [1, 3, 1])
        #expect(fold.folded == [.group(.selection), .tool(.crop), .tool(.arrow), .tool(.highlight),
                                .tool(.lens), .tool(.pen), .tool(.fill)])
    }

    @Test("A little more room brings the next tools back in, and folds only what still does not fit")
    func moreRoomMoreTools() {
        let fold = video(room: roomForTheFive + 2 * (metrics.slot + metrics.gap) + metrics.hairline + metrics.gap)
        #expect(fold.shownEntries == [.tool(.select), .blade, .tool(.text), .group(.shapes), .tool(.measure),
                                      .group(.selection), .tool(.crop)])
        #expect(fold.folded == [.tool(.arrow), .tool(.highlight), .tool(.lens), .tool(.pen), .tool(.fill)])
    }

    @Test("A narrow video folds its own tools last: Measure goes before Shape, Select stays longest")
    func narrowVideo() {
        let three = metrics.width(of: [[.tool(.select)], [.blade, .tool(.text)]], more: true)
        let fold = video(room: three)
        #expect(fold.shownEntries == [.tool(.select), .blade, .tool(.text)])
        #expect(fold.folded.first == .group(.shapes))
        #expect(fold.folded.contains(.tool(.measure)))
    }

    @Test("A narrow picture folds from the end of its bar")
    func narrowPicture() {
        let room = metrics.width(of: [[.tool(.select), .group(.selection), .tool(.crop), .tool(.measure)],
                                      [.tool(.arrow)]], more: true)
        let fold = ToolBarFold(picture, room: room, metrics: metrics)
        #expect(fold.shown == [[.tool(.select), .group(.selection), .tool(.crop), .tool(.measure)],
                               [.tool(.arrow)]])
        #expect(fold.folded == [.group(.shapes), .tool(.highlight), .tool(.text), .tool(.lens),
                                .tool(.pen), .tool(.fill)])
    }

    @Test("No room at all puts every tool under More, nothing lost")
    func noRoom() {
        let fold = video(room: 0)
        #expect(fold.shown.isEmpty)
        #expect(fold.folded.count == picture.entries.count + 1)
        #expect(fold.folded.first == .tool(.select))
    }

    @Test("Nothing is lost and nothing is twice, at any width")
    func everySlotExactlyOnce() {
        for room in stride(from: CGFloat(0), through: 700, by: 7) {
            let fold = video(room: room, lit: .tool(.fill))
            let shown = fold.shownEntries
            #expect(Set(shown).isDisjoint(with: fold.folded))
            #expect(shown.count + fold.folded.count == picture.entries.count + 1)
            // And the row always fits the room, More included.
            if !shown.isEmpty {
                #expect(metrics.width(of: fold.shown, more: !fold.folded.isEmpty) <= room)
            }
        }
    }

    @Test("A family is one slot and is never split: a member in hand keeps the whole family")
    func aFamilyIsNeverSplit() {
        let fold = ToolBarFold(picture, room: 2000, metrics: metrics)
        #expect(fold.entry(for: .rectangle) == .group(.shapes))
        #expect(fold.entry(for: .ellipse) == .group(.shapes))
        let named = ToolBarFold(picture, front: [[.tool(.select)], [.tool(.rectangle)]])
        #expect(named.shownEntries == [.tool(.select), .group(.shapes)])
        #expect(!named.isFolded(.line))
    }

    @Test("Trim rides with Crop, in front or under More")
    func trimRidesWithCrop() {
        #expect(video(room: roomForTheFive).isFolded(.trim))
        #expect(video(room: 2000).entry(for: .trim) == .tool(.crop))
        #expect(!video(room: 2000).isFolded(.trim))
    }

    // MARK: The tool in hand

    @Test("A folded tool in hand swaps into the bar, taking the place of the last tool to fit")
    func theToolInHandSwapsIn() {
        let fold = video(room: roomForTheFive, lit: .tool(.fill))
        #expect(!fold.folded.contains(.tool(.fill)))
        // Measure is the lowest of the five, so it is the one that steps aside.
        #expect(fold.shownEntries == [.tool(.select), .blade, .tool(.text), .group(.shapes), .tool(.fill)])
        #expect(fold.folded.contains(.tool(.measure)))
        #expect(metrics.width(of: fold.shown, more: true) <= roomForTheFive)
    }

    @Test("The tool in hand never moves the tools that stay: it takes its own family's place")
    func theToolInHandKeepsOrder() {
        let fold = video(room: roomForTheFive, lit: .tool(.crop))
        #expect(fold.shownEntries == [.tool(.select), .blade, .tool(.text), .group(.shapes), .tool(.crop)])
        let picture = ToolBarFold(self.picture,
                                  room: metrics.width(of: [[.tool(.select), .group(.selection)]], more: true),
                                  metrics: metrics, keeping: .tool(.measure))
        #expect(picture.shownEntries == [.tool(.select), .tool(.measure)])
    }

    @Test("A tool in hand that already shows changes nothing")
    func aShownToolInHand() {
        #expect(video(room: roomForTheFive, lit: .tool(.text)) == video(room: roomForTheFive))
    }

    @Test("With no room even for the tool in hand, it stays under More and More lights")
    func noRoomToSwap() {
        let fold = video(room: metrics.more, lit: .tool(.fill))
        #expect(fold.shown.isEmpty)
        #expect(fold.folded.contains(.tool(.fill)))
        #expect(fold.folded.contains(fold.lit(activeTool: .fill, bladeInHand: false) ?? .blade))
    }

    @Test("The Blade in hand lights the Blade and nothing else")
    func theBladeLightsAlone() {
        let fold = video(room: roomForTheFive)
        #expect(fold.lit(activeTool: .select, bladeInHand: true) == .blade)
        #expect(fold.lit(activeTool: .text, bladeInHand: true) == .blade)
        #expect(fold.lit(activeTool: .select, bladeInHand: false) == .tool(.select))
        #expect(fold.lit(activeTool: .ellipse, bladeInHand: false) == .group(.shapes))
    }

    @Test("A bar with no Blade in it never lights one")
    func noBladeNoLight() {
        let fold = ToolBarFold(picture, room: 2000, metrics: metrics)
        #expect(fold.lit(activeTool: .select, bladeInHand: true) == .tool(.select))
    }

    // MARK: Keys

    @Test("The letters the timeline takes, and the ones it leaves the canvas")
    func timelineLetters() {
        for letter: Character in ["k", "l", "i", "o", "m", "a", "w", "b", "r"] {
            #expect(!TimelineKeys.leavesToTheCanvas(letter), "\(letter) is the timeline's")
        }
        // V is both: the timeline puts its tool down and the press carries on
        // to the canvas's Select.
        for letter: Character in ["t", "g", "p", "f", "c", "h", "z", "v"] {
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
