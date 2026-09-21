import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The one place the shipped strip has to grow for video
/// (`docs/design/video-surface.md` §2): **a layer row draws a bar when the
/// layer has an in and an out, and a bare heading when it does not.**
///
/// One rule, both jobs. A bell that rotates does not occupy time — the
/// properties on it do — so its row stays the labelled hairline it has always
/// been. A clip IS a start and an end, so its row gets a bar. Written before
/// the change, which is the rule for `PhotonzCore`.
@Suite("A layer row that occupies time")
struct MotionStripBarTests {

    static func shape(_ name: String) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
              frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    }

    static func rotation(start: Int, over: Int) -> LayerMotion {
        LayerMotion(property: .rotation, from: .number(-12), to: .number(12),
                    timing: MotionTiming(startMS: start, durationMS: over))
    }

    // MARK: - Heading or bar

    @Test func aLayerThatOnlyMovesIsStillAHeading() {
        var bell = Self.shape("Bell body")
        bell.motions = [Self.rotation(start: 0, over: 900)]
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [bell]
        let groups = doc.motionStrip()
        #expect(groups.count == 1)
        #expect(groups[0].bar == nil)
        #expect(groups[0].lanes.count == 1)
    }

    @Test func aLayerWithAnInAndAnOutGetsABar() {
        var clip = Self.shape("Piece 1")
        clip.time = LayerTime(inMS: 0, outMS: 2000)
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [clip]
        let groups = doc.motionStrip()
        #expect(groups.count == 1)
        #expect(groups[0].bar == LayerTime(inMS: 0, outMS: 2000))
        // Nothing on it moves, so it has a bar and no lanes at all.
        #expect(groups[0].lanes.isEmpty)
    }

    @Test func aClipThatAlsoMovesHasABarAndLanesUnderIt() {
        var clip = Self.shape("Piece 1")
        clip.time = LayerTime(inMS: 500, outMS: 2500)
        clip.motions = [Self.rotation(start: 0, over: 400)]
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [clip]
        let groups = doc.motionStrip()
        #expect(groups[0].bar?.inMS == 500)
        #expect(groups[0].lanes.count == 1)
    }

    @Test func aLayerWithNeitherIsNotOnTheStripAtAll() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [Self.shape("Background")]
        #expect(doc.motionStrip().isEmpty)
    }

    /// Topmost first, which is how the layers panel reads and how the stack
    /// composites (`LayerCompositing.swift`).
    @Test func clipsAreListedTheWayTheLayersPanelListsThem() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = (1...3).map { index in
            var clip = Self.shape("Piece \(index)")
            clip.time = LayerTime(inMS: (index - 1) * 1000, outMS: index * 1000)
            return clip
        }
        #expect(doc.motionStrip().map(\.layerName) == ["Piece 3", "Piece 2", "Piece 1"])
    }

    // MARK: - What a drag can catch on

    @Test func theEndsOfAClipAreSomethingAnotherBarCanLineUpWith() {
        var clip = Self.shape("Piece 1")
        clip.time = LayerTime(inMS: 0, outMS: 2000)
        var bell = Self.shape("Bell body")
        bell.motions = [Self.rotation(start: 0, over: 900)]
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [clip, bell]
        let edges = doc.motionStripEdges(excluding: UUID())
        #expect(edges.contains { $0.ms == 2000 && $0.name == "Piece 1" && !$0.isStart })
        #expect(edges.contains { $0.ms == 0 && $0.name == "Piece 1" && $0.isStart })
    }

    @Test func aBarsOwnEndsAreNotSomethingItCanCatchOn() {
        var bell = Self.shape("Bell body")
        let motion = Self.rotation(start: 100, over: 900)
        bell.motions = [motion]
        bell.time = LayerTime(inMS: 0, outMS: 2000)
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [bell]
        let edges = doc.motionStripEdges(excluding: motion.id)
        #expect(!edges.contains { $0.ms == 100 })
        // The layer's own stretch is a different bar, so its ends stay.
        #expect(edges.contains { $0.ms == 2000 })
    }

    // MARK: - The ruler a document with a last frame gets

    @Test func aLapLeavesRoomToOverrunIntoAndADocumentDoesNot() {
        let lap = MotionStripRuler(cycleMS: 900)
        #expect(lap.spanMS > lap.cycleMS)
        #expect(lap.repeats)

        let document = MotionStripRuler(documentMS: 5000)
        #expect(document.spanMS == 5000)
        #expect(document.cycleMS == 5000)
        #expect(!document.repeats)
    }

    @Test func theLastFrameOfADocumentIsTheRightHandEdge() {
        let ruler = MotionStripRuler(documentMS: 5000)
        #expect(ruler.fraction(ofMS: 5000) == 1)
        #expect(ruler.fraction(ofMS: 2500) == 0.5)
        #expect(ruler.ms(atFraction: 1) == 5000)
    }

    @Test func aDocumentRulerStillWritesRoundNumbersAlongItsTop() {
        let ticks = MotionStripRuler(documentMS: 5000).ticks
        #expect(ticks.count >= 4)
        #expect(ticks.count <= 9)
        #expect(ticks.first?.ms == 0)
        #expect(ticks.allSatisfy { $0.ms <= 5000 })
    }

    @Test func aRulerForNoTimeAtAllIsStillAUsableRuler() {
        let ruler = MotionStripRuler(documentMS: 0)
        #expect(ruler.spanMS >= 1)
        #expect(ruler.fraction(ofMS: 0) == 0)
    }

    // MARK: - One arithmetic, two strips

    @Test func theRecordingStripAndADocumentsRulerLandOnTheSamePixel() {
        // The recording window's strip used to divide seconds by seconds on its
        // own. It measures through the document ruler now, and this is the
        // proof that re-pointing it moved nothing: for every piece, the place
        // the ruler puts it is the place the cut list always put it.
        let cuts = VideoCutList(pieces: [VideoPiece(start: 0, end: 4),
                                         VideoPiece(start: 6, end: 9.5)],
                                sourceDuration: 12)
        let ruler = MotionStripRuler(documentMS: cuts.documentDurationMS)
        for (index, time) in cuts.layerTimes().enumerated() {
            guard let range = cuts.timelineRange(ofPiece: index) else {
                Issue.record("piece \(index) has no range")
                continue
            }
            let was = range.start / cuts.timelineDuration
            let now = ruler.fraction(ofMS: Double(time.inMS))
            #expect(abs(was - now) < 1e-9)
            let wasWidth = (range.end - range.start) / cuts.timelineDuration
            #expect(abs(wasWidth - ruler.fraction(ofMS: Double(time.lengthMS))) < 1e-9)
        }
    }

    // MARK: - The strip's own summary row

    @Test func theRowAStripLeavesBehindCountsClipsAsMoving() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        var clip = Self.shape("Piece 1")
        clip.time = LayerTime(inMS: 0, outMS: 2000)
        doc.layers = [clip]
        let text = MotionStripSummary.text(groups: doc.motionStrip(),
                                           selectedLayerID: clip.id, cycleMS: 2000)
        // No empty middle segment: the clip has nothing moving on it, so the
        // row says the layer and the length and stops.
        #expect(text == "Piece 1 · 2000 ms")
    }
}


