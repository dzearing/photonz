import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Tracks** on a document with time (`DocumentTracks.swift`,
/// `docs/design/mocks/pages/video.html`).
///
/// A track is a row of the timeline that holds any number of clips. It can be
/// added, renamed, grouped, hidden, muted, soloed and locked, and a clip can be
/// carried onto another track or onto a new one between two.
///
/// Written before the timeline uses them, which is the rule for `PhotonzCore`.
@Suite("Tracks")
struct DocumentTracksTests {

    static let movie = MovieRef(pixelSize: CGSize(width: 100, height: 100),
                                durationMS: 6000, hasSound: true)

    /// A recording at the bottom, a title over it, and some music.
    static func cut() -> (doc: PhotonzDocument, recording: UUID, title: UUID, music: UUID) {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        let recording = doc.layers[0].id
        var title = Layer(name: "Hello", content: .text(TextContent(string: "Hello")),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        title.time = LayerTime(inMS: 1000, outMS: 3000)
        doc.addLayer(title)
        let music = doc.addSound(SoundRef(durationMS: 5000), name: "music", atMS: 0)
        return (doc, recording, title.id, music)
    }

    // MARK: - A document that has never been given tracks

    @Test("A document nobody has touched shows a track per clip: picture on top, sound under it")
    func implicitTracks() {
        let (doc, recording, title, music) = Self.cut()
        let tracks = doc.timelineTracks
        // The recording's own sound on Audio, and the music on its own track.
        #expect(tracks.map(\.name) == ["Title", "V1", "Audio", "Audio 2"])
        #expect(tracks.map(\.kind) == [.video, .video, .audio, .audio])
        #expect(doc.clipIDs(onTrack: tracks[0].id) == [title])
        #expect(doc.clipIDs(onTrack: tracks[1].id) == [recording])
        #expect(doc.linkedSoundClipIDs(onTrack: tracks[2].id) == [recording])
        #expect(doc.clipIDs(onTrack: tracks[3].id) == [music])
        // Reading them writes nothing: a file nobody edited saves as it was.
        #expect(doc.tracks.isEmpty)
        #expect(doc.layers.allSatisfy { $0.trackID == nil })
    }

    @Test("A still document has no tracks")
    func stillDocumentHasNone() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10),
                                  layers: [Layer(name: "a", content: .text(TextContent(string: "a")),
                                                 frame: .zero)])
        #expect(doc.timelineTracks.isEmpty)
    }

    @Test("Writing the tracks down keeps every name, every id and every clip where it was")
    func materializingKeepsTheLayout() {
        var (doc, _, _, _) = Self.cut()
        let before = doc.timelineTracks
        let clips = before.map { doc.clipIDs(onTrack: $0.id) }
        doc.materializeTracks()
        #expect(doc.tracks == before)
        #expect(doc.timelineTracks == before)
        #expect(doc.timelineTracks.map { doc.clipIDs(onTrack: $0.id) } == clips)
    }

    // MARK: - Adding, naming, removing

    @Test("A new video track is named after the next free number and lands above the picture")
    func addVideoTrack() {
        var (doc, _, _, _) = Self.cut()
        let id = doc.addTrack(.video)
        #expect(doc.timelineTracks.first?.id == id)
        // V1 is the recording; the title's track is called Title.
        #expect(doc.timelineTracks.first?.name == "V2")
        #expect(doc.clipIDs(onTrack: id).isEmpty)
    }

    @Test("A new audio track lands under the sound and a captions track above the picture")
    func addAudioAndCaptions() {
        var (doc, _, _, _) = Self.cut()
        let audio = doc.addTrack(.audio)
        #expect(doc.timelineTracks.last?.id == audio)
        #expect(doc.timelineTracks.last?.name == "Audio 3")
        let captions = doc.addTrack(.captions)
        #expect(doc.timelineTracks.first?.id == captions)
        #expect(doc.timelineTracks.first?.name == "Captions")
    }

    @Test("A track can be added at a place")
    func addAtIndex() {
        var (doc, _, _, _) = Self.cut()
        let id = doc.addTrack(.video, at: 1)
        #expect(doc.timelineTracks.map(\.id).firstIndex(of: id) == 1)
    }

    @Test("Renaming a track keeps the words, trimmed; an empty name changes nothing")
    func rename() {
        var (doc, _, _, _) = Self.cut()
        let id = doc.timelineTracks[1].id
        let renamed = doc.renameTrack(id, to: "  Screen  ")
        #expect(renamed)
        #expect(doc.track(id: id)?.name == "Screen")
        let blank = doc.renameTrack(id, to: "   ")
        #expect(!blank)
        #expect(doc.track(id: id)?.name == "Screen")
    }

    @Test("Deleting a track deletes the clips on it")
    func deleteTrack() {
        var (doc, _, title, _) = Self.cut()
        let id = doc.timelineTracks[0].id
        doc.deleteTrack(id)
        #expect(doc.layer(id: title) == nil)
        #expect(!doc.timelineTracks.contains { $0.id == id })
        #expect(doc.timelineTracks.map(\.name) == ["V1", "Audio", "Audio 2"])
    }

    // MARK: - Hide, mute, solo, lock

    @Test("A hidden track's clips are not drawn, and showing it again brings them back")
    func hideTrack() {
        var (doc, recording, title, _) = Self.cut()
        let top = doc.timelineTracks[0].id
        doc.updateTrack(top) { $0.isHidden = true }
        let frame = doc.drawn(atTimeMS: 1500)
        #expect(frame.layer(id: title)?.isVisible == false)
        #expect(frame.layer(id: recording)?.isVisible == true)
        // The layer itself is untouched: the eye in the layers list is its own.
        #expect(doc.layer(id: title)?.isVisible == true)
        doc.updateTrack(top) { $0.isHidden = false }
        #expect(doc.drawn(atTimeMS: 1500).layer(id: title)?.isVisible == true)
    }

    @Test("Soloing a picture track shows only it; the sound is untouched")
    func soloPicture() {
        var (doc, recording, title, music) = Self.cut()
        doc.updateTrack(doc.timelineTracks[0].id) { $0.isSolo = true }
        let frame = doc.drawn(atTimeMS: 1500)
        #expect(frame.layer(id: title)?.isVisible == true)
        #expect(frame.layer(id: recording)?.isVisible == false)
        #expect(doc.audioMix().contains { $0.layerID == music })
    }

    @Test("A muted track is not heard")
    func muteTrack() throws {
        var (doc, recording, _, music) = Self.cut()
        let musicTrack = try #require(doc.trackID(ofClip: music))
        doc.updateTrack(musicTrack) { $0.isMuted = true }
        let mix = doc.audioMix()
        #expect(!mix.contains { $0.layerID == music })
        #expect(mix.contains { $0.layerID == recording })
    }

    @Test("Soloing a sound track silences everything else, the recording's own sound included")
    func soloSound() throws {
        var (doc, recording, _, music) = Self.cut()
        let musicTrack = try #require(doc.trackID(ofClip: music))
        doc.updateTrack(musicTrack) { $0.isSolo = true }
        let mix = doc.audioMix()
        #expect(mix.contains { $0.layerID == music })
        #expect(!mix.contains { $0.layerID == recording })
        // ...and the picture is still all there.
        #expect(doc.drawn(atTimeMS: 1500).layer(id: recording)?.isVisible == true)
    }

    @Test("A locked track says so for every clip on it")
    func lockTrack() {
        var (doc, recording, title, _) = Self.cut()
        doc.updateTrack(doc.timelineTracks[1].id) { $0.isLocked = true }
        #expect(doc.isClipOnLockedTrack(recording))
        #expect(!doc.isClipOnLockedTrack(title))
    }

    // MARK: - Moving clips between tracks

    @Test("A title carried onto the recording's track, clear of it in time, lands there and draws under what is above")
    func moveOntoTrack() throws {
        var (doc, recording, title, _) = Self.cut()
        // Make room on V1 for the title: the recording is cut down to its first second.
        doc.updateLayer(id: recording) { $0.time = LayerTime(inMS: 0, outMS: 1000, sourceLengthMS: 6000) }
        let v1 = doc.timelineTracks[1].id
        let moved = doc.moveClip(title, toTrack: v1)
        #expect(moved)
        #expect(doc.trackID(ofClip: title) == v1)
        #expect(Set(doc.clipIDs(onTrack: v1)) == [recording, title])
        // The track it left was written down and stays, empty, where it was.
        #expect(doc.timelineTracks.count == 4)
    }

    @Test("A clip cannot land where it would cover another clip on that track")
    func refusesOverlap() {
        var (doc, recording, title, _) = Self.cut()
        let v1 = doc.timelineTracks[1].id
        #expect(!doc.canPlace(title, onTrack: v1))
        let moved = doc.moveClip(title, toTrack: v1)
        #expect(!moved)
        #expect(doc.trackID(ofClip: title) != v1)
        _ = recording
    }

    @Test("It can be judged at the time it is about to land at")
    func overlapAtANewTime() {
        var (doc, recording, title, _) = Self.cut()
        doc.updateLayer(id: recording) { $0.time = LayerTime(inMS: 0, outMS: 1000, sourceLengthMS: 6000) }
        let v1 = doc.timelineTracks[1].id
        #expect(doc.canPlace(title, onTrack: v1, atInMS: 1000))
        #expect(!doc.canPlace(title, onTrack: v1, atInMS: 500))
    }

    @Test("Sound goes on sound tracks and picture on picture tracks")
    func kindsMatch() {
        let (doc, _, title, music) = Self.cut()
        #expect(!doc.canPlace(music, onTrack: doc.timelineTracks[0].id))
        #expect(!doc.canPlace(title, onTrack: doc.timelineTracks[2].id))
    }

    @Test("Nothing lands on a locked track")
    func lockedRefusesDrops() {
        var (doc, recording, title, _) = Self.cut()
        doc.updateLayer(id: recording) { $0.time = LayerTime(inMS: 0, outMS: 1000, sourceLengthMS: 6000) }
        let v1 = doc.timelineTracks[1].id
        doc.updateTrack(v1) { $0.isLocked = true }
        #expect(!doc.canPlace(title, onTrack: v1))
    }

    @Test("A clip dropped between two tracks makes a new track there, and the stack follows the tracks")
    func dropBetweenMakesATrack() throws {
        var (doc, recording, title, _) = Self.cut()
        // The title is carried to a new track UNDER the recording's.
        let made = doc.moveClipToNewTrack(title, at: 2)
        let new = try #require(made)
        let tracks = doc.timelineTracks
        #expect(tracks.map(\.id).firstIndex(of: new) == 2)
        #expect(doc.clipIDs(onTrack: new) == [title])
        #expect(tracks[2].kind == .video)
        // Lower on the timeline is further back in the picture.
        let order = doc.layers.map(\.id)
        let t = try #require(order.firstIndex(of: title))
        let r = try #require(order.firstIndex(of: recording))
        #expect(t < r)
    }

    @Test("A move is a value change only: undoing it is putting the old document back")
    func movesAreValues() {
        var (doc, _, title, _) = Self.cut()
        let before = doc
        _ = doc.moveClipToNewTrack(title, at: 0)
        #expect(doc != before)
    }

    // MARK: - Groups

    @Test("Grouping tracks gathers them together under one group, and ungrouping lets them go")
    func groupAndUngroup() throws {
        var (doc, _, _, _) = Self.cut()
        let ids = doc.timelineTracks.map(\.id)
        let grouped = doc.groupTracks([ids[0], ids[2]])
        let group = try #require(grouped)
        let tracks = doc.timelineTracks
        // Gathered next to the top one, in their order.
        #expect(tracks.map(\.id) == [ids[0], ids[2], ids[1], ids[3]])
        #expect(tracks[0].groupID == group && tracks[1].groupID == group)
        #expect(tracks[2].groupID == nil)
        #expect(doc.trackGroups.first?.name == "Group 1")
        doc.ungroupTracks(group)
        #expect(doc.timelineTracks.allSatisfy { $0.groupID == nil })
        #expect(doc.trackGroups.isEmpty)
    }

    // MARK: - Saving

    @Test("Tracks and a clip's track survive a save; a document without them writes neither")
    func codable() throws {
        var (doc, _, title, _) = Self.cut()
        let plain = try JSONEncoder().encode(doc)
        let text = String(decoding: plain, as: UTF8.self)
        #expect(!text.contains("\"tracks\""))
        #expect(!text.contains("trackID"))
        _ = doc.moveClipToNewTrack(title, at: 0)
        doc.updateTrack(doc.timelineTracks[1].id) { $0.isLocked = true }
        _ = doc.groupTracks([doc.timelineTracks[0].id])
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.timelineTracks == doc.timelineTracks)
        #expect(back.trackGroups == doc.trackGroups)
        #expect(back.trackID(ofClip: title) == doc.trackID(ofClip: title))
    }

    // MARK: - Where a drop lands

    @Test("A drop inside a row lands on its track; near a boundary, or past either end, it makes a new one")
    func dropTarget() {
        let a = UUID(), b = UUID()
        let rows = [TrackDropRow(trackID: a, minY: 0, maxY: 28),
                    TrackDropRow(trackID: b, minY: 34, maxY: 62)]
        #expect(TrackDrop.resolve(y: 14, rows: rows) == .onto(a))
        #expect(TrackDrop.resolve(y: 48, rows: rows) == .onto(b))
        #expect(TrackDrop.resolve(y: 31, rows: rows) == .newTrack(at: 1))
        #expect(TrackDrop.resolve(y: 27, rows: rows) == .newTrack(at: 1))
        #expect(TrackDrop.resolve(y: -8, rows: rows) == .newTrack(at: 0))
        #expect(TrackDrop.resolve(y: 70, rows: rows) == .newTrack(at: 2))
        #expect(TrackDrop.resolve(y: 1, rows: rows) == .newTrack(at: 0))
    }
}
