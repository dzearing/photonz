import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A shape can throw a shadow, and now it can also GLOW.
///
/// The Effects list was built to make this a one-case change: a new kind, its
/// settings, and an entry on the plus. Everything else — the tick, the cross,
/// the grip, the colour row, the multi-selection sentence, the saved file —
/// reads the list rather than the kind, so none of it is touched here.
///
/// The plus offers **Glow** once, not "Glow" and "Inner Glow". Splitting a kind
/// across two menu items is the thing the user reported on 2026-09-07 about the
/// shadow: inner and outer are one effect drawn somewhere else, so the row
/// carries a Kind and the menu stays short.
@Suite("Glow effect")
struct GlowEffectTests {

    private func box(_ style: LayerStyle = LayerStyle()) -> Layer {
        Layer(name: "Box",
              content: .annotation(AnnotationContent(shape: .rectangle,
                                                     strokeWidth: 0,
                                                     colorHex: "#FF0000",
                                                     start: .zero,
                                                     end: CGPoint(x: 100, y: 60),
                                                     fillColorHex: "#FF0000")),
              frame: CGRect(x: 0, y: 0, width: 100, height: 60),
              style: style)
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        doc.layers = layers
        return doc
    }

    // MARK: The menu

    @Test("The plus offers a Glow, once, beside the Shadow")
    func theMenu() {
        #expect(AddableEffect.allCases.map(\.title) == ["Shadow", "Glow", "Border", "Blur"])
        // ONE entry, not a Glow and an Inner Glow: the row it becomes carries
        // the Kind that turns it inside.
        #expect(AddableEffect.allCases.filter { $0.kind == .glow }.count == 1)
        #expect(AddableEffect.glow.newEffect.glow?.kind == .outer)
    }

    @Test("A glow is countable, draggable and paints a colour")
    func theKind() {
        #expect(EffectKind.glow.title == "Glow")
        #expect(EffectKind.glow.isCountable)
        #expect(EffectKind.glow.isPinned == false)
        #expect(EffectKind.glow.paintsAColor)
        #expect(EffectKind.glow.colorSlot == .glow)
    }

    @Test("A new glow arrives already looking like something")
    func newGlowIsUsable() {
        let glow = AddableEffect.glow.newEffect.glow
        #expect(glow?.isOn == true)
        #expect(glow?.paints == true)
        // Not black: a black halo is a shadow, and the whole point of this
        // effect is that it does not only darken.
        #expect(glow?.colorHex != "#000000")
        #expect((glow?.radius ?? 0) > 0)
        #expect((glow?.opacity ?? 0) > 0.5)
    }

    // MARK: More than one of them

    @Test("Two glows of different colours sit on one shape, in the order they arrived")
    func twoGlowsOnOneShape() {
        let layer = box()
        var doc = document([layer])
        #expect(doc.addEffect(.glow, layerIDs: [layer.id]) == 1)
        #expect(doc.addEffect(.glow, layerIDs: [layer.id]) == 1)

        // The second lands at the FOOT, so the first holds still.
        doc.updateGlowEffect(layerIDs: [layer.id], at: 0) {
            $0.colorHex = "#00FF00"
            $0.size = 4
        }
        doc.updateGlowEffect(layerIDs: [layer.id], at: 1) {
            $0.colorHex = "#0000FF"
            $0.size = 12
        }
        let glows = doc.layer(id: layer.id)!.style.glowEffects
        #expect(glows.count == 2)
        #expect(glows[0].colorHex == "#00FF00")
        #expect(glows[1].colorHex == "#0000FF")

        // Dragging the wide one up puts it over the tight one, which is the
        // whole meaning of the grip.
        #expect(doc.moveEffect(layerIDs: [layer.id], from: 1, to: 0) == 1)
        let moved = doc.layer(id: layer.id)!.style.glowEffects
        #expect(moved[0].colorHex == "#0000FF")
        #expect(moved[1].colorHex == "#00FF00")
    }

