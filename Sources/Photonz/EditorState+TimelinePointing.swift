// A click on something on the timeline picks it AND puts the playhead on the
// moment under the pointer, the way Premiere and Final Cut do.
//
// A right click (or a Control-click) never moves the playhead (the user,
// 2026-10-13, reversing their 2026-10-12 ask): a person parks the playhead at
// a moment, then right clicks the clip anywhere and chooses Add Key, Split at
// Playhead, Freeze Frame or Add Zoom at that parked moment. It picks what it
// landed on unless that is already part of what is picked, and then the menu
// acts on the whole pick. Rows that act at the playhead say where it is when
// the playhead may be far from the pointer ("Add Key at 0:02.00").
//
// A right click has two halves, because SwiftUI tells nobody where it landed:
//
// 1. The window's mouse monitor sees the press before anything else does and
//    hands its place to `timelineRightPress(at:)`, which notes it and counts
//    it. A walk's right click never passes the monitor, so the walk offers it
//    by hand through `TimelineRightPress`, as it does keys through
//    `TimelineKeyRouter`.
// 2. SwiftUI builds the menu of whatever is under the pointer the moment the
//    menu is asked for, not before (measured 2026-10-12: the clip menu's body
//    ran inside `menu(for:)`). Every timeline menu reads the count, so it is
//    built afresh for every press, and says what it is about as it is built
//    (`timelineMenuBuilt(for:)`). Others are rebuilt in the same pass (a zoom
//    lane's menu took a press meant for the clip above it), so a menu only
//    counts when the press landed on its own row and inside its own time,
//    and that one picks what it is about.

import AppKit
import PhotonzCore

/// What a timeline menu is about, said as it is built.
enum TimelineMenuTarget: Equatable {
    case clip(UUID, piece: Int, onTheSound: Bool)
    case zoom(ClipZoomRef)
}

extension EditorState {

    // MARK: A click

    /// A plain click on something on the timeline, after it is picked: the
    /// playhead goes to the moment under the pointer, `laneX` points from the
    /// lane's left edge. It plays on from there when it was playing, and stays
    /// paused when it was not. A Control-click is a right click, and leaves
    /// the playhead where it is.
    func playheadToTimelineClick(laneX: CGFloat, laneWidth: CGFloat) {
        guard documentHasTime,
              let ms = TimelinePointing.ms(atLaneX: laneX, laneWidth: laneWidth, ruler: motionStripRuler)
        else { return }
        playheadToTimelineClick(atMS: ms)
    }

    /// The same, for a click that already knows its moment.
    func playheadToTimelineClick(atMS ms: Int) {
        guard documentHasTime, !Self.isControlClick(NSApp.currentEvent) else { return }
        scrubDocument(toMS: ms)
    }

    // MARK: A right click

    /// A right click at `point`, in SwiftUI's global space: on the tracks, it
    /// is noted for the menu it is about to open (`timelineMenuBuilt(for:)`).
    /// Answers whether it landed on the tracks.
    @discardableResult
    func timelineRightPress(at point: CGPoint) -> Bool {
        timelineRightPressMS = nil
        guard documentHasTime, !isWatching, timelineTracksViewport.contains(point),
              let ms = TimelinePointing.ms(atLaneX: point.x - timelineTracksFrame.minX - TimelineDock.lanesLeading,
                                           laneWidth: timelineLaneWidth, ruler: motionStripRuler)
        else { return false }
        timelineRightPressMS = ms
        timelineLastRightPressMS = ms
        timelineRightPressY = point.y - timelineTracksFrame.minY
        timelineRightPresses &+= 1
        // Only the menu this press opens may learn from it: that one is built
        // before this turn of the run loop is over.
        DispatchQueue.main.async { [weak self] in self?.timelineRightPressMS = nil }
        return true
    }

    /// A timeline menu being built, before it works out its rows. When the
    /// right click just made landed on what it is about, the thing gets picked
    /// unless it is already part of the pick, the way Finder picks a file you
    /// right click. The playhead stays where it was parked, so the rows act
    /// there. The pick waits for the menu to be built.
    func timelineMenuBuilt(for target: TimelineMenuTarget) {
        guard let ms = timelineRightPressMS, rightPress(atMS: ms, y: timelineRightPressY, landsOn: target)
        else { return }
        timelineRightPressMS = nil
        DispatchQueue.main.async { [weak self] in self?.pickForRightPress(target) }
    }

