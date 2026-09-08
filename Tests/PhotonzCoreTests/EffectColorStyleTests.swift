import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// An effect's colour is one of its SETTINGS, and it is a colour like any
/// other.
///
/// Reported by the user on 2026-09-07: a border's colour sat up in the row
/// header beside the tick while its width and position sat in the settings
/// below, so the colour was the only setting in the wrong place — and it was
/// the one colour in the app that could not take a saved name.
///
/// So an effect's colour lives with its other settings, and it binds to a
/// `ColorStyle` exactly the way a fill or an outline does: pick a saved colour
/// and the effect wears the name, edit the name and the effect follows, delete
/// the name and the effect keeps what it is wearing.
///
/// The awkward part, and the reason most of these tests exist: an effect is
/// addressed by its PLACE in the list, and the list moves. Adding, removing and
/// dragging a row all have to carry the bindings with them, or a shadow ends up
/// wearing the border's name.
@Suite("An effect's colour")
struct EffectColorStyleTests {

    private func box(_ effects: [LayerEffect] = []) -> Layer {
        var style = LayerStyle()
        style.effects = effects
        return Layer(name: "Box",
                     content: .annotation(AnnotationContent(shape: .rectangle,
                                                            // A bare box: its edge would be a Border in this very list
                                                     // (`OutlineRetirementTests`), and these are about what
                                                     // somebody ADDS to it.
                                                     strokeWidth: 0,
                                                            colorHex: "#FF0000",
                                                            start: .zero,
                                                            end: CGPoint(x: 100, y: 60))),
                     frame: CGRect(x: 0, y: 0, width: 100, height: 60),
                     style: style)
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        doc.layers = layers
        return doc
    }

    // MARK: One colour, whatever the effect is

    @Test("Every effect that paints a colour answers the same question")
    func oneColourReading() {
        var border = LayerEffect.border(BorderEffect(colorHex: "#112233"))
        var shadow = LayerEffect.shadow(ShadowStyle(colorHex: "#445566"))
        let blur = LayerEffect.blur(BlurEffect())

        #expect(border.colorHex == "#112233")
        #expect(shadow.colorHex == "#445566")
        // A blur has no colour at all, so it has no colour row: the list reads
        // one way and the rows that have nothing to say do not say it blankly.
        #expect(blur.colorHex == nil)

        border.colorHex = "#AABBCC"
        shadow.colorHex = "#DDEEFF"
        #expect(border.border?.colorHex == "#AABBCC")
        #expect(shadow.shadow?.colorHex == "#DDEEFF")
    }

    @Test("A colour that is an effect's is offered the same saved colours as a line")
    func effectColourIsInk() {
        #expect(EffectKind.border.colorSlot == .border)
        #expect(EffectKind.shadow.colorSlot == .shadow)
        #expect(EffectKind.blur.colorSlot == nil)
        // Both are drawn OVER a layer rather than filling an area of the
        // design, so both take the ink shelf. A shadow painted in the colour
        // somebody keeps for hairlines is a normal thing to want.
        #expect(ColorSlot.shadow.styleRole == .ink)
        #expect(ColorSlot.shadow.acceptsGradient == false)
        // No layer HAS a shadow colour among its own slots: it belongs to an
        // entry in the Effects list, not to what the layer is. A phantom
        // Shadow row in the Color section is exactly what this stops.
        #expect(box().colorSlots.contains(.shadow) == false)
    }

    @Test("A layer reads and paints the colour of the effect at a place in its list")
    func layerLevelColour() {
        var layer = box([.blur(BlurEffect()),
                         .border(BorderEffect(colorHex: "#112233"))])
        #expect(layer.colorHex(forEffectAt: 1) == "#112233")
        // The blur has no colour, so asking for one gets nothing rather than a
        // black swatch nobody chose.
        #expect(layer.colorHex(forEffectAt: 0) == nil)
        #expect(layer.colorHex(forEffectAt: 7) == nil)

        layer.setColorHex("#00FF00", forEffectAt: 1)
        #expect(layer.style.borderEffect(at: 1)?.colorHex == "#00FF00")
    }

    // MARK: Wearing a saved colour

    @Test("A border's colour can wear a saved name, and editing the name repaints it")
    func borderFollowsItsStyle() {
        let layer = box([.border(BorderEffect(colorHex: "#112233"))])
        var doc = document([layer])
        let styleID = doc.addColorStyle(name: "Hairline", colorHex: "#112233")

        #expect(doc.bindColorStyle(layerIDs: [layer.id], effectAt: 0, styleID: styleID) == 1)
        #expect(doc.layer(id: layer.id)?.colorStyleID(forEffectAt: 0) == styleID)

        _ = doc.setColorStyleHex(styleID: styleID, hex: "#FF0000")
        #expect(doc.layer(id: layer.id)?.style.borderEffect(at: 0)?.colorHex == "#FF0000")
        #expect(doc.colorStyleUsageCount(id: styleID) == 1)
    }

