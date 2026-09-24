import Foundation

// What a stretch cut out of a recording takes with it.
//
// Throwing a piece of a talking recording away closes the gap inside that
// clip, and that alone left every caption after it over the wrong words, and
// the lines for the speech that went playing over black. An editor who knows
// Premiere expects the cut to take everything along with the picture, the way
// a ripple delete does with sync lock on, so that is what happens: the stretch
// comes out of the whole document at once.
//
// The rule for any one layer depends only on where it sits against the
// stretch that went:
//
// - **Over before it starts**: not touched.
// - **Starts after it ends**: moves earlier by its length.
// - **Wholly inside it**: goes with it. A caption for words nobody will hear,
//   a title over a shot nobody will see, a sound that only played there.
// - **Words or a shape across either end**: loses exactly the part that was
//   inside, so a caption never runs on over the join.
// - **A sound or a picture that starts inside and runs on**: lands on the join
//   and keeps everything it plays. Its head is somebody else's edit.
// - **A sound or a picture across the whole stretch**, music under the take:
//   left as it was. Cutting into it would be cutting something nobody pointed
//   at.
//
// A caption's words carry their own moments on the document's clock, and they
// move by the same rule, so the word being lit is still the word being said.

extension PhotonzDocument {

    /// Take the stretch from `start` to `end` out of every layer but one, and
    /// close it up. Answers whether anything changed.
    ///
    /// A clip on a locked track, and a locked layer, stay exactly where they
    /// are: locking is saying so.
    @discardableResult
    public mutating func removeTime(fromMS start: Int, toMS end: Int, exceptLayer keep: UUID?) -> Bool {
        removeTime(fromMS: start, toMS: end, exceptLayers: keep.map { [$0] } ?? [])
    }

    /// The same, leaving alone every layer in `keep`: the ones the caller has
    /// already cut for itself (`MarkedStretch.swift`).
    @discardableResult
    public mutating func removeTime(fromMS start: Int, toMS end: Int, exceptLayers keep: Set<UUID>) -> Bool {
        let length = end - start
        guard start >= 0, length > 0 else { return false }
        let squeeze = { (ms: Int) -> Int in ms < start ? ms : (ms >= end ? ms - length : start) }
        var gone: Set<UUID> = []
        var changed = false
        for layer in allLayers {
            guard !keep.contains(layer.id), !layer.isLocked, let time = layer.time,
                  time.outMS > start, !isClipOnLockedTrack(layer.id) else { continue }
            if time.inMS >= end {
                updateLayer(id: layer.id) { moved in
                    moved.time = time.moved(toInMS: time.inMS - length)
                    moved.captionWords = moved.captionWords?.map { $0.shifted(byMS: -length) }
                }
            } else if time.inMS >= start, time.outMS <= end {
                gone.insert(layer.id)
            } else if layer.holdsMedia {
                guard time.inMS >= start else { continue }
                updateLayer(id: layer.id) { $0.time = time.moved(toInMS: start) }
            } else {
                updateLayer(id: layer.id) { cut in
                    cut.time = LayerTime(inMS: squeeze(time.inMS), outMS: squeeze(time.outMS),
                                         sourceInMS: time.sourceInMS, sourceLengthMS: time.sourceLengthMS)
                    cut.captionWords = cut.captionWords?.map {
                        TranscribedWord($0.text, startMS: squeeze($0.startMS),
                                        endMS: squeeze($0.endMS), confidence: $0.confidence)
                    }
                }
                refitFade(layer.id)
            }
            changed = true
        }
        removeLayersEmptyingCaptions(gone)
        if changed { refreshDuration() }
        return changed
    }

    /// Take layers a stretch took with it away, and a Captions group whose
    /// every line went with them: that is not a track anybody wants left on
    /// the timeline with nothing on it.
    mutating func removeLayersEmptyingCaptions(_ gone: Set<UUID>) {
        guard !gone.isEmpty else { return }
        removeLayers(ids: gone)
        let empty = allLayers.filter {
            $0.name == CaptionLayers.groupName && $0.group?.children.isEmpty == true
        }
        removeLayers(ids: Set(empty.map(\.id)))
    }
}
