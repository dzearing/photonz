import Foundation

// **A video's length that ended with its last clip goes on ending with it**
// (user 2026-10-29: "when i delete the max video clip ... the max length
// doesn't get reduced ... It should always be 2x the max Duration").
//
// A clip landing past the end stretches the written length to hold it
// (`ClipLanding`, `MediaDrop`, `ClipDragCopy`, `RangeClipboard`), and a trim
// shrank it again (`ClipTrim`, `ClipBarDrag.refreshDuration`). Nothing else
// did: delete that clip, or drag it back, and the video went on running to
// where it had been, the timeline zooming out to twice a length nothing
// filled. So every edit, whatever made it, ends the same way (`History`).
//
// Only a length that was ending with the last clip follows it. A blank video
// made longer than what is on it keeps the tail it was made with, and one
// left with nothing on it keeps its length rather than vanishing from under
// the timeline.

extension PhotonzDocument {

    /// Where the last thing with a stretch of time in it ends.
    var lastClipEndMS: Int? { allLayers.compactMap { $0.time?.outMS }.max() }

    /// After an edit from `before`: a written length that ended with the last
    /// clip ends with the last clip now.
    mutating func followLastClip(from before: PhotonzDocument) {
        guard let written = durationMS, let was = before.durationMS,
              let endedAt = before.lastClipEndMS, endedAt >= was,
              let endsAt = lastClipEndMS, endsAt != written else { return }
        durationMS = endsAt
    }
}
