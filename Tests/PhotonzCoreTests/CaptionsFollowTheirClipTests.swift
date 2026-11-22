import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// A freeze of one track takes the captions heard off that track's clip with
/// it (`HoldPush.swift`).
///
/// Holding a frame with Freeze every track off moves the clip and what comes
/// after it on its own track, and lets every other track run on under the
/// still. Captions sit on a track of their own, but they are the clip's own
/// words: left behind, every line after the freeze is shown over the wrong
/// picture by the length of the freeze. So the Captions layer remembers which
/// recording it was heard off, and a freeze of a clip playing that recording
/// moves those captions as if they were on its track.
@Suite("Captions of a clip move with it when a freeze moves only its track")
struct CaptionsFollowTheirClipTests {

    static let talkID = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!

    static func talk() -> MovieRef {
        MovieRef(id: talkID, pixelSize: CGSize(width: 1920, height: 1080), durationMS: 8000,
                 hasSound: true)
    }

    static func word(_ text: String, _ start: Int, _ end: Int) -> TranscribedWord {
        TranscribedWord(text, startMS: start, endMS: end)
    }

    /// The talk's own captions: a line before 0:03, a line across it and a
    /// line after it.
    static let talkCues = [
        CaptionCue(words: [word("Hello", 1000, 1500), word("there", 1500, 2400)],
                   inMS: 1000, outMS: 2500),
        CaptionCue(words: [word("this", 2600, 2900), word("is", 3100, 3400),
                           word("the", 3400, 3900)], inMS: 2600, outMS: 4000),
        CaptionCue(words: [word("talk.", 5000, 6800)], inMS: 5000, outMS: 7000),
    ]

    /// An eight second talking recording on V1, music under the whole of it,
    /// and the talk's captions heard off it.
    static func document() -> (doc: PhotonzDocument, clip: UUID, music: UUID, captions: UUID) {
        var doc = PhotonzDocument.recording(talk(), name: "Sample Talk")
        let clip = doc.layers[0].id
        let music = doc.addSound(SoundRef(durationMS: 8000), name: "Sample Music", atMS: 0)
        let captions = doc.landCaptions(talkCues, heardOff: talkID)
        return (doc, clip, music, captions ?? UUID())
    }

    /// A second Captions layer, heard off some other recording.
    static func addOtherCaptions(to doc: inout PhotonzDocument, heardOff sound: UUID) -> UUID {
        let cues = [
            CaptionCue(words: [word("other", 2000, 2800), word("voice", 3200, 3800)],
                       inMS: 2000, outMS: 4000),
            CaptionCue(words: [word("later", 5000, 5800)], inMS: 5000, outMS: 6000),
        ]
        let box = CGSize(width: 1000, height: 100)
        var content = GroupContent(children: CaptionLayers.layers(for: cues, in: doc.canvasSize,
                                                                  look: .standard, box: box))
        content.captionLook = .standard
        content.captionsHeardOff = sound
        let layer = Layer(name: "Other captions", content: .group(content),
                          frame: CGRect(origin: CGPoint(x: 100, y: 100), size: box))
        doc.addLayer(layer)
        return layer.id
    }

    static func cues(_ doc: PhotonzDocument, in captions: UUID) -> [Layer] {
        (doc.layer(id: captions)?.children ?? []).sorted { ($0.time?.inMS ?? 0) < ($1.time?.inMS ?? 0) }
    }

    static func starts(_ cue: Layer) -> [Int] { cue.captionWords?.map(\.startMS) ?? [] }

    // MARK: - The freeze

