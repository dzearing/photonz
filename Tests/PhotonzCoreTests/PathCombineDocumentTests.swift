import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The four area operations carried across to a real document: which layer
/// survives, what it is left wearing, and what it says happened
/// (`PathCombining.swift`).
@Suite("Combining shapes in a document")
struct PathCombineDocumentTests {

    // MARK: Helpers

    private func ellipseLayer(_ name: String, at origin: CGPoint,
                              size: CGFloat = 100, fill: String = "#34C759") -> Layer {
        var shape = AnnotationContent(shape: .ellipse, strokeWidth: 4, colorHex: "#FF3B30",
                                      start: .zero, end: CGPoint(x: size, y: size))
        shape.fill = Paint(hex: fill)
        return Layer(name: name, content: .annotation(shape),
                     frame: CGRect(origin: origin, size: CGSize(width: size, height: size)))
    }

    private func lineLayer(_ name: String) -> Layer {
        let shape = AnnotationContent(shape: .line, strokeWidth: 6, colorHex: "#FF3B30",
                                      start: .zero, end: CGPoint(x: 100, y: 60))
        var layer = AnnotationBuilder.layer(content: shape, from: CGPoint(x: 400, y: 400),
                                           to: CGPoint(x: 500, y: 460))
        layer.name = name
        return layer
    }

