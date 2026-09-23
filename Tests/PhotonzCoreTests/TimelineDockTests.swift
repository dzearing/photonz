import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **The timeline dock** under a document with time (`TimelineTrack.swift`,
/// `docs/design/mocks/pages/video.html`).
///
/// Two things the dock decides that a window never has to: what KIND of track
/// each row is, which picks its icon and its clip colour, and the numbers along
/// its ruler, which the mock writes in plain seconds ("0s 3s 6s").
///
/// Written before the dock, which is the rule for `PhotonzCore`.
@Suite("The timeline dock")
struct TimelineDockTests {

    static let movie = MovieRef(pixelSize: CGSize(width: 100, height: 100),
                                durationMS: 5000, hasSound: true)

    // MARK: - What kind of track a row is

    @Test("A recording is a video track")
    func aRecordingIsAVideoTrack() {
        let doc = PhotonzDocument.recording(Self.movie, name: "take")
        #expect(doc.layers[0].timelineTrackKind == .video)
        #expect(doc.motionStrip().first?.trackKind == .video)
    }

    @Test("A sound is an audio track, and so is a recording's detached sound")
    func soundIsAnAudioTrack() throws {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        let id = doc.addSound(SoundRef(durationMS: 3000), name: "music", atMS: 0)
        #expect(doc.layer(id: id)?.timelineTrackKind == .audio)
        let split = try #require(doc.detachingSound(ofLayer: doc.layers[0].id))
        #expect(split.document.layer(id: split.soundLayerID)?.timelineTrackKind == .audio)
    }

    @Test("Words are a text track")
    func wordsAreAText() {
        let layer = Layer(name: "Title", content: .text(TextContent(string: "Hello")),
                          frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        #expect(layer.timelineTrackKind == .text)
    }

    @Test("A placed component is a component track, whatever it draws")
    func anInstanceIsAComponent() {
        let words = Layer(name: "Name", content: .text(TextContent(string: "Name")),
                          frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        let layer = Layer(name: "Lower third",
                          content: .group(GroupContent(children: [words], instanceOf: UUID())),
                          frame: CGRect(x: 0, y: 0, width: 80, height: 20))
        #expect(layer.timelineTrackKind == .component)
    }

    @Test("Anything else drawn over the picture is an overlay")
    func aShapeIsAnOverlay() {
        let layer = Layer(name: "Box",
                          content: .annotation(AnnotationContent(shape: .rectangle)),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        #expect(layer.timelineTrackKind == .overlay)
    }

    // MARK: - The ruler, in seconds

    @Test("Fifteen seconds reads 0s 3s 6s 9s 12s 15s, the mock's own ruler")
    func fifteenSecondsReadsLikeTheMock() {
        let ruler = MotionStripRuler(documentMS: 15_000)
        #expect(ruler.secondTicks.map(\.label) == ["0s", "3s", "6s", "9s", "12s", "15s"])
        #expect(ruler.secondTicks.map(\.ms) == [0, 3000, 6000, 9000, 12_000, 15_000])
    }

    @Test("Eight seconds steps in twos")
    func eightSecondsStepsInTwos() {
        let ruler = MotionStripRuler(documentMS: 8000)
        #expect(ruler.secondTicks.map(\.label) == ["0s", "2s", "4s", "6s", "8s"])
    }

    @Test("Opened right out, the ruler reads in tenths")
    func openedOutReadsTenths() {
        let ruler = MotionStripRuler(documentMS: 8000,
                                     zoom: TimelineZoom(scale: 8, startMS: 2000))
        let labels = ruler.secondTicks.map(\.label)
        #expect(labels.first == "2s")
        #expect(labels.contains { $0.contains(".") })
        #expect(labels.allSatisfy { $0.hasSuffix("s") })
    }

    @Test("Past a minute the ruler reads minutes and seconds")
    func pastAMinuteReadsTimecode() {
        let ruler = MotionStripRuler(documentMS: 5 * 60_000)
        let labels = ruler.secondTicks.map(\.label)
        #expect(labels.first == "0:00")
        #expect(labels.contains("1:00"))
        #expect(labels.count >= 4 && labels.count <= 9)
    }

    @Test("Every ruler has between four and nine numbers")
    func tickCountStaysReadable() {
        for ms in [1500, 4000, 8000, 15_000, 42_000, 90_000, 600_000, 3_600_000] {
            let count = MotionStripRuler(documentMS: ms).secondTicks.count
            #expect(count >= 4 && count <= 9, "\(ms) ms gave \(count) ticks")
        }
    }
}
