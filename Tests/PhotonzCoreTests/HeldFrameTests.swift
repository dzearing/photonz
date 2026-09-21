import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Holding on a frame (`docs/design/mocks/pages/video-freeze-wt.html`,
/// `hold-on-a-frame`).
///
/// Written before the model, which is the rule for `PhotonzCore`. The page says
/// the design and the test in one line: **"A freeze is not a special object: it
/// is a clip whose in and out are the same frame, so it drops into the timeline
/// like any other."** So every test here is a test that a hold behaves like the
/// pieces either side of it — it is trimmed by the same call, it is given a
/// length by the same call, and what is drawn over it is an ordinary layer with
/// an in and an out.
@Suite("A frame held is an ordinary piece of the edit")
struct HeldFrameTests {

    static func movie(durationMS: Int = 8000) -> MovieRef {
        MovieRef(id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
                 pixelSize: CGSize(width: 1920, height: 1080),
                 durationMS: durationMS)
    }

    /// An eight second recording as the document it opens as, with a two
    /// second hold taken at four seconds.
    static func held(holdMS: Int = 2000) -> (doc: PhotonzDocument, clip: UUID) {
        var doc = PhotonzDocument.recording(movie(), name: "Take 1")
        let id = doc.layers[0].id
        let held = doc.holdFrame(id, atMS: 4000, forMS: holdMS)
        #expect(held)
        return (doc, id)
    }

    /// The mark somebody draws on a held frame, which is the reason they held
    /// it in the first place.
    static func arrow() -> Layer {
        Layer(name: "Arrow",
              content: .annotation(AnnotationContent(shape: .arrow, strokeWidth: 4,
                                                     colorHex: "#FF3B30")),
              frame: CGRect(x: 10, y: 10, width: 100, height: 40))
    }

    // MARK: - A chosen length

    @Test("A held frame can be given a length, and everything after it moves along")
    func aHoldCanBeGivenALength() throws {
        var (doc, id) = Self.held()
        #expect(doc.documentDurationMS == 10_000)
        let did1 = doc.setHoldLength(id, ofPiece: 1, toMS: 5000)
        #expect(did1)
        let pieces = try #require(doc.layer(id: id)?.clipPieces)
        #expect(pieces.piece(at: 1)?.lengthMS == 5000)
        #expect(pieces.piece(at: 1)?.isHeld == true)
        // The eight second recording plus five seconds of one frame.
        #expect(doc.documentDurationMS == 13_000)
        // ...and the piece after it starts five seconds later than it did,
        // because a hold INSERTS time rather than covering it over.
        #expect(pieces.startMS(ofPiece: 2) == 9000)
    }

    @Test("Giving a hold a length keeps the frame it holds")
    func aLengthKeepsTheFrame() throws {
        var (doc, id) = Self.held()
        let before = try #require(doc.layer(id: id)?.movieFrameSourceMS(atTimeMS: 4500))
        let did2 = doc.setHoldLength(id, ofPiece: 1, toMS: 6000)
        #expect(did2)
        let after = try #require(doc.layer(id: id)?.movieFrameSourceMS(atTimeMS: 4500))
        #expect(after == before)
        // ...however far into the hold you look.
        #expect(doc.layer(id: id)?.movieFrameSourceMS(atTimeMS: 9500) == before)
    }

    @Test("A piece that plays has no hold length to set")
    func onlyAHoldTakesAHoldLength() {
        var (doc, id) = Self.held()
        let did3 = doc.setHoldLength(id, ofPiece: 0, toMS: 3000)
        #expect(!did3)
        let did4 = doc.setHoldLength(id, ofPiece: 2, toMS: 3000)
        #expect(!did4)
        // ...and the length it already has is not an edit at all, so it is
        // never an undo step that does nothing.
        let did5 = doc.setHoldLength(id, ofPiece: 1, toMS: 2000)
        #expect(!did5)
    }

    @Test("A hold cannot be made so short that nobody could grab it again")
    func aHoldHasAFloor() throws {
        var (doc, id) = Self.held()
        let did6 = doc.setHoldLength(id, ofPiece: 1, toMS: -400)
        #expect(did6)
        let pieces = try #require(doc.layer(id: id)?.clipPieces)
        #expect(pieces.piece(at: 1)?.lengthMS == ClipPiece.shortestMS)
    }

    @Test("A hold can be held for as long as it needs, well past what the panel offers")
    func aHoldHasNoCeiling() throws {
        var (doc, id) = Self.held()
        let did7 = doc.setHoldLength(id, ofPiece: 1, toMS: 120_000)
        #expect(did7)
        #expect(doc.layer(id: id)?.clipPieces?.piece(at: 1)?.lengthMS == 120_000)
        // What the panel offers in one click is a short list of the lengths
        // people actually pick, never a limit on the edit itself.
        #expect(ClipPieces.holdStopsMS.max() ?? 0 < 120_000)
        #expect(ClipPieces.holdStopsMS.map(ClipPieces.holdTitle) == ["1s", "2s", "3s", "5s", "10s"])
    }

    // MARK: - What is being held at a moment

    @Test("The moment under the playhead says which frame is being held, and for how long")
    func theHoldUnderTheMoment() throws {
        let (doc, id) = Self.held()
        let held = try #require(doc.heldFrame(atTimeMS: 5000))
        #expect(held.layerID == id)
        #expect(held.pieceIndex == 1)
        #expect(held.inMS == 4000)
        #expect(held.outMS == 6000)
        #expect(held.lengthMS == 2000)
        // The frame it holds, in the recording's own clock: four seconds in.
        // The moment the hold was taken at, NOT the frame grid that moment is
        // fetched on — a badge saying 0:03 about a freeze taken at 0:04 is a
        // badge nobody believes.
        #expect(held.sourceMS == 4000)
    }

    @Test("A moment in a piece that plays is holding nothing")
    func nothingHeldWhereItPlays() {
        let (doc, _) = Self.held()
        #expect(doc.heldFrame(atTimeMS: 1000) == nil)
        #expect(doc.heldFrame(atTimeMS: 7000) == nil)
        // The out is the first moment the hold is over, the same half-open rule
        // every stretch in the document follows.
        #expect(doc.heldFrame(atTimeMS: 6000) == nil)
        #expect(doc.heldFrame(atTimeMS: 5999) != nil)
    }

    @Test("A clip placed later in the timeline holds on the document's clock, not its own")
    func aHoldOnAClipPlacedLater() throws {
        var (doc, id) = Self.held()
        doc.updateLayer(id: id) { $0.time = $0.time?.moved(toInMS: 3000) }
        #expect(doc.heldFrame(atTimeMS: 5000) == nil)
        let held = try #require(doc.heldFrame(atTimeMS: 8000))
        #expect(held.inMS == 7000)
        #expect(held.outMS == 9000)
    }

    @Test("A document with no time in it never holds anything")
    func noTimeNoHold() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        #expect(doc.heldFrame(atTimeMS: 0) == nil)
    }

    @Test("The badge says what is on screen and which frame it came from")
    func theBadgeSaysWhichFrame() throws {
        let (doc, _) = Self.held()
        let held = try #require(doc.heldFrame(atTimeMS: 5000))
        #expect(held.badge == "Held frame · 0:04")
        #expect(held.lengthSentence == "One frame, on screen for 2s.")
    }

    // MARK: - Drawing on a held frame

    @Test("A shape drawn while the playhead stands in a hold is on screen for exactly the hold")
    func aShapeDrawnOnAHoldTakesItsSpan() throws {
        var (doc, _) = Self.held()
        let arrow = Self.arrow()
        doc.addLayerDrawn(arrow, atTimeMS: 5000)
        let landed = try #require(doc.layer(id: arrow.id))
        let time = try #require(landed.time)
        #expect(time.inMS == 4000)
        #expect(time.outMS == 6000)
        // On screen for the hold and nowhere else, which is what the timeline
        // then draws as a bar lined up with it.
        #expect(landed.isOnScreen(atTimeMS: 5000))
        #expect(!landed.isOnScreen(atTimeMS: 3000))
        #expect(!landed.isOnScreen(atTimeMS: 7000))
    }

    @Test("A shape drawn where the recording plays is on screen for the whole thing, as before")
    func aShapeDrawnOffAHoldIsUnchanged() throws {
        var (doc, _) = Self.held()
        let arrow = Self.arrow()
        doc.addLayerDrawn(arrow, atTimeMS: 1000)
        #expect(doc.layer(id: arrow.id)?.time == nil)
        #expect(doc.layer(id: arrow.id)?.isOnScreen(atTimeMS: 7000) == true)
    }

    @Test("A clip dropped on a hold keeps its own stretch rather than taking the hold's")
    func somethingThatAlreadyOccupiesTimeKeepsIt() throws {
        var (doc, _) = Self.held()
        var second = Self.arrow()
        second.time = LayerTime(inMS: 0, outMS: 3000, sourceInMS: 0, sourceLengthMS: 3000)
        doc.addLayerDrawn(second, atTimeMS: 5000)
        #expect(doc.layer(id: second.id)?.time?.inMS == 0)
        #expect(doc.layer(id: second.id)?.time?.outMS == 3000)
    }

    @Test("A shape drawn on a hold animates over the hold, because the hold is its whole life")
    func aShapeOnAHoldAnimatesOverIt() throws {
        var (doc, _) = Self.held()
        var arrow = Self.arrow()
        arrow.motions = [LayerMotion(property: .opacity, from: .number(0), to: .number(100),
                                     timing: MotionTiming(startMS: 0, durationMS: 2000),
                                     curve: .linear, repeats: .once)]
        doc.addLayerDrawn(arrow, atTimeMS: 5000)
        // Halfway through the hold is halfway through the fade: the layer's
        // motion is read on its own clock, which the hold's in and out set.
        let middle = try #require(doc.drawn(atTimeMS: 5000).layer(id: arrow.id))
        #expect(abs(middle.style.opacity - 0.5) < 0.05)
        let start = try #require(doc.drawn(atTimeMS: 4000).layer(id: arrow.id))
        #expect(start.style.opacity < 0.05)
    }

    @Test("A hold pushes the picture along, and sound on its own layer keeps running under it")
    func aHoldPushesThePictureOnly() throws {
        var (doc, id) = Self.held()
        let musicID = doc.addSound(SoundRef(durationMS: 8000), name: "voice over", atMS: 0)
        let before = try #require(doc.layer(id: musicID)?.time)
        let did = doc.setHoldLength(id, ofPiece: 1, toMS: 5000)
        #expect(did)
        // The picture is five seconds longer and the voice is where it was:
        // you keep talking over the frozen frame. It is also the other half of
        // the freeze clickthrough's open question, which nobody has answered —
        // a hold that pushed EVERYTHING would keep a voice locked to the shot
        // it belongs to, at the cost of the case above.
        #expect(doc.layer(id: musicID)?.time == before)
        #expect(doc.layer(id: id)?.time?.outMS == 13_000)
    }

    // MARK: - What comes out of it

    @Test("A hold exports as the frames it should be rather than as a still that stutters")
    func aHoldExportsAsFrames() throws {
        var (doc, id) = Self.held()
        let did8 = doc.setHoldLength(id, ofPiece: 1, toMS: 3000)
        #expect(did8)
        // Eight seconds of recording plus three seconds of one frame.
        #expect(doc.documentDurationMS == 11_000)
        let plan = DocumentVideoExport.plan(durationMS: doc.documentDurationMS,
                                            canvasSize: doc.canvasSize,
                                            format: .mp4, quality: .high)
        #expect(plan.durationMS == 11_000)
        // Every frame of the hold is photographed, at the same rate as the rest
        // of the file: a hold is not one long frame, it is the same frame many
        // times, which is what stops a player from stalling on it.
        let inTheHold = (0..<plan.frameCount).filter { index in
            let ms = plan.timeMS(at: index)
            return ms >= 4000 && ms < 7000
        }
        #expect(inTheHold.count == Int((3.0 * plan.fps).rounded()))
        let clip = try #require(doc.layer(id: id))
        let frames = Set(inTheHold.map { clip.movieFrameSourceMS(atTimeMS: plan.timeMS(at: $0)) })
        // ...and every one of them is the SAME frame of the recording.
        #expect(frames.count == 1)
        #expect(frames.first == Self.movie().frameSourceMS(atSourceMS: 4000))
        // A recording with a hold in it is no longer the file it came from, so
        // the export cannot take the copy-the-file shortcut.
        #expect(doc.untouchedRecording == nil)
    }
}
