import AppKit
import Foundation
import PhotonzCore

/// Where a clip carried up or down the timeline would land, and whether it
/// may: a track of the wrong kind, a locked one, or one with something already
/// there at that time says no.
struct ClipTrackDrop: Equatable {
    let target: TrackDrop
    let allowed: Bool
}

/// One track as the timeline dock draws it: the track, the clips on it, and
/// the rows of anything inside those clips that moves on its own.
struct TimelineTrackRowModel: Identifiable {
    let track: DocumentTrack
    /// The top level clips on the track, one bar each.
    let clips: [MotionStripGroup]
    /// Parts inside those clips with time or motion of their own, drawn as
    /// rows of their own under the track the way the strip always drew them.
    let inner: [MotionStripGroup]
    /// Switched off, or left out by another track being soloed: its clips are
    /// drawn faint, because the picture or the mix is going on without them.
    let isOff: Bool

    var id: UUID { track.id }

    /// A lane with sound on it is the kit's taller lane, because its level
    /// line needs somewhere to be dragged.
    var carriesSound: Bool { track.kind == .audio || clips.contains(where: \.isSound) }
}

/// One row of the dock's grid: a group's heading or a track.
enum TimelineRowModel: Identifiable {
    case group(DocumentTrackGroup, isCollapsed: Bool, tracks: [TimelineTrackRowModel])
    case track(TimelineTrackRowModel, inGroup: Bool)

    var id: UUID {
        switch self {
        case .group(let group, _, _): group.id
        case .track(let row, _): row.id
        }
    }
}

/// **Tracks on the timeline** (`DocumentTracks.swift`): the thin layer between
/// the dock and the document. Every change goes through `perform`, so each is
/// one step to undo.
extension EditorState {

    // MARK: What the dock draws

    /// Every track, top to bottom, with what is on it.
    var timelineTrackRows: [TimelineTrackRowModel] {
        guard let document = shownDocument else { return [] }
        let groups = motionStripGroups
        let byLayer = Dictionary(groups.map { ($0.layerID, $0) }, uniquingKeysWith: { a, _ in a })
        let tracks = document.timelineTracks
        let soloPicture = tracks.contains { $0.kind != .audio && $0.isSolo }
        let soloSound = tracks.contains { $0.kind == .audio && $0.isSolo }
        return tracks.map { track in
            var clips: [MotionStripGroup] = []
            var inner: [MotionStripGroup] = []
            for id in document.clipIDs(onTrack: track.id) {
                if let group = byLayer[id] { clips.append(group) }
                guard let layer = document.layer(id: id) else { continue }
                for part in layer.selfAndDescendants.dropFirst() {
                    if let group = byLayer[part.id] { inner.append(group) }
                }
            }
            let isOff = track.kind == .audio
                ? track.isMuted || (soloSound && !track.isSolo)
                : track.isHidden || (soloPicture && !track.isSolo)
            return TimelineTrackRowModel(track: track, clips: clips, inner: inner, isOff: isOff)
        }
    }

    /// The dock's rows: tracks, with a heading over each run of tracks in one
    /// group, and a folded group's tracks left out.
    var timelineRows: [TimelineRowModel] {
        let tracks = timelineTrackRows
        let groups = Dictionary((document?.trackGroups ?? []).map { ($0.id, $0) },
                                uniquingKeysWith: { a, _ in a })
        var rows: [TimelineRowModel] = []
        var index = 0
        while index < tracks.count {
            guard let groupID = tracks[index].track.groupID, let group = groups[groupID] else {
                rows.append(.track(tracks[index], inGroup: false))
                index += 1
                continue
            }
            var run: [TimelineTrackRowModel] = []
            while index < tracks.count, tracks[index].track.groupID == groupID {
                run.append(tracks[index])
                index += 1
            }
            let folded = collapsedTrackGroupIDs.contains(groupID)
            rows.append(.group(group, isCollapsed: folded, tracks: run))
            if !folded { rows += run.map { .track($0, inGroup: true) } }
        }
        return rows
    }

    // MARK: Picking tracks

    /// A click on a track's header picks it, and the clip on it so the panel
    /// talks about it; ⇧ or ⌘ adds it to the tracks already picked, which is
    /// what Group Tracks gathers.
    func pickTrack(_ id: UUID, extending: Bool) {
        if extending {
            if selectedTrackIDs.contains(id) { selectedTrackIDs.remove(id) } else { selectedTrackIDs.insert(id) }
            return
        }
        selectedTrackIDs = [id]
        if let clip = document?.clipIDs(onTrack: id).first { selectLayer(clip) }
    }

    /// The tracks a menu on `id` acts on: the picked ones when it is one of
    /// them, otherwise just it.
    func tracksActedOn(from id: UUID) -> [UUID] {
        guard selectedTrackIDs.contains(id) else { return [id] }
        let order = document?.timelineTracks.map(\.id) ?? []
        return order.filter { selectedTrackIDs.contains($0) }
    }

    // MARK: Changing them

    func addTrack(_ kind: DocumentTrack.Kind, at index: Int? = nil) {
        var made: UUID?
        perform { made = $0.addTrack(kind, at: index) }
        if let made { selectedTrackIDs = [made] }
    }

    func beginRenamingTrack(_ id: UUID) {
        selectedTrackIDs = [id]
        renamingTrackID = id
    }

