import Foundation
import PhotonzCore

/// A layer's track shows only what is animated
/// (`a-layer-s-track-shows-only-what-is-animated-and`, `KeyMoments.swift`,
/// `video-animate.html`, "A track lists only what is animated").
///
/// A row under a track is a value that has keys and nothing else. Click its
/// name to pick it and ⌫ stops it animating; Animate ▸ on the clip, on a key
/// of its key line, and in Clip ▸ Animate brings one back. Every change goes
/// through `perform`, so each is one step to undo.
extension EditorState {

    // MARK: A picked row

    /// The row picked by a click on its name, while its layer is the one in
    /// hand and no keys are picked instead.
    var keyRowInHand: KeyLaneRowID? {
        guard let row = pickedKeyRow, documentHasTime, selectedLayerID == row.layerID,
              keySelection == nil, !isClipLocked(row.layerID),
              keyLanes(layerID: row.layerID).contains(where: { $0.motionID == row.motionID }) else { return nil }
        return row
    }

    func isKeyRowPicked(layerID: UUID, motionID: UUID) -> Bool {
        keyRowInHand == KeyLaneRowID(layerID: layerID, motionID: motionID)
    }

    /// A click on a row's name: the row is picked, and the keys are not.
    func pickKeyRow(layerID: UUID, motionID: UUID) {
        if selectedLayerID != layerID { selectLayer(layerID) }
        clearKeySelection()
        if let property = document?.layer(id: layerID)?.motions?.first(where: { $0.id == motionID })?.property {
            activeKeyProperty = .motion(property)
        }
        pickedKeyRow = KeyLaneRowID(layerID: layerID, motionID: motionID)
    }

    /// ⌫ with a row picked, and the row's Stop Animating: every key on it
    /// goes in one undo step, the row leaves, and the value stays what it is
    /// at the playhead.
    func stopAnimatingRow(layerID: UUID, motionID: UUID) {
        guard !isClipLocked(layerID),
              let motion = document?.layer(id: layerID)?.motions?.first(where: { $0.id == motionID }) else { return }
        let property = KeyedProperty.motion(motion.property, effect: motion.effectOrdinal)
        let time = documentTimeMS
        if pickedKeyRow?.motionID == motionID { pickedKeyRow = nil }
        if activeKeyProperty == property { activeKeyProperty = nil }
        graphedKeyLanes.remove(motionID)
        perform { $0.stopKeying(layerID: layerID, property, atDocumentTimeMS: time) }
    }

    /// ⌫ on the row in hand. False where no row is picked.
    @discardableResult
    func stopAnimatingRowInHand() -> Bool {
        guard let row = keyRowInHand else { return false }
        stopAnimatingRow(layerID: row.layerID, motionID: row.motionID)
        return true
    }

    // MARK: Animate ▸

    /// Animate ▸ a value: one key at the playhead holding the value it has
    /// now, and its row appears under the track, opened.
    func animate(_ property: KeyedProperty, layerID: UUID) {
        guard !isClipLocked(layerID) else { return }
        if selectedLayerID != layerID { selectLayer(layerID) }
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        if isDocumentPlaying { pauseDocument() }
        activeKeyProperty = property
        perform { $0.animate(layerID: layerID, property, atDocumentTimeMS: time, ease: ease) }
        if let track = document?.trackID(ofClip: layerID) { closedKeyTracks.remove(track) }
    }

    /// What Animate ▸ lists on a layer: every value it can key that is not
    /// animating, under the panel's groups. Empty for a sound.
    func animateGroups(layerID: UUID) -> [(group: AnimateGroup, properties: [KeyedProperty])] {
        guard documentHasTime, let layer = document?.layer(id: layerID), !layer.isSoundOnly else { return [] }
        let animating = Set(keyLanes(layerID: layerID).map { KeyedProperty.motion($0.property, effect: $0.effect) })
        return layer.animateGroups(excluding: animating)
    }

    /// The Animate ▸ row of a clip's menu and a key's, nil where the clip is
    /// locked or has nothing to animate.
    func animateMenuRow(layerID: UUID) -> MenuRow? {
        guard !isClipLocked(layerID), let layer = document?.layer(id: layerID) else { return nil }
        let groups = animateGroups(layerID: layerID)
        guard !groups.isEmpty else { return nil }
        return .submenu("Animate", groups.map { entry in
            .section(entry.group.title, entry.properties.map { property in
                .command(property.title(on: layer)) {
                    // The named command (`AppCommandRunner`), on this layer.
                    if self.selectedLayerID != layerID { self.selectLayer(layerID) }
                    self.run(.animateProperty, ["property": .string(property.title(on: layer))])
                }
            })
        })
    }
}
