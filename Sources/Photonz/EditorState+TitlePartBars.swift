import AppKit
import PhotonzCore

/// A title part's bar on the timeline taken hold of: which part, which end,
/// and how far the hand has carried it, already caught on whatever it snapped
/// to (task `a-title-page-s-parts-each-have-their-own-labelle`).
struct TitlePartDrag: Equatable {
    let titleID: UUID
    let pieceID: UUID
    let index: Int
    let grab: TitlePartGrab
    /// The bar as it was when the hand took it.
    let from: TitlePartTiming
    var byMS: Int
    /// The moment the end in the hand caught on, nil while it is free.
    var caughtMS: Int?
}

extension EditorState {

    // MARK: The arrow on a title's track

    /// Whether a track holds a placed title, which earns its header the arrow
    /// that opens the title's part rows.
    func trackHasTitleParts(_ layerIDs: [UUID]) -> Bool {
        guard let document else { return false }
        return layerIDs.contains { id in
            guard let layer = document.layer(id: id) else { return false }
            return layer.group?.titleRecipe != nil && layer.isPlacedInTime && !layer.isComponentInstance
        }
    }

    /// Whether the arrow on track `trackID` has its title's parts open. Closed
    /// until somebody opens it.
    func titlePartRowsOpen(trackID: UUID) -> Bool {
        titlePartTracksOpened[trackID] ?? false
    }

    /// The arrow: open closes it, closed opens it.
    func toggleTitlePartRows(trackID: UUID) {
        titlePartTracksOpened[trackID] = !titlePartRowsOpen(trackID: trackID)
        timelineTrackRowsMemo = nil
    }

    // MARK: A part's bar

    /// The bar the row of the part `pieceID` draws: where the hand has it while
    /// it is being dragged, as the title is compiled otherwise. Nil for
    /// anything that is not a part of a placed title.
    func titlePartTiming(pieceID: UUID) -> TitlePartTiming? {
        guard let document, let titleID = document.titleLayerID(containing: pieceID),
              titleID != pieceID else { return nil }
        return withDraggedTitlePart(document).titlePartTimings(layerID: titleID)
            .first { $0.pieceID == pieceID }
    }

    /// A press on a part's bar: the part is picked, as a click on it in the
    /// picture picks it, and the drag starts from the bar as it is.
    func beginTitlePartDrag(pieceID: UUID, grab: TitlePartGrab) {
        guard let document, let titleID = document.titleLayerID(containing: pieceID),
              !isClipLocked(titleID),
              let timing = document.titlePartTimings(layerID: titleID).first(where: { $0.pieceID == pieceID })
        else { return }
        if selectedLayerID != pieceID { selectLayer(pieceID, inGroup: titleID) }
        titlePartDrag = TitlePartDrag(titleID: titleID, pieceID: pieceID, index: timing.index, grab: grab,
                                      from: timing, byMS: 0, caughtMS: nil)
    }

    /// The hand moved `byMS` along the timeline. The end in the hand catches
    /// on the playhead, the title's own ends, the other parts' ends and the
    /// markers when it comes within `catchMS` of one. Nothing is written down.
    func updateTitlePartDrag(byMS raw: Int, catchMS: Int) {
        guard var drag = titlePartDrag, let document else { return }
        let from = drag.from
        let base = from.titleInMS
        var moments = [documentTimeMS, base, base + (document.layer(id: drag.titleID)?.time?.lengthMS ?? 0)]
        moments += document.markers.map(\.atMS)
        for other in document.titlePartTimings(layerID: drag.titleID) where other.pieceID != drag.pieceID {
            moments += [base + other.startMS, base + other.inEndMS, base + other.outStartMS, base + other.endMS]
        }
        // The ends that travel with the hand, on the document's clock.
        let ends: [Int] = switch drag.grab {
        case .start: [base + from.startMS]
        case .end: [base + from.endMS]
        case .body: [base + from.startMS, base + from.endMS]
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
        titlePartDrag = drag
        rerender()
    }

    /// Let go: one undo step, and the Part section follows.
    func commitTitlePartDrag() {
        guard let drag = titlePartDrag else { return }
        titlePartDrag = nil
        guard drag.byMS != 0, var probe = document,
              probe.retimeTitlePart(layerID: drag.titleID, index: drag.index, grab: drag.grab, byMS: drag.byMS)
        else { rerender(); return }
        perform { $0.retimeTitlePart(layerID: drag.titleID, index: drag.index, grab: drag.grab, byMS: drag.byMS) }
        rerender()
    }

    func cancelTitlePartDrag() {
        guard titlePartDrag != nil else { return }
        titlePartDrag = nil
        rerender()
    }

    /// `document` with the part under the hand retimed, for the canvas and the
    /// part's bar to show the timing the hand has.
    func withDraggedTitlePart(_ document: PhotonzDocument) -> PhotonzDocument {
        guard let drag = titlePartDrag, drag.byMS != 0 else { return document }
        var document = document
        document.retimeTitlePart(layerID: drag.titleID, index: drag.index, grab: drag.grab, byMS: drag.byMS)
        return document
    }
}
