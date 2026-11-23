import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Duck Under Speech: music dips under the stretches the captions heard
/// somebody talking (`SpeechDucking.swift`).
@Suite("Music ducks under the speech the captions heard")
struct SpeechDuckingTests {

    static let talkID = UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000001")!

    static func word(_ text: String, _ start: Int, _ end: Int) -> TranscribedWord {
        TranscribedWord(text, startMS: start, endMS: end)
    }

    /// Ten seconds of talk: speech 1.0 to 3.0 s (a short breath inside it),
    /// a pause, then speech 6.0 to 8.0 s.
    static let cues = [
        CaptionCue(words: [word("Hello", 1000, 1500), word("there.", 1500, 2000),
                           word("Welcome", 2300, 3000)], inMS: 1000, outMS: 3000),
        CaptionCue(words: [word("Second", 6000, 7000), word("part.", 7000, 8000)],
                   inMS: 6000, outMS: 8000),
    ]

    static func document(musicAt: Int = 0, captions: Bool = true)
        -> (doc: PhotonzDocument, talk: UUID, music: UUID) {
        var doc = PhotonzDocument.recording(
            MovieRef(id: talkID, pixelSize: CGSize(width: 1920, height: 1080), durationMS: 10_000,
                     hasSound: true), name: "Sample Talk")
        let talk = doc.layers[0].id
        let music = doc.addSound(SoundRef(durationMS: 10_000), name: "Music", atMS: musicAt)
        if captions { _ = doc.landCaptions(cues, heardOff: talkID) }
        return (doc, talk, music)
    }

    static func level(_ doc: PhotonzDocument, _ id: UUID) -> AudioLevel {
        doc.layer(id: id)?.soundLevel ?? AudioLevel()
    }

    // MARK: - When somebody is talking

    @Test("Words a breath apart are one stretch; a real pause splits them")
    func stretchesJoinShortPauses() {
        let (doc, _, _) = Self.document()
        #expect(doc.speechStretches == [1000...3000, 6000...8000])
    }

    @Test("A pause shorter than the shortest gap stays ducked, a longer one comes up")
    func shortestGap() {
        let gap = SpeechDuck.shortestGapMS
        #expect(SpeechDuck.stretches([0...1000, (1000 + gap - 1)...3000]) == [0...3000])
        #expect(SpeechDuck.stretches([0...1000, (1000 + gap)...3000]) == [0...1000, (1000 + gap)...3000])
        #expect(SpeechDuck.stretches([2000...3000, 0...2500]) == [0...3000])
    }

    // MARK: - The dip

    @Test("The music sits lower under every stretch of speech and comes back up in the gaps")
    func musicDipsUnderSpeech() throws {
        var (doc, _, music) = Self.document()
        let did = doc.duckUnderSpeech(layerID: music)
        #expect(did)
        let level = Self.level(doc, music)
        let duck = SpeechDuck.gain
        #expect(abs(duck - 0.398) < 0.01, "the mock's -8 dB")
        // Full before the first word, down while talking, back up in the pause.
        #expect(level.gain(atLayerMS: 300) == 1)
        #expect(abs(level.gain(atLayerMS: 1000) - duck) < 0.001)
        #expect(abs(level.gain(atLayerMS: 2100) - duck) < 0.001, "the breath at 2.0 s stays ducked")
        #expect(abs(level.gain(atLayerMS: 3000) - duck) < 0.001)
        #expect(level.gain(atLayerMS: 4500) == 1)
        #expect(abs(level.gain(atLayerMS: 7000) - duck) < 0.001)
        #expect(level.gain(atLayerMS: 9500) == 1)
        // Down over the ramp, finished as the first word starts.
        let halfway = level.gain(atLayerMS: 1000 - SpeechDuck.rampMS / 2)
        #expect(halfway < 1 && halfway > duck)
        // Points that can be dragged afterwards like any other: four per dip.
        #expect(level.points.map(\.atMS) == [700, 1000, 3000, 3300, 5700, 6000, 8000, 8300])
    }

    @Test("The dip lands where the speech is when the music starts later on the timeline")
    func musicPlacedLater() {
        var (doc, _, music) = Self.document(musicAt: 2000)
        let did = doc.duckUnderSpeech(layerID: music)
        #expect(did)
        let level = Self.level(doc, music)
        // Music's own clock: speech at 1.0 to 3.0 s of the document is -1.0 to
        // 1.0 s of the music, so it starts ducked and comes up at 1.0 s.
        #expect(abs(level.gain(atLayerMS: 0) - SpeechDuck.gain) < 0.001)
        #expect(abs(level.gain(atLayerMS: 1000) - SpeechDuck.gain) < 0.001)
        #expect(level.gain(atLayerMS: 2000) == 1)
        #expect(abs(level.gain(atLayerMS: 4500) - SpeechDuck.gain) < 0.001)
    }