    @Test("A shadow's colour wears a name the same way, so the list reads one way")
    func shadowFollowsItsStyle() {
        let layer = box([.shadow(ShadowStyle(colorHex: "#112233"))])
        var doc = document([layer])
        let styleID = doc.addColorStyle(name: "Hairline", colorHex: "#112233")

        #expect(doc.bindColorStyle(layerIDs: [layer.id], effectAt: 0, styleID: styleID) == 1)
        _ = doc.setColorStyleHex(styleID: styleID, hex: "#00FF00")
        #expect(doc.layer(id: layer.id)?.style.shadow(at: 0)?.colorHex == "#00FF00")
    }

    @Test("Saving an effect's colour keeps it under a name and points the effect at it")
    func savingFromAnEffect() {
        let layer = box([.border(BorderEffect(colorHex: "#334455"))])
        var doc = document([layer])

        let styleID = doc.saveColorStyle(from: [layer.id], effectAt: 0, name: "Edge")
        #expect(styleID != nil)
        #expect(doc.colorStyle(id: styleID!)?.name == "Edge")
        // Saved FROM a ring, so it is offered ON rings and lines rather than as
        // something to fill a box with.
        #expect(doc.colorStyle(id: styleID!)?.roles == [.ink])
        #expect(doc.layer(id: layer.id)?.colorStyleID(forEffectAt: 0) == styleID)
    }

    @Test("Painting an effect's colour by hand takes it off the name")
    func paintingLetsGo() {
        let layer = box([.border(BorderEffect(colorHex: "#112233"))])
        var doc = document([layer])
        let styleID = doc.addColorStyle(name: "Hairline", colorHex: "#112233")
        _ = doc.bindColorStyle(layerIDs: [layer.id], effectAt: 0, styleID: styleID)

        #expect(doc.setColorHex(layerIDs: [layer.id], effectAt: 0, hex: "#00FF00") == 1)
        #expect(doc.layer(id: layer.id)?.colorStyleID(forEffectAt: 0) == nil)
        #expect(doc.layer(id: layer.id)?.style.borderEffect(at: 0)?.colorHex == "#00FF00")
    }

    @Test("Deleting a saved colour leaves the effect wearing exactly what it wore")
    func deletingKeepsThePaint() {
        let layer = box([.border(BorderEffect(colorHex: "#112233"))])
        var doc = document([layer])
        let styleID = doc.addColorStyle(name: "Hairline", colorHex: "#112233")
        _ = doc.bindColorStyle(layerIDs: [layer.id], effectAt: 0, styleID: styleID)

        doc.deleteColorStyle(id: styleID)
        #expect(doc.layer(id: layer.id)?.style.borderEffect(at: 0)?.colorHex == "#112233")
        #expect(doc.layer(id: layer.id)?.colorStyleID(forEffectAt: 0) == nil)
    }

    @Test("A claim that has drifted lets go on its own")
    func reconcileBreaksADriftedClaim() {
        let layer = box([.border(BorderEffect(colorHex: "#112233"))])
        var doc = document([layer])
        let styleID = doc.addColorStyle(name: "Hairline", colorHex: "#112233")
        _ = doc.bindColorStyle(layerIDs: [layer.id], effectAt: 0, styleID: styleID)

        // Painted some other way — a paste, a tool default — so the claim
        // "this came from Hairline" is now false.
        doc.updateLayer(id: layer.id) { $0.style.updateBorderEffect(at: 0) { $0.colorHex = "#000000" } }
        #expect(doc.reconcileColorStyles() == 1)
        #expect(doc.layer(id: layer.id)?.colorStyleID(forEffectAt: 0) == nil)
        #expect(doc.layer(id: layer.id)?.style.borderEffect(at: 0)?.colorHex == "#000000")
    }

    // MARK: The list moves, and the names have to move with it

    @Test("Removing an effect takes its name with it and shifts the ones below")
    func removingKeepsBindingsStraight() {
        let layer = box([.shadow(ShadowStyle(colorHex: "#111111")),
                         .border(BorderEffect(colorHex: "#222222"))])
        var doc = document([layer])
        let one = doc.addColorStyle(name: "One", colorHex: "#111111")
        let two = doc.addColorStyle(name: "Two", colorHex: "#222222")
        _ = doc.bindColorStyle(layerIDs: [layer.id], effectAt: 0, styleID: one)
        _ = doc.bindColorStyle(layerIDs: [layer.id], effectAt: 1, styleID: two)

        _ = doc.removeEffect(layerIDs: [layer.id], at: 0)
        // The border moved up into place 0, so its name came with it. Without
        // this the border would be wearing the shadow's name.
        #expect(doc.layer(id: layer.id)?.colorStyleID(forEffectAt: 0) == two)
        #expect(doc.colorStyleUsageCount(id: one) == 0)
    }

