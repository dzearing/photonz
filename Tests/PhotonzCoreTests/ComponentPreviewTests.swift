import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Preview: a page of components behaves like the real controls, using only the
/// looks a person made (`docs/design/mocks/pages/component-preview.html`, the
/// user's answer of 2026-11-06). Everything lives in a value thrown away on
/// leaving, so nothing here may ever reach the document.
@Suite("Preview: a page of components acts like real controls")
struct ComponentPreviewTests {

    // MARK: - A page to try

    /// One component with `looks`, each its own drawing, the box filled with a
    /// colour of its own so a test can tell which drawing a copy is showing.
    /// `words` are text parts laid side by side, for a segmented control.
    static func make(_ doc: inout PhotonzDocument, _ name: String, looks: [String],
                     words: [String] = []) -> UUID {
        var parts = [Layer(name: "Box",
                           content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                                  end: CGPoint(x: 120, y: 40))),
                           frame: CGRect(x: 0, y: 0, width: 120, height: 40))]
        parts[0].setColorHex("#336699", for: .fill)
        for (index, word) in words.enumerated() {
            parts.append(Layer(name: word, content: .text(TextContent(string: word)),
                               frame: CGRect(x: CGFloat(index) * 40, y: 10, width: 40, height: 20)))
        }
        doc.layers.append(contentsOf: parts)
        guard let group = doc.groupLayers(ids: Set(parts.map(\.id)), name: name),
              let component = doc.makeComponent(id: group.id)
        else { preconditionFailure("could not make \(name)") }
        for look in looks.dropFirst() { doc.addComponentVersion(componentID: component, name: look) }
        if looks.count > 1, let first = doc.componentVersions(of: component).first {
            doc.renameComponentVersion(componentID: component, version: first.id, to: looks[0])
        }
        return component
    }

    @discardableResult
    static func place(_ doc: inout PhotonzDocument, _ component: UUID, at point: CGPoint,
                      look: String? = nil) -> UUID {
        let version = look.flatMap { name in
            doc.componentVersions(of: component).first { $0.option == name }?.id
        }
        guard let copy = doc.insertComponentInstance(of: component, at: point, version: version)
        else { preconditionFailure("could not place a copy") }
        doc.syncComponentInstances()
        return copy
    }

    static func page() -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), pixelScale: 1)
    }

    static let button = ["Default", "Hover", "Pressed", "Focused", "Disabled"]
    static let toggle = ["Off", "Hover", "Focused", "On", "On Hover", "On Focused"]
    static let tab = ["Default", "Hover", "Focused", "Selected"]

    /// The word a copy is showing right now.
    static func look(_ preview: ComponentPreview, _ copy: UUID, _ doc: PhotonzDocument) -> String? {
        preview.look(of: copy, in: doc)
    }

    /// One whole click: down and up on the same copy.
    static func click(_ preview: inout ComponentPreview, _ copy: UUID, _ doc: PhotonzDocument,
                      at point: CGPoint? = nil) {
        preview.press(copy, in: doc)
        preview.release(over: copy, at: point, in: doc)
    }

    // MARK: - Reading a look's name

    @Test("A look's name says what it is for, in any case and word order")
    func readsNames() {
        #expect(ComponentLookName("Hover").moment == .hover)
        #expect(ComponentLookName("hovered").moment == .hover)
        #expect(ComponentLookName("Pressed").moment == .pressed)
        #expect(ComponentLookName("Focus").moment == .focused)
        #expect(ComponentLookName("Disabled").isDisabled)
        #expect(ComponentLookName("On").latch == .on)
        #expect(ComponentLookName("Checked").latch == .on)
        #expect(ComponentLookName("Selected").latch == .selected)
        #expect(ComponentLookName("Hover On").latch == .on)
        #expect(ComponentLookName("Hover On").moment == .hover)
        #expect(ComponentLookName("On Disabled").isDisabled)
        #expect(ComponentLookName("Default").saysAState == false)
        #expect(ComponentLookName("Compact").saysAState == false)
        #expect(ComponentLookName("Off").saysAState)
        #expect(ComponentLookName("Primary Hover").stem == ["primary"])
    }

    // MARK: - The pointer

    @Test("Pointing shows Hover, pressing shows Pressed, and leaving puts the rest back")
    func hoverAndPress() {
        var doc = Self.page()
        let copy = Self.place(&doc, Self.make(&doc, "Button", looks: Self.button), at: CGPoint(x: 200, y: 200))
        var preview = ComponentPreview()
        #expect(Self.look(preview, copy, doc) == "Default")
        preview.point(at: copy)
        #expect(Self.look(preview, copy, doc) == "Hover")
        preview.press(copy, in: doc)
        #expect(Self.look(preview, copy, doc) == "Pressed")
        preview.release(over: copy, at: nil, in: doc)
        #expect(Self.look(preview, copy, doc) == "Hover")
        preview.point(at: nil)
        #expect(Self.look(preview, copy, doc) == "Default")
    }

    @Test("Sliding off while held lets go: no click, and sliding back presses again")
    func slideOff() {
        var doc = Self.page()
        let sw = Self.place(&doc, Self.make(&doc, "Switch", looks: Self.toggle + ["Pressed"]),
                            at: CGPoint(x: 200, y: 200))
        var preview = ComponentPreview()
        preview.point(at: sw)
        preview.press(sw, in: doc)
        #expect(Self.look(preview, sw, doc) == "Pressed")
        preview.drag(over: nil)
        #expect(Self.look(preview, sw, doc) == "Off")
        preview.drag(over: sw)
        #expect(Self.look(preview, sw, doc) == "Pressed")
        preview.drag(over: nil)
        preview.release(over: nil, at: nil, in: doc)
        #expect(Self.look(preview, sw, doc) == "Off")
    }

    @Test("A held press lights nothing else up")
    func heldPressLightsNothingElse() {
        var doc = Self.page()
        let component = Self.make(&doc, "Button", looks: Self.button)
        let one = Self.place(&doc, component, at: CGPoint(x: 200, y: 200))
        let two = Self.place(&doc, component, at: CGPoint(x: 400, y: 200))
        var preview = ComponentPreview()
        preview.press(one, in: doc)
        preview.drag(over: two)
        #expect(Self.look(preview, two, doc) == "Default")
    }

    @Test("The copy under a point is found through a lock, and never a layer that is not a copy")
    func findsTheCopy() {
        var doc = Self.page()
        let copy = Self.place(&doc, Self.make(&doc, "Button", looks: Self.button), at: CGPoint(x: 200, y: 200))
        doc.updateLayer(id: copy) { $0.isLocked = true }
        let preview = ComponentPreview()
        #expect(preview.copy(at: CGPoint(x: 200, y: 200), in: doc) == copy)
        #expect(preview.copy(at: CGPoint(x: 700, y: 500), in: doc) == nil)
    }

    // MARK: - Clicks that stay

    @Test("A click flips a switch and it stays; a second click flips it back")
    func switchFlips() {
        var doc = Self.page()
        let sw = Self.place(&doc, Self.make(&doc, "Switch", looks: Self.toggle), at: CGPoint(x: 200, y: 200))
        var preview = ComponentPreview()
        preview.point(at: sw)
        Self.click(&preview, sw, doc)
        #expect(Self.look(preview, sw, doc) == "On Hover")
        preview.point(at: nil)
        #expect(Self.look(preview, sw, doc) == "On")
        preview.point(at: sw)
        Self.click(&preview, sw, doc)
        preview.point(at: nil)
        #expect(Self.look(preview, sw, doc) == "Off")
    }

    @Test("A checkbox rests on Default beside Checked")
    func checkbox() {
        var doc = Self.page()
        let box = Self.place(&doc, Self.make(&doc, "Checkbox", looks: ["Default", "Hover", "Checked"]),
                             at: CGPoint(x: 200, y: 200))
        var preview = ComponentPreview()
        Self.click(&preview, box, doc)
        #expect(Self.look(preview, box, doc) == "Checked")
        Self.click(&preview, box, doc)
        #expect(Self.look(preview, box, doc) == "Default")
    }

    @Test("A tab group keeps one selected, and clicking the selected one keeps it")
    func tabsKeepOne() {
        var doc = Self.page()
        let component = Self.make(&doc, "Tab", looks: Self.tab)
        let one = Self.place(&doc, component, at: CGPoint(x: 100, y: 100), look: "Selected")
        let two = Self.place(&doc, component, at: CGPoint(x: 240, y: 100))
        let three = Self.place(&doc, component, at: CGPoint(x: 380, y: 100))
        var preview = ComponentPreview()
        Self.click(&preview, two, doc)
        #expect(Self.look(preview, one, doc) == "Default")
        #expect(Self.look(preview, two, doc) == "Selected")
        #expect(Self.look(preview, three, doc) == "Default")
        Self.click(&preview, two, doc)
        #expect(Self.look(preview, two, doc) == "Selected")
    }

    @Test("Radios keep one on; two switches side by side do not")
    func radiosAndSwitches() {
        var doc = Self.page()
        let radio = Self.make(&doc, "Radio", looks: ["Off", "Hover", "Focused", "On"])
        let first = Self.place(&doc, radio, at: CGPoint(x: 100, y: 100), look: "On")
        let second = Self.place(&doc, radio, at: CGPoint(x: 240, y: 100), look: "Off")
        let toggle = Self.make(&doc, "Switch", looks: Self.toggle)
        let left = Self.place(&doc, toggle, at: CGPoint(x: 100, y: 300))
        let right = Self.place(&doc, toggle, at: CGPoint(x: 240, y: 300))
        var preview = ComponentPreview()
        Self.click(&preview, second, doc)
        #expect(Self.look(preview, first, doc) == "Off")
        #expect(Self.look(preview, second, doc) == "On")
        Self.click(&preview, left, doc)
        Self.click(&preview, right, doc)
        #expect(Self.look(preview, left, doc) == "On")
        #expect(Self.look(preview, right, doc) == "On")
    }

    @Test("Copies in different groups are different groups of tabs")
    func twoGroups() {
        var doc = Self.page()
        let component = Self.make(&doc, "Tab", looks: Self.tab)
        let a1 = Self.place(&doc, component, at: CGPoint(x: 100, y: 100), look: "Selected")
        let a2 = Self.place(&doc, component, at: CGPoint(x: 240, y: 100))
        let b1 = Self.place(&doc, component, at: CGPoint(x: 100, y: 300), look: "Selected")
        let b2 = Self.place(&doc, component, at: CGPoint(x: 240, y: 300))
        _ = doc.groupLayers(ids: [a1, a2], name: "Top")
        _ = doc.groupLayers(ids: [b1, b2], name: "Bottom")
        var preview = ComponentPreview()
        Self.click(&preview, a2, doc)
        #expect(Self.look(preview, a2, doc) == "Selected")
        #expect(Self.look(preview, b1, doc) == "Selected")
        #expect(Self.look(preview, b2, doc) == "Default")
    }

    @Test("A plain Hover never un-picks a Selected tab, and an On Hover is used when it exists")
    func latchedKeepsItsLook() {
        var doc = Self.page()
        let tab = Self.place(&doc, Self.make(&doc, "Tab", looks: Self.tab), at: CGPoint(x: 100, y: 100),
                             look: "Selected")
        let sw = Self.place(&doc, Self.make(&doc, "Switch", looks: Self.toggle), at: CGPoint(x: 300, y: 100),
                            look: "On")
        var preview = ComponentPreview()
        preview.point(at: tab)
        #expect(Self.look(preview, tab, doc) == "Selected")
        preview.point(at: sw)
        #expect(Self.look(preview, sw, doc) == "On Hover")
    }

    @Test("A look with its own first word keeps to its family: Primary Hover, not Hover")
    func stems() {
        var doc = Self.page()
        let component = Self.make(&doc, "Button", looks: ["Primary", "Primary Hover", "Secondary", "Secondary Hover"])
        let copy = Self.place(&doc, component, at: CGPoint(x: 100, y: 100), look: "Secondary")
        var preview = ComponentPreview()
        preview.point(at: copy)
        #expect(Self.look(preview, copy, doc) == "Secondary Hover")
    }

    @Test("A look nobody drew keeps the current look")
    func noLookForAState() {
        var doc = Self.page()
        let copy = Self.place(&doc, Self.make(&doc, "Button", looks: ["Default", "Hover"]), at: CGPoint(x: 100, y: 100))
        var preview = ComponentPreview()
        preview.point(at: copy)
        preview.press(copy, in: doc)
        // No Pressed look: the Hover it had stays up, as the prototype does.
        #expect(Self.look(preview, copy, doc) == "Hover")
    }

    @Test("A Disabled copy does not respond to a point, a press or a click")
    func disabledIgnoresEverything() {
        var doc = Self.page()
        let copy = Self.place(&doc, Self.make(&doc, "Button", looks: Self.button), at: CGPoint(x: 100, y: 100),
                              look: "Disabled")
        let sw = Self.place(&doc, Self.make(&doc, "Switch", looks: Self.toggle + ["On Disabled"]),
                            at: CGPoint(x: 300, y: 100), look: "On Disabled")
        var preview = ComponentPreview()
        preview.point(at: copy)
        #expect(Self.look(preview, copy, doc) == "Disabled")
        preview.press(copy, in: doc)
        #expect(Self.look(preview, copy, doc) == "Disabled")
        Self.click(&preview, sw, doc)
        #expect(Self.look(preview, sw, doc) == "On Disabled")
    }

    @Test("A disabled radio is left alone when its group changes")
    func disabledPeer() {
        var doc = Self.page()
        let radio = Self.make(&doc, "Radio", looks: ["Off", "On", "Disabled"])
        let dead = Self.place(&doc, radio, at: CGPoint(x: 100, y: 100), look: "Disabled")
        let live = Self.place(&doc, radio, at: CGPoint(x: 240, y: 100))
        var preview = ComponentPreview()
        Self.click(&preview, live, doc)
        #expect(Self.look(preview, dead, doc) == "Disabled")
    }

    // MARK: - The keyboard

    @Test("Tab walks the page in reading order, Shift-Tab walks back, and wraps")
    func tabOrder() {
        var doc = Self.page()
        let component = Self.make(&doc, "Button", looks: Self.button)
        // Placed out of order: the layers list says nothing about reading order.
        let bottom = Self.place(&doc, component, at: CGPoint(x: 100, y: 400))
        let topRight = Self.place(&doc, component, at: CGPoint(x: 400, y: 100))
        let topLeft = Self.place(&doc, component, at: CGPoint(x: 100, y: 104))
        var preview = ComponentPreview()
        #expect(preview.tabStops(in: doc) == [topLeft, topRight, bottom])
        preview.tab(backwards: false, in: doc)
        #expect(Self.look(preview, topLeft, doc) == "Focused")
        preview.tab(backwards: false, in: doc)
        #expect(Self.look(preview, topLeft, doc) == "Default")
        #expect(Self.look(preview, topRight, doc) == "Focused")
        preview.tab(backwards: true, in: doc)
        preview.tab(backwards: true, in: doc)
        #expect(Self.look(preview, bottom, doc) == "Focused")
    }

    @Test("Tab skips a Disabled copy, a hidden one, and one with nothing to show")
    func tabSkips() {
        var doc = Self.page()
        let component = Self.make(&doc, "Button", looks: Self.button)
        let live = Self.place(&doc, component, at: CGPoint(x: 100, y: 100))
        Self.place(&doc, component, at: CGPoint(x: 240, y: 100), look: "Disabled")
        let hidden = Self.place(&doc, component, at: CGPoint(x: 380, y: 100))
        doc.updateLayer(id: hidden) { $0.isVisible = false }
        Self.place(&doc, Self.make(&doc, "Plain", looks: ["Default", "Hover"]), at: CGPoint(x: 100, y: 300))
        #expect(ComponentPreview().tabStops(in: doc) == [live])
    }

    @Test("A copy off the canvas is not on the page: Tab passes it and the pointer cannot reach it")
    func offTheCanvas() {
        var doc = Self.page()
        let component = Self.make(&doc, "Button", looks: Self.button)
        let on = Self.place(&doc, component, at: CGPoint(x: 100, y: 100))
        // Where Ask leaves the looks of a component it made: well below the page.
        Self.place(&doc, component, at: CGPoint(x: 100, y: 1000))
        let preview = ComponentPreview()
        #expect(preview.tabStops(in: doc) == [on])
        #expect(preview.copy(at: CGPoint(x: 100, y: 1000), in: doc) == nil)
    }

    @Test("Space clicks what has focus, and Tab goes on from there even if it has no Focused look now")
    func spaceClicksAndTabGoesOn() {
        var doc = Self.page()
        let component = Self.make(&doc, "Tab", looks: Self.tab)
        let one = Self.place(&doc, component, at: CGPoint(x: 100, y: 100), look: "Selected")
        let two = Self.place(&doc, component, at: CGPoint(x: 240, y: 100))
        let three = Self.place(&doc, component, at: CGPoint(x: 380, y: 100))
        var preview = ComponentPreview()
        // A Selected tab has no Selected Focused look, so the first stop is two.
        preview.tab(backwards: false, in: doc)
        #expect(Self.look(preview, two, doc) == "Focused")
        preview.activateFocus(in: doc)
        #expect(Self.look(preview, two, doc) == "Selected")
        #expect(Self.look(preview, one, doc) == "Default")
        preview.tab(backwards: false, in: doc)
        #expect(Self.look(preview, three, doc) == "Focused")
    }

    @Test("A click on a field shows Focused until a press on nothing lets it go")
    func clickFocusesAField() {
        var doc = Self.page()
        let field = Self.place(&doc, Self.make(&doc, "Text Field", looks: ["Default", "Hover", "Focused", "Disabled"]),
                               at: CGPoint(x: 100, y: 100))
        var preview = ComponentPreview()
        Self.click(&preview, field, doc)
        #expect(Self.look(preview, field, doc) == "Focused")
        preview.press(nil, in: doc)
        preview.release(over: nil, at: nil, in: doc)
        #expect(Self.look(preview, field, doc) == "Default")
    }

    // MARK: - A control that is one component

    @Test("A click on a word of a segmented control shows that word's look")
    func segmentedWords() {
        var doc = Self.page()
        let component = Self.make(&doc, "Range", looks: ["Day", "Week", "Month"], words: ["Day", "Week", "Month"])
        let copy = Self.place(&doc, component, at: CGPoint(x: 200, y: 200), look: "Week")
        guard let box = doc.layer(id: copy)?.frame else { Issue.record("no copy"); return }
        var preview = ComponentPreview()
        // The third word sits 80 to 120 along the control.
        Self.click(&preview, copy, doc, at: CGPoint(x: box.minX + 100, y: box.midY))
        #expect(Self.look(preview, copy, doc) == "Month")
        // Between the words still lands on the nearest.
        Self.click(&preview, copy, doc, at: CGPoint(x: box.minX + 2, y: box.minY + 1))
        #expect(Self.look(preview, copy, doc) == "Day")
        #expect(preview.note(in: doc) == nil)
    }

    // MARK: - The note

    @Test("A component named some other way says so, briefly, only under the pointer")
    func noteForOtherNames() {
        var doc = Self.page()
        let copy = Self.place(&doc, Self.make(&doc, "Plan", looks: ["Compact", "Expanded"]), at: CGPoint(x: 100, y: 100))
        var preview = ComponentPreview()
        #expect(preview.note(in: doc) == nil)
        preview.point(at: copy)
        #expect(preview.note(in: doc) == "Plan: no state looks")
        // Nothing plays: pressing and clicking it draws the page as it was.
        Self.click(&preview, copy, doc)
        #expect(preview.drawn(doc) == doc)
    }

    @Test("The note fits the chrome's 30 characters whatever the component is called")
    func noteFitsTheChrome() {
        var doc = Self.page()
        let copy = Self.place(&doc, Self.make(&doc, "A Very Long Component Name Indeed", looks: ["Compact", "Expanded"]),
                              at: CGPoint(x: 100, y: 100))
        var preview = ComponentPreview()
        preview.point(at: copy)
        #expect((preview.note(in: doc)?.count ?? 99) <= 30)
    }

    // MARK: - The document is never touched

    @Test("Drawing hands back a changed value and leaves the document exactly as it was")
    func drawnIsAThrowaway() {
        var doc = Self.page()
        let copy = Self.place(&doc, Self.make(&doc, "Switch", looks: Self.toggle), at: CGPoint(x: 200, y: 200))
        let before = doc
        var preview = ComponentPreview()
        Self.click(&preview, copy, doc)
        let drawn = preview.drawn(doc)
        #expect(doc == before)
        let on = doc.componentVersions(of: doc.layer(id: copy)?.instanceOf ?? UUID()).first { $0.option == "On Hover" || $0.option == "On" }
        #expect(drawn.instanceVersion(of: copy) == on?.id)
        #expect(drawn != doc)
    }

    @Test("With nothing to change, drawing hands the document straight back")
    func drawnAtRest() {
        var doc = Self.page()
        Self.place(&doc, Self.make(&doc, "Button", looks: Self.button), at: CGPoint(x: 200, y: 200))
        #expect(ComponentPreview().drawn(doc) == doc)
    }

    /// What a copy's text says right now.
    static func words(_ doc: PhotonzDocument, _ copy: UUID) -> [String] {
        (doc.layer(id: copy)?.selfAndDescendants ?? []).compactMap { $0.text?.string }
    }

    @Test("A copy keeps its own words in every look, in Preview and when its look is set by hand")
    func wordsFollowEveryLook() throws {
        var doc = Self.page()
        let component = Self.make(&doc, "Tab", looks: Self.tab, words: ["Label"])
        let copy = Self.place(&doc, component, at: CGPoint(x: 240, y: 100))
        // Worded after the looks exist, as place_component's words are, so the
        // knob this makes sits on one drawing and not the others.
        #expect(doc.agentWordCopy(copy, with: ["Privacy"]) == nil)
        doc.syncComponentInstances()
        #expect(Self.words(doc, copy) == ["Privacy"])

        var preview = ComponentPreview()
        preview.point(at: copy)
        #expect(Self.words(preview.drawn(doc), copy) == ["Privacy"])
        Self.click(&preview, copy, doc)
        #expect(Self.words(preview.drawn(doc), copy) == ["Privacy"])

        let selected = try #require(doc.componentVersions(of: component).first { $0.option == "Selected" })
        doc.setInstanceVersion(instance: copy, to: selected.id)
        doc.syncComponentInstances()
        #expect(Self.words(doc, copy) == ["Privacy"])
    }

    @Test("A look keeps its own colour: only words carry across from another look's knob")
    func onlyWordsCarry() throws {
        var doc = Self.page()
        let component = Self.make(&doc, "Tab", looks: Self.tab, words: ["Label"])
        let copy = Self.place(&doc, component, at: CGPoint(x: 240, y: 100))
        let first = try #require(doc.componentVersions(of: component).first)
        let main = try #require(doc.layer(id: first.layerID))
        let box = try #require(main.children.first { $0.name == "Box" })
        let knob = doc.addComponentProperty(componentID: component, version: first.id, target: box.id,
                                            kind: .color, slot: .fill)
        let id = try #require(knob)
        doc.updateLayer(id: copy) { layer in
            guard var group = layer.group else { return }
            group.overrides.append(ComponentOverride(property: id, value: .color(ComponentColorAnswer(colorHex: "#FF0000"))))
            layer.content = .group(group)
        }
        let hover = try #require(doc.componentVersions(of: component).first { $0.option == "Hover" })
        doc.setInstanceVersion(instance: copy, to: hover.id)
        doc.syncComponentInstances()
        let drawnBox = doc.layer(id: copy)?.children.first { $0.name == "Box" }
        #expect(drawnBox?.colorHex(for: .fill)?.uppercased() != "#FF0000")
    }

    @Test("A locked copy still plays, on the throwaway")
    func lockedCopyDraws() {
        var doc = Self.page()
        let component = Self.make(&doc, "Button", looks: Self.button)
        let copy = Self.place(&doc, component, at: CGPoint(x: 200, y: 200))
        doc.updateLayer(id: copy) { $0.isLocked = true }
        var preview = ComponentPreview()
        preview.point(at: copy)
        let hover = doc.componentVersions(of: component).first { $0.option == "Hover" }
        #expect(preview.drawn(doc).instanceVersion(of: copy) == hover?.id)
    }

    @Test("Only the State answer moves on a copy of a component asking State and Size")
    func secondQuestionStays() throws {
        var doc = Self.page()
        let component = Self.make(&doc, "Button", looks: ["Default", "Hover"])
        let added = doc.addComponentVariantProperty(componentID: component, name: "Size")
        let asked = try #require(added)
        let size = asked.property
        // A second answer to Size, drawn for both looks.
        let drawnLarge = doc.addComponentVersion(componentID: component, from: asked.version, name: "Hover")
        let hoverLarge = try #require(drawnLarge)
        let large = try #require(doc.componentVersion(of: component, id: asked.version))
        let want = doc.componentVariantAnswers(of: component, drawing: large)[size]
        let copy = Self.place(&doc, component, at: CGPoint(x: 200, y: 200))
        doc.setInstanceVersion(instance: copy, to: large.id)
        doc.syncComponentInstances()
        var preview = ComponentPreview()
        preview.point(at: copy)
        let drawn = preview.drawn(doc)
        #expect(drawn.instanceVersion(of: copy) == hoverLarge)
        #expect(drawn.instanceVariantAnswers(of: copy)[size] == want)
    }

    @Test("A look deleted from outside falls back to what the copy stores")
    func staleLook() {
        var doc = Self.page()
        let component = Self.make(&doc, "Switch", looks: Self.toggle)
        let copy = Self.place(&doc, component, at: CGPoint(x: 200, y: 200))
        var preview = ComponentPreview()
        Self.click(&preview, copy, doc)
        let gone = Set(doc.componentVersions(of: component).filter { $0.option.hasPrefix("On") }.map(\.layerID))
        doc.layers.removeAll { gone.contains($0.id) }
        doc.componentOriginals.removeAll { gone.contains($0.id) }
        doc.syncComponentInstances()
        #expect(Self.look(preview, copy, doc) == "Off")
    }

    @Test("Only the keys that leave the page alone reach the menus in Preview")
    func keysThatPassThrough() {
        for key in ["\r", "q", "w", "h", "m", "s", "=", "-", "0", ","] {
            #expect(ComponentPreview.commandKeyReachesTheMenus(key))
        }
        for key in ["z", "v", "x", "d", "g", "k", "a", "Z"] {
            #expect(!ComponentPreview.commandKeyReachesTheMenus(key))
        }
    }

    @Test("A walk can claim what Preview shows at a point")
    func walkStep() throws {
        let script = try PlaytestScript.decode(Data(#"""
            { "steps": [ { "do": "expectPreview", "on": true, "at": [200, 100], "shows": "Hover",
                           "note": "Plan: no state looks", "unchanged": true } ] }
            """#.utf8))
        guard case .expectPreview(let on, let at, let shows, let note, let unchanged) = script.steps[0] else {
            Issue.record("expectPreview"); return
        }
        #expect(on == true)
        #expect(at?.point == CGPoint(x: 200, y: 100))
        #expect(shows == "Hover")
        #expect(note == "Plan: no state looks")
        #expect(unchanged == true)
        #expect(script.steps[0].name == "expectPreview")
        #expect(PlaytestStep.names.contains("expectPreview"))
        #expect(PlaytestLockSafety.stepsThatSurviveALock.contains("expectPreview"))
        #expect(throws: (any Error).self) {
            try PlaytestScript.decode(Data(#"{ "steps": [ { "do": "expectPreview" } ] }"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try PlaytestScript.decode(Data(#"{ "steps": [ { "do": "expectPreview", "shows": "Hover" } ] }"#.utf8))
        }
    }

    @Test("A page with no copies has nothing to preview")
    func canPreview() {
        var doc = Self.page()
        #expect(!doc.canPreviewComponents)
        Self.place(&doc, Self.make(&doc, "Button", looks: Self.button), at: CGPoint(x: 200, y: 200))
        #expect(doc.canPreviewComponents)
    }
}
