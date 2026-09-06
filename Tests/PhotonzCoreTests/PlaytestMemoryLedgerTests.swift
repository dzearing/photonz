import Foundation
import PhotonzCore
import Testing

/// A walk that changes one of the app's remembered settings and leaves it
/// changed hands the next walk a machine it never asked for. Four walks were
/// doing exactly that on 2026-09-05: each passed on its own and failed inside
/// the full run, because something earlier had moved a setting under it.
///
/// The ledger is the part that can be reasoned about without an app: what the
/// settings were before the walk, what they are after, and therefore which
/// areas of memory have to be put back.
@Suite("What a walk changed in the app's memory")
struct PlaytestMemoryLedgerTests {

    private let keys: [PlaytestMemory: [String]] = [
        .text: ["textStyles"],
        .color: ["recentColors", "fill.foreground"],
        .panel: ["inspector.visible", "library.scope"],
    ]

    private func data(_ string: String) -> Data { Data(string.utf8) }

    @Test("A walk that touched nothing has nothing to put back")
    func nothingChanged() {
        let before = ["textStyles": data("24"), "inspector.visible": data("true")]
        let ledger = PlaytestMemoryLedger(before: before, after: before, keys: keys)
        #expect(ledger.changed.isEmpty)
        #expect(ledger.restore.isEmpty)
        #expect(ledger.report == "left every remembered setting as it found it")
    }

    @Test("A changed value names the area of memory it belongs to")
    func changedValueNamesItsMemory() {
        let ledger = PlaytestMemoryLedger(
            before: ["textStyles": data("24")],
            after: ["textStyles": data("48")],
            keys: keys)
        #expect(ledger.changed == [.text])
        #expect(ledger.restore == ["textStyles": data("24")])
    }

    @Test("A setting the walk created from nothing is put back to nothing")
    func settingCreatedByTheWalk() {
        let ledger = PlaytestMemoryLedger(
            before: [:],
            after: ["recentColors": data("#ff0000")],
            keys: keys)
        #expect(ledger.changed == [.color])
        // Nothing was there, so putting it back means taking it away again.
        #expect(ledger.restore == ["recentColors": nil])
    }

    @Test("A setting the walk cleared is put back to what it held")
    func settingClearedByTheWalk() {
        let ledger = PlaytestMemoryLedger(
            before: ["library.scope": data("styles")],
            after: [:],
            keys: keys)
        #expect(ledger.changed == [.panel])
        #expect(ledger.restore == ["library.scope": data("styles")])
    }

    @Test("Two settings in one area of memory name that area once")
    func oneAreaNamedOnce() {
        let ledger = PlaytestMemoryLedger(
            before: ["recentColors": data("a"), "fill.foreground": data("b")],
            after: ["recentColors": data("c"), "fill.foreground": data("d")],
            keys: keys)
        #expect(ledger.changed == [.color])
        #expect(ledger.restore.count == 2)
    }

    @Test("Areas are reported in the order the app remembers them, not at random")
    func areasAreInAStableOrder() {
        let ledger = PlaytestMemoryLedger(
            before: [:],
            after: ["inspector.visible": data("false"), "textStyles": data("48")],
            keys: keys)
        #expect(ledger.changed == [.text, .panel])
        #expect(ledger.report == "put back text, panel")
    }

    @Test("A key belonging to no area of memory is left alone")
    func unknownKeysAreNotOurs() {
        let ledger = PlaytestMemoryLedger(
            before: ["welcome.setupCompleted": data("true")],
            after: ["welcome.setupCompleted": data("false")],
            keys: keys)
        #expect(ledger.changed.isEmpty)
        #expect(ledger.restore.isEmpty)
    }

    @Test("What the walk declared is said apart from what it did not")
    func declaredAndUndeclared() {
        let ledger = PlaytestMemoryLedger(
            before: [:],
            after: ["textStyles": data("48"), "library.scope": data("comps")],
            keys: keys)
        #expect(ledger.undeclared(given: [.text]) == [.panel])
        #expect(ledger.undeclared(given: [.text, .panel]).isEmpty)
        #expect(ledger.undeclared(given: []) == [.text, .panel])
    }
}
