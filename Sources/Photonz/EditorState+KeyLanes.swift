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
        return document.hasKeyLanes(anyOf: Set(layerIDs))
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
        if let property = document?.layer(id: layerID)?.motions?.first(where: { $0.id == ref.motionID })?.property {
            activeKeyProperty = .motion(property)
        }
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
        rows.append(.command(refs.count == 1 ? "Copy Key" : "Copy \(refs.count) Keys", KeyClipboardKeys.copy) {
            self.copyKeys(layerID: layerID, refs)
        })
        rows.append(pasteKeysRow(layerID: layerID))
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
        rows.append(pasteKeysRow(layerID: layerID))
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

    // MARK: Copy and paste

    /// The keys the copy and paste rows print: the Edit menu's own.
    enum KeyClipboardKeys {
        static let copy = MenuShortcut.command("c")
        static let paste = MenuShortcut.command("v")
    }

    /// Whether ⌘C means keys: some are picked on the layer in hand.
    var canCopyPickedKeys: Bool {
        guard documentHasTime, let keySelection, !keySelection.refs.isEmpty,
              selectedLayerID == keySelection.layerID else { return false }
        return true
    }

    /// ⌘C with keys picked: those keys go on the clipboard, and the layer
    /// does not. False where no keys are picked, so ⌘C copies what it always
    /// did.
    @discardableResult
    func copyPickedKeys() -> Bool {
        guard canCopyPickedKeys, let keys = keySelection else { return false }
        return copyKeys(layerID: keys.layerID, keys.refs)
    }

    @discardableResult
    func copyKeys(layerID: UUID, _ refs: Set<KeyRef>) -> Bool {
        guard let copied = document?.copyKeys(layerID: layerID, refs),
              let data = try? JSONEncoder().encode(copied) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(CopiedKeys.pasteboardType))
        return true
    }

    /// ⌘X with keys picked: copied, then gone.
    @discardableResult
    func cutPickedKeys() -> Bool {
        guard canDeletePickedKeys, copyPickedKeys() else { return false }
        return deletePickedKeys()
    }

    /// The keys on the clipboard, where the last thing copied was keys.
    var keysOnClipboard: CopiedKeys? {
        guard let data = NSPasteboard.general.data(forType: NSPasteboard.PasteboardType(CopiedKeys.pasteboardType))
        else { return nil }
        return try? JSONDecoder().decode(CopiedKeys.self, from: data)
    }

    /// Whether ⌘V means keys onto this layer (the picked one where nil): keys
    /// on the clipboard, and a value of theirs the layer has.
    func canPasteKeys(onto layerID: UUID? = nil) -> Bool {
        guard documentHasTime, let id = layerID ?? pickedLayerID, !isClipLocked(id),
              let copied = keysOnClipboard, let document else { return false }
        return document.canPasteKeys(copied, layerID: id)
    }

    /// ⌘V with keys on the clipboard: they land at the playhead on the
    /// picked layer, earliest first, as one undo step, and are what is picked
    /// afterwards. A playhead off the clip pastes at the clip's nearer end, so
    /// no key lands where nothing can show it. False where nothing landed, so
    /// ⌘V pastes what it always did.
    @discardableResult
    func pasteKeysAtPlayhead(onto layerID: UUID? = nil) -> Bool {
        guard let id = layerID ?? pickedLayerID, canPasteKeys(onto: id),
              let copied = keysOnClipboard, let layer = document?.layer(id: id) else { return false }
        var at = documentTimeMS
        if let time = layer.time { at = min(max(at, time.inMS), max(time.inMS, time.outMS - 1)) }
        if selectedLayerID != id { selectLayer(id) }
        var landed = Set<KeyRef>()
        perform { landed = $0.pasteKeys(copied, layerID: id, atDocumentMS: at) }
        guard !landed.isEmpty else { return false }
        if let track = document?.trackID(ofClip: id) { closedKeyTracks.remove(track) }
        keySelection = KeySelection(layerID: id, refs: landed)
        return true
    }

    /// Paste Keys, on the menus of the things keys land on.
    func pasteKeysRow(layerID: UUID) -> MenuRow {
        let count = keysOnClipboard?.keys.count ?? 0
        return .command(count > 1 ? "Paste \(count) Keys" : "Paste Keys", KeyClipboardKeys.paste,
                        enabled: canPasteKeys(onto: layerID)) {
            self.pasteKeysAtPlayhead(onto: layerID)
        }
    }

    // MARK: The playhead on keys

    /// How close, in points, a dragged playhead has to come to a key to be
    /// pulled onto it. About a diamond's width.
    static let keySnapPoints: CGFloat = 8

    /// How much of the timeline's clock `keySnapPoints` spans on a lane
    /// `laneWidth` wide, at the zoom it is at.
    func keySnapReachMS(laneWidth: CGFloat) -> Int {
        guard laneWidth > 0 else { return 0 }
        let ruler = motionStripRuler
        let span = ruler.ms(atFraction: Double(Self.keySnapPoints / laneWidth)) - ruler.ms(atFraction: 0)
        return max(0, Int(span.rounded()))
    }

    /// A playhead dragged across the timeline: pulled onto a key within
    /// `reachMS` of the hand, the way Premiere's playhead catches keyframes.
    func dragPlayhead(toMS ms: Int, snappingWithinMS reachMS: Int) {
        guard reachMS > 0, let document = shownDocument ?? document else {
            dragPlayhead(toMS: ms)
            return
        }
        dragPlayhead(toMS: KeySnap.snapped(ms, to: document.keyMoments(layerIDs: nil), withinMS: reachMS))
    }

    /// The layers ⇧K and ⌥K step across: the picked one, or every layer.
    private var keyStepLayers: [UUID]? { pickedLayerID.map { [$0] } }

    func canGoToKey(forward: Bool) -> Bool {
        guard documentHasTime, let document else { return false }
        return document.neighbourKeyMoment(layerIDs: keyStepLayers, from: documentTimeMS,
                                           forward: forward) != nil
    }

    /// ⇧K and ⌥K: the playhead to the next or previous key of the picked
    /// layer, or of anything where nothing is picked.
    func goToKey(forward: Bool) {
        guard documentHasTime, let document,
              let moment = document.neighbourKeyMoment(layerIDs: keyStepLayers, from: documentTimeMS,
                                                       forward: forward) else { return }
        if isDocumentPlaying { pauseDocument() }
        scrubDocument(toMS: moment)
    }
}
