import Foundation
import PhotonzCore

// When a title is on screen (`TitleTime.swift`,
// `docs/design/mocks/pages/video-title-wt.html`).
//
// Everything here is about a layer that is simply PLACED in time — a title, a
// mark on a held frame — as against one that PLAYS. There is no title object
// and no titles panel: this is the handful of things the Time section and the
// timeline need to ask about the words in your hand.
//
// The direct way to say when a title comes on and goes off is the bar in the
// timeline, and that needs nothing here: both its ends are draggable already
// (`EditorState+ClipBar`). The bar's right-click menu is the other way round,
// for the moment you are already looking at: put the playhead on the frame the
// words should arrive on and choose Start at Playhead.
extension EditorState {

    /// The layer whose in and out the Time section speaks for: the picked one,
    /// where it is placed in time rather than played.
    var placedLayerInHand: Layer? {
        guard Experiments.shared.titleOnTheTimelineEnabled
                || Experiments.shared.componentOnTheTimelineEnabled
                || Experiments.shared.drawnOnTheTimelineEnabled,
              documentHasTime,
              let id = selectedLayerID, let layer = document?.layer(id: id),
              layer.isPlacedInTime else { return nil }
        return layer
    }

    /// The moment something placed right now should arrive at, or nil where
    /// this document has no time in it and nothing is placed in time at all.
    ///
    /// One answer for every way a thing arrives — dragged off the shelf,
    /// double clicked on a tile, inserted from the menu — so a component can
    /// never land knowing when it is on screen by one route and not by
    /// another.
    var placementMomentMS: Int? {
        guard Experiments.shared.componentOnTheTimelineEnabled, documentHasTime else { return nil }
        return documentTimeMS
    }

    /// `0:02 to 0:05 · 3.0s`, for the panel and for a walk to read.
    var placedLayerReading: String? {
        placedLayerInHand?.time.map { TitleTime.reading($0) }
    }

    /// A layer placed in time that the timeline's verbs may act on, whichever
    /// layer happens to be picked: the one a right click was opened on.
    private func placedLayer(_ id: UUID) -> Layer? {
        guard Experiments.shared.titleOnTheTimelineEnabled
                || Experiments.shared.componentOnTheTimelineEnabled
                || Experiments.shared.drawnOnTheTimelineEnabled,
              documentHasTime, !isClipLocked(id),
              let layer = document?.layer(id: id), layer.isPlacedInTime else { return nil }
        return layer
    }

    /// Whether the playhead is somewhere this layer's in point could go.
    func canStartPlacedLayerHere(_ id: UUID) -> Bool {
        placedLayer(id)?.canStartPlaced(atMS: documentTimeMS) == true
    }

    func canEndPlacedLayerHere(_ id: UUID) -> Bool {
        placedLayer(id)?.canEndPlaced(atMS: documentTimeMS) == true
    }

    /// Arrive at the playhead, leaving where it goes alone.
    func startPlacedLayerHere(_ id: UUID) {
        guard canStartPlacedLayerHere(id) else { return }
        selectLayer(id)
        pauseDocument()
        let moment = documentTimeMS
        perform { $0.moveLayerStart(id, toMS: moment) }
        documentMomentChanged()
    }

    /// Go at the playhead, leaving where it arrives alone.
    func endPlacedLayerHere(_ id: UUID) {
        guard canEndPlacedLayerHere(id) else { return }
        selectLayer(id)
        pauseDocument()
        let moment = documentTimeMS
        perform { $0.moveLayerEnd(id, toMS: moment) }
        documentTimeMS = min(documentTimeMS, lastDocumentTimeMS)
        documentMomentChanged()
    }

    /// How long the words take to come on and go off again, where they do.
    var placedLayerFadeMS: Int { placedLayerInHand?.titleFadeMS ?? 0 }

    func canSetPlacedLayerFade(_ ms: Int) -> Bool {
        guard let id = placedLayerInHand?.id else { return false }
        return canSetPlacedLayerFade(ms, layerID: id)
    }

    func canSetPlacedLayerFade(_ ms: Int, layerID id: UUID) -> Bool {
        placedLayer(id)?.canSetTitleFade(toMS: ms) == true
    }

    func setPlacedLayerFade(_ ms: Int) {
        guard let id = placedLayerInHand?.id else { return }
        setPlacedLayerFade(ms, layerID: id)
    }

    /// Write the fade, which is an ordinary Opacity motion and nothing else
    /// (`TitleTime.fade`).
    func setPlacedLayerFade(_ ms: Int, layerID id: UUID) {
        guard canSetPlacedLayerFade(ms, layerID: id) else { return }
        selectLayer(id)
        perform { $0.setTitleFade(id, toMS: ms) }
        documentMomentChanged()
    }

    /// **Start at Playhead**, **End at Playhead** and **Fade ▸**: what the
    /// bar of something placed in time offers on a right click. A row the
    /// playhead gives nowhere to go is dimmed, as Split at Playhead is, since
    /// the reason is the playhead you can see.
    func placedLayerMenuRows(layerID id: UUID) -> [MenuRow] {
        guard let layer = placedLayer(id) else { return [] }
        let fade = layer.titleFadeMS ?? 0
        return [
            .command("Start at Playhead", enabled: canStartPlacedLayerHere(id)) {
                self.startPlacedLayerHere(id)
            },
            .command("End at Playhead", enabled: canEndPlacedLayerHere(id)) {
                self.endPlacedLayerHere(id)
            },
            .submenu("Fade", TitleTime.fadeStopsMS.map { ms in
                .toggle(TitleTime.fadeTitle(ms), isOn: ms == fade) {
                    self.setPlacedLayerFade(ms, layerID: id)
                }
            }),
        ]
    }
}
