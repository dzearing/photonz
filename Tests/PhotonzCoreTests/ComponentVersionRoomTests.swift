import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// Where a new version's drawing lands (`docs/design/ui-building.md`, "A
/// component holds more than one version").
///
/// Adding a version puts a whole second drawing on the canvas. Before this it
/// always went the same distance to the right of the one it was copied from,
/// which meant a third version landed exactly on the second, and any version
/// landed on whatever already happened to be sitting there. It now looks for
/// room first.
struct ComponentVersionRoomTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    /// A "Button" component at `at`, on a canvas of `canvas`.
    private func withButton(at rect: CGRect = CGRect(x: 40, y: 40, width: 120, height: 40),
                            canvas: CGSize = CGSize(width: 2000, height: 1200),
                            others: [Layer] = []) -> (doc: PhotonzDocument, componentID: UUID) {
        var doc = PhotonzDocument(canvasSize: canvas, layers: [box("Box", rect)] + others)
        let main = doc.groupLayers(ids: [doc.layers[0].id], name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        return (doc, componentID)
    }

    /// The canvas box of every version this component has.
    private func versionBoxes(_ doc: PhotonzDocument, _ componentID: UUID) -> [CGRect] {
        doc.componentVersions(of: componentID).compactMap { doc.canvasBounds(of: $0.layerID) }
    }

    // MARK: - Two drawings never share the same spot

    @Test func aSecondVersionLandsBesideTheFirst() {
        var c = withButton()
        _ = c.doc.addComponentVersion(componentID: c.componentID)
        let boxes = versionBoxes(c.doc, c.componentID)
        #expect(boxes.count == 2)
        // Same top edge, clear of the first, in the reading direction.
        #expect(boxes[1].minY == boxes[0].minY)
        #expect(boxes[1].minX >= boxes[0].maxX)
    }

    @Test func athirdVersionDoesNotLandOnTheSecond() {
        var c = withButton()
        _ = c.doc.addComponentVersion(componentID: c.componentID)
        _ = c.doc.addComponentVersion(componentID: c.componentID)
        _ = c.doc.addComponentVersion(componentID: c.componentID)
        let boxes = versionBoxes(c.doc, c.componentID)
        #expect(boxes.count == 4)
        for (i, a) in boxes.enumerated() {
            for b in boxes[(i + 1)...] {
                #expect(!a.intersects(b), "\(a) lands on \(b)")
            }
        }
    }

    /// Every version added from the FIRST one, which is what pressing Add
    /// Version repeatedly with the original selected does.
    @Test func versionsAddedFromTheSameSourceEachGetTheirOwnRoom() {
        var c = withButton()
        let first = c.doc.componentVersions(of: c.componentID)[0].id
        for _ in 0..<3 { _ = c.doc.addComponentVersion(componentID: c.componentID, from: first) }
        let boxes = versionBoxes(c.doc, c.componentID)
        #expect(boxes.count == 4)
        for (i, a) in boxes.enumerated() {
            for b in boxes[(i + 1)...] { #expect(!a.intersects(b), "\(a) lands on \(b)") }
        }
    }

    // MARK: - It steps past whatever is already there

    @Test func aVersionStepsPastSomethingAlreadySittingBeside() {
        var c = withButton(others: [box("Note", CGRect(x: 150, y: 0, width: 400, height: 300))])
        _ = c.doc.addComponentVersion(componentID: c.componentID)
        let added = versionBoxes(c.doc, c.componentID)[1]
        let occupant = c.doc.layers.first { $0.name == "Note" }!.frame
        #expect(!added.intersects(occupant))
        #expect(added.minX >= occupant.maxX)
    }

    @Test func aVersionNeverLandsOnAnyExistingLayer() {
        let clutter = [box("A", CGRect(x: 150, y: 0, width: 300, height: 200)),
                       box("B", CGRect(x: 500, y: 20, width: 300, height: 200)),
                       box("C", CGRect(x: 850, y: 10, width: 300, height: 90))]
        var c = withButton(others: clutter)
        _ = c.doc.addComponentVersion(componentID: c.componentID)
        let added = versionBoxes(c.doc, c.componentID)[1]
        for layer in c.doc.layers where layer.name != "Button" {
            #expect(!added.intersects(c.doc.canvasBounds(of: layer.id)!), "lands on \(layer.name)")
        }
    }

    // MARK: - It stays somewhere you can actually scroll to

    /// The canvas camera cannot travel past the canvas, so a drawing dropped
    /// off the edge is one nobody can look at. When the row runs out of canvas
    /// the new drawing starts a row underneath instead.
    @Test func aVersionWrapsBelowRatherThanLeavingTheCanvas() {
        var c = withButton(at: CGRect(x: 40, y: 40, width: 120, height: 40),
                           canvas: CGSize(width: 300, height: 900))
        _ = c.doc.addComponentVersion(componentID: c.componentID)
        let boxes = versionBoxes(c.doc, c.componentID)
        #expect(boxes[1].maxX <= 300)
        #expect(boxes[1].minY >= boxes[0].maxY)
        #expect(!boxes[1].intersects(boxes[0]))
    }

    @Test func aVersionStaysInsideTheCanvasWhenThereIsRoom() {
        var c = withButton(canvas: CGSize(width: 900, height: 700))
        for _ in 0..<4 { _ = c.doc.addComponentVersion(componentID: c.componentID) }
        let canvas = CGRect(x: 0, y: 0, width: 900, height: 700)
        for box in versionBoxes(c.doc, c.componentID) {
            #expect(canvas.contains(box), "\(box) is off the canvas")
        }
    }

    // MARK: - The backdrop is scenery, not an occupant

    /// Every real document has a Background layer covering the whole canvas.
    /// There is nowhere on the canvas that is not on top of it, so treating it
    /// as taken means nothing ever finds room and every version stacks on the
    /// last one. That is exactly what happened the first time this ran in the
    /// app: three drawings in one spot on a blank document.
    @Test func aFullCanvasBackdropDoesNotUseUpTheCanvas() {
        let backdrop = box("Background", CGRect(x: 0, y: 0, width: 2000, height: 1200))
        var c = withButton(others: [backdrop])
        for _ in 0..<3 { _ = c.doc.addComponentVersion(componentID: c.componentID) }
        let boxes = versionBoxes(c.doc, c.componentID)
        #expect(boxes.count == 4)
        for (i, a) in boxes.enumerated() {
            for b in boxes[(i + 1)...] { #expect(!a.intersects(b), "\(a) lands on \(b)") }
        }
    }

    /// Something merely LARGE is still something you can land on top of, so it
    /// is still stepped over.
    @Test func somethingLargeButNotTheWholeCanvasIsStillSteppedOver() {
        let big = box("Photo", CGRect(x: 0, y: 0, width: 1900, height: 1100))
        var c = withButton(at: CGRect(x: 40, y: 40, width: 120, height: 40), others: [big])
        _ = c.doc.addComponentVersion(componentID: c.componentID)
        let added = versionBoxes(c.doc, c.componentID)[1]
        #expect(!added.intersects(big.frame))
    }

    // MARK: - One undo takes the whole thing back

    @Test func oneUndoRemovesTheDrawingAndTheVersionTogether() {
        let c = withButton()
        var history = History(document: c.doc)
        let before = history.current.layers.count
        history.perform { _ = $0.addComponentVersion(componentID: c.componentID) }
        #expect(history.current.componentVersions(of: c.componentID).count == 2)
        #expect(history.current.layers.count == before + 1)
        history.undo()
        #expect(history.current.componentVersions(of: c.componentID).count == 1)
        #expect(history.current.layers.count == before)
    }
}
