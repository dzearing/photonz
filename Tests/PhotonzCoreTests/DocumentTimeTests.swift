import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Time in the document: a duration on the picture, and an in and an out on a
/// layer (`docs/design/video-surface.md` §2).
///
/// Written before the model, which is the rule for `PhotonzCore`. Everything a
/// timeline will ever need to decide is settled here, in a module that has
/// never heard of a player: how long the document is, which layers are on
/// screen at a moment, what one of them looks like there, and how a recording
/// already cut into pieces arrives in the same shape.
///
/// The one rule the whole file is really about: **a document with no time
/// behaves exactly as it does today.** Nearly a third of these tests are that
/// sentence in different words, because it is what makes this safe to land
/// while nothing in the app makes a document with time yet.
@Suite("Time in the document")
struct DocumentTimeTests {

    // MARK: - Fixtures

    static func shape(_ name: String) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
              frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    }

    /// Three clips back to back, the way a recording cut twice arrives.
    static func threePieces() -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        var first = shape("Piece 1")
        first.time = LayerTime(inMS: 0, outMS: 2000)
        var second = shape("Piece 2")
        second.time = LayerTime(inMS: 2000, outMS: 3500)
        var third = shape("Piece 3")
        third.time = LayerTime(inMS: 3500, outMS: 5000)
        doc.layers = [first, second, third]
        return doc
    }

    // MARK: - A layer's in and out

    @Test func aLayerCarriesAPointItStartsAndAPointItEnds() {
        let time = LayerTime(inMS: 250, outMS: 1750)
        #expect(time.inMS == 250)
        #expect(time.outMS == 1750)
        #expect(time.lengthMS == 1500)
    }

    @Test func aStretchIsNeverShorterThanSomethingYouCouldGrab() {
        // An out on top of the in is a bar of no width, which is a bar nobody
        // can ever take hold of again.
        let squashed = LayerTime(inMS: 400, outMS: 400)
        #expect(squashed.lengthMS == LayerTime.shortestMS)
        let inverted = LayerTime(inMS: 400, outMS: 100)
        #expect(inverted.inMS == 400)
        #expect(inverted.lengthMS == LayerTime.shortestMS)
    }

    @Test func aStretchNeverStartsBeforeTheDocumentDoes() {
        let time = LayerTime(inMS: -500, outMS: 1000)
        #expect(time.inMS == 0)
        #expect(time.outMS == 1000)
    }

    @Test func aStretchHoldsTheMomentsInsideItAndNotItsOwnOut() {
        let time = LayerTime(inMS: 1000, outMS: 2000)
        #expect(!time.contains(ms: 999))
        #expect(time.contains(ms: 1000))
        #expect(time.contains(ms: 1999))
        // Half open, so two clips meeting at 2000 never both draw there.
        #expect(!time.contains(ms: 2000))
    }

    @Test func aTrimmedStretchSaysHowMuchIsSpareEitherSideOfIt() {
        // Four seconds of source, of which the second and third are kept.
        let time = LayerTime(inMS: 0, outMS: 2000, sourceInMS: 1000, sourceLengthMS: 4000)
        #expect(time.spareBeforeMS == 1000)
        #expect(time.spareAfterMS == 1000)
    }

    @Test func aStretchWithNoSourceBehindItHasNothingSpare() {
        let time = LayerTime(inMS: 0, outMS: 2000)
        #expect(time.spareBeforeMS == 0)
        #expect(time.spareAfterMS == 0)
    }

    @Test func movingAStretchKeepsItsLengthAndItsPlaceInItsSource() {
        let time = LayerTime(inMS: 0, outMS: 2000, sourceInMS: 1000, sourceLengthMS: 4000)
        let moved = time.moved(toInMS: 3000)
        #expect(moved.inMS == 3000)
        #expect(moved.outMS == 5000)
        #expect(moved.sourceInMS == 1000)
    }

    // MARK: - The document's duration

    @Test func aDocumentCanCarryADuration() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.durationMS = 5000
        #expect(doc.hasTime)
        #expect(doc.documentDurationMS == 5000)
    }

    @Test func aDocumentWithNothingWrittenDownIsAsLongAsItsLastLayerLeaves() {
        let doc = Self.threePieces()
        #expect(doc.durationMS == nil)
        #expect(doc.hasTime)
        #expect(doc.documentDurationMS == 5000)
    }

    @Test func aDocumentWithNoTimeInItHasNone() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [Self.shape("Box")]
        #expect(!doc.hasTime)
        #expect(doc.documentDurationMS == 0)
    }

    @Test func aDurationWrittenDownBeatsWhatTheLayersAddUpTo() {
        // A recording with a held tail: the picture runs on after the last
        // clip, which is a thing a duration you can write down can say and a
        // duration read off the layers never can.
        var doc = Self.threePieces()
        doc.durationMS = 8000
        #expect(doc.documentDurationMS == 8000)
    }

    @Test func aDurationOfNothingIsNoDuration() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.durationMS = 0
        #expect(doc.durationMS == nil)
        #expect(!doc.hasTime)
    }

    @Test func timeInsideAGroupCountsTowardsTheDocumentsLength() {
        var child = Self.shape("Inside")
        child.time = LayerTime(inMS: 0, outMS: 3000)
        let group = Layer(name: "Group", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [group]
        #expect(doc.hasTime)
        #expect(doc.documentDurationMS == 3000)
    }

    // MARK: - One ruler or the other

    @Test func aDocumentWithTimeIsMeasuredByItsDurationAndNotByItsLap() {
        var doc = Self.threePieces()
        doc.motionCycleMS = 900
        #expect(doc.timelineLengthMS == 5000)
    }

    @Test func aDocumentWithoutTimeIsStillMeasuredByItsLap() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        var bell = Self.shape("Bell")
        bell.motions = [LayerMotion(property: .rotation, from: .number(-12), to: .number(12),
                                    timing: MotionTiming(startMS: 0, durationMS: 900))]
        doc.layers = [bell]
        #expect(!doc.hasTime)
        #expect(doc.timelineLengthMS == 900)
    }

    // MARK: - The picture at a moment

    @Test func onlyTheLayersWhoseStretchHoldsTheMomentAreOnScreen() {
        let doc = Self.threePieces()
        #expect(doc.drawn(atTimeMS: 0).allLayers.filter(\.isVisible).map(\.name) == ["Piece 1"])
        #expect(doc.drawn(atTimeMS: 2500).allLayers.filter(\.isVisible).map(\.name) == ["Piece 2"])
        #expect(doc.drawn(atTimeMS: 4999).allLayers.filter(\.isVisible).map(\.name) == ["Piece 3"])
    }

    @Test func theLastMomentOfTheDocumentStillDrawsSomething() {
        // Asking for the frame AT the duration is asking for one past the last
        // one there is. It comes back as the last frame rather than as an empty
        // picture, because an empty last frame reads as the video having broken.
        let doc = Self.threePieces()
        #expect(doc.drawn(atTimeMS: 5000).allLayers.filter(\.isVisible).map(\.name) == ["Piece 3"])
        #expect(doc.drawn(atTimeMS: 99_000).allLayers.filter(\.isVisible).map(\.name) == ["Piece 3"])
    }

    @Test func aMomentBeforeTheStartIsTheStart() {
        let doc = Self.threePieces()
        #expect(doc.drawn(atTimeMS: -400).allLayers.filter(\.isVisible).map(\.name) == ["Piece 1"])
    }

    @Test func aLayerWithNoStretchIsOnScreenTheWholeTime() {
        // A background, an adjustment, a frame: `video-surface.md` §3, the case
        // that makes deleting the layers list impossible.
        var doc = Self.threePieces()
        doc.layers.insert(Self.shape("Background"), at: 0)
        for ms in [0, 2500, 4999] {
            #expect(doc.drawn(atTimeMS: ms).allLayers.filter(\.isVisible).map(\.name).contains("Background"))
        }
    }

    @Test func aLayerHiddenByHandStaysHiddenInsideItsOwnStretch() {
        var doc = Self.threePieces()
        doc.layers[0].isVisible = false
        #expect(doc.drawn(atTimeMS: 0).allLayers.filter(\.isVisible).isEmpty)
    }

    @Test func theDocumentItselfIsNeverTouchedByBeingDrawn() {
        let doc = Self.threePieces()
        _ = doc.drawn(atTimeMS: 4000)
        #expect(doc.allLayers.filter(\.isVisible).count == doc.allLayers.count)
    }

    @Test func aStretchInsideAGroupIsFoundAndHidden() {
        var early = Self.shape("Early")
        early.time = LayerTime(inMS: 0, outMS: 1000)
        var late = Self.shape("Late")
        late.time = LayerTime(inMS: 1000, outMS: 2000)
        let group = Layer(name: "Group",
                          content: .group(GroupContent(children: [early, late])),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [group]
        let at500 = doc.drawn(atTimeMS: 500).allLayers.filter(\.isVisible).map(\.name)
        #expect(at500 == ["Group", "Early"])
    }

    @Test func aMovingLayerInATimedDocumentIsSampledOnTheDocumentsOwnClock() {
        // A one second fade inside a four second document. Three seconds in it
        // has faded up and stayed there. On the icon's clock the lap would be
        // as long as the fade, so three seconds in would be the top of the
        // fourth lap and the layer would be invisible again — which is what a
        // video sampled on a looping ruler looks like, and why the two clocks
        // are kept apart.
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        var title = Self.shape("Title")
        title.time = LayerTime(inMS: 0, outMS: 4000)
        title.motions = [LayerMotion(property: .opacity, from: .number(0), to: .number(100),
                                     timing: MotionTiming(startMS: 0, durationMS: 1000),
                                     repeats: .forever)]
        doc.layers = [title]
        doc.durationMS = 4000
        #expect(doc.automaticMotionCycleLengthMS == 1000)

        let late = doc.drawn(atTimeMS: 3000).allLayers.first { $0.name == "Title" }
        #expect(late?.style.opacity == 1)

        let halfway = doc.drawn(atTimeMS: 500).allLayers.first { $0.name == "Title" }
        #expect((halfway?.style.opacity ?? 0) > 0.4)
        #expect((halfway?.style.opacity ?? 1) < 0.6)
    }

    @Test func aDocumentWithNoTimeDrawsExactlyWhatItAlwaysDrew() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        var bell = Self.shape("Bell")
        bell.motions = [LayerMotion(property: .rotation, from: .number(-12), to: .number(12),
                                    timing: MotionTiming(startMS: 0, durationMS: 900))]
        doc.layers = [bell]
        for ms in [0, 450, 900] {
            #expect(doc.drawn(atTimeMS: ms) == doc.moved(toMotionTimeMS: ms))
        }
    }

    @Test func aStillDocumentComesBackUntouched() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [Self.shape("Box")]
        #expect(doc.drawn(atTimeMS: 1234) == doc)
    }

    // MARK: - Saving and opening

    @Test func aDocumentWithNoTimeSavesByteForByteWhatItAlwaysSaved() throws {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [Self.shape("Box")]
        let json = try String(decoding: JSONEncoder().encode(doc), as: UTF8.self)
        #expect(!json.contains("durationMS"))
        #expect(!json.contains("\"time\""))
    }

    @Test func aDocumentWithTimeOpensWithItsTimeIntact() throws {
        var doc = Self.threePieces()
        doc.durationMS = 5000
        doc.layers[1].time = LayerTime(inMS: 2000, outMS: 3500,
                                       sourceInMS: 1200, sourceLengthMS: 9000)
        let reopened = try JSONDecoder().decode(PhotonzDocument.self,
                                                from: JSONEncoder().encode(doc))
        #expect(reopened.durationMS == 5000)
        #expect(reopened.layers.map(\.time) == doc.layers.map(\.time))
        #expect(reopened.layers[1].time?.sourceInMS == 1200)
        #expect(reopened.layers[1].time?.sourceLengthMS == 9000)
    }

    @Test func aCopyOfALayerOccupiesTheSameStretch() {
        var piece = Self.shape("Piece 1")
        piece.time = LayerTime(inMS: 500, outMS: 2500, sourceInMS: 100)
        #expect(piece.duplicated().time == piece.time)
        #expect(piece.reidentified().time == piece.time)
    }

    // MARK: - A recording arriving as time

    @Test func anUncutRecordingIsOneStretchAsLongAsTheRecording() {
        let cuts = VideoCutList(duration: 12.5)
        #expect(cuts.documentDurationMS == 12_500)
        let times = cuts.layerTimes()
        #expect(times.count == 1)
        #expect(times[0].inMS == 0)
        #expect(times[0].outMS == 12_500)
        #expect(times[0].sourceInMS == 0)
        #expect(times[0].sourceLengthMS == 12_500)
    }

    @Test func aCutRecordingIsOneStretchPerPieceBackToBack() {
        // Ten seconds with the middle two dropped: two pieces, and the second
        // one starts on the timeline where the first one left off, not where it
        // sits in the file.
        let cuts = VideoCutList(pieces: [VideoPiece(start: 0, end: 4),
                                         VideoPiece(start: 6, end: 10)],
                                sourceDuration: 10)
        let times = cuts.layerTimes()
        #expect(times.map(\.inMS) == [0, 4000])
        #expect(times.map(\.outMS) == [4000, 8000])
        #expect(times.map(\.sourceInMS) == [0, 6000])
        #expect(cuts.documentDurationMS == 8000)
    }

    @Test func everyPieceRemembersWhereInTheFileItCameFrom() {
        // The round trip, which is what makes this a projection and not a lie:
        // from the stretches alone, every piece's place in the source file
        // comes back exactly.
        let cuts = VideoCutList(pieces: [VideoPiece(start: 1.25, end: 3.5),
                                         VideoPiece(start: 7, end: 9.75)],
                                sourceDuration: 12)
        for (time, piece) in zip(cuts.layerTimes(), cuts.pieces) {
            #expect(time.sourceInMS == Int((piece.start * 1000).rounded()))
            #expect(time.sourceInMS + time.lengthMS == Int((piece.end * 1000).rounded()))
            #expect(time.sourceLengthMS == 12_000)
        }
    }

    @Test func aRecordingLaidIntoADocumentIsADocumentWithTime() {
        let cuts = VideoCutList(pieces: [VideoPiece(start: 0, end: 4),
                                         VideoPiece(start: 6, end: 10)],
                                sourceDuration: 10)
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = cuts.layerTimes().enumerated().map { index, time in
            var layer = Self.shape("Piece \(index + 1)")
            layer.time = time
            return layer
        }
        doc.durationMS = cuts.documentDurationMS
        #expect(doc.hasTime)
        #expect(doc.documentDurationMS == 8000)
        #expect(doc.drawn(atTimeMS: 5000).allLayers.filter(\.isVisible).map(\.name) == ["Piece 2"])
    }
}