    @Test("Freezing the talk for ten seconds at 0:03 on its own track moves its captions after 0:03 by ten seconds")
    func captionsAfterTheFreezeMoveAlong() throws {
        var (doc, clip, _, captions) = Self.document()
        let did1 = doc.holdFrame(clip, atMS: 3000, forMS: 10_000, push: .thisTrack)
        #expect(did1)
        let cues = Self.cues(doc, in: captions)
        try #require(cues.count == 3)
        // Said before the freeze: where it was.
        #expect(cues[0].time == LayerTime(inMS: 1000, outMS: 2500))
        #expect(Self.starts(cues[0]) == [1000, 1500])
        // Across the freeze: it waits through it, and its words after 0:03
        // are said ten seconds later, over the same picture they were heard on.
        #expect(cues[1].time == LayerTime(inMS: 2600, outMS: 14_000))
        #expect(Self.starts(cues[1]) == [2600, 13_100, 13_400])
        // After the freeze: ten seconds later, every word with it.
        #expect(cues[2].time == LayerTime(inMS: 15_000, outMS: 17_000))
        #expect(Self.starts(cues[2]) == [15_000])
    }

    @Test("The music on its own track still runs on under the freeze")
    func musicRunsOn() throws {
        var (doc, clip, music, _) = Self.document()
        let before = try #require(doc.layer(id: music))
        let did2 = doc.holdFrame(clip, atMS: 3000, forMS: 10_000, push: .thisTrack)
        #expect(did2)
        #expect(doc.layer(id: music)?.time == before.time)
        #expect(doc.layer(id: music)?.clipPieces == before.clipPieces)
    }

    @Test("Captions heard off another recording do not move")
    func otherCaptionsStay() throws {
        var (doc, clip, _, _) = Self.document()
        let other = Self.addOtherCaptions(to: &doc, heardOff: UUID())
        let before = Self.cues(doc, in: other)
        let did3 = doc.holdFrame(clip, atMS: 3000, forMS: 10_000, push: .thisTrack)
        #expect(did3)
        #expect(Self.cues(doc, in: other) == before)
    }

    @Test("Captions written before they remembered their recording follow the one recording the document listened to")
    func olderCaptionsFollowTheOneRecordingHeard() throws {
        var doc = PhotonzDocument.recording(Self.talk(), name: "Sample Talk")
        let clip = doc.layers[0].id
        let landed = doc.landCaptions(Self.talkCues)
        let captions = try #require(landed)
        doc.noteCaptionsListened(to: Self.talkID)
        #expect(doc.layer(id: captions)?.captionsHeardOff == nil)
        let did4 = doc.holdFrame(clip, atMS: 3000, forMS: 10_000, push: .thisTrack)
        #expect(did4)
        #expect(Self.cues(doc, in: captions)[2].time?.inMS == 15_000)
    }

    @Test("A clip whose sound was taken off it leaves the captions with the sound")
    func detachedSoundKeepsTheCaptions() throws {
        var (doc, clip, _, captions) = Self.document()
        doc.updateLayer(id: clip) { $0.soundDetached = true }
        let before = Self.cues(doc, in: captions)
        let did5 = doc.holdFrame(clip, atMS: 3000, forMS: 10_000, push: .thisTrack)
        #expect(did5)
        #expect(Self.cues(doc, in: captions) == before)
    }

    // MARK: - Changing it afterwards

    @Test("The still made shorter takes the captions back with it")
    func shorterStillBringsThemBack() throws {
        var (doc, clip, _, captions) = Self.document()
        let did6 = doc.holdFrame(clip, atMS: 3000, forMS: 10_000, push: .thisTrack)
        #expect(did6)
        let index = try #require(doc.layer(id: clip)?.clipPieces?.pieceIndex(atMS: 5000))
        let did7 = doc.setHoldLength(clip, ofPiece: index, toMS: 4000)
        #expect(did7)
        let cues = Self.cues(doc, in: captions)
        #expect(cues[1].time == LayerTime(inMS: 2600, outMS: 8000))
        #expect(Self.starts(cues[1]) == [2600, 7100, 7400])
        #expect(cues[2].time == LayerTime(inMS: 9000, outMS: 11_000))
    }

    @Test("Throwing the still away puts every caption back exactly where it was")
    func deletingTheStillPutsThemBack() throws {
        var (doc, clip, _, captions) = Self.document()
        let before = Self.cues(doc, in: captions)
        let did8 = doc.holdFrame(clip, atMS: 3000, forMS: 10_000, push: .thisTrack)
        #expect(did8)
        let index = try #require(doc.layer(id: clip)?.clipPieces?.pieceIndex(atMS: 5000))
        let did9 = doc.rippleDeleteClipPiece(clip, at: index)
        #expect(did9)
        #expect(Self.cues(doc, in: captions) == before)
    }

