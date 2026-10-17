import AppKit
import PhotonzCore

/// A part's bar on the timeline taken hold of: which part, which end, and how
/// far the hand has carried it, already caught on whatever it snapped to (task
/// `any-timeline-row-that-holds-sub-layers-expands-a`). A title's parts have
/// their own (`TitlePartDrag`), since they are timed through the title's
/// design.
struct PartBarDrag: Equatable {
    let pieceID: UUID
    let grab: TitlePartGrab
    /// The bar as it was when the hand took it.
    let from: LayerPartStretch
    var byMS: Int
    var caughtMS: Int?
}

/// How a row under a clip sits: how far in, and whether it has an arrow.
struct TimelineRowNesting: Equatable {
    var depth: Int
    /// It has parts of its own, or values moving on it, to open into.
    var opens: Bool
    var isOpen: Bool
}

extension EditorState {

    // MARK: Opening rows

    /// Whether a row on the timeline is open. One set with the layers list's
    /// open groups: the timeline is the layers list with a time axis, so
    /// opening a group in one opens it in the other (`TimelineChildRows.swift`).
    func timelineRowOpen(_ id: UUID) -> Bool { expandedGroupIDs.contains(id) }

    /// The arrow on a row: open closes it, closed opens it. With ⌥, every part
    /// inside that has parts of its own opens or closes with it, the way the
    /// layers list's arrow works.
    func toggleTimelineRow(_ id: UUID, everyLevel: Bool) {
        let ids = everyLevel ? (document?.timelineRowsOpeningEveryLevel(from: id) ?? []).union([id]) : [id]
        if timelineRowOpen(id) {
            expandedGroupIDs.subtract(ids)
        } else {
            expandedGroupIDs.formUnion(ids)
        }
        timelineTrackRowsMemo = nil
    }

    /// The clips on a track that have parts to open into: what earns its
    /// header the arrow.
    func clipsWithParts(_ layerIDs: [UUID]) -> [UUID] {
        guard let document else { return [] }
        return layerIDs.filter { document.timelineRowOpens($0) }
    }

    /// The arrow on a track's header opens every clip on it that has parts.
    /// Open while every one of them is.
    func trackPartsOpen(_ layerIDs: [UUID]) -> Bool {
        let clips = clipsWithParts(layerIDs)
        return !clips.isEmpty && clips.allSatisfy(timelineRowOpen)
    }

    func toggleTrackParts(_ layerIDs: [UUID], everyLevel: Bool) {
        guard let document else { return }
        let clips = clipsWithParts(layerIDs)
        var ids = Set(clips)
        if everyLevel { for clip in clips { ids.formUnion(document.timelineRowsOpeningEveryLevel(from: clip)) } }
        if trackPartsOpen(layerIDs) {
            expandedGroupIDs.subtract(ids)
        } else {
            expandedGroupIDs.formUnion(ids)
        }
        timelineTrackRowsMemo = nil
    }

    /// Where a closed row's parts have timing of their own: the faint marks
    /// along its bar. Nothing for an open row, whose parts are on screen.
    func timelineChildMarks(of id: UUID) -> [LayerTime] {
        guard !timelineRowOpen(id), let document = shownDocument else { return [] }
        return document.timelineChildMarks(of: id)
    }

    // MARK: A part's bar

    /// The bar the row of part `pieceID` draws: where the hand has it while
    /// it is being dragged. Nil for anything that is not a part of something
    /// placed in time, and for a title's parts (`titlePartTiming`).
    func partBarStretch(pieceID: UUID) -> LayerPartStretch? {
        guard let document = shownDocument else { return nil }
        return withDraggedPartBar(document).partStretch(of: pieceID)
    }

    /// A press on a part's bar: the part is picked, and the drag starts from
    /// the bar as it is.
    func beginPartBarDrag(pieceID: UUID, grab: TitlePartGrab) {
        guard let document, let stretch = document.partStretch(of: pieceID), !stretch.isInsideACopy,
              !isClipLocked(pieceID) else { return }
        pauseDocument()
        if selectedLayerID != pieceID { selectLayer(pieceID, inGroup: document.parentID(of: pieceID)) }
        partBarDrag = PartBarDrag(pieceID: pieceID, grab: grab, from: stretch, byMS: 0, caughtMS: nil)
    }

    /// The hand moved `byMS` along the timeline. The end in the hand catches
    /// on the playhead, the ends of what it is inside, the other parts' ends
    /// and the markers within `catchMS`. Nothing is written down.
    func updatePartBarDrag(byMS raw: Int, catchMS: Int) {
        guard var drag = partBarDrag, let document else { return }
        let from = drag.from
        var moments = [documentTimeMS, from.boundsStartMS, from.boundsEndMS] + document.markers.map(\.atMS)
        if let parent = document.parentID(of: drag.pieceID) {
            for other in document.timelineChildIDs(of: parent) where other != drag.pieceID {
                if let stretch = document.partStretch(of: other) { moments += [stretch.startMS, stretch.endMS] }
            }
        }
        let ends: [Int] = switch drag.grab {
        case .start: [from.startMS]
        case .end: [from.endMS]
        case .body: [from.startMS, from.endMS]
        }
        var moved = raw
        var caught: Int?
        var best = Int.max
        for end in ends {
            let landed = TitlePartTiming.snapped(end + raw, to: moments, withinMS: catchMS)
            let pull = abs(landed - (end + raw))
            if landed != end + raw, pull < best {
                best = pull
                moved = landed - end
                caught = landed
            }
        }
        drag.byMS = moved
        drag.caughtMS = caught
        partBarDrag = drag
        rerender()
    }

    /// Let go: one undo step.
    func commitPartBarDrag() {
        guard let drag = partBarDrag else { return }
        partBarDrag = nil
        guard drag.byMS != 0, var probe = document,
              probe.retimePart(drag.pieceID, grab: drag.grab, byMS: drag.byMS)
        else { rerender(); return }
        perform { $0.retimePart(drag.pieceID, grab: drag.grab, byMS: drag.byMS) }
        rerender()
    }

    func cancelPartBarDrag() {
        guard partBarDrag != nil else { return }
        partBarDrag = nil
        rerender()
    }

    /// `document` with the part under the hand retimed, for the canvas and the
    /// part's bar to show the timing the hand has.
    func withDraggedPartBar(_ document: PhotonzDocument) -> PhotonzDocument {
        guard let drag = partBarDrag, drag.byMS != 0 else { return document }
        var document = document
        document.retimePart(drag.pieceID, grab: drag.grab, byMS: drag.byMS)
        return document
    }
}
