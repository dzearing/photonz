import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Level, level over time, and the one plan both playing and exporting read
/// (`docs/design/video-audio.md`).
///
/// The point of the plan being a value rather than a player is the acceptance
/// item nobody can check by ear in a test: **what you hear and what you export
/// come from the same function.** If they agree here they agree everywhere,
/// because there is only the one answer to agree with.
@Suite("Level, and what plays at a moment")
struct AudioMixTests {

    static func document(soundLengthMS: Int = 10_000) -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [])
        let id = doc.addSound(SoundRef(durationMS: soundLengthMS), name: "music", atMS: 0)
        return (doc, id)
    }

    // MARK: - The level itself

    @Test("With nobody touching it, sound plays at the level it was recorded at")
    func defaultLevelIsUnity() {
        let level = AudioLevel()
        #expect(level.gain(atLayerMS: 0) == 1)
        #expect(level.gain(atLayerMS: 9999) == 1)
        #expect(level.isSilent == false)
    }

    @Test("Level is read in decibels, because that is what a level is called everywhere")
    func levelReadsInDecibels() {
        #expect(AudioLevel.decibels(forGain: 1).map { ($0 * 10).rounded() / 10 } == 0)
        #expect(AudioLevel.decibels(forGain: 0.5).map { ($0 * 10).rounded() / 10 } == -6)
        #expect(AudioLevel.decibels(forGain: 2).map { ($0 * 10).rounded() / 10 } == 6)
        // Nothing at all has no number of decibels, so it says so in words.
        #expect(AudioLevel.decibels(forGain: 0) == nil)
        #expect(AudioLevel(gain: 0).label == "Silent")
        #expect(AudioLevel(gain: 1).label == "0.0 dB")
        #expect(AudioLevel(gain: 0.5).label == "-6.0 dB")
    }

    @Test("Decibels back to gain is the same number it came from")
    func decibelsRoundTrip() throws {
        for gain in [0.1, 0.25, 0.5, 1.0, 1.5, 2.0] {
            let dB = try #require(AudioLevel.decibels(forGain: gain))
            #expect(abs(AudioLevel.gain(forDecibels: dB) - gain) < 0.0001)
        }
    }

    @Test("A level louder than twice as loud is refused, so nothing can be driven into noise")
    func levelIsBounded() {
        #expect(AudioLevel(gain: 99).gain == AudioLevel.loudestGain)
        #expect(AudioLevel(gain: -1).gain == 0)
    }

    // MARK: - Level over time

    @Test("Two points make a ramp, and between them the level slides")
    func pointsInterpolate() {
        let level = AudioLevel(points: [AudioLevelPoint(atMS: 1000, gain: 1),
                                        AudioLevelPoint(atMS: 2000, gain: 0.2)])
        #expect(level.gain(atLayerMS: 1000) == 1)
        #expect(level.gain(atLayerMS: 2000) == 0.2)
        #expect(abs(level.gain(atLayerMS: 1500) - 0.6) < 0.0001)
    }

    @Test("Outside the points the level holds, so a duck stays ducked until it is brought back")
    func pointsHoldAtTheEnds() {
        let level = AudioLevel(points: [AudioLevelPoint(atMS: 1000, gain: 1),
                                        AudioLevelPoint(atMS: 2000, gain: 0.2)])
        #expect(level.gain(atLayerMS: 0) == 1)
        #expect(level.gain(atLayerMS: 99_000) == 0.2)
    }

    @Test("Points are kept in time order however they are put in")
    func pointsSortThemselves() {
        let level = AudioLevel(points: [AudioLevelPoint(atMS: 2000, gain: 0.2),
                                        AudioLevelPoint(atMS: 1000, gain: 1)])
        #expect(level.points.map(\.atMS) == [1000, 2000])
    }

    @Test("A second point at the same moment replaces the first, so a curve never doubles back")
    func pointsAreOnePerMoment() {
        var level = AudioLevel()
        level.setPoint(atMS: 1000, gain: 0.5)
        level.setPoint(atMS: 1000, gain: 0.25)
        #expect(level.points.count == 1)
        #expect(level.points[0].gain == 0.25)
    }

    @Test("The fader and the curve multiply, so pulling the fader down takes the whole shape with it")
    func faderScalesTheCurve() {
        let level = AudioLevel(gain: 0.5, points: [AudioLevelPoint(atMS: 0, gain: 1),
                                                   AudioLevelPoint(atMS: 1000, gain: 0.5)])
        #expect(level.gain(atLayerMS: 0) == 0.5)
        #expect(level.gain(atLayerMS: 1000) == 0.25)
    }

    @Test("A fade in is two points and nothing else, which is why there is no fade control")
    func aFadeIsJustPoints() {
        var level = AudioLevel()
        level.setPoint(atMS: 0, gain: 0)
        level.setPoint(atMS: 1500, gain: 1)
        #expect(level.gain(atLayerMS: 0) == 0)
        #expect(abs(level.gain(atLayerMS: 750) - 0.5) < 0.0001)
        #expect(level.gain(atLayerMS: 1500) == 1)
    }

    @Test("A level nobody has touched is written down as nothing at all")
    func defaultLevelWritesNothing() throws {
        var (doc, _) = Self.document()
        doc.layers[0].setSoundLevel(AudioLevel())
        let text = try #require(String(data: try JSONEncoder().encode(doc), encoding: .utf8))
        #expect(!text.contains("soundLevel"))
    }

    // MARK: - The plan

    @Test("One sound makes one segment, reading the file from where it was placed")
    func onePieceOneSegment() throws {
        let (doc, id) = Self.document()
        let mix = doc.audioMix()
        #expect(mix.count == 1)
        let one = try #require(mix.first)
        #expect(one.layerID == id)
        #expect(one.startMS == 0)
        #expect(one.lengthMS == 10_000)
        #expect(one.sourceInMS == 0)
        #expect(one.ramps.count == 1)
        #expect(one.ramps[0].isFlat)
        #expect(one.ramps[0].fromGain == 1)
    }

    @Test("A sound cut in two plays as two segments, each reading its own stretch of the file")
    func cutSoundPlaysAsPieces() throws {
        var (doc, id) = Self.document()
        let cut = doc.splitClip(id, atMS: 4000)
        #expect(cut)
        let dropped = doc.removeClipPiece(id, at: 0)
        #expect(dropped)
        let mix = doc.audioMix()
        #expect(mix.count == 1)
        // The first four seconds were thrown away, so what is left starts
        // reading four seconds into the file and lands at the very beginning.
        #expect(mix[0].startMS == 0)
        #expect(mix[0].sourceInMS == 4000)
        #expect(mix[0].lengthMS == 6000)
    }

    @Test("A held frame is silent, because one frame has no sound to play")
    func heldFramesAreSilent() throws {
        var (doc, id) = Self.document()
        let held = doc.holdFrame(id, atMS: 5000)
        #expect(held)
        let mix = doc.audioMix()
        // Three pieces on the timeline, two of them with sound under them.
        #expect(doc.layer(id: id)?.clipPieces?.count == 3)
        #expect(mix.count == 2)
    }

    @Test("A layer switched off in the layers list is neither seen nor heard")
    func switchedOffIsSilent() throws {
        var (doc, _) = Self.document()
        doc.layers[0].isVisible = false
        #expect(doc.audioMix().isEmpty)
    }

    @Test("A level pulled all the way down leaves nothing to play")
    func silentLevelLeavesNoSegment() throws {
        var (doc, _) = Self.document()
        doc.layers[0].soundLevel = AudioLevel(gain: 0)
        #expect(doc.audioMix().isEmpty)
    }

    @Test("Level over time becomes the ramps an export writes, in the document's own clock")
    func pointsBecomeRamps() throws {
        var (doc, _) = Self.document()
        doc.layers[0].time = LayerTime(inMS: 2000, outMS: 12_000, sourceInMS: 0, sourceLengthMS: 10_000)
        doc.layers[0].soundLevel = AudioLevel(points: [AudioLevelPoint(atMS: 1000, gain: 1),
                                                       AudioLevelPoint(atMS: 2000, gain: 0.2)])
        let segment = try #require(doc.audioMix().first)
        // A point a second into a layer that starts two seconds in is at three
        // seconds on the document's clock, and an export has to be told so.
        #expect(segment.ramps.map(\.fromMS) == [2000, 3000, 4000])
        #expect(segment.ramps.map(\.toMS) == [3000, 4000, 12_000])
        #expect(segment.ramps[0].isFlat)
        #expect(segment.ramps[1].fromGain == 1)
        #expect(abs(segment.ramps[1].toGain - 0.2) < 0.0001)
        #expect(segment.ramps[2].isFlat)
        // ...and the ramps cover the segment end to end with no hole in them.
        #expect(segment.ramps.first?.fromMS == segment.startMS)
        #expect(segment.ramps.last?.toMS == segment.endMS)
    }

    @Test("What is audible at a moment is everything laid over it, which is what a mix is")
    func severalSoundsPlayTogether() throws {
        var (doc, _) = Self.document()
        _ = doc.addSound(SoundRef(durationMS: 4000), name: "voiceover", atMS: 2000)
        _ = doc.addSound(SoundRef(durationMS: 3000), name: "sting", atMS: 20_000)
        #expect(doc.audioMix().count == 3)
        #expect(doc.audioMix(atMS: 500).count == 1)
        #expect(doc.audioMix(atMS: 3000).count == 2)
        #expect(doc.audioMix(atMS: 21_000).count == 1)
        #expect(doc.audioMix(atMS: 8000).count == 1)
    }

    @Test("A clip still carrying its own sound is in the mix, and is not once it is detached")
    func aClipIsInTheMixUntilItIsDetached() throws {
        let doc = PhotonzDocument.recording(
            MovieRef(pixelSize: CGSize(width: 100, height: 100), durationMS: 5000, hasSound: true),
            name: "take")
        #expect(doc.audioMix().count == 1)
        let split = try #require(doc.detachingSound(ofLayer: doc.layers[0].id))
        let mix = split.document.audioMix()
        #expect(mix.count == 1)
        #expect(mix[0].layerID == split.soundLayerID)
    }
}
