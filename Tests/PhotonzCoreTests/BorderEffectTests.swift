import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A border is something you ADD, and you can add more than one.
///
/// The user's report on 2026-09-07: the plus offered a drop shadow, an inner
/// shadow and a blur, so a second edge — an outer one, an inner one, two of
/// them at once — simply could not be made. And the two shadow entries were one
/// idea named twice, since the model has always held one shadow with a Kind.
///
/// So the plus now offers **Shadow, Border, Blur**: one shadow whose Kind
/// switches it in place, and a border that is countable, draggable and carries
/// a Position of its own. `docs/design/shape-parts.md`, "Appearance and
/// Effects".
@Suite("Border effect")
struct BorderEffectTests {

    private func box(_ style: LayerStyle = LayerStyle()) -> Layer {
        Layer(name: "Box",
              content: .annotation(AnnotationContent(shape: .rectangle,
                                                     strokeWidth: 4,
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

    // MARK: The menu

    @Test("The plus offers one Shadow, a Border and a Blur")
    func theMenu() {
        #expect(AddableEffect.allCases.map(\.title) == ["Shadow", "Border", "Blur"])
        // The two shadow entries were one idea named twice. One entry adds an
        // ordinary drop shadow, and the Kind on the row it becomes is what
        // turns it into an inner one.
        #expect(AddableEffect.shadow.newEffect.shadow?.kind == .drop)
    }

    @Test("A border is countable, draggable and paints a colour")
    func theKind() {
        #expect(EffectKind.border.title == "Border")
        #expect(EffectKind.border.isCountable)
        #expect(EffectKind.border.isPinned == false)
        #expect(EffectKind.border.paintsAColor)
    }

    @Test("A new border arrives already looking like something")
    func newBorderIsUsable() {
        let border = AddableEffect.border.newEffect.border
        #expect(border?.isOn == true)
        #expect((border?.width ?? 0) > 0)
        // Outside, because the one edge a shape already HAS is drawn inside it:
        // a border that landed in the same place would look like nothing
        // happened, which is the whole complaint.
        #expect(border?.position == .outside)
        #expect(border?.paints == true)
    }

    // MARK: More than one of them

    @Test("An inner and an outer border are two entries with their own settings")
    func twoBordersOnOneShape() {
        let layer = box()
        var doc = document([layer])
        #expect(doc.addEffect(.border, layerIDs: [layer.id]) == 1)
        #expect(doc.addEffect(.border, layerIDs: [layer.id]) == 1)

        // The second lands at the foot of the list, so the first holds still.
        doc.updateBorderEffect(layerIDs: [layer.id], at: 0) {
            $0.position = .outside
            $0.width = 6
            $0.colorHex = "#00FF00"
        }
        doc.updateBorderEffect(layerIDs: [layer.id], at: 1) {
            $0.position = .inside
            $0.width = 2
            $0.colorHex = "#0000FF"
        }

        let style = doc.layer(id: layer.id)!.style
        #expect(style.borderEffects.count == 2)
        #expect(style.borderEffects[0].position == .outside)
        #expect(style.borderEffects[0].width == 6)
        #expect(style.borderEffects[0].colorHex == "#00FF00")
        #expect(style.borderEffects[1].position == .inside)
        #expect(style.borderEffects[1].width == 2)
        #expect(style.borderEffects[1].colorHex == "#0000FF")

        // Two rows, told apart by name rather than by counting down the panel.
        let rows = doc.layerEffectRows(layerIDs: [layer.id])
        #expect(rows.map(\.title) == ["Border 1", "Border 2"])
        #expect(rows.allSatisfy { $0.canReorder && $0.canRemove })
    }

    @Test("Only the border you asked for changes")
    func oneBorderAtATime() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.border, layerIDs: [layer.id])
        doc.addEffect(.border, layerIDs: [layer.id])
        doc.updateBorderEffect(layerIDs: [layer.id], at: 1) { $0.width = 11 }
        let style = doc.layer(id: layer.id)!.style
        #expect(style.borderEffects[0].width == BorderEffect.startingWidth)
        #expect(style.borderEffects[1].width == 11)
        // And a place in the list that holds no border is left alone entirely.
        #expect(doc.updateBorderEffect(layerIDs: [layer.id], at: 7) { $0.width = 1 } == 0)
    }

    @Test("A border obeys the order, and can be taken out")
    func orderAndRemoval() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.border, layerIDs: [layer.id])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        doc.addEffect(.border, layerIDs: [layer.id])
        doc.updateBorderEffect(layerIDs: [layer.id], at: 0) { $0.colorHex = "#111111" }
        doc.updateBorderEffect(layerIDs: [layer.id], at: 2) { $0.colorHex = "#222222" }
        #expect(doc.layer(id: layer.id)!.style.effects.map(\.kind) == [.border, .shadow, .border])

        // Dragged to the top, the second border goes over the first.
        #expect(doc.moveEffect(layerIDs: [layer.id], from: 2, to: 0) == 1)
        #expect(doc.layer(id: layer.id)!.style.borderEffects.map(\.colorHex)
                == ["#222222", "#111111"])

