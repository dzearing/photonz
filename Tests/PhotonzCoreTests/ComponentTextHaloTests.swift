import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Text inside a component is a label on a control, not a caption over a
/// screenshot, so the contrast halo every new text layer is born wearing is not
/// drawn there (`docs/design/ui-building.md`, step E9).
///
/// The rule is read at draw time and nothing is erased: the halo the text was
/// given is still on the layer, so taking the text back out brings it back.
@Suite("Component text halo")
struct ComponentTextHaloTests {

    private func text(_ string: String, colorHex: String = "#000000",
                      at point: CGPoint = .zero) -> Layer {
        TextBuilder.layer(content: TextContent(string: string, fontSize: 14, colorHex: colorHex),
                          at: point, naturalSize: CGSize(width: 40, height: 18))
    }

    private func box(_ rect: CGRect) -> Layer {
        Layer(name: "Box",
              content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                     end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    /// A red box with a black label on it, grouped and promoted: the button
    /// from the end-to-end walk that showed the smudge.
    private func button() -> (document: PhotonzDocument, componentID: UUID,
                              groupID: UUID, labelID: UUID) {
        let label = text("Save", at: CGPoint(x: 20, y: 12))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300),
                                  layers: [box(CGRect(x: 10, y: 10, width: 120, height: 40)), label])
        let group = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Group")!
        let componentID = doc.makeComponent(id: group.id)!
        return (doc, componentID, group.id, label.id)
    }

    // MARK: - The rule itself

    @Test func newTextIsBornWearingTheHalo() {
        let layer = text("Save")
        #expect(layer.style.shadow == TextBuilder.autoContrastShadow(forColorHex: "#000000"))
        #expect(layer.drawnShadow(insideComponent: false) == layer.style.shadow)
    }

    @Test func insideAComponentTheHaloIsNotDrawn() {
        #expect(text("Save").drawnShadow(insideComponent: true) == nil)
    }

    @Test func theHaloIsNotErasedOnlyLeftUndrawn() {
        let layer = text("Save")
        #expect(layer.style.shadow != nil)
        // The same layer, asked the other way, still has it to give.
        #expect(layer.drawnShadow(insideComponent: false) != nil)
    }

    @Test func aShadowSomebodyChoseStillDrawsInsideAComponent() {
        var layer = text("Save")
        layer.style.shadow = ShadowStyle(radius: 12, offset: CGSize(width: 0, height: 6),
                                         colorHex: "#000000", opacity: 0.4)
        #expect(layer.drawnShadow(insideComponent: true) == layer.style.shadow)
    }

    @Test func theRuleOnlyTouchesText() {
        var shape = box(CGRect(x: 0, y: 0, width: 10, height: 10))
        shape.style.shadow = TextBuilder.autoContrastShadow(forColorHex: "#000000")
        #expect(shape.drawnShadow(insideComponent: true) == shape.style.shadow)
    }

    @Test func recoloredTextKeepsTheRule() {
        // Repainting refreshes the halo for the new color; the rule follows it.
        let layer = TextBuilder.restyled(layer: text("Save"), colorHex: "#FFFFFF")
        #expect(layer.style.shadow == TextBuilder.autoContrastShadow(forColorHex: "#FFFFFF"))
        #expect(layer.drawnShadow(insideComponent: true) == nil)
    }

    // MARK: - Who counts as inside

    @Test func textOnTheCanvasIsNotInsideAComponent() {
        let layer = text("Gap 16")
        let doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [layer])
        #expect(doc.isInsideComponent(layer.id) == false)
    }

    @Test func aPlainGroupIsNotAComponent() {
        // The everyday redline move: an arrow and its caption bundled together.
        let caption = text("Gap 16")
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300),
                                  layers: [box(CGRect(x: 0, y: 0, width: 40, height: 4)), caption])
        _ = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Group")
        #expect(doc.isInsideComponent(caption.id) == false)
    }

    @Test func textInsideTheOriginalIsInsideAComponent() {
        let made = button()
        #expect(made.document.isInsideComponent(made.labelID))
    }

    @Test func textInsideACopyIsInsideAComponent() {
        var (doc, componentID, _, _) = button()
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 200, y: 150))!
        let labelInCopy = doc.layer(id: copy)!.children.first { $0.isText }!
        #expect(doc.isInsideComponent(labelInCopy.id))
        #expect(labelInCopy.drawnShadow(insideComponent: true) == nil)
    }

    @Test func nestingDeeperStaysInside() {
        var (doc, _, groupID, labelID) = button()
        // A group inside the component: the label is two levels down now.
        _ = doc.groupLayers(ids: [labelID], name: "Inner")
        #expect(doc.isInsideComponent(labelID))
        #expect(doc.layer(id: groupID)?.isMainComponent == true)
    }

    @Test func theComponentItselfIsNotInsideItself() {
        let made = button()
        #expect(made.document.isInsideComponent(made.groupID) == false)
    }

    // MARK: - Making and unmaking

    @Test func promotingDropsTheHaloAndUngroupingPutsItBack() {
        var (doc, _, groupID, labelID) = button()
        #expect(doc.isInsideComponent(labelID))

        _ = doc.ungroupLayers(ids: [groupID])
        #expect(doc.isInsideComponent(labelID) == false)
        // Nothing was erased on the way in, so the halo is simply drawn again.
        let label = doc.layer(id: labelID)!
        #expect(label.drawnShadow(insideComponent: false)
                == TextBuilder.autoContrastShadow(forColorHex: "#000000"))
    }
}
