import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A text box you can give room to.
///
/// Where the words sit DOWN a box has been a real choice since 2026-09-03 and
/// an unreachable one on the canvas: a plain text box is always exactly as tall
/// as its words, so Middle and Bottom had nothing to move them in and the only
/// way to make room was to put the box in something that stretched it. These
/// are the rules that let a person make the room themselves — by dragging the
/// box's bottom edge, or by typing a height — and that keep it once made.
@Suite("A text box can be given room down the box")
struct TextBoxRoomTests {

    private func words(_ string: String = "Hello there", size: CGFloat = 15) -> TextContent {
        var text = TextContent(string: string)
        text.fontSize = size
        return text
    }

    /// A text layer hugging its words, the way one arrives on the canvas.
    private func hugging(_ content: TextContent? = nil) -> Layer {
        let text = content ?? words()
        return Layer(name: "Label", content: .text(text), frame:
                        CGRect(origin: CGPoint(x: 20, y: 30),
                               size: TextMeasurement.size(of: text)))
    }

    /// How tall the words in `layer` need their box to be at its own width.
    private func wordsHeight(_ layer: Layer) -> CGFloat {
        guard case .text(let content) = layer.content else { return 0 }
        return TextMeasurement.size(of: content, wrappingAt: layer.frame.width).height
    }

    // MARK: Giving room

    @Test func aTallerBoxHandedToATextLayerIsKept() {
        let layer = hugging()
        let room = wordsHeight(layer) + 60
        let taller = layer.resized(to: CGRect(x: 20, y: 30, width: layer.frame.width, height: room),
                                  chosenByHand: true)
        #expect(abs(taller.frame.height - room) < 0.01)
    }

    @Test func theRoomIsRememberedAsSomethingSomebodyChose() {
        let layer = hugging()
        let room = wordsHeight(layer) + 60
        let taller = layer.resized(to: CGRect(x: 20, y: 30, width: layer.frame.width, height: room),
                                  chosenByHand: true)
        #expect(taller.heightChosenByHand == taller.frame.height)
        #expect(taller.hasRoomDownTheBox)
    }

    @Test func aBoxWithNoRoomHasNoneOfItToShareOut() {
        #expect(hugging().hasRoomDownTheBox == false)
        #expect(hugging().heightChosenByHand == nil)
    }

    /// The point of all of it: with room, Middle and Bottom have something to
    /// move the words in. `TextBlockMetrics` does the moving; this is the fact
    /// it needs.
    @Test func roomIsWhatMakesMiddleAndBottomMeanAnything() {
        var text = words()
        text.verticalAlignment = .middle
        let layer = hugging(text)
        let taller = layer.resized(to: layer.frame.insetBy(dx: 0, dy: -30), chosenByHand: true)
        #expect(taller.frame.height > wordsHeight(taller))
    }

    // MARK: Keeping it

    @Test func aWidthDragKeepsTheRoomInsteadOfCollapsingBackToTheWords() {
        let layer = hugging(words("A paragraph with quite a few words in it to wrap"))
        let room = wordsHeight(layer) + 80
        let roomy = layer.resized(to: CGRect(x: 20, y: 30, width: layer.frame.width, height: room),
                                  chosenByHand: true)
        // Now drag the side in: the words re-wrap and grow taller, and the room
        // is still the floor they sit in.
        let narrower = roomy.resized(to: CGRect(x: 20, y: 30, width: 120, height: roomy.frame.height),
                                     chosenByHand: true)
        #expect(narrower.frame.width == 120)
        #expect(narrower.frame.height >= room - 0.01)
        #expect(narrower.heightChosenByHand == room)
    }

    @Test func movingTheBoxChangesNothingAboutItsRoom() {
        let layer = hugging()
        let room = wordsHeight(layer) + 40
        let roomy = layer.resized(to: CGRect(x: 20, y: 30, width: layer.frame.width, height: room),
                                  chosenByHand: true)
        let moved = roomy.resized(to: roomy.frame.offsetBy(dx: 100, dy: 12), chosenByHand: true)
        #expect(moved.frame.height == roomy.frame.height)
        #expect(moved.heightChosenByHand == room)
    }