        #expect(doc.removeEffect(layerIDs: [layer.id], at: 0) == 1)
        #expect(doc.layer(id: layer.id)!.style.borderEffects.map(\.colorHex) == ["#111111"])
    }

    @Test("The tick keeps every number on a border and stops it drawing")
    func offIsNotRemove() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.border, layerIDs: [layer.id])
        doc.updateBorderEffect(layerIDs: [layer.id], at: 0) { $0.width = 9 }
        #expect(doc.setEffectEnabled(layerIDs: [layer.id], at: 0, on: false) == 1)
        let border = doc.layer(id: layer.id)!.style.borderEffects[0]
        #expect(border.isOn == false)
        #expect(border.width == 9)
        #expect(border.paints == false)
    }

    // MARK: How far it reaches

    @Test("An outside border makes room for itself, an inside one does not")
    func reach() {
        var outside = LayerStyle()
        outside.effects = [.border(BorderEffect(width: 6, position: .outside))]
        #expect(outside.previewPadding == 6)

        var inside = LayerStyle()
        inside.effects = [.border(BorderEffect(width: 6, position: .inside))]
        #expect(inside.previewPadding == 0)

        var centred = LayerStyle()
        centred.effects = [.border(BorderEffect(width: 6, position: .center))]
        #expect(centred.previewPadding == 3)

        // The furthest ring decides. Two of them overlap; they do not stack
        // end to end, so the reach is the widest one and not their sum.
        var both = LayerStyle()
        both.effects = [.border(BorderEffect(width: 6, position: .outside)),
                        .border(BorderEffect(width: 2, position: .outside))]
        #expect(both.previewPadding == 6)

        // Switched off, it asks for nothing.
        var off = LayerStyle()
        off.effects = [.border(BorderEffect(width: 6, position: .outside, isOn: false))]
        #expect(off.previewPadding == 0)
    }

    @Test("A layer wearing a border is not plain")
    func plainness() {
        var style = LayerStyle()
        #expect(style.isPlain)
        style.effects = [.border(BorderEffect())]
        #expect(style.isPlain == false)
        style.effects = [.border(BorderEffect(isOn: false))]
        #expect(style.isPlain)
    }

    // MARK: The file

    @Test("A border saves and opens as the border it was")
    func roundTrip() throws {
        var style = LayerStyle()
        style.effects = [.border(BorderEffect(width: 3, colorHex: "#ABCDEF",
                                              position: .center, isOn: false)),
                         .shadow(ShadowStyle(kind: .inner))]
        let data = try JSONEncoder().encode(style)
        let back = try JSONDecoder().decode(LayerStyle.self, from: data)
        #expect(back.effects == style.effects)
        // And the saved file names the kind out loud, so a person reading it
        // can tell what the entry is.
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"kind\":\"border\""))
    }

    @Test("A shadow saved before this opens as the shadow it was, inner or outer")
    func oldShadowsKeepTheirKind() throws {
        // Written by a build whose plus had two shadow entries: the kind is a
        // field on the shadow itself, so nothing about the menu merge can lose
        // it. An inner one opens inner and a drop one opens drop.
        for kind in ["inner", "drop"] {
            let json = """
            {"opacity":1,"blurRadius":0,"cornerRadius":0,"borderWidth":0,
             "borderColorHex":"#000000","blendMode":"normal",
             "shadow":{"radius":12,"offset":[0,4],"spread":0,
                       "colorHex":"#000000","opacity":0.4,"kind":"\(kind)"}}
            """
            let style = try JSONDecoder().decode(LayerStyle.self, from: Data(json.utf8))
            #expect(style.effects.count == 1)
            #expect(style.shadows.first?.kind.rawValue == kind)
        }
    }

    // MARK: One Shadow with a switch on it

    @Test("The Kind switches a shadow in place and keeps everything else")
    func kindChangesInPlace() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        doc.updateEffect(layerIDs: [layer.id], at: 0) {
            $0.shadow?.radius = 20
            $0.shadow?.colorHex = "#123456"
        }
        #expect(doc.setShadowKind(layerIDs: [layer.id], at: 0, to: .inner) == 1)
        let shadow = doc.layer(id: layer.id)!.style.shadows[0]
        #expect(shadow.kind == .inner)
        #expect(shadow.radius == 20)
        #expect(shadow.colorHex == "#123456")
        // Still one entry, in the same place: the switch does not add a row.
        #expect(doc.layerEffectRows(layerIDs: [layer.id]).map(\.title) == ["Shadow"])
    }
}
