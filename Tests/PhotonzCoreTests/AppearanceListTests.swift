import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The Appearance list is a list you ADD to.
///
/// Three fixed rows held fill, outline and shadow. The effects people asked for
/// next — a second shadow, a shadow cast into the shape, a glow, a bevel — do
/// not fit by adding six more fixed rows, so the list grows instead: a plus
/// that offers the kinds, a remove on anything added, and an order you can drag
/// because the order is what they paint in.
///
/// The user chose this on 2026-09-07, from three panels drawn for the same
/// rectangle. The model is `docs/design/shape-parts.md`, "How the list grows".
@Suite("Appearance list")
struct AppearanceListTests {

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

    private func shadowRows(_ doc: PhotonzDocument, _ ids: [UUID]) -> [LayerPartRow] {
        doc.layerPartRows(layerIDs: ids).filter { $0.part == .shadow }
    }

    // MARK: A shadow is something you add

    @Test("A layer with no shadow has no Shadow row: the plus is how one arrives")
    func noShadowNoRow() {
        let layer = box()
        let doc = document([layer])
        #expect(shadowRows(doc, [layer.id]).isEmpty)
        // ...and the plus says what can be added, in the words a person is
        // looking for rather than behind a popup they have not opened.
        #expect(AppearanceKind.allCases.map(\.title) == ["Shadow", "Inner Shadow"])
    }

    @Test("Adding a shadow adds one row, and adding a second adds a second row")
    func addTwoShadows() {
        let layer = box()
        var doc = document([layer])
        #expect(doc.addAppearance(.dropShadow, layerIDs: [layer.id]) == 1)
        #expect(shadowRows(doc, [layer.id]).count == 1)
        #expect(doc.addAppearance(.dropShadow, layerIDs: [layer.id]) == 1)

        let rows = shadowRows(doc, [layer.id])
        #expect(rows.count == 2)
        #expect(rows.map(\.index) == [0, 1])
        // Two rows, two ids, so the panel can tell one from the other and a
        // drag lands on the row it was aimed at.
        #expect(Set(rows.map(\.id)).count == 2)
    }

    @Test("Each shadow keeps its own settings")
    func shadowsAreIndependent() {
        let layer = box()
        var doc = document([layer])
        doc.addAppearance(.dropShadow, layerIDs: [layer.id])
        doc.addAppearance(.dropShadow, layerIDs: [layer.id])
        doc.updateLayerStyles(layerIDs: [layer.id]) { style in
            style.updateShadow(at: 0) { $0.radius = 2; $0.colorHex = "#FF0000" }
            style.updateShadow(at: 1) { $0.radius = 40; $0.colorHex = "#0000FF" }
        }
        let shadows = doc.layer(id: layer.id)!.style.shadows
        #expect(shadows.map(\.radius) == [2, 40])
        #expect(shadows.map(\.colorHex) == ["#FF0000", "#0000FF"])
    }

    @Test("Removing one shadow leaves the other exactly as it was")
    func removeIsIndependent() {
        let layer = box()
        var doc = document([layer])
        doc.addAppearance(.dropShadow, layerIDs: [layer.id])
        doc.addAppearance(.innerShadow, layerIDs: [layer.id])
        doc.updateLayerStyles(layerIDs: [layer.id]) { $0.updateShadow(at: 0) { $0.radius = 7 } }

        #expect(doc.removeShadow(layerIDs: [layer.id], at: 1) == 1)
        let shadows = doc.layer(id: layer.id)!.style.shadows
        #expect(shadows.count == 1)
        #expect(shadows[0].radius == 7)
        #expect(shadows[0].kind == .drop)
        // Removing a row that is not there changes nothing rather than crashing.
        #expect(doc.removeShadow(layerIDs: [layer.id], at: 4) == 0)
    }

    // MARK: Inner and outer are a SETTING, not a different effect

    @Test("Inner Shadow adds one Shadow row with its Kind already set")
    func innerIsAKindNotAnEffect() {
        let layer = box()
        var doc = document([layer])
        doc.addAppearance(.innerShadow, layerIDs: [layer.id])
        let rows = shadowRows(doc, [layer.id])
        #expect(rows.count == 1)
        // The same row type as a drop shadow: same title, same switch, same
        // colour, same five settings.
        #expect(rows[0].title == "Shadow")
        #expect(doc.layer(id: layer.id)!.style.shadows[0].kind == .inner)
    }

