import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Move a layer from A to B, grow it, shrink it, fade it
/// (task `move-a-layer-from-a-to-b-grow-it-shrink-it-fade`).
///
/// Written before the model. Keys already exist (`PropertyKeys.swift`); this is
/// the timeline's half of them: a diamond on the layer's clip for every moment
/// something is keyed, which a hand drags in time, right-clicks to ease the way
/// Premiere eases a key, and deletes. Plus the title presets, which write
/// ordinary keys.
@Suite("Keys on a clip")
struct ClipKeyMarksTests {

    // MARK: - Fixtures

    /// Ten seconds, with a title on screen from 2s to 8s.
    static func withTitle() -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var title = Layer(name: "Hello",
                          content: .text(TextContent(string: "Hello", fontSize: 48)),
                          frame: CGRect(x: 100, y: 100, width: 400, height: 80))
        title.time = LayerTime(inMS: 2000, outMS: 8000)
        doc.layers = [title]
        doc.durationMS = 10_000
        return (doc, title.id)
    }

    static func number(_ value: MotionValue?) -> Double? {
        if case let .number(number) = value { return number }
        return nil
    }

    static func point(_ value: MotionValue?) -> CGPoint? {
        if case let .point(point) = value { return point }
        return nil
    }

    /// Scale keyed 100 at 3s and 200 at 6s, and position keyed at 3s.
    static func keyed() -> (PhotonzDocument, UUID) {
        var (doc, id) = withTitle()
        doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(200), layerID: id, .motion(.scale), atDocumentTimeMS: 6000)
        doc.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 3000)
        return (doc, id)
    }

    // MARK: - Per-key ease on a motion

    @Test func aMotionNobodyHasEasedPlaysAsItAlwaysDid() {
        let motion = LayerMotion(property: .opacity, from: .number(0), to: .number(100),
                                 timing: MotionTiming(startMS: 0, durationMS: 1000),
                                 curve: .easeInOut, repeats: .once)
        #expect(motion.keys.allSatisfy { $0.ease == nil })
        let expected = EasingCurve.easeInOut.value(at: 0.25) * 100
        #expect(abs((Self.number(motion.value(atMS: 250, cycleMS: 10_000)) ?? 0) - expected) < 0.001)
    }

    @Test func linearOnBothKeysMakesTheSegmentLinear() {
        var motion = LayerMotion(property: .opacity, from: .number(0), to: .number(100),
                                 timing: MotionTiming(startMS: 0, durationMS: 1000),
                                 curve: .easeInOut, repeats: .once)
        motion = motion.easing(key: 0, .linear).easing(key: 1, .linear)
        #expect(motion.keys.map(\.ease) == [.linear, .linear])
        #expect(abs((Self.number(motion.value(atMS: 250, cycleMS: 10_000)) ?? 0) - 25) < 0.001)
    }

    @Test func easeInSlowsTheArrivalAndEaseOutSlowsTheLeaving() {
        // Premiere's meaning: Ease In on a key is how it ARRIVES there, Ease
        // Out is how it LEAVES.
        let base = LayerMotion(property: .opacity, from: .number(0), to: .number(100),
                               timing: MotionTiming(startMS: 0, durationMS: 1000),
                               curve: .linear, repeats: .once)
        let arrives = base.easing(key: 1, .easeIn)
        let leaves = base.easing(key: 0, .easeOut)
        let late = Self.number(arrives.value(atMS: 900, cycleMS: 10_000)) ?? 0
        let early = Self.number(leaves.value(atMS: 100, cycleMS: 10_000)) ?? 100
        // Arriving slowly, it is nearly there well before the end.
        #expect(late > 95)
        // Leaving slowly, it has barely moved a tenth of the way in.
        #expect(early < 5)
        #expect(KeyEase.easeInAndOut.easesIn && KeyEase.easeInAndOut.easesOut)
        #expect(!KeyEase.linear.easesIn && !KeyEase.linear.easesOut)
    }

    @Test func aKeyKeepsItsEaseWhenItsValueIsRewrittenOrTheMotionGrows() {
        var motion = LayerMotion.keyed(.scale, atMS: 1000, value: .number(100))
        motion = motion.settingKey(atMS: 4000, value: .number(200))
        motion = motion.easing(key: 1, .easeIn)
        motion = motion.settingKey(atMS: 4000, value: .number(250))
        #expect(motion.keyframes.last?.ease == .easeIn)
        motion = motion.settingKey(atMS: 2500, value: .number(150))
        #expect(motion.keyframes.map(\.atMS) == [1000, 2500, 4000])
        #expect(motion.keyframes.map(\.ease) == [nil, nil, .easeIn])
        let retimed = motion.retimed(to: MotionTiming(startMS: 1000, durationMS: 6000))
        #expect(retimed.keys.map(\.ease) == [nil, nil, .easeIn])
    }

    @Test func anEasedMotionRoundTripsThroughAFile() throws {
        let motion = LayerMotion.keyed(.scale, atMS: 0, value: .number(100))
            .settingKey(atMS: 1000, value: .number(150))
            .settingKey(atMS: 2000, value: .number(200))
            .easing(key: 0, .easeOut).easing(key: 1, .linear).easing(key: 2, .easeIn)
        let data = try JSONEncoder().encode(motion)
        let back = try JSONDecoder().decode(LayerMotion.self, from: data)
        #expect(back == motion)
        // A motion nobody eased writes no ease at all.
        let plain = try JSONEncoder().encode(LayerMotion.keyed(.scale, atMS: 0, value: .number(100)))
        let text = String(data: plain, encoding: .utf8) ?? ""
        #expect(!text.contains("fromEase") && !text.contains("toEase"))
    }

    // MARK: - The marks on the clip

    @Test func aClipShowsOneMarkPerKeyedMoment() {
        let (doc, id) = Self.keyed()
        let marks = doc.clipKeyMarks(layerID: id)
        #expect(marks.map(\.documentMS) == [3000, 6000])
        #expect(Set(marks[0].properties) == [.position, .scale])
        #expect(marks[1].properties == [.scale])
    }

    @Test func aLayerWithNothingKeyedHasNoMarks() {
        let (doc, id) = Self.withTitle()
        #expect(doc.clipKeyMarks(layerID: id).isEmpty)
    }

    @Test func draggingAMarkMovesEveryKeyAtThatMoment() {
        var (doc, id) = Self.keyed()
        let moved = doc.moveClipKeys(layerID: id, fromMS: 3000, toMS: 4000)
        #expect(moved)
        #expect(doc.clipKeyMarks(layerID: id).map(\.documentMS) == [4000, 6000])
        // It kept what it said: scale is 100 on the moved key.
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.scale), atDocumentTimeMS: 4000)) == 100)
        #expect(doc.keyDiamond(layerID: id, .motion(.position), atDocumentTimeMS: 4000) == .onKey)
    }

    @Test func aDraggedMarkStopsShortOfItsNeighbourAndTheClipsEnds() {
        var (doc, id) = Self.keyed()
        doc.moveClipKeys(layerID: id, fromMS: 3000, toMS: 9000)
        // Scale's next key is at 6s: the mark cannot pass it and swap the move.
        let first = doc.clipKeyMarks(layerID: id).first?.documentMS ?? 0
        #expect(first < 6000)
        #expect(doc.keyCount(layerID: id, .motion(.scale)) == 2)
        var (other, oid) = Self.keyed()
        other.moveClipKeys(layerID: oid, fromMS: 3000, toMS: 0)
        #expect(other.clipKeyMarks(layerID: oid).first?.documentMS == 2000)
    }

    @Test func easingAMarkEasesEveryKeyThere() {
        var (doc, id) = Self.keyed()
        // A key nobody eased reads as its motion's own curve: ease in and out.
        #expect(doc.clipKeyEase(layerID: id, atMS: 3000) == .easeInAndOut)
        doc.easeClipKeys(layerID: id, atMS: 3000, .linear)
        #expect(doc.clipKeyEase(layerID: id, atMS: 3000) == .linear)
        let scale = doc.layer(id: id)?.keyedMotion(.scale)
        #expect(scale?.keyframes.first?.ease == .linear)
        let position = doc.layer(id: id)?.keyedMotion(.position)
        #expect(position?.keyframes.first?.ease == .linear)
    }

    @Test func deletingAMarkDeletesEveryKeyThere() {
        var (doc, id) = Self.keyed()
        let removed = doc.removeClipKeys(layerID: id, atMS: 6000)
        #expect(removed)
        #expect(doc.clipKeyMarks(layerID: id).map(\.documentMS) == [3000])
        // Position's only key going takes its keying with it, keeping the place.
        doc.removeClipKeys(layerID: id, atMS: 3000)
        #expect(doc.clipKeyMarks(layerID: id).isEmpty)
        #expect(doc.layer(id: id)?.frame.origin == CGPoint(x: 100, y: 100))
    }

    // MARK: - Title presets

    @Test func fadeInBringsTheWordsUpOverHalfASecond() {
        var (doc, id) = Self.withTitle()
        let done = doc.animateIn(.fade, layerID: id)
        #expect(done)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.opacity), atDocumentTimeMS: 2000)) == 0)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.opacity), atDocumentTimeMS: 2500)) == 100)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.opacity), atDocumentTimeMS: 5000)) == 100)
    }

    @Test func slideInArrivesFromOffTheLeftEdge() {
        var (doc, id) = Self.withTitle()
        doc.animateIn(.slide, layerID: id)
        let start = Self.point(doc.keyedValue(layerID: id, .motion(.position), atDocumentTimeMS: 2000))
        let landed = Self.point(doc.keyedValue(layerID: id, .motion(.position), atDocumentTimeMS: 2500))
        #expect((start?.x ?? 0) <= -400)
        #expect(start?.y == 100)
        #expect(landed == CGPoint(x: 100, y: 100))
    }

    @Test func popAndScaleGrowTheWordsIn() {
        var (doc, id) = Self.withTitle()
        doc.animateIn(.pop, layerID: id)
        let small = Self.number(doc.keyedValue(layerID: id, .motion(.scale), atDocumentTimeMS: 2000)) ?? 100
        #expect(small < 20)
        // A pop overshoots before it settles.
        let peak = (2000...2500).map { Self.number(doc.keyedValue(layerID: id, .motion(.scale), atDocumentTimeMS: $0)) ?? 0 }.max() ?? 0
        #expect(peak > 105)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.scale), atDocumentTimeMS: 2500)) == 100)

        var (plain, pid) = Self.withTitle()
        plain.animateIn(.scale, layerID: pid)
        let grows = (2000...2500).map { Self.number(plain.keyedValue(layerID: pid, .motion(.scale), atDocumentTimeMS: $0)) ?? 0 }
        #expect((grows.first ?? 100) < 20)
        #expect((grows.max() ?? 0) <= 100)
    }

    @Test func outPresetsTakeTheWordsOffByTheEnd() {
        var (doc, id) = Self.withTitle()
        doc.animateOut(.fade, layerID: id)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.opacity), atDocumentTimeMS: 7500)) == 100)
        #expect((Self.number(doc.keyedValue(layerID: id, .motion(.opacity), atDocumentTimeMS: 7999)) ?? 100) < 2)

        var (slid, sid) = Self.withTitle()
        slid.animateOut(.slide, layerID: sid)
        let gone = Self.point(slid.keyedValue(layerID: sid, .motion(.position), atDocumentTimeMS: 8000))
        #expect((gone?.x ?? 0) >= 1920)
    }

    @Test func inAndOutTogetherKeepTheKeysBetween() {
        var (doc, id) = Self.withTitle()
        doc.animateIn(.fade, layerID: id)
        doc.animateOut(.fade, layerID: id)
        #expect(doc.keyCount(layerID: id, .motion(.opacity)) == 4)
        #expect(doc.clipKeyMarks(layerID: id).map(\.documentMS) == [2000, 2500, 7500, 8000])
        // A fade in and a fade out is exactly the fade the Time section reads.
        #expect(doc.layer(id: id)?.titleFadeMS == 500)
    }

    @Test func presetsAreOnlyForThingsPlacedInTime() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let still = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#000000")),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        doc.layers = [still]
        let done = doc.animateIn(.fade, layerID: still.id)
        #expect(!done)
    }

    @Test func aShortTitleSharesItsLengthBetweenInAndOut() {
        var (doc, id) = Self.withTitle()
        doc.updateLayer(id: id) { $0.time = LayerTime(inMS: 2000, outMS: 2600) }
        doc.animateIn(.fade, layerID: id)
        doc.animateOut(.fade, layerID: id)
        let marks = doc.clipKeyMarks(layerID: id).map(\.documentMS)
        #expect(marks == [2000, 2300, 2600])
    }

    // MARK: - Where a title lands

    @Test func aTitleSitsOnATrackCalledTitle() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var title = Layer(name: "Hello", content: .text(TextContent(string: "Hello")),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        title.time = LayerTime(inMS: 0, outMS: 1000)
        doc.addLayer(title)
        #expect(doc.timelineTracks.first?.name == "Title")
    }
}
