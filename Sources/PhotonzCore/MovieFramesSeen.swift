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
        let plan = moviePlan
        // A camera or a lens can show a layer from anywhere, so nothing is
        // taken to be covered then.
        var cover = 0
        if camera == nil, let top = plan.covers.last(where: {
            $0.inMS <= moment && moment < $0.outMS && fillsTheFrame(layers[$0.index], atTimeMS: moment)
        }), top.index > 0 {
            let changing = hasEditPointTransitions
                && editPointMoments(atMS: moment).contains {
                    $0.onScreen == layers[top.index].id || $0.borrowed == layers[top.index].id
                }
            if !changing { cover = top.index }
        }
        guard cover > 0 || !plan.off.isEmpty else { return all }
        return all.filter {
            guard let index = plan.topLayer[$0.layerID] else { return true }
            return index >= cover && !plan.off.contains(index)
        }
    }

    /// Which layers play a recording and when, read off the layers once and
    /// kept until one changes. A playing clock asks what each moment needs
    /// dozens of times after an edit and on every tick, and each answer went
    /// through every layer, copying it, whether or not it was on screen: 5 ms
    /// of every edit's pass on a 100 clip edit (2026-11-24).
    var moviePlan: DocumentDerived.MoviePlan {
        derived.answer(\.moviePlan) {
            var plan = DocumentDerived.MoviePlan()
            let off = layersOffScreenByTrack()
            for index in layers.indices {
                let id = layers[index].id
                if layers[index].merged != nil { plan.merged.append(index) }
                if off.contains(id) { plan.off.insert(index) }
                guard Self.playsSomething(layers[index]) else { continue }
                // A layer alone answers only while it is on screen; one with
                // layers inside is asked at every moment, for theirs.
                let alone: Bool = if case .group = layers[index].content { false } else { true }
                let time = alone ? layers[index].time : nil
                plan.plays.append(.init(index: index, inMS: time?.inMS ?? .min, outMS: time?.outMS ?? .max))
                if alone, let time, !off.contains(id), layers[index].movie != nil {
                    plan.covers.append(.init(index: index, inMS: time.inMS, outMS: time.outMS))
                }
            }
            func place(_ list: [Layer], under top: Int) {
                for index in list.indices {
                    plan.topLayer[list[index].id] = top
                    plan.topLayer[Layer.transitionPartnerID(of: list[index].id)] = top
                    if case .group(let group) = list[index].content { place(group.children, under: top) }
                }
            }
            for index in layers.indices { place([layers[index]], under: index) }
            return plan
        }
    }

    private static func playsSomething(_ layer: Layer) -> Bool {
        if layer.movie != nil { return true }
        guard case .group(let group) = layer.content else { return false }
        return group.children.indices.contains { playsSomething(group.children[$0]) }
    }

    /// The frames a layer and everything inside it needs at a moment.
    static func movieFrameRequests(of layer: Layer, atTimeMS ms: Int, into all: inout [MovieFrameRequest]) {
        if layer.movie != nil { all += layer.movieFrameRequests(atTimeMS: ms) }
        if case .group(let group) = layer.content {
            for index in group.children.indices {
                movieFrameRequests(of: group.children[index], atTimeMS: ms, into: &all)
            }
        }
    }

    /// Whether this clip covers every pixel of the canvas at a moment and
    /// lets nothing under it show: a recording (which has no transparency as
    /// it is read) over the whole frame, with nothing done to it.
    func fillsTheFrame(_ layer: Layer, atTimeMS ms: Int) -> Bool {
        layer.isVisible && layer.movie != nil && layer.movieFrameSourceMS(atTimeMS: ms) != nil
            && layer.incomingMovieFrameSourceMS(atTimeMS: ms) == nil
            && layer.frame.contains(CGRect(origin: .zero, size: canvasSize))
            && layer.style.isPlain && layer.style.effects.isEmpty
            && layer.crop == nil && layer.transform.isIdentity && layer.reshape == nil
            && (layer.motions ?? []).isEmpty && layer.pictureFade == nil
            && (layer.zooms ?? []).isEmpty && layer.zoomWindow == nil && layer.merged == nil
    }
}
