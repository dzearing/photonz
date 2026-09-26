import AppKit
import Foundation
import PhotonzCore
import PhotonzMedia

/// What is in the air over the timeline: where it lands, drawn on the lanes as
/// a ghost the length of the file (`video.html`, `.lane.drop`).
struct TimelineFileHover: Equatable {
    /// What the clip will be called, which is what the ghost says.
    var name: String
    var landing: ClipLanding

    /// The label for it, in the bar over the tracks and on a refused ghost:
    /// the edit, the track and the time, the way Premiere's drag says Insert
    /// or Overwrite. Never a sentence (`no-sentences-or-debug-readouts-anywhere-in-the-c`).
    var note: String {
        guard landing.allowed else { return landing.isLocked ? "Locked" : "Occupied" }
        let edit = landing.edit == .insert ? "Insert" : "Overwrite"
        let track: String
        if case .newTrack = landing.target {
            track = "New \(landing.trackName)"
        } else {
            track = landing.trackName
        }
        return "\(edit) · \(track) · \(CaptionProgress.clock(landing.startMS))"
    }
}

/// Where a file in the air is over the timeline, and whether ⌘ is held.
struct TimelineFilePointer {
    var point: CGPoint
    var insert: Bool
}

/// The file behind the ghost: what kind it is, and its reference once the
/// file has been read, which is kept so letting go does not read it twice.
struct TimelineFileInAir {
    var url: URL
    var kind: MediaDrop.Kind
    var movie: MovieRef?
    var sound: SoundRef?

    var lengthMS: Int? { movie?.durationMS ?? sound?.durationMS }
    var trackKind: DocumentTrack.Kind { kind == .sound ? .audio : .video }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

// A sound or a recording let go on the TIMELINE lands at the moment and on the
// track under the pointer (`ClipLanding`), where one let go on the picture
// lands at the playhead (`EditorState+MediaDrop`). The drop answer is one pure
// function either way; this is the part that knows about pointers and files.
extension EditorState {

    /// The width of the band either side of an edge a clip in the air is
    /// pulled onto, in points on the lane, which is what makes it the same
    /// reach at every zoom.
    static let timelineDropSnapPoints: CGFloat = 8

    /// A file has arrived over the timeline. Its length is read off it now, so
    /// the ghost can be drawn the length it will be.
    func beginTimelineFileHover(_ url: URL) {
        guard Experiments.shared.droppingMedia, document?.hasTime == true,
              let kind = MediaFiles.kind(of: url) else { return }
        guard timelineFileInAir?.url != url else { return }
        timelineFileInAir = TimelineFileInAir(url: url, kind: kind)
        Task { [weak self] in
            switch kind {
            case .recording:
                let movie = await MovieLibrary.shared.movie(at: url)
                guard let self, self.timelineFileInAir?.url == url else { return }
                self.timelineFileInAir?.movie = movie
            case .sound:
                let sound = await SoundLibrary.shared.sound(at: url)
                guard let self, self.timelineFileInAir?.url == url else { return }
                self.timelineFileInAir?.sound = sound
            }
            // Room at the end for it, held for as long as it is in the air,
            // so a clip let go after the last one has a lane to be drawn on.
            if let length = self?.timelineFileInAir?.lengthMS { self?.timelineDropRoomMS = length }
            self?.refreshTimelineFileHover()
        }
    }

    /// Where the pointer is, in the tracks' own space, as it crosses the
    /// timeline. `insert` is ⌘ held.
    func moveTimelineFileHover(to point: CGPoint, insert: Bool) {
        timelineFilePointer = TimelineFilePointer(point: point, insert: insert)
        refreshTimelineFileHover()
    }

    private func refreshTimelineFileHover() {
        guard let inAir = timelineFileInAir, let hover = timelineFilePointer,
              let landing = timelineLanding(for: inAir, at: hover.point, insert: hover.insert) else {
            if timelineFileHover != nil { timelineFileHover = nil }
            return
        }
        let next = TimelineFileHover(name: inAir.name, landing: landing)
        if timelineFileHover != next { timelineFileHover = next }
    }

    /// The file has left the timeline without landing.
    func endTimelineFileHover() {
        timelineFilePointer = nil
        timelineFileInAir = nil
        if timelineDropRoomMS != nil { timelineDropRoomMS = nil }
        if timelineFileHover != nil { timelineFileHover = nil }
    }

    /// Where a file in the air at `point` would land.
    func timelineLanding(for inAir: TimelineFileInAir, at point: CGPoint, insert: Bool) -> ClipLanding? {
        guard let document, let length = inAir.lengthMS, timelineLaneWidth > 0 else { return nil }
        let ruler = motionStripRuler
        let x = point.x - TimelineDock.lanesLeading
        let fraction = min(max(0, x / timelineLaneWidth), 1)
        let raw = Int(ruler.ms(atFraction: Double(fraction)).rounded())
        let reach = Int(ruler.msSpanning(fraction: Double(Self.timelineDropSnapPoints / timelineLaneWidth))
            .rounded())
        let start = ClipLanding.snapped(startMS: raw, lengthMS: length,
                                        to: document.timelineEdgesMS + [documentTimeMS],
                                        withinMS: isTimelineSnapping ? max(0, reach) : 0)
        return document.clipLanding(kind: inAir.trackKind, lengthMS: length, atMS: start,
                                    over: trackDrop(atY: point.y),
                                    edit: insert ? .insert : .overwrite)
    }

