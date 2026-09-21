import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A transition lives at a cut (`docs/design/video-transitions.md`).
///
/// Written before the model, which is the rule for `PhotonzCore`. The one thing
/// every test here is really about: **a transition is a relationship between
/// the two pieces either side of a join, not a filter on one of them.** So it
/// is asked for by naming the cut, it is paid for out of BOTH sides' spare
/// media, and what it does is answered in one place that the canvas and the
/// exporter both read.
@Suite("A transition lives at the cut between two pieces")
struct ClipTransitionTests {

    static func movie(durationMS: Int = 20_000) -> MovieRef {
        MovieRef(id: UUID(uuidString: "AAAAAAAA-2222-3333-4444-555555555555")!,
                 pixelSize: CGSize(width: 640, height: 480), durationMS: durationMS)
    }

    /// Two pieces of one recording that are NOT next to each other in the file:
    /// the middle was thrown away, which is the commonest real cut there is.
    /// Each side has spare media because the file runs on past both.
    static func cutClip() -> ClipPieces {
        ClipPieces(pieces: [ClipPiece(sourceInMS: 1000, lengthMS: 3000),
                            ClipPiece(sourceInMS: 10_000, lengthMS: 4000)],
                   sourceLengthMS: 20_000)
    }

    // MARK: - Where a transition lives

    @Test("A clip of one piece has no cuts, so there is nowhere to put one")
    func onePieceHasNoCuts() {
        let pieces = ClipPieces(single: LayerTime(inMS: 0, outMS: 5000,
                                                  sourceInMS: 0, sourceLengthMS: 20_000))
        #expect(pieces.cutIndices.isEmpty)
        var trial = pieces
        let did1 = trial.setTransition(ClipTransition(kind: .dissolve), atCut: 0)
        #expect(did1 == false)
        let did2 = trial.setTransition(ClipTransition(kind: .dissolve), atCut: 1)
        #expect(did2 == false)
    }

    @Test("A cut is named by the piece that arrives at it")
    func aCutIsNamedByTheIncomingPiece() {
        var pieces = Self.cutClip()
        #expect(pieces.cutIndices == [1])
        let did3 = pieces.setTransition(ClipTransition(kind: .dissolve, lengthMS: 600), atCut: 1)
        #expect(did3)
        #expect(pieces.transition(atCut: 1)?.kind == .dissolve)
        #expect(pieces.transition(atCut: 1)?.lengthMS == 600)
        // And the cut knows where it is on the clip's own clock.
        #expect(pieces.cut(at: 1)?.atMS == 3000)
    }

    @Test("Taking the transition off a cut leaves a hard cut")
    func aTransitionCanBeTakenOff() {
        var pieces = Self.cutClip()
        let did4 = pieces.setTransition(ClipTransition(kind: .dipToBlack), atCut: 1)
        #expect(did4)
        let did5 = pieces.setTransition(nil, atCut: 1)
        #expect(did5)
        #expect(pieces.transition(atCut: 1) == nil)
        #expect(pieces.hasAnyTransition == false)
    }

