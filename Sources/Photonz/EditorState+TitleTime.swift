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
// (`EditorState+ClipBar`). These two buttons are the other way round, for the
// moment you are already looking at — put the playhead on the frame the words
// should arrive on and say Start Here.
extension EditorState {

    /// The layer whose in and out the Time section speaks for: the picked one,
    /// where it is placed in time rather than played.
    var placedLayerInHand: Layer? {
        guard Experiments.shared.titleOnTheTimelineEnabled
                || Experiments.shared.componentOnTheTimelineEnabled,
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

    /// Whether the playhead is somewhere the in point could go: inside the
    /// document and not on top of the out.
    var canStartPlacedLayerHere: Bool {
        guard let time = placedLayerInHand?.time else { return false }
        return documentTimeMS != time.inMS && documentTimeMS <= time.outMS - LayerTime.shortestMS
    }

    var canEndPlacedLayerHere: Bool {
        guard let time = placedLayerInHand?.time else { return false }
        return documentTimeMS != time.outMS && documentTimeMS >= time.inMS + LayerTime.shortestMS
    }

    /// Arrive at the playhead, leaving where it goes alone.
    func startPlacedLayerHere() {
        guard canStartPlacedLayerHere, let id = placedLayerInHand?.id else { return }
        pauseDocument()
        let moment = documentTimeMS
        perform { $0.moveLayerStart(id, toMS: moment) }
        documentMomentChanged()
    }

    /// Go at the playhead, leaving where it arrives alone.
    func endPlacedLayerHere() {
        guard canEndPlacedLayerHere, let id = placedLayerInHand?.id else { return }
        pauseDocument()
        let moment = documentTimeMS
        perform { $0.moveLayerEnd(id, toMS: moment) }
        documentTimeMS = min(documentTimeMS, lastDocumentTimeMS)
        documentMomentChanged()
    }

    /// How long the words take to come on and go off again, where they do.
    var placedLayerFadeMS: Int { placedLayerInHand?.titleFadeMS ?? 0 }

    func canSetPlacedLayerFade(_ ms: Int) -> Bool {
        guard let layer = placedLayerInHand, let time = layer.time else { return false }
        guard ms != placedLayerFadeMS else { return false }
        // Nought is always available as the way back; any other length needs
        // room for the words to be fully up somewhere in the middle.
        return ms == 0 || TitleTime.fade(overMS: ms, lengthMS: time.lengthMS) != nil
    }

    /// Write the fade, which is an ordinary Opacity motion and nothing else
    /// (`TitleTime.fade`).
    func setPlacedLayerFade(_ ms: Int) {
        guard canSetPlacedLayerFade(ms), let id = placedLayerInHand?.id else { return }
        perform { $0.setTitleFade(id, toMS: ms) }
        documentMomentChanged()
    }
}
