import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Appearance is what a shape IS. Effects is a list you ADD to.
///
/// The user's split, chosen on 2026-09-07 from three drawn panels. Appearance
/// holds opacity, fill, outline and a corner radius where there are corners,
/// always in that order, never added and never removed. Effects starts EMPTY
/// and grows: a shadow, a shadow cast into the layer, a blur, and later a glow
/// or a filter, each addable more than once where that means something,
/// removable, and draggable because the order is the order they paint in.
///
/// The model is `docs/design/shape-parts.md`, "Appearance and Effects".
@Suite("Effects list")
struct EffectsListTests {

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

    private func ellipse() -> Layer {
        Layer(name: "Ellipse",
              content: .annotation(AnnotationContent(shape: .ellipse,
                                                     strokeWidth: 4,
                                                     colorHex: "#FF0000",
                                                     start: .zero,
                                                     end: CGPoint(x: 80, y: 80))),
              frame: CGRect(x: 0, y: 0, width: 80, height: 80))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        doc.layers = layers
        return doc
    }

    // MARK: The split itself

    @Test("A new shape's Effects list is empty, and Appearance carries no shadow")
    func effectsStartEmpty() {
        let layer = box()
        let doc = document([layer])
        #expect(doc.layerEffectRows(layerIDs: [layer.id]).isEmpty)
        // Nothing in Appearance is a shadow or a blur any more: they are things
        // you add, so they live in the list below.
        let parts = doc.layerPartRows(layerIDs: [layer.id])
        #expect(parts.allSatisfy { $0.part != .shadow })
        #expect(!parts.contains { $0.title == "Blur" })
        #expect(!parts.contains { $0.title == "Opacity" })
    }

