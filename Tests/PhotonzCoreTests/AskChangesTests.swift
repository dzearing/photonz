import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Ask makes the change straight away, and each request is one row in the
/// Agent group that can be turned off, on again, or deleted (the user,
/// 2026-10-20). A request is recorded as the document before and after it, and
/// turning it off takes that difference out of the document as it is NOW, so
/// later edits to other layers stay.
@Suite("Ask: each change one row, off, on and deleted")
struct AskChangesTests {

    static func box(_ name: String, x: CGFloat = 0, color: String = "#000000") -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle, colorHex: color)),
              frame: CGRect(x: x, y: 0, width: 50, height: 20))
    }

    static func picture(_ layers: [Layer] = []) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: layers)
    }

    // MARK: Taking a change out, and putting it back

    @Test("Turning off a change that added layers takes them out, and turning it on puts them back")
    func addedLayersComeAndGo() throws {
        let base = Self.box("Screenshot")
        let before = Self.picture([base])
        var after = before
        after.addLayer(Self.box("Measure 1", x: 10))
        after.addLayer(Self.box("Measure 2", x: 20))
        let change = AskRecordedChange(before: before, after: after)

        guard case .changed(let off) = change.takenOut(of: after) else { Issue.record("not taken out"); return }
        #expect(off == before)
        guard case .changed(let on) = change.putBack(into: off) else { Issue.record("not put back"); return }
        #expect(on == after)
    }

    @Test("An edit to an existing layer goes back to what it was, and comes back")
    func editedLayerRestores() throws {
        let base = Self.box("Card")
        let before = Self.picture([base])
        var after = before
        after.updateLayer(id: base.id) { $0.frame.origin.x = 120 }
        let change = AskRecordedChange(before: before, after: after)
        guard case .changed(let off) = change.takenOut(of: after) else { Issue.record("not taken out"); return }
        #expect(off.layer(id: base.id)?.frame.origin.x == 0)
        guard case .changed(let on) = change.putBack(into: off) else { Issue.record("not put back"); return }
        #expect(on.layer(id: base.id)?.frame.origin.x == 120)
    }

    @Test("A later edit to a different layer stays when an earlier change is turned off")
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
        // ...and on again lands the drawn layer where it was, under the later one.
        guard case .changed(let on) = change.putBack(into: off) else { Issue.record("not put back"); return }
        #expect(on.layers.map(\.id) == later.layers.map(\.id))
        #expect(on == later)
    }

    @Test("A later change built on this one blocks turning it off, and changes nothing")
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
        #expect(change.putBack(into: after) == .unchanged)
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
        #expect(list.shown.map(\.asked) == ["second", "first"])
        #expect(list.shown.allSatisfy { $0.isOn })
    }

    @Test("A request that changed nothing leaves no row")
    func nothingNoRow() {
        var list = AskChangeList()
        let a = Self.picture([Self.box("One")])
        let made = list.record(asked: "noop", sentence: "x", before: a, after: a)
        #expect(made == nil)
        #expect(list.shown.isEmpty)
    }

    @Test("Switching a row off and on hands back the document, and the row follows")
    func switchRow() throws {
        var list = AskChangeList()
        let a = Self.picture()
        var b = a
        b.addLayer(Self.box("One"))
        let idMade = list.record(asked: "draw", sentence: "Drew a shape", before: a, after: b)
        let id = try #require(idMade)
        guard case .changed(let off) = list.setOn(false, id: id, in: b) else { Issue.record("no change"); return }
        #expect(off == a)
        #expect(list.row(id)?.isOn == false)
        guard case .changed(let on) = list.setOn(true, id: id, in: off) else { Issue.record("no change"); return }
        #expect(on == b)
        #expect(list.row(id)?.isOn == true)
    }

    @Test("A blocked switch stays where it was and the row says why")
    func blockedRowSays() throws {
        var list = AskChangeList()
        let a = Self.picture()
        var b = a
        let drawn = Self.box("One")
        b.addLayer(drawn)
        let idMade = list.record(asked: "draw", sentence: "Drew a shape", before: a, after: b)
        let id = try #require(idMade)
        var later = b
        later.updateLayer(id: drawn.id) { $0.frame.origin.x = 99 }
        let blocked = list.setOn(false, id: id, in: later)
        #expect(blocked == .blocked)
        #expect(list.row(id)?.isOn == true)
        #expect(list.row(id)?.note == AskChangeList.laterChangeNote)
        // The note goes once the row can switch again.
        guard case .changed = list.setOn(false, id: id, in: b) else { Issue.record("no change"); return }
        #expect(list.row(id)?.note == nil)
    }

    @Test("Deleting an on row takes its change out and the row goes; deleting an off row only removes the row")
    func deleteRows() throws {
        var list = AskChangeList()
        let a = Self.picture()
        var b = a
        b.addLayer(Self.box("One"))
        var c = b
        c.addLayer(Self.box("Two"))
        let firstMade = list.record(asked: "one", sentence: "Drew a shape", before: a, after: b)
        let first = try #require(firstMade)
        let secondMade = list.record(asked: "two", sentence: "Drew a shape", before: b, after: c)
        let second = try #require(secondMade)
        guard case .changed(let gone) = list.delete(id: first, in: c) else { Issue.record("no change"); return }
        #expect(gone.layers.map(\.name) == ["Two"])
        #expect(list.shown.map(\.id) == [second])
        guard case .changed(let off) = list.setOn(false, id: second, in: gone) else { Issue.record("no change"); return }
        let removed = list.delete(id: second, in: off)
        #expect(removed == .unchanged)
        #expect(list.shown.isEmpty)
    }

    @Test("After undo and redo the rows read what the document really holds, and a deleted row undone comes back")
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
        // Deleted, then the delete undone.
        _ = list.delete(id: id, in: b)
        #expect(list.shown.isEmpty)
        list.follow(b)
        #expect(list.shown.map(\.id) == [id])
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
