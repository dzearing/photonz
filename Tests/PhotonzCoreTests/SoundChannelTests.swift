import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **The Channel section** for a picked sound (`docs/design/mocks/pages/
/// video-audio.html`, `#propBody`): the file name beside its header, Mute and
/// Solo, and a Volume slider in decibels.
///
/// Mute and Solo are the switches on the sound's own track, the same ones on
/// the track header, never a second mute on the layer: a clip's own sound
/// answers to the audio track it is drawn on, a piece of sound to the track it
/// sits on.
@Suite("Sound channel")
struct SoundChannelTests {

    static func movie(_ ms: Int = 6000) -> MovieRef {
        MovieRef(pixelSize: CGSize(width: 100, height: 100), durationMS: ms, hasSound: true)
    }

    // MARK: - Which track Mute and Solo switch

    @Test("A clip's own sound answers to the audio track it is drawn on, not its picture track")
    func clipSoundUsesItsLinkedTrack() throws {
        let doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let clip = doc.layers[0].id
        let linked = try #require(doc.linkedSoundTrackID(ofClip: clip))
        #expect(doc.soundTrackID(ofLayer: clip) == linked)
        #expect(doc.soundTrackID(ofLayer: clip) != doc.trackID(ofClip: clip))
    }

    @Test("A piece of sound answers to the track it sits on")
    func soundLayerUsesItsOwnTrack() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let music = doc.addSound(SoundRef(durationMS: 3000), name: "music", atMS: 0)
        let track = try #require(doc.trackID(ofClip: music))
        #expect(doc.soundTrackID(ofLayer: music) == track)
        #expect(doc.track(id: track)?.kind == .audio)
    }

    @Test("A detached sound answers to the track it landed on")
    func detachedSoundUsesItsTrack() throws {
        let opened = PhotonzDocument.recording(Self.movie(), name: "take")
        let clip = opened.layers[0].id
        let linked = try #require(opened.linkedSoundTrackID(ofClip: clip))
        let split = try #require(opened.detachingSound(ofLayer: clip))
        #expect(split.document.soundTrackID(ofLayer: split.soundLayerID) == linked)
        // The picture makes no sound any more, so it has no channel.
        #expect(split.document.soundTrackID(ofLayer: clip) == nil)
    }

    @Test("Something that makes no sound has no channel")
    func silentLayerHasNoChannel() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        let box = Layer(name: "box", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                        frame: .zero)
        doc.addLayer(box)
        #expect(doc.soundTrackID(ofLayer: box.id) == nil)
        #expect(doc.soundTrackID(ofLayer: UUID()) == nil)
    }

    @Test("Muting the channel's track silences exactly that sound")
    func mutingTheChannelTrack() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let clip = doc.layers[0].id
        let music = doc.addSound(SoundRef(durationMS: 3000), name: "music", atMS: 0)
        let track = try #require(doc.soundTrackID(ofLayer: music))
        doc.updateTrack(track) { $0.isMuted = true }
        let mix = doc.audioMix()
        #expect(!mix.contains { $0.layerID == music })
        #expect(mix.contains { $0.layerID == clip })
        #expect(doc.track(id: try #require(doc.soundTrackID(ofLayer: music)))?.isMuted == true)
    }

    // MARK: - The name beside the header

    @Test("The header names the file the sound came from")
    func fileNameIsTheRememberedOne() {
        var doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let sound = SoundRef(durationMS: 3000)
        let music = doc.addSound(sound, name: "music", atMS: 0)
        doc.rememberMedia(.sound(sound), named: "music.wav")
        #expect(doc.soundFileName(ofLayer: music) == "music.wav")
    }

    @Test("A clip's own sound is named by its recording's file")
    func clipSoundIsNamedByItsRecording() {
        let movie = Self.movie()
        var doc = PhotonzDocument.recording(movie, name: "take")
        doc.rememberMedia(.recording(movie), named: "take.mov")
        #expect(doc.soundFileName(ofLayer: doc.layers[0].id) == "take.mov")
    }

    @Test("A sound whose file was never remembered is named by its layer")
    func unrememberedFileFallsBackToTheLayerName() {
        var doc = PhotonzDocument.recording(Self.movie(), name: "take")
        let music = doc.addSound(SoundRef(durationMS: 3000), name: "music", atMS: 0)
        #expect(doc.soundFileName(ofLayer: music) == "music")
        #expect(doc.soundFileName(ofLayer: UUID()) == nil)
    }

    // MARK: - The Volume slider

    @Test("The Volume slider runs from -24 to +6 dB, as the mock draws it")
    func volumeRange() {
        #expect(AudioLevel.volumeRangeDB == -24...6)
    }

    @Test("The slider sits at the level's decibels, and at its foot for silence")
    func sliderPosition() {
        #expect(AudioLevel.volumeSliderDB(forGain: 1) == 0)
        #expect(abs(AudioLevel.volumeSliderDB(forGain: 0.5) - -6.02) < 0.01)
        #expect(AudioLevel.volumeSliderDB(forGain: 0) == -24)
        #expect(AudioLevel.volumeSliderDB(forGain: 0.001) == -24)
        #expect(AudioLevel.volumeSliderDB(forGain: AudioLevel.loudestGain) == 6)
    }

    @Test("Dragging the slider lands on half decibels, as the mock's step does")
    func sliderLandsOnHalfDecibels() throws {
        let gain = AudioLevel.volumeGain(sliderDB: -3.3)
        let dB = try #require(AudioLevel.decibels(forGain: gain))
        #expect(abs(dB - -3.5) < 0.001)
        #expect(AudioLevel.volumeGain(sliderDB: 0) == 1)
        // Past the ends is the end.
        #expect(abs((AudioLevel.decibels(forGain: AudioLevel.volumeGain(sliderDB: 12)) ?? 0) - 6) < 0.001)
        #expect(abs((AudioLevel.decibels(forGain: AudioLevel.volumeGain(sliderDB: -60)) ?? 0) - -24) < 0.001)
    }
}
