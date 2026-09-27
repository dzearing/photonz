import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// **A transition carries the sound across the cut too** (`TransitionSound.swift`).
///
/// A dissolve that blends the picture while the sound jumps at the edit point
/// is half a transition: the export has a hard audio cut, often a click, in the
/// middle of a smooth picture change. A Final Cut editor expects the dissolve
/// to cross-fade the sound, and Premiere puts a Constant Power crossfade on
/// with the same key. So the one mix plan the player and the exporter both
/// read (`PhotonzDocument.audioMix()`) is where it happens.
@Suite("A transition carries the sound across the cut")
struct TransitionSoundTests {

    /// Ten seconds recorded, eight of them used: two seconds spare after.
    static let take = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 10_000,
                               hasSound: true)

    /// The talk on V1 from 0 to 8s, and b-roll butted onto it from 8s to 12s,
    /// read from 1.5s of its own six: one edit point, at 8s.
    static func edit(brollHasSound: Bool = true) throws
        -> (doc: PhotonzDocument, take: UUID, broll: UUID, brollSound: SoundRef?) {
        let broll = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 6000,
                             hasSound: brollHasSound)
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let take = doc.layers[0].id
        doc.updateLayer(id: take) {
            $0.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 10_000)
        }
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        var clip = Layer(name: "b-roll", content: .image(broll.frameRef(atSourceMS: 1500)),
                         frame: CGRect(origin: .zero, size: broll.pixelSize))
        clip.movie = broll
        clip.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 1500, sourceLengthMS: 6000)
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 8000,
                                      over: .onto(v1), edit: .overwrite)
        let arrived = doc.land(clip, at: landing)
        let landed = try #require(arrived)
        #expect(doc.editPoints(onTrack: v1).map(\.atMS) == [8000])
        return (doc, take, landed, broll.soundRef)
    }

    static func segment(_ mix: [AudioMixSegment], of layer: UUID) throws -> AudioMixSegment {
        let found = mix.filter { $0.layerID == layer }
        #expect(found.count == 1)
        return try #require(found.first)
    }

    // MARK: - A hard cut stays hard

    @Test("With nothing on the cut, the sound cuts exactly where the picture does")
    func hardCutStaysHard() throws {
        let (doc, take, broll, _) = try Self.edit()
        let mix = doc.audioMix()
        let out = try Self.segment(mix, of: take)
        let into = try Self.segment(mix, of: broll)
        #expect(out.startMS == 0 && out.endMS == 8000)
        #expect(into.startMS == 8000 && into.endMS == 12_000)
        #expect(into.sourceInMS == 1500)
        #expect(out.gain(atMS: 7999) == 1)
        #expect(into.gain(atMS: 8000) == 1)
    }

    // MARK: - A dissolve cross-fades

    @Test("A dissolve runs the outgoing sound on and starts the incoming one early, over its length")
    func dissolveOverlapsTheSound() throws {
        var (doc, take, broll, _) = try Self.edit()
        let did2 = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 400),
                                  at: .edit(outgoing: take, incoming: broll))
        #expect(did2)
        let mix = doc.audioMix()
        let out = try Self.segment(mix, of: take)
        let into = try Self.segment(mix, of: broll)
        // The same spare the picture spends: 200 ms either side of the cut.
        #expect(out.startMS == 0 && out.endMS == 8200)
        #expect(out.sourceInMS == 0 && out.sourceLengthMS == 8200)
        #expect(into.startMS == 7800 && into.endMS == 12_000)
        #expect(into.sourceInMS == 1300 && into.sourceLengthMS == 4200)
        // Nothing moves before the transition or after it.
        #expect(out.gain(atMS: 7000) == 1)
        #expect(abs(out.gain(atMS: 7800) - 1) < 0.001)
        #expect(abs(into.gain(atMS: 7800)) < 0.001)
        #expect(abs(into.gain(atMS: 8200) - 1) < 0.001)
        #expect(into.gain(atMS: 11_000) == 1)
        #expect(abs(out.gain(atMS: 8200)) < 0.001)
    }

    @Test("The cross-fade keeps the power even: no dip and no bump in the middle")
    func dissolveIsEqualPower() throws {
        var (doc, take, broll, _) = try Self.edit()
        let did3 = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 400),
                                  at: .edit(outgoing: take, incoming: broll))
        #expect(did3)
        let mix = doc.audioMix()
        let out = try Self.segment(mix, of: take)
        let into = try Self.segment(mix, of: broll)
        // Half way through, each side is at -3 dB rather than -6.
        #expect(abs(out.gain(atMS: 8000) - 0.7071) < 0.01)
        #expect(abs(into.gain(atMS: 8000) - 0.7071) < 0.01)
        for ms in stride(from: 7800, through: 8200, by: 5) {
            let power = pow(out.gain(atMS: ms), 2) + pow(into.gain(atMS: ms), 2)
            #expect(abs(power - 1) < 0.02, "power \(power) at \(ms)")
        }
        // Each side only ever moves one way: out falls, in rises.
        let samples = stride(from: 7800, through: 8200, by: 10).map { (out.gain(atMS: $0), into.gain(atMS: $0)) }
        for (a, b) in zip(samples, samples.dropFirst()) {
            #expect(b.0 <= a.0 + 1e-9 && b.1 >= a.1 - 1e-9)
        }
    }

    @Test("Every kind that puts both shots on screen cross-fades the sound the same way")
    func everyOverlapKindCrossFades() throws {
        for kind in ClipTransitionKind.allCases where kind.needsOverlap {
            var (doc, take, broll, _) = try Self.edit()
            let did4 = doc.setTransition(ClipTransition(kind: kind, lengthMS: 600),
                                      at: .edit(outgoing: take, incoming: broll))
            #expect(did4)
            let mix = doc.audioMix()
            #expect(try Self.segment(mix, of: take).endMS == 8300, "\(kind)")
            #expect(try Self.segment(mix, of: broll).startMS == 7700, "\(kind)")
        }
    }

    @Test("The clip's own level still counts under the cross-fade")
    func levelMultipliesTheCrossFade() throws {
        var (doc, take, broll, _) = try Self.edit()
        doc.updateLayer(id: take) { $0.setSoundLevel(AudioLevel(gain: 0.5)) }
        let did5 = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 400),
                                  at: .edit(outgoing: take, incoming: broll))
        #expect(did5)
        let out = try Self.segment(doc.audioMix(), of: take)
        #expect(abs(out.gain(atMS: 7000) - 0.5) < 0.001)
        #expect(abs(out.gain(atMS: 8000) - 0.3536) < 0.01)
    }

    @Test("B-roll with no sound: the talk fades out over the dissolve instead of stopping dead")
    func silentIncomingStillFadesTheOutgoing() throws {
        var (doc, take, broll, sound) = try Self.edit(brollHasSound: false)
        #expect(sound == nil)
        let did6 = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 400),
                                  at: .edit(outgoing: take, incoming: broll))
        #expect(did6)
        let mix = doc.audioMix()
        #expect(mix.allSatisfy { $0.layerID == take })
        let out = try Self.segment(mix, of: take)
        #expect(out.endMS == 8200)
        #expect(abs(out.gain(atMS: 8000) - 0.7071) < 0.01)
        #expect(abs(out.gain(atMS: 8200)) < 0.001)
    }

    // MARK: - A dip dips

    @Test("A dip to black takes the sound through silence with the picture")
    func dipDipsTheSound() throws {
        for kind in [ClipTransitionKind.dipToBlack, .dipToWhite] {
            var (doc, take, broll, _) = try Self.edit()
            let did7 = doc.setTransition(ClipTransition(kind: kind, lengthMS: 400),
                                      at: .edit(outgoing: take, incoming: broll))
            #expect(did7)
            let mix = doc.audioMix()
            let out = try Self.segment(mix, of: take)
            let into = try Self.segment(mix, of: broll)
            // A dip spends no spare, for the sound either.
            #expect(out.endMS == 8000 && into.startMS == 8000)
            #expect(into.sourceInMS == 1500)
            #expect(abs(out.gain(atMS: 7800) - 1) < 0.001)
            #expect(abs(out.gain(atMS: 7900) - 0.5) < 0.01)
            #expect(abs(out.gain(atMS: 8000)) < 0.001)
            #expect(abs(into.gain(atMS: 8000)) < 0.001)
            #expect(abs(into.gain(atMS: 8100) - 0.5) < 0.01)
            #expect(abs(into.gain(atMS: 8200) - 1) < 0.001)
        }
    }

    // MARK: - What is not touched

    @Test("Music on its own track, linked to neither clip, is not touched")
    func unlinkedMusicIsUntouched() throws {
        var (doc, take, broll, _) = try Self.edit()
        let music = SoundRef(durationMS: 20_000)
        let musicID = doc.addSound(music, name: "music", atMS: 0)
        let before = try Self.segment(doc.audioMix(), of: musicID)
        let did8 = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 400),
                                  at: .edit(outgoing: take, incoming: broll))
        #expect(did8)
        #expect(try Self.segment(doc.audioMix(), of: musicID) == before)
    }

    @Test("Sound taken off the clip onto its own layer is no longer linked, so it is not touched")
    func detachedSoundIsUntouched() throws {
        var (doc, take, broll, _) = try Self.edit()
        let detached = try #require(doc.detachingSound(ofLayer: take))
        doc = detached.document
        let before = try Self.segment(doc.audioMix(), of: detached.soundLayerID)
        let did9 = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 400),
                                  at: .edit(outgoing: take, incoming: broll))
        #expect(did9)
        #expect(try Self.segment(doc.audioMix(), of: detached.soundLayerID) == before)
    }

    @Test("Two clips pulled apart have no cut, so their sound plays as it always did")
    func partedClipsAreUntouched() throws {
        var (doc, take, broll, _) = try Self.edit()
        let did10 = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 400),
                                  at: .edit(outgoing: take, incoming: broll))
        #expect(did10)
        let did11 = doc.moveClip(broll, toInMS: 9000)
        #expect(did11)
        let mix = doc.audioMix()
        #expect(try Self.segment(mix, of: take).endMS == 8000)
        #expect(try Self.segment(mix, of: broll).startMS == 9000)
        #expect(try Self.segment(mix, of: broll).gain(atMS: 9000) == 1)
    }

    // MARK: - A cut inside one clip

    /// The take cut at 3s and 5s with the middle thrown away: one clip whose
    /// join at 3s jumps from 3s of the recording to 5s.
    static func jumpCut() throws -> (doc: PhotonzDocument, take: UUID) {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let take = doc.layers[0].id
        doc.updateLayer(id: take) {
            $0.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 10_000)
        }
        let did12 = doc.splitClip(take, atMS: 3000)
        #expect(did12)
        let did13 = doc.splitClip(take, atMS: 5000)
        #expect(did13)
        let did14 = doc.removeClipPiece(take, at: 1)
        #expect(did14)
        return (doc, take)
    }

    @Test("A dissolve on a join inside one clip overlaps its two pieces, each on its own voice")
    func joinDissolveOverlapsPieces() throws {
        var (doc, take) = try Self.jumpCut()
        let did15 = doc.setClipTransition(take, atCut: 1, to: ClipTransition(kind: .dissolve, lengthMS: 400))
        #expect(did15)
        let mix = doc.audioMix().filter { $0.layerID == take }.sorted { $0.startMS < $1.startMS }
        #expect(mix.count == 2)
        #expect(mix[0].startMS == 0 && mix[0].endMS == 3200 && mix[0].sourceLengthMS == 3200)
        #expect(mix[1].startMS == 2800 && mix[1].sourceInMS == 4800)
        // Two pieces of one clip playing at once each need a fader of their own.
        #expect(mix[0].voice != mix[1].voice)
        #expect(abs(mix[0].gain(atMS: 3000) - 0.7071) < 0.01)
        #expect(abs(mix[1].gain(atMS: 3000) - 0.7071) < 0.01)
    }

    @Test("A plain split with a dissolve on it reads the same sound both sides, so the sound is left alone")
    func continuousJoinIsUntouched() throws {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let take = doc.layers[0].id
        doc.updateLayer(id: take) {
            $0.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 10_000)
        }
        let did16 = doc.splitClip(take, atMS: 4000)
        #expect(did16)
        let before = doc.audioMix()
        let did17 = doc.setClipTransition(take, atCut: 1, to: ClipTransition(kind: .dissolve, lengthMS: 400))
        #expect(did17)
        #expect(doc.audioMix() == before)
        // ...but a dip still dips.
        let did18 = doc.setClipTransition(take, atCut: 1, to: ClipTransition(kind: .dipToBlack, lengthMS: 400))
        #expect(did18)
        let dipped = doc.audioMix().sorted { $0.startMS < $1.startMS }
        #expect(abs(dipped[0].gain(atMS: 3900) - 0.5) < 0.01)
    }
}
