import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// Placing a copy of a PARTICULAR version, straight from the shelf
/// (`docs/design/ui-building.md`, "A component holds more than one version").
///
/// Before this, every copy landed showing the component's first version, so a
/// disabled button was two steps: place one, then switch it. The shelf can now
/// hand over the version you asked for, and the copy arrives already showing
/// it.
struct ComponentVersionPlacementTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    /// "Button" with two versions: Default, and a Disabled one whose label
    /// reads differently and whose box is wider, so a copy of it is
    /// recognisable by its contents AND by its size.
    private func withTwoVersions() -> (doc: PhotonzDocument, componentID: UUID,
                                       first: UUID, disabled: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 900, height: 700),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 120, height: 40)),
                                           text("Label", "Save", CGRect(x: 20, y: 18, width: 60, height: 20))])
        let main = doc.groupLayers(ids: [doc.layers[0].id, doc.layers[1].id], name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        let disabled = doc.addComponentVersion(componentID: componentID)!
        doc.renameComponentVersion(componentID: componentID, version: disabled, to: "Disabled")
        // Make the second drawing genuinely different: wider box, other words.
        let drawing = doc.mainComponent(componentID: componentID, version: disabled)!
        let disabledBox = drawing.children[0].id
        let disabledLabel = drawing.children[1].id
        doc.updateLayer(id: disabledBox) { $0.frame.size.width = 200 }
        doc.updateLayer(id: disabledLabel) { layer in
            guard case .text(var content) = layer.content else { return }
            content.string = "Saving"
            layer.content = .text(content)
        }
        let first = doc.componentVersions(of: componentID)[0].id
        return (doc, componentID, first, disabled)
    }

    // MARK: - The copy arrives showing what was asked for

    @Test func placingAVersionLandsACopyAlreadyShowingIt() {
        var c = withTwoVersions()
        let copy = c.doc.insertComponentInstance(of: c.componentID,
                                                 at: CGPoint(x: 500, y: 400),
                                                 version: c.disabled)!
        #expect(c.doc.instanceVersion(of: copy) == c.disabled)
        // ...and it DRAWS that version, rather than naming it and showing the
        // other one.
        let strings = c.doc.layer(id: copy)!.selfAndDescendants.compactMap { layer -> String? in
            guard case .text(let content) = layer.content else { return nil }
            return content.string
        }
        #expect(strings == ["Saving"])
    }

    @Test func aPlacedVersionIsTheSizeOfThatDrawing() {
        var c = withTwoVersions()
        let point = CGPoint(x: 500, y: 400)
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: point, version: c.disabled)!
        let placed = c.doc.layer(id: copy)!
        let drawing = c.doc.mainComponent(componentID: c.componentID, version: c.disabled)!
        #expect(placed.frame.size == drawing.frame.size)
        // Centred on the drop, the same rule a copy of the first version follows.
        #expect(abs(placed.localBounds.midX - point.x) < 0.01)
        #expect(abs(placed.localBounds.midY - point.y) < 0.01)
    }

    @Test func askingForNoVersionStillPlacesTheFirst() {
        var c = withTwoVersions()
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 500, y: 400))!
        #expect(c.doc.instanceVersion(of: copy) == c.first)
        let strings = c.doc.layer(id: copy)!.selfAndDescendants.compactMap { layer -> String? in
            guard case .text(let content) = layer.content else { return nil }
            return content.string
        }
        #expect(strings == ["Save"])
    }

    @Test func aVersionThisComponentDoesNotHoldFallsBackToTheFirst() {
        var c = withTwoVersions()
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 500, y: 400),
                                                 version: UUID())!
        #expect(c.doc.instanceVersion(of: copy) == c.first)
    }

    /// A component with one version has no version to name, and placing it is
    /// exactly what it always was.
    @Test func aComponentWithOneVersionPlacesAsItAlwaysDid() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 120, height: 40))])
        let main = doc.groupLayers(ids: [doc.layers[0].id], name: "Chip")!
        let componentID = doc.makeComponent(id: main.id)!
        let only = doc.componentVersions(of: componentID)[0].id
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 300, y: 300),
                                               version: only)!
        // Nothing is written down, because there is nothing to tell apart.
        #expect(doc.layer(id: copy)?.instanceVersionID == nil)
        #expect(doc.instanceVersion(of: copy) == only)
    }

    /// Switching the copy afterwards still works, so choosing at the shelf is
    /// a shortcut rather than a decision you are stuck with.
    @Test func aCopyPlacedAsOneVersionCanStillBeSwitched() {
        var c = withTwoVersions()
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: CGPoint(x: 500, y: 400),
                                                 version: c.disabled)!
        let switched = c.doc.setInstanceVersion(instance: copy, to: c.first)
        #expect(switched)
        #expect(c.doc.instanceVersion(of: copy) == c.first)
    }

    // MARK: - What the drag in the air promises

    @Test func theBoxDrawnMidDragIsTheChosenVersionsSize() {
        let c = withTwoVersions()
        let first = c.doc.componentDropSize(of: c.componentID, version: c.first)!
        let disabled = c.doc.componentDropSize(of: c.componentID, version: c.disabled)!
        #expect(disabled.width > first.width)
        #expect(disabled == c.doc.mainComponent(componentID: c.componentID,
                                                version: c.disabled)!.localBounds.size)
        // Naming nothing is the first version, which is what it always drew.
        #expect(c.doc.componentDropSize(of: c.componentID) == first)
    }

    @Test func theLandingOutlineIsTheChosenVersionsSize() {
        var c = withTwoVersions()
        let point = CGPoint(x: 500, y: 400)
        let landing = c.doc.componentDropLanding(of: c.componentID, at: point,
                                                 version: c.disabled)!
        #expect(landing.host == nil)
        #expect(landing.rect.size == c.doc.componentDropSize(of: c.componentID,
                                                             version: c.disabled)!)
        // What the outline promised is what the drop delivers.
        let copy = c.doc.insertComponentInstance(of: c.componentID, at: point, version: c.disabled)!
        let placed = c.doc.layer(id: copy)!
        #expect(placed.localBounds.size == landing.rect.size)
        #expect(abs(placed.localBounds.midX - landing.rect.midX) < 0.01)
    }
}
