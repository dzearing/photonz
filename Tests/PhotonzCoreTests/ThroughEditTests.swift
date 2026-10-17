import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Join Through Edit** (`ThroughEdit.swift`): a cut whose two sides still
/// read straight on from each other, the same recording at the same speed with
/// nothing taken out, put back into one piece. Premiere's name for such a cut
/// is a through edit, and its right-click joins it.
@Suite("Joining a through edit")
struct ThroughEditTests {

    static let take = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 10_000)

    /// The sample recording, 0 to 10s, cut with B at 4s.
    static func cutAt4s() -> (doc: PhotonzDocument, clip: UUID) {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let clip = doc.layers[0].id
        doc.updateLayer(id: clip) {
            $0.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0, sourceLengthMS: 10_000)
        }
        let cut = doc.splitClip(clip, atMS: 4000)
        #expect(cut)
        return (doc, clip)
    }

    // MARK: - Inside one clip

    @Test("A cut made with B and nothing else joins back into the one clip it was")
    func joinsWhatBMade() throws {
        var (doc, clip) = Self.cutAt4s()
        let uncut = Self.uncut()
        #expect(doc.layer(id: clip)?.clipPieces?.count == 2)
        #expect(doc.canJoinThroughEdit(at: .join(clip: clip, index: 1)))
        let joined = doc.joinThroughEdit(at: .join(clip: clip, index: 1))
        #expect(joined)
        let layer = try #require(doc.layer(id: clip))
        #expect(layer.clipPieces?.count == 1)
        #expect(layer.time == uncut.layers[0].time)
        // Back to a plain stretch: nothing extra written down.
        #expect(layer.cuts == nil)
    }

    @Test("The join keeps the earlier piece's marks and drops the transition on the cut")
    func earlierPieceWins() throws {
        var (doc, clip) = Self.cutAt4s()
        // Hide the picture of the second piece only.
        doc.updateLayer(id: clip) { layer in
            var pieces = try! #require(layer.clipPieces)
            pieces.setPictureHidden(ofPiece: 1, true)
            layer.setClipPieces(pieces)
        }
        let dip = ClipTransition(kind: .dipToBlack, lengthMS: 500)
        let did1 = doc.setTransition(dip, at: .join(clip: clip, index: 1))
        #expect(did1)
        #expect(doc.canJoinThroughEdit(at: .join(clip: clip, index: 1)))
        let did2 = doc.joinThroughEdit(at: .join(clip: clip, index: 1))
        #expect(did2)
        let piece = try #require(doc.layer(id: clip)?.clipPieces?.piece(at: 0))
        #expect(piece.pictureHidden == false)
        #expect(piece.transitionIn == nil)
        #expect(piece.sourceInMS == 0)
        #expect(piece.lengthMS == 10_000)
    }

    @Test("Joining the middle cut of three pieces leaves the other cut where it was")
    func middleCutOfThree() throws {
        var (doc, clip) = Self.cutAt4s()
        let did3 = doc.splitClip(clip, atMS: 7000)
        #expect(did3)
        let did4 = doc.joinThroughEdit(at: .join(clip: clip, index: 1))
        #expect(did4)
        let pieces = try #require(doc.layer(id: clip)?.clipPieces)
        #expect(pieces.pieces.map(\.lengthMS) == [7000, 3000])
        #expect(pieces.pieces.map(\.sourceInMS) == [0, 7000])
    }

    @Test("A cut with frames taken out between its sides is not a through edit")
    func framesRemovedIsNotThrough() throws {
        var (doc, clip) = Self.cutAt4s()
        let did5 = doc.splitClip(clip, atMS: 6000)
        #expect(did5)
        // Throw away 4s to 6s: the cut at 4s now jumps two seconds.
        let did6 = doc.removeClipPiece(clip, at: 1)
        #expect(did6)
        #expect(doc.canJoinThroughEdit(at: .join(clip: clip, index: 1)) == false)
        let did7 = doc.joinThroughEdit(at: .join(clip: clip, index: 1))
        #expect(did7 == false)
        #expect(doc.layer(id: clip)?.clipPieces?.count == 2)
    }

    @Test("A cut where the speed changes is not a through edit")
    func speedChangeIsNotThrough() {
        var (doc, clip) = Self.cutAt4s()
        let did8 = doc.setClipSpeed(clip, ofPiece: 1, percent: 200)
        #expect(did8)
        #expect(doc.canJoinThroughEdit(at: .join(clip: clip, index: 1)) == false)
    }

    @Test("Two pieces at the same changed speed still join, at that speed")
    func sameChangedSpeedJoins() throws {
        var (doc, clip) = Self.cutAt4s()
        let did9 = doc.setClipSpeed(clip, ofPiece: 0, percent: 200)
        #expect(did9)
        let did10 = doc.setClipSpeed(clip, ofPiece: 1, percent: 200)
        #expect(did10)
        #expect(doc.canJoinThroughEdit(at: .join(clip: clip, index: 1)))
        let did11 = doc.joinThroughEdit(at: .join(clip: clip, index: 1))
        #expect(did11)
        let piece = try #require(doc.layer(id: clip)?.clipPieces?.piece(at: 0))
        #expect(piece.speedPercent == 200)
        #expect(piece.sourceInMS == 0)
        #expect(piece.sourceOutMS == 10_000)
    }

    @Test("A held frame on either side is not a through edit")
    func holdIsNotThrough() {
        var (doc, clip) = Self.cutAt4s()
        let did12 = doc.holdFrame(clip, atMS: 2000)
        #expect(did12)
        let cuts = doc.layer(id: clip)?.clipPieces?.cutIndices ?? []
        for index in cuts {
            let place = TimelineCutPlace.join(clip: clip, index: index)
            let cut = doc.documentCut(at: place)?.cut
            #expect(doc.canJoinThroughEdit(at: place) == (cut?.isContinuous == true))
            if cut?.outgoing.isHeld == true || cut?.incoming.isHeld == true {
                #expect(doc.canJoinThroughEdit(at: place) == false)
            }
        }
    }

    @Test("Nothing else in the document moves")
    func nothingElseMoves() throws {
        var (doc, clip) = Self.cutAt4s()
        var title = Layer(name: "title", content: .image(Self.take.frameRef(atSourceMS: 0)),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        title.time = LayerTime(inMS: 3000, outMS: 6000)
        doc.layers.append(title)
        let others = doc.layers.filter { $0.id != clip }
        let did13 = doc.joinThroughEdit(at: .join(clip: clip, index: 1))
        #expect(did13)
        #expect(doc.layers.filter { $0.id != clip } == others)
        #expect(doc.durationMS == 10_000 || doc.durationMS == nil)
    }

    @Test("A cut on a locked track is not joined")
    func lockedTrackRefuses() throws {
        var (doc, clip) = Self.cutAt4s()
        let track = try #require(doc.trackID(ofClip: clip))
        doc.updateTrack(track) { $0.isLocked = true }
        #expect(doc.canJoinThroughEdit(at: .join(clip: clip, index: 1)) == false)
        let did14 = doc.joinThroughEdit(at: .join(clip: clip, index: 1))
        #expect(did14 == false)
    }

    // MARK: - Between two clips

    /// One recording laid down as two clips on V1 that read straight on: 0 to
    /// 4s of the file, then 4s to 10s, butted at 4s.
    static func twoClips() throws -> (doc: PhotonzDocument, first: UUID, second: UUID) {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let first = doc.layers[0].id
        doc.updateLayer(id: first) {
            $0.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 0, sourceLengthMS: 10_000)
        }
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        var clip = doc.layers[0]
        clip = Layer(name: "take", content: clip.content, frame: clip.frame)
        clip.movie = Self.take
        clip.time = LayerTime(inMS: 0, outMS: 6000, sourceInMS: 4000, sourceLengthMS: 10_000)
        clip.motions = nil
        let landing = doc.clipLanding(kind: .video, lengthMS: 6000, atMS: 4000,
                                      over: .onto(v1), edit: .overwrite)
        let landed = doc.land(clip, at: landing)
        let second = try #require(landed)
        #expect(doc.editPoints(onTrack: v1).map(\.atMS) == [4000])
        return (doc, first, second)
    }

    @Test("Two clips of one recording that run on are joined into the earlier one")
    func twoClipsJoin() throws {
        var (doc, first, second) = try Self.twoClips()
        doc.updateLayer(id: first) { $0.name = "intro" }
        doc.updateLayer(id: second) { $0.name = "rest" }
        let place = TimelineCutPlace.edit(outgoing: first, incoming: second)
        #expect(doc.canJoinThroughEdit(at: place))
        let did15 = doc.joinThroughEdit(at: place)
        #expect(did15)
        #expect(doc.layer(id: second) == nil)
        let joined = try #require(doc.layer(id: first))
        #expect(joined.name == "intro")
        #expect(joined.time?.inMS == 0)
        #expect(joined.time?.outMS == 10_000)
        #expect(joined.clipPieces?.count == 1)
        #expect(joined.clipPieces?.piece(at: 0)?.sourceOutMS == 10_000)
    }

    @Test("A held dip between two clips is taken off with the join, and its black goes with it")
    func heldDipBetweenClipsGoes() throws {
        var (doc, first, second) = try Self.twoClips()
        let place = TimelineCutPlace.edit(outgoing: first, incoming: second)
        let dip = ClipTransition(kind: .dipToBlack, lengthMS: 500, holdMS: 1000)
        let did16 = doc.setTransition(dip, at: place)
        #expect(did16)
        #expect(doc.layer(id: second)?.time?.inMS == 5000)
        #expect(doc.canJoinThroughEdit(at: place))
        let did17 = doc.joinThroughEdit(at: place)
        #expect(did17)
        let joined = try #require(doc.layer(id: first))
        #expect(joined.time?.outMS == 10_000)
    }

    @Test("Two clips of different recordings are not a through edit")
    func differentRecordingsRefuse() throws {
        var (doc, first, second) = try Self.twoClips()
        let other = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 10_000)
        doc.updateLayer(id: second) { $0.movie = other }
        #expect(doc.canJoinThroughEdit(at: .edit(outgoing: first, incoming: second)) == false)
    }

    static func uncut() -> PhotonzDocument {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let clip = doc.layers[0].id
        doc.updateLayer(id: clip) {
            $0.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0, sourceLengthMS: 10_000)
        }
        return doc
    }
}

@Suite("What the canvas says when a through edit is joined")
struct ThroughEditNoticeTests {
    @Test("The note names the transition the join took off")
    func namesTheTransition() {
        let note = CopyConfirmation(subject: .throughEditJoined(removed: .dipToBlack), shownAt: Date())
        #expect(note.title == "Joined")
        #expect(note.detail == "Dip to black taken off")
    }
}
