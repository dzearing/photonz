import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A clip's own sound, on an audio track under it** (`DocumentTracks.swift`,
/// `docs/design/mocks/pages/video.html`).
///
/// A recording carries its sound. On the timeline that sound is a segment of
/// its own on an audio track under the picture, LINKED to its clip the way
/// Premiere links a clip's audio: it is the clip's own time, cuts and level
/// drawn a second time, so moving, trimming or cutting the clip moves, trims
/// and cuts its sound with no second thing to keep in step. Detach Audio is
/// what breaks the link.
@Suite("Linked sound")
struct LinkedSoundTests {

    static func movie(_ ms: Int = 6000, sound: Bool = true) -> MovieRef {
        MovieRef(pixelSize: CGSize(width: 100, height: 100), durationMS: ms, hasSound: sound)
    }

    static func clip(_ movie: MovieRef, name: String, atMS: Int) -> Layer {
        var layer = Layer(name: name, content: .image(movie.frameRef(atSourceMS: 0)),
                          frame: CGRect(origin: .zero, size: movie.pixelSize))
        layer.movie = movie
        layer.time = LayerTime(inMS: atMS, outMS: atMS + movie.durationMS,
                               sourceInMS: 0, sourceLengthMS: movie.durationMS)
        return layer
    }

    // MARK: - From the moment it opens

    @Test("A recording with sound opens with its sound on an Audio track under the picture")
    func recordingOpensWithALinkedSegment() throws {
        let doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let clip = try #require(doc.layers.first?.id)
        let tracks = doc.timelineTracks
        #expect(tracks.map(\.name) == ["V1", "Audio"])
        #expect(tracks.map(\.kind) == [.video, .audio])
        #expect(doc.clipIDs(onTrack: tracks[0].id) == [clip])
        // The audio track holds no layer of its own: it holds the clip's sound.
        #expect(doc.clipIDs(onTrack: tracks[1].id).isEmpty)
        #expect(doc.linkedSoundClipIDs(onTrack: tracks[1].id) == [clip])
        #expect(doc.linkedSoundTrackID(ofClip: clip) == tracks[1].id)
        // Reading it writes nothing, and makes no second layer.
        #expect(doc.tracks.isEmpty)
        #expect(doc.allLayers.count == 1)
    }

    @Test("The audio track under a clip keeps its id however often it is read")
    func linkedTrackIsStable() throws {
        let doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let clip = try #require(doc.layers.first?.id)
        #expect(doc.linkedSoundTrackID(ofClip: clip) == doc.linkedSoundTrackID(ofClip: clip))
        #expect(doc.linkedSoundTrackID(ofClip: clip) != clip)
    }

    @Test("A recording with no sound still shows an empty Audio track, as the mock does")
    func silentRecordingHasAnEmptyAudioTrack() throws {
        let doc = PhotonzDocument.recording(Self.movie(sound: false), name: "take")
        let clip = try #require(doc.layers.first?.id)
        #expect(doc.timelineTracks.map(\.name) == ["V1", "Audio"])
        #expect(doc.linkedSoundTrackID(ofClip: clip) == nil)
        let audio = try #require(doc.timelineTracks.last?.id)
        #expect(doc.clipIDs(onTrack: audio).isEmpty)
        #expect(doc.linkedSoundClipIDs(onTrack: audio).isEmpty)
    }