    @Test("Dragging a row up or down carries its name")
    func movingCarriesBindings() {
        let layer = box([.shadow(ShadowStyle(colorHex: "#111111")),
                         .border(BorderEffect(colorHex: "#222222"))])
        var doc = document([layer])
        let one = doc.addColorStyle(name: "One", colorHex: "#111111")
        let two = doc.addColorStyle(name: "Two", colorHex: "#222222")
        _ = doc.bindColorStyle(layerIDs: [layer.id], effectAt: 0, styleID: one)
        _ = doc.bindColorStyle(layerIDs: [layer.id], effectAt: 1, styleID: two)

        _ = doc.moveEffect(layerIDs: [layer.id], from: 1, to: 0)
        #expect(doc.layer(id: layer.id)?.colorStyleID(forEffectAt: 0) == two)
        #expect(doc.layer(id: layer.id)?.colorStyleID(forEffectAt: 1) == one)
    }

    @Test("Adding a pinned effect at the top pushes every name down with its row")
    func addingShiftsBindings() {
        let layer = box([.shadow(ShadowStyle(colorHex: "#111111"))])
        var doc = document([layer])
        let one = doc.addColorStyle(name: "One", colorHex: "#111111")
        _ = doc.bindColorStyle(layerIDs: [layer.id], effectAt: 0, styleID: one)

        // A blur is pinned to the top, so the shadow becomes entry 1.
        _ = doc.addEffect(.blur, layerIDs: [layer.id])
        #expect(doc.layer(id: layer.id)?.style.effect(at: 0)?.kind == .blur)
        #expect(doc.layer(id: layer.id)?.colorStyleID(forEffectAt: 1) == one)
        #expect(doc.layer(id: layer.id)?.colorStyleID(forEffectAt: 0) == nil)
    }

    // MARK: What the row reads over a selection

    @Test("The row reads one name over two layers wearing it, and Mixed when they differ")
    func selectionReading() {
        let a = box([.border(BorderEffect(colorHex: "#112233"))])
        let b = box([.border(BorderEffect(colorHex: "#112233"))])
        var doc = document([a, b])
        let styleID = doc.addColorStyle(name: "Hairline", colorHex: "#112233")

        _ = doc.bindColorStyle(layerIDs: [a.id, b.id], effectAt: 0, styleID: styleID)
        #expect(doc.colorStyleSelection(layerIDs: [a.id, b.id], effectAt: 0).reading
                == .style(styleID))

        _ = doc.setColorHex(layerIDs: [b.id], effectAt: 0, hex: "#00FF00")
        #expect(doc.colorStyleSelection(layerIDs: [a.id, b.id], effectAt: 0).reading == .mixed)
    }

    @Test("A row over a layer with no effect there simply does not reach it")
    func rowSkipsALayerWithNothingThere() {
        let a = box([.border(BorderEffect(colorHex: "#112233"))])
        let b = box()
        let doc = document([a, b])
        let selection = doc.colorStyleSelection(layerIDs: [a.id, b.id], effectAt: 0)
        #expect(selection.layerIDs == [a.id])
        #expect(selection.selectionCount == 2)
    }

    @Test("A blur brings no colour row at all")
    func blurHasNoColourRow() {
        let layer = box([.blur(BlurEffect())])
        let doc = document([layer])
        #expect(doc.colorStyleSelection(layerIDs: [layer.id], effectAt: 0).isEmpty)
    }

    @Test("A locked layer is left alone, exactly as every other colour row leaves it")
    func lockedLayerSitsOut() {
        var layer = box([.border(BorderEffect(colorHex: "#112233"))])
        layer.isLocked = true
        var doc = document([layer])
        #expect(doc.colorStyleSelection(layerIDs: [layer.id], effectAt: 0).isEmpty)
        #expect(doc.setColorHex(layerIDs: [layer.id], effectAt: 0, hex: "#00FF00") == 0)
    }

    // MARK: The file

    @Test("A name on an effect's colour survives a save and an open")
    func roundTrip() throws {
        let layer = box([.border(BorderEffect(colorHex: "#112233"))])
        var doc = document([layer])
        let styleID = doc.addColorStyle(name: "Hairline", colorHex: "#112233")
        _ = doc.bindColorStyle(layerIDs: [layer.id], effectAt: 0, styleID: styleID)

        let data = try JSONEncoder().encode(doc)
        let reopened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(reopened.layer(id: layer.id)?.colorStyleID(forEffectAt: 0) == styleID)
    }

    @Test("A layer wearing only slot colours writes exactly what it always wrote")
    func oldFilesAreUntouched() throws {
        var layer = box()
        layer.bindColorStyle(UUID(), for: .fill)
        let data = try JSONEncoder().encode(layer.colorStyleBindings)
        let text = String(decoding: data, as: UTF8.self)
        // No place-in-the-list key on a binding that is not an effect's, so a
        // document that has never met an effect colour reads the same as ever.
        #expect(!text.contains("effectIndex"))
    }
}
