import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What the ends of a LINE and an ARROW look like.
///
/// A path drawn with the Pen has said this since 2026-09-15
/// (`PathLineStyleTests`), and nothing else did: a line and an arrow ended in a
/// half circle whatever anybody wanted, so a line drawing built out of the
/// shape tools could not be made to match one built with the Pen. Same three
/// answers, same words, one model (`PathLineStyle.swift`).
@Suite("How a line and an arrow end")
struct ShapeLineEndTests {

    private func line(width: CGFloat = 8) -> AnnotationContent {
        AnnotationContent(shape: .line, strokeWidth: width,
                          start: .zero, end: CGPoint(x: 100, y: 0))
    }

    private func document(_ contents: [AnnotationContent]) -> (PhotonzDocument, [UUID]) {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        var ids: [UUID] = []
        for content in contents {
            let layer = Layer(name: "Shape", content: .annotation(content),
                              frame: CGRect(x: 0, y: 0, width: 120, height: 40))
            document.layers.append(layer)
            ids.append(layer.id)
        }
        return (document, ids)
    }

    // MARK: What a shape arrives wearing

    @Test("A fresh line and a fresh arrow end exactly as they always did: round")
    func defaults() {
        #expect(line().lineEnd == .round)
        #expect(AnnotationContent(shape: .arrow).lineEnd == .round)
    }

    @Test("The three answers are the path's three answers, named the same way")
    func sharesThePathsModel() {
        #expect(PathLineEnd.allCases.map(\.title) == ["Flat", "Round", "Square"])
    }

    // MARK: Where the setting can act

    @Test("Only a line and an arrow have ends anybody can see")
    func onlyOpenShapesShowEnds() {
        #expect(AnnotationContent(shape: .line, strokeWidth: 4).showsLineEnds)
        #expect(AnnotationContent(shape: .arrow, strokeWidth: 4).showsLineEnds)
        #expect(!AnnotationContent(shape: .rectangle, strokeWidth: 4).showsLineEnds)
        #expect(!AnnotationContent(shape: .ellipse, strokeWidth: 4).showsLineEnds)
        #expect(!AnnotationContent(shape: .highlight, strokeWidth: 4).showsLineEnds)
    }

    @Test("A line with no thickness left has no ends to shape")
    func noWidthNoEnds() {
        #expect(!AnnotationContent(shape: .line, strokeWidth: 0).showsLineEnds)
    }

    @Test("The row is offered on a line and an arrow and on nothing else")
    func theRowFollowsTheShape() {
        #expect(AnnotationContent(shape: .line, strokeWidth: 4).settingRows.contains(.lineEnds))
        #expect(AnnotationContent(shape: .arrow, strokeWidth: 4).settingRows.contains(.lineEnds))
        #expect(!AnnotationContent(shape: .rectangle, strokeWidth: 4).settingRows.contains(.lineEnds))
    }

    // MARK: Setting it

    @Test("One choice reaches every picked line, and says how many it changed")
    func setsEveryPickedShape() {
        var (document, ids) = document([line(), line()])
        #expect(document.setShapeLineEnd(layerIDs: ids, to: .square) == 2)
        #expect(document.layers.allSatisfy { $0.annotation?.lineEnd == .square })
        // Setting what is already set changes nothing, so a caller can tell a
        // no-op from an edit and never files an undo step for it.
        #expect(document.setShapeLineEnd(layerIDs: ids, to: .square) == 0)
    }

    @Test("A locked shape and a shape with no ends are left exactly as they are")
    func leavesWhatItCannotTouch() {
        var (document, ids) = document([line(), AnnotationContent(shape: .rectangle,
                                                                  strokeWidth: 4)])
        document.layers[0].isLocked = true
        #expect(document.setShapeLineEnd(layerIDs: ids, to: .flat) == 0)
        #expect(document.layers[0].annotation?.lineEnd == .round)
        #expect(document.layers[1].annotation?.lineEnd == .round)
    }

    @Test("The picked lines say what they all wear, or that they differ")
    func theRowReadsTheSelection() {
        var (document, ids) = document([line(), line()])
        document.setShapeLineEnd(layerIDs: [ids[0]], to: .flat)
        let selection = document.shapeSelection(layerIDs: ids)
        #expect(selection.reading(\.lineEnd).isMixed)
        document.setShapeLineEnd(layerIDs: ids, to: .flat)
        let same = document.shapeSelection(layerIDs: ids)
        #expect(same.reading(\.lineEnd).value == .flat)
        #expect(!same.reading(\.lineEnd).isMixed)
    }

    // MARK: Save and load

    @Test("The choice survives being saved and opened again")
    func survivesARoundTrip() throws {
        var content = line()
        content.lineEnd = .square
        let data = try JSONEncoder().encode(content)
        let back = try JSONDecoder().decode(AnnotationContent.self, from: data)
        #expect(back.lineEnd == .square)
    }

    @Test("A line drawn before there was a choice opens round, which is what it drew")
    func olderFilesOpenRound() throws {
        let json = """
        {"shape":"line","strokeWidth":8,"colorHex":"#FF3B30",
         "start":[0,0],"end":[100,0],"arrowheadScale":1}
        """
        let back = try JSONDecoder().decode(AnnotationContent.self,
                                            from: Data(json.utf8))
        #expect(back.lineEnd == .round)
    }

    // MARK: Room to draw it

    @Test("A square end asks the frame for more room than a round one, so it is not clipped")
    func squareEndsAskForMoreRoom() {
        var round = line(width: 10)
        round.lineEnd = .round
        var square = line(width: 10)
        square.lineEnd = .square
        var flat = line(width: 10)
        flat.lineEnd = .flat
        #expect(round.renderPadding == 5)
        #expect(flat.renderPadding == 5)
        // A square end's far CORNER sits width/√2 from the last point: 7.07,
        // rounded up to a whole point like every other reach.
        #expect(square.renderPadding == 8)
    }
}
