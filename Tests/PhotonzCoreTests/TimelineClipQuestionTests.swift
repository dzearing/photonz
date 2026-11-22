import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Asking whether any clip on the timeline is of some kind answers what
/// `timelineClipLayers.contains` answers, without copying every clip out of the
/// document to ask it: the panel asked it on every pass of a pick, and on the 6
/// minute reference edit each ask copied a few hundred clips
/// (`a-long-edit-with-transitions-plays-scrubs-and-ed`, pass 28).
@Suite("Asking about the timeline's clips")
struct TimelineClipQuestionTests {

    static func shape(_ name: String, time: LayerTime?) -> Layer {
        var layer = Layer(name: name,
                          content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FF3B30")),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        layer.time = time
        return layer
    }

    @Test func itAnswersWhatTheListOfClipsAnswers() {
        var doc = PhotonzDocument.recording(HeldFrameTests.movie(), name: "Take 1")
        doc.layers.append(Self.shape("Box", time: LayerTime(inMS: 0, outMS: 1000)))
        #expect(doc.hasTimelineClip { $0.movie != nil })
        #expect(doc.hasTimelineClip { $0.movie != nil } == doc.timelineClipLayers.contains { $0.movie != nil })
        #expect(doc.hasTimelineClip { $0.name == "Box" })
        #expect(!doc.hasTimelineClip { $0.name == "Nothing by that name" })
    }

    @Test func aLayerOffTheTimelineIsNotAClip() {
        var doc = PhotonzDocument.recording(HeldFrameTests.movie(), name: "Take 1")
        doc.layers.append(Self.shape("Still", time: nil))
        #expect(doc.timelineClipLayers.contains { $0.name == "Still" } == false)
        #expect(!doc.hasTimelineClip { $0.name == "Still" })
    }

    @Test func aDocumentWithoutTimeHasNoClips() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        doc.layers = [Self.shape("Box", time: LayerTime(inMS: 0, outMS: 1000))]
        #expect(doc.timelineClipLayers.isEmpty == !doc.hasTimelineClip { _ in true })
    }
}