/// The numbers along the top of a DOCUMENT's ruler (`docs/design/video.md`).
///
/// A lap is measured in milliseconds because ninety of them is the whole point
/// of a lag. A recording is measured in minutes and seconds because that is how
/// long a recording is and how everything that has ever played one says so.
@Suite("A document's ruler reads in minutes and seconds")
struct DocumentRulerTests {

    @Test("A recording's ruler is timecode, not milliseconds")
    func documentTicksAreTimecode() {
        let ruler = MotionStripRuler(documentMS: 8000)
        let labels = ruler.ticks.map(\.label)
        #expect(labels.first == "0:00")
        #expect(labels.contains("0:02"))
        #expect(labels.allSatisfy { $0.contains(":") })
        #expect(!labels.contains { $0.contains("ms") })
    }

    @Test("A lap's ruler is untouched: still milliseconds, still a unit on the last one")
    func cycleTicksAreUnchanged() {
        let ruler = MotionStripRuler(cycleMS: 1200)
        let labels = ruler.ticks.map(\.label)
        #expect(labels.first == "0")
        #expect(labels.last?.hasSuffix(" ms") == true)
    }

    @Test("A long recording says hours when it has them")
    func hoursWhenThereAreHours() {
        let ruler = MotionStripRuler(documentMS: 2 * 60 * 60 * 1000)
        #expect(ruler.ticks.contains { $0.label.filter { $0 == ":" }.count == 2 })
    }
}