    /// Two ovals overlapping in the middle: the pair every one of the four
    /// commands is shown on.
    private func pair() -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        document.layers = [ellipseLayer("Circle A", at: CGPoint(x: 40, y: 40)),
                           ellipseLayer("Circle B", at: CGPoint(x: 100, y: 40), fill: "#FF9F0A")]
        return document
    }

    private func ids(_ document: PhotonzDocument) -> Set<UUID> {
        Set(document.layers.map(\.id))
    }

    // MARK: A rectangle and an oval are outlines too

    @Test("Ovals drawn with the shape tool combine without being converted first")
    func shapesCombineAsThemselves() throws {
        var document = pair()
        let bottom = document.layers[0].id
        let plan = document.combineLayers(ids: ids(document), .join)
        #expect(plan.takes == 2)
        #expect(plan.didAnything)
        #expect(document.layers.count == 1)
        let survivor = try #require(document.layer(id: bottom))
        #expect(survivor.path != nil, "what is left is a path, not an oval")
        #expect(survivor.name == "Circle A")
    }

    @Test("A rectangle and an oval become one shape")
    func rectangleAndOvalCombine() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        var box = AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#FF3B30",
                                    start: .zero, end: CGPoint(x: 120, y: 60))
        box.fill = Paint(hex: "#3478F6")
        document.layers = [Layer(name: "Box", content: .annotation(box),
                                 frame: CGRect(x: 20, y: 20, width: 120, height: 60)),
                           ellipseLayer("Oval", at: CGPoint(x: 100, y: 10), size: 80)]
        let plan = document.combineLayers(ids: ids(document), .join)
        #expect(plan.didAnything)
        #expect(document.layers.count == 1)
        let path = try #require(document.layers[0].path)
        #expect(path.ringCount == 1)
        #expect(path.anchors.count > 4)
    }

    // MARK: Which layer survives

    @Test("The bottom shape survives, keeping its slot, its name and its effects")
    func theBottomShapeSurvives() throws {
        var document = pair()
        document.layers[0].style.blurRadius = 8
        let bottom = document.layers[0].id
        let top = document.layers[1].id
        let plan = document.combineLayers(ids: ids(document), .cutOut)
        #expect(plan.keeper == "Circle A")
        #expect(document.layer(id: top) == nil)
        let survivor = try #require(document.layer(id: bottom))
        #expect(survivor.style.blurRadius == 8, "the softness came with it")
        let path = try #require(survivor.path)
        #expect(path.fillColorHex == "#34C759", "the bottom shape's fill, not the top one's")
    }

    @Test("A turned shape combines as the shape you can see, and comes back unturned")
    func turnedShapesCombineWhereTheyLook() throws {
        var document = pair()
        document.layers[1].transform = LayerTransform(rotation: .pi / 4)
        let plan = document.combineLayers(ids: ids(document), .join)
        #expect(plan.didAnything)
        let survivor = try #require(document.layers.first)
        #expect(survivor.transform.isIdentity, "the turn is part of the outline now")
        // A turned circle covers the same box, so the join reaches as far as
        // the unturned one would. What matters is that it ran at all.
        #expect(survivor.frame.width > 100)
    }

    // MARK: The edge cases, answered rather than crashed

    @Test("Keeping the overlap of shapes that do not touch changes nothing")
    func nothingToKeepChangesNothing() {
        var document = pair()
        document.layers[1].frame.origin = CGPoint(x: 300, y: 200)
        let before = document
        let plan = document.combineLayers(ids: ids(document), .keepOverlap)
        #expect(plan.cameToNothing)
        #expect(plan.didAnything == false)
        #expect(document.layers.count == before.layers.count)
        #expect(plan.title == "Nothing to keep")
        #expect(plan.detail.contains("do not overlap"))
        #expect(plan.detail.contains("nothing was changed"))
    }

    @Test("A shape cut out of a copy of itself changes nothing")
    func cutOutOfItselfChangesNothing() {
        var document = pair()
        document.layers[1].frame = document.layers[0].frame
        let plan = document.combineLayers(ids: ids(document), .cutOut)
        #expect(plan.cameToNothing)
        #expect(document.layers.count == 2)
    }

    @Test("A line has no inside, so it is left exactly where it was")
    func linesAreLeftAlone() throws {
        var document = pair()
        document.layers.append(lineLayer("Line 1"))
        let line = document.layers[2].id
        let plan = document.combineLayers(ids: ids(document), .join)
        #expect(plan.takes == 2)
        #expect(plan.leftOut == 1)
        #expect(document.layer(id: line) != nil, "the line is still there")
        #expect(plan.detail.contains("left alone"))
    }

    @Test("One shape on its own is not enough, and nothing happens")
    func oneShapeDoesNothing() {
        var document = pair()
        let plan = document.combineLayers(ids: [document.layers[0].id], .join)
        #expect(plan.takes == 1)
        #expect(plan.didAnything == false)
        #expect(document.layers.count == 2)
    }

    @Test("A locked shape cannot be combined away underneath somebody")
    func lockedShapesStayOut() {
        var document = pair()
        document.layers[1].isLocked = true
        #expect(document.combinableLayers(ids: ids(document)).count == 1)
    }

    // MARK: What it says happened

    @Test("The line under the canvas names the shape whose look survived")
    func theNoticeNamesTheKeeper() {
        var document = pair()
        let plan = document.combineLayers(ids: ids(document), .join)
        #expect(plan.title == "Joined")
        #expect(plan.detail.hasPrefix("2 shapes are now one path"))
        #expect(plan.detail.contains("keeping Circle A's fill, outline and effects"))
        #expect(plan.detail.contains("—") == false)
    }

    @Test("A cut that leaves a hole says so, because a hole is easy to miss")
    func theNoticeSaysThereIsAHole() {
        var document = pair()
        // A small oval wholly inside the big one. It has to be built rather
        // than have its frame moved: a shape tool's oval is drawn from its own
        // start and end, which a new frame alone does not change.
        document.layers[1] = ellipseLayer("Circle B", at: CGPoint(x: 65, y: 65),
                                          size: 50, fill: "#FF9F0A")
        let plan = document.combineLayers(ids: ids(document), .cutOut)
        #expect(plan.rings == 2)
        #expect(plan.detail.contains("It has a hole in it"))
    }

    @Test("A result in unconnected pieces says how many")
    func theNoticeCountsThePieces() {
        var document = pair()
        document.layers[1].frame.origin = CGPoint(x: 300, y: 40)
        let plan = document.combineLayers(ids: ids(document), .join)
        #expect(plan.rings == 2)
        #expect(plan.detail.contains("2 pieces"))
    }

    // MARK: What the row is called afterwards

    /// The pair as the shape tool actually leaves it: two ovals nobody has
    /// named, so their rows read "Ellipse" and "Ellipse 2".
    private func unnamedPair() -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        document.layers = [ellipseLayer("Ellipse", at: CGPoint(x: 40, y: 40)),
                           ellipseLayer("Ellipse 2", at: CGPoint(x: 100, y: 40), fill: "#FF9F0A")]
        return document
    }

    @Test("Two unnamed ovals combined leave one row called Path")
    func combiningRenamesTheSurvivor() throws {
        for operation in PathCombine.Operation.allCases {
            var document = unnamedPair()
            let plan = document.combineLayers(ids: ids(document), operation)
            #expect(plan.didAnything, "\(operation) should have combined the pair")
            let survivor = try #require(document.layers.first)
            #expect(survivor.path != nil)
            #expect(survivor.displayName == "Path",
                    "\(operation) left the row saying \(survivor.displayName)")
        }
    }

    @Test("A layer somebody called Card is still called Card")
    func aHandNamedShapeKeepsItsName() throws {
        for operation in PathCombine.Operation.allCases {
            var document = unnamedPair()
            document.layers[0].name = "Card"
            document.combineLayers(ids: ids(document), operation)
            #expect(document.layers.first?.name == "Card")
        }
    }

    @Test("A survivor already called Path keeps its number rather than taking the next one")
    func anAlreadyPathNameIsNotBumped() throws {
        var document = unnamedPair()
        document.layers[0].name = "Path"
        document.layers[1].name = "Path 2"
        document.combineLayers(ids: ids(document), .join)
        #expect(document.layers.first?.name == "Path",
                "the two it absorbed are gone, so there is nothing to be told apart from")
    }

    @Test("A Path already in the list means the new one takes the next number")
    func theNewNameAvoidsOneAlreadyTaken() throws {
        var document = unnamedPair()
        var elsewhere = ellipseLayer("Path", at: CGPoint(x: 300, y: 200))
        elsewhere.name = "Path"
        document.addLayer(elsewhere)
        let pairIDs = Set(document.layers.prefix(2).map(\.id))
        document.combineLayers(ids: pairIDs, .join)
        #expect(document.layers.first?.name == "Path 2")
    }

    @Test("The new name rides in the same step, so one undo puts both back")
    func theRenameRidesInTheSameUndoStep() throws {
        let document = unnamedPair()
        let bottom = try #require(document.layers.first?.id)
        var history = History(document: document)
        history.perform { $0.combineLayers(ids: Set(document.layers.map(\.id)), .join) }
        #expect(history.current.layer(id: bottom)?.name == "Path")
        history.undo()
        #expect(history.current.layers.count == 2)
        #expect(history.current.layer(id: bottom)?.name == "Ellipse")
        #expect(history.current.layer(id: bottom)?.annotation?.shape == .ellipse)
        #expect(!history.canUndo)
    }

    @Test("The line under the canvas names the row the way it read before the combine")
    func theNoticeUsesTheNameThatWasOnScreen() {
        var document = unnamedPair()
        let plan = document.combineLayers(ids: ids(document), .join)
        #expect(plan.keeper == "Ellipse")
        #expect(plan.detail.contains("keeping Ellipse's fill, outline and effects"))
    }

    // MARK: It survives the disk

    @Test("A document with a hole in it saves and opens again with the hole")
    func theHoleSurvivesTheDocument() throws {
        var document = pair()
        // A small oval wholly inside the big one. It has to be built rather
        // than have its frame moved: a shape tool's oval is drawn from its own
        // start and end, which a new frame alone does not change.
        document.layers[1] = ellipseLayer("Circle B", at: CGPoint(x: 65, y: 65),
                                          size: 50, fill: "#FF9F0A")
        document.combineLayers(ids: ids(document), .cutOut)
        let data = try JSONEncoder().encode(document)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        let path = try #require(back.layers.first?.path)
        #expect(path.ringCount == 2)
        #expect(path.hasSeveralRings)
    }
}