    @Test("A document with no recording in it gets no empty Audio track")
    func titlesOnlyGetNoAudioTrack() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [])
        var title = Layer(name: "Hello", content: .text(TextContent(string: "Hello")),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        title.time = LayerTime(inMS: 0, outMS: 3000)
        doc.addLayer(title)
        doc.durationMS = 3000
        #expect(!doc.timelineTracks.contains { $0.kind == .audio })
    }

    @Test("Two clips one after the other share the Audio track; music gets a track of its own")
    func clipsInARowShareOneAudioTrack() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "intro")
        let intro = doc.layers[0].id
        doc.materializeTracks()
        let v1 = try #require(doc.timelineTracks.first { $0.kind == .video }?.id)
        var demo = Self.clip(Self.movie(4000), name: "demo", atMS: 6000)
        demo.trackID = v1
        doc.addLayer(demo)
        let music = doc.addSound(SoundRef(durationMS: 9000), name: "music", atMS: 0)
        let audio = try #require(doc.linkedSoundTrackID(ofClip: intro))
        #expect(doc.linkedSoundTrackID(ofClip: demo.id) == audio)
        #expect(Set(doc.linkedSoundClipIDs(onTrack: audio)) == [intro, demo.id])
        let musicTrack = try #require(doc.trackID(ofClip: music))
        #expect(musicTrack != audio)
        #expect(doc.track(id: musicTrack)?.kind == .audio)
    }

    @Test("A clip over another clip in time puts its sound on a second audio track")
    func overlappingClipsGetTheirOwnAudioTracks() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "screen")
        let screen = doc.layers[0].id
        let pip = Self.clip(Self.movie(3000), name: "face", atMS: 1000)
        doc.addLayer(pip)
        #expect(doc.timelineTracks.map(\.name) == ["V2", "V1", "Audio", "Audio 2"])
        // The bottom picture's sound takes the first audio track.
        #expect(doc.linkedSoundTrackID(ofClip: screen) == doc.timelineTracks[2].id)
        #expect(doc.linkedSoundTrackID(ofClip: pip.id) == doc.timelineTracks[3].id)
    }

    @Test("Both halves of a clip an insert splits keep their own linked sound")
    func splitHalvesStayLinked() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let clip = doc.layers[0].id
        let cut = doc.splitClip(clip, atMS: 3000)
        #expect(cut)
        // A cut is pieces inside one clip, so its sound is one segment with
        // the same join in it, drawn off the same clip.
        #expect(doc.linkedSoundTrackID(ofClip: clip) != nil)
        #expect(doc.layer(id: clip)?.clipPieces?.count == 2)
    }

    // MARK: - Linked means one thing

    @Test("Moving the clip moves its sound: the segment is the clip's own time")
    func movingTheClipMovesItsSound() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let clip = doc.layers[0].id
        _ = doc.moveClip(clip, toInMS: 2000)
        let mix = doc.audioMix()
        #expect(mix.first?.layerID == clip)
        #expect(mix.first?.startMS == 2000)
    }

    // MARK: - Detach Audio

    @Test("Detach Audio puts the sound on the very track its linked segment was on")
    func detachLandsOnTheLinkedTrack() throws {
        let doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let clip = doc.layers[0].id
        let linked = try #require(doc.linkedSoundTrackID(ofClip: clip))
        let split = try #require(doc.detachingSound(ofLayer: clip))
        let after = split.document
        #expect(after.linkedSoundTrackID(ofClip: clip) == nil)
        #expect(after.trackID(ofClip: split.soundLayerID) == linked)
        #expect(after.timelineTracks.map(\.name) == ["V1", "Audio"])
        #expect(after.linkedSoundClipIDs(onTrack: linked).isEmpty)
    }

    @Test("After Detach Audio, moving the picture leaves the sound where it was")
    func detachedSoundStaysPut() throws {
        let opened = PhotonzDocument.recording(Self.movie(), name: "take")
        let clip = opened.layers[0].id
        let split = try #require(opened.detachingSound(ofLayer: clip))
        var doc = split.document
        _ = doc.moveClip(clip, toInMS: 2000)
        #expect(doc.layer(id: clip)?.time?.inMS == 2000)
        #expect(doc.layer(id: split.soundLayerID)?.time?.inMS == 0)
    }

    // MARK: - Heard or not

    @Test("Muting the audio track under a clip silences its sound and leaves its picture")
    func mutingTheLinkedTrack() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let clip = doc.layers[0].id
        let audio = try #require(doc.linkedSoundTrackID(ofClip: clip))
        doc.updateTrack(audio) { $0.isMuted = true }
        #expect(!doc.audioMix().contains { $0.layerID == clip })
        #expect(doc.drawn(atTimeMS: 1000).layer(id: clip)?.isVisible == true)
        doc.updateTrack(audio) { $0.isMuted = false }
        #expect(doc.audioMix().contains { $0.layerID == clip })
    }

    @Test("Soloing the audio track under a clip keeps its sound and silences the music")
    func soloingTheLinkedTrack() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let clip = doc.layers[0].id
        let music = doc.addSound(SoundRef(durationMS: 3000), name: "music", atMS: 0)
        let audio = try #require(doc.linkedSoundTrackID(ofClip: clip))
        doc.updateTrack(audio) { $0.isSolo = true }
        let mix = doc.audioMix()
        #expect(mix.contains { $0.layerID == clip })
        #expect(!mix.contains { $0.layerID == music })
    }

    @Test("Deleting the audio track under a clip takes its sound away and keeps its picture")
    func deletingTheLinkedTrack() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let clip = doc.layers[0].id
        let audio = try #require(doc.linkedSoundTrackID(ofClip: clip))
        doc.deleteTrack(audio)
        #expect(doc.layer(id: clip) != nil)
        #expect(doc.layer(id: clip)?.sound == nil)
        #expect(!doc.audioMix().contains { $0.layerID == clip })
    }

    @Test("Music dropped over a linked segment takes the lane; the clip's sound moves down a track")
    func soundLayerWinsTheLane() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let clip = doc.layers[0].id
        doc.materializeTracks()
        let audio = try #require(doc.linkedSoundTrackID(ofClip: clip))
        let music = doc.addSound(SoundRef(durationMS: 3000), name: "music", atMS: 0)
        doc.updateLayer(id: music) { $0.trackID = audio }
        #expect(doc.trackID(ofClip: music) == audio)
        let moved = try #require(doc.linkedSoundTrackID(ofClip: clip))
        #expect(moved != audio)
        #expect(Set(doc.timelineTracks.map(\.id)).count == doc.timelineTracks.count)
    }
}

