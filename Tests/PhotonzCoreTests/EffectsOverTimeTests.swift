import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// An effect changing over a shot is the motion machinery pointed at a
/// different property (`docs/design/video-transitions.md`).
///
/// **There is no second mechanism here, and that is the whole test.** The user
/// settled the animation model on 2026-09-15: a value recorded at a moment,
/// motion as a property of a layer, a lane per moving part, real easing. A blur
/// coming on over a second is a `LayerMotion` like any other, so it gets the
/// curve list, the lane on the strip, the From and To row, undo and the export
/// without one line written for it.
@Suite("The effects a layer already has can change over time")
struct EffectsOverTimeTests {

    static func movie() -> MovieRef {
        MovieRef(id: UUID(uuidString: "BBBBBBBB-2222-3333-4444-555555555555")!,
                 pixelSize: CGSize(width: 640, height: 480), durationMS: 8000)
    }

    /// A recording, six seconds of it, with a soft blur already on it.
    static func clip(blurRadius: CGFloat? = 8) -> Layer {
        var layer = Layer(name: "Recording",
                          content: .image(Self.movie().frameRef(atSourceMS: 0)),
                          frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        layer.movie = Self.movie()
        layer.time = LayerTime(inMS: 0, outMS: 6000, sourceInMS: 0, sourceLengthMS: 8000)
        if let blurRadius { layer.style.blurRadius = blurRadius }
        return layer
    }

    static func document(_ layer: Layer) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 640, height: 480),
                                       layers: [layer])
        document.durationMS = layer.time?.outMS
        return document
    }

    // MARK: - What is on offer

    @Test("A layer with a blur on it is offered its blur, with the number it is wearing")
    func aBlurIsOffered() throws {
        let offers = MotionProperty.offered(for: Self.clip())
        let blur = try #require(offers.first { $0.property == .blur })
        #expect(blur.current == .number(8))
        #expect(blur.reading == "8 pt")
    }

    @Test("A layer with no blur is not offered one, because there is no effect to change")
    func nothingIsOfferedWithoutTheEffect() {
        let offers = MotionProperty.offered(for: Self.clip(blurRadius: nil))
        #expect(!offers.contains { $0.property == .blur })
    }

    @Test("A fresh blur motion already does something: it comes on from nothing")
    func aFreshBlurMoves() {
        let motion = LayerMotion.starting(.blur, on: Self.clip())
        // A document finishes, so a motion added in one plays once and stays
        // where it landed. A blur that took itself back off again is not what
        // anybody meant (an icon, which repeats, still bounces).
        #expect(motion.repeats == .once)
        #expect(motion.property == .blur)
        #expect(motion.from != motion.to)
        // From clear to the blur the layer is wearing, which is the shot coming
        // out of focus over about a second.
        #expect(motion.from == .number(0))
        #expect(motion.to == .number(8))
    }

    @Test("An icon still bounces: only a layer with a stretch of time plays once")
    func anIconStillRepeats() {
        var mark = Layer(name: "Bell", content: .annotation(AnnotationContent(shape: .rectangle)),
                         frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        mark.style.blurRadius = 4
        #expect(LayerMotion.starting(.blur, on: mark).repeats == .foreverThereAndBack)
        mark.time = LayerTime(inMS: 0, outMS: 2000)
        #expect(LayerMotion.starting(.blur, on: mark).repeats == .once)
    }

    // MARK: - What it looks like as the document runs

    @Test("A blur that comes on over a second is clear at the start and there by the end")
    func aBlurComesOn() throws {
        var layer = Self.clip()
        layer.motions = [LayerMotion(property: .blur, from: .number(0), to: .number(12),
                                     timing: MotionTiming(startMS: 1000, durationMS: 1000),
                                     curve: .linear, repeats: .once)]
        let document = Self.document(layer)
        // Before it starts, the layer is as sharp as it was drawn.
        #expect(try #require(document.drawn(atTimeMS: 500).layers.first).style.blurRadius == 0)
        // Half way through, half way there.
        let half = try #require(document.drawn(atTimeMS: 1500).layers.first)
        #expect(abs(half.style.blurRadius - 6) < 0.2)
        // ...and it stays where it landed for the rest of the shot rather than
        // snapping back: the document finishes, it does not loop.
        #expect(try #require(document.drawn(atTimeMS: 2000).layers.first).style.blurRadius == 12)
        #expect(try #require(document.drawn(atTimeMS: 5500).layers.first).style.blurRadius == 12)
    }

    @Test("Nothing about the layer itself changes: the blur is worked out at the moment it is drawn")
    func nothingIsBakedIn() throws {
        var layer = Self.clip()
        layer.motions = [LayerMotion(property: .blur, from: .number(0), to: .number(12),
                                     timing: MotionTiming(startMS: 0, durationMS: 1000),
                                     curve: .linear, repeats: .once)]
        let document = Self.document(layer)
        _ = document.drawn(atTimeMS: 900)
        #expect(document.layers.first?.style.blurRadius == 8)
    }

    @Test("A colour that shifts across a shot is the same machinery on a layer that paints one")
    func aColourShifts() throws {
        var title = Layer(name: "Title",
                          content: .text(TextContent(string: "Photonz", colorHex: "#FF0000")),
                          frame: CGRect(x: 40, y: 40, width: 300, height: 60))
        title.time = LayerTime(inMS: 0, outMS: 6000)
        title.motions = [LayerMotion(property: .color, from: .color("#FF0000"),
                                     to: .color("#0000FF"),
                                     timing: MotionTiming(startMS: 0, durationMS: 4000),
                                     curve: .linear, repeats: .once)]
        let document = Self.document(title)
        #expect(try #require(document.drawn(atTimeMS: 0).layers.first).text?.colorHex == "#FF0000")
        let middle = try #require(document.drawn(atTimeMS: 2000).layers.first).text?.colorHex
        #expect(middle != "#FF0000")
        #expect(middle != "#0000FF")
        #expect(try #require(document.drawn(atTimeMS: 4000).layers.first).text?.colorHex == "#0000FF")
    }

    @Test("It rides on the strip like every other moving part, with its own lane")
    func itGetsALane() throws {
        var layer = Self.clip()
        layer.motions = [LayerMotion(property: .blur, from: .number(0), to: .number(12),
                                     timing: MotionTiming(startMS: 1000, durationMS: 1000),
                                     curve: .easeInOut)]
        let strip = Self.document(layer).motionStrip()
        let group = try #require(strip.first)
        // One row for the clip, with its bar, and one lane under it for the
        // blur: exactly what a layer that moves and occupies time looks like.
        #expect(group.bar != nil)
        #expect(group.lanes.count == 1)
        #expect(group.lanes.first?.title == "Blur")
    }

    @Test("What an export photographs carries the blur, because it is the same picture")
    func theExportHasItToo() throws {
        var layer = Self.clip()
        layer.motions = [LayerMotion(property: .blur, from: .number(0), to: .number(12),
                                     timing: MotionTiming(startMS: 0, durationMS: 1000),
                                     curve: .linear, repeats: .once)]
        let document = Self.document(layer)
        // A document with something changing over time is never the untouched
        // recording, so an export cannot take the copy-the-file shortcut.
        #expect(document.untouchedRecording == nil)
        #expect(try #require(document.drawn(atTimeMS: 1000).layers.first).style.blurRadius == 12)
    }
}
