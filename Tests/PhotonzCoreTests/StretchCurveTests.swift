import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Between the keys: the curve of the stretch the playhead is in
/// (task `a-moving-layer-shows-between-the-keys-in-propert`,
/// `docs/design/mocks/pages/video-move-wt.html` step 6).
///
/// Written before the model. Keys ease one key at a time, Premiere's way, so a
/// stretch runs on what its two keys say. The Curve dropdown asks the question
/// the other way round, about the stretch, with the mock's eight names. The
/// four a pair of keys can say are written onto the keys, so the timeline's
/// Easing and a key's right-click read the change; the shaped four ride the
/// stretch itself, and any per-key ease on either end takes the stretch back.
@Suite("Stretch curve")
struct StretchCurveTests {

    // MARK: - Fixtures

    /// Position keyed at 0s, 4s and 8s. Every key made the way the panel
    /// makes one, so every key is at its default ease.
    static func threeKeys() -> LayerMotion {
        var motion = LayerMotion.keyed(.position, atMS: 0, value: .point(CGPoint(x: 100, y: 500)))
        motion = motion.settingKey(atMS: 4000, value: .point(CGPoint(x: 700, y: 500)))
        motion = motion.settingKey(atMS: 8000, value: .point(CGPoint(x: 700, y: 100)))
        return motion
    }

    static func twoKeys() -> LayerMotion {
        var motion = LayerMotion.keyed(.position, atMS: 0, value: .point(CGPoint(x: 100, y: 500)))
        motion = motion.settingKey(atMS: 4000, value: .point(CGPoint(x: 700, y: 500)))
        return motion
    }

