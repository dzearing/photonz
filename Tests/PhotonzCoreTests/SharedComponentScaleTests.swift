import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// A shared component arrives the size it LOOKS, not the size it was written
/// in (the task "A shared component arrives the size it should be in this
/// document", raised by the audit 2026-09-12-shared-components).
///
/// A document opened from a Retina capture measures everything in image
/// pixels, so a button that looks 60 points wide is 120 units wide there. Drop
/// it into a one-to-one document and 120 units is 120 points: twice the
/// button. The shelf records the scale the drawing was made at, and every way
/// in restates it in the scale of the document it is arriving in.
struct SharedComponentScaleTests {

    // MARK: - Two documents, two scales

    private func button() -> [Layer] {
        var box = Layer(name: "Box",
                        content: .annotation(AnnotationContent(shape: .rectangle,
                                                               strokeWidth: 4,
                                                               start: .zero,
                                                               end: CGPoint(x: 120, y: 40))),
                        frame: CGRect(x: 10, y: 10, width: 120, height: 40))
        box.style.cornerRadius = 8
        let label = Layer(name: "Label",
                          content: .text(TextContent(string: "Save", fontSize: 24)),
                          frame: CGRect(x: 20, y: 18, width: 60, height: 20))
        return [box, label]
    }

    /// A document at `pixelScale` holding a shared component "Button".
    private func documentSharing(pixelScale: CGFloat)
        -> (doc: PhotonzDocument, componentID: UUID, shared: SharedComponent) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: button(), pixelScale: pixelScale)
        let main = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        let shared = doc.shareComponent(componentID: componentID)!
        return (doc, componentID, shared)
    }

    private func blank(pixelScale: CGFloat) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [],
                        pixelScale: pixelScale)
    }

    private func label(in doc: PhotonzDocument, under mainID: UUID) -> TextContent? {
        guard let main = doc.layer(id: mainID) else { return nil }
        for child in main.selfAndDescendants {
            if case .text(let text) = child.content { return text }
        }
        return nil
    }

    // MARK: - The scale travels with the drawing

    @Test func theShelfRecordsTheScaleTheDrawingWasMadeAt() {
        let c = documentSharing(pixelScale: 2)
        #expect(c.shared.pixelScale == 2)
    }

    // MARK: - Dropping it in

    @Test func aRetinaComponentArrivesHalfSizeInAOneToOneDocument() {
        let c = documentSharing(pixelScale: 2)
        var target = blank(pixelScale: 1)
        let placed = target.adoptSharedComponent(c.shared, at: CGPoint(x: 400, y: 300))
        let main = target.layer(id: placed!)!
        #expect(main.localBounds.size == CGSize(width: 60, height: 20))
        #expect(label(in: target, under: main.id)?.fontSize == 12)
    }

    @Test func aOneToOneComponentArrivesDoubleSizeInARetinaDocument() {
        let c = documentSharing(pixelScale: 1)
        var target = blank(pixelScale: 2)
        let placed = target.adoptSharedComponent(c.shared, at: CGPoint(x: 400, y: 300))
        let main = target.layer(id: placed!)!
        #expect(main.localBounds.size == CGSize(width: 240, height: 80))
        #expect(label(in: target, under: main.id)?.fontSize == 48)
    }

    @Test func twoDocumentsAtTheSameScaleAreUnchanged() {
        let c = documentSharing(pixelScale: 2)
        var target = blank(pixelScale: 2)
        let placed = target.adoptSharedComponent(c.shared, at: CGPoint(x: 400, y: 300))
        let main = target.layer(id: placed!)!
        #expect(main.localBounds.size == CGSize(width: 120, height: 40))
        #expect(label(in: target, under: main.id)?.fontSize == 24)
    }

    @Test func aShelfWrittenBeforeTheScaleWasRecordedIsTakenVerbatim() {
        let c = documentSharing(pixelScale: 2)
        var old = c.shared
        old.pixelScale = nil
        var target = blank(pixelScale: 1)
        let placed = target.adoptSharedComponent(old, at: CGPoint(x: 400, y: 300))
        let main = target.layer(id: placed!)!
        #expect(main.localBounds.size == CGSize(width: 120, height: 40))
    }

    // MARK: - ...and every look at the shelf afterwards

    @Test func followingTheShelfKeepsTheSizeThisDocumentPutItAt() {
        let c = documentSharing(pixelScale: 2)
        var target = blank(pixelScale: 1)
        let placed = target.adoptSharedComponent(c.shared, at: CGPoint(x: 400, y: 300))!
        let shelf = SharedComponentShelf([c.shared])
        target.syncSharedComponents(from: shelf)
        #expect(target.layer(id: placed)?.localBounds.size == CGSize(width: 60, height: 20))
        // ...and a second look changes nothing at all, so an unchanged shelf
        // never records an edit.
        let report = target.syncSharedComponents(from: shelf)
        #expect(report.updatedComponents == 0)
    }

    @Test func anEditInTheSmallDocumentComesBackTheRightSizeInTheBigOne() {
        var c = documentSharing(pixelScale: 2)
        var target = blank(pixelScale: 1)
        let placed = target.adoptSharedComponent(c.shared, at: CGPoint(x: 400, y: 300))!
        // The second document widens the box inside it by 10 of its own points...
        let boxID = target.layer(id: placed)!.children.first(where: { $0.name == "Box" })!.id
        target.updateLayer(id: boxID) { $0.frame.size.width += 10 }
        let republished = target.sharedComponent(componentID: c.componentID)!
        #expect(republished.pixelScale == 1)
        // ...and the first document, which counts in twos, sees twenty.
        c.doc.syncSharedComponents(from: SharedComponentShelf([republished]))
        let mine = c.doc.mainComponent(componentID: c.componentID)!
        #expect(mine.localBounds.size == CGSize(width: 140, height: 40))
    }
}