    @Test("The Kind popup turns a drop shadow into an inner one and back")
    func kindIsASetting() {
        let layer = box()
        var doc = document([layer])
        doc.addAppearance(.dropShadow, layerIDs: [layer.id])
        #expect(doc.setShadowKind(layerIDs: [layer.id], at: 0, to: .inner) == 1)
        #expect(doc.layer(id: layer.id)!.style.shadows[0].kind == .inner)
        // Everything else about it survives the switch: it is one shadow drawn
        // in a different place, not a different shadow.
        #expect(doc.layer(id: layer.id)!.style.shadows[0].radius == ShadowStyle().radius)
        #expect(doc.setShadowKind(layerIDs: [layer.id], at: 0, to: .drop) == 1)
        #expect(doc.layer(id: layer.id)!.style.shadows[0].kind == .drop)
    }

    // MARK: Off is not remove

    @Test("Switching a shadow off keeps the entry and everything set on it")
    func offKeepsTheEntry() {
        let layer = box()
        var doc = document([layer])
        doc.addAppearance(.dropShadow, layerIDs: [layer.id])
        doc.updateLayerStyles(layerIDs: [layer.id]) { $0.updateShadow(at: 0) { $0.radius = 30 } }

        #expect(doc.setShadowEnabled(layerIDs: [layer.id], at: 0, on: false) == 1)
        let style = doc.layer(id: layer.id)!.style
        #expect(style.shadows.count == 1)
        #expect(style.shadows[0].radius == 30)
        #expect(style.shadows[0].isOn == false)
        // Off draws nothing...
        #expect(style.paintedShadows.isEmpty)
        // ...and the row still reads off rather than vanishing.
        let rows = shadowRows(doc, [layer.id])
        #expect(rows.count == 1)
        #expect(rows[0].isOn == false)
    }

    @Test("Only a countable kind carries a remove")
    func onlyCountableKindsRemove() {
        var layer = box()
        layer.setPaint(Paint(hex: "#00FF00"), for: .fill)
        var doc = document([layer])
        doc.addAppearance(.dropShadow, layerIDs: [layer.id])
        let rows = doc.layerPartRows(layerIDs: [layer.id])
        // A plain rectangle has exactly one gesture on its Fill and Outline
        // rows — the tick — so there is never a question of which of the two
        // ways to make a thing go away is meant.
        #expect(rows.first { $0.part == .fill }?.canRemove == false)
        #expect(rows.first { $0.part == .outline }?.canRemove == false)
        #expect(rows.first { $0.part == .shadow }?.canRemove == true)
    }

    // MARK: Order is what they paint in

    @Test("Dragging a row changes the order the shadows paint in")
    func reorder() {
        let layer = box()
        var doc = document([layer])
        doc.addAppearance(.dropShadow, layerIDs: [layer.id])
        doc.addAppearance(.dropShadow, layerIDs: [layer.id])
        doc.updateLayerStyles(layerIDs: [layer.id]) { style in
            style.updateShadow(at: 0) { $0.colorHex = "#FF0000" }
            style.updateShadow(at: 1) { $0.colorHex = "#0000FF" }
        }
        #expect(doc.moveShadow(layerIDs: [layer.id], from: 1, to: 0) == 1)
        #expect(doc.layer(id: layer.id)!.style.shadows.map(\.colorHex) == ["#0000FF", "#FF0000"])
        // A move that goes nowhere is not an edit.
        #expect(doc.moveShadow(layerIDs: [layer.id], from: 0, to: 0) == 0)
        #expect(doc.moveShadow(layerIDs: [layer.id], from: 0, to: 9) == 0)
    }

    @Test("Only rows for a countable kind can be dragged")
    func onlyCountableKindsReorder() {
        let layer = box()
        var doc = document([layer])
        doc.addAppearance(.dropShadow, layerIDs: [layer.id])
        let rows = doc.layerPartRows(layerIDs: [layer.id])
        #expect(rows.first { $0.part == .outline }?.canReorder == false)
        #expect(rows.first { $0.part == .shadow }?.canReorder == true)
    }