    @Test("Nothing is named the same in both panels")
    func noWordAppearsTwice() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        doc.addEffect(.blur, layerIDs: [layer.id])
        let appearance = Set(doc.layerPartRows(layerIDs: [layer.id]).map(\.title))
        let effects = Set(doc.layerEffectRows(layerIDs: [layer.id]).map(\.title))
        #expect(appearance.isDisjoint(with: effects))
    }

    @Test("Corner Radius is offered only where there are corners")
    func cornersOnlyWhereTheyExist() {
        let round = ellipse(), square = box()
        let doc = document([round, square])
        #expect(doc.cornerRadiusSelection(layerIDs: [round.id], cornersOnly: true).isEmpty)
        #expect(doc.cornerRadiusSelection(layerIDs: [square.id], cornersOnly: true).count == 1)
        // Both picked: the row is there for the one that has corners and says
        // so, rather than vanishing or lying.
        let both = doc.cornerRadiusSelection(layerIDs: [round.id, square.id], cornersOnly: true)
        #expect(both.count == 1)
        #expect(both.note == "Applies to 1 of the 2 selected layers.")
    }

    // MARK: A list you add to

    @Test("The plus offers each effect by the words a person is looking for")
    func theMenu() {
        // The two halos sit together at the top, because somebody reaching for
        // a glow is looking where the shadow is.
        #expect(AddableEffect.allCases.map(\.title) == ["Shadow", "Glow", "Border", "Blur"])
    }

    @Test("Adding a shadow adds one row, and adding a second adds a second row")
    func addTwoShadows() {
        let layer = box()
        var doc = document([layer])
        #expect(doc.addEffect(.shadow, layerIDs: [layer.id]) == 1)
        #expect(doc.layerEffectRows(layerIDs: [layer.id]).count == 1)
        #expect(doc.addEffect(.shadow, layerIDs: [layer.id]) == 1)

        let rows = doc.layerEffectRows(layerIDs: [layer.id])
        #expect(rows.count == 2)
        #expect(rows.map(\.index) == [0, 1])
        // Told apart by name rather than by counting down the panel...
        #expect(rows.map(\.title) == ["Shadow 1", "Shadow 2"])
        // ...and by id, so a drag lands on the row it was aimed at.
        #expect(Set(rows.map(\.id)).count == 2)
    }

    @Test("A lone shadow is simply called Shadow")
    func oneOfAKindKeepsItsPlainName() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        doc.setShadowKind(layerIDs: [layer.id], at: 0, to: .inner)
        #expect(doc.layerEffectRows(layerIDs: [layer.id]).map(\.title) == ["Shadow"])
    }

    @Test("A layer has one softness, so a second Blur is never added")
    func blurIsNotCountable() {
        let layer = box()
        var doc = document([layer])
        #expect(doc.addEffect(.blur, layerIDs: [layer.id]) == 1)
        #expect(doc.addEffect(.blur, layerIDs: [layer.id]) == 0)
        #expect(doc.layerEffectRows(layerIDs: [layer.id]).count == 1)
    }

    @Test("Each shadow keeps its own settings")
    func shadowsAreIndependent() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        doc.updateLayerStyles(layerIDs: [layer.id]) { style in
            style.updateShadow(at: 0) { $0.radius = 2; $0.colorHex = "#FF0000" }
            style.updateShadow(at: 1) { $0.radius = 40; $0.colorHex = "#0000FF" }
        }
        let shadows = doc.layer(id: layer.id)!.style.shadows
        #expect(shadows.map(\.radius) == [2, 40])
        #expect(shadows.map(\.colorHex) == ["#FF0000", "#0000FF"])
    }

    @Test("Removing one entry leaves the others exactly as they were")
    func removeIsIndependent() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        doc.setShadowKind(layerIDs: [layer.id], at: 1, to: .inner)
        doc.updateLayerStyles(layerIDs: [layer.id]) { $0.updateShadow(at: 0) { $0.radius = 7 } }

        #expect(doc.removeEffect(layerIDs: [layer.id], at: 1) == 1)
        let shadows = doc.layer(id: layer.id)!.style.shadows
        #expect(shadows.count == 1)
        #expect(shadows[0].radius == 7)
        #expect(shadows[0].kind == .drop)
        // Removing a row that is not there changes nothing rather than crashing.
        #expect(doc.removeEffect(layerIDs: [layer.id], at: 4) == 0)
    }

    @Test("Everything in the list can be taken out again")
    func everythingAddedCanBeRemoved() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.blur, layerIDs: [layer.id])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        #expect(doc.layerEffectRows(layerIDs: [layer.id]).allSatisfy { $0.canRemove })
        // ...and nothing in Appearance can, because nothing in it was added.
        #expect(doc.layerPartRows(layerIDs: [layer.id]).count > 0)
    }

    // MARK: Inner and outer are a SETTING, not a different effect

    @Test("The plus adds ONE Shadow, and the Kind on it is what makes it inner")
    func innerIsAKindNotAnEffect() {
        let layer = box()
        var doc = document([layer])
        // There is no second menu item for an inner shadow any more: it was one
        // effect named twice, and the row it adds has always carried the Kind
        // (the user's report, 2026-09-07).
        #expect(AddableEffect.allCases.filter { $0.kind == .shadow }.count == 1)
        doc.addEffect(.shadow, layerIDs: [layer.id])
        doc.setShadowKind(layerIDs: [layer.id], at: 0, to: .inner)
        let rows = doc.layerEffectRows(layerIDs: [layer.id])
        #expect(rows.count == 1)
        #expect(rows[0].title == "Shadow")
        #expect(doc.layer(id: layer.id)!.style.shadows[0].kind == .inner)
    }

    @Test("The Kind popup turns a drop shadow into an inner one and back")
    func kindIsASetting() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        #expect(doc.setShadowKind(layerIDs: [layer.id], at: 0, to: .inner) == 1)
        #expect(doc.layer(id: layer.id)!.style.shadows[0].kind == .inner)
        // Everything else about it survives the switch: it is one shadow drawn
        // in a different place, not a different shadow.
        #expect(doc.layer(id: layer.id)!.style.shadows[0].radius == ShadowStyle().radius)
        #expect(doc.setShadowKind(layerIDs: [layer.id], at: 0, to: .drop) == 1)
        #expect(doc.layer(id: layer.id)!.style.shadows[0].kind == .drop)
    }

    // MARK: Off is not remove

    @Test("Switching an effect off keeps the entry and everything set on it")
    func offKeepsTheEntry() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        doc.updateLayerStyles(layerIDs: [layer.id]) { $0.updateShadow(at: 0) { $0.radius = 30 } }

        #expect(doc.setEffectEnabled(layerIDs: [layer.id], at: 0, on: false) == 1)
        let style = doc.layer(id: layer.id)!.style
        #expect(style.shadows.count == 1)
        #expect(style.shadows[0].radius == 30)
        #expect(style.shadows[0].isOn == false)
        // Off draws nothing...
        #expect(style.paintedShadows.isEmpty)
        // ...and the row still reads off rather than vanishing.
        let rows = doc.layerEffectRows(layerIDs: [layer.id])
        #expect(rows.count == 1)
        #expect(rows[0].isOn == false)
    }

    @Test("A blur switched off keeps its amount and stops blurring")
    func blurOffKeepsItsNumber() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.blur, layerIDs: [layer.id])
        doc.updateLayerStyles(layerIDs: [layer.id]) { $0.blurRadius = 24 }
        #expect(doc.layer(id: layer.id)!.style.blurRadius == 24)

        #expect(doc.setEffectEnabled(layerIDs: [layer.id], at: 0, on: false) == 1)
        // The renderer asks for a number and gets nothing to do...
        #expect(doc.layer(id: layer.id)!.style.blurRadius == 0)
        // ...and the number itself is still there, waiting.
        #expect(doc.layer(id: layer.id)!.style.effects[0].blur?.radius == 24)
        #expect(doc.setEffectEnabled(layerIDs: [layer.id], at: 0, on: true) == 1)
        #expect(doc.layer(id: layer.id)!.style.blurRadius == 24)
    }

    // MARK: Order is what they paint in

    @Test("Dragging a row changes the order the shadows paint in")
    func reorder() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        doc.updateLayerStyles(layerIDs: [layer.id]) { style in
            style.updateShadow(at: 0) { $0.colorHex = "#FF0000" }
            style.updateShadow(at: 1) { $0.colorHex = "#0000FF" }
        }
        #expect(doc.moveEffect(layerIDs: [layer.id], from: 1, to: 0) == 1)
        #expect(doc.layer(id: layer.id)!.style.shadows.map(\.colorHex) == ["#0000FF", "#FF0000"])
        // A move that goes nowhere is not an edit.
        #expect(doc.moveEffect(layerIDs: [layer.id], from: 0, to: 0) == 0)
        #expect(doc.moveEffect(layerIDs: [layer.id], from: 0, to: 9) == 0)
    }

    @Test("A blur holds its place at the top, and nothing may be dropped above it")
    func blurIsPinned() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        doc.addEffect(.blur, layerIDs: [layer.id])
        // Whichever order they were added in, the blur is the top row.
        let rows = doc.layerEffectRows(layerIDs: [layer.id])
        #expect(rows.map(\.kind) == [.blur, .shadow])
        // It carries no grip, because a grip that changes nothing is a lie...
        #expect(rows[0].canReorder == false)
        #expect(rows[1].canReorder)
        // ...and the shadow cannot be dropped over it.
        #expect(doc.moveEffect(layerIDs: [layer.id], from: 1, to: 0) == 0)
    }

    @Test("A shadow's row knows which shadow it is once a blur is above it")
    func shadowNumberingSurvivesTheBlur() {
        let layer = box()
        var doc = document([layer])
        doc.addEffect(.blur, layerIDs: [layer.id])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        doc.addEffect(.shadow, layerIDs: [layer.id])
        let rows = doc.layerEffectRows(layerIDs: [layer.id])
        #expect(rows.map(\.index) == [0, 1, 2])
        #expect(rows.map(\.shadowIndex) == [nil, 0, 1])
    }

    // MARK: More than one layer picked

    @Test("Adding reaches every picked layer, so the lists stay the same length")
    func addingReachesEveryone() {
        let one = box(), two = box()
        var doc = document([one, two])
        #expect(doc.addEffect(.shadow, layerIDs: [one.id, two.id]) == 2)
        #expect(doc.layer(id: one.id)!.style.shadows.count == 1)
        #expect(doc.layer(id: two.id)!.style.shadows.count == 1)
        #expect(doc.layerEffectRows(layerIDs: [one.id, two.id]).count == 1)
    }

    @Test("A row that reaches fewer layers than are picked says so")
    func rowsLineUpByPosition() {
        let one = box(), two = box()
        var doc = document([one, two])
        doc.addEffect(.shadow, layerIDs: [one.id, two.id])
        doc.addEffect(.shadow, layerIDs: [one.id])

        let rows = doc.layerEffectRows(layerIDs: [one.id, two.id])
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
        #expect(doc.addEffect(.shadow, layerIDs: [locked.id]) == 0)
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
        // ...and it has one row in Effects, which is what it was already wearing.
        #expect(style.effects.count == 1)
    }

    @Test("A blur written before Effects was a list opens as a Blur row, on")
    func oldBlurBecomesARow() throws {
        let json = """
        {"opacity":1,"blurRadius":6,"cornerRadius":0,"borderWidth":0,\
        "borderColorHex":"#000000","blendMode":"normal"}
        """
        let style = try JSONDecoder().decode(LayerStyle.self, from: Data(json.utf8))
        #expect(style.blurRadius == 6)
        #expect(style.effects.map(\.kind) == [.blur])
        #expect(style.effects[0].isOn)
    }

    @Test("A layer with no blur opens with an empty list, not a Blur row set to zero")
    func zeroBlurIsNotAnEffect() throws {
        let json = """
        {"opacity":1,"blurRadius":0,"cornerRadius":0,"borderWidth":0,\
        "borderColorHex":"#000000","blendMode":"normal"}
        """
        let style = try JSONDecoder().decode(LayerStyle.self, from: Data(json.utf8))
        #expect(style.effects.isEmpty)
    }

    @Test("A blur and two shadows open in the order the renderer has always drawn them")
    func migrationOrder() throws {
        let json = """
        {"opacity":1,"blurRadius":4,"cornerRadius":0,"borderWidth":0,\
        "borderColorHex":"#000000","blendMode":"normal",\
        "shadows":[{"radius":1,"offset":[0,1],"colorHex":"#AA0000","opacity":1},\
        {"radius":2,"offset":[0,2],"colorHex":"#0000AA","opacity":1}]}
        """
        let style = try JSONDecoder().decode(LayerStyle.self, from: Data(json.utf8))
        #expect(style.effects.map(\.kind) == [.blur, .shadow, .shadow])
        // The shadows keep the numbers everything else addresses them by.
        #expect(style.shadows.map(\.colorHex) == ["#AA0000", "#0000AA"])
        #expect(style.blurRadius == 4)
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

    @Test("A blur round-trips, and an older build still blurs the layer")
    func blurRoundTrips() throws {
        var style = LayerStyle()
        style.effects = [.blur(BlurEffect(radius: 9))]
        let data = try JSONEncoder().encode(style)
        let back = try JSONDecoder().decode(LayerStyle.self, from: data)
        #expect(back == style)
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(raw?["blurRadius"] as? Double == 9)
    }

    @Test("A blur switched off saves as no blur, so an older build agrees with the screen")
    func offBlurSavesAsNothing() throws {
        var style = LayerStyle()
        style.effects = [.blur(BlurEffect(radius: 9, isOn: false))]
        let data = try JSONEncoder().encode(style)
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(raw?["blurRadius"] as? Double == 0)
        // ...and this build still has the row, with the number it was left at.
        let back = try JSONDecoder().decode(LayerStyle.self, from: data)
        #expect(back.effects[0].blur?.radius == 9)
        #expect(back.effects[0].isOn == false)
    }

    // MARK: The list is how a new effect arrives

    @Test("A kind is described by its name, its count and whether it holds a place")
    func kindsAreData() {
        // Every entry the plus offers turns into a row of a kind that knows
        // whether it can be had twice and whether its place in the order is
        // yours to choose. A glow or a bevel arrives by joining this list, and
        // nothing else changes to accept it.
        for addable in AddableEffect.allCases {
            #expect(!addable.title.isEmpty)
            #expect(addable.newEffect.kind == addable.kind)
            #expect(addable.newEffect.isOn)
        }
        #expect(EffectKind.shadow.isCountable)
        #expect(EffectKind.blur.isCountable == false)
        #expect(EffectKind.blur.isPinned)
        #expect(EffectKind.shadow.isPinned == false)
    }

    @Test("Writing the shadows back leaves everything else in the list alone")
    func shadowsAreAViewOverTheList() {
        var style = LayerStyle()
        style.effects = [.blur(BlurEffect()), .shadow(ShadowStyle(colorHex: "#111111"))]
        style.shadows.append(ShadowStyle(colorHex: "#222222"))
        #expect(style.effects.map(\.kind) == [.blur, .shadow, .shadow])
        style.shadows = []
        #expect(style.effects.map(\.kind) == [.blur])
        #expect(style.blurRadius == BlurEffect.startingRadius)
    }
}
