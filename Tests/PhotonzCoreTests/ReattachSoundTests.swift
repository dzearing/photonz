import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Re-attach Audio** (`SoundClip.swift`, `docs/design/video-audio.md`).
///
/// Detach Audio takes a recording's sound off its picture and lays it on a
/// layer of its own. Re-attach is the way back that is not undo: the sound
/// layer goes, and the picture speaks for its recording again, linked and in
/// step with it however far the loose sound had been moved, trimmed or cut.
@Suite("Re-attach sound")
struct ReattachSoundTests {

    static func movie(_ ms: Int = 6000, sound: Bool = true) -> MovieRef {
        MovieRef(pixelSize: CGSize(width: 100, height: 100), durationMS: ms, hasSound: sound)
    }

    /// A recording with its sound detached: the document, the picture, the sound.
    static func detached(_ ms: Int = 6000) throws -> (PhotonzDocument, UUID, UUID) {
        let opened = PhotonzDocument.recording(movie(ms), name: "take")
        let clip = opened.layers[0].id
        let split = try #require(opened.detachingSound(ofLayer: clip))
        return (split.document, clip, split.soundLayerID)
    }

    // MARK: - When it is offered

    @Test("A clip whose sound is still on it has nothing to re-attach")
    func linkedClipOffersNothing() throws {
        let doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let clip = doc.layers[0].id
        #expect(doc.canReattachSound(ofLayer: clip) == false)
        #expect(doc.reattachingSound(ofLayer: clip) == nil)
    }

    @Test("After Detach Audio, both the picture and its sound offer Re-attach")
    func bothHalvesOfferIt() throws {
        let (doc, clip, sound) = try Self.detached()
        #expect(doc.canReattachSound(ofLayer: clip))
        #expect(doc.canReattachSound(ofLayer: sound))
        #expect(doc.canDetachSound(ofLayer: clip) == false)
    }