    // MARK: More than one layer picked

    @Test("Adding reaches every picked layer, so the lists stay the same length")
    func addingReachesEveryone() {
        let one = box(), two = box()
        var doc = document([one, two])
        #expect(doc.addAppearance(.dropShadow, layerIDs: [one.id, two.id]) == 2)
        #expect(doc.layer(id: one.id)!.style.shadows.count == 1)
        #expect(doc.layer(id: two.id)!.style.shadows.count == 1)
        #expect(shadowRows(doc, [one.id, two.id]).count == 1)
    }

    @Test("A row that reaches fewer layers than are picked says so")
    func rowsLineUpByPosition() {
        let one = box(), two = box()
        var doc = document([one, two])
        doc.addAppearance(.dropShadow, layerIDs: [one.id, two.id])
        doc.addAppearance(.dropShadow, layerIDs: [one.id])

        let rows = shadowRows(doc, [one.id, two.id])
        #expect(rows.count == 2)
        #expect(rows[0].switchIDs.count == 2)
        #expect(rows[0].reachNote == nil)
        #expect(rows[1].switchIDs == [one.id])
        #expect(rows[1].reachNote?.contains("1 of the 2 selected layers") == true)
    }

    @Test("A locked layer is never restyled by the list")
    func lockedLayersSitOut() {
        var locked = box()
        locked.isLocked = true
        var doc = document([locked])
        #expect(doc.addAppearance(.dropShadow, layerIDs: [locked.id]) == 0)
        #expect(doc.layer(id: locked.id)!.style.shadows.isEmpty)
    }

    // MARK: Documents that already exist

    @Test("A document written before the list existed opens with its shadow on")
    func oldDocumentsOpenUnchanged() throws {
        let json = """
        {"opacity":1,"blurRadius":0,"cornerRadius":8,"borderWidth":0,\
        "borderColorHex":"#000000","blendMode":"normal",\
        "shadow":{"radius":12,"offset":[0,4],"colorHex":"#112233","opacity":0.4}}
        """
        let style = try JSONDecoder().decode(LayerStyle.self, from: Data(json.utf8))
        #expect(style.shadows.count == 1)
        #expect(style.shadows[0].colorHex == "#112233")
        // The two settings that did not exist yet read as what they always were.
        #expect(style.shadows[0].kind == .drop)
        #expect(style.shadows[0].isOn)
    }

    @Test("One shadow still saves where one shadow has always been saved")
    func oneShadowRoundTrips() throws {
        let style = LayerStyle(shadow: ShadowStyle(colorHex: "#445566"))
        let data = try JSONEncoder().encode(style)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"shadow\""))
        #expect(!text.contains("\"shadows\""))
        let back = try JSONDecoder().decode(LayerStyle.self, from: data)
        #expect(back == style)
    }

    @Test("Two shadows round-trip, and an older build still sees the first one")
    func twoShadowsRoundTrip() throws {
        let style = LayerStyle(shadows: [ShadowStyle(colorHex: "#AA0000"),
                                         ShadowStyle(colorHex: "#0000AA", kind: .inner, isOn: false)])
        let data = try JSONEncoder().encode(style)
        let back = try JSONDecoder().decode(LayerStyle.self, from: data)
        #expect(back == style)
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let first = raw?["shadow"] as? [String: Any]
        #expect(first?["colorHex"] as? String == "#AA0000")
    }

    // MARK: The list is how a new effect arrives

    @Test("A kind is described by its name, its count, its colour and its settings")
    func kindsAreData() {
        // Every entry the plus offers turns into a row of a part that knows
        // whether it can be had twice. A glow or a bevel arrives by joining
        // this list, and nothing else changes to accept it.
        for kind in AppearanceKind.allCases {
            #expect(!kind.title.isEmpty)
            #expect(kind.part.isCountable)
        }
        #expect(LayerPart.fill.isCountable == false)
        #expect(LayerPart.outline.isCountable == false)
        #expect(LayerPart.shadow.isCountable)
    }
}
