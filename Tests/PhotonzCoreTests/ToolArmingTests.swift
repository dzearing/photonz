import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Painting something that already exists arms the tool that draws it, so the
/// next one comes out the colour you just chose.
///
/// The toolbar swatch has always done this. The colour rows in the right-hand
/// panel did not, which made picking the same colour in two places mean two
/// different things. This is the reading that closes the gap: given the layers
/// a colour row just settled, which tools come away armed and with what.
///
/// It is the same rule Thickness and Corner Radius already follow from that
/// panel: every KIND of shape the change reached is armed for itself, so
/// painting a box and an arrow blue leaves both tools blue and leaves the
/// ellipse tool alone.
struct ToolArmingTests {

    // MARK: - Fixtures

    private func box(fill: String? = "#3366FF", stroke: String = "#101010",
                     locked: Bool = false) -> Layer {
        shape(.rectangle, fill: fill, stroke: stroke, locked: locked)
    }

    private func shape(_ kind: AnnotationShape, fill: String? = nil,
                       stroke: String = "#101010", locked: Bool = false) -> Layer {
        var annotation = AnnotationContent(shape: kind, start: .zero,
                                           end: CGPoint(x: 60, y: 30))
        annotation.colorHex = stroke
        if kind == .rectangle || kind == .ellipse { annotation.fillColorHex = fill }
        var layer = Layer(name: "\(kind)", content: .annotation(annotation),
                          frame: CGRect(x: 0, y: 0, width: 60, height: 30))
        layer.isLocked = locked
        return layer
    }

    private func text(_ color: String = "#FFFFFF") -> Layer {
        Layer(name: "Label", content: .text(TextContent(string: "Hi", colorHex: color)),
              frame: CGRect(x: 0, y: 0, width: 40, height: 20))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    private func ramp(_ hex: String, kind: Paint.Kind = .linear) -> Paint {
        var paint = Paint(hex: hex)
        paint.becoming(kind)
        return paint
    }

    // MARK: - One shape painted

    @Test func paintingOneBoxesOutlineArmsTheBoxTool() {
        let layer = box(stroke: "#B0184A")
        let doc = document([layer])
        let arming = doc.toolArming(layerIDs: [layer.id], slot: .stroke)
        #expect(arming.count == 1)
        #expect(arming.first?.shape == .rectangle)
        #expect(arming.first?.paint?.hex == "#B0184A")
    }

    @Test func paintingOneBoxesInsideArmsItsFill() {
        let layer = box(fill: "#34C759")
        let doc = document([layer])
        let arming = doc.toolArming(layerIDs: [layer.id], slot: .fill)
        #expect(arming.first?.shape == .rectangle)
        #expect(arming.first?.paint?.hex == "#34C759")
    }

    @Test func aGradientArmsTheToolAsAGradient() {
        var layer = box()
        layer.setPaint(ramp("#3366FF", kind: .radial), for: .fill)
        let doc = document([layer])
        let paint = doc.toolArming(layerIDs: [layer.id], slot: .fill).first?.paint
        #expect(paint?.isGradient == true)
        #expect(paint?.kind == .radial)
        #expect(paint?.hex == "#3366FF")
    }

    // MARK: - Every kind the change reached, and only those

    @Test func eachKindIsArmedForItself() {
        let rect = shape(.rectangle, stroke: "#B0184A")
        let arrow = shape(.arrow, stroke: "#B0184A")
        let doc = document([rect, arrow])
        let arming = doc.toolArming(layerIDs: [rect.id, arrow.id], slot: .stroke)
        #expect(arming.map(\.shape) == [.rectangle, .arrow])
        #expect(arming.allSatisfy { $0.paint?.hex == "#B0184A" })
    }

    @Test func aKindNobodyPickedIsNotArmed() {
        let rect = shape(.rectangle, stroke: "#B0184A")
        let doc = document([rect, shape(.ellipse)])
        let arming = doc.toolArming(layerIDs: [rect.id], slot: .stroke)
        #expect(arming.map(\.shape) == [.rectangle])
    }

    @Test func kindsComeBackInDrawOrderWithoutRepeats() {
        let a = shape(.line, stroke: "#B0184A")
        let b = shape(.arrow, stroke: "#B0184A")
        let c = shape(.line, stroke: "#B0184A")
        let doc = document([a, b, c])
        let arming = doc.toolArming(layerIDs: [a.id, b.id, c.id], slot: .stroke)
        #expect(arming.map(\.shape) == [.line, .arrow])
    }

    // MARK: - Only what there is one honest answer for

    @Test func aKindThatDoesNotAgreeArmsNothing() {
        let a = shape(.rectangle, stroke: "#B0184A")
        let b = shape(.rectangle, stroke: "#101010")
        let doc = document([a, b])
        #expect(doc.toolArming(layerIDs: [a.id, b.id], slot: .stroke).isEmpty)
    }

    @Test func oneKindDisagreeingDoesNotStopAnother() {
        let a = shape(.rectangle, stroke: "#B0184A")
        let b = shape(.rectangle, stroke: "#101010")
        let arrow = shape(.arrow, stroke: "#B0184A")
        let doc = document([a, b, arrow])
        let arming = doc.toolArming(layerIDs: [a.id, b.id, arrow.id], slot: .stroke)
        #expect(arming.map(\.shape) == [.arrow])
    }

    @Test func twoRampsOverTheSameColorDoNotAgree() {
        var a = box()
        a.setPaint(ramp("#3366FF", kind: .linear), for: .fill)
        var b = box()
        b.setPaint(ramp("#3366FF", kind: .radial), for: .fill)
        let doc = document([a, b])
        #expect(doc.toolArming(layerIDs: [a.id, b.id], slot: .fill).isEmpty)
    }

    // MARK: - Layers that have no say

    @Test func aLockedLayerIsNotWhatArmsTheTool() {
        let locked = shape(.rectangle, stroke: "#101010", locked: true)
        let live = shape(.rectangle, stroke: "#B0184A")
        let doc = document([locked, live])
        let arming = doc.toolArming(layerIDs: [locked.id, live.id], slot: .stroke)
        #expect(arming.first?.paint?.hex == "#B0184A",
                "a locked box the pick could not repaint must not make the row read Mixed")
    }