/// **Fades** are two points on a sound's level, and a handle at each top
/// corner of its segment writes them.
@Suite("Sound fades")
struct SoundFadeTests {

    @Test("A level nobody has touched has no fades")
    func untouched() {
        let level = AudioLevel()
        #expect(level.fadeInMS == 0)
        #expect(level.fadeOutMS(lengthMS: 5000) == 0)
    }

    @Test("A fade in is silence at the start rising to the level")
    func fadeIn() {
        var level = AudioLevel()
        level.setFadeIn(1500, lengthMS: 5000)
        #expect(level.fadeInMS == 1500)
        #expect(level.gain(atLayerMS: 0) == 0)
        #expect(abs(level.gain(atLayerMS: 750) - 0.5) < 0.001)
        #expect(level.gain(atLayerMS: 1500) == 1)
        #expect(level.gain(atLayerMS: 4000) == 1)
    }

    @Test("A fade out falls to silence at the end")
    func fadeOut() {
        var level = AudioLevel()
        level.setFadeOut(1000, lengthMS: 5000)
        #expect(level.fadeOutMS(lengthMS: 5000) == 1000)
        #expect(level.gain(atLayerMS: 4000) == 1)
        #expect(level.gain(atLayerMS: 5000) == 0)
        #expect(level.fadeInMS == 0)
    }

    @Test("Both fades together, and changing one leaves the other")
    func bothFades() {
        var level = AudioLevel()
        level.setFadeIn(1000, lengthMS: 5000)
        level.setFadeOut(2000, lengthMS: 5000)
        level.setFadeIn(500, lengthMS: 5000)
        #expect(level.fadeInMS == 500)
        #expect(level.fadeOutMS(lengthMS: 5000) == 2000)
        #expect(level.points.count == 4)
    }

    @Test("A fade dragged back to nothing leaves no points behind")
    func fadeRemoved() {
        var level = AudioLevel()
        level.setFadeIn(1000, lengthMS: 5000)
        level.setFadeIn(0, lengthMS: 5000)
        #expect(level.points.isEmpty)
        #expect(level.isUntouched)
    }

    @Test("A fade in never runs into the fade out")
    func fadesDoNotCross() {
        var level = AudioLevel()
        level.setFadeOut(3000, lengthMS: 5000)
        level.setFadeIn(4000, lengthMS: 5000)
        #expect(level.fadeInMS <= 2000)
        #expect(level.fadeOutMS(lengthMS: 5000) == 3000)
    }

    @Test("A fade rises to the level the shape already had there, so a duck is kept")
    func fadeKeepsTheShape() {
        var level = AudioLevel()
        level.setPoint(atMS: 2000, gain: 0.5)
        level.setPoint(atMS: 3000, gain: 0.5)
        level.setFadeIn(1000, lengthMS: 5000)
        #expect(level.gain(atLayerMS: 1000) == 0.5)
        #expect(level.gain(atLayerMS: 2500) == 0.5)
    }

    @Test("The fader moves the whole shape, fades included")
    func faderCarriesTheFades() {
        var level = AudioLevel()
        level.setFadeIn(1000, lengthMS: 5000)
        level.gain = 0.5
        #expect(level.gain(atLayerMS: 3000) == 0.5)
        #expect(level.fadeInMS == 1000)
    }
}
