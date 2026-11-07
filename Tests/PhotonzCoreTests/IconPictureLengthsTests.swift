import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// On a picture that is 24 units across, every length a person reads or types
/// is in those units, the same as the tag above the shape.
@Suite("An icon picture's lengths read in its units")
struct IconPictureLengthsTests {

    static let unit: CGFloat = 512.0 / 24
    static let lengths = LengthUnit(points: unit)

    static func picture(layers: [Layer] = []) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 512, height: 512), layers: layers)
        document.madeAsIcon = true
        return document
    }

    static func pen(width: CGFloat) -> Layer {
        let content = PathContent(anchors: [PathAnchor(point: CGPoint(x: 5 * unit, y: 6 * unit)),
                                            PathAnchor(point: CGPoint(x: 18 * unit, y: 6 * unit))],
                                  isClosed: false, paint: Paint(hex: "#000000"), strokeWidth: width)
        return PathBuilder.layer(content, at: content.bounds.origin)
    }

    static func member(_ frame: CGRect, id: UUID = UUID()) -> LayerGeometrySelection.Member {
        let layer = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 2,
                                                                              start: .zero, end: CGPoint(x: 10, y: 10))),
                          frame: frame)
        return LayerGeometrySelection.Member(id: id, frame: frame, editing: LayerGeometryEditing(layer: layer))
    }

    // MARK: Which pictures

    @Test("An Icon picture has units, and every other picture has points")
    func whichPictures() {
        #expect(Self.picture().lengthUnit == Self.lengths)
        #expect(!Self.picture().lengthUnit.isPoint)
        #expect(PhotonzDocument(canvasSize: CGSize(width: 512, height: 512), layers: []).lengthUnit == .point)
    }

    @Test("A 24 unit icon frame on a bigger canvas reads as it does today")
    func frameOnABiggerCanvas() {
        let frame = Layer.frameLayer(name: "Icon", origin: CGPoint(x: 40, y: 40),
                                     size: CGSize(width: 24, height: 24), children: [], backgroundHex: nil)
        let document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [frame])
        #expect(document.lengthUnit == .point)
        #expect(LengthUnit.point.lineWidth == SliderNumber.lineWidth)
        #expect(LengthUnit.point.length == SliderNumber.points)
        #expect(LengthUnit.point.strokeWidthRange == AnnotationStyles.strokeWidthRange)
    }

    // MARK: Width

    @Test("1.75 typed lands as the icon's 1.75, and reads back as 1.75")
    func typedWidth() {
        let typing = Self.lengths.lineWidth
        let stored = Self.lengths.typedLength(typing.slid(1.75))
        #expect(abs(stored - 1.75 * Self.unit) < 1e-9)
        #expect(typing.spell(typing.shown(stored)) == "1.75")
        #expect(typing.readout(typing.shown(stored)) == "1.75")
    }

    @Test("Width's box takes every weight an icon set uses and stops short of nonsense")
    func widthRange() {
        let typing = Self.lengths.lineWidth
        let range = Self.lengths.strokeWidthRange
        #expect(abs(typing.shown(range.lowerBound) - 0.25) < 1e-9)
        #expect(abs(typing.shown(range.upperBound) - 12) < 1e-9)
    }

    @Test("A length row reaches as far as Width does, so a 2 unit edge never reads 1.88")
    func lengthRowReach() {
        let range: ClosedRange<CGFloat> = 0...40
        let reach = Self.lengths.reach(of: range)
        #expect(reach.lowerBound == 0)
        #expect(reach.upperBound == Self.lengths.strokeWidthRange.upperBound)
        #expect(reach.contains(2 * Self.unit))
        #expect(LengthUnit.point.reach(of: range) == range)
        // A row that already reaches further keeps its own end.
        #expect(Self.lengths.reach(of: 0...1000).upperBound == 1000)
    }

    @Test("A pull on the knob lands on quarters of a unit, and on whole points elsewhere")
    func pull() {
        #expect(abs(Self.lengths.pulled(38) - 1.75 * Self.unit) < 1e-9)
        #expect(LengthUnit.point.pulled(37.6) == 38)
    }

    @Test("The written file says the weight that was typed")
    func writtenFile() {
        let line = Self.pen(width: Self.lengths.typedLength(Self.lengths.lineWidth.slid(1.75)))
        let svg = SVGExport.write(Self.picture(layers: [line]), background: .drop).text
        #expect(svg.contains("stroke-width=\"1.75\""))
    }

    @Test("A 24 unit SVG's 1.75 line reads 1.75, not 37.33")
    func openedLine() {
        let typing = Self.picture().lengthUnit.lineWidth
        #expect(typing.readout(typing.shown(1.75 * Self.unit)) == "1.75")
    }

    // MARK: Position and size

    @Test("X, Y, W and H read in units, to two places at most")
    func geometryReads() {
        let box = CGRect(x: 9 * Self.unit, y: 4.5 * Self.unit, width: 6 * Self.unit, height: 200)
        let selection = LayerGeometrySelection([Self.member(box)], lengths: Self.lengths)
        #expect(selection.reading(.x).draftText(for: .x) == "9")
        #expect(selection.reading(.y).draftText(for: .y) == "4.5")
        #expect(selection.reading(.width).draftText(for: .width) == "6")
        #expect(selection.reading(.height).draftText(for: .height) == "9.38")
    }

    @Test("A number typed into W lands in units")
    func geometryTyped() throws {
        let id = UUID()
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let selection = LayerGeometrySelection([Self.member(box, id: id)], lengths: Self.lengths)
        let moved = try #require(selection.applying(6, to: .width)[id])
        #expect(abs(moved.width - 6 * Self.unit) < 1e-9)
    }

    @Test("A typed number that landed is not reported as refused")
    func geometryNotRefused() {
        let box = CGRect(x: 0, y: 0, width: 6 * Self.unit, height: 100)
        let selection = LayerGeometrySelection([Self.member(box)], lengths: Self.lengths)
        #expect(selection.refusal(asking: 6, for: .width, landedOn: selection.reading(.width)) == nil)
    }

    @Test("Finishing with the number already showing moves nothing")
    func geometrySameNumber() {
        let box = CGRect(x: 200, y: 0, width: 100, height: 100)
        let selection = LayerGeometrySelection([Self.member(box)], lengths: Self.lengths)
        #expect(selection.applying(9.38, to: .x).isEmpty)
    }

    @Test("An arrow key steps one unit from the number on screen, fraction and all")
    func geometryStep() throws {
        let id = UUID()
        let box = CGRect(x: 1.75 * Self.unit, y: 0, width: 100, height: 100)
        let selection = LayerGeometrySelection([Self.member(box, id: id)], lengths: Self.lengths)
        let up = try #require(selection.stepping(.x, direction: 1, coarse: false)[id])
        #expect(abs(up.minX - 2.75 * Self.unit) < 1e-9)
    }

    @Test("Points go on reading whole, as they always have")
    func geometryInPoints() throws {
        let id = UUID()
        let box = CGRect(x: 295.5, y: 0, width: 100, height: 100)
        let selection = LayerGeometrySelection([Self.member(box, id: id)])
        #expect(selection.reading(.x).draftText(for: .x) == "296")
        let up = try #require(selection.stepping(.x, direction: 1, coarse: false)[id])
        #expect(up.minX == 297)
    }

    // MARK: The pill under a drag

    @Test("The pill reads units on an Icon picture and whole points on any other")
    func pill() {
        let size = DragReadout.Subject.size(CGSize(width: 6 * Self.unit, height: 200))
        #expect(DragReadout.text(size, in: Self.lengths) == "6 × 9.38")
        #expect(DragReadout.text(.position(CGPoint(x: 2.5 * Self.unit, y: 0)), in: Self.lengths) == "2.5, 0")
        #expect(DragReadout.text(.radius(1.5 * Self.unit), in: Self.lengths) == "Radius 1.5")
        #expect(DragReadout.text(.size(CGSize(width: 580.4, height: 448)), in: .point) == "580 × 448")
        #expect(DragReadout.text(.radius(1.5), in: .point) == "Radius 1.5")
    }

    // MARK: Corner radius

    @Test("A radius reads and spells in units, and lands exactly")
    func radius() {
        #expect(Self.lengths.spell(Self.lengths.reading(2 * Self.unit)) == "2")
        #expect(abs(Self.lengths.stored(2) - 2 * Self.unit) < 1e-9)
        #expect(LengthUnit.point.spell(LengthUnit.point.reading(18.4)) == "18")
    }
}