    @Test("Music brought in from a file has no picture to go back into")
    func musicOffersNothing() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let music = doc.addSound(SoundRef(durationMS: 4000), name: "music", atMS: 0)
        #expect(doc.canReattachSound(ofLayer: music) == false)
        #expect(doc.reattachingSound(ofLayer: music) == nil)
    }

    @Test("A recording with no sound track has nothing to re-attach")
    func silentRecordingOffersNothing() throws {
        var doc = PhotonzDocument.recording(Self.movie(sound: false), name: "take")
        let clip = doc.layers[0].id
        doc.updateLayer(id: clip) { $0.soundDetached = true }
        #expect(doc.canReattachSound(ofLayer: clip) == false)
    }

    // MARK: - What it does

    @Test("Re-attach from the picture: the sound layer goes and the picture speaks again")
    func reattachFromThePicture() throws {
        let (doc, clip, sound) = try Self.detached()
        let joined = try #require(doc.reattachingSound(ofLayer: clip))
        let after = joined.document
        #expect(joined.pictureID == clip)
        #expect(joined.soundLayerID == sound)
        #expect(after.layer(id: sound) == nil)
        #expect(after.layer(id: clip)?.sound != nil)
        #expect(after.layer(id: clip)?.hasLinkedSound == true)
        #expect(after.canDetachSound(ofLayer: clip))
        #expect(after.canReattachSound(ofLayer: clip) == false)
        // One layer playing the recording's sound, and it is the picture.
        #expect(after.audioMix().map(\.layerID) == [clip])
    }

    @Test("Re-attach from the sound does the same thing")
    func reattachFromTheSound() throws {
        let (doc, clip, sound) = try Self.detached()
        let joined = try #require(doc.reattachingSound(ofLayer: sound))
        #expect(joined.pictureID == clip)
        #expect(joined.document.layer(id: sound) == nil)
        #expect(joined.document.layer(id: clip)?.hasLinkedSound == true)
    }

    @Test("The sound goes back onto the audio track it was sitting on")
    func landsOnTheTrackItWasOn() throws {
        let (doc, clip, sound) = try Self.detached()
        let track = try #require(doc.trackID(ofClip: sound))
        let after = try #require(doc.reattachingSound(ofLayer: clip)).document
        #expect(after.linkedSoundTrackID(ofClip: clip) == track)
        #expect(after.timelineTracks.map(\.name) == ["V1", "Audio"])
    }

    @Test("Detach then re-attach leaves the timeline as it opened")
    func roundTripLooksTheSame() throws {
        let opened = PhotonzDocument.recording(Self.movie(), name: "take")
        let clip = opened.layers[0].id
        let detached = try #require(opened.detachingSound(ofLayer: clip)).document
        let after = try #require(detached.reattachingSound(ofLayer: clip)).document
        #expect(after.allLayers.count == 1)
        #expect(after.timelineTracks.map(\.name) == opened.timelineTracks.map(\.name))
        #expect(after.audioMix().map(\.startMS) == opened.audioMix().map(\.startMS))
        #expect(after.audioMix().map(\.sourceInMS) == opened.audioMix().map(\.sourceInMS))
    }

    // MARK: - Back in step

    @Test("A sound slid off its picture snaps back in step")
    func movedSoundSnapsBack() throws {
        var (doc, clip, sound) = try Self.detached()
        _ = doc.moveClip(sound, toInMS: 1500)
        let after = try #require(doc.reattachingSound(ofLayer: sound)).document
        let mix = after.audioMix()
        #expect(mix.count == 1)
        #expect(mix.first?.layerID == clip)
        #expect(mix.first?.startMS == 0)
        #expect(mix.first?.sourceInMS == 0)
    }

    @Test("A trimmed sound comes back whole, as long as its picture")
    func trimmedSoundComesBackWhole() throws {
        var (doc, clip, sound) = try Self.detached()
        doc.updateLayer(id: sound) { $0.time = $0.time?.withIn(2000).withOut(4000) }
        let after = try #require(doc.reattachingSound(ofLayer: clip)).document
        let mix = after.audioMix()
        #expect(mix.map(\.layerID) == [clip])
        #expect(mix.first?.startMS == 0)
        #expect(mix.first?.lengthMS == 6000)
    }

    // MARK: - What the sound had on it

    @Test("Volume, gain and effects set on the loose sound come back with it")
    func levelComesBack() throws {
        var (doc, clip, sound) = try Self.detached()
        var level = AudioLevel(gain: 0.5, clipGainDB: 6)
        level.setFadeIn(500, lengthMS: 6000)
        doc.updateLayer(id: sound) { $0.setSoundLevel(level) }
        let after = try #require(doc.reattachingSound(ofLayer: clip)).document
        #expect(after.layer(id: clip)?.soundLevel == level)
    }

    @Test("A level line drawn on a sound that was slid off step is let go; the rest stays")
    func offStepDropsTheLine() throws {
        var (doc, clip, sound) = try Self.detached()
        var level = AudioLevel(gain: 0.5, clipGainDB: 6)
        level.setFadeIn(500, lengthMS: 6000)
        doc.updateLayer(id: sound) { $0.setSoundLevel(level) }
        _ = doc.moveClip(sound, toInMS: 1500)
        let after = try #require(doc.reattachingSound(ofLayer: clip)).document
        let back = try #require(after.layer(id: clip)?.soundLevel)
        #expect(back.gain == 0.5)
        #expect(back.clipGainDB == 6)
        #expect(back.points.isEmpty)
    }

    // MARK: - More than one

    @Test("With two takes of one recording, each picture takes back its own sound")
    func pairsTheMatchingStretch() throws {
        // One recording laid down twice, each half of it, both detached.
        var doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let first = doc.layers[0].id
        doc.updateLayer(id: first) { $0.time = $0.time?.withOut(3000) }
        var second = try #require(doc.layer(id: first))
        second = second.duplicated()
        second.time = LayerTime(inMS: 3000, outMS: 6000, sourceInMS: 3000, sourceLengthMS: 6000)
        doc.addLayer(second)
        var split = try #require(doc.detachingSound(ofLayer: first))
        let firstSound = split.soundLayerID
        split = try #require(split.document.detachingSound(ofLayer: second.id))
        let secondSound = split.soundLayerID
        let detached = split.document

        let joined = try #require(detached.reattachingSound(ofLayer: second.id))
        #expect(joined.soundLayerID == secondSound)
        #expect(joined.document.layer(id: firstSound) != nil)
        let back = try #require(detached.reattachingSound(ofLayer: firstSound))
        #expect(back.pictureID == first)
    }

    @Test("A picture whose sound layer was deleted gets its own sound back")
    func deletedSoundComesBack() throws {
        var (doc, clip, sound) = try Self.detached()
        doc.removeLayers(ids: [sound])
        #expect(doc.canReattachSound(ofLayer: clip))
        let joined = try #require(doc.reattachingSound(ofLayer: clip))
        #expect(joined.soundLayerID == nil)
        #expect(joined.document.layer(id: clip)?.hasLinkedSound == true)
    }
}
