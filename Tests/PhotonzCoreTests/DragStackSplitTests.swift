import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A dragged layer is floated over a picture of what is under it, so whatever
/// is drawn OVER it has to be a picture of its own floated over the sprite, or
/// the layer comes out on top for the whole of the move and drops back under
/// on the release.
@Suite("The stack cut in two at a dragged layer")
struct DragStackSplitTests {

    private func box(_ name: String, _ x: CGFloat = 0) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle)),
              frame: CGRect(x: x, y: 0, width: 100, height: 100))
    }

    private func visible(_ document: PhotonzDocument) -> [String] {
        document.allLayers.filter(\.isVisible).map(\.name)
    }

    @Test("A layer with nothing over it is floated over everything else, as it always was")
    func topmostKeepsTheOldArrangement() throws {
        let under = box("Under"), moved = box("Moved")
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [under, moved])
        let split = try #require(doc.dragStackSplit(at: moved.id))
        #expect(visible(split.below) == ["Under"])
        #expect(split.above == nil)
    }

    @Test("A layer under another is floated BETWEEN what is under it and what is over it")
    func layerUnderAnotherIsSandwiched() throws {
        let floor = box("Floor"), moved = box("Moved"), cover = box("Cover", 50), lid = box("Lid", 80)
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300),
                                  layers: [floor, moved, cover, lid])
        let split = try #require(doc.dragStackSplit(at: moved.id))
        #expect(visible(split.below) == ["Floor"])
        let above = try #require(split.above)
        #expect(visible(above) == ["Cover", "Lid"])
        #expect(above.canvasSize == doc.canvasSize)
        #expect(split.over == [cover.id, lid.id])
    }

    @Test("A hidden layer over it counts for nothing")
    func hiddenCoverIsNothing() throws {
        let moved = box("Moved")
        var cover = box("Cover")
        cover.isVisible = false
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [moved, cover])
        let split = try #require(doc.dragStackSplit(at: moved.id))
        #expect(split.above == nil)
    }

    @Test("A captions layer listed under it is still drawn over it")
    func captionsAreAbove() throws {
        let moved = box("Moved")
        var captions = box("Captions")
        var words = GroupContent(children: [])
        words.captionLook = .preset(.karaoke)
        captions.content = .group(words)
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [captions, moved])
        #expect(doc.layers[0].isCaptionsLayer)
        let split = try #require(doc.dragStackSplit(at: moved.id))
        #expect(visible(try #require(split.above)) == ["Captions"])
        #expect(!visible(split.below).contains("Captions"))
    }

    @Test("Something over it that mixes with what is under it cannot be floated, so there is no split")
    func mixingCoverRefuses() {
        let moved = box("Moved")
        var cover = box("Cover")
        cover.style.blendMode = .multiply
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [moved, cover])
        #expect(doc.dragStackSplit(at: moved.id) == nil)
    }

    @Test("A lens over it reads what is under it, so there is no split")
    func lensCoverRefuses() {
        let moved = box("Moved")
        let lens = Layer(name: "Lens", content: .lens(LensContent()),
                         frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let group = Layer(name: "Group", content: .group(GroupContent(children: [lens])),
                          frame: .zero)
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [moved, group])
        #expect(doc.dragStackSplit(at: moved.id) == nil)
    }

    @Test("A piece inside a group with something drawn over it has no split")
    func nestedUnderSomethingRefuses() {
        let piece = box("Piece")
        let group = Layer(name: "Group", content: .group(GroupContent(children: [piece])), frame: .zero)
        let cover = box("Cover")
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [group, cover])
        #expect(doc.dragStackSplit(at: piece.id) == nil)
    }

    @Test("A piece inside a group with nothing drawn over it keeps the old arrangement")
    func nestedOnTopKeepsTheOldArrangement() throws {
        let under = box("Under"), piece = box("Piece")
        let group = Layer(name: "Group", content: .group(GroupContent(children: [under, piece])), frame: .zero)
        let floor = box("Floor")
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [floor, group])
        let split = try #require(doc.dragStackSplit(at: piece.id))
        #expect(split.above == nil)
        #expect(visible(split.below) == ["Floor", "Group", "Under"])
    }

    @Test("A layer that is not in the document has no split")
    func unknownLayer() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [box("A")])
        #expect(doc.dragStackSplit(at: UUID()) == nil)
    }
}
