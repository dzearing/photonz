import AppKit
import Foundation
import PhotonzCore

// Copy, cut and paste a range of time (`RangeClipboard.swift`).
//
// With a range drawn on the ruler in hand, ⌘C copies that stretch of every
// track, ⌘X copies it and takes it out with the gap closed, and ⌘V lays it
// back in at the playhead on the tracks it came off, covering what is there.
// The playhead then waits at the end of what landed, so pressing ⌘V again
// lays the next copy straight after it, as in Premiere and Final Cut.

extension EditorState {

    enum RangeClipboardKeys {
        static let cut = MenuShortcut.command("x")
        static let copy = MenuShortcut.command("c")
    }

    // MARK: The Edit menu's three

    /// Edit ▸ Copy: keys picked on a lane, else a range in hand, else the
    /// layer (`copySelectedLayer`).
    func copyWhatIsInHand() {
        if copyPickedKeys() { return }
        if rulerRangeHeld != nil, copyMarkedRange() { return }
        copySelectedLayer()
    }

    /// Edit ▸ Cut, in the same order.
    func cutWhatIsInHand() {
        if cutPickedKeys() { return }
        if rulerRangeHeld != nil, cutMarkedRange() { return }
        cutSelectedLayer()
    }

    /// Edit ▸ Paste: keys onto the picked layer, else a copied range at the
    /// playhead, else a layer or a picture (`paste`).
    func pasteWhatIsOnTheClipboard() {
        if pasteKeysAtPlayhead() { return }
        if pasteRange() { return }
        paste()
    }

    // MARK: Copy and cut

    /// Whether the marked stretch has anything in it to copy or cut: the same
    /// answer Delete and Ripple Delete give.
    var canCopyMarkedRange: Bool {
        documentHasTime && canTakeOutMarkedStretch
    }

    /// The marked stretch of every track onto the clipboard. False where
    /// nothing is marked or nothing runs through it.
    @discardableResult
    func copyMarkedRange() -> Bool {
        guard documentHasTime, let range = document?.markedRangeMS,
              let copied = document?.copyRange(range) else { return false }
        return putOnClipboard(copied)
    }

    /// The marked stretch copied, then taken out of every track with the gap
    /// closed, as one step to undo.
    @discardableResult
    func cutMarkedRange() -> Bool {
        guard canCopyMarkedRange, var trial = document, let copied = trial.cutMarkedStretch(),
              putOnClipboard(copied) else { return false }
        endTrimBeforeCutting()
        pauseDocument()
        perform { _ = $0.cutMarkedStretch() }
        selectedClipPieceIndex = nil
        rulerRangeInHand = nil
        documentMomentChanged()
        return true
    }

    private func putOnClipboard(_ copied: CopiedRange) -> Bool {
        var copied = copied
        copied.origin = rangeClipboardOrigin
        guard let data = try? JSONEncoder().encode(copied) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(CopiedRange.pasteboardType))
        return true
    }

    // MARK: Paste

    /// The range on the clipboard, where the last thing copied was a range
    /// in this window.
    var rangeOnClipboard: CopiedRange? {
        guard documentHasTime,
              let data = NSPasteboard.general.data(forType: NSPasteboard.PasteboardType(CopiedRange.pasteboardType)),
              let copied = try? JSONDecoder().decode(CopiedRange.self, from: data),
              copied.origin == rangeClipboardOrigin else { return nil }
        return copied
    }

    /// The copied range laid in at `ms` (the playhead where nil), as one step
    /// to undo. What landed is picked and the playhead waits at its end.
    /// False where there was no range to paste, so ⌘V pastes what it always
    /// did.
    @discardableResult
    func pasteRange(atMS ms: Int? = nil) -> Bool {
        guard let copied = rangeOnClipboard else { return false }
        let at = ms ?? documentTimeMS
        endTrimBeforeCutting()
        pauseDocument()
        var landed: [UUID] = []
        perform { landed = $0.pasteRange(copied, atMS: at) }
        selectedClipPieceIndex = nil
        rulerRangeInHand = nil
        selectLayers(Set(landed))
        scrubDocument(toMS: at + copied.lengthMS)
        documentMomentChanged()
        return true
    }

    /// Paste, on the ruler's menu: the copied range, laid in where the right
    /// click landed.
    func pasteRangeRow(atMS ms: Int) -> MenuRow? {
        guard rangeOnClipboard != nil else { return nil }
        return .command("Paste", KeyClipboardKeys.paste) { self.pasteRange(atMS: ms) }
    }
}
