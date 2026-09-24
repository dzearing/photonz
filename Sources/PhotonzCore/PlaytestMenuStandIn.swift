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
        // Layer ▸ Copy Look and Paste Look, and View ▸ Show Timing. All three
        // hang off the focused window like undo, so all three are dimmed and
        // empty for the whole of a walk: `copy-a-look-walk` and
        // `motion-timing-strip-walk` both pressed their chord, both were told
        // the item has no action behind it, and both stopped there once the
        // panel menus above them stopped refusing (2026-09-21).
        Chord(key: "c", modifiers: [.command, .option, .shift]): .copyLook,
        Chord(key: "v", modifiers: [.command, .option, .shift]): .pasteLook,
        Chord(key: "t", modifiers: [.command, .option]): .toggleTimingStrip,
        // View ▸ Mode ▸ … . The whole submenu hangs off the focused window like
        // undo, so a walk pressing ⌃2 is told the item has no action behind it
        // and stops there. The numbers are `WindowModes.shortcutNumber`, in the
        // order the chip's own list shows them.
        Chord(key: "1", modifiers: [.control]): .modeIcon,
        Chord(key: "2", modifiers: [.control]): .modeRedline,
        Chord(key: "3", modifiers: [.control]): .modeVideo,
        Chord(key: "4", modifiers: [.control]): .modeDesign,
        // Layer ▸ the four arrange rows. The stack is the composite order, so
        // these are the presses a compositing walk makes most, and every one of
        // them hangs off the focused window like undo.
        Chord(key: "]", modifiers: [.command, .shift]): .bringToFront,
        Chord(key: "]", modifiers: [.command]): .bringForward,
        Chord(key: "[", modifiers: [.command]): .sendBackward,
        Chord(key: "[", modifiers: [.command, .shift]): .sendToBack,
        // Video ▸ Go to Next Key and Go to Previous Key, the playhead from key
        // to key. Window-scoped like undo, so dimmed for the whole of a walk.
        Chord(key: "k", modifiers: [.shift]): .goToNextKey,
        Chord(key: "k", modifiers: [.option]): .goToPreviousKey,
    ]
}
