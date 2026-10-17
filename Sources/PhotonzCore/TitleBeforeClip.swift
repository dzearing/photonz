import Foundation

// A title page put in front of a clip, on the clip's own track
// (task `insert-a-title-before-a-clip-on-its-track-and-ch`).
//
// The user, 2026-10-17: "I select a clip, double click a title, it inserts it
// on the same track as the selected clip before it and adjusts things. And I
// can visually see the transition between them on the layout, and i can click
// it to select it, and right click to change the transition or press delete to
// delete the transition."
//
// That is Premiere's title on V1 ahead of the clip: the page is a clip in the
// sequence like a recording, the clip and everything after it move along by
// the page's length, and the join between the two is an edit point like any
// other (`EditPointTransitions.swift`). So the page carries no fade out of its
// own: how it leaves is the transition on that join, a cross dissolve until
// somebody picks another, and a straight cut once they delete it.
//
// A title is drawn rather than recorded, so it has frames either side of its
// edges for as long as anyone wants: any overlapping transition can run on
// over its tail, which is how a dissolve into a recording read from its first
// frame is paid for (`ClipCut.fitted` puts it after the cut).
//
// Name cards and anything laid over the picture still go on a track of their
// own above it (`titleLanding`).

extension TitlePreset {
    /// Whether this goes INTO a sequence, in front of a clip on its track: a
    /// title page, unless it is made of the recording under it (Behind
    /// Glass), which has nothing to show without a recording beneath it and
    /// so is always laid over one.
    public var goesInFrontOfAClip: Bool {
        guard kind == .titlePage else { return false }
        if case .builtIn(let builtIn) = self { return !builtIn.usesTheRecording }
        return true
    }
}

extension Layer {
    /// Whether this is a picture clip a sequence is cut from: a recording, or
    /// clips merged into one that has a picture. The clips a title page is put
    /// in front of, and what makes a track a sequence.
    var isSequencePicture: Bool {
        guard time != nil else { return false }
        if movie != nil { return true }
        if let merged { return !merged.isSoundOnly }
        return false
    }
}

extension PhotonzDocument {

    /// Whether a title page can go in front of this clip on its track: a
    /// picture clip at the top of the document, on a picture track that is not
    /// locked.
    public func canInsertTitle(beforeClip id: UUID) -> Bool {
        guard hasTime, let clip = layer(id: id), clip.isSequencePicture, parentID(of: id) == nil,
              let trackID = trackID(ofClip: id), let track = track(id: trackID) else { return false }
        return track.kind == .video && !track.isLocked
    }

    /// Put a title page in front of a clip, on its track: the page starts
    /// where the clip did, the clip and everything after it move along by the
    /// page's length, and the join between them gets `join` (Premiere's
    /// default, a cross dissolve, unless another is asked for).
    ///
    /// Nil, and nothing changed, for a name card or a page made of the
    /// recording under it (laid over the picture, never cut into it) and for
    /// a clip `canInsertTitle(beforeClip:)` refuses.
    @discardableResult
    public mutating func insertTitle(_ preset: TitlePreset, beforeClip id: UUID,
                                     join: ClipTransitionKind = .usualDefault,
                                     motionBlur: Bool = false) -> InsertedTitle? {
        guard preset.goesInFrontOfAClip, canInsertTitle(beforeClip: id),
              let trackID = trackID(ofClip: id), let track = track(id: trackID),
              let start = layer(id: id)?.time?.inMS else { return nil }
        let landing = ClipLanding(target: .onto(trackID), startMS: start, lengthMS: preset.lengthMS,
                                  edit: .insert, trackName: track.name, allowed: true)
        return insertTitle(preset, atTimeMS: start, landing: landing, motionBlur: motionBlur, join: join)
    }

    /// Where a title page let go over the timeline is put INTO the sequence:
    /// over a picture track that holds a recording and is not locked, it is
    /// inserted at the moment, pushing what is after it along. Nil anywhere
    /// else, where it is laid over the picture as before (`titleLanding`).
    public func titlePageSequenceLanding(lengthMS: Int, atMS ms: Int, over pointed: TrackDrop?) -> ClipLanding? {
        guard case .onto(let id)? = pointed, let track = track(id: id), track.kind == .video,
              !track.isLocked,
              clipIDs(onTrack: id).contains(where: { layer(id: $0)?.isSequencePicture == true })
        else { return nil }
        let landing = clipLanding(kind: .video, lengthMS: lengthMS, atMS: ms, over: .onto(id), edit: .insert)
        guard landing.allowed, landing.target == .onto(id) else { return nil }
        return landing
    }

    /// A page landed into a sequence by `landing` (an insert onto a track):
    /// the transition the clip it went in front of arrived with stays on that
    /// cut, which the page now arrives at; the join from the page into the
    /// clip gets `join`; and the page's own fade out goes, since the join is
    /// how it leaves.
    mutating func settleTitleInSequence(_ page: UUID, trackID: UUID, carried: ClipTransition?,
                                        formerlyArriving: UUID?, join: ClipTransitionKind) {
        if pictureFadeMS(page, .out) > 0 { setPictureFade(page, .out, toMS: 0) }
        guard let time = layer(id: page)?.time else { return }
        if let carried, let formerlyArriving {
            updateLayer(id: formerlyArriving) { $0.arrivalTransition = nil }
            updateLayer(id: page) { $0.arrivalTransition = carried }
            if let before = editPoints(onTrack: trackID).first(where: { $0.incoming == page }),
               let cut = documentCut(at: .edit(outgoing: before.outgoing, incoming: page))?.cut,
               let fit = cut.fitted(carried.kind), fit != carried {
                updateLayer(id: page) { $0.arrivalTransition = fit }
            }
        }
        guard let after = editPoints(onTrack: trackID).first(where: { $0.outgoing == page }),
              after.atMS == time.outMS else { return }
        let place = TimelineCutPlace.edit(outgoing: page, incoming: after.incoming)
        if let fit = documentCut(at: place)?.cut.fitted(join) { setTransition(fit, at: place) }
    }

    private func pictureFadeMS(_ id: UUID, _ end: FadeEnd) -> Int {
        layer(id: id)?.pictureFadeMS(end) ?? 0
    }
}
