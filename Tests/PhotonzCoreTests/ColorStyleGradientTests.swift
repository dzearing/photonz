import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A saved color that is a gradient: kept in the Library under a name, put on
/// another shape whole, and edited in one place.
///
/// The flat-color half of this lives in `ColorStyleTests`; everything here is
/// about the ramp surviving the trip. A gradient somebody spent time aiming is
/// the exact thing worth keeping, and until now it was the one thing a style
/// could not hold.
struct ColorStyleGradientTests {

    // MARK: - Fixtures

    private func sunset() -> Paint {
        Paint(hex: "#FF7A00", kind: .linear,
              stops: [GradientStop(hex: "#FF7A00", position: 0),
                      GradientStop(hex: "#FF2D55", position: 1)],
              angle: 45)
    }

    private func box(_ name: String = "Box", fill: String? = "#3366FF",
                     stroke: String = "#101010") -> Layer {
        var annotation = AnnotationContent(shape: .rectangle, start: .zero,
                                           end: CGPoint(x: 60, y: 30))
        annotation.colorHex = stroke
        annotation.fillColorHex = fill
        return Layer(name: name, content: .annotation(annotation),
                     frame: CGRect(x: 0, y: 0, width: 60, height: 30))
    }

    private func text(_ name: String = "Label", color: String = "#FFFFFF") -> Layer {
        Layer(name: name, content: .text(TextContent(string: "Hi", colorHex: color)),
              frame: CGRect(x: 0, y: 0, width: 40, height: 20))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    // MARK: - Two paints drawing the same thing

    @Test func aSolidIgnoresTheRampItIsNoLongerUsing() {
        var wasGradient = sunset()
        wasGradient.becoming(.solid)
        #expect(wasGradient.draws(sameAs: Paint(hex: "#FF7A00")))
    }

    @Test func hexCaseIsNotADifference() {
        #expect(Paint(hex: "#ff7a00").draws(sameAs: Paint(hex: "#FF7A00")))
    }

    @Test func aMovedStopIsADifference() {
        var moved = sunset()
        moved.stops[1].position = 0.6
        #expect(!moved.draws(sameAs: sunset()))
    }

    @Test func aReaimedRampIsADifference() {
        var turned = sunset()
        turned.angle = 90
        #expect(!turned.draws(sameAs: sunset()))
    }

    @Test func aGradientNeverDrawsLikeTheFlatColorItStandsFor() {
        #expect(!sunset().draws(sameAs: Paint(hex: "#FF7A00")))
    }

    // MARK: - Saving one

    @Test func savingAFillKeepsTheWholeRamp() {
        var doc = document([box()])
        doc.updateLayer(id: doc.layers[0].id) { $0.setPaint(sunset(), for: .fill) }
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Sunset")!
        #expect(doc.colorStyle(id: id)?.paint.draws(sameAs: sunset()) == true)
        #expect(doc.colorStyle(id: id)?.paint.isGradient == true)
    }

    @Test func aSavedGradientStillHasAFlatColorForEverythingThatCanOnlyDrawOne() {
        var doc = document([box()])
        doc.updateLayer(id: doc.layers[0].id) { $0.setPaint(sunset(), for: .fill) }
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Sunset")!
        #expect(doc.colorStyle(id: id)?.colorHex == "#FF7A00")
    }

    @Test func layersWithDifferentRampsHaveNothingToSave() {
        var doc = document([box("A"), box("B")])
        doc.updateLayer(id: doc.layers[0].id) { $0.setPaint(sunset(), for: .fill) }
        var other = sunset()
        other.angle = 300
        doc.updateLayer(id: doc.layers[1].id) { $0.setPaint(other, for: .fill) }
        let ids = doc.layers.map(\.id)
        #expect(doc.colorStyleSelection(layerIDs: ids, slot: .fill).reading == .mixed)
        #expect(doc.saveColorStyle(from: ids, slot: .fill, name: "Sunset") == nil)
    }

    @Test func layersWearingTheSameRampAgree() {
        var doc = document([box("A"), box("B")])
        for id in doc.layers.map(\.id) {
            doc.updateLayer(id: id) { $0.setPaint(sunset(), for: .fill) }
        }
        let selection = doc.colorStyleSelection(layerIDs: doc.layers.map(\.id), slot: .fill)
        #expect(selection.savablePaint?.draws(sameAs: sunset()) == true)
    }

    @Test func aSavedRampIsCalledGradientRatherThanColor() {
        var doc = document([box()])
        let id = doc.addColorStyle(paint: sunset(), roles: [.surface])
        #expect(doc.colorStyle(id: id)?.name == "Gradient")
    }

    // MARK: - Putting it on something else

    @Test func applyingASavedGradientPaintsTheWholeRampAndItsAim() {
        var doc = document([box("A"), box("B")])
        doc.updateLayer(id: doc.layers[0].id) { $0.setPaint(sunset(), for: .fill) }
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Sunset")!
        let bound = doc.bindColorStyle(layerID: doc.layers[1].id, slot: .fill, styleID: id)
        #expect(bound)
        #expect(doc.layers[1].paint(for: .fill)?.draws(sameAs: sunset()) == true)
        #expect(doc.layers[1].colorStyleID(for: .fill) == id)
    }

    @Test func aGradientIsNotOfferedWhereNoRampCanBeDrawn() {
        var doc = document([box(), text()])
        doc.updateLayer(id: doc.layers[0].id) { $0.setPaint(sunset(), for: .stroke) }
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .stroke, name: "Sunset")!
        #expect(doc.colorStyles(for: .stroke).map(\.id).contains(id))
        #expect(!doc.colorStyles(for: .text).map(\.id).contains(id))
        #expect(!doc.colorStyles(for: .border).map(\.id).contains(id))
    }