    @Test func aLineHasNoInsideToArm() {
        let line = shape(.line, stroke: "#B0184A")
        let doc = document([line])
        #expect(doc.toolArming(layerIDs: [line.id], slot: .fill).isEmpty)
    }

    @Test func aTextBlockArmsNoShape() {
        let label = text("#B0184A")
        let doc = document([label])
        #expect(doc.toolArming(layerIDs: [label.id], slot: .text).isEmpty)
    }

    @Test func nothingPickedArmsNothing() {
        let doc = document([box()])
        #expect(doc.toolArming(layerIDs: [], slot: .stroke).isEmpty)
    }

    // MARK: - An inside switched off is an answer too

    @Test func aBoxWithNoFillArmsTheToolWithNoFill() {
        let layer = box(fill: nil)
        let doc = document([layer])
        let arming = doc.toolArming(layerIDs: [layer.id], slot: .fill)
        #expect(arming.count == 1)
        #expect(arming.first?.paint == nil, "the next box comes out an outline, like this one")
    }

    @Test func aFilledBoxAndAnEmptyOneDoNotAgree() {
        let a = box(fill: "#34C759")
        let b = box(fill: nil)
        let doc = document([a, b])
        #expect(doc.toolArming(layerIDs: [a.id, b.id], slot: .fill).isEmpty)
    }

    // MARK: - Landing it on the tool

    @Test func armingLandsOnThePartTheRowPaints() {
        var styles = AnnotationStyles()
        styles.arm(ramp("#B0184A"), slot: .stroke, forShape: .rectangle)
        styles.arm(Paint(hex: "#34C759"), slot: .fill, forShape: .rectangle)
        #expect(styles.paint(forShape: .rectangle).isGradient)
        #expect(styles.paint(forShape: .rectangle).hex == "#B0184A")
        #expect(styles.fillPaint(forShape: .rectangle)?.hex == "#34C759")
    }

    @Test func armingWithNoFillLeavesTheNextBoxAnOutline() {
        var styles = AnnotationStyles()
        styles.arm(Paint(hex: "#34C759"), slot: .fill, forShape: .rectangle)
        styles.arm(nil, slot: .fill, forShape: .rectangle)
        #expect(styles.fillPaint(forShape: .rectangle) == nil)
        #expect(styles.content(for: .rectangle)?.fillColorHex == nil)
    }

    @Test func aShapeWithNoInsideIsNeverArmedWithOne() {
        var styles = AnnotationStyles()
        styles.arm(Paint(hex: "#34C759"), slot: .fill, forShape: .line)
        #expect(styles == AnnotationStyles())
    }

    @Test func aRingAndInkAreNotTheToolsColorToArm() {
        var styles = AnnotationStyles()
        styles.arm(Paint(hex: "#34C759"), slot: .border, forShape: .rectangle)
        styles.arm(Paint(hex: "#34C759"), slot: .text, forShape: .rectangle)
        #expect(styles == AnnotationStyles())
    }

    @Test func anOutlineIsNeverArmedWithNothing() {
        var styles = AnnotationStyles()
        styles.setPaint(Paint(hex: "#B0184A"), forShape: .arrow)
        styles.arm(nil, slot: .stroke, forShape: .arrow)
        #expect(styles.paint(forShape: .arrow).hex == "#B0184A",
                "a line always has a colour, so there is no nothing to arm it with")
    }
}
