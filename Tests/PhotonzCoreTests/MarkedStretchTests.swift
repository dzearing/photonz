import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Extract and Lift**: an In and an Out marked on the ruler, and one key
/// takes what they enclose out of every track (`MarkedStretch.swift`).
///
/// Premiere's apostrophe (Extract) closes the gap; its semicolon (Lift) leaves
/// one. Cutting a five minute recording to ninety seconds is mostly throwing
/// long stretches away, and before this each stretch cost two cuts, a click
/// and a Delete.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("Extract and Lift a marked stretch")
struct MarkedStretchTests {

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

    /// A twelve second recording, uncut, with a caption before the stretch
    /// from 4.0s to 8.0s, one across each end of it, one inside and one after.
    static func talk() -> (doc: PhotonzDocument, clip: UUID, captions: [String: UUID]) {
        var doc = PhotonzDocument.recording(movie(), name: "Talk")
        let clip = doc.layers[0].id
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

    static func title(_ text: String, _ inMS: Int, _ outMS: Int) -> Layer {
        var title = Layer(name: text, content: .text(TextContent(string: text)),
                          frame: CGRect(x: 0, y: 0, width: 200, height: 80))
        title.time = LayerTime(inMS: inMS, outMS: outMS)
        return title
    }

    // MARK: A clip's own pieces

    @Test("A stretch out of the middle of one piece leaves two that meet at the join")
    func piecesLoseTheMiddle() throws {
        let pieces = ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 12_000)], sourceLengthMS: 12_000)
        let left = try #require(pieces.removingStretch(fromMS: 4000, toMS: 8000))
        #expect(left.totalLengthMS == 8000)
        #expect(left.count == 2)
        #expect(left.piece(at: 0)?.sourceInMS == 0)
        #expect(left.piece(at: 0)?.lengthMS == 4000)
        #expect(left.piece(at: 1)?.sourceInMS == 8000)
        #expect(left.piece(at: 1)?.lengthMS == 4000)
        // What plays right after the join is the frame that played at 8.0s.
        #expect(left.sourceMS(atMS: 4000) == 8000)
    }

    @Test("A stretch across a cut takes the tail of one piece and the head of the next")
    func piecesAcrossACut() throws {
        var pieces = ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 12_000)], sourceLengthMS: 12_000)
        pieces.split(atMS: 6000)
        let left = try #require(pieces.removingStretch(fromMS: 4000, toMS: 8000))
        #expect(left.totalLengthMS == 8000)
        #expect(left.count == 2)
        #expect(left.piece(at: 1)?.sourceInMS == 8000)
    }

    @Test("A piece at double speed loses the frames that played in the stretch")
    func piecesAtSpeed() throws {
        var pieces = ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 12_000)], sourceLengthMS: 12_000)
        pieces.setSpeed(ofPiece: 0, percent: 200)
        // Six seconds on the timeline, reading all twelve of the file.
        let left = try #require(pieces.removingStretch(fromMS: 2000, toMS: 4000))
        #expect(left.totalLengthMS == 4000)
        #expect(left.piece(at: 1)?.sourceInMS == 8000)
    }

    @Test("A clip wholly inside the stretch has nothing left")
    func piecesAllGone() {
        let pieces = ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 6000)], sourceLengthMS: 6000)
        #expect(pieces.removingStretch(fromMS: 0, toMS: 6000) == nil)
        #expect(pieces.removingStretch(fromMS: -100, toMS: 7000) == nil)
    }

    @Test("A stretch that misses the clip changes nothing")
    func piecesMissed() {
        let pieces = ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 6000)], sourceLengthMS: 6000)
        #expect(pieces.removingStretch(fromMS: 7000, toMS: 9000) == pieces)
        #expect(pieces.removingStretch(fromMS: 3000, toMS: 3000) == pieces)
    }

    // MARK: Extract

    @Test("Extract takes the stretch out of the recording and closes the gap")
    func extractClosesTheGap() throws {
        var (doc, clip, _) = Self.talk()
        let did = doc.extractStretch(fromMS: 4000, toMS: 8000)
        #expect(did)
        let time = try #require(doc.layer(id: clip)?.time)
        #expect(time.inMS == 0)
        #expect(time.lengthMS == 8000)
        #expect(doc.layer(id: clip)?.clipPieces?.sourceMS(atMS: 4000) == 8000)
        #expect(doc.documentDurationMS == 8000)
    }

    @Test("Extract takes the captions along: inside go, across an end shorten, after move up")
    func extractTakesCaptions() throws {
        var (doc, _, captions) = Self.talk()
        doc.extractStretch(fromMS: 4000, toMS: 8000)
        #expect(doc.layer(id: captions["thrown"] ?? UUID()) == nil)
        #expect(doc.layer(id: captions["over"] ?? UUID())?.time?.outMS == 4000)
        let past = try #require(doc.layer(id: captions["past"] ?? UUID()))
        #expect(past.time?.inMS == 4000)
        #expect(past.time?.outMS == 5200)
        let after = try #require(doc.layer(id: captions["after"] ?? UUID()))
        #expect(after.time?.inMS == 5500)
        #expect(after.captionWords?.first?.startMS == 5500)
    }

    @Test("Extract cuts music under the stretch too: every unlocked track loses it")
    func extractCutsMusic() throws {
        var (doc, _, _) = Self.talk()
        let music = doc.addSound(SoundRef(durationMS: 10_000), name: "music", atMS: 1000)
        doc.extractStretch(fromMS: 4000, toMS: 8000)
        let time = try #require(doc.layer(id: music)?.time)
        #expect(time.inMS == 1000)
        #expect(time.lengthMS == 6000)
    }

    @Test("Extract cuts the head off a sound that starts inside, and lands the rest on the join")
    func extractCutsAHead() throws {
        var (doc, _, _) = Self.talk()
        let sting = doc.addSound(SoundRef(durationMS: 4000), name: "sting", atMS: 6000)
        doc.extractStretch(fromMS: 4000, toMS: 8000)
        let time = try #require(doc.layer(id: sting)?.time)
        #expect(time.inMS == 4000)
        #expect(time.lengthMS == 2000)
        #expect(doc.layer(id: sting)?.clipPieces?.sourceMS(atMS: 0) == 2000)
    }

    @Test("Extract leaves a clip on a locked track exactly where it was")
    func extractSparesLockedTracks() throws {
        var (doc, _, _) = Self.talk()
        let music = doc.addSound(SoundRef(durationMS: 10_000), name: "music", atMS: 1000)
        doc.materializeTracks()
        let track = try #require(doc.trackID(ofClip: music))
        doc.updateTrack(track) { $0.isLocked = true }
        let was = try #require(doc.layer(id: music))
        doc.extractStretch(fromMS: 4000, toMS: 8000)
        #expect(doc.layer(id: music) == was)
    }

    @Test("A title wholly inside goes, one across the stretch loses exactly it")
    func extractTitles() throws {
        var (doc, _, _) = Self.talk()
        let inside = Self.title("Inside", 5000, 6000)
        let across = Self.title("Across", 2000, 10_000)
        doc.addLayer(inside)
        doc.addLayer(across)
        doc.extractStretch(fromMS: 4000, toMS: 8000)
        #expect(doc.layer(id: inside.id) == nil)
        #expect(doc.layer(id: across.id)?.time?.inMS == 2000)
        #expect(doc.layer(id: across.id)?.time?.outMS == 6000)
    }

    @Test("Marking 1:15 to 2:30 of a five minute recording and extracting leaves 3:45")
    func fiveMinutesToThreeFortyFive() throws {
        var doc = PhotonzDocument.recording(Self.movie(durationMS: 300_000), name: "Long")
        doc.setMarkIn(atMS: 75_000)
        doc.setMarkOut(atMS: 150_000)
        let extracted = doc.extractMarkedStretch()
        #expect(extracted)
        #expect(doc.documentDurationMS == 225_000)
        // The marks are spent: the stretch they named is gone.
        #expect(doc.markInMS == nil)
        #expect(doc.markOutMS == nil)
    }

    @Test("Markers after the stretch move up with the picture, and one inside lands on the join")
    func extractMovesMarkers() {
        var (doc, _, _) = Self.talk()
        doc.addMarker(atMS: 2000)
        doc.addMarker(atMS: 5000)
        doc.addMarker(atMS: 10_000)
        doc.setMarkIn(atMS: 4000)
        doc.setMarkOut(atMS: 8000)
        doc.extractMarkedStretch()
        #expect(doc.markers.map(\.atMS) == [2000, 4000, 6000])
    }

    @Test("With nothing marked there is nothing to extract or lift")
    func nothingMarked() {
        var (doc, _, _) = Self.talk()
        let was = doc
        let extracted = doc.extractMarkedStretch()
        #expect(!extracted)
        let lifted = doc.liftMarkedStretch()
        #expect(!lifted)
        #expect(doc == was)
    }

    // MARK: Lift

    @Test("Lift takes the stretch out and leaves the gap: the clip becomes two on one track")
    func liftLeavesAGap() throws {
        var (doc, clip, _) = Self.talk()
        let track = try #require(doc.trackID(ofClip: clip))
        let did = doc.liftStretch(fromMS: 4000, toMS: 8000)
        #expect(did)
        #expect(doc.documentDurationMS == 12_000)
        let head = try #require(doc.layer(id: clip)?.time)
        #expect(head.inMS == 0)
        #expect(head.outMS == 4000)
        let tail = try #require(doc.allLayers.first { $0.isClip && $0.id != clip })
        #expect(tail.time?.inMS == 8000)
        #expect(tail.time?.outMS == 12_000)
        #expect(tail.clipPieces?.sourceMS(atMS: 0) == 8000)
        #expect(doc.trackID(ofClip: tail.id) == track)
        #expect(doc.trackID(ofClip: clip) == track)
    }

    @Test("Lift takes captions inside with it and trims the ones across an end, moving nothing")
    func liftTrimsCaptions() throws {
        var (doc, _, captions) = Self.talk()
        let after = try #require(doc.layer(id: captions["after"] ?? UUID()))
        doc.liftStretch(fromMS: 4000, toMS: 8000)
        #expect(doc.layer(id: captions["thrown"] ?? UUID()) == nil)
        let over = try #require(doc.layer(id: captions["over"] ?? UUID()))
        #expect(over.time?.outMS == 4000)
        #expect(over.captionWords?.allSatisfy { $0.endMS <= 4000 } == true)
        let past = try #require(doc.layer(id: captions["past"] ?? UUID()))
        #expect(past.time?.inMS == 8000)
        #expect(past.time?.outMS == 9200)
        #expect(past.captionWords?.allSatisfy { $0.startMS >= 8000 } == true)
        #expect(doc.layer(id: after.id) == after)
    }

    @Test("Lift splits a title across the stretch into the part before and the part after")
    func liftSplitsATitle() throws {
        var (doc, _, _) = Self.talk()
        let across = Self.title("Across", 2000, 10_000)
        doc.addLayer(across)
        doc.liftStretch(fromMS: 4000, toMS: 8000)
        #expect(doc.layer(id: across.id)?.time?.outMS == 4000)
        let rest = doc.allLayers.filter { $0.id != across.id && $0.name.hasPrefix("Across") }
            .compactMap(\.time)
        #expect(rest.count == 1)
        #expect(rest.first?.outMS == 10_000)
    }

    @Test("Lift on a marked stretch spends the marks")
    func liftMarked() {
        var (doc, _, _) = Self.talk()
        doc.setMarkIn(atMS: 4000)
        doc.setMarkOut(atMS: 8000)
        let lifted = doc.liftMarkedStretch()
        #expect(lifted)
        #expect(doc.markInMS == nil)
        #expect(doc.markOutMS == nil)
        #expect(doc.documentDurationMS == 12_000)
    }

    // MARK: The keys

    @Test("Apostrophe extracts and semicolon lifts, while the timeline has the keyboard")
    func keys() {
        func command(_ character: Character, focused: Bool) -> TimelineKeyCommand? {
            TimelineKeys.command(for: TimelineKeyPress(key: .letter(character)), timelineFocused: focused)
        }
        #expect(command("'", focused: true) == .extractMarked)
        #expect(command(";", focused: true) == .liftMarked)
        #expect(command("'", focused: false) == nil)
        #expect(command(";", focused: false) == nil)
        // Read off the keyboard, the way the app sees them.
        #expect(TimelineKeyPress(characters: "'", keyCode: 39, modifiers: [], isRepeat: false)?.key == .letter("'"))
        #expect(TimelineKeyPress(characters: ";", keyCode: 41, modifiers: [], isRepeat: false)?.key == .letter(";"))
    }

    @Test("A walk can claim how long the timeline is")
    func walkClaimsLength() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "expectTimeline", "lengthMS": 225000 } ] }
        """.utf8))
        guard case .expectTimeline(let claim) = script.steps[0] else {
            Issue.record("expectTimeline"); return
        }
        #expect(claim.lengthMS == 225_000)
    }
}
