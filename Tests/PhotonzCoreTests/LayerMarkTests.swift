import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The small mark in front of a layer's name on the timing strip, saying what
/// kind of layer it is: a path, a circle, words, a picture.
///
/// Written before the mark, which is the rule for `PhotonzCore`.
@Suite("A layer's kind mark")
struct LayerMarkTests {

    static let box = CGRect(x: 0, y: 0, width: 40, height: 40)

    static func shape(_ shape: AnnotationShape) -> Layer {
        Layer(name: "Shape", content: .annotation(AnnotationContent(shape: shape)), frame: box)
    }

    @Test("A path is a path, the way the bell's body is drawn in the mock")
    func aPathIsAPath() {
        let layer = Layer(name: "Bell body",
                          content: .path(PathContent(anchors: [PathAnchor(point: .zero),
                                                               PathAnchor(point: CGPoint(x: 10, y: 10))])),
                          frame: Self.box)
        #expect(layer.mark == .path)
    }

    @Test("Each drawn shape is marked as the shape it is, never as one family")
    func eachShapeIsItsOwnMark() {
        #expect(Self.shape(.ellipse).mark == .ellipse)
        #expect(Self.shape(.rectangle).mark == .rectangle)
        #expect(Self.shape(.arrow).mark == .arrow)
        #expect(Self.shape(.line).mark == .line)
        #expect(Self.shape(.highlight).mark == .highlight)
    }

    @Test("Words, a picture and a sound each have their own mark")
    func wordsPictureSound() {
        let words = Layer(name: "Title", content: .text(TextContent(string: "Hello")), frame: Self.box)
        let picture = Layer(name: "Shot", content: .image(ImageRef(pixelSize: Self.box.size)), frame: Self.box)
        #expect(words.mark == .text)
        #expect(picture.mark == .picture)
        var doc = PhotonzDocument.recording(TimelineDockTests.movie, name: "take")
        let id = doc.addSound(SoundRef(durationMS: 3000), name: "music", atMS: 0)
        #expect(doc.layer(id: id)?.mark == .sound)
    }

    @Test("A recording is a video, though it is a picture that also carries sound")
    func aRecordingIsAVideo() {
        let doc = PhotonzDocument.recording(TimelineDockTests.movie, name: "take")
        #expect(doc.layers[0].mark == .video)
    }

    @Test("A placed component is a component, whatever it draws inside")
    func anInstanceIsAComponent() {
        let words = Layer(name: "Name", content: .text(TextContent(string: "Name")), frame: Self.box)
        let layer = Layer(name: "Lower third",
                          content: .group(GroupContent(children: [words], instanceOf: UUID())),
                          frame: Self.box)
        #expect(layer.mark == .component)
    }

    @Test("A group is a group, and a frame is a frame")
    func groupsAndFrames() {
        let a = Self.shape(.rectangle)
        let group = Layer(name: "Group", content: .group(GroupContent(children: [a])), frame: Self.box)
        let frame = Layer(name: "Frame", content: .group(GroupContent(children: [a], isFrame: true)),
                          frame: Self.box)
        #expect(group.mark == .group)
        #expect(frame.mark == .frame)
    }

    @Test("The timing strip's heading carries the layer's mark")
    func theStripCarriesTheMark() throws {
        var knob = Self.shape(.ellipse)
        knob.motions = [MotionStripTests.rotation(start: 0, over: 900)]
        let doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [knob])
        let group = try #require(doc.motionStrip().first)
        #expect(group.mark == .ellipse)
    }
}