    @Test func aCopyTakesTheRoomWithIt() {
        let layer = hugging()
        let room = wordsHeight(layer) + 40
        let roomy = layer.resized(to: CGRect(x: 20, y: 30, width: layer.frame.width, height: room),
                                  chosenByHand: true)
        #expect(roomy.duplicated().heightChosenByHand == room)
        #expect(roomy.reidentified().heightChosenByHand == room)
    }

    @Test func roomSurvivesAFileBeingWrittenAndReadBack() throws {
        let layer = hugging()
        let room = wordsHeight(layer) + 40
        let roomy = layer.resized(to: CGRect(x: 20, y: 30, width: layer.frame.width, height: room),
                                  chosenByHand: true)
        let data = try JSONEncoder().encode(roomy)
        let back = try JSONDecoder().decode(Layer.self, from: data)
        #expect(back.heightChosenByHand == room)
    }

    /// A document written before any of this has no such key, and a box in it
    /// hugs its words exactly as it always did.
    @Test func aBoxWrittenBeforeThisHasNoRoom() throws {
        let layer = hugging()
        var json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(layer))
            as? [String: Any] ?? [:]
        json.removeValue(forKey: "heightChosenByHand")
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(try JSONDecoder().decode(Layer.self, from: data).heightChosenByHand == nil)
    }

    // MARK: Giving it back

    @Test func askingForLessThanTheWordsNeedPutsTheBoxBackToHugging() {
        let layer = hugging()
        let room = wordsHeight(layer) + 60
        let roomy = layer.resized(to: CGRect(x: 20, y: 30, width: layer.frame.width, height: room),
                                  chosenByHand: true)
        let hugs = roomy.resized(to: CGRect(x: 20, y: 30, width: layer.frame.width, height: 4),
                                 chosenByHand: true)
        #expect(abs(hugs.frame.height - wordsHeight(layer)) < 0.01)
        #expect(hugs.heightChosenByHand == nil)
        #expect(hugs.hasRoomDownTheBox == false)
    }

    // MARK: What is NOT a choice somebody made

    /// A stack, a grid or a screen handing a box a height is the container's
    /// answer, not a person's, so it never becomes room the box then keeps
    /// once it leaves.
    @Test func aHeightTheContainerWorkedOutIsNotRoomSomebodyChose() {
        let layer = hugging()
        let filled = layer.resized(to: CGRect(x: 20, y: 30, width: layer.frame.width, height: 200),
                                   fillingHeight: true, chosenByHand: true)
        #expect(filled.frame.height == 200)
        #expect(filled.heightChosenByHand == nil)
    }

    @Test func aBoxTheFlowPlacedIsNotRoomSomebodyChoseEither() {
        let layer = hugging()
        let placed = layer.resized(to: CGRect(x: 20, y: 30, width: layer.frame.width, height: 200),
                                   placedByContainer: true, chosenByHand: true)
        #expect(placed.heightChosenByHand == nil)
    }

    // MARK: A title that stays on one line

    @Test func aOneLineTitleTakesRoomToo() {
        var text = words("Title")
        text.staysOnOneLine = true
        let layer = hugging(text)
        let room = layer.frame.height + 50
        let roomy = layer.resized(to: CGRect(x: 20, y: 30, width: layer.frame.width, height: room),
                                  chosenByHand: true)
        #expect(abs(roomy.frame.height - room) < 0.01)
        #expect(roomy.heightChosenByHand == room)
    }

    // MARK: The handles

    /// Across the box the handles set the WRAP WIDTH and the words decide how
    /// tall the box comes out. That is what they have always done.
    @Test func draggingASideStillReWrapsAndLetsTheWordsDecideTheHeight() {
        let layer = hugging(words("A paragraph with quite a few words in it to wrap"))
        let seen = layer.withoutSlack(layer.frame)
        let dragged = layer.textResized(from: seen,
                                        to: CGRect(x: seen.minX, y: seen.minY,
                                                   width: 140, height: 400),
                                        handle: .right)
        #expect(dragged.width == 140)
        #expect(dragged.height < 400)
    }

    /// Down the box they give it ROOM.
    @Test func draggingTheBottomEdgeDownGivesTheBoxRoom() {
        let layer = hugging()
        let seen = layer.withoutSlack(layer.frame)
        let dragged = layer.textResized(from: seen,
                                        to: CGRect(x: seen.minX, y: seen.minY,
                                                   width: seen.width, height: seen.height + 90),
                                        handle: .bottom)
        #expect(abs(dragged.height - (seen.height + 90)) < 0.01)
        #expect(dragged.width == seen.width)
        #expect(dragged.minY == seen.minY)
    }

    @Test func draggingTheTopEdgeUpGivesRoomAndHoldsTheBottomEdge() {
        let layer = hugging()
        let seen = layer.withoutSlack(layer.frame)
        let dragged = layer.textResized(from: seen,
                                        to: CGRect(x: seen.minX, y: seen.minY - 90,
                                                   width: seen.width, height: seen.height + 90),
                                        handle: .top)
        #expect(abs(dragged.height - (seen.height + 90)) < 0.01)
        #expect(abs(dragged.maxY - seen.maxY) < 0.01)
    }

    @Test func theBottomEdgeWillNotGoAboveTheWords() {
        let layer = hugging()
        let seen = layer.withoutSlack(layer.frame)
        let dragged = layer.textResized(from: seen,
                                        to: CGRect(x: seen.minX, y: seen.minY,
                                                   width: seen.width, height: 2),
                                        handle: .bottom)
        #expect(abs(dragged.height - seen.height) < 0.01)
    }

    @Test func aSideDragOnARoomyBoxKeepsItsRoom() {
        let layer = hugging(words("A paragraph with quite a few words in it to wrap"))
        let room = wordsHeight(layer) + 80
        let roomy = layer.resized(to: CGRect(x: 20, y: 30, width: layer.frame.width, height: room),
                                  chosenByHand: true)
        let seen = roomy.withoutSlack(roomy.frame)
        let dragged = roomy.textResized(from: seen,
                                        to: CGRect(x: seen.minX, y: seen.minY,
                                                   width: 160, height: seen.height),
                                        handle: .right)
        #expect(dragged.height >= seen.height - 0.01)
    }

    // MARK: The Height field

    @Test func theHeightFieldTakesANumberForATextBox() {
        let editing = LayerGeometryEditing(layer: hugging(), textTakesAHeight: true)
        #expect(editing.allows(.height))
        #expect(editing.fixedReason(for: .height) == nil)
    }

    @Test func theHeightFieldStopsAtTheWords() {
        let layer = hugging()
        let editing = LayerGeometryEditing(layer: layer, textTakesAHeight: true)
        // The field speaks the box a person SEES, so the floor is the words
        // without the room the renderer draws them in.
        let seenWords = wordsHeight(layer) - layer.boxSlack.height
        #expect(abs((editing.minimum(for: .height) ?? 0) - seenWords) < 0.01)
    }

    @Test func typingAHeightGivesTheBoxRoomAndTheSlackGoesBackOn() {
        let layer = hugging()
        let selection = LayerGeometrySelection([
            .init(id: layer.id, frame: layer.withoutSlack(layer.frame),
                  editing: LayerGeometryEditing(layer: layer, textTakesAHeight: true), slack: layer.boxSlack)
        ])
        let moves = selection.applying(120, to: .height)
        let box = try! #require(moves[layer.id])
        #expect(box.height == 120 + layer.boxSlack.height)
        #expect(layer.resized(to: box, chosenByHand: true).frame.height == box.height)
    }

    // MARK: Saying so when there is no room

    @Test func theTextSectionSaysWhyMiddleIsDoingNothing() {
        var text = words()
        text.verticalAlignment = .middle
        let selection = TextLayerSelection(
            members: [.init(id: UUID(), content: text, hasRoomDownTheBox: false)],
            selectionCount: 1)
        let note = selection.downTheBoxNote
        #expect(note != nil)
        #expect(note?.contains("Position & Size") == true)
    }

    @Test func itSaysNothingWhileTheWordsAreAskedToSitAtTheTop() {
        let selection = TextLayerSelection(
            members: [.init(id: UUID(), content: words(), hasRoomDownTheBox: false)],
            selectionCount: 1)
        #expect(selection.downTheBoxNote == nil)
    }

    @Test func itSaysNothingOnceTheBoxHasRoom() {
        var text = words()
        text.verticalAlignment = .bottom
        let selection = TextLayerSelection(
            members: [.init(id: UUID(), content: text, hasRoomDownTheBox: true)],
            selectionCount: 1)
        #expect(selection.downTheBoxNote == nil)
    }
}