    @Test("A piece carried somewhere else in the order takes how it arrives with it")
    func aTransitionFollowsThePieceThatArrives() {
        var pieces = ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 2000),
                                         ClipPiece(sourceInMS: 8000, lengthMS: 2000),
                                         ClipPiece(sourceInMS: 15_000, lengthMS: 2000)],
                                sourceLengthMS: 20_000)
        let did6 = pieces.setTransition(ClipTransition(kind: .dipToWhite, lengthMS: 500), atCut: 2)
        #expect(did6)
        let did7 = pieces.move(from: 2, to: 1)
        #expect(did7)
        // The dip went with the piece it was the arrival of, so it is now at
        // the cut that piece arrives at, and the other cut is hard.
        #expect(pieces.transition(atCut: 1)?.kind == .dipToWhite)
        #expect(pieces.transition(atCut: 2) == nil)
    }

    @Test("Cutting a piece in two leaves the new join hard and the old one alone")
    func splittingKeepsTheTransitionWhereItWas() {
        var pieces = Self.cutClip()
        let did8 = pieces.setTransition(ClipTransition(kind: .dissolve, lengthMS: 400), atCut: 1)
        #expect(did8)
        // Cut the SECOND piece in half: pieces become 0, 1, 2 and the dissolve
        // is still the way piece 1 arrives.
        let did9 = pieces.split(atMS: 5000)
        #expect(did9)
        #expect(pieces.count == 3)
        #expect(pieces.transition(atCut: 1)?.kind == .dissolve)
        #expect(pieces.transition(atCut: 2) == nil)
    }

    @Test("A transition writes nothing into a clip that has none")
    func nothingIsWrittenWithoutATransition() throws {
        let plain = Self.cutClip()
        let written = try JSONEncoder().encode(plain)
        let text = String(decoding: written, as: UTF8.self)
        #expect(!text.contains("transition"))
        var withOne = plain
        let did10 = withOne.setTransition(ClipTransition(kind: .dissolve, lengthMS: 700), atCut: 1)
        #expect(did10)
        let round = try JSONDecoder().decode(ClipPieces.self,
                                             from: try JSONEncoder().encode(withOne))
        #expect(round == withOne)
        #expect(round.transition(atCut: 1)?.lengthMS == 700)
    }

    // MARK: - What a cut can afford

    @Test("A cut says what spare media there is either side of it")
    func aCutKnowsItsSpare() throws {
        let cut = try #require(Self.cutClip().cut(at: 1))
        // The outgoing piece stops at 4000ms of a 20s file, so there are 16
        // seconds of it left to run on into.
        #expect(cut.spareAfterOutMS == 16_000)
        // The incoming piece starts 10 seconds in, so there are 10 seconds of
        // it before its first frame.
        #expect(cut.spareBeforeInMS == 10_000)
    }

    @Test("A transition may not reach past the middle of either piece it joins")
    func aTransitionStopsAtTheMiddleOfEitherPiece() throws {
        let cut = try #require(Self.cutClip().cut(at: 1))
        // Three seconds out, four seconds in: the shorter one decides.
        #expect(cut.longestMS(of: .dissolve) == 3000)
        #expect(cut.longestMS(of: .dipToBlack) == 3000)
    }

    @Test("With no spare media, the ones that need an overlap cannot be afforded and the dips can")
    func noSpareMeansNoOverlap() throws {
        // Both pieces read the file from its very first frame and to its very
        // last: there is nothing either side to spend.
        let pieces = ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 5000),
                                         ClipPiece(sourceInMS: 5000, lengthMS: 5000)],
                                sourceLengthMS: 10_000)
        let cut = try #require(pieces.cut(at: 1))
        #expect(cut.spareAfterOutMS == 5000)   // the file runs on past the outgoing piece
        #expect(cut.spareBeforeInMS == 5000)
        // ...but the same clip with both pieces hard against the ends of the file:
        let tight = ClipPieces(pieces: [ClipPiece(sourceInMS: 5000, lengthMS: 5000),
                                        ClipPiece(sourceInMS: 0, lengthMS: 5000)],
                               sourceLengthMS: 10_000)
        let tightCut = try #require(tight.cut(at: 1))
        #expect(tightCut.spareAfterOutMS == 0)
        #expect(tightCut.spareBeforeInMS == 0)
        #expect(tightCut.canAfford(.dissolve) == false)
        #expect(tightCut.longestMS(of: .dissolve) == 0)
        #expect(tightCut.canAfford(.dipToBlack))
        #expect(tightCut.longestMS(of: .dipToBlack) == 5000)
    }

    @Test("A dissolve longer than the cut can pay for is refused, not quietly shortened")
    func tooLongIsRefused() {
        var tight = ClipPieces(pieces: [ClipPiece(sourceInMS: 5000, lengthMS: 5000),
                                        ClipPiece(sourceInMS: 0, lengthMS: 5000)],
                               sourceLengthMS: 10_000)
        let did11 = tight.setTransition(ClipTransition(kind: .dissolve, lengthMS: 400), atCut: 1)
        #expect(did11 == false)
        #expect(tight.transition(atCut: 1) == nil)
        var room = Self.cutClip()
        let did12 = room.setTransition(ClipTransition(kind: .dissolve, lengthMS: 9000), atCut: 1)
        #expect(did12 == false)
        let did13 = room.setTransition(ClipTransition(kind: .dissolve, lengthMS: 3000), atCut: 1)
        #expect(did13)
    }

    @Test("A cut where the two pieces read the same frames says a dissolve would be invisible")
    func aPlainSplitIsContinuous() throws {
        var pieces = ClipPieces(single: LayerTime(inMS: 0, outMS: 6000,
                                                  sourceInMS: 0, sourceLengthMS: 20_000))
        let did14 = pieces.split(atMS: 3000)
        #expect(did14)
        let cut = try #require(pieces.cut(at: 1))
        // The frames on both sides of this join are the same frames, so
        // blending them shows nothing at all.
        #expect(cut.isContinuous)
        // ...whereas a join with something thrown away between its sides is a
        // real change of picture.
        #expect(try #require(Self.cutClip().cut(at: 1)).isContinuous == false)
    }

    // MARK: - What is on screen in the middle of one

    @Test("Away from every transition, a clip shows the one frame it always did")
    func awayFromACutNothingChanges() throws {
        var pieces = Self.cutClip()
        let did15 = pieces.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000), atCut: 1)
        #expect(did15)
        let moment = try #require(pieces.moment(atMS: 500))
        #expect(moment.sourceMS == pieces.sourceMS(atMS: 500))
        #expect(moment.incomingSourceMS == nil)
        #expect(moment.dipColorHex == nil)
    }

    @Test("Half way through a dissolve, both pieces are on screen, half and half")
    func aDissolvePutsBothOnScreen() throws {
        var pieces = Self.cutClip()
        let did16 = pieces.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000), atCut: 1)
        #expect(did16)
        // The cut is at 3000; a second of dissolve is 2500 to 3500.
        let middle = try #require(pieces.moment(atMS: 3000))
        #expect(abs(middle.incomingOpacity - 0.5) < 0.01)
        #expect(middle.dipColorHex == nil)
        // Before the cut, the outgoing piece is playing its own frames and the
        // INCOMING one has started early, out of the spare before its in point.
        let early = try #require(pieces.moment(atMS: 2750))
        #expect(early.sourceMS == 1000 + 2750)
        #expect(early.incomingSourceMS == 10_000 - 250)
        // After it, the outgoing piece is running on past its own out point,
        // out of the spare after it, and the incoming one is playing its own.
        let late = try #require(pieces.moment(atMS: 3250))
        #expect(late.sourceMS == 1000 + 3250)          // 250ms past its own last frame
        #expect(late.incomingSourceMS == 10_000 + 250)
    }

    @Test("A dissolve starts on the outgoing picture and ends on the incoming one")
    func aDissolveRunsFromOneToTheOther() throws {
        var pieces = Self.cutClip()
        let did17 = pieces.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000), atCut: 1)
        #expect(did17)
        let start = try #require(pieces.moment(atMS: 2500))
        #expect(start.incomingOpacity < 0.02)
        let nearlyDone = try #require(pieces.moment(atMS: 3490))
        #expect(nearlyDone.incomingOpacity > 0.97)
        // And the instant it is over, the clip is simply playing the incoming
        // piece the way it always did.
        let after = try #require(pieces.moment(atMS: 3500))
        #expect(after.incomingSourceMS == nil)
        #expect(after.sourceMS == pieces.sourceMS(atMS: 3500))
    }

    @Test("A dip spends no media: each piece plays its own frames and the picture goes through a colour")
    func aDipSpendsNothing() throws {
        var pieces = Self.cutClip()
        let did18 = pieces.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 1000), atCut: 1)
        #expect(did18)
        let before = try #require(pieces.moment(atMS: 2750))
        // The frame is the one that was always there: nothing has run on.
        #expect(before.sourceMS == pieces.sourceMS(atMS: 2750))
        #expect(before.incomingSourceMS == nil)
        #expect(before.dipColorHex == "#000000")
        #expect(abs(before.dipOpacity - 0.5) < 0.02)
        // Right on the cut it is all the way through the colour.
        let atTheCut = try #require(pieces.moment(atMS: 3000))
        #expect(atTheCut.dipOpacity > 0.99)
        // And on the far side it comes back up out of it.
        let after = try #require(pieces.moment(atMS: 3250))
        #expect(after.sourceMS == pieces.sourceMS(atMS: 3250))
        #expect(abs(after.dipOpacity - 0.5) < 0.02)
    }

    @Test("A dip to white goes through white")
    func aDipToWhiteIsWhite() throws {
        var pieces = Self.cutClip()
        let did19 = pieces.setTransition(ClipTransition(kind: .dipToWhite, lengthMS: 400), atCut: 1)
        #expect(did19)
        #expect(try #require(pieces.moment(atMS: 3000)).dipColorHex == "#FFFFFF")
    }

    // MARK: - The document draws it, and the same answer is what gets exported

    static func clipDocument(_ pieces: ClipPieces) -> PhotonzDocument {
        var layer = Layer(name: "Recording",
                          content: .image(Self.movie().frameRef(atSourceMS: 0)),
                          frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        layer.movie = Self.movie()
        layer.time = LayerTime(inMS: 0, outMS: pieces.totalLengthMS,
                               sourceInMS: 0, sourceLengthMS: 20_000)
        layer.setClipPieces(pieces)
        var document = PhotonzDocument(canvasSize: CGSize(width: 640, height: 480),
                                       layers: [layer])
        document.durationMS = layer.time?.outMS
        return document
    }

    @Test("In the middle of a dissolve the document hands the renderer two pictures")
    func theDocumentDrawsBothPictures() throws {
        var pieces = Self.cutClip()
        let did20 = pieces.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000), atCut: 1)
        #expect(did20)
        let document = Self.clipDocument(pieces)
        let shown = document.drawn(atTimeMS: 3000)
        #expect(shown.layers.count == 2)
        // The lower one is the shot going out, at full strength; the one over
        // it is the shot coming in, half way up.
        #expect(shown.layers[0].style.opacity == 1)
        #expect(abs(shown.layers[1].style.opacity - 0.5) < 0.01)
        #expect(shown.layers[0].id != shown.layers[1].id)
        // Both of them are pictures, which is the whole trick: the renderer
        // never learns that transitions exist.
        for layer in shown.layers { #expect(layer.imageRef != nil) }
        // And either side of the dissolve there is one picture again.
        #expect(document.drawn(atTimeMS: 500).layers.count == 1)
        #expect(document.drawn(atTimeMS: 5000).layers.count == 1)
    }

    @Test("In the middle of a dip the document lays a colour over the picture")
    func theDocumentDrawsTheDip() throws {
        var pieces = Self.cutClip()
        let did21 = pieces.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 1000), atCut: 1)
        #expect(did21)
        let document = Self.clipDocument(pieces)
        let shown = document.drawn(atTimeMS: 3000)
        #expect(shown.layers.count == 2)
        let dip = try #require(shown.layers.last)
        #expect(dip.annotation?.fillColorHex == "#000000")
        #expect(dip.style.opacity > 0.99)
        // It covers the clip it belongs to and nothing else.
        #expect(dip.frame == shown.layers[0].frame)
    }

    @Test("Both frames of a dissolve are asked for, so neither is missing when it is drawn")
    func bothFramesAreFetched() throws {
        var pieces = Self.cutClip()
        let did22 = pieces.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000), atCut: 1)
        #expect(did22)
        let document = Self.clipDocument(pieces)
        let wanted = document.movieFrames(atTimeMS: 3000)
        #expect(wanted.count == 2)
        #expect(Set(wanted.map(\.ref)).count == 2)
        // Away from the dissolve it is one frame, exactly as before.
        #expect(document.movieFrames(atTimeMS: 500).count == 1)
    }

    @Test("What an export photographs is what the canvas draws, transition and all")
    func whatPlaysIsWhatExports() throws {
        var pieces = Self.cutClip()
        let did23 = pieces.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000), atCut: 1)
        #expect(did23)
        let document = Self.clipDocument(pieces)
        // The export photographs `drawn(atTimeMS:)`, so this is the same
        // question asked the way the writer asks it.
        let plan = DocumentVideoExport.plan(durationMS: document.documentDurationMS,
                                            canvasSize: document.canvasSize,
                                            format: .mp4, quality: .high)
        let moments = (0..<plan.frameCount).map { plan.timeMS(at: $0) }
        let inside = try #require(moments.first { $0 >= 2900 && $0 <= 3100 })
        let picture = document.drawn(atTimeMS: inside)
        #expect(picture.layers.count == 2)
        // A clip with a transition on it is never the untouched recording, so
        // an export can never take the copy-the-file shortcut past it.
        #expect(document.untouchedRecording == nil)
    }

    // MARK: - The clip in the document, edited through history

    @Test("A transition goes on and comes off through the document, like any other edit")
    func theDocumentEditsIt() throws {
        var document = Self.clipDocument(Self.cutClip())
        let id = try #require(document.layers.first?.id)
        let put = document.setClipTransition(id, atCut: 1,
                                             to: ClipTransition(kind: .dissolve, lengthMS: 800))
        #expect(put)
        #expect(document.layer(id: id)?.clipPieces?.transition(atCut: 1)?.lengthMS == 800)
        // The clip did not move and did not change length: a transition is
        // paid for with spare frames, never with position.
        #expect(document.layer(id: id)?.time == LayerTime(inMS: 0, outMS: 7000,
                                                          sourceInMS: 1000,
                                                          sourceLengthMS: 20_000))
        let did24 = document.setClipTransition(id, atCut: 1, to: nil)
        #expect(did24)
        #expect(document.layer(id: id)?.clipPieces?.hasAnyTransition == false)
        // A cut that is not there is refused rather than invented.
        let nowhere = document.setClipTransition(id, atCut: 5,
                                                 to: ClipTransition(kind: .dissolve))
        #expect(nowhere == false)
    }
}