    /// The track, or the place between two, at a height in the tracks' own
    /// space: the same reading a clip carried up or down the timeline gets.
    func trackDrop(atY y: CGFloat) -> TrackDrop? {
        let rows = trackDropRows.values.sorted { $0.minY < $1.minY }
        return TrackDrop.resolve(y: y, rows: rows).map { resolved -> TrackDrop in
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
    }

    /// Let go over the timeline: the file lands where the ghost said.
    @discardableResult
    func dropTimelineFile(_ url: URL, at point: CGPoint, insert: Bool) async -> UUID? {
        guard Experiments.shared.droppingMedia, let kind = MediaFiles.kind(of: url) else { return nil }
        let inAir = timelineFileInAir?.url == url ? timelineFileInAir ?? TimelineFileInAir(url: url, kind: kind)
                                                  : TimelineFileInAir(url: url, kind: kind)
        // It lands where the ghost said, read before the ghost and the room
        // made for it go, since taking the room away moves the lane under the
        // pointer.
        let promised = timelineFileInAir?.url == url
            ? timelineLanding(for: inAir, at: point, insert: insert) : nil
        endTimelineFileHover()
        return await landTimelineFile(inAir) { [weak self] inAir in
            promised ?? self?.timelineLanding(for: inAir, at: point, insert: insert)
        }
    }

    /// A file put on the timeline at the playhead rather than under a pointer:
    /// a Library tile double clicked, or Add at Playhead on its menu. It goes
    /// over what is there on the picked track, the way Premiere's Overwrite
    /// does, and onto a track of its own when no track is picked, so nothing
    /// already cut is ever covered by a double click.
    @discardableResult
    func placeTimelineFileAtPlayhead(_ url: URL) async -> UUID? {
        guard Experiments.shared.droppingMedia, let kind = MediaFiles.kind(of: url) else { return nil }
        let at = documentTimeMS
        let picked = selectedTrackIDs.count == 1 ? selectedTrackIDs.first : nil
        return await landTimelineFile(TimelineFileInAir(url: url, kind: kind)) { [weak self] inAir in
            guard let document = self?.document, let length = inAir.lengthMS else { return nil }
            return document.clipLanding(kind: inAir.trackKind, lengthMS: length, atMS: at,
                                        over: picked.map { .onto($0) }, edit: .overwrite)
        }
    }

    /// Reads the file if nobody has yet, and lands it where `landing` says.
    /// The document remembers the file as it lands, under its own name, so it
    /// stays on the Library shelf after its last clip is cut away.
    private func landTimelineFile(_ inAir: TimelineFileInAir,
                                  landing: (TimelineFileInAir) -> ClipLanding?) async -> UUID? {
        var inAir = inAir
        let url = inAir.url
        switch inAir.kind {
        case .recording: if inAir.movie == nil { inAir.movie = await MovieLibrary.shared.movie(at: url) }
        case .sound: if inAir.sound == nil { inAir.sound = await SoundLibrary.shared.sound(at: url) }
        }
        guard let document, document.hasTime, let length = inAir.lengthMS else {
            raiseCanvasNotice(.mediaWouldNotOpen(name: url.lastPathComponent))
            return nil
        }
        guard let landing = landing(inAir), landing.allowed else { return nil }
        var layer: Layer
        let media: DocumentMediaSource.Media
        if let movie = inAir.movie {
            let frame = document.placementForIncomingImage(size: movie.pixelSize, at: nil)
            layer = Layer(name: inAir.name, content: .image(movie.frameRef(atSourceMS: 0)), frame: frame)
            layer.movie = movie
            layer.time = LayerTime(inMS: 0, outMS: length, sourceInMS: 0, sourceLengthMS: movie.durationMS)
            media = .recording(movie)
        } else if let sound = inAir.sound {
            layer = Layer.sound(sound, name: inAir.name,
                                time: LayerTime(inMS: 0, outMS: length, sourceLengthMS: sound.durationMS))
            media = .sound(sound)
        } else {
            return nil
        }
        var landed: UUID?
        pauseDocument()
        perform {
            landed = $0.land(layer, at: landing)
            if landed != nil { $0.rememberMedia(media, named: url.lastPathComponent) }
        }
        guard let landed else { return nil }
        selectLayer(landed)
        if let sound = inAir.sound { SoundLibrary.shared.loadWaveform(for: sound) }
        if let track = self.document?.trackID(ofClip: landed) { selectedTrackIDs = [track] }
        documentMomentChanged()
        raiseCanvasNotice(.landedOnTrack(name: inAir.name, track: landing.trackName,
                                         atMS: landing.startMS, isSound: inAir.movie == nil))
        return landed
    }

    // MARK: - Edit points

    /// Pick the cut between two clips.
    func pickEditPoint(_ point: TimelineEditPoint) {
        selectLayer(nil)
        selectedEditPoint = point
    }

    /// Whether this cut is the picked one and still there.
    func isEditPointPicked(_ point: TimelineEditPoint) -> Bool {
        selectedEditPoint?.id == point.id
    }
}