    @Test("Turning Freeze every track on and off again leaves the captions where the freeze put them")
    func switchingWhatItPushesLeavesCaptionsAlone() throws {
        var (doc, clip, music, captions) = Self.document()
        let did10 = doc.holdFrame(clip, atMS: 3000, forMS: 10_000, push: .thisTrack)
        #expect(did10)
        let frozen = Self.cues(doc, in: captions)
        let index = try #require(doc.layer(id: clip)?.clipPieces?.pieceIndex(atMS: 5000))
        let did11 = doc.setHoldPush(clip, ofPiece: index, to: .everything)
        #expect(did11)
        // The captions already moved with the clip; only the music takes the
        // time in now.
        #expect(Self.cues(doc, in: captions) == frozen)
        #expect(doc.layer(id: music)?.time?.outMS == 18_000)
        let did12 = doc.setHoldPush(clip, ofPiece: index, to: .thisTrack)
        #expect(did12)
        #expect(Self.cues(doc, in: captions) == frozen)
        #expect(doc.layer(id: music)?.time?.outMS == 8000)
    }

    // MARK: - The drift mark

    @Test("The clip's own captions carry no drift mark, while the music and other captions do")
    func noDriftOnTheClipsOwnWords() throws {
        var (doc, clip, music, captions) = Self.document()
        let other = Self.addOtherCaptions(to: &doc, heardOff: UUID())
        let did13 = doc.holdFrame(clip, atMS: 3000, forMS: 10_000, push: .thisTrack)
        #expect(did13)
        for cue in Self.cues(doc, in: captions) {
            #expect(doc.holdDrifts(forLayer: cue.id).isEmpty)
        }
        #expect(!doc.holdDrifts(forLayer: music).isEmpty)
        let across = try #require(Self.cues(doc, in: other).first)
        #expect(!doc.holdDrifts(forLayer: across.id).isEmpty)
    }

    @Test("No word of the clip's own captions is said over its still, which is what the walk checks")
    func noWordOverTheStill() throws {
        var (doc, clip, _, captions) = Self.document()
        let did = doc.holdFrame(clip, atMS: 3000, forMS: 10_000, push: .thisTrack)
        #expect(did)
        #expect(doc.captionWordsOverOwnStills().isEmpty)
        // Put the captions back where they were before the freeze, the way
        // they stayed until this was fixed, and the words over the still are
        // named.
        doc.updateLayer(id: captions) { layer in
            layer.children = layer.children.map { cue in
                var cue = cue
                if let time = cue.time, time.inMS >= 13_000 {
                    cue.time = LayerTime(inMS: time.inMS - 10_000, outMS: time.outMS - 10_000)
                    cue.captionWords = cue.captionWords?.map { $0.shifted(byMS: -10_000) }
                }
                return cue
            }
        }
        #expect(doc.captionWordsOverOwnStills().map(\.text) == ["talk."])
    }

    // MARK: - Kept with the document

    @Test("Which recording captions were heard off is saved, and a group that never said writes nothing")
    func heardOffIsSaved() throws {
        let (doc, _, _, captions) = Self.document()
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.layer(id: captions)?.captionsHeardOff == Self.talkID)

        let plain = try JSONEncoder().encode(GroupContent(children: []))
        #expect(!(String(data: plain, encoding: .utf8) ?? "").contains("heardOff"))
    }

    @Test("Writing captions again without saying keeps the recording they were heard off")
    func rewritingKeepsTheRecording() throws {
        var (doc, _, _, captions) = Self.document()
        let again = doc.landCaptions(Array(Self.talkCues.prefix(2)))
        #expect(again == captions)
        #expect(doc.layer(id: captions)?.captionsHeardOff == Self.talkID)
    }
}
