import Foundation
import PhotonzCore
import Testing

/// macOS will not give a script-launched background app the front, so SwiftUI
/// never rebuilds the probe's menu bar after launch and every window-scoped
/// command sits there dimmed with nothing behind it. A walk that presses ⌘Z is
/// therefore pressing a dead item, however healthy the app is: the walk could
/// only ever report the frozen menu bar back at itself.
///
/// So a chord a walk presses carries a stand-in: the command the person doing
/// that press meant. This is the table of them, which is pure data and can be
/// read without an app on screen.
@Suite("What a chord means when its menu item cannot run")
struct PlaytestMenuStandInTests {

    @Test("Command Z means undo")
    func undo() {
        #expect(PlaytestMenuStandIn.action(for: key("z"), modifiers: [.command]) == .undo)
    }

    @Test("Shift command Z means redo")
    func redo() {
        #expect(PlaytestMenuStandIn.action(for: key("z"), modifiers: [.command, .shift]) == .redo)
        // The order a script happens to list the modifiers in is not meaning.
        #expect(PlaytestMenuStandIn.action(for: key("z"), modifiers: [.shift, .command]) == .redo)
    }

    @Test("The copies and the cut carry their chords too")
    func clipboard() {
        #expect(PlaytestMenuStandIn.action(for: key("c"), modifiers: [.command]) == .copy)
        #expect(PlaytestMenuStandIn.action(for: key("c"), modifiers: [.command, .shift]) == .copyMerged)
        #expect(PlaytestMenuStandIn.action(for: key("x"), modifiers: [.command]) == .cut)
    }

    @Test("The zoom chords carry theirs")
    func zoom() {
        #expect(PlaytestMenuStandIn.action(for: key("="), modifiers: [.command]) == .zoomIn)
        #expect(PlaytestMenuStandIn.action(for: key("-"), modifiers: [.command]) == .zoomOut)
        #expect(PlaytestMenuStandIn.action(for: key("0"), modifiers: [.command]) == .zoomToFit)
    }

    @Test("Delete on its own means dropping the piece of a recording")
    func deletePiece() {
        // Video ▸ Delete This Piece is window-scoped, so it is dimmed for the
        // whole of a walk like undo is. Both spellings of the key reach it.
        #expect(PlaytestMenuStandIn.action(for: key("delete"), modifiers: []) == .videoDeletePiece)
        #expect(PlaytestMenuStandIn.action(for: key("backspace"), modifiers: []) == .videoDeletePiece)
        // With a modifier it is a different chord: ⌘⌫ is Delete Layer.
        #expect(PlaytestMenuStandIn.action(for: key("delete"), modifiers: [.command]) == nil)
    }

    @Test("A chord with no stand-in says so rather than guessing")
    func unknown() {
        // Nothing should quietly stand in for a chord nobody wrote down: a
        // walk that meant something else would pass on the wrong command.
        #expect(PlaytestMenuStandIn.action(for: key("q"), modifiers: [.command]) == nil)
        #expect(PlaytestMenuStandIn.action(for: key("h"), modifiers: [.command, .shift]) == nil)
    }

    @Test("The same letter without command is not the chord")
    func modifiersMatter() {
        // "z" on its own is a tool shortcut in some apps and nothing here; it
        // must never reach undo.
        #expect(PlaytestMenuStandIn.action(for: key("z"), modifiers: []) == nil)
        #expect(PlaytestMenuStandIn.action(for: key("z"), modifiers: [.option]) == nil)
        #expect(PlaytestMenuStandIn.action(for: key("z"), modifiers: [.command, .option]) == nil)
    }

    private func key(_ name: String) -> PlaytestKey {
        guard let key = PlaytestKey(name) else {
            Issue.record("\(name) is not a key")
            return PlaytestKey.escape
        }
        return key
    }
}
