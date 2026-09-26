import Foundation
import PhotonzCore

// Anything drawn on a video is on the timeline (`DrawnOnTheTimeline.swift`,
// `next-anything-drawn-on-a-video-is-on-the-timeline`).
//
// Every tool that makes a layer comes through here, so a rectangle, a line, a
// lens, a measurement, a paste or a dropped picture made on a document with
// time lands with a stretch and a row of its own, and none of them can arrive
// knowing when it is on screen by one route and not by another.
extension EditorState {

    /// Whether what is drawn now is placed in time: the switch is on and the
    /// document has time. A picture never is.
    var placesDrawingsInTime: Bool {
        Experiments.shared.drawnOnTheTimelineEnabled && documentHasTime
    }

    /// One undo step adding `layer` drawn at the playhead: onto the screen it
    /// was drawn on, for the hold it was drawn on, and, on a video, from the
    /// playhead to the end of the shot.
    func addDrawnLayer(_ layer: Layer) {
        let moment = documentTimeMS
        let placing = placesDrawingsInTime
        perform { $0.addLayerDrawn(layer, atTimeMS: moment, placingInTime: placing) }
    }

    /// `layer` with the stretch a drawing made at the playhead is given, for
    /// the routes that add a layer some other way (a measurement, a drop on the
    /// layers list). Unchanged on a picture, or where it already has one.
    func placedInTimeIfDrawnOnVideo(_ layer: Layer) -> Layer {
        guard placesDrawingsInTime, layer.time == nil,
              let span = document?.drawnSpan(atTimeMS: documentTimeMS) else { return layer }
        var placed = layer
        placed.time = span
        return placed
    }

    // MARK: The key diamond on a row's header

    /// The layer a track header's diamond keys: the picked one, where it is on
    /// this track and the diamond is offered at all.
    func headerKeyLayerID(onTrackWith clipIDs: [UUID]) -> UUID? {
        guard Experiments.shared.drawnOnTheTimelineEnabled,
              let layer = keyLayer, clipIDs.contains(layer.id) else { return nil }
        return layer.id
    }

    func headerKeyDiamond(_ layerID: UUID) -> KeyDiamond {
        document?.transformKeyDiamond(layerID: layerID, atDocumentTimeMS: documentTimeMS) ?? .dormant
    }

    /// The header diamond, pressed: where it is, its size, its angle and its
    /// opacity keyed at the playhead, or the keys here taken away.
    func toggleHeaderKey(_ layerID: UUID) {
        let time = documentTimeMS
        let ease = newKeyEaseToWrite
        if isDocumentPlaying { pauseDocument() }
        perform { $0.toggleTransformKey(layerID: layerID, atDocumentTimeMS: time, ease: ease) }
    }
}