    static func document(_ motion: LayerMotion) -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var art = Layer(name: "Sparkle",
                        content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FFD36B")),
                        frame: CGRect(x: 100, y: 500, width: 100, height: 50))
        art.time = LayerTime(inMS: 0, outMS: 10_000)
        art.motions = [motion]
        doc.layers = [art]
        doc.durationMS = 10_000
        return (doc, art.id)
    }

    static func x(_ motion: LayerMotion, atMS ms: Int) -> Double {
        if case let .point(point) = motion.value(atMS: ms, cycleMS: 10_000) { return Double(point.x) }
        return .nan
    }

    // MARK: - Which stretch

    @Test func thePlayheadIsInTheStretchBetweenTheKeysEitherSideOfIt() {
        let motion = Self.threeKeys()
        #expect(motion.stretch(atMS: 1000) == 0)
        #expect(motion.stretch(atMS: 5000) == 1)
        // On a key, the stretch it starts; on the last, the one it ends.
        #expect(motion.stretch(atMS: 4000) == 1)
        #expect(motion.stretch(atMS: 8000) == 1)
        // Before the first key or after the last, the nearest stretch.
        #expect(motion.stretch(atMS: 9000) == 1)
    }

    @Test func oneKeyHasNoStretch() {
        let motion = LayerMotion.keyed(.opacity, atMS: 1000, value: .number(100))
        #expect(motion.stretch(atMS: 1000) == nil)
        #expect(motion.stretchCurve(0) == nil)
    }

    // MARK: - Reading it

    @Test func aStretchNobodyEasedReadsAsTheMotionsOwnCurve() {
        let motion = Self.threeKeys()
        #expect(motion.stretchCurve(0) == PropertyKeys.curve)
        #expect(motion.stretchCurve(1) == PropertyKeys.curve)
    }

    @Test func aStretchReadsWhatItsTwoKeysSay() {
        let motion = Self.threeKeys().easing(key: 0, .linear).easing(key: 1, .linear)
        #expect(motion.stretchCurve(0) == .linear)
        let settling = Self.threeKeys().easing(key: 0, .linear).easing(key: 1, .easeIn)
        #expect(settling.stretchCurve(0) == .easeOut)
    }

    @Test func aHeldKeyReadsAsHold() {
        let motion = Self.threeKeys().easing(key: 0, .hold)
        #expect(motion.stretchCurve(0) == .steps(1))
        #expect(StretchCurve.title(.steps(1)) == "Hold")
    }

    @Test func aDrawnStretchReadsAsCustom() {
        let motion = Self.threeKeys().settingHandle(key: 0, .leaving, to: CGPoint(x: 0.1, y: 0.8))
        guard case .custom = motion.stretchCurve(0) else {
            Issue.record("expected a drawn curve, got \(String(describing: motion.stretchCurve(0)))")
            return
        }
        #expect(StretchCurve.title(motion.stretchCurve(0) ?? .linear) == "Custom")
    }

    // MARK: - Choosing it

    @Test func everyNamedCurveReadsBackAsItselfOnTheStretchItWasChosenFor() {
        for curve in EasingCurve.named {
            let motion = Self.threeKeys().curvingStretch(1, curve)
            #expect(motion.stretchCurve(1) == curve, "\(curve.title)")
            // And the stretch next to it is exactly what it was.
            #expect(motion.stretchCurve(0) == PropertyKeys.curve, "\(curve.title) moved the stretch before it")
        }
    }

    @Test func choosingACurveChangesHowTheValueTravelsThere() {
        let before = Self.twoKeys()
        let linear = before.curvingStretch(0, .linear)
        // A quarter of the way through a flat run is a quarter of the way there.
        #expect(abs(Self.x(linear, atMS: 1000) - 250) < 1)
        // An eased one is behind that, leaning out of the first key.
        #expect(Self.x(before, atMS: 1000) < 245)
        let elastic = before.curvingStretch(0, .easeOutElastic)
        #expect(abs(Self.x(elastic, atMS: 1000) - Self.x(linear, atMS: 1000)) > 1)
    }

    @Test func theFourTheKeysCanSayAreWrittenOnTheKeys() {
        let motion = Self.twoKeys().curvingStretch(0, .linear)
        #expect(motion.keyframes[0].ease == .linear)
        #expect(motion.keyframes[1].ease == .linear)
        let both = Self.twoKeys().curvingStretch(0, .easeInOut)
        // The two ends of a move have one half nobody can see, and it follows
        // the half that shows, so a two-key move reads one ease on both keys.
        #expect(both.keyframes[0].ease == .easeInAndOut)
        #expect(both.keyframes[1].ease == .easeInAndOut)
    }

    @Test func aMiddleKeyKeepsTheHalfThatShapesTheOtherStretch() {
        let base = Self.threeKeys().easing(key: 1, .easeIn)   // settles into key 1, leaves it flat
        let motion = base.curvingStretch(1, .easeIn)           // slow start out of key 1
        #expect(motion.keyframes[1].ease == .easeInAndOut)
        #expect(motion.stretchCurve(0) == base.stretchCurve(0))
    }

    @Test func theShapedCurvesRideTheStretchAndAPerKeyEaseTakesItBack() {
        let bounced = Self.threeKeys().curvingStretch(0, .easeOutBack)
        #expect(bounced.stretchCurve(0) == .easeOutBack)
        // The key's right-click (or the timeline's Easing) on either end.
        #expect(bounced.easing(key: 0, .linear).stretchCurve(0) != .easeOutBack)
        #expect(bounced.easing(key: 1, .linear).stretchCurve(0) != .easeOutBack)
        // And choosing one of the four afterwards replaces it.
        #expect(bounced.curvingStretch(0, .linear).stretchCurve(0) == .linear)
    }

    @Test func aCurveDrawnByHandIsTheTwoKeysHandles() {
        let drawn = EasingCurve.custom(x1: 0.1, y1: 0.7, x2: 0.3, y2: 1)
        let motion = Self.threeKeys().curvingStretch(0, drawn)
        #expect(motion.keyframes[0].ease == .bezier)
        #expect(motion.keyframes[1].ease == .bezier)
        #expect(motion.stretchCurve(0) == drawn)
        #expect(motion.stretchCurve(1) == PropertyKeys.curve)
    }

    @Test func aKeyLandingPartWayAlongAShapedStretchKeepsBothHalvesShaped() {
        let bounced = Self.twoKeys().curvingStretch(0, .easeOutElastic)
        let split = bounced.settingKey(atMS: 2000, value: .point(CGPoint(x: 400, y: 300)))
        #expect(split.stretchCurve(0) == .easeOutElastic)
        #expect(split.stretchCurve(1) == .easeOutElastic)
    }

    @Test func aShapedStretchSurvivesSavingAndOpening() throws {
        let motion = Self.threeKeys().curvingStretch(0, .steps(4)).curvingStretch(1, .easeInOutSine)
        let data = try JSONEncoder().encode(motion)
        let read = try JSONDecoder().decode(LayerMotion.self, from: data)
        #expect(read.stretchCurve(0) == .steps(4))
        #expect(read.stretchCurve(1) == .easeInOutSine)
    }

    @Test func aMotionWrittenBeforeStretchCurvesReadsBackUnchanged() throws {
        let motion = Self.threeKeys()
        let json = String(decoding: try JSONEncoder().encode(motion), as: UTF8.self)
        #expect(!json.contains("fromCurve"))
    }

    // MARK: - The document, at the playhead

    @Test func theDocumentCurvesTheStretchUnderThePlayhead() {
        var (doc, id) = Self.document(Self.threeKeys())
        doc.curveStretch(layerID: id, .position, atDocumentTimeMS: 5000, .easeOutBack)
        #expect(doc.stretchCurve(layerID: id, .position, atDocumentTimeMS: 5000) == .easeOutBack)
        #expect(doc.stretchCurve(layerID: id, .position, atDocumentTimeMS: 1000) == PropertyKeys.curve)
    }

    @Test func thePickedKeysEaseFollowsACurveChosenForTheStretch() {
        var (doc, id) = Self.document(Self.twoKeys())
        doc.curveStretch(layerID: id, .position, atDocumentTimeMS: 1000, .linear)
        guard let motion = doc.layer(id: id)?.keyedMotion(.position) else {
            Issue.record("no motion")
            return
        }
        let refs = Set(motion.keyframes.map { KeyRef(motionID: motion.id, clockMS: $0.atMS) })
        #expect(doc.keysEase(layerID: id, refs) == .linear)
    }

    @Test func aStretchIsOnlyAskedOfAPropertyWithTwoKeys() {
        let (doc, id) = Self.document(LayerMotion.keyed(.position, atMS: 0, value: .point(.zero)))
        #expect(doc.stretchCurve(layerID: id, .position, atDocumentTimeMS: 0) == nil)
    }
}
