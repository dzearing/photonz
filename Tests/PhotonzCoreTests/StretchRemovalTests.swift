import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Cutting a stretch out of a recording takes the rest of the document along:
/// the captions over the words that went go with them, a caption across the
/// join is shortened, and everything after the stretch moves earlier by its
/// length. Premiere's ripple delete with sync lock on, which is what an editor
/// expects when the gap closes.
@Suite("What a stretch cut out of a recording takes with it")
struct StretchRemovalTests {

    static func movie(durationMS: Int = 12_000) -> MovieRef {
        MovieRef(id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
                 pixelSize: CGSize(width: 1920, height: 1080),
                 durationMS: durationMS)
    }

    static func cue(_ text: String, _ inMS: Int, _ outMS: Int) -> CaptionCue {
        let words = text.split(separator: " ").map(String.init)
        let step = (outMS - inMS) / max(1, words.count)
        return CaptionCue(words: words.enumerated().map { index, word in
            TranscribedWord(word, startMS: inMS + index * step, endMS: inMS + (index + 1) * step)
        }, inMS: inMS, outMS: outMS)
    }

    /// A twelve second recording cut at four and eight seconds, so the middle
    /// piece is the four seconds from 4.0s to 8.0s, with a caption before the
    /// stretch, one across each end of it, one inside it and one after it.
    static func talk() -> (doc: PhotonzDocument, clip: UUID, captions: [String: UUID]) {
        var doc = PhotonzDocument.recording(movie(), name: "Talk")
        let clip = doc.layers[0].id
        doc.splitClip(clip, atMS: 4000)
        doc.splitClip(clip, atMS: 8000)
        doc.landCaptions([
            cue("before", 1000, 3000),
            cue("over the start", 3500, 4600),
            cue("thrown away", 5000, 7000),
            cue("past the end", 7400, 9200),
            cue("after it", 9500, 11_000),
        ])
        var ids: [String: UUID] = [:]
        for layer in doc.captionLayers {
            ids[layer.captionWords?.first?.text ?? ""] = layer.id
        }
        return (doc, clip, ids)
    }

    @Test("A caption that sat only inside the piece goes with it")
    func captionInsideGoes() throws {
        var (doc, clip, captions) = Self.talk()
        let did = doc.rippleDeleteClipPiece(clip, at: 1)
        #expect(did)
        #expect(doc.layer(id: captions["thrown"] ?? UUID()) == nil)
        #expect(captions["thrown"] != nil)
        #expect(doc.captionLayers.count == 4)
    }

    @Test("Every caption after the piece moves earlier by its length, words and all")
    func captionAfterMoves() throws {
        var (doc, clip, captions) = Self.talk()
        doc.rippleDeleteClipPiece(clip, at: 1)
        let after = try #require(doc.layer(id: captions["after"] ?? UUID()))
        #expect(after.time?.inMS == 5500)
        #expect(after.time?.outMS == 7000)
        #expect(after.captionWords?.map(\.startMS) == [5500, 6250])
        #expect(after.captionWords?.last?.endMS == 7000)
    }

    @Test("A caption before the piece is left exactly as it was")
    func captionBeforeStays() throws {
        var (doc, clip, captions) = Self.talk()
        let id = try #require(captions["before"])
        let was = try #require(doc.layer(id: id))
        doc.rippleDeleteClipPiece(clip, at: 1)
        #expect(doc.layer(id: id) == was)
    }

    @Test("A caption across either end of the piece is shortened, never left running over the join")
    func straddlersShorten() throws {
        var (doc, clip, captions) = Self.talk()
        doc.rippleDeleteClipPiece(clip, at: 1)
        let start = try #require(doc.layer(id: captions["over"] ?? UUID()))
        #expect(start.time?.inMS == 3500)
        #expect(start.time?.outMS == 4000)
        // The words that were said inside the stretch close up onto the join.
        #expect(start.captionWords?.allSatisfy { $0.endMS <= 4000 } == true)
        let end = try #require(doc.captionLayers.first { $0.time?.inMS == 4000 })
        #expect(end.time?.outMS == 5200)
        #expect(end.captionWords?.first?.startMS == 4000)
        #expect(end.captionWords?.last?.endMS == 5200)
    }

