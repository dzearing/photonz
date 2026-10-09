import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// The variants mock's Reset props: one press puts a copy's answers back to
/// what the original says, its variant included
/// (`docs/design/mocks/pages/ui-variants.html`, `#reset2`).
struct ComponentResetPropertiesTests {

    private func box(_ name: String, _ rect: CGRect, fill: String) -> Layer {
        var content = AnnotationContent(shape: .rectangle, start: .zero,
                                        end: CGPoint(x: rect.width, y: rect.height))
        content.fillColorHex = fill
        return Layer(name: name, content: .annotation(content), frame: rect)
    }

    private struct Fixture {
        var doc: PhotonzDocument
        var componentID: UUID
        var wording: UUID
        var show: UUID
    }

    /// A Button with a wording and a show-or-hide knob.
    private func fixture() -> Fixture {
        var doc = PhotonzDocument(
            canvasSize: CGSize(width: 900, height: 700),
            layers: [box("Box", CGRect(x: 10, y: 10, width: 160, height: 40), fill: "#3366FF"),
                     Layer(name: "Label", content: .text(TextContent(string: "Save")),
                           frame: CGRect(x: 24, y: 18, width: 60, height: 20)),
                     box("Icon", CGRect(x: 130, y: 18, width: 16, height: 16), fill: "#FFFFFF")])
        let labelID = doc.layers[1].id
        let iconID = doc.layers[2].id
        let main = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        let wording = doc.addComponentProperty(componentID: componentID, target: labelID, kind: .text)!
        let show = doc.addComponentProperty(componentID: componentID, target: iconID, kind: .visible)!
        return Fixture(doc: doc, componentID: componentID, wording: wording, show: show)
    }

    @Test func aCopyFollowingEverythingHasNothingToReset() {
        var f = fixture()
        let copy = f.doc.insertComponentInstance(of: f.componentID, at: CGPoint(x: 300, y: 300))!
        #expect(f.doc.canResetInstanceProperties(instances: [copy]) == false)
        let before = f.doc
        #expect(f.doc.resetInstanceProperties(instances: [copy]) == 0)
        #expect(f.doc == before)
    }

    @Test func resetClearsEveryAnswerTheCopyGaveItself() {
        var f = fixture()
        let copy = f.doc.insertComponentInstance(of: f.componentID, at: CGPoint(x: 300, y: 300))!
        f.doc.setInstanceOverride(instances: [copy], property: f.wording, value: .text("Buy"))
        f.doc.setInstanceOverride(instances: [copy], property: f.show, value: .visible(false))
        #expect(f.doc.instanceOverrides(instance: copy) == [f.wording, f.show])
        #expect(f.doc.canResetInstanceProperties(instances: [copy]))

        #expect(f.doc.resetInstanceProperties(instances: [copy]) == 1)
        #expect(f.doc.instanceOverrides(instance: copy).isEmpty)
        #expect(f.doc.canResetInstanceProperties(instances: [copy]) == false)
    }

    @Test func resetPutsTheCopyBackOnTheFirstVariant() {
        var f = fixture()
        let second = f.doc.addComponentVersion(componentID: f.componentID, name: "Secondary")!
        let copy = f.doc.insertComponentInstance(of: f.componentID, at: CGPoint(x: 300, y: 300))!
        let first = f.doc.componentVersions(of: f.componentID).first!.id
        #expect(f.doc.instanceVersion(of: copy) == first)

        f.doc.setInstanceVersion(instances: [copy], to: second)
        #expect(f.doc.canResetInstanceProperties(instances: [copy]))
        #expect(f.doc.resetInstanceProperties(instances: [copy]) == 1)
        #expect(f.doc.instanceVersion(of: copy) == first)
    }

    @Test func resetReachesEveryPickedCopyAndCountsOnlyTheOnesItChanged() {
        var f = fixture()
        let a = f.doc.insertComponentInstance(of: f.componentID, at: CGPoint(x: 300, y: 300))!
        let b = f.doc.insertComponentInstance(of: f.componentID, at: CGPoint(x: 300, y: 420))!
        let c = f.doc.insertComponentInstance(of: f.componentID, at: CGPoint(x: 300, y: 540))!
        f.doc.setInstanceOverride(instances: [a, b], property: f.wording, value: .text("Buy"))

        #expect(f.doc.resetInstanceProperties(instances: [a, b, c]) == 2)
        #expect(f.doc.instanceOverrides(instance: a).isEmpty)
        #expect(f.doc.instanceOverrides(instance: b).isEmpty)
    }

    @Test func aLockedCopyKeepsItsAnswers() {
        var f = fixture()
        let copy = f.doc.insertComponentInstance(of: f.componentID, at: CGPoint(x: 300, y: 300))!
        f.doc.setInstanceOverride(instances: [copy], property: f.wording, value: .text("Buy"))
        f.doc.updateLayer(id: copy) { $0.isLocked = true }

        #expect(f.doc.canResetInstanceProperties(instances: [copy]) == false)
        #expect(f.doc.resetInstanceProperties(instances: [copy]) == 0)
        #expect(f.doc.instanceOverrides(instance: copy) == [f.wording])
    }
}
