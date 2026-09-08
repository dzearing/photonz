import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What a group will do with more room, said before anybody types it.
///
/// The complaint this answers: the same number in the same field does two
/// opposite things. On a loose drawing the box grows outward and the pieces
/// stay exactly where they were drawn; on a drawing where one piece has been
/// named the surface, the pieces move in and the box grows from the corner it
/// is pinned at. Both are right for the drawing they happen to, and neither of
/// them was written anywhere a person could read before typing.
///
/// So every group carries its answer, and the tests here hold the answer
/// against what the flow ACTUALLY does, which is the only thing that stops a
/// sentence in the panel from drifting away from the canvas.
@Suite("A group says what more room will do to it")
struct RoomAnswerTests {

    // MARK: - Building blocks

    private func box(_ name: String, _ frame: CGRect,
                     placement: LayerPlacement? = nil) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)),
              frame: frame, placement: placement)
    }

    private func group(_ children: [Layer], layout: GroupLayout? = nil,
                       origin: CGPoint = .zero) -> Layer {
        var content = GroupContent(children: children)
        content.layout = layout
        return Layer(name: "Group", content: .group(content),
                     frame: CGRect(origin: origin, size: .zero))
    }

    /// A loose drawing: two pieces sitting where somebody put them, and nothing
    /// painted to the group's own edges.
    private func loose(_ layout: GroupLayout = .free()) -> Layer {
        group([box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
               box("B", CGRect(x: 60, y: 40, width: 40, height: 20))],
              layout: layout, origin: CGPoint(x: 100, y: 50))
    }

    /// The same drawing with one difference: the box under the word is painted
    /// to the group's own edges, which is what makes it a button.
    private func button(_ layout: GroupLayout = .free()) -> Layer {
        group([box("Background", CGRect(x: 0, y: 0, width: 128, height: 36),
                   placement: .fill),
               box("Label", CGRect(x: 41, y: 8, width: 50, height: 20))],
              layout: layout, origin: CGPoint(x: 100, y: 50))
    }

    private func canvasFrames(_ layer: Layer) -> [CGRect] {
        layer.children.map { $0.frame.offsetBy(dx: layer.frame.origin.x, dy: layer.frame.origin.y) }
    }

    // MARK: - The answer each kind of group gives

    @Test("A loose drawing grows its box outward")
    func looseDrawingGrowsOutward() {
        #expect(loose().roomAnswer == .growsTheBoxOutward)
    }

    @Test("A drawing with a surface in it moves its pieces in instead")
    func aSurfaceMovesThePiecesIn() {
        #expect(button().roomAnswer == .movesThePiecesIn)
    }

    @Test("A stack moves its pieces in, surface or no surface")
    func aStackMovesThePiecesIn() {
        #expect(loose(.init(kind: .stack)).roomAnswer == .movesThePiecesIn)
        #expect(button(.init(kind: .stack)).roomAnswer == .movesThePiecesIn)
    }

    @Test("A drawing sized by hand, with nothing stretching in it, answers to room at all")
    func aFixedDrawingWithNothingStretchingMovesNothing() {
        #expect(loose(.free(width: 300, height: 200)).roomAnswer == .movesNothing)
        // One side still the size of its contents is one side that can grow.
        #expect(loose(.free(width: 300)).roomAnswer == .growsTheBoxOutward)
    }

    @Test("A drawing sized by hand whose surface is painted to those edges moves nothing either")
    func aFixedButtonMovesNothing() {
        #expect(button(.free(width: 300, height: 200)).roomAnswer == .movesNothing)
    }

    @Test("A rail stretched one way is moved in by room, however the box was arrived at")
    func aRailMovesIn() {
        let rail = group([box("A", CGRect(x: 0, y: 0, width: 40, height: 20)),
                          box("Rule", CGRect(x: 0, y: 30, width: 100, height: 1),
                              placement: LayerPlacement(horizontal: .stretch))],
                         layout: .free(width: 300, height: 200))
        #expect(rail.roomAnswer == .movesThePiecesIn)
    }

    @Test("Anything that is not a group with something in it has no answer to give")
    func nothingToSay() {
        #expect(box("A", CGRect(x: 0, y: 0, width: 10, height: 10)).roomAnswer == nil)
        #expect(group([]).roomAnswer == nil)
    }

    // MARK: - The answer is what the flow really does

    @Test("Grows the box outward means exactly that: the box moves out and no piece moves")
    func outwardIsWhatTheFlowDoes() {
        let before = GroupFlow.flowing(loose())
        #expect(before.roomAnswer == .growsTheBoxOutward)
        let after = GroupFlow.flowing(
            group(before.children, layout: .free(padding: GroupPadding(16)),
                  origin: before.frame.origin))
        #expect(canvasFrames(after) == canvasFrames(before))
        #expect(after.localBounds == before.localBounds.insetBy(dx: -16, dy: -16))
    }

    @Test("Moves the pieces in means exactly that: the corner holds and the pieces move")
    func movingInIsWhatTheFlowDoes() {
        let before = GroupFlow.flowing(button())
        #expect(before.roomAnswer == .movesThePiecesIn)
        let after = GroupFlow.flowing(
            group(before.children, layout: .free(padding: GroupPadding(16)),
                  origin: before.frame.origin))
        #expect(after.frame.origin == before.frame.origin)
        #expect(canvasFrames(after) != canvasFrames(before))
    }

    @Test("Moves nothing means exactly that: neither the box nor a piece changes")
    func movingNothingIsWhatTheFlowDoes() {
        let sized = GroupFlow.flowing(loose(.free(width: 300, height: 200)))
        #expect(sized.roomAnswer == .movesNothing)
        let after = GroupFlow.flowing(
            group(sized.children, layout: .free(padding: GroupPadding(16),
                                                width: 300, height: 200),
                  origin: sized.frame.origin))
        #expect(canvasFrames(after) == canvasFrames(sized))
        #expect(after.localBounds == sized.localBounds)
    }

    // MARK: - What the panel says

    @Test("Every answer has a line a person can read, and no two of them read the same")
    func everyAnswerHasItsOwnLine() {
        let lines = RoomAnswer.allCases.map(\.sentence)
        #expect(Set(lines).count == RoomAnswer.allCases.count)
        for line in lines {
            #expect(!line.isEmpty)
            #expect(!line.contains("—"))
        }
    }

    // MARK: - Several picked at once

    @Test("Two groups that give the same answer say it once; two that disagree say nothing")
    func severalPicked() {
        let document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                       layers: [loose(), button()])
        let both = document.contentsSelection(layerIDs: document.layers.map(\.id))
        #expect(both.roomAnswer == nil)
        let onlyLoose = document.contentsSelection(layerIDs: [document.layers[0].id])
        #expect(onlyLoose.roomAnswer == .growsTheBoxOutward)
        let pair = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                   layers: [loose(), loose()])
        #expect(pair.contentsSelection(layerIDs: pair.layers.map(\.id)).roomAnswer
                == .growsTheBoxOutward)
    }
}
