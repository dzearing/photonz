import AppKit
import Foundation
import PhotonzCore

/// The keys picked on one layer's lanes.
struct KeySelection: Equatable {
    var layerID: UUID
    var refs: Set<KeyRef>
}

/// Picked keys being dragged along their lanes: how far, and whether Option
/// is making copies rather than moving them.
struct KeyLaneDrag: Equatable {
    var layerID: UUID
    var byMS: Int
    var copying: Bool
}

/// A layer's track opens into one lane per keyed value
/// (`a-layer-s-track-opens-into-one-lane-per-keyed-va`, `KeyLanes.swift`).
///
/// A thin layer over the model: every change goes through `perform`, so a
/// drag, a copy, a delete, an ease and a handle each cost one undo step.
extension EditorState {

    // MARK: What is drawn

    /// The lanes of a layer, as the timeline is showing it.
    func keyLanes(layerID: UUID) -> [KeyLane] {
        guard documentHasTime, let document = shownDocument ?? document else { return [] }
        return document.keyLanes(layerID: layerID)
    }

    /// Whether any clip on a track has a value keyed: the arrow on its header.
    func trackHasKeyLanes(_ layerIDs: [UUID]) -> Bool {
        guard documentHasTime, let document else { return false }
        return layerIDs.contains { document.hasKeyLanes(layerID: $0) }
    }

    func isKeyTrackOpen(_ trackID: UUID) -> Bool { !closedKeyTracks.contains(trackID) }

    /// The arrow on a track's header.
    func toggleKeyTrack(_ trackID: UUID) {
        if closedKeyTracks.contains(trackID) {
            closedKeyTracks.remove(trackID)
        } else {
            closedKeyTracks.insert(trackID)
        }
    }

    /// The curve a lane opens into, drawn with a handle drag still in the air
    /// where there is one.
    func keyGraph(layerID: UUID, motionID: UUID,
                  handle: (ref: KeyRef, side: KeyHandleSide, point: CGPoint)? = nil) -> KeyGraph? {
        guard var document = shownDocument ?? document else { return nil }
        if let handle {
            document.setKeyHandle(layerID: layerID, handle.ref, handle.side, toGraphPoint: handle.point)
        }
        return document.keyGraph(layerID: layerID, motionID: motionID)
    }

    func isKeyLaneGraphed(_ motionID: UUID) -> Bool { graphedKeyLanes.contains(motionID) }

    func toggleKeyGraph(_ motionID: UUID) {
        if graphedKeyLanes.contains(motionID) {
            graphedKeyLanes.remove(motionID)
        } else {
            graphedKeyLanes.insert(motionID)
        }
    }

    /// The Animating header's Graph link: the picked layer's first value that
    /// has a curve, opened on its lane with its track opened too.
    func openGraphForPickedLayer() {
        guard let id = selectedLayerID, let document else { return }
        let lanes = keyLanes(layerID: id)
        guard let lane = lanes.first(where: { document.keyGraph(layerID: id, motionID: $0.motionID) != nil })
        else { return }
        if let track = document.trackID(ofClip: id) { closedKeyTracks.remove(track) }
        graphedKeyLanes.insert(lane.motionID)
    }

    // MARK: Picking

    func pickedKeys(layerID: UUID) -> Set<KeyRef> {
        guard let keySelection, keySelection.layerID == layerID else { return [] }
        return keySelection.refs
    }

    /// A click on a key: it alone is picked and the playhead goes to it, so
    /// the panel's diamonds say what is keyed there. Shift or Command adds it
    /// to what is picked, or takes it out.
    func pickKey(layerID: UUID, _ ref: KeyRef, atMS ms: Int, extending: Bool) {
        if selectedLayerID != layerID { selectLayer(layerID) }
        if extending {
            var refs = pickedKeys(layerID: layerID)
            if refs.contains(ref) { refs.remove(ref) } else { refs.insert(ref) }
            keySelection = refs.isEmpty ? nil : KeySelection(layerID: layerID, refs: refs)
            return
        }
        keySelection = KeySelection(layerID: layerID, refs: [ref])
        if isDocumentPlaying { pauseDocument() }
        scrubDocument(toMS: ms)
    }

    /// A box drawn round keys: those are picked, added to what already is
    /// where Shift is held.
    func pickKeys(layerID: UUID, _ refs: Set<KeyRef>, extending: Bool) {
        if selectedLayerID != layerID { selectLayer(layerID) }
        let all = extending ? pickedKeys(layerID: layerID).union(refs) : refs
        keySelection = all.isEmpty ? nil : KeySelection(layerID: layerID, refs: all)
    }

    func clearKeySelection() {
        if keySelection != nil { keySelection = nil }
    }

    // MARK: Dragging

    /// A key taken hold of. One nobody had picked is picked alone first, the
    /// way a drag on an unselected clip takes that clip.
    func beginKeyDrag(layerID: UUID, grabbing ref: KeyRef) {
        guard !isClipLocked(layerID) else { return }
        if !pickedKeys(layerID: layerID).contains(ref) {
            if selectedLayerID != layerID { selectLayer(layerID) }
            keySelection = KeySelection(layerID: layerID, refs: [ref])
        }
        keyLaneDrag = KeyLaneDrag(layerID: layerID, byMS: 0, copying: false)
    }

