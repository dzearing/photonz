import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The color of a layer's border, as one of the colors that live in the Color
/// section rather than a swatch of its own buried in the effects.
///
/// A border is not part of what a layer IS — it is styling laid over whatever
/// the layer happens to be — so every kind of layer can have one, and the row
/// turns up exactly when there is a border to paint.
struct BorderColorSlotTests {

    // MARK: - Fixtures

    private func box(_ name: String = "Box", border: CGFloat = 0,
                     borderHex: String = "#101010") -> Layer {
        var annotation = AnnotationContent(shape: .rectangle, start: .zero,
                                           end: CGPoint(x: 60, y: 30))
        annotation.colorHex = "#202020"
        annotation.fillColorHex = "#3366FF"
        var layer = Layer(name: name, content: .annotation(annotation),
                          frame: CGRect(x: 0, y: 0, width: 60, height: 30))
        layer.style = LayerStyle(borderWidth: border, borderColorHex: borderHex)
        return layer
    }

    private func picture(_ name: String = "Shot", border: CGFloat = 0) -> Layer {
        var layer = Layer(name: name, content: .image(ImageRef(id: UUID(), pixelSize: .zero)),
                          frame: CGRect(x: 0, y: 0, width: 80, height: 60))
        layer.style = LayerStyle(borderWidth: border, borderColorHex: "#445566")
        return layer
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    // MARK: - When a layer has a border color at all

    @Test func aBoxWithNoBorderHasNoBorderColor() {
        let plain = box()
        #expect(plain.colorSlots.contains(.border) == false)
        #expect(plain.colorHex(for: .border) == nil)
    }

    @Test func givingABoxABorderGivesItABorderColor() {
        let bordered = box(border: 3, borderHex: "#FF3B30")
        #expect(bordered.colorSlots == [.fill, .stroke, .border])
        #expect(bordered.colorHex(for: .border) == "#FF3B30")
    }

    /// A border is styling rather than content, so a picture can wear one, and
    /// then its color is the only one it has.
    @Test func aPictureWithABorderHasOneColorAndItIsTheBorder() {
        #expect(picture().colorSlots.isEmpty)
        #expect(picture(border: 2).colorSlots == [.border])
    }

    /// Border is the last row, under the colors that say what the layer is.
    @Test func theBorderRowComesAfterTheColorsTheLayerItselfHas() {
        #expect(ColorSlot.allCases == [.fill, .stroke, .text, .border])
    }

    /// A border is ink: an outline color saved off one is offered on the next,
    /// and never as something to fill a box with.
    @Test func aBorderTakesTheSameSavedColorsAnOutlineDoes() {
        #expect(ColorSlot.border.styleRole == .ink)
    }

    /// The way back to a border is its width in the Effects section, so the
    /// row carries no checkbox of its own.
    @Test func theBorderRowHasNoOnOffCheckbox() {
        #expect(ColorSlot.border.isSwitchable == false)
        #expect(ColorSlot.border.selectionTitle == "Border")
    }

    // MARK: - The row over a selection

    @Test func theRowIsThereOnlyOnceSomethingPickedHasABorder() {
        let plain = box("Plain")
        let bordered = box("Bordered", border: 4)
        let doc = document([plain, bordered])
        #expect(doc.colorRowSlots(layerIDs: [plain.id]).contains(.border) == false)
        #expect(doc.colorRowSlots(layerIDs: [plain.id, bordered.id]) == [.fill, .stroke, .border])
    }

    /// It paints every bordered layer picked, in one step, and stays quiet
    /// about the one with no border: a box without a border has no border
    /// color at all, the way a text block has no fill, and a row announcing
    /// that would be small print on any mixed selection.
    @Test func oneColorPaintsEveryBorderPicked() {
        let a = box("A", border: 3, borderHex: "#111111")
        let b = box("B", border: 5, borderHex: "#222222")
        let c = box("C")
        var doc = document([a, b, c])
        let ids = [a.id, b.id, c.id]
        #expect(doc.colorStyleSelection(layerIDs: ids, slot: .border).reading == .mixed)
        #expect(doc.setColorHex(layerIDs: ids, slot: .border, hex: "#FF3B30") == 2)
        #expect(doc.layer(id: a.id)?.style.borderColorHex == "#FF3B30")
        #expect(doc.layer(id: b.id)?.style.borderColorHex == "#FF3B30")
        #expect(doc.layer(id: c.id)?.style.borderColorHex == "#101010")
        let after = doc.colorStyleSelection(layerIDs: ids, slot: .border)
        #expect(after.reading == .color("#FF3B30"))
        #expect(after.note == nil)
    }

    @Test func aLockedLayersBorderIsLeftAlone() {
        var locked = box("Locked", border: 3)
        locked.isLocked = true
        let free = box("Free", border: 3)
        var doc = document([locked, free])
        #expect(doc.setColorHex(layerIDs: [locked.id, free.id], slot: .border,
                                hex: "#00FF00") == 1)
        #expect(doc.layer(id: locked.id)?.style.borderColorHex == "#101010")
    }

    // MARK: - Wearing a saved color

    @Test func aBorderColorCanBeSavedUnderANameAndEditedInOneStep() {
        let a = box("A", border: 3, borderHex: "#2B5BFF")
        let b = box("B", border: 3, borderHex: "#2B5BFF")
        var doc = document([a, b])
        let styleID = doc.saveColorStyle(from: [a.id, b.id], slot: .border, name: "Hairline")
        #expect(styleID != nil)
        guard let styleID else { return }
        #expect(doc.colorStyle(id: styleID)?.roles == [.ink])
        #expect(doc.layer(id: a.id)?.colorStyleID(for: .border) == styleID)
        #expect(doc.layer(id: b.id)?.colorStyleID(for: .border) == styleID)
        // One edit to the name repaints every border wearing it.
        #expect(doc.setColorStyleHex(styleID: styleID, hex: "#FF3B30") == 2)
        #expect(doc.layer(id: a.id)?.style.borderColorHex == "#FF3B30")
        #expect(doc.layer(id: b.id)?.style.borderColorHex == "#FF3B30")
        #expect(doc.reconcileColorStyles() == 0)
    }

    /// A saved color made off an outline is offered on a border, and one made
    /// for fills is not.
    @Test func theBorderRowOffersTheInkColorsAndNotTheFills() {
        var doc = document([box(border: 2)])
        let ink = doc.addColorStyle(name: "Hairline", colorHex: "#101010", roles: [.ink])
        let surface = doc.addColorStyle(name: "Card", colorHex: "#FFFFFF", roles: [.surface])
        let offered = doc.colorStyles(for: .border).map(\.id)
        #expect(offered.contains(ink))
        #expect(offered.contains(surface) == false)
    }

    /// Taking a border off for a moment must not quietly lose the name it is
    /// wearing: the slot stays while a saved color is pointed at it, so the
    /// safety net that breaks stale claims leaves this one alone.
    @Test func aBorderKeepsItsSavedColorWhileTheWidthIsZero() {
        let a = box("A", border: 3, borderHex: "#2B5BFF")
        var doc = document([a])
        guard let styleID = doc.saveColorStyle(from: a.id, slot: .border, name: "Hairline")
        else { Issue.record("no style saved"); return }
        _ = doc.updateLayerStyles(layerIDs: [a.id]) { $0.borderWidth = 0 }
        #expect(doc.reconcileColorStyles() == 0)
        #expect(doc.layer(id: a.id)?.colorStyleID(for: .border) == styleID)
        // And it follows an edit to the name, so the border comes back wearing
        // whatever that color is now.
        #expect(doc.setColorStyleHex(styleID: styleID, hex: "#00A86B") == 1)
        _ = doc.updateLayerStyles(layerIDs: [a.id]) { $0.borderWidth = 3 }
        #expect(doc.layer(id: a.id)?.style.borderColorHex == "#00A86B")
    }

    /// Painting a border by hand takes it off its saved color, the same way
    /// every other row does.
    @Test func pickingAColorByHandLetsGoOfTheName() {
        let a = box("A", border: 3, borderHex: "#2B5BFF")
        var doc = document([a])
        _ = doc.saveColorStyle(from: a.id, slot: .border, name: "Hairline")
        _ = doc.setColorHex(layerIDs: [a.id], slot: .border, hex: "#FFCC00")
        #expect(doc.layer(id: a.id)?.colorStyleID(for: .border) == nil)
        #expect(doc.layer(id: a.id)?.style.borderColorHex == "#FFCC00")
    }

    /// A zoom callout's ring IS a border, so a picked callout brings a Border
    /// row. That is a second place its ring color can be set, beside the
    /// toolbar's own swatch, which the audit says out loud.
    @Test func aZoomCalloutsRingTurnsUpAsABorderColor() throws {
        let callout = try #require(ZoomCalloutBuilder.layer(
            from: CGPoint(x: 20, y: 20), to: CGPoint(x: 80, y: 60),
            canvas: CGSize(width: 400, height: 400)))
        #expect(callout.colorSlots == [.border])
        #expect(callout.colorHex(for: .border) == "#FF3B30")
    }

    // MARK: - Documents written before this existed

    @Test func anOlderDocumentOpensWithItsBorderColorsUnchanged() throws {
        let doc = document([box("A", border: 4, borderHex: "#C059F2"), box("B")])
        let data = try JSONEncoder().encode(doc)
        let reopened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        let a = try #require(reopened.layers.first)
        #expect(a.style.borderColorHex == "#C059F2")
        #expect(a.colorStyleBindings == nil)
        #expect(a.colorHex(for: .border) == "#C059F2")
        #expect(reopened.layers.last?.colorSlots.contains(.border) == false)
    }
}
