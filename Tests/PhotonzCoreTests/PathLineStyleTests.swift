import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What KIND of line a path is drawn with: how it ends, how it turns a corner,
/// and whether it is solid, dashed or dotted.
///
/// Raised by the user on 2026-09-14, first real session with the Pen: "in
/// appearance, there is a color but it's not clear its the stroke color and
/// thickness and also no brush style to choose". A path had exactly one
/// unnamed colour and no way to say anything about the line itself.
@Suite("A path's line style")
struct PathLineStyleTests {

    private func openPath(width: CGFloat = 4) -> PathContent {
        PathContent(anchors: [PathAnchor(point: .zero),
                              PathAnchor(point: CGPoint(x: 100, y: 0)),
                              PathAnchor(point: CGPoint(x: 100, y: 60))],
                    isClosed: false, strokeWidth: width, fill: nil)
    }

    // MARK: What a path arrives wearing

    @Test("A fresh path is drawn exactly as it always was: solid, round ends, sharp corners")
    func defaults() {
        let path = openPath()
        #expect(path.lineEnd == .round)
        #expect(path.lineCorner == .sharp)
        #expect(path.linePattern == .solid)
    }

    @Test("Every option is named in words a person recognises, not drawing-engine words")
    func titles() {
        #expect(PathLineEnd.allCases.map(\.title) == ["Flat", "Round", "Square"])
        #expect(PathLineCorner.allCases.map(\.title) == ["Sharp", "Round", "Flat"])
        #expect(PathLinePattern.allCases.map(\.title) == ["Solid", "Dashed", "Dotted"])
    }

    // MARK: Dashes

    @Test("A solid line has no dash pattern at all")
    func solidHasNoPattern() {
        #expect(PathLinePattern.solid.pattern(forWidth: 4) == nil)
    }

    @Test("Dashes and dots are measured in line widths, so they look the same at any weight")
    func patternScalesWithWeight() {
        let thin = PathLinePattern.dashed.pattern(forWidth: 2)
        let thick = PathLinePattern.dashed.pattern(forWidth: 8)
        #expect(thin == [6, 4])
        #expect(thick == [24, 16])
        #expect(PathLinePattern.dotted.pattern(forWidth: 4) == [4, 8])
    }

    @Test("A line with no width has no dashes to draw")
    func noWidthNoPattern() {
        #expect(PathLinePattern.dashed.pattern(forWidth: 0) == nil)
    }

    @Test("The dashes a path draws come off the weight it is actually wearing")
    func pathPattern() {
        var path = openPath(width: 6)
        #expect(path.dashPattern == nil)
        path.linePattern = .dashed
        #expect(path.dashPattern == [18, 12])
    }

    // MARK: Where a square end reaches

    @Test("A square end reaches further than a round one, so the bitmap makes room for it")
    func squareEndsReachFurther() {
        var path = openPath(width: 10)
        #expect(path.strokeOutset == 5)
        path.lineEnd = .square
        // The far corner of a square cap sits width/√2 from the end point,
        // which is further than the half width a round cap reaches.
        #expect(path.strokeOutset == 8)
    }

    @Test("A flat end reaches no further than a round one")
    func flatEndsReachTheSame() {
        var path = openPath(width: 10)
        path.lineEnd = .flat
        #expect(path.strokeOutset == 5)
    }

    @Test("A CLOSED path has no ends, so a square end asks for no extra room")
    func closedPathHasNoEnds() {
        var path = openPath(width: 10)
        path.isClosed = true
        path.lineEnd = .square
        #expect(path.strokeOutset == 5)
    }

    // MARK: On disk

    @Test("The line style survives save and load")
    func roundTrips() throws {
        var path = openPath()
        path.lineEnd = .square
        path.lineCorner = .round
        path.linePattern = .dotted
        let data = try JSONEncoder().encode(path)
        let back = try JSONDecoder().decode(PathContent.self, from: data)
        #expect(back.lineEnd == .square)
        #expect(back.lineCorner == .round)
        #expect(back.linePattern == .dotted)
    }

    @Test("A document saved before any of this existed opens with the look it had")
    func oldFilesKeepTheirLook() throws {
        let json = """
        {"anchors":[{"point":[0,0],"kind":"corner"},\
        {"point":[10,0],"kind":"corner"}],\
        "closed":false,"strokeWidth":4,"strokePosition":"center","fillRule":"nonZero"}
        """
        let back = try JSONDecoder().decode(PathContent.self, from: Data(json.utf8))
        #expect(back.lineEnd == .round)
        #expect(back.lineCorner == .sharp)
        #expect(back.linePattern == .solid)
    }

    // MARK: Setting it on a document

    private func document(_ path: PathContent) -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let layer = Layer(name: "Path", content: .path(path),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 60))
        doc.layers.append(layer)
        return (doc, layer.id)
    }

    @Test("One choice reaches every picked path and says how many it reached")
    func setsThemAll() {
        var (doc, first) = document(openPath())
        let second = Layer(name: "Path", content: .path(openPath()),
                           frame: CGRect(x: 0, y: 0, width: 100, height: 60))
        doc.layers.append(second)
        #expect(doc.setPathLineEnd(layerIDs: [first, second.id], to: .square) == 2)
        #expect(doc.layer(id: first)?.path?.lineEnd == .square)
        #expect(doc.layer(id: second.id)?.path?.lineEnd == .square)
    }

    @Test("A locked path is left exactly as it is")
    func locked() {
        var (doc, id) = document(openPath())
        doc.updateLayer(id: id) { $0.isLocked = true }
        #expect(doc.setPathLinePattern(layerIDs: [id], to: .dashed) == 0)
        #expect(doc.layer(id: id)?.path?.linePattern == .solid)
    }

    @Test("A layer that is not a path has no line style to set")
    func notAPath() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let box = Layer(name: "Rectangle",
                        content: .annotation(AnnotationContent(shape: .rectangle,
                                                               colorHex: "#FF0000",
                                                               start: .zero,
                                                               end: CGPoint(x: 40, y: 40))),
                        frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        doc.layers.append(box)
        #expect(doc.setPathLineCorner(layerIDs: [box.id], to: .round) == 0)
    }

    // MARK: Where the settings are OFFERED

    @Test("An open path is asked about its ends, because they are on screen")
    func openPathShowsEnds() {
        #expect(openPath().showsLineEnds)
    }

    @Test("A closed solid path is not asked about its ends: it has none")
    func closedSolidPathHidesEnds() {
        var path = openPath()
        path.isClosed = true
        #expect(!path.showsLineEnds)
    }

    @Test("A closed DASHED path is asked about its ends again: every dash has two")
    func closedDashedPathShowsEnds() {
        var path = openPath()
        path.isClosed = true
        path.linePattern = .dashed
        #expect(path.showsLineEnds)
    }
}
