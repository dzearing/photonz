import AppKit
import Foundation
import PhotonzCore

// A gap between two clips, picked with a click and closed with Delete, Shift
// Delete, Ripple Delete in the Sequence menu or the gap's own right-click menu
// (`TimelineGap.swift`), the way Premiere and Final Cut close one.
//
// The gap is drawn in the same band a range on some tracks wears, so it reads
// as a stretch of time picked on that track, which is what it is.

extension EditorState {

    /// The gap a click picked, while it is still the thing in hand: nothing
    /// else has been picked since and it is still a gap.
    var timelineGapHeld: TimelineGap? {
        guard documentHasTime, let gap = timelineGapInHand, selectedLayerID == nil,
              multiSelectedLayerIDs.isEmpty, selectedEditPoint == nil, trackRangeInHand == nil,
              timelinePicks.isEmpty, !canDeletePickedKeys,
              document?.gap(onTrack: gap.trackID, atMS: gap.range.lowerBound) == gap else { return nil }
        return gap
    }

    /// The gaps on a track, where a click picks one and a right click offers
    /// to close it. None on a Captions track, whose spaces are pauses.
    func timelineGaps(onTrack track: DocumentTrack) -> [TimelineGap] {
        guard documentHasTime, track.kind != .captions, let document else { return [] }
        return document.gaps(onTrack: track.id)
    }

    /// Pick the gap at `ms` on the track whose row is at `y`, if there is one
    /// there. A click anywhere else lets the last one go.
    func pickTimelineGap(atMS ms: Int, y: CGFloat) {
        let row = trackDropRows.values.first { $0.minY <= y && y <= $0.maxY }
        guard let row, let document, let gap = document.gap(onTrack: row.trackID, atMS: ms) else { return }
        timelineGapInHand = gap
    }

    func canCloseGap(_ gap: TimelineGap) -> Bool {
        documentHasTime && document?.canCloseGap(gap) == true
    }

    var canCloseGapInHand: Bool {
        guard let gap = timelineGapHeld else { return false }
        return canCloseGap(gap)
    }

    /// Close the gap in hand: everything after it on its track slides back,
    /// with its sound and its captions, as one step to undo.
    func closeGapInHand() {
        guard let gap = timelineGapHeld else { return }
        closeGap(gap)
    }

    /// Close `gap`, picked or not: what its right-click menu does. A gap that
    /// cannot close changes nothing and says what is in the way under the
    /// canvas (`GapCloseRefusal`): a key that did nothing reads as broken.
    func closeGap(_ gap: TimelineGap) {
        guard documentHasTime, let document else { return }
        if let refusal = document.gapCloseRefusal(gap) {
            NSSound.beep()
            raiseCanvasNotice(.gapNotClosed(refusal))
            return
        }
        endTrimBeforeCutting()
        pauseDocument()
        perform { $0.closeGap(gap) }
        timelineGapInHand = nil
        // The playhead stays on the frame it was on, unless that frame moved
        // under it: a playhead in the gap lands on the join.
        if gap.range.contains(documentTimeMS) { documentTimeMS = gap.range.lowerBound }
        if documentTimeMS > lastDocumentTimeMS { documentTimeMS = lastDocumentTimeMS }
        documentMomentChanged()
    }

    /// The rows a right click on a gap leads with.
    func timelineGapMenuRows(_ gap: TimelineGap) -> [MenuRow] {
        [.command("Ripple Delete", TimelineMenuKeys.rippleDelete, enabled: canCloseGap(gap)) {
            self.closeGap(gap)
        }]
    }
}
