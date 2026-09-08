import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The Outline row leaves Appearance, and a layer's edge becomes a Border in
/// the Effects list.
///
/// Reported by the user on 2026-09-07 and again on 2026-09-08: Border became
/// something you ADD in Effects, but the old Outline row stayed in Appearance,
/// so there were two ways to draw a line round a shape and no way to tell which
/// one you were looking at. The answer they picked on the decision card was
/// "shapes arrive with their edge already listed": a box still comes out of the
/// rectangle tool with a line round it, and that line is a Border you can
/// retune, reorder or take off with the cross.
///
/// Two edges existed underneath, drawn two different ways:
///
/// * a **shape's own stroke** (`AnnotationContent.strokeWidth`), which a
///   rectangle and an ellipse wore, and
/// * a **layer ring** (`LayerStyle.borderWidth`), which everything else —
///   a picture, a label, a frame, a group, a highlight — wore.
///
/// Both become `BorderEffect`s, and neither can be reached any other way.
@Suite("Outline retirement")
struct OutlineRetirementTests {

    private func rows(for layers: [Layer]) -> [LayerPartRow] {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        doc.layers = layers
        return doc.layerPartRows(layerIDs: layers.map(\.id))
    }

    private func rectangle(strokeWidth: CGFloat = 4,
                           colorHex: String = "#FF0000",
                           position: BorderPosition = .inside,
                           style: LayerStyle = LayerStyle()) -> Layer {
        var content = AnnotationContent(shape: .rectangle,
                                        strokeWidth: strokeWidth,
                                        colorHex: colorHex,
                                        start: .zero,
                                        end: CGPoint(x: 100, y: 60))
        content.strokePosition = position
        return Layer(name: "Box", content: .annotation(content),
                     frame: CGRect(x: 0, y: 0, width: 100, height: 60), style: style)
    }

    // MARK: - A layer ring becomes a border in the list

    @Test("A style built with a border width carries it as a Border effect")
    func aRingIsAnEffect() {
        let style = LayerStyle(borderWidth: 6, borderColorHex: "#00FF00")
        #expect(style.borderEffects.count == 1)
        #expect(style.borderEffects.first?.width == 6)
        #expect(style.borderEffects.first?.colorHex == "#00FF00")
        // Inside is where every ring drawn before there was a choice sat, so
        // it is where one built the old way still sits.
        #expect(style.borderEffects.first?.position == .inside)
    }

    @Test("The old border accessors read and write that entry")
    func theOldAccessorsStillWork() {
        var style = LayerStyle()
        #expect(style.borderWidth == 0)
        style.borderWidth = 3
        style.borderColorHex = "#123456"
        #expect(style.borderEffects.count == 1)
        #expect(style.borderWidth == 3)
        #expect(style.borderColorHex == "#123456")
        style.borderPosition = .outside
        #expect(style.borderEffects.first?.position == .outside)
        // Setting it back to nought leaves the entry there, exactly as taking a
        // slider to nought always has: the row stays and the colour with it.
        style.borderWidth = 0
        #expect(style.borderEffects.count == 1)
        #expect(style.borderColorHex == "#123456")
    }

    @Test("A switched-off border reads as no width, the way a blur does")
    func offReadsAsNothing() {
        var style = LayerStyle(borderWidth: 4)
        style.effects[0].isOn = false
        #expect(style.borderWidth == 0)
    }

    // MARK: - Opening a document saved with an outline

    @Test("A document saved with a layer ring opens with it as a Border")
    func aSavedRingOpensAsABorder() throws {
        let json = """
        {"opacity":1,"cornerRadius":0,"borderWidth":5,"borderColorHex":"#2B5BFF"}
        """
        let style = try JSONDecoder().decode(LayerStyle.self, from: Data(json.utf8))
        #expect(style.borderEffects.count == 1)
        #expect(style.borderEffects.first?.width == 5)
        #expect(style.borderEffects.first?.colorHex == "#2B5BFF")
        #expect(style.borderEffects.first?.position == .inside)
    }