    @Test("The mix that plays and exports carries the dip, on the document's clock")
    func theMixCarriesIt() throws {
        var (doc, _, music) = Self.document()
        doc.duckUnderSpeech(layerID: music)
        let segment = try #require(doc.audioMix().first { $0.layerID == music })
        #expect(abs(segment.gain(atMS: 2000) - SpeechDuck.gain) < 0.001)
        #expect(segment.gain(atMS: 4500) == 1)
    }

    @Test("Ducking twice writes the same dips, not a second duck on the first")
    func runTwice() {
        var (doc, _, music) = Self.document()
        doc.duckUnderSpeech(layerID: music)
        let once = Self.level(doc, music)
        let again = doc.duckUnderSpeech(layerID: music)
        #expect(!again, "nothing changes")
        #expect(Self.level(doc, music) == once)
    }

    @Test("The fader, fade in and fade out are kept; the duck rides inside them")
    func fadesAndFaderKept() {
        var (doc, _, music) = Self.document()
        doc.updateLayer(id: music) { layer in
            var level = AudioLevel(gain: 0.5)
            level.setFadeIn(1500, lengthMS: 10_000)
            level.setFadeOut(1000, lengthMS: 10_000)
            layer.setSoundLevel(level)
        }
        doc.duckUnderSpeech(layerID: music)
        let level = Self.level(doc, music)
        #expect(level.gain == 0.5)
        #expect(level.fadeInMS == 1500, "still a fade in")
        #expect(level.fadeOutMS(lengthMS: 10_000) == 1000, "still a fade out")
        #expect(level.gain(atLayerMS: 0) == 0)
        // The top of the fade in is under speech, so it rises to the ducked level.
        #expect(abs(level.shape(atLayerMS: 1500) - SpeechDuck.gain) < 0.001)
        #expect(level.shape(atLayerMS: 4500) == 1)
        #expect(abs(level.shape(atLayerMS: 7000) - SpeechDuck.gain) < 0.001)
    }

    @Test("Points somebody dragged by hand are replaced by the duck, the way Premiere's Generate Keyframes does")
    func handPointsReplaced() {
        var (doc, _, music) = Self.document()
        doc.updateLayer(id: music) { layer in
            var level = AudioLevel()
            level.setPoint(atMS: 4000, gain: 0.2)
            level.setPoint(atMS: 5000, gain: 0.2)
            layer.setSoundLevel(level)
        }
        doc.duckUnderSpeech(layerID: music)
        let level = Self.level(doc, music)
        #expect(!level.points.contains { $0.atMS == 4000 || $0.atMS == 5000 })
        #expect(level.gain(atLayerMS: 4500) == 1)
    }

    // MARK: - When it cannot

    @Test("With no captions anywhere the command says it needs them")
    func needsCaptions() {
        var (doc, _, music) = Self.document(captions: false)
        #expect(doc.duckUnderSpeechAvailability(layerID: music) == .needsCaptions)
        #expect(SpeechDuck.Availability.needsCaptions.tip != nil)
        let did = doc.duckUnderSpeech(layerID: music)
        #expect(!did)
        #expect(doc.layer(id: music)?.soundLevel == nil)
    }

    @Test("The voice the captions were heard off is not ducked under itself")
    func notTheVoice() {
        let (doc, talk, music) = Self.document()
        #expect(doc.duckUnderSpeechAvailability(layerID: talk) == .isTheVoice)
        #expect(doc.duckUnderSpeechAvailability(layerID: music) == .ready)
    }

    @Test("A detached voice is still the voice")
    func detachedVoice() throws {
        var (doc, talk, _) = Self.document()
        let detached = try #require(doc.detachingSound(ofLayer: talk))
        doc = detached.document
        #expect(doc.duckUnderSpeechAvailability(layerID: detached.soundLayerID) == .isTheVoice)
    }

    @Test("Something with no sound is not offered the command")
    func notASound() throws {
        let (doc, _, _) = Self.document()
        let captions = try #require(doc.captionsLayers.first)
        #expect(doc.duckUnderSpeechAvailability(layerID: captions.id) == .notASound)
    }
}
