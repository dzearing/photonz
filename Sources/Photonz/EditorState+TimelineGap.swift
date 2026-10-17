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

    /// Close the gap in hand: everything after it slides back, on its track
    /// and on the others (titles, music, captions), as one step to undo.
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

    /// What a right click on a gap, or on empty space on a track, offers
    /// (`TimelineMenuTable`): what you can put there or take out, and the
    /// timeline's view. The track's own menu is one level down, under Track,
    /// added by the menu itself since its rows are the header's
    /// (`TimelineTrackMenu`).
    func timelineSpaceMenuRows(track: DocumentTrack, gap: TimelineGap?) -> [MenuRow] {
        let emptyPictureTrack = isTrackEmpty(track.id) && track.kind == .video && !track.isLocked
        return timelineMenu(gap == nil ? .emptySpace : .gap) { row in
            switch row {
            case .closeGap:
                // Never greyed: a gap that cannot close says why when it is
                // asked to (`closeGap`).
                guard let gap else { return [] }
                return [.command("Ripple Delete", TimelineMenuKeys.rippleDelete) { self.closeGap(gap) }]
            case .addTitlePage:
                // A title page or a name card from its presets, on this track
                // from the playhead (`EditorState+TitlePresets`).
                return emptyPictureTrack ? self.titleInsertMenuRows(verb: "Add", onTrack: track.id) : []
            case .addText:
                return emptyPictureTrack ? [.command("Add Text") { self.addText(onTrack: track.id) }] : []
            case .addRectangle:
                return emptyPictureTrack ? [.command("Add Rectangle") { self.addRectangle(onTrack: track.id) }] : []
            case .putLayerHere:
                // A layer that is on the canvas and on no track.
                let loose = self.layersOffTheTimeline
                guard emptyPictureTrack, !loose.isEmpty else { return [] }
                return [.submenu("Put Layer Here", loose.map { layer in
                    .command(layer.name) { self.putLayerOnTimeline(layer.id, onTrack: track.id) }
                })]
            case .pasteHere:
                guard emptyPictureTrack, self.canPasteLayerOrPicture else { return [] }
                return [.command("Paste Here") { self.paste(onTrack: track.id) }]
            case .captionsTrack:
                return track.kind == .captions ? self.captionTrackMenuRows() : []
            case .zoomToFit:
                return self.timelineViewMenuRows().filter { $0.title == "Zoom to Fit" && $0.isEnabled }
            case .compactTracks:
                return self.timelineViewMenuRows().filter { $0.title == "Compact Tracks" }
            default:
                return []
            }
        }
    }
}