    @Test("The ring lands under the borders somebody added, where it painted")
    func theRingLandsUnderAddedBorders() throws {
        let json = """
        {"opacity":1,"borderWidth":5,"borderColorHex":"#2B5BFF",
         "effects":[{"kind":"border","border":{"width":2,"colorHex":"#000000",
         "position":"outside","isOn":true}}]}
        """
        let style = try JSONDecoder().decode(LayerStyle.self, from: Data(json.utf8))
        // The list paints from the foot up, so the entry that used to be
        // painted FIRST — the layer's own ring — has to end up last.
        #expect(style.borderEffects.count == 2)
        #expect(style.borderEffects.first?.width == 2)
        #expect(style.borderEffects.last?.width == 5)
    }

    @Test("A document saved since the retirement does not grow a second ring")
    func noDoubleConversion() throws {
        var style = LayerStyle(borderWidth: 5, borderColorHex: "#2B5BFF")
        let data = try JSONEncoder().encode(style)
        style = try JSONDecoder().decode(LayerStyle.self, from: data)
        #expect(style.borderEffects.count == 1)
        #expect(style.borderEffects.first?.width == 5)
    }

    @Test("A file written today still shows its edge in a build from yesterday")
    func theOldKeysAreStillWritten() throws {
        let style = LayerStyle(borderWidth: 5, borderColorHex: "#2B5BFF")
        let data = try JSONEncoder().encode(style)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["borderWidth"] as? CGFloat == 5)
        #expect(json["borderColorHex"] as? String == "#2B5BFF")
    }

    // MARK: - A shape's own stroke becomes a border too

    @Test("A rectangle's outline arrives as a Border and leaves its stroke")
    func aRectangleStrokeBecomesABorder() {
        let migrated = rectangle().retiringItsOutline()
        #expect(migrated.annotation?.strokeWidth == 0)
        #expect(migrated.style.borderEffects.count == 1)
        let border = migrated.style.borderEffects[0]
        #expect(border.width == 4)
        #expect(border.colorHex == "#FF0000")
        #expect(border.position == .inside)
    }

    @Test("Where the stroke sat is where the border sits")
    func thePositionComesWithIt() {
        let migrated = rectangle(position: .outside).retiringItsOutline()
        #expect(migrated.style.borderEffects.first?.position == .outside)
    }

    @Test("A gradient outline stays a gradient")
    func aGradientOutlineSurvives() {
        var content = AnnotationContent(shape: .ellipse, strokeWidth: 6,
                                        colorHex: "#FF0000",
                                        start: .zero, end: CGPoint(x: 80, y: 80))
        content.paint = Paint(hex: "#FF0000", kind: .linear,
                              stops: [GradientStop(hex: "#FF0000", position: 0),
                                      GradientStop(hex: "#0000FF", position: 1)])
        let layer = Layer(name: "Oval", content: .annotation(content),
                          frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        let border = try? #require(layer.retiringItsOutline().style.borderEffects.first)
        #expect(border?.paint.isGradient == true)
        #expect(border?.paint.stops.count == 2)
    }

    @Test("A line and an arrow keep their stroke, because they ARE it")
    func aLineKeepsItsStroke() {
        for shape in [AnnotationShape.line, .arrow] {
            let layer = Layer(name: "Line",
                              content: .annotation(AnnotationContent(shape: shape,
                                                                     strokeWidth: 4,
                                                                     colorHex: "#FF0000",
                                                                     start: .zero,
                                                                     end: CGPoint(x: 50, y: 0))),
                              frame: CGRect(x: 0, y: 0, width: 50, height: 4))
            let migrated = layer.retiringItsOutline()
            #expect(migrated.annotation?.strokeWidth == 4)
            #expect(migrated.style.borderEffects.isEmpty)
        }
    }

    @Test("A highlight keeps its wash")
    func aHighlightKeepsItsWash() {
        let layer = Layer(name: "Highlight",
                          content: .annotation(AnnotationContent(shape: .highlight,
                                                                 strokeWidth: 4,
                                                                 colorHex: "#FFD60A",
                                                                 start: .zero,
                                                                 end: CGPoint(x: 50, y: 20))),
                          frame: CGRect(x: 0, y: 0, width: 50, height: 20))
        let migrated = layer.retiringItsOutline()
        #expect(migrated.annotation?.strokeWidth == 4)
        #expect(migrated.style.borderEffects.isEmpty)
    }

    @Test("A box wearing both rings keeps both, in the order they painted")
    func bothRingsSurvive() {
        let layer = rectangle(strokeWidth: 4, colorHex: "#FF0000",
                              style: LayerStyle(borderWidth: 6, borderColorHex: "#00FF00"))
        let borders = layer.retiringItsOutline().style.borderEffects
        // Bottom to top the canvas showed: the shape's stroke, then the layer
        // ring over it. The list reads top first, so the ring comes first.
        #expect(borders.count == 2)
        #expect(borders[0].colorHex == "#00FF00")
        #expect(borders[1].colorHex == "#FF0000")
    }

    @Test("A shape inside a group is reached too")
    func groupsAreWalked() {
        let child = rectangle()
        let group = Layer(name: "Group",
                          content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 60))
        let migrated = group.retiringItsOutline()
        let inner = try? #require(migrated.group?.children.first)
        #expect(inner?.annotation?.strokeWidth == 0)
        #expect(inner?.style.borderEffects.count == 1)
    }

    @Test("Opening a document walks every layer")
    func openingADocumentMigrates() throws {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200))
        // Written the old way, on purpose: a shape whose stroke is its edge.
        doc.layers = [rectangle()]
        let data = try JSONEncoder().encode(doc)
        let opened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(opened.layers[0].annotation?.strokeWidth == 0)
        #expect(opened.layers[0].style.borderEffects.first?.width == 4)
        #expect(opened.layers[0].style.borderEffects.first?.colorHex == "#FF0000")
    }

    @Test("A document already retired is left alone")
    func retiringTwiceChangesNothing() {
        let once = rectangle().retiringItsOutline()
        let twice = once.retiringItsOutline()
        #expect(twice.style.borderEffects.count == 1)
        #expect(twice == once)
    }

    // MARK: - What a freshly drawn shape arrives with

    @Test("A new rectangle arrives with its edge in the Effects list")
    func aNewRectangleArrivesWithABorder() {
        let styles = AnnotationStyles()
        let content = try? #require(styles.content(for: .rectangle))
        #expect(content?.strokeWidth == 0)
        let style = styles.arrivingStyle(forShape: .rectangle)
        #expect(style.borderEffects.count == 1)
        #expect(style.borderEffects.first?.width == AnnotationContent.defaultStrokeWidth)
        #expect(style.borderEffects.first?.colorHex == ShapeDefaults.standard(for: .rectangle).colorHex)
    }

    @Test("A new arrow arrives with no border at all")
    func aNewArrowHasNoBorder() {
        let styles = AnnotationStyles()
        let content = try? #require(styles.content(for: .arrow))
        #expect(content?.strokeWidth == AnnotationContent.defaultStrokeWidth)
        #expect(styles.arrivingStyle(forShape: .arrow).borderEffects.isEmpty)
    }

    // MARK: - The row is gone

    @Test("Appearance no longer offers an Outline row")
    func noOutlineRow() {
        let box = rectangle().retiringItsOutline()
        #expect(!rows(for: [box]).contains { $0.title == "Outline" })
    }

    @Test("A box does not grow a stray Stroke row in its place")
    func noStrayStrokeRow() {
        let box = rectangle().retiringItsOutline()
        #expect(rows(for: [box]).map(\.title) == ["Fill"])
    }

    @Test("An arrow still says what it is drawn in")
    func anArrowKeepsItsInkRow() {
        let arrow = Layer(name: "Arrow",
                          content: .annotation(AnnotationContent(shape: .arrow,
                                                                 strokeWidth: 4,
                                                                 colorHex: "#FF0000",
                                                                 start: .zero,
                                                                 end: CGPoint(x: 50, y: 0))),
                          frame: CGRect(x: 0, y: 0, width: 50, height: 4))
        #expect(rows(for: [arrow]).map(\.title) == [ColorSlot.stroke.title])
    }
}
