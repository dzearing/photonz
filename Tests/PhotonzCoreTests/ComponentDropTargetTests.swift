import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// What letting go of a component over a canvas point would do, asked BEFORE
/// the button comes up so the canvas can say so while the drag is still in the
/// air (`docs/design/ui-building.md`, "Dragging one out of the Library").
///
/// The same answer decides the drop itself, so the picture the canvas draws
/// mid-drag and what actually happens can never disagree.
struct ComponentDropTargetTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    /// One component, 60 x 70, made out of two pieces near the origin.
    private func withComponent() -> (PhotonzDocument, UUID, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 60, height: 30)),
                                           box("Label", CGRect(x: 20, y: 50, width: 40, height: 30))])
        let group = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Setting")!
        let componentID = doc.makeComponent(id: group.id)!
        return (doc, group.id, componentID)
    }

    // MARK: - Where it would land

    @Test func bareCanvasIsBareCanvas() {
        let (doc, _, componentID) = withComponent()
        #expect(doc.componentDropTarget(of: componentID, at: CGPoint(x: 400, y: 300)) == .canvas)
    }

    @Test func aPointOnAFrameJoinsThatFrame() {
        var (doc, _, componentID) = withComponent()
        let frame = doc.addFrame(origin: CGPoint(x: 200, y: 200), size: CGSize(width: 300, height: 300))
        #expect(doc.componentDropTarget(of: componentID, at: CGPoint(x: 250, y: 250)) == .frame(frame.id))
        // ...and a point just outside it does not.
        #expect(doc.componentDropTarget(of: componentID, at: CGPoint(x: 150, y: 250)) == .canvas)
    }

    /// The one drop that is refused outright: a copy landing inside its own
    /// original would draw forever.
    @Test func droppingAComponentOntoItsOwnOriginalIsRefused() {
        var (doc, main, componentID) = withComponent()
        doc.setFrame(id: main, isFrame: true)
        // The original sits at 10,10 and is 60 x 70, so its middle is inside it.
        #expect(doc.componentDropTarget(of: componentID, at: CGPoint(x: 40, y: 45)) == .refused)
    }

    @Test func anUnknownComponentIsRefused() {
        let (doc, _, _) = withComponent()
        #expect(doc.componentDropTarget(of: UUID(), at: CGPoint(x: 400, y: 300)) == .refused)
    }

    /// A starter is not in the document until it is dropped, so its target is
    /// answered from the shelf rather than from a main that is not there yet.
    @Test func aStarterStillOnTheShelfLandsOnTheFrameUnderIt() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [])
        let frame = doc.addFrame(origin: CGPoint(x: 100, y: 100), size: CGSize(width: 200, height: 200))
        #expect(doc.componentDropTarget(of: StarterComponent.button.componentID,
                                        at: CGPoint(x: 150, y: 150)) == .frame(frame.id))
        #expect(doc.componentDropTarget(of: StarterComponent.button.componentID,
                                        at: CGPoint(x: 500, y: 500)) == .canvas)
    }

    /// The drop agrees with the picture: what `componentDropTarget` promised is
    /// where `insertComponentInstance` actually put it.
    @Test func theDropAgreesWithWhatWasPromised() {
        var (doc, _, componentID) = withComponent()
        let frame = doc.addFrame(origin: CGPoint(x: 200, y: 200), size: CGSize(width: 300, height: 300))
        let point = CGPoint(x: 300, y: 300)
        #expect(doc.componentDropTarget(of: componentID, at: point) == .frame(frame.id))
        let placed = doc.insertComponentInstance(of: componentID, at: point)!
        #expect(doc.parentID(of: placed) == frame.id)
    }

    // MARK: - How big it would be

    @Test func aComponentLandsAtTheSizeOfItsOriginal() {
        let (doc, _, componentID) = withComponent()
        #expect(doc.componentDropSize(of: componentID) == CGSize(width: 60, height: 70))
    }

    @Test func aStarterLandsAtTheSizeItIsDrawnAt() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [])
        let size = doc.componentDropSize(of: StarterComponent.button.componentID)
        #expect(size != nil)
        #expect(size!.width > 0 && size!.height > 0)
        // ...and it is the size the drop actually produces.
        var placing = doc
        let placed = placing.insertStarterComponent(.button, at: CGPoint(x: 400, y: 300))!
        #expect(placing.layer(id: placed)!.localBounds.size == size!)
    }

    @Test func somethingThatIsNotAComponentHasNoSize() {
        let (doc, _, _) = withComponent()
        #expect(doc.componentDropSize(of: UUID()) == nil)
    }
}