    func renameTrack(_ id: UUID, to name: String) {
        renamingTrackID = nil
        guard document?.track(id: id)?.name != name.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return }
        perform { $0.renameTrack(id, to: name) }
    }

    func toggleTrackHidden(_ id: UUID) { perform { $0.updateTrack(id) { $0.isHidden.toggle() } } }
    func toggleTrackMuted(_ id: UUID) {
        perform { $0.updateTrack(id) { $0.isMuted.toggle() } }
        documentMomentChanged()
    }
    func toggleTrackSolo(_ id: UUID) {
        perform { $0.updateTrack(id) { $0.isSolo.toggle() } }
        documentMomentChanged()
    }
    func toggleTrackLocked(_ id: UUID) { perform { $0.updateTrack(id) { $0.isLocked.toggle() } } }

    func deleteTrack(_ id: UUID) {
        selectedTrackIDs.remove(id)
        perform { $0.deleteTrack(id) }
        documentTimeMS = min(documentTimeMS, lastDocumentTimeMS)
        documentMomentChanged()
    }

    /// Gather the tracks a menu acts on into a group.
    func groupTracks(from id: UUID) {
        let ids = tracksActedOn(from: id)
        perform { _ = $0.groupTracks(ids) }
    }

    /// Group the picked tracks: the menu's command, and what a walk asks for.
    var canGroupPickedTracks: Bool { !selectedTrackIDs.isEmpty }
    func groupPickedTracks() {
        guard let first = document?.timelineTracks.map(\.id).first(where: selectedTrackIDs.contains)
        else { return }
        groupTracks(from: first)
    }

    func ungroupTracks(_ groupID: UUID) {
        collapsedTrackGroupIDs.remove(groupID)
        perform { $0.ungroupTracks(groupID) }
    }

    func renameTrackGroup(_ id: UUID, to name: String) {
        renamingTrackID = nil
        perform { $0.renameTrackGroup(id, to: name) }
    }

    func toggleTrackGroupCollapsed(_ id: UUID) {
        if collapsedTrackGroupIDs.contains(id) {
            collapsedTrackGroupIDs.remove(id)
        } else {
            collapsedTrackGroupIDs.insert(id)
        }
    }

    // MARK: Carrying a clip between tracks

    /// The clip in hand has been carried to `pointerY` in the tracks' own
    /// space, having travelled `travelledY` up or down since it was grabbed.
    ///
    /// A clip only leaves its track once it has been carried clearly up or
    /// down, so a sideways slide started near the top of a lane never makes a
    /// track by accident.
    func updateClipTrackDrop(pointerY: CGFloat, travelledY: CGFloat) {
        guard let session = clipBarDrag, case .body = session.grab, abs(travelledY) >= 8 else {
            if clipTrackDrop != nil { clipTrackDrop = nil }
            return
        }
        let rows = trackDropRows.values.sorted { $0.minY < $1.minY }
        let drop = TrackDrop.resolve(y: pointerY, rows: rows).map { resolved -> TrackDrop in
            // A place between two rows ON SCREEN, said as a place in the whole
            // list of tracks, which also holds any a folded group hides.
            guard case .newTrack(let at) = resolved else { return resolved }
            let order = document?.timelineTracks.map(\.id) ?? []
            if at < rows.count, let index = order.firstIndex(of: rows[at].trackID) {
                return .newTrack(at: index)
            }
            if let last = rows.last, let index = order.firstIndex(of: last.trackID) {
                return .newTrack(at: index + 1)
            }
            return .newTrack(at: order.count)
        }
        setClipTrackDrop(drop)
    }

    /// Aim the clip in hand at a track, or at a new one, or back at its own.
    func setClipTrackDrop(_ drop: TrackDrop?) {
        guard let session = clipBarDrag, let document, let drop else {
            if clipTrackDrop != nil { clipTrackDrop = nil }
            return
        }
        let id = session.layerID
        let result: ClipTrackDrop?
        switch drop {
        case .onto(let track):
            result = track == document.trackID(ofClip: id) ? nil
                : ClipTrackDrop(target: drop, allowed: document.canPlace(
                    id, onTrack: track, atInMS: session.landing.clipStartMS))
        case .newTrack:
            result = ClipTrackDrop(target: drop, allowed: !document.isClipOnLockedTrack(id))
        }
        if clipTrackDrop != result { clipTrackDrop = result }
    }

    /// Let go of a clip that was carried onto a track: the slide and the change
    /// of track are one step to undo.
    func landClip(_ id: UUID, atInMS inMS: Int, moved: Bool, on drop: ClipTrackDrop) {
        perform { document in
            if moved { document.moveClip(id, toInMS: inMS) }
            switch drop.target {
            case .onto(let track): document.moveClip(id, toTrack: track)
            case .newTrack(let at): document.moveClipToNewTrack(id, at: at)
            }
        }
        if let track = document?.trackID(ofClip: id) { selectedTrackIDs = [track] }
    }

    /// What the capsule adds while a clip is carried over the tracks.
    var clipTrackDropReading: String? {
        guard let drop = clipTrackDrop else { return nil }
        switch drop.target {
        case .onto(let id):
            let name = document?.track(id: id)?.name ?? "track"
            return drop.allowed ? "to \(name)" : "no room on \(name)"
        case .newTrack:
            return drop.allowed ? "to a new track" : nil
        }
    }

    /// Whether a clip sits on a locked track, which is every gesture on it
    /// turned off.
    func isClipLocked(_ layerID: UUID) -> Bool {
        shownDocument?.isClipOnLockedTrack(layerID) ?? false
    }
}
