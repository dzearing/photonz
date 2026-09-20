import Foundation

/// The command a chord means, for the chords a walk cannot actually press.
///
/// macOS will not give a script-launched background process the front. Without
/// a focus event SwiftUI never re-evaluates its `Commands` body, so the probe's
/// menu bar stays frozen at the state it was built in at launch, when no
/// editor existed: every window-scoped item is dimmed with nothing behind it
/// for the whole walk, however the document changes. Pressing ⌘Z in a walk
/// therefore reports the frozen menu bar back at itself and says nothing at all
/// about undo.
///
/// The walk still means undo. So a chord carries a stand-in — the command a
/// person making that press would have run — and the harness runs it when the
/// menu item it found cannot run itself, saying so plainly in the log. What is
/// being worked around is the probe never coming to the front, which is a fact
/// about how a walk is launched rather than anything about the app.
///
/// Only chords written down here get one. A chord nobody listed fails the walk
/// as before, because a walk that quietly ran the wrong command would be worse
/// than one that stopped.
public enum PlaytestMenuStandIn {

    /// What this chord means, or nil when nothing stands in for it.
    ///
    /// The modifiers are compared as a set: the order a script happens to list
    /// them in is not meaning, and a chord with one modifier too many is a
    /// different chord, not a near miss.
    public static func action(for key: PlaytestKey, modifiers: [PlaytestModifier]) -> PlaytestAction? {
        table[Chord(key: key.name.lowercased(), modifiers: Set(modifiers))]
    }

    private struct Chord: Hashable {
        let key: String
        let modifiers: Set<PlaytestModifier>
    }

    /// Each entry is a command that lives on a window's menu, which is exactly
    /// the set the frozen menu bar kills. App-level commands (Capture, New
    /// Window, Open) are built live and stay live, so a walk can press those
    /// for real and none of them belong here.
    private static let table: [Chord: PlaytestAction] = [
        Chord(key: "z", modifiers: [.command]): .undo,
        // File > Save. It hangs off the focused window exactly as undo does, so
        // it is dimmed and empty for the whole of a walk; the stand-in saves
        // whichever kind of window is in front, which is what the item does.
        Chord(key: "s", modifiers: [.command]): .save,
        Chord(key: "z", modifiers: [.command, .shift]): .redo,
        Chord(key: "c", modifiers: [.command]): .copy,
        Chord(key: "c", modifiers: [.command, .shift]): .copyMerged,
        Chord(key: "x", modifiers: [.command]): .cut,
        Chord(key: "=", modifiers: [.command]): .zoomIn,
        Chord(key: "-", modifiers: [.command]): .zoomOut,
        Chord(key: "0", modifiers: [.command]): .zoomToFit,
        // Video ▸ Delete This Piece. Plain ⌫, and the only plain-key chord
        // here: the rest of the Video menu is live-built letters a walk can
        // press for real, but this one sits on a window-scoped item like undo.
        Chord(key: "delete", modifiers: []): .videoDeletePiece,
        Chord(key: "backspace", modifiers: []): .videoDeletePiece,
        // Layer ▸ Delete Layer and Edit ▸ Fill with Foreground. Both hang off
        // the editor the way undo does, so both are dimmed for the whole of a
        // walk and neither press can run its own row.
        Chord(key: "delete", modifiers: [.command]): .deleteLayer,
        Chord(key: "backspace", modifiers: [.command]): .deleteLayer,
        Chord(key: "delete", modifiers: [.option]): .fillWithForeground,
        Chord(key: "backspace", modifiers: [.option]): .fillWithForeground,
    ]
}
