import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzMedia
import Testing

/// **A transition carries the sound across the cut, in the exported file too.**
///
/// The plan is settled in `TransitionSoundTests`; this writes it out through
/// the exporter's own mixdown and reads the file back, so what is measured is
/// what somebody would hear: no step in the level either side of the edit
/// point where a dissolve is, and a real step where there is none.
@Suite("A transition's sound exports the way it plays", .serialized)
struct TransitionSoundExportTests {

    /// Its own folder and its own tone: the other mix suites run beside this
    /// one and write their files while it reads.
    static let folder = TestTone.scratch()

    static func tone() throws -> URL {
        let url = folder.appendingPathComponent("talk.m4a")
        if !FileManager.default.fileExists(atPath: url.path) {
            try TestTone.writeFlat(to: url, seconds: 10)
        }
        return url
    }

    static func exported(_ mix: [AudioMixSegment], urls: [UUID: URL],
                         named name: String) async throws -> Waveform {
        let out = folder.appendingPathComponent("\(name)-out.m4a")
        _ = try await AudioMixdown.write(mix, urls: urls, to: out)
        return try #require(await SoundFile.read(at: out)).waveform
    }

    /// A talk from 0 to 8s with its own sound, and silent b-roll butted onto it
    /// at 8s, the way the sample talk and its b-roll meet.
    static func talkThenBroll() throws -> (doc: PhotonzDocument, take: UUID, broll: UUID,
                                           urls: [UUID: URL]) {
        let talk = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 10_000,
                            hasSound: true)
        let footage = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 6000)
        var doc = PhotonzDocument.recording(talk, name: "talk")
        let take = doc.layers[0].id
        doc.updateLayer(id: take) {
            $0.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 10_000)
        }
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        var clip = Layer(name: "b-roll", content: .image(footage.frameRef(atSourceMS: 1500)),
                         frame: CGRect(origin: .zero, size: footage.pixelSize))
        clip.movie = footage
        clip.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 1500, sourceLengthMS: 6000)
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 8000,
                                      over: .onto(v1), edit: .overwrite)
        let arrived = doc.land(clip, at: landing)
        let broll = try #require(arrived)
        let url = try Self.tone()
        return (doc, take, broll, [talk.id: url])
    }

    /// The largest change in level across any 40 ms of the file between two
    /// moments: a hard cut is one bucket loud and the next silent, and a
    /// cross-fade never moves that far that fast.
    /// Past the end of the written file is silence, which is what plays there
    /// under a picture with no sound of its own.
    static func largestStep(_ wave: Waveform, fromMS: Int, toMS: Int) -> Float {
        let lo = max(0, fromMS / Waveform.bucketMS)
        let hi = toMS / Waveform.bucketMS
        guard hi > lo else { return 0 }
        func level(_ i: Int) -> Float { i < wave.peaks.count ? wave.peaks[i] : 0 }
        return (lo..<hi).map { abs(level($0 + 2) - level($0)) }.max() ?? 0
    }

    @Test("With no transition the file steps at the edit point, which is what the test can see")
    func hardCutSteps() async throws {
        let (doc, _, _, urls) = try Self.talkThenBroll()
        let wave = try await Self.exported(doc.audioMix(), urls: urls,
                                                        named: "edit-hard")
        #expect(AudioMixdownTests.loudness(wave, fromMS: 7000, toMS: 7900) > 0.3)
        #expect(Self.largestStep(wave, fromMS: 7000, toMS: 9000) > 0.3)
    }

    @Test("A dissolve at the edit point exports as a fade, with no step either side of the cut")
    func dissolveHasNoStep() async throws {
        var (doc, take, broll, urls) = try Self.talkThenBroll()
        let did = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000),
                                    at: .edit(outgoing: take, incoming: broll))
        #expect(did)
        let wave = try await Self.exported(doc.audioMix(), urls: urls,
                                                        named: "edit-dissolve")
        let full = AudioMixdownTests.loudness(wave, fromMS: 6000, toMS: 7000)
        #expect(full > 0.3)
        #expect(Self.largestStep(wave, fromMS: 7000, toMS: 9000) < full * 0.2)
        // The talk is still heard past the cut, running on into its spare...
        #expect(AudioMixdownTests.loudness(wave, fromMS: 8100, toMS: 8200) > full * 0.3)
        // ...and is gone once the dissolve is over.
        #expect(AudioMixdownTests.loudness(wave, fromMS: 8700, toMS: 9500) < full * 0.1)
    }

    @Test("A dip to black exports as a dip: the sound goes through silence on the cut")
    func dipDipsInTheFile() async throws {
        var (doc, take, broll, urls) = try Self.talkThenBroll()
        // The b-roll gets the same tone, so the far side of the dip has sound
        // to come back up to.
        let footage = try #require(doc.layer(id: broll)?.movie)
        doc.updateLayer(id: broll) {
            $0.movie = MovieRef(id: footage.id, pixelSize: footage.pixelSize,
                                durationMS: footage.durationMS, hasSound: true)
        }
        urls[footage.id] = urls.values.first
        let did = doc.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 1000),
                                    at: .edit(outgoing: take, incoming: broll))
        #expect(did)
        let wave = try await Self.exported(doc.audioMix(), urls: urls,
                                                        named: "edit-dip")
        let full = AudioMixdownTests.loudness(wave, fromMS: 6000, toMS: 7000)
        #expect(full > 0.3)
        #expect(AudioMixdownTests.loudness(wave, fromMS: 7960, toMS: 8040) < full * 0.2)
        #expect(AudioMixdownTests.loudness(wave, fromMS: 9000, toMS: 10_000) > full * 0.7)
        #expect(Self.largestStep(wave, fromMS: 7000, toMS: 9000) < full * 0.2)
    }
}