    func updateKeyDrag(byMS ms: Int, copying: Bool) {
        guard var drag = keyLaneDrag else { return }
        drag.byMS = ms
        drag.copying = copying
        keyLaneDrag = drag
    }

    /// Let go: the picked keys land (or their copies do), as one undo step,
    /// and what landed is what is picked.
    func commitKeyDrag() {
        guard let drag = keyLaneDrag else { return }
        keyLaneDrag = nil
        let refs = pickedKeys(layerID: drag.layerID)
        guard drag.byMS != 0, !refs.isEmpty else { return }
        moveKeys(layerID: drag.layerID, refs, byMS: drag.byMS, copying: drag.copying)
    }

    func cancelKeyDrag() { keyLaneDrag = nil }

    func moveKeys(layerID: UUID, _ refs: Set<KeyRef>, byMS ms: Int, copying: Bool) {
        guard !isClipLocked(layerID) else { return }
        var landed = refs
        perform { landed = $0.moveKeys(layerID: layerID, refs, byMS: ms, copying: copying) }
        keySelection = KeySelection(layerID: layerID, refs: landed)
    }

    // MARK: Deleting and easing

    /// Whether ⌫ means these keys: some are picked on the layer in hand.
    var canDeletePickedKeys: Bool {
        guard documentHasTime, let keySelection, !keySelection.refs.isEmpty,
              selectedLayerID == keySelection.layerID,
              !isClipLocked(keySelection.layerID) else { return false }
        return true
    }

    /// ⌫ with keys picked: those keys go, and the layer stays.
    @discardableResult
    func deletePickedKeys() -> Bool {
        guard canDeletePickedKeys, let keys = keySelection else { return false }
        keySelection = nil
        perform { $0.removeKeys(layerID: keys.layerID, keys.refs) }
        return true
    }

    /// What a right click on a key acts on: everything picked where the key
    /// is among it, and the key alone where it is not.
    private func keysInHand(layerID: UUID, _ ref: KeyRef) -> Set<KeyRef> {
        let picked = pickedKeys(layerID: layerID)
        return picked.contains(ref) ? picked : [ref]
    }

    func easeKeys(layerID: UUID, _ refs: Set<KeyRef>, _ ease: KeyEase) {
        guard !isClipLocked(layerID) else { return }
        if selectedLayerID != layerID { selectLayer(layerID) }
        perform { $0.easeKeys(layerID: layerID, refs, ease) }
    }

    /// A right click on a key: Premiere's ways a value moves through a key,
    /// ticked where every key in hand agrees, then the curve, then Delete.
    func keyMenuRows(layerID: UUID, _ ref: KeyRef, atMS ms: Int) -> [MenuRow] {
        guard let document, !isClipLocked(layerID) else { return [] }
        let refs = keysInHand(layerID: layerID, ref)
        let current = document.keysEase(layerID: layerID, refs)
        var rows: [MenuRow] = KeyEase.allCases.map { ease in
            .toggle(ease.title, isOn: current == ease) {
                self.easeKeys(layerID: layerID, refs, ease)
            }
        }
        rows.append(.separator)
        rows.append(contentsOf: graphRows(layerID: layerID, motionID: ref.motionID))
        rows.append(.command("Go to Key") { self.pickKey(layerID: layerID, ref, atMS: ms, extending: false) })
        rows.append(.separator)
        rows.append(.command(refs.count == 1 ? "Delete Key" : "Delete \(refs.count) Keys", destructive: true) {
            self.keySelection = nil
            self.perform { $0.removeKeys(layerID: layerID, refs) }
        })
        return rows
    }

    /// A right click on a lane, off its keys.
    func keyLaneMenuRows(layerID: UUID, motionID: UUID) -> [MenuRow] {
        guard !isClipLocked(layerID) else { return graphRows(layerID: layerID, motionID: motionID) }
        let lane = keyLanes(layerID: layerID).first { $0.motionID == motionID }
        var rows = graphRows(layerID: layerID, motionID: motionID)
        rows.append(.command("Select All Keys") {
            self.pickKeys(layerID: layerID, Set(lane?.keys.map(\.ref) ?? []), extending: false)
        })
        return rows
    }

    private func graphRows(layerID: UUID, motionID: UUID) -> [MenuRow] {
        guard document?.keyGraph(layerID: layerID, motionID: motionID) != nil else { return [] }
        return [.toggle("Show Graph", isOn: isKeyLaneGraphed(motionID)) { self.toggleKeyGraph(motionID) }]
    }

    // MARK: Handles

    /// A handle let go on the curve: the key becomes a Bezier key shaped by
    /// where it landed. One undo step.
    func setKeyHandle(layerID: UUID, _ ref: KeyRef, _ side: KeyHandleSide, toGraphPoint point: CGPoint) {
        guard !isClipLocked(layerID) else { return }
        if selectedLayerID != layerID { selectLayer(layerID) }
        perform { $0.setKeyHandle(layerID: layerID, ref, side, toGraphPoint: point) }
    }
}