    @Test func aFlatSlotWearingAGradientStyleTakesItsFlatColor() {
        var doc = document([text()])
        let id = doc.addColorStyle(name: "Sunset", paint: sunset(), roles: [.ink])
        let bound = doc.bindColorStyle(layerID: doc.layers[0].id, slot: .text, styleID: id)
        #expect(bound)
        #expect(doc.layers[0].colorHex(for: .text) == "#FF7A00")
        #expect(doc.reconcileColorStyles() == 0)
        #expect(doc.layers[0].colorStyleID(for: .text) == id)
    }

    // MARK: - Editing one

    @Test func editingASavedGradientRepaintsEverythingWearingIt() {
        var doc = document([box("A"), box("B")])
        doc.updateLayer(id: doc.layers[0].id) { $0.setPaint(sunset(), for: .fill) }
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Sunset")!
        _ = doc.bindColorStyle(layerID: doc.layers[1].id, slot: .fill, styleID: id)
        var cooler = sunset()
        cooler.stops[1].hex = "#5856D6"
        cooler.angle = 200
        #expect(doc.setColorStylePaint(styleID: id, paint: cooler) == 2)
        for layer in doc.layers {
            #expect(layer.paint(for: .fill)?.draws(sameAs: cooler) == true)
        }
        #expect(doc.reconcileColorStyles() == 0)
    }

    @Test func aStyleCanBeTurnedFromAFlatColorIntoAGradient() {
        var doc = document([box()])
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Card")!
        #expect(doc.setColorStylePaint(styleID: id, paint: sunset()) == 1)
        #expect(doc.layers[0].paint(for: .fill)?.isGradient == true)
        #expect(doc.reconcileColorStyles() == 0)
    }

    @Test func aStyleCanBeFlattenedBackToOneColor() {
        var doc = document([box()])
        doc.updateLayer(id: doc.layers[0].id) { $0.setPaint(sunset(), for: .fill) }
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Sunset")!
        #expect(doc.setColorStyleHex(styleID: id, hex: "#00A870") == 1)
        #expect(doc.layers[0].paint(for: .fill)?.isGradient == false)
        #expect(doc.layers[0].colorHex(for: .fill) == "#00A870")
        #expect(doc.reconcileColorStyles() == 0)
    }

    // MARK: - The binding stays honest

    @Test func movingAStopOnTheLayerLetsGoOfTheStyle() {
        var doc = document([box()])
        doc.updateLayer(id: doc.layers[0].id) { $0.setPaint(sunset(), for: .fill) }
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Sunset")!
        #expect(doc.layers[0].colorStyleID(for: .fill) == id)
        // The flat color is untouched, so only a paint-deep check catches this.
        doc.updateLayer(id: doc.layers[0].id) {
            var paint = $0.paint(for: .fill)!
            paint.stops[1].hex = "#00FF00"
            $0.setPaint(paint, for: .fill)
        }
        #expect(doc.reconcileColorStyles() == 1)
        #expect(doc.layers[0].colorStyleID(for: .fill) == nil)
        #expect(doc.layers[0].paint(for: .fill)?.isGradient == true)
    }