    /// A left press with Control held: the Mac's right click.
    static func isControlClick(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged: return event.modifierFlags.contains(.control)
        default: return false
        }
    }

    /// Whether a right click at `ms`, `y` down the tracks, is on `target`: a
    /// zoom bar on its own lane, a clip on its track's lane and inside its
    /// time, never on a zoom or key lane under it. Rows are measured down the
    /// tracks' own space as they lay out (`trackDropRows`, `zoomLaneRows`).
    private func rightPress(atMS ms: Int, y: CGFloat, landsOn target: TimelineMenuTarget) -> Bool {
        guard let document else { return false }
        switch target {
        case .zoom(let ref):
            // Which bar is the lane's to say, from where the press landed
            // along it (`ZoomBarsView.rightPressedBar`); only the lane is here.
            return zoomLaneRows[ref.layerID]?.contains(y) == true
        case .clip(let id, _, let onTheSound):
            if zoomLaneRows.values.contains(where: { $0.contains(y) })
                || keyLaneRows.values.contains(where: { $0.contains(y) }) { return false }
            guard let lane = trackDropRows.values.first(where: { $0.minY <= y && y <= $0.maxY }),
                  let row = timelineTrackRows.first(where: { $0.track.id == lane.trackID }),
                  (onTheSound ? row.linked : row.clips).contains(where: { $0.layerID == id }),
                  let time = document.layer(id: id)?.time else { return false }
            return time.inMS...time.outMS ~= ms
        }
    }

    private func pickForRightPress(_ target: TimelineMenuTarget) {
        switch target {
        case .clip(let id, let piece, let onTheSound):
            guard document?.layer(id: id) != nil, !isClipInPick(id, piece: piece, onTheSound: onTheSound)
            else { return }
            clearKeySelection()
            let count = document?.layer(id: id)?.clipPieces?.count ?? 1
            selectClipPiece(layerID: id, index: count > 1 ? piece : nil)
        case .zoom(let ref):
            guard !isZoomLit(ref) else { return }
            pickZoom(ref)
        }
    }

    /// Whether a clip, or this piece of it, is part of what is picked: picked
    /// itself, one of several, under a range in hand, in a box's pick, or on a
    /// track picked by its header.
    func isClipInPick(_ id: UUID, piece: Int, onTheSound: Bool = false) -> Bool {
        if multiSelectedLayerIDs.contains(id) { return true }
        if selectedLayerID == id { return selectedClipPieceIndex.map { $0 == piece } ?? true }
        if rangeSection?.ids.contains(id) == true { return true }
        if isPiecePickedByBox(layerID: id, index: piece) { return true }
        return goesWithTracksInHand(id, asSound: onTheSound)
    }

    /// The clips a clip menu row acts on: every picked clip when the one right
    /// clicked is one of several picked, else that one alone.
    func clipMenuTargets(_ id: UUID) -> [UUID] {
        guard multiSelectedLayerIDs.count > 1, multiSelectedLayerIDs.contains(id), let document else { return [id] }
        return document.allLayers.map(\.id).filter { multiSelectedLayerIDs.contains($0) }
    }
}

/// A right click offered to the timeline before any menu is built.
@MainActor
enum TimelineRightPress {
    /// `windowPoint` is in the window's own space, as an event carries it. The
    /// dock's mouse monitor offers a person's right click; a walk offers its
    /// own by hand, since a click it makes never passes the monitor. True when
    /// it landed on the tracks.
    @discardableResult
    static func offer(at windowPoint: CGPoint, in window: NSWindow) -> Bool {
        guard let editor = TimelineKeyRouter.editor(in: window), let content = window.contentView else { return false }
        let local = content.convert(windowPoint, from: nil)
        let top = content.isFlipped ? local.y : content.bounds.height - local.y
        return editor.timelineRightPress(at: CGPoint(x: local.x, y: top))
    }
}
