import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The tool in your hand can hold a SAVED colour, not just a copy of one.
///
/// Pointing a shape at Accent used to leave the tool that drew it on the old
/// colour, so the next shape had to be pointed at Accent all over again —
/// while picking a plain colour on the same row carried over by itself. This
/// closes that gap, and closes it properly: the next shape wears the NAME, so
/// editing Accent later still moves it, rather than a frozen copy of what
/// Accent happened to be.
///
/// The awkward part is that what the tool holds outlives the document. It is a
/// preference, remembered across launches like thickness and corner radius,
/// and a saved colour's identity lives inside ONE document. So the name is
/// resolved against the open document every single time a shape is drawn, and
/// a name this document has never heard of quietly falls back to the plain
/// colour the tool remembers alongside it.
struct ToolColorStyleArmingTests {

    // MARK: - Fixtures

    private func shape(_ kind: AnnotationShape, fill: String? = nil,
                       stroke: String = "#101010") -> Layer {
        var annotation = AnnotationContent(shape: kind, start: .zero,
                                           end: CGPoint(x: 60, y: 30))
        annotation.colorHex = stroke
        if kind == .rectangle || kind == .ellipse { annotation.fillColorHex = fill }
        return Layer(name: "\(kind)", content: .annotation(annotation),
                     frame: CGRect(x: 0, y: 0, width: 60, height: 30))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    /// A drag's worth of new shape, built the way the canvas builds one.
    private func drawn(_ tool: Tool, with styles: AnnotationStyles) -> Layer? {
        guard let content = styles.content(for: tool) else { return nil }
        return AnnotationBuilder.layer(content: content, from: .zero,
                                       to: CGPoint(x: 80, y: 40))
    }

    // MARK: - What a colour row leaves the tool holding

    @Test func pointingABoxAtASavedColourLeavesTheBoxToolHoldingIt() {
        var doc = document([shape(.rectangle, fill: "#3366FF")])
        let accent = doc.addColorStyle(name: "Accent", colorHex: "#B0184A")
        let boxID = doc.layers[0].id
        let bound = doc.bindColorStyle(layerID: boxID, slot: .fill, styleID: accent)
        #expect(bound)

        let arming = doc.toolArming(layerIDs: [boxID], slot: .fill)
        #expect(arming.count == 1)
        #expect(arming[0].styleID == accent)
        #expect(arming[0].paint?.hex == "#B0184A")
    }

    @Test func aPlainColourLeavesTheToolHoldingNoName() {
        var doc = document([shape(.rectangle, fill: "#3366FF")])
        let accent = doc.addColorStyle(name: "Accent", colorHex: "#B0184A")
        let boxID = doc.layers[0].id
        let bound = doc.bindColorStyle(layerID: boxID, slot: .fill, styleID: accent)
        #expect(bound)
        _ = doc.setColorHex(layerIDs: [boxID], slot: .fill, hex: "#22AA55")

        let arming = doc.toolArming(layerIDs: [boxID], slot: .fill)
        #expect(arming.count == 1)
        #expect(arming[0].styleID == nil)
    }

    @Test func shapesWearingDifferentNamesNameNothing() {
        var doc = document([shape(.rectangle, fill: "#3366FF"),
                            shape(.rectangle, fill: "#3366FF")])
        let one = doc.addColorStyle(name: "Accent", colorHex: "#B0184A")
        let two = doc.addColorStyle(name: "Brand", colorHex: "#B0184A")
        let ids = doc.layers.map(\.id)
        let boundOne = doc.bindColorStyle(layerID: ids[0], slot: .fill, styleID: one)
        let boundTwo = doc.bindColorStyle(layerID: ids[1], slot: .fill, styleID: two)
        #expect(boundOne && boundTwo)

        // Both boxes ARE the same colour, so the tool still comes away with it.
        // It just cannot claim a name only half of them wear.
        let arming = doc.toolArming(layerIDs: ids, slot: .fill)
        #expect(arming.count == 1)
        #expect(arming[0].paint?.hex == "#B0184A")
        #expect(arming[0].styleID == nil)
    }

    @Test func onlySomeOfThemWearingItNamesNothing() {
        var doc = document([shape(.rectangle, fill: "#B0184A"),
                            shape(.rectangle, fill: "#B0184A")])
        let accent = doc.addColorStyle(name: "Accent", colorHex: "#B0184A")
        let ids = doc.layers.map(\.id)
        let bound = doc.bindColorStyle(layerID: ids[0], slot: .fill, styleID: accent)
        #expect(bound)

        let arming = doc.toolArming(layerIDs: ids, slot: .fill)
        #expect(arming.count == 1)
        #expect(arming[0].styleID == nil)
    }

    // MARK: - What the tool remembers

    @Test func armingWithANameKeepsBothTheNameAndTheColour() {
        var styles = AnnotationStyles()
        let accent = UUID()
        styles.arm(Paint(hex: "#B0184A"), styleID: accent, slot: .stroke, forShape: .arrow)
        #expect(styles.colorStyleID(forShape: .arrow, slot: .stroke) == accent)
        #expect(styles.paint(forShape: .arrow).hex == "#B0184A")
        // Its own kind only: pointing an arrow at Accent says nothing about lines.
        #expect(styles.colorStyleID(forShape: .line, slot: .stroke) == nil)
    }

    @Test func pickingAPlainColourAfterwardsPutsTheToolBackToAPlainColour() {
        var styles = AnnotationStyles()
        let accent = UUID()
        styles.arm(Paint(hex: "#B0184A"), styleID: accent, slot: .stroke, forShape: .arrow)
        styles.setPaint(Paint(hex: "#22AA55"), forShape: .arrow)
        #expect(styles.colorStyleID(forShape: .arrow, slot: .stroke) == nil)
    }

    @Test func switchingAFillOffLetsGoOfTheNameToo() {
        var styles = AnnotationStyles()
        let accent = UUID()
        styles.arm(Paint(hex: "#B0184A"), styleID: accent, slot: .fill, forShape: .rectangle)
        #expect(styles.colorStyleID(forShape: .rectangle, slot: .fill) == accent)
        styles.setFillPaint(nil, forShape: .rectangle)
        #expect(styles.colorStyleID(forShape: .rectangle, slot: .fill) == nil)
    }

    @Test func armingWithNoNameLetsGoOfTheOneItWasHolding() {
        var styles = AnnotationStyles()
        styles.arm(Paint(hex: "#B0184A"), styleID: UUID(), slot: .stroke, forShape: .arrow)
        styles.arm(Paint(hex: "#22AA55"), slot: .stroke, forShape: .arrow)
        #expect(styles.colorStyleID(forShape: .arrow, slot: .stroke) == nil)
    }

    @Test func whatTheToolHoldsSurvivesALaunch() throws {
        var styles = AnnotationStyles()
        let accent = UUID()
        styles.arm(Paint(hex: "#B0184A"), styleID: accent, slot: .stroke, forShape: .arrow)
        styles.arm(Paint(hex: "#101010"), styleID: UUID(), slot: .fill, forShape: .rectangle)
        let data = try JSONEncoder().encode(styles)
        let read = try JSONDecoder().decode(AnnotationStyles.self, from: data)
        #expect(read.colorStyleID(forShape: .arrow, slot: .stroke) == accent)
        #expect(read == styles)
    }

    @Test func prefsWrittenBeforeAnyOfThisReadBackHoldingNothing() throws {
        // The key simply is not there in prefs from before saved colours could
        // be held, and that has to decode rather than throw.
        let json = """
        {"shapes":{"arrow":{"colorHex":"#FF3B30","strokeWidth":4}}}
        """
        let read = try JSONDecoder().decode(AnnotationStyles.self, from: Data(json.utf8))
        #expect(read.colorStyleID(forShape: .arrow, slot: .stroke) == nil)
        #expect(read.paint(forShape: .arrow).hex == "#FF3B30")
    }

    // MARK: - What the next shape comes out wearing

    @Test func theNextShapeWearsTheNameRatherThanACopyOfIt() throws {
        var doc = document([])
        let accent = doc.addColorStyle(name: "Accent", colorHex: "#B0184A", roles: [.ink])
        var styles = AnnotationStyles()
        styles.arm(Paint(hex: "#B0184A"), styleID: accent, slot: .stroke, forShape: .arrow)

        let plain = try #require(drawn(.arrow, with: styles))
        let worn = doc.wearingArmedColorStyles(plain, styles: styles)
        #expect(worn.colorStyleID(for: .stroke) == accent)
        #expect(worn.paint(for: .stroke)?.hex == "#B0184A")

        // ...and it MOVES when the saved colour is edited later, which is the
        // whole point of holding the name instead of a copy.
        doc.addLayer(worn)
        let moved = doc.setColorStyleHex(styleID: accent, hex: "#0055FF")
        #expect(moved == 1)
        #expect(doc.layer(id: worn.id)?.paint(for: .stroke)?.hex == "#0055FF")
    }

    @Test func theNextShapeTakesWhatTheSavedColourIsNowNotWhatItWas() throws {
        var doc = document([])
        let accent = doc.addColorStyle(name: "Accent", colorHex: "#B0184A", roles: [.ink])
        var styles = AnnotationStyles()
        styles.arm(Paint(hex: "#B0184A"), styleID: accent, slot: .stroke, forShape: .arrow)
        // Accent is repainted while the tool is still holding it.
        _ = doc.setColorStyleHex(styleID: accent, hex: "#0055FF")

        let worn = doc.wearingArmedColorStyles(try #require(drawn(.arrow, with: styles)),
                                               styles: styles)
        #expect(worn.paint(for: .stroke)?.hex == "#0055FF")
        // Which also means the safety net has nothing to break.
        doc.addLayer(worn)
        let broken = doc.reconcileColorStyles()
        #expect(broken == 0)
    }

    @Test func aNameThisDocumentHasNeverHeardOfFallsBackToThePlainColour() throws {
        var doc = document([])
        var styles = AnnotationStyles()
        styles.arm(Paint(hex: "#B0184A"), styleID: UUID(), slot: .stroke, forShape: .arrow)

        let worn = doc.wearingArmedColorStyles(try #require(drawn(.arrow, with: styles)),
                                               styles: styles)
        #expect(worn.colorStyleID(for: .stroke) == nil)
        #expect(worn.paint(for: .stroke)?.hex == "#B0184A")
        doc.addLayer(worn)
        let broken = doc.reconcileColorStyles()
        #expect(broken == 0)
    }

    @Test func aSavedColourNoLongerMeantForThatPartIsNotWorn() throws {
        var doc = document([])
        let hairline = doc.addColorStyle(name: "Hairline", colorHex: "#B0184A", roles: [.ink])
        var styles = AnnotationStyles()
        // Armed on a box's inside back when it was offered there...
        styles.arm(Paint(hex: "#B0184A"), styleID: hairline, slot: .fill, forShape: .rectangle)
        // ...and it is for outlines only now.
        let worn = doc.wearingArmedColorStyles(try #require(drawn(.rectangle, with: styles)),
                                               styles: styles)
        #expect(worn.colorStyleID(for: .fill) == nil)
    }

    @Test func aBoxWithNoInsideIsNotGivenOneByAName() throws {
        var doc = document([])
        let surface = doc.addColorStyle(name: "Surface", colorHex: "#B0184A", roles: [.surface])
        var styles = AnnotationStyles()
        styles.arm(Paint(hex: "#B0184A"), styleID: surface, slot: .fill, forShape: .rectangle)
        // The tool is armed to draw outlines only, whatever it was holding.
        styles.setFillPaint(nil, forShape: .rectangle)
        styles.setColorStyleID(surface, slot: .fill, forShape: .rectangle)

        let worn = doc.wearingArmedColorStyles(try #require(drawn(.rectangle, with: styles)),
                                               styles: styles)
        #expect(worn.paint(for: .fill) == nil)
        #expect(worn.colorStyleID(for: .fill) == nil)
    }

    @Test func aSavedGradientReachesTheNextShapeWhole() throws {
        var doc = document([])
        var ramp = Paint(hex: "#B0184A")
        ramp.becoming(.linear)
        let sunset = doc.addColorStyle(name: "Sunset", paint: ramp, roles: [.surface])
        var styles = AnnotationStyles()
        styles.arm(ramp, styleID: sunset, slot: .fill, forShape: .rectangle)

        let worn = doc.wearingArmedColorStyles(try #require(drawn(.rectangle, with: styles)),
                                               styles: styles)
        #expect(worn.colorStyleID(for: .fill) == sunset)
        #expect(worn.paint(for: .fill)?.isGradient == true)
    }

    @Test func aShapeDrawnHoldingNothingIsUntouched() throws {
        let doc = document([])
        let styles = AnnotationStyles()
        let plain = try #require(drawn(.arrow, with: styles))
        let worn = doc.wearingArmedColorStyles(plain, styles: styles)
        #expect(worn == plain)
    }
}
