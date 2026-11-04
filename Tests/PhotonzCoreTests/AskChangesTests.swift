import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Ask makes the change straight away, and each request is one row in the
/// Agent group's history (the user, 2026-11-04: "I think it should just be
/// history rather than having toggles and trashcans"). A request is recorded
/// as the document before and after it; undo takes a request back, and each
/// row reads off the document whether its change is still in it, by taking
/// that difference out of the document as it is NOW.
@Suite("Ask: each change one row of history")
struct AskChangesTests {

    static func box(_ name: String, x: CGFloat = 0, color: String = "#000000") -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle, colorHex: color)),
              frame: CGRect(x: x, y: 0, width: 50, height: 20))
    }

    static func picture(_ layers: [Layer] = []) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: layers)
    }

    // MARK: Taking a change out, and putting it back

    @Test("Taking out a change that added layers takes them out")
    func addedLayersComeAndGo() throws {
        let base = Self.box("Screenshot")
        let before = Self.picture([base])
        var after = before
        after.addLayer(Self.box("Measure 1", x: 10))
        after.addLayer(Self.box("Measure 2", x: 20))
        let change = AskRecordedChange(before: before, after: after)

        guard case .changed(let off) = change.takenOut(of: after) else { Issue.record("not taken out"); return }
        #expect(off == before)
    }

    @Test("An edit to an existing layer goes back to what it was")
    func editedLayerRestores() throws {
        let base = Self.box("Card")
        let before = Self.picture([base])
        var after = before
        after.updateLayer(id: base.id) { $0.frame.origin.x = 120 }
        let change = AskRecordedChange(before: before, after: after)
        guard case .changed(let off) = change.takenOut(of: after) else { Issue.record("not taken out"); return }
        #expect(off.layer(id: base.id)?.frame.origin.x == 0)
    }

    @Test("A later edit to a different layer stays when an earlier change is taken out")
    func laterEditsStay() throws {
        let card = Self.box("Card")
        let other = Self.box("Other", x: 300)
        let before = Self.picture([card, other])
        var after = before
        let drawn = Self.box("Drawn", x: 40)
        after.addLayer(drawn)
        after.updateLayer(id: card.id) { $0.name = "Card renamed" }
        let change = AskRecordedChange(before: before, after: after)

        // A later change: another layer moved, and one more added on top.
        var later = after
        later.updateLayer(id: other.id) { $0.frame.origin.y = 77 }
        let added = Self.box("Later", x: 500)
        later.addLayer(added)

        guard case .changed(let off) = change.takenOut(of: later) else { Issue.record("not taken out"); return }
        #expect(off.layer(id: drawn.id) == nil)
        #expect(off.layer(id: card.id)?.name == "Card")
        #expect(off.layer(id: other.id)?.frame.origin.y == 77)
        #expect(off.layer(id: added.id) != nil)
    }

    @Test("A later change built on this one blocks taking it out, and changes nothing")
    func laterDependencyBlocks() {
        let before = Self.picture([Self.box("Screenshot")])
        var after = before
        let drawn = Self.box("Drawn", x: 40)
        after.addLayer(drawn)
        let change = AskRecordedChange(before: before, after: after)
        var later = after
        later.updateLayer(id: drawn.id) { $0.frame.origin.x = 200 }
        #expect(change.takenOut(of: later) == .blocked)
    }

    @Test("Two edits to the same value block, an edit to a different value of the same layer does not")
    func sameLayerDifferentValue() throws {
        let card = Self.box("Card")
        let before = Self.picture([card])
        var after = before
        after.updateLayer(id: card.id) { $0.frame.origin.x = 120 }
        let change = AskRecordedChange(before: before, after: after)

        var renamed = after
        renamed.updateLayer(id: card.id) { $0.name = "Hero" }
        guard case .changed(let off) = change.takenOut(of: renamed) else { Issue.record("not taken out"); return }
        #expect(off.layer(id: card.id)?.frame.origin.x == 0)
        #expect(off.layer(id: card.id)?.name == "Hero")

        var moved = after
        moved.updateLayer(id: card.id) { $0.frame.origin.x = 300 }
        #expect(change.takenOut(of: moved) == .blocked)
    }

    @Test("A change already out of the document has nothing to take out")
    func alreadyOut() {
        let before = Self.picture([Self.box("Screenshot")])
        var after = before
        after.addLayer(Self.box("Drawn"))
        let change = AskRecordedChange(before: before, after: after)
        #expect(change.takenOut(of: before) == .unchanged)
    }

    @Test("A layer added inside a group comes and goes inside that group")
    func insideAGroup() throws {
        let inner = Self.box("Inner")
        let group = Layer(name: "Group", content: .group(GroupContent(children: [inner])),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let before = Self.picture([group])
        var after = before
        let added = Self.box("Added", x: 30)
        let grouped = after.addLayer(added, toGroup: group.id)
        #expect(grouped)
        let change = AskRecordedChange(before: before, after: after)
        guard case .changed(let off) = change.takenOut(of: after) else { Issue.record("not taken out"); return }
        #expect(off == before)
    }

    @Test("Saved styles a change made come and go with it")
    func stylesComeAndGo() throws {
        let before = Self.picture([Self.box("Card")])
        var after = before
        after.colorStyles.append(ColorStyle(name: "Brand", colorHex: "#3366FF"))
        let change = AskRecordedChange(before: before, after: after)
        guard case .changed(let off) = change.takenOut(of: after) else { Issue.record("not taken out"); return }
        #expect(off.colorStyles.isEmpty)
    }

    @Test("A row's click picks what the change made: the layers it added, else the ones it edited")
    func madeLayers() throws {
        let inner = Self.box("Inner")
        let group = Layer(name: "Group", content: .group(GroupContent(children: [inner])),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let before = Self.picture([group])
        var after = before
        let drawn = Self.box("Drawn")
        after.addLayer(drawn)
        let added = AskRecordedChange(before: before, after: after)
        #expect(added.madeLayerIDs(in: after) == [drawn.id])
        // Gone from the document: nothing to pick.
        #expect(added.madeLayerIDs(in: before).isEmpty)

        var edited = before
        edited.updateLayer(id: inner.id) { $0.name = "Renamed" }
        let edit = AskRecordedChange(before: before, after: edited)
        #expect(edit.madeLayerIDs(in: edited) == [inner.id])
    }

    // MARK: The list of rows

    @Test("Each request is one row, newest at the top")
    func rowsNewestFirst() {
        var list = AskChangeList()
        let a = Self.picture()
        var b = a
        b.addLayer(Self.box("One"))
        var c = b
        c.addLayer(Self.box("Two"))
        list.record(asked: "first", sentence: "Drew a shape", before: a, after: b)
        list.record(asked: "second", sentence: "Drew a shape", before: b, after: c)
        #expect(list.rows.map(\.asked) == ["second", "first"])
        #expect(list.rows.allSatisfy { $0.isOn })
    }

    @Test("A request that changed nothing leaves no row")
    func nothingNoRow() {
        var list = AskChangeList()
        let a = Self.picture([Self.box("One")])
        let made = list.record(asked: "noop", sentence: "x", before: a, after: a)
        #expect(made == nil)
        #expect(list.rows.isEmpty)
    }

    @Test("After undo and redo the rows read what the document really holds")
    func resyncAfterUndo() throws {
        var list = AskChangeList()
        let a = Self.picture()
        var b = a
        b.addLayer(Self.box("One"))
        let idMade = list.record(asked: "draw", sentence: "Drew a shape", before: a, after: b)
        let id = try #require(idMade)
        // Command Z took the request back.
        list.follow(a)
        #expect(list.row(id)?.isOn == false)
        list.follow(b)
        #expect(list.row(id)?.isOn == true)
    }

    @Test("A row keeps how Ask understood the request, for its card")
    func rowKeepsWhatItUnderstood() throws {
        var list = AskChangeList()
        let a = Self.picture()
        var b = a
        b.addLayer(Self.box("One"))
        let made = list.record(asked: "draw", sentence: "Drew a shape", before: a, after: b,
                               understood: ["A blue box", "Drew a shape"])
        #expect(list.row(try #require(made))?.understood == ["A blue box", "Drew a shape"])
    }

    @Test("Clear History empties the list and leaves the documents alone")
    func clearEmptiesTheList() {
        var list = AskChangeList()
        let a = Self.picture()
        var b = a
        b.addLayer(Self.box("One"))
        var c = b
        c.addLayer(Self.box("Two"))
        list.record(asked: "one", sentence: "Drew a shape", before: a, after: b)
        list.record(asked: "two", sentence: "Drew a shape", before: b, after: c)
        list.clear()
        #expect(list.rows.isEmpty)
        // What comes next is a row like any other.
        var d = c
        d.addLayer(Self.box("Three"))
        list.record(asked: "three", sentence: "Drew a shape", before: c, after: d)
        #expect(list.rows.map(\.asked) == ["three"])
    }

    // MARK: The row's words

    @Test("The row says what changed in a few plain words")
    func sentences() {
        func steps(_ tools: [String]) -> [AskStep] { tools.map { AskStep(tool: $0, arguments: [:]) } }
        #expect(AskChangeWords.sentence(steps(Array(repeating: "add_measurement", count: 8))) == "Added 8 measurements")
        #expect(AskChangeWords.sentence(steps(["add_measurement"])) == "Added a measurement")
        #expect(AskChangeWords.sentence(steps(["add_shape", "add_path", "add_path"])) == "Drew 3 shapes")
        #expect(AskChangeWords.sentence([AskStep(tool: "add_title", arguments: ["text": "Case 1"])])
                == "Added the title \u{201C}Case 1\u{201D}")
        #expect(AskChangeWords.sentence(steps(["place_component", "place_component", "add_text", "add_text", "add_text"]))
                == "Added 3 texts and placed 2 components")
        #expect(AskChangeWords.sentence(steps(["place_component", "add_text", "apply_style", "set_layout"]))
                == "Placed a component and 3 more")
        #expect(AskChangeWords.sentence([]) == "Made a change")
        for sentence in [AskChangeWords.sentence(steps(["add_shape", "cut", "trim", "move_clip", "set_layer"]))] {
            #expect(!sentence.contains("\u{2014}"))
            #expect(sentence.count <= 40)
        }
    }
}
