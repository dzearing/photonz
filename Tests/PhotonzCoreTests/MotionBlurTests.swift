import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Motion blur on titles that move fast (task
/// `motion-blur-on-titles-that-move-fast`, `docs/design/video-titles-polish.md`,
/// step 4 of 6).
///
/// Written before the model. Motion blur is an effect like Grain: a switch and
/// a Shutter angle, on any layer or on a title's group as a whole, never baked
/// into pixels. At the moment a frame is drawn, everything it covers is read a
/// little before and a little after (the shutter, centred on the frame), and a
/// part that travelled far enough in that time is handed the path it took,
/// relative to where it is drawn. The renderer smears the part along that
/// path. A part holding still is handed nothing, so a held frame is exactly
/// the frame it always was.
@Suite("Motion blur on titles that move fast")
struct MotionBlurTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    static func box(_ name: String = "Box", frame: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(
            shape: .rectangle, strokeWidth: 0, colorHex: "#FFFFFF",
            start: .zero, end: CGPoint(x: frame.width, y: frame.height), fillColorHex: "#FFFFFF")),
            frame: frame)
    }

    /// A box sliding from x=0 to x=1600 between 1000ms and 1500ms of a video,
    /// on a straight line, so it travels 3.2pt every millisecond.
    static func slide(blur: MotionBlurEffect? = MotionBlurEffect(), curve: EasingCurve = .linear,
                      distance: CGFloat = 1600) -> (PhotonzDocument, UUID) {
        var layer = box(frame: CGRect(x: 0, y: 400, width: 200, height: 200))
        layer.time = LayerTime(inMS: 0, outMS: 4_000)
        layer.motions = [LayerMotion(property: .position, from: .point(CGPoint(x: 0, y: 400)),
                                     to: .point(CGPoint(x: distance, y: 400)),
                                     timing: MotionTiming(startMS: 1_000, durationMS: 500),
                                     curve: curve, repeats: .once)]
        if let blur { layer.style.effects.append(.motionBlur(blur)) }
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.layers = [layer]
        doc.durationMS = 4_000
        return (doc, layer.id)
    }

    static func travel(_ transform: CGAffineTransform, of point: CGPoint) -> CGPoint {
        let moved = point.applying(transform)
        return CGPoint(x: moved.x - point.x, y: moved.y - point.y)
    }

    // MARK: - The effect

    @Test("Motion Blur is an effect with a switch and a Shutter angle, 180 degrees to start")
    func theEffect() throws {
        let blur = MotionBlurEffect()
        #expect(blur.shutterAngle == 180)
        #expect(blur.isOn)
        #expect(MotionBlurEffect(shutterAngle: 500).shutterAngle == 360)
        #expect(MotionBlurEffect(shutterAngle: -4).shutterAngle == 0)
        #expect(EffectKind.motionBlur.title == "Motion Blur")
        #expect(!EffectKind.motionBlur.isCountable)
        #expect(EffectKind.motionBlur.colorSlot == nil)
        #expect(AddableEffect.motionBlur.kind == .motionBlur)
        #expect(AddableEffect.motionBlur.title == "Motion Blur")
        #expect(AddableEffect.motionBlur.newEffect == .motionBlur(MotionBlurEffect()))
        // 180 degrees is half a frame of the movie an export writes (33ms).
        #expect(abs(MotionBlurEffect.frameMS - 33) < 0.01)
        #expect(abs(blur.shutterMS - 16.5) < 0.01)
        #expect(abs(MotionBlurEffect(shutterAngle: 360).shutterMS - 33) < 0.01)
    }

    @Test("It saves legibly and reads back the same, and magnifying a document leaves it alone")
    func savesLegibly() throws {
        let effect = LayerEffect.motionBlur(MotionBlurEffect(shutterAngle: 270, isOn: false))
        let data = try JSONEncoder().encode(effect)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"kind\":\"motionBlur\""))
        #expect(try JSONDecoder().decode(LayerEffect.self, from: data) == effect)
        #expect(effect.magnified(by: 2) == effect)
        #expect(effect.colorHex == nil)
        var style = LayerStyle()
        style.effects = [effect]
        #expect(style.motionBlurEffect(at: 0)?.shutterAngle == 270)
        style.updateMotionBlurEffect(at: 0) { $0.isOn = true }
        #expect(style.motionBlurEffect(at: 0)?.isOn == true)
        // A motion blur is about time, not the picture: a group wearing one is
        // still a container its contents draw straight through.
        #expect(style.isPlain)
    }

    // MARK: - Who moves, and how far

    @Test("A part sliding fast is handed the path it took across the shutter, centred on the frame")
    func aFastSlideIsSmeared() throws {
        let (doc, id) = Self.slide()
        let drawn = try #require(doc.drawn(atTimeMS: 1_250).layer(id: id))
        let smear = try #require(drawn.motionSmear)
        #expect(smear.samples.count >= 8)
        // 3.2pt a millisecond for 16.5ms: 53pt end to end, half behind it and
        // half ahead of it.
        let middle = CGPoint(x: drawn.frame.midX, y: drawn.frame.midY)
        let first = Self.travel(try #require(smear.samples.first), of: middle)
        let last = Self.travel(try #require(smear.samples.last), of: middle)
        #expect(abs(first.x + 26.4) < 1, "first \(first)")
        #expect(abs(last.x - 26.4) < 1, "last \(last)")
        #expect(abs(first.y) < 0.01 && abs(last.y) < 0.01)
        #expect(abs(smear.span - 52.8) < 1.5, "span \(smear.span)")
        // Evenly along the way on a straight line.
        let steps = smear.samples.map { Self.travel($0, of: middle).x }
        for (a, b) in zip(steps, steps.dropFirst()) { #expect(b > a) }
    }

    @Test("A wider shutter smears further: 360 degrees is twice 180")
    func widerShutterSmearsFurther() throws {
        let (half, id) = Self.slide()
        let (whole, wholeID) = Self.slide(blur: MotionBlurEffect(shutterAngle: 360))
        let a = try #require(half.drawn(atTimeMS: 1_250).layer(id: id)?.motionSmear)
        let b = try #require(whole.drawn(atTimeMS: 1_250).layer(id: wholeID)?.motionSmear)
        #expect(abs(b.span / a.span - 2) < 0.1, "\(a.span) then \(b.span)")
    }

    @Test("Held still, switched off, or never asked for: nothing is handed over")
    func heldFramesAreLeftAlone() throws {
        let (doc, id) = Self.slide()
        // Before it moves, and well after it lands.
        #expect(doc.drawn(atTimeMS: 500).layer(id: id)?.motionSmear == nil)
        #expect(doc.drawn(atTimeMS: 2_000).layer(id: id)?.motionSmear == nil)
        let (plain, plainID) = Self.slide(blur: nil)
        #expect(plain.drawn(atTimeMS: 1_250).layer(id: plainID)?.motionSmear == nil)
        let (off, offID) = Self.slide(blur: MotionBlurEffect(isOn: false))
        #expect(off.drawn(atTimeMS: 1_250).layer(id: offID)?.motionSmear == nil)
        let (shut, shutID) = Self.slide(blur: MotionBlurEffect(shutterAngle: 0))
        #expect(shut.drawn(atTimeMS: 1_250).layer(id: shutID)?.motionSmear == nil)
    }

    @Test("Slow drift stays sharp: a part has to move faster than a small threshold")
    func slowDriftStaysSharp() throws {
        // 20pt over 500ms is 0.7pt across a 180 degree shutter.
        let (doc, id) = Self.slide(distance: 20)
        #expect(doc.drawn(atTimeMS: 1_250).layer(id: id)?.motionSmear == nil)
        #expect(MotionSmear.threshold <= 1.5)
    }

    @Test("An expo ease smears hard at the start of the move and not at all as it lands")
    func easeOutSmearsEarly() throws {
        let (doc, id) = Self.slide(curve: .easeOutExpo)
        let early = try #require(doc.drawn(atTimeMS: 1_020).layer(id: id)?.motionSmear)
        let late = doc.drawn(atTimeMS: 1_480).layer(id: id)?.motionSmear
        #expect(early.span > 60)
        #expect(late == nil || late?.span ?? 0 < early.span / 10)
    }

    @Test("Growing and turning are followed too, not just sliding")
    func scaleAndRotationAreFollowed() throws {
        var layer = Self.box(frame: CGRect(x: 760, y: 340, width: 400, height: 400))
        layer.time = LayerTime(inMS: 0, outMS: 4_000)
        layer.motions = [LayerMotion(property: .scale, from: .number(20), to: .number(100),
                                     timing: MotionTiming(startMS: 1_000, durationMS: 300), repeats: .once)]
        layer.style.effects = [.motionBlur(MotionBlurEffect())]
        var spin = Self.box("Spin", frame: CGRect(x: 100, y: 100, width: 300, height: 100))
        spin.time = LayerTime(inMS: 0, outMS: 4_000)
        spin.motions = [LayerMotion(property: .rotation, from: .number(0), to: .number(360),
                                    timing: MotionTiming(startMS: 1_000, durationMS: 400), repeats: .once)]
        spin.style.effects = [.motionBlur(MotionBlurEffect())]
        var doc = PhotonzDocument(canvasSize: Self.canvas)
        doc.layers = [layer, spin]
        doc.durationMS = 4_000
        let shown = doc.drawn(atTimeMS: 1_150)
        let grow = try #require(shown.layer(id: layer.id)?.motionSmear)
        // Smaller before, bigger after, about the middle, which stays put.
        let first = try #require(grow.samples.first), last = try #require(grow.samples.last)
        #expect(first.a < 1 && last.a > 1, "\(first.a) \(last.a)")
        let middle = CGPoint(x: 960, y: 540)
        #expect(hypot(Self.travel(first, of: middle).x, Self.travel(first, of: middle).y) < 0.5)
        let turn = try #require(shown.layer(id: spin.id)?.motionSmear)
        let angles = turn.samples.map { atan2($0.b, $0.a) }
        #expect((angles.first ?? 0) < -0.05 && (angles.last ?? 0) > 0.05, "\(angles)")
    }

    // MARK: - A title as a whole

    /// A title: a still backdrop, and a headline and a subtitle that slide in
    /// on their own beats, inside one group.
    static func title(blurOnGroup: MotionBlurEffect?, subtitleOwn: MotionBlurEffect? = nil)
        -> (PhotonzDocument, group: UUID, headline: UUID, subtitle: UUID, backdrop: UUID) {
        let backdrop = box("Backdrop", frame: CGRect(origin: .zero, size: canvas))
        var headline = box("Headline", frame: CGRect(x: 200, y: 400, width: 800, height: 120))
        headline.motions = [LayerMotion(property: .position, from: .point(CGPoint(x: -900, y: 400)),
                                        to: .point(CGPoint(x: 200, y: 400)),
                                        timing: MotionTiming(startMS: 0, durationMS: 400),
                                        curve: .linear, repeats: .once)]
        var subtitle = box("Subtitle", frame: CGRect(x: 200, y: 560, width: 600, height: 60))
        subtitle.motions = [LayerMotion(property: .position, from: .point(CGPoint(x: 200, y: 1200)),
                                        to: .point(CGPoint(x: 200, y: 560)),
                                        timing: MotionTiming(startMS: 100, durationMS: 400),
                                        curve: .linear, repeats: .once)]
        if let subtitleOwn { subtitle.style.effects = [.motionBlur(subtitleOwn)] }
        var group = Layer(name: "Title", content: .group(GroupContent(children: [backdrop, headline, subtitle])),
                          frame: CGRect(origin: .zero, size: .zero))
        group.time = LayerTime(inMS: 1_000, outMS: 5_000)
        if let blurOnGroup { group.style.effects = [.motionBlur(blurOnGroup)] }
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.layers = [group]
        doc.durationMS = 6_000
        return (doc, group.id, headline.id, subtitle.id, backdrop.id)
    }

    @Test("Switched on for a title, each moving part is smeared by its own move and the still ones are not")
    func aTitleAsAWhole() throws {
        let (doc, _, headline, subtitle, backdrop) = Self.title(blurOnGroup: MotionBlurEffect())
        let shown = doc.drawn(atTimeMS: 1_250)
        let head = try #require(shown.layer(id: headline)?.motionSmear)
        let sub = try #require(shown.layer(id: subtitle)?.motionSmear)
        #expect(shown.layer(id: backdrop)?.motionSmear == nil)
        // The headline travels right, the subtitle up.
        let headStep = Self.travel(try #require(head.samples.last), of: .zero)
        let subStep = Self.travel(try #require(sub.samples.last), of: .zero)
        #expect(headStep.x > 10 && abs(headStep.y) < 0.01, "\(headStep)")
        #expect(subStep.y < -10 && abs(subStep.x) < 0.01, "\(subStep)")
    }

    @Test("A part's own Motion Blur beats the title's, even switched off")
    func aPartCanOptOut() throws {
        let (doc, _, headline, subtitle, _) = Self.title(blurOnGroup: MotionBlurEffect(),
                                                         subtitleOwn: MotionBlurEffect(isOn: false))
        let shown = doc.drawn(atTimeMS: 1_250)
        #expect(shown.layer(id: headline)?.motionSmear != nil)
        #expect(shown.layer(id: subtitle)?.motionSmear == nil)
        // ...and on with a title that has none.
        let (alone, _, otherHeadline, otherSubtitle, _) = Self.title(blurOnGroup: nil,
                                                                     subtitleOwn: MotionBlurEffect(shutterAngle: 360))
        let shownAlone = alone.drawn(atTimeMS: 1_250)
        #expect(shownAlone.layer(id: otherHeadline)?.motionSmear == nil)
        #expect(shownAlone.layer(id: otherSubtitle)?.motionSmear != nil)
    }

    @Test("A title sliding in as a whole smears every part of it the same way")
    func aGroupSlidingAsOne() throws {
        var (doc, group, headline, _, backdrop) = Self.title(blurOnGroup: MotionBlurEffect())
        doc.updateLayer(id: group) { layer in
            layer.motions = [LayerMotion(property: .position, from: .point(CGPoint(x: 0, y: 1080)),
                                         to: .point(.zero), timing: MotionTiming(startMS: 1_000, durationMS: 500),
                                         curve: .linear, repeats: .once)]
        }
        let shown = doc.drawn(atTimeMS: 2_250)
        // The parts have stopped moving inside it; the title is still rising.
        let back = try #require(shown.layer(id: backdrop)?.motionSmear)
        let head = try #require(shown.layer(id: headline)?.motionSmear)
        let a = Self.travel(try #require(back.samples.last), of: .zero)
        let b = Self.travel(try #require(head.samples.last), of: .zero)
        #expect(a.y < -10 && abs(a.y - b.y) < 0.01, "\(a) \(b)")
    }

    @Test("Words that come in a piece at a time are told how long the shutter is open")
    func revealPiecesAreTold() throws {
        var text = TextContent(string: "Fast words", fontSize: 96, colorHex: "#FFFFFF")
        text.reveal = TextReveal(style: .riseAndFade, unit: .word)
        var words = Layer(name: "Words", content: .text(text), frame: CGRect(x: 100, y: 100, width: 1200, height: 140))
        var group = Layer(name: "Title", content: .group(GroupContent(children: [words])),
                          frame: CGRect(origin: .zero, size: .zero))
        group.time = LayerTime(inMS: 0, outMS: 4_000)
        group.style.effects = [.motionBlur(MotionBlurEffect(shutterAngle: 270))]
        var doc = PhotonzDocument(canvasSize: Self.canvas)
        doc.layers = [group]
        doc.durationMS = 4_000
        let shown = try #require(doc.drawn(atTimeMS: 100).layer(id: words.id)?.text)
        #expect(abs((shown.revealShutterMS ?? 0) - 33 * 0.75) < 0.01)
        // Without a motion blur over it, nothing is said.
        words.style.effects = []
        group.style.effects = []
        group.children = [words]
        doc.layers = [group]
        #expect(doc.drawn(atTimeMS: 100).layer(id: words.id)?.text?.revealShutterMS == nil)
    }

    @Test("A path drawn at twice the size travels twice as far")
    func magnifiedSmear() throws {
        let (doc, id) = Self.slide()
        let shown = doc.drawn(atTimeMS: 1_250)
        let smear = try #require(shown.layer(id: id)?.motionSmear)
        let big = try #require(shown.magnified(by: 2).layer(id: id)?.motionSmear)
        #expect(big.samples.count == smear.samples.count)
        let a = Self.travel(try #require(smear.samples.last), of: .zero)
        let b = Self.travel(try #require(big.samples.last), of: .zero)
        #expect(abs(b.x - a.x * 2) < 0.01)
    }

    @Test("A smear is only ever on the frame being drawn, never on the document")
    func onlyOnTheDrawnFrame() throws {
        let (doc, id) = Self.slide()
        #expect(doc.drawn(atTimeMS: 1_250).layer(id: id)?.motionSmear != nil)
        #expect(doc.layer(id: id)?.motionSmear == nil)
    }

    @Test("A revealing piece can be read between two whole milliseconds, and agrees with them on them")
    func posesBetweenMilliseconds() throws {
        let reveal = TextReveal(style: .riseAndFade, unit: .word, curve: .linear)
        #expect(reveal.pose(rank: 1, atElapsed: 170) == reveal.pose(rank: 1, atElapsedMS: 170))
        let a = reveal.pose(rank: 1, atElapsedMS: 170).offsetEm.y
        let b = reveal.pose(rank: 1, atElapsedMS: 171).offsetEm.y
        let between = reveal.pose(rank: 1, atElapsed: 170.5).offsetEm.y
        #expect(abs(between - (a + b) / 2) < 1e-9)
    }

    @Test("A built-in title can arrive wearing motion blur on the whole title, and its parts smear as they come in")
    func builtInTitlesWearIt() throws {
        var doc = PhotonzDocument(canvasSize: Self.canvas)
        doc.durationMS = 10_000
        var plain = doc
        let placed = doc.insertTitle(.midnight, atTimeMS: 1_000, motionBlur: true)
        let inserted = try #require(placed)
        let group = try #require(doc.layer(id: inserted.layerID))
        #expect(group.style.motionBlur == MotionBlurEffect())
        // Nothing in the title itself wears one: the title as a whole does.
        #expect(group.children.allSatisfy { $0.style.motionBlur == nil })
        // Some part of it is smeared while it arrives, and none once it is in.
        let arriving = (1_000...1_400).contains { ms in
            doc.drawn(atTimeMS: ms).layer(id: inserted.layerID)?.children.contains { $0.motionSmear != nil } == true
        }
        #expect(arriving)
        let landed = try #require(doc.drawn(atTimeMS: 2_500).layer(id: inserted.layerID))
        #expect(landed.children.allSatisfy { $0.motionSmear == nil })
        // Asked for without it, it has none.
        let placedPlain = plain.insertTitle(.midnight, atTimeMS: 1_000)
        let without = try #require(placedPlain)
        #expect(plain.layer(id: without.layerID)?.style.motionBlur == nil)
    }
}
