import CoreGraphics
import Foundation

// A clip nobody can see is not read while it plays
// (`an-edit-with-50-tracks-and-100-clips-scrolls-pla`).
//
// Recording over recording dropped on tracks of their own, each filling the
// frame, is the commonest tall edit there is, and only the top one is seen.
// Every one under it was decoded all the same, and a Mac decodes about 630
// full Retina frames a second whatever they are for (2026-11-24). So a
// playing clock asks only for the frames that are seen. A still playhead and
// an export still ask for every one.

extension PhotonzDocument {

    /// The frames of `movieFrames(atTimeMS:)` somebody can see at a moment:
    /// all but those of clips on a track switched off, and of clips under one
    /// that fills the frame and lets nothing through.
    public func movieFramesSeen(atTimeMS ms: Int) -> [MovieFrameRequest] {
        let all = movieFrames(atTimeMS: ms)
        guard all.count > 1 else { return all }
        let moment = min(max(0, ms), lastDrawableTimeMS)
        let off = layersOffScreenByTrack()
        var hidden = Set<UUID>()
        func hide(_ layer: Layer) {
            for inside in layer.selfAndDescendants {
                hidden.insert(inside.id)
                hidden.insert(Layer.transitionPartnerID(of: inside.id))
            }
        }
        for layer in layers where off.contains(layer.id) { hide(layer) }
        // A camera or a lens can show a layer from anywhere, so nothing is
        // taken to be covered then.
        if camera == nil, let cover = layers.lastIndex(where: {
            !off.contains($0.id) && fillsTheFrame($0, atTimeMS: moment)
        }), cover > 0 {
            let changing = hasEditPointTransitions
                ? Set(editPointMoments(atMS: moment).flatMap { [$0.onScreen, $0.borrowed] }) : []
            if !changing.contains(layers[cover].id) {
                for layer in layers[..<cover] { hide(layer) }
            }
        }
        guard !hidden.isEmpty else { return all }
        return all.filter { !hidden.contains($0.layerID) }
    }

    /// Whether this clip covers every pixel of the canvas at a moment and
    /// lets nothing under it show: a recording (which has no transparency as
    /// it is read) over the whole frame, with nothing done to it.
    private func fillsTheFrame(_ layer: Layer, atTimeMS ms: Int) -> Bool {
        layer.isVisible && layer.movie != nil && layer.movieFrameSourceMS(atTimeMS: ms) != nil
            && layer.incomingMovieFrameSourceMS(atTimeMS: ms) == nil
            && layer.frame.contains(CGRect(origin: .zero, size: canvasSize))
            && layer.style.isPlain && layer.style.effects.isEmpty
            && layer.crop == nil && layer.transform.isIdentity && layer.reshape == nil
            && (layer.motions ?? []).isEmpty && layer.pictureFade == nil
            && (layer.zooms ?? []).isEmpty && layer.zoomWindow == nil && layer.merged == nil
    }
}
