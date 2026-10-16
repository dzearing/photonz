import Foundation
import PhotonzCore

// MARK: - A component let go over the timeline (Next, video)

// `video-title-wt.html` step 10: the lower third dragged from the Library onto
// the Title track lands there, at that moment. A component is laid over the
// picture the way a title is, so it takes the landing a title tile takes: the
// track under the pointer when it is free, otherwise a track of its own, and
// never over or into the recording (`PhotonzDocument.titleLanding`).

extension EditorState {

    /// Whether a component let go over the timeline can land on it at all:
    /// a document with time, and components that know when they are on screen.
    var timelineTakesComponents: Bool {
        Experiments.shared.componentsEnabled && placementMomentMS != nil
    }

    /// Where a component let go at `point` (the tracks' own space) would land.
    /// Three seconds long, as anything newly placed in time is
    /// (`ComponentsInTime.swift`).
    func componentLanding(at point: CGPoint) -> ClipLanding? {
        guard timelineTakesComponents else { return nil }
        return timelineOverlayLanding(lengthMS: TitleTime.defaultLengthMS, at: point)
    }

    /// What the ghost calls a component in the air: the name its tile prints.
    func componentDropName(_ payload: ComponentDrag.Payload) -> String {
        componentEntries.first { $0.id == payload.componentID.uuidString }?.name
            ?? document?.mainComponent(componentID: payload.componentID)?.name
            ?? "Component"
    }

    /// A component tile has arrived over the timeline, or moved across it: the
    /// ghost a file draws, saying Component, its track and its time.
    func moveComponentHover(_ payload: ComponentDrag.Payload, to point: CGPoint) {
        timelineComponentInAir = payload
        // Room past the end for it, so one let go after the last clip has a
        // lane to be drawn on.
        if timelineDropRoomMS != TitleTime.defaultLengthMS { timelineDropRoomMS = TitleTime.defaultLengthMS }
        guard let landing = componentLanding(at: point) else {
            if timelineFileHover != nil { timelineFileHover = nil }
            return
        }
        let next = TimelineFileHover(name: componentDropName(payload), landing: landing, verb: "Component")
        if timelineFileHover != next { timelineFileHover = next }
    }

    /// The tile has left the timeline without landing.
    func endComponentHover() {
        timelineComponentInAir = nil
        endTimelineFileHover()
    }

    /// Let go over the timeline: a copy lands where the ghost said, in the
    /// middle of the picture, as one step to undo, picked, with the playhead
    /// on its in so it is on screen.
    @discardableResult
    func dropComponentOnTimeline(_ payload: ComponentDrag.Payload, at point: CGPoint) -> Bool {
        // Read before the room made for it goes, since taking the room away
        // moves the lane under the pointer.
        let landing = componentLanding(at: point)
        endComponentHover()
        guard let landing, landing.allowed else { return false }
        pauseDocument()
        guard placeComponent(componentID: payload.componentID, at: visibleCanvasCentre,
                             version: payload.version, onTimeline: landing) != nil else { return false }
        moveDocumentPlayhead(toMS: landing.startMS)
        return true
    }
}

extension PhotonzDocument {
    /// A copy just placed, landed where a drop over the timeline said. Should
    /// that landing no longer hold, it still arrives at the dropped moment.
    mutating func landPlacedComponent(_ id: UUID?, on landing: ClipLanding?) {
        guard let id, let landing else { return }
        if !landPlacedLayer(id, at: landing) { placeInTime(id, atTimeMS: landing.startMS) }
    }
}