    @Test("A glow and a shadow are two rows that keep their own numbers")
    func glowBesideShadow() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        doc.addEffect(.glow, layerIDs: [layer.id])
        let rows = doc.layerEffectRows(layerIDs: [layer.id])
        #expect(rows.map(\.title) == ["Shadow", "Glow"])
        // A glow is not a shadow, however it is drawn: the Shadow rows are
        // still addressed by counting shadows, and there is exactly one.
        #expect(doc.layer(id: layer.id)!.style.shadows.count == 1)
        #expect(doc.layer(id: layer.id)!.style.glowEffects.count == 1)
    }

    // MARK: The tick and the cross

    @Test("A glow switched off keeps every number on it, and the cross takes it out")
    func offKeepsItsSettings() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.glow, layerIDs: [layer.id])
        doc.updateGlowEffect(layerIDs: [layer.id], at: 0) {
            $0.colorHex = "#FF00FF"
            $0.radius = 21
            $0.size = 7
            $0.opacity = 0.55
        }
        #expect(doc.setEffectEnabled(layerIDs: [layer.id], at: 0, on: false) == 1)
        let off = doc.layer(id: layer.id)!.style.glowEffect(at: 0)
        #expect(off?.isOn == false)
        #expect(off?.colorHex == "#FF00FF")
        #expect(off?.radius == 21)
        #expect(off?.size == 7)
        #expect(off?.opacity == 0.55)
        // Off paints nothing, which is what makes look-with-and-without a
        // gesture rather than a redo.
        #expect(doc.layer(id: layer.id)!.style.paintedGlows.isEmpty)

        #expect(doc.removeEffect(layerIDs: [layer.id], at: 0) == 1)
        #expect(doc.layer(id: layer.id)!.style.effects.isEmpty)
    }

    @Test("The Kind turns one glow inside without making a second row")
    func kindTurnsItInside() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.glow, layerIDs: [layer.id])
        doc.updateGlowEffect(layerIDs: [layer.id], at: 0) { $0.kind = .inner }
        #expect(doc.layer(id: layer.id)!.style.glowEffects.count == 1)
        #expect(doc.layer(id: layer.id)!.style.glowEffect(at: 0)?.kind == .inner)
        #expect(doc.layerEffectRows(layerIDs: [layer.id]).map(\.title) == ["Glow"])
    }

    @Test("A settings change aimed at a glow leaves a shadow in that place alone")
    func aimingAtTheRightEntry() {
        let shape = box()
        var withShadow = shape
        withShadow.style.effects = [.shadow(ShadowStyle())]
        var withGlow = box()
        withGlow.style.effects = [.glow(GlowEffect())]
        var doc = document([withShadow, withGlow])
        #expect(doc.updateGlowEffect(layerIDs: [withShadow.id, withGlow.id], at: 0) {
            $0.radius = 30
        } == 1)
        #expect(doc.layer(id: withShadow.id)!.style.shadow(at: 0)?.radius == 12)
        #expect(doc.layer(id: withGlow.id)!.style.glowEffect(at: 0)?.radius == 30)
    }

    // MARK: How far it reaches

    @Test("An outer glow makes room for itself and an inner one asks for none")
    func reach() {
        var outer = LayerStyle()
        outer.effects = [.glow(GlowEffect(colorHex: "#00FF00", radius: 10, size: 4,
                                          opacity: 1, kind: .outer))]
        #expect(outer.previewPadding >= 34)

        var inner = LayerStyle()
        inner.effects = [.glow(GlowEffect(colorHex: "#00FF00", radius: 10, size: 4,
                                          opacity: 1, kind: .inner))]
        // An inner glow never puts a pixel outside its layer, so it costs no
        // room at all.
        #expect(inner.previewPadding == 0)

        // Switched off it reaches nowhere either.
        var off = LayerStyle()
        off.effects = [.glow(GlowEffect(colorHex: "#00FF00", radius: 10, size: 4,
                                        opacity: 1, kind: .outer, isOn: false))]
        #expect(off.previewPadding == 0)
    }

    @Test("A glow counts as decoration, so a group wearing one is not plain")
    func notPlain() {
        var style = LayerStyle()
        style.effects = [.glow(GlowEffect())]
        #expect(style.isPlain == false)
        #expect(style.hasNoFixedSizeDecoration == false)
    }

    // MARK: The saved file

    @Test("A glow is written legibly and comes back exactly as it went in")
    func roundTrip() throws {
        var style = LayerStyle()
        style.effects = [.glow(GlowEffect(colorHex: "#12AB34", radius: 9, size: 3,
                                          opacity: 0.6, kind: .inner))]
        let data = try JSONEncoder().encode(style)
        let text = String(decoding: data, as: UTF8.self)
        // A file is a thing people open: the kind is named, not indexed.
        #expect(text.contains("\"kind\":\"glow\""))
        let back = try JSONDecoder().decode(LayerStyle.self, from: data)
        #expect(back.glowEffects == style.glowEffects)
    }

    @Test("A document written before glows existed opens exactly as it did")
    func oldDocumentsAreUntouched() throws {
        // The shape of a style saved before this: a blur number and one shadow,
        // and no effects list at all.
        let json = """
        {"opacity":1,"blurRadius":4,"cornerRadius":8,"borderWidth":0,
         "borderColorHex":"#000000","blendMode":"normal",
         "shadow":{"radius":12,"offset":[0,4],"spread":0,
                   "colorHex":"#000000","opacity":0.4}}
        """
        let style = try JSONDecoder().decode(LayerStyle.self, from: Data(json.utf8))
        #expect(style.glowEffects.isEmpty)
        #expect(style.blurRadius == 4)
        #expect(style.shadows.count == 1)
        #expect(style.effects.map(\.kind) == [.blur, .shadow])
    }

    // MARK: What it is, underneath

    @Test("A glow is a shadow with nowhere to fall")
    func aGlowIsAnUnoffsetShadow() {
        let glow = GlowEffect(colorHex: "#00FF00", radius: 10, size: 3,
                              opacity: 0.5, kind: .outer)
        let shadow = glow.asShadow
        #expect(shadow.offset == .zero)
        #expect(shadow.radius == 10)
        #expect(shadow.spread == 3)
        #expect(shadow.colorHex == "#00FF00")
        #expect(shadow.opacity == 0.5)
        #expect(shadow.kind == .drop)
        #expect(GlowEffect(kind: .inner).asShadow.kind == .inner)
    }
}
