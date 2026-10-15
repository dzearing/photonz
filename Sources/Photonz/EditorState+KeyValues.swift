import CoreGraphics
import Foundation
import PhotonzCore

/// The key a key values popover hangs from: a key picked by a click on its
/// lane or on its graph.
struct KeyValuesAnchor: Equatable {
    var layerID: UUID
    var ref: KeyRef
}

/// What the popover hanging from `anchor` keeps off: the lines drawn on its
/// open graph, in points measured from the key's middle.
struct KeyValuesClear: Equatable {
    var anchor: KeyValuesAnchor
    var lines: [[CGPoint]]

    /// The lines in the same space as `keyFrame`, the key's drawn frame.
    func lines(around keyFrame: CGRect) -> [[CGPoint]] {
        lines.map { $0.map { CGPoint(x: $0.x + keyFrame.midX, y: $0.y + keyFrame.midY) } }
    }
}

/// A click on a key opens a popover above it with that value at the key, to
/// type (Next, `next-key-values`; `KeyValuesPopover`; the placement
/// contract's "Named exception: the transform values", the key overlay).
///
/// It is the transform values popover's kind, anchored to the key and never
/// over it: one row per value the picked keys hold, in its own units, Mixed
/// where they differ, and Reset to the value's default. Easing is not here: it
/// stays in the timeline bar while keys are picked and on a key's right click.
/// Escape, a click anywhere else, another tool, typing, a menu or Play close
/// it. Every value it lands goes through `perform`, one undo step each.
@MainActor
extension EditorState {

    // MARK: Up and down

    /// Whether the popover is on screen: its key is still picked, the hand is
    /// not carrying keys, and nothing is playing.
    var showsKeyValues: Bool {
        guard Experiments.shared.keyValuesEnabled, let anchor = keyValuesAnchor,
              let keySelection, keySelection.layerID == anchor.layerID,
              keySelection.refs.contains(anchor.ref), keyLaneDrag == nil,
              !isDocumentPlaying, !isWatching, documentHasTime else { return false }
        return !keyValueRows.isEmpty
    }

    /// A click on a key just picked it: the popover opens above it. A click
    /// that took the key out of the pick leaves nothing to hang it from.
    func openKeyValues(layerID: UUID, at ref: KeyRef) {
        guard Experiments.shared.keyValuesEnabled, !isClipLocked(layerID),
              pickedKeys(layerID: layerID).contains(ref) else {
            dropKeyValues()
            return
        }
        // One popover at a time: the transform values make way.
        dropTransformBar()
        let anchor = KeyValuesAnchor(layerID: layerID, ref: ref)
        if keyValuesAnchor != anchor { keyValuesAnchor = anchor }
    }

    func dropKeyValues() {
        if keyValuesAnchor != nil { keyValuesAnchor = nil }
        if keyValuesClear != nil { keyValuesClear = nil }
        if keyValuesPopoverFrame != nil { keyValuesPopoverFrame = nil }
    }

    /// Escape: closes the popover and nothing else, so the keys stay picked.
    /// False when it was not open.
    func escapeKeyValues() -> Bool {
        guard showsKeyValues else { return false }
        dropKeyValues()
        return true
    }

    /// What the open popover keeps off, in window points: the curve and
    /// handles of the graph its key sits on; nothing on a shut lane.
    var keyValuesClearLines: [[CGPoint]] {
        guard let anchor = keyValuesAnchor, let frame = keyValuesAnchorFrame,
              let clear = keyValuesClear, clear.anchor == anchor else { return [] }
        return clear.lines(around: frame)
    }

    // MARK: What it shows

    /// One row per value the picked keys hold, in the lanes' order.
    var keyValueRows: [KeyValueRow] {
        guard let keySelection, let document else { return [] }
        return document.keyValueRows(layerID: keySelection.layerID, keySelection.refs)
    }

    /// Whether Reset would change anything.
    var canResetKeyValues: Bool {
        guard let keySelection, let document, !isClipLocked(keySelection.layerID) else { return false }
        return document.canResetKeyValues(layerID: keySelection.layerID, keySelection.refs)
    }

    // MARK: Typing

    /// A value typed into a row: every picked key of that value takes it, one
    /// undo step. Hands back what the keys now read.
    @discardableResult
    func setKeyValue(motionID: UUID, _ edit: KeyValueEdit) -> KeyValueReading? {
        guard let keySelection, !isClipLocked(keySelection.layerID) else { return nil }
        let layerID = keySelection.layerID, refs = keySelection.refs
        guard var trial = document,
              trial.setKeyValues(layerID: layerID, refs, motionID: motionID, edit) else {
            return keyValueRows.first { $0.motionID == motionID }?.value
        }
        perform { $0.setKeyValues(layerID: layerID, refs, motionID: motionID, edit) }
        return keyValueRows.first { $0.motionID == motionID }?.value
    }

    /// Reset: the picked keys go to their values' defaults, one undo step.
    func resetKeyValues() {
        guard canResetKeyValues, let keySelection else { return }
        let layerID = keySelection.layerID, refs = keySelection.refs
        perform { $0.resetKeyValues(layerID: layerID, refs) }
    }
}