    @Test func reaimingAGradientOnTheLayerLetsGoOfTheStyle() {
        var doc = document([box()])
        doc.updateLayer(id: doc.layers[0].id) { $0.setPaint(sunset(), for: .fill) }
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Sunset")!
        doc.updateLayer(id: doc.layers[0].id) {
            var paint = $0.paint(for: .fill)!
            paint.angle = 12
            $0.setPaint(paint, for: .fill)
        }
        #expect(doc.reconcileColorStyles() == 1)
        _ = id
    }

    @Test func aFlatStyleSurvivesALayerThatUsedToBeAGradient() {
        // A paint keeps its stops while it is solid, so a plain hex comparison
        // is not the same question as "does it draw the same".
        var doc = document([box()])
        var wasGradient = sunset()
        wasGradient.becoming(.solid)
        doc.updateLayer(id: doc.layers[0].id) { $0.setPaint(wasGradient, for: .fill) }
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Flat")!
        #expect(doc.reconcileColorStyles() == 0)
        #expect(doc.layers[0].colorStyleID(for: .fill) == id)
    }

    // MARK: - On disk

    @Test func aFlatStyleWritesTheBareStringItAlwaysWrote() throws {
        let style = ColorStyle(name: "Card", colorHex: "#FFFFFF", roles: [.surface])
        let json = try JSONEncoder().encode(style)
        let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["colorHex"] as? String == "#FFFFFF")
    }

    @Test func aGradientStyleReadsBackWhole() throws {
        let style = ColorStyle(name: "Sunset", paint: sunset(), roles: [.surface])
        let json = try JSONEncoder().encode(style)
        let read = try JSONDecoder().decode(ColorStyle.self, from: json)
        #expect(read.paint.draws(sameAs: sunset()))
        #expect(read.name == "Sunset")
    }

    @Test func aStyleSavedBeforeGradientsExistedStillOpens() throws {
        let json = Data("""
            {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","name":"Accent","colorHex":"#3B7DF5"}
            """.utf8)
        let read = try JSONDecoder().decode(ColorStyle.self, from: json)
        #expect(read.colorHex == "#3B7DF5")
        #expect(!read.paint.isGradient)
    }
}

/// The few words the shelf and its buttons have room for.
struct ColorStyleGradientNamingTests {

    @Test func aFlatStyleIsStillDescribedByItsHex() {
        #expect(ColorStyleNaming.paintText(Paint(hex: "#FF7A00")) == "#FF7A00")
        #expect(ColorStyleNaming.subject(Paint(hex: "#FF7A00")) == "color")
    }

    @Test func aRampIsDescribedByTheKindOfRampItIs() {
        let paint = Paint(hex: "#FF7A00", kind: .radial,
                          stops: [GradientStop(hex: "#FF7A00", position: 0),
                                  GradientStop(hex: "#FF2D55", position: 1)])
        #expect(ColorStyleNaming.paintText(paint) == "Radial gradient")
        #expect(ColorStyleNaming.subject(paint) == "gradient")
    }
}

/// The Style section's own words, which have to stop saying Color the moment
/// the thing beside them is a ramp.
struct ColorStyleGradientSectionTests {

    private func ramp() -> Paint {
        Paint(hex: "#FF7A00", kind: .linear,
              stops: [GradientStop(hex: "#FF7A00", position: 0),
                      GradientStop(hex: "#FF2D55", position: 1)])
    }

    @Test func aFlatStyleStillCallsItsRowColor() {
        #expect(ColorStyleNaming.rowTitle(Paint(hex: "#FF7A00")) == "Color")
        #expect(ColorStyleNaming.gradientReachNote(Paint(hex: "#FF7A00")) == nil)
    }

    @Test func aRampCallsItsRowGradientAndSaysWhereItCannotGo() {
        #expect(ColorStyleNaming.rowTitle(ramp()) == "Gradient")
        #expect(ColorStyleNaming.gradientReachNote(ramp())?.contains("Text and borders") == true)
    }
}
