import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// **A stretch cleaned on its own eases in and out** (`TransitionSound.swift`,
/// "the seam either side of a stretch cleaned on its own").
///
/// Clean Noise in Section plays a cleaned copy inside the range and the file
/// as recorded either side. Switched over at the cut, the room tone drops from
/// one sample to the next, which is a click. So the two readings overlap for a
/// short fixed time centred on each cut, and fade in straight lines: they are
/// two readings of the same recording, so straight lines keep the voice at
/// its level where an equal-power fade would swell it in the middle.
@Suite("A cleaned stretch eases in and out of the sound around it")
struct SectionCleaningSeamTests {

    static let take = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 10_000,
                               hasSound: true)
    static let half = SectionCleaningSeam.lengthMS / 2

    /// The take, its own sound cleaned between 0:03 and 0:06.
    static func cleaned(level: AudioLevel? = nil) throws -> (doc: PhotonzDocument, take: UUID) {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let take = doc.layers[0].id
        if let level { doc.updateLayer(id: take) { $0.setSoundLevel(level) } }
        let did = doc.cleanNoiseSection([take], within: 3000..<6000)
        #expect(did)
        return (doc, take)
    }

    @Test("The seam is short and fixed")
    func shortAndFixed() {
        #expect(SectionCleaningSeam.lengthMS >= 100)
        #expect(SectionCleaningSeam.lengthMS <= 300)
    }

    @Test("Each reading runs on into the other by half the seam either side of both cuts")
    func overlapCentredOnEachCut() throws {
        let (doc, take) = try Self.cleaned()
        let mix = doc.audioMix().filter { $0.layerID == take }.sorted { $0.startMS < $1.startMS }
        try #require(mix.count == 3)
        let (before, inside, after) = (mix[0], mix[1], mix[2])
        #expect(before.sound.cleaning == nil && after.sound.cleaning == nil)
        #expect(inside.sound.cleaning != nil)
        #expect(before.startMS == 0 && before.endMS == 3000 + Self.half)
        #expect(inside.startMS == 3000 - Self.half && inside.endMS == 6000 + Self.half)
        #expect(after.startMS == 6000 - Self.half && after.endMS == 10_000)
        // Each still reads the recording in step with the clock.
        #expect(inside.sourceInMS == 3000 - Self.half)
        #expect(inside.sourceOutMS == 6000 + Self.half)
        #expect(after.sourceInMS == 6000 - Self.half)
        #expect(before.sourceOutMS == 3000 + Self.half)
    }

    @Test("The two readings fade in straight lines and always add up to the level")
    func straightLinesAddingToOne() throws {
        let (doc, take) = try Self.cleaned()
        let mix = doc.audioMix().filter { $0.layerID == take }
        for cut in [3000, 6000] {
            for ms in stride(from: cut - Self.half - 20, through: cut + Self.half + 20, by: 10) {
                let heard = mix.filter { $0.contains(ms: ms) }.map { $0.gain(atMS: ms) }
                #expect(abs(heard.reduce(0, +) - 1) < 0.001, "at \(ms)")
            }
            let at = mix.filter { $0.contains(ms: cut) }
            #expect(at.count == 2)
            #expect(at.allSatisfy { abs($0.gain(atMS: cut) - 0.5) < 0.001 })
        }
        // Outside the seams only one reading plays, at full level.
        for ms in [1000, 2800, 4500, 5800, 8000] {
            let heard = mix.filter { $0.contains(ms: ms) }
            #expect(heard.count == 1 && abs(heard[0].gain(atMS: ms) - 1) < 0.001, "at \(ms)")
        }
    }

    @Test("The cleaned reading has its own voice, so the player gives each its own fader")
    func ownVoice() throws {
        let (doc, take) = try Self.cleaned()
        let mix = doc.audioMix().filter { $0.layerID == take }.sorted { $0.startMS < $1.startMS }
        try #require(mix.count == 3)
        #expect(mix[0].voice == 0 && mix[1].voice == 1 && mix[2].voice == 0)
    }

    @Test("The seam rides on the sound's own level")
    func onTheLevel() throws {
        let (doc, take) = try Self.cleaned(level: AudioLevel(gain: 0.5))
        let mix = doc.audioMix().filter { $0.layerID == take }
        let heard = mix.filter { $0.contains(ms: 3000) }.map { $0.gain(atMS: 3000) }
        #expect(abs(heard.reduce(0, +) - 0.5) < 0.001)
        #expect(mix.filter { $0.contains(ms: 4500) }.map { $0.gain(atMS: 4500) } == [0.5])
    }

    @Test("A plain split, and a sound cleaned whole, have no seam")
    func noSeamWhereNothingChanges() throws {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let take = doc.layers[0].id
        doc.splitClip(take, atMS: 3000)
        doc.splitClip(take, atMS: 6000)
        let plain = doc.audioMix().filter { $0.layerID == take }.sorted { $0.startMS < $1.startMS }
        #expect(plain.map(\.startMS) == [0, 3000, 6000])
        #expect(plain.map(\.endMS) == [3000, 6000, 10_000])

        var whole = AudioLevel()
        whole.noiseReduction = .medium
        let (cleanedWhole, id) = try Self.cleaned()
        var doc2 = cleanedWhole
        doc2.updateLayer(id: id) { $0.setSoundLevel(whole) }
        let mix = doc2.audioMix().filter { $0.layerID == id }.sorted { $0.startMS < $1.startMS }
        #expect(mix.map(\.startMS) == [0, 3000, 6000])
        #expect(Set(mix.map(\.sound.id)).count == 1)
    }

    @Test("A short cleaned stretch eases over no more than half of itself at each end")
    func shortStretch() throws {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let take = doc.layers[0].id
        let did = doc.cleanNoiseSection([take], within: 3000..<3120)
        #expect(did)
        let mix = doc.audioMix().filter { $0.layerID == take }.sorted { $0.startMS < $1.startMS }
        try #require(mix.count == 3)
        #expect(mix[1].startMS == 3000 - 60 && mix[1].endMS == 3120 + 60)
        #expect(mix[0].endMS == 3060 && mix[2].startMS == 3060)
        for ms in stride(from: 2900, through: 3220, by: 10) {
            let heard = mix.filter { $0.contains(ms: ms) }.map { $0.gain(atMS: ms) }
            #expect(heard.reduce(0, +) <= 1.001, "at \(ms)")
        }
    }

    @Test("A dissolve put on the cut by hand still shapes it; the seam stands aside")
    func dissolveWins() throws {
        var (doc, take) = try Self.cleaned()
        let pieces = try #require(doc.layer(id: take)?.clipPieces)
        let cut = try #require(pieces.cuts.first)
        let did = doc.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 400),
                                    at: .join(clip: take, index: cut.index))
        #expect(did)
        let mix = doc.audioMix().filter { $0.layerID == take }.sorted { $0.startMS < $1.startMS }
        try #require(mix.count == 3)
        // The dip keeps each side inside its own time and goes through silence.
        #expect(mix[0].endMS == 3000 && mix[1].startMS == 3000)
        #expect(mix.filter { $0.contains(ms: 3000) }.map { $0.gain(atMS: 3000) }.reduce(0, +) < 0.01)
        // The far cut has nothing on it and still eases.
        #expect(mix[1].endMS == 6000 + Self.half)
    }
}