    @Test("Titles and sounds after the piece move earlier with it")
    func laterLayersMove() throws {
        var (doc, clip, _) = Self.talk()
        let sound = doc.addSound(SoundRef(durationMS: 2000), name: "whoosh", atMS: 9000)
        var title = Layer(name: "Title", content: .text(TextContent(string: "Next")),
                          frame: CGRect(x: 0, y: 0, width: 200, height: 80))
        title.time = LayerTime(inMS: 10_000, outMS: 11_000)
        doc.addLayer(title)
        doc.rippleDeleteClipPiece(clip, at: 1)
        #expect(doc.layer(id: sound)?.time?.inMS == 5000)
        #expect(doc.layer(id: title.id)?.time?.inMS == 6000)
        #expect(doc.layer(id: title.id)?.time?.outMS == 7000)
    }

    @Test("A title across the whole piece loses exactly the stretch that went")
    func titleAcrossShortens() throws {
        var (doc, clip, _) = Self.talk()
        var title = Layer(name: "Title", content: .text(TextContent(string: "Across")),
                          frame: CGRect(x: 0, y: 0, width: 200, height: 80))
        title.time = LayerTime(inMS: 2000, outMS: 10_000)
        doc.addLayer(title)
        doc.rippleDeleteClipPiece(clip, at: 1)
        #expect(doc.layer(id: title.id)?.time?.inMS == 2000)
        #expect(doc.layer(id: title.id)?.time?.outMS == 6000)
    }

    @Test("A sound that starts inside the piece lands on the join and keeps all it plays")
    func soundStartingInsideLandsOnJoin() throws {
        var (doc, clip, _) = Self.talk()
        let sound = doc.addSound(SoundRef(durationMS: 4000), name: "sting", atMS: 6000)
        doc.rippleDeleteClipPiece(clip, at: 1)
        #expect(doc.layer(id: sound)?.time?.inMS == 4000)
        #expect(doc.layer(id: sound)?.time?.lengthMS == 4000)
    }

    @Test("Music under the whole take is left as it was")
    func musicAcrossStays() throws {
        var (doc, clip, _) = Self.talk()
        let music = doc.addSound(SoundRef(durationMS: 10_000), name: "music", atMS: 1000)
        let was = try #require(doc.layer(id: music)?.time)
        doc.rippleDeleteClipPiece(clip, at: 1)
        #expect(doc.layer(id: music)?.time == was)
    }

    @Test("A document whose captions all went loses its empty Captions group too")
    func emptyCaptionGroupGoes() {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Talk")
        let clip = doc.layers[0].id
        doc.splitClip(clip, atMS: 4000)
        doc.splitClip(clip, atMS: 8000)
        doc.landCaptions([Self.cue("only this", 5000, 7000)])
        doc.rippleDeleteClipPiece(clip, at: 1)
        #expect(!doc.hasCaptions)
        #expect(!doc.allLayers.contains { $0.name == CaptionLayers.groupName })
    }

    @Test("The recording's last caption ends with the recording after the cut")
    func lastCaptionEndsWithRecording() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Talk")
        let clip = doc.layers[0].id
        doc.splitClip(clip, atMS: 4000)
        doc.splitClip(clip, atMS: 8000)
        doc.landCaptions([Self.cue("one", 0, 3000), Self.cue("two", 9000, 12_000)])
        doc.rippleDeleteClipPiece(clip, at: 1)
        let clipOut = try #require(doc.layer(id: clip)?.time?.outMS)
        #expect(clipOut == 8000)
        #expect(doc.captionLayers.last?.time?.outMS == clipOut)
        #expect(doc.documentDurationMS == 8000)
    }

    @Test("Removing a stretch straight out of the document works without a clip to cut")
    func removeTimeDirectly() throws {
        var (doc, _, captions) = Self.talk()
        let did = doc.removeTime(fromMS: 4000, toMS: 8000, exceptLayer: nil)
        #expect(did)
        #expect(doc.layer(id: captions["thrown"] ?? UUID()) == nil)
        #expect(captions["thrown"] != nil)
        let nothing = doc.removeTime(fromMS: 5000, toMS: 5000, exceptLayer: nil)
        #expect(!nothing)
    }
}
