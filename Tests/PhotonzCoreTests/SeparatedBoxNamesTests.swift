import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Which run of text names which box, and what the name reads like.
///
/// The rule is `SeparatedBoxNames`. These are the shapes a settings pane makes:
/// a switch with its label to the left of it, a button with its label inside
/// it, a card with three of each on it, and a stripe with nothing to say.
@Suite("A separated box is named after words you can see")
struct SeparatedBoxNamesTests {

    /// The fixture pane, in its own pixels: a card holding three rows, each row
    /// a label on the left and a switch on the right, and a button under it
    /// with its label inside it.
    private static func pane() -> (rects: [CGRect], isRun: [Bool]) {
        var rects: [CGRect] = []
        var isRun: [Bool] = []
        func add(_ rect: CGRect, run: Bool) { rects.append(rect); isRun.append(run) }
        // 0: the card.
        add(CGRect(x: 60, y: 150, width: 1320, height: 260), run: false)
        // 1, 2: the switches on it.
        add(CGRect(x: 1260, y: 170, width: 84, height: 44), run: false)
        add(CGRect(x: 1260, y: 260, width: 84, height: 44), run: false)
        // 3: the button, and 4 its label inside it.
        add(CGRect(x: 230, y: 760, width: 250, height: 60), run: false)
        add(CGRect(x: 270, y: 775, width: 170, height: 30), run: true)
        // 5, 6: the two row labels on the card.
        add(CGRect(x: 96, y: 180, width: 190, height: 26), run: true)
        add(CGRect(x: 96, y: 270, width: 215, height: 26), run: true)
        return (rects, isRun)
    }

    @Test func aBoxTakesTheWordsBesideItOnTheSameRow() {
        let (rects, isRun) = Self.pane()
        let labels = SeparatedBoxNames.labels(rects: rects, isRunOfText: isRun)
        #expect(labels[1] == 5)
        #expect(labels[2] == 6)
    }

    @Test func aBoxTakesTheWordsSittingInsideIt() {
        let (rects, isRun) = Self.pane()
        let labels = SeparatedBoxNames.labels(rects: rects, isRunOfText: isRun)
        #expect(labels[3] == 4)
    }

    /// A card holds three rows of words, and none of them is the card's name.
    /// It falls back to the number the command gave it.
    @Test func aBoxHoldingSeveralRunsTakesNoneOfThem() {
        let (rects, isRun) = Self.pane()
        let labels = SeparatedBoxNames.labels(rects: rects, isRunOfText: isRun)
        #expect(labels[0] == nil)
    }

    @Test func aRunOfTextIsNeverNamedAfterAnything() {
        let (rects, isRun) = Self.pane()
        let labels = SeparatedBoxNames.labels(rects: rects, isRunOfText: isRun)
        #expect(labels[4] == nil)
        #expect(labels[5] == nil)
        #expect(labels[6] == nil)
    }

    /// Words on another row are not this box's words, however close they are
    /// vertically: a label under a switch belongs to the row under it.
    @Test func wordsOnAnotherRowAreNotTaken() {
        let rects = [CGRect(x: 400, y: 100, width: 80, height: 40),
                     CGRect(x: 60, y: 200, width: 180, height: 26)]
        let labels = SeparatedBoxNames.labels(rects: rects, isRunOfText: [false, true])
        #expect(labels[0] == nil)
    }

    /// One label, two boxes on its row: the near one wins and the far one keeps
    /// its number, so the list never says the same thing twice.
    @Test func oneLabelNamesOneBox() {
        let rects = [CGRect(x: 60, y: 100, width: 180, height: 26),
                     CGRect(x: 300, y: 95, width: 80, height: 40),
                     CGRect(x: 500, y: 95, width: 80, height: 40)]
        let labels = SeparatedBoxNames.labels(rects: rects, isRunOfText: [true, false, false])
        #expect(labels[1] == 0)
        #expect(labels[2] == nil)
    }

    /// Something in the way means the words are not this box's words: a switch
    /// on the far side of another control is not what that label names.
    @Test func wordsWithSomethingBetweenThemAndTheBoxAreNotTaken() {
        let rects = [CGRect(x: 60, y: 100, width: 180, height: 26),
                     CGRect(x: 300, y: 95, width: 80, height: 40),
                     CGRect(x: 500, y: 95, width: 80, height: 40),
                     CGRect(x: 700, y: 95, width: 80, height: 40)]
        let labels = SeparatedBoxNames.labels(rects: rects,
                                              isRunOfText: [true, false, false, false])
        #expect(labels[1] == 0)
        #expect(labels[2] == nil)
        #expect(labels[3] == nil)
    }

    /// Words to the RIGHT of a box name it too, which is what a checkbox with
    /// its label after it looks like.
    @Test func wordsAfterABoxNameItWhenThereAreNoneBefore() {
        let rects = [CGRect(x: 60, y: 95, width: 40, height: 40),
                     CGRect(x: 120, y: 100, width: 180, height: 26)]
        let labels = SeparatedBoxNames.labels(rects: rects, isRunOfText: [false, true])
        #expect(labels[0] == 1)
    }

    @Test func theSamePaneTwiceGivesTheSameAnswer() {
        let (rects, isRun) = Self.pane()
        let once = SeparatedBoxNames.labels(rects: rects, isRunOfText: isRun)
        let twice = SeparatedBoxNames.labels(rects: rects, isRunOfText: isRun)
        #expect(once == twice)
    }

    @Test func nothingInTheListIsNamedAfterNothing() {
        #expect(SeparatedBoxNames.labels(rects: [], isRunOfText: []) == [])
    }

    // MARK: - What the name reads like

    @Test func aNamedBoxSaysItsWordsAndSaysItIsABox() {
        #expect(SeparatedBoxNames.name(fromWords: "Launch at login") == "Launch at login box")
    }

    @Test func wordsTooLongForARowAreCutTheSameWayARunsAre() {
        let long = String(repeating: "wide ", count: 20)
        let name = SeparatedBoxNames.name(fromWords: long)
        #expect(name.hasSuffix(" box"))
        #expect(name.contains("\u{2026}"))
        #expect(name.count <= LayerNaming.wordsLimit + 5)
    }

    /// A picture the reader found no words in leaves the box with nothing to
    /// say, so the caller keeps the number it already had.
    @Test func noWordsMeansNoName() {
        #expect(SeparatedBoxNames.name(fromWords: "   ").isEmpty)
        #expect(SeparatedBoxNames.name(fromWords: "").isEmpty)
    }
}
