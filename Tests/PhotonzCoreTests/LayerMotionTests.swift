import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Motion: a layer told to change one of its properties over time.
///
/// Written before the model, which is the rule for `PhotonzCore`. Every fact
/// the panel and the canvas will lean on is settled here, in a module that
/// knows nothing about either: what a layer HAS that can move, what a curve
/// does between nought and one, what the picture looks like at a given
/// millisecond, and what the row says about itself.
@Suite("A layer changing one of its properties over time")
struct LayerMotionTests {

    // MARK: - Fixtures

    static func shape(rotation: CGFloat = 0, opacity: Double = 1) -> Layer {
        var layer = Layer(name: "Bell",
                          content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 colorHex: "#0C0E14")),
                          frame: CGRect(x: 6, y: 4, width: 40, height: 40))
        layer.transform.rotation = rotation
        layer.style.opacity = opacity
        return layer
    }

    static func rotationMotion(from: Double = -12, to: Double = 12,
                               start: Int = 0, over: Int = 900,
                               curve: EasingCurve = .linear,
                               repeats: MotionRepeat = .forever) -> LayerMotion {
        LayerMotion(property: .rotation,
                    from: .number(from), to: .number(to),
                    timing: MotionTiming(startMS: start, durationMS: over),
                    curve: curve, repeats: repeats)
    }

    // MARK: - What a layer HAS that can move

    /// The plus is built out of the layer, not out of a fixed list: every
    /// property it offers carries the value that property has right now,
    /// because that is what you would be animating away from.
    @Test func everyPropertyOfferedCarriesTheValueItHasNow() {
        let layer = Self.shape(rotation: .pi / 4, opacity: 0.5)
        let offered = MotionProperty.offered(for: layer)

        #expect(offered.contains { $0.property == .position })
        #expect(offered.contains { $0.property == .rotation })
        #expect(offered.contains { $0.property == .opacity })
        #expect(offered.contains { $0.property == .scale })

        let rotation = offered.first { $0.property == .rotation }
        #expect(rotation?.current == .number(45))
        let opacity = offered.first { $0.property == .opacity }
        #expect(opacity?.current == .number(50))
        let position = offered.first { $0.property == .position }
        #expect(position?.current == .point(CGPoint(x: 6, y: 4)))
        // Scale is always 100% of what was drawn: there is nothing else it
        // could mean before anything has moved.
        #expect(offered.first { $0.property == .scale }?.current == .number(100))
    }

    /// A photograph has no colour of its own and no line round it, so the menu
    /// must not offer either: a row that cannot change anything is a row that
    /// lies about what the layer is.
    @Test func aPictureIsNotOfferedAColourOrAStrokeItHasNot() {
        let picture = Layer(name: "Shot", content: .image(ImageRef(pixelSize: CGSize(width: 100, height: 60))),
                            frame: CGRect(x: 0, y: 0, width: 100, height: 60))
        let offered = MotionProperty.offered(for: picture).map(\.property)
        #expect(!offered.contains(.color))
        #expect(!offered.contains(.strokeWidth))
        // ...but where it sits, how big it is, how turned and how faded it is
        // are true of anything at all.
        #expect(offered.contains(.position))
        #expect(offered.contains(.scale))
        #expect(offered.contains(.rotation))
        #expect(offered.contains(.opacity))
    }

    /// A drawn path has a colour and a line whose width is its own, so both
    /// are offered, with the numbers the path is wearing.
    @Test func aDrawnPathIsOfferedItsColourAndItsStrokeWidth() {
        let path = Layer(name: "Glyph",
                         content: .path(PathContent(anchors: [PathAnchor(point: .zero),
                                                              PathAnchor(point: CGPoint(x: 10, y: 10))],
                                                    paint: Paint(hex: "#0C0E14"),
                                                    strokeWidth: 1.7,
                                                    fill: nil)),
                         frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        let offered = MotionProperty.offered(for: path)
        #expect(offered.first { $0.property == .color }?.current == .color("#0C0E14"))
        #expect(offered.first { $0.property == .strokeWidth }?.current == .number(1.7))
    }

    /// One property, one answer. A layer already turning cannot be given a
    /// second rotation, the same way a layer already blurred cannot be given a
    /// second blur.
    @Test func aPropertyAlreadyMovingIsNotOfferedTwice() {
        var layer = Self.shape()
        layer.motions = [Self.rotationMotion()]
        let offered = MotionProperty.offered(for: layer)
        #expect(offered.first { $0.property == .rotation }?.isAlreadyMoving == true)
        #expect(offered.first { $0.property == .opacity }?.isAlreadyMoving == false)
    }

    // MARK: - Curves

    /// Every curve starts where the motion starts and ends where it ends. A
    /// curve that did not would silently move the From and To somebody typed.
    @Test func everyNamedCurveRunsFromNoughtToOne() {
        for curve in EasingCurve.named {
            #expect(abs(curve.value(at: 0) - 0) < 1e-6, "\(curve.title) leaves 0")
            #expect(abs(curve.value(at: 1) - 1) < 1e-6, "\(curve.title) lands on 1")
        }
    }

    @Test func linearIsTheIdentity() {
        #expect(abs(EasingCurve.linear.value(at: 0.25) - 0.25) < 1e-9)
        #expect(abs(EasingCurve.linear.value(at: 0.5) - 0.5) < 1e-9)
    }

    /// Ease out is fast then slow, so it is ahead of linear in the middle;
    /// ease in is the mirror of it and behind. Ease in out is the design
    /// language's own `--ease-standard`, which is fast out and slow in rather
    /// than symmetrical, so it sits between the two.
    @Test func easeOutLeadsAndEaseInTrails() {
        #expect(EasingCurve.easeOut.value(at: 0.5) > 0.5)
        #expect(EasingCurve.easeIn.value(at: 0.5) < 0.5)
        let middle = EasingCurve.easeInOut.value(at: 0.5)
        #expect(middle > EasingCurve.easeIn.value(at: 0.5))
        #expect(middle < EasingCurve.easeOut.value(at: 0.5))
    }

    /// The three curves the design language already had, under the names people
    /// actually use for them (`tokens.css`): `--ease-standard` is Ease in out
    /// and `--ease-decel` is Ease out. This is the mapping the open easing task
    /// asked somebody to settle.
    @Test func theNamedEasesAreTheDesignLanguagesOwnTokens() {
        for tenth in 0...10 {
            let t = Double(tenth) / 10
            #expect(abs(EasingCurve.easeInOut.value(at: t)
                        - EasingCurve.custom(x1: 0.4, y1: 0, x2: 0.2, y2: 1).value(at: t)) < 1e-6)
            #expect(abs(EasingCurve.easeOut.value(at: t)
                        - EasingCurve.custom(x1: 0, y1: 0, x2: 0.2, y2: 1).value(at: t)) < 1e-6)
        }
    }

    /// Back and elastic overshoot on purpose: that is the whole reason they
    /// are on the menu, and a clamp would quietly turn them into ease out.
    @Test func backAndElasticAreAllowedPastTheEnd() {
        let back = (1...19).map { EasingCurve.easeOutBack.value(at: Double($0) / 20) }
        #expect(back.contains { $0 > 1 })
        let elastic = (1...19).map { EasingCurve.easeOutElastic.value(at: Double($0) / 20) }
        #expect(elastic.contains { $0 > 1 })
    }

    /// Steps jump, and between two jumps it does not move at all.
    @Test func stepsHoldsStillBetweenItsJumps() {
        let steps = EasingCurve.steps(4)
        #expect(steps.value(at: 0.1) == steps.value(at: 0.2))
        #expect(steps.value(at: 0.3) > steps.value(at: 0.2))
        #expect(steps.value(at: 1) == 1)
    }

    /// A drawn curve is four numbers, and linear is the one everybody can
    /// check by hand.
    @Test func aDrawnCurveIsSolvedFromItsFourNumbers() {
        let straight = EasingCurve.custom(x1: 0.25, y1: 0.25, x2: 0.75, y2: 0.75)
        for tenth in 0...10 {
            let t = Double(tenth) / 10
            #expect(abs(straight.value(at: t) - t) < 1e-4)
        }
        let standard = EasingCurve.custom(x1: 0.4, y1: 0, x2: 0.2, y2: 1)
        #expect(abs(standard.value(at: 0.5) - EasingCurve.easeInOut.value(at: 0.5)) < 1e-4)
    }

    /// The named list is what every surface offers, in one order, and it is
    /// what the open task about easing settled: one vocabulary, not four.
    @Test func theNamedCurvesAreOneSettledList() {
        #expect(EasingCurve.named.first == .linear)
        let titles = EasingCurve.named.map(\.title)
        #expect(titles == ["Linear", "Ease in out", "Ease in", "Ease out",
                           "Ease in out sine", "Ease out back", "Ease out elastic",
                           "Steps, 4"])
    }

    // MARK: - What the value is at a given millisecond

    @Test func halfWayThroughALinearMotionIsHalfWayBetweenItsValues() {
        let motion = Self.rotationMotion(from: 0, to: 20, over: 1000, repeats: .once)
        #expect(motion.value(atMS: 500, cycleMS: 1000) == .number(10))
    }

    /// Before it starts it is sitting at From, which is what lets one part of
    /// an icon lag behind another.
    @Test func beforeItStartsItSitsAtFrom() {
        let motion = Self.rotationMotion(from: -12, to: 12, start: 300, over: 600, repeats: .once)
        #expect(motion.value(atMS: 0, cycleMS: 900) == .number(-12))
        #expect(motion.value(atMS: 299, cycleMS: 900) == .number(-12))
        #expect(motion.value(atMS: 600, cycleMS: 900) == .number(0))
    }

    /// Once means once: it plays, it stays where it landed, and it does not
    /// come round again however long the preview runs.
    @Test func onceStaysWhereItLanded() {
        let motion = Self.rotationMotion(from: 0, to: 20, over: 1000, repeats: .once)
        #expect(motion.value(atMS: 1000, cycleMS: 1000) == .number(20))
        #expect(motion.value(atMS: 5500, cycleMS: 1000) == .number(20))
        #expect(motion.hasSettled(atMS: 1000, cycleMS: 1000))
        #expect(!motion.hasSettled(atMS: 999, cycleMS: 1000))
    }

    @Test func threeTimesPlaysThreeTimesAndThenStops() {
        let motion = Self.rotationMotion(from: 0, to: 20, over: 1000, repeats: .times(3))
        #expect(motion.value(atMS: 500, cycleMS: 1000) == .number(10))
        #expect(motion.value(atMS: 2500, cycleMS: 1000) == .number(10))
        #expect(!motion.hasSettled(atMS: 2999, cycleMS: 1000))
        #expect(motion.hasSettled(atMS: 3000, cycleMS: 1000))
        #expect(motion.value(atMS: 3500, cycleMS: 1000) == .number(20))
    }

    /// Forever never settles, which is what the preview asks before it decides
    /// whether to keep drawing frames.
    @Test func foreverNeverSettles() {
        let motion = Self.rotationMotion(repeats: .forever)
        #expect(!motion.hasSettled(atMS: 10_000_000, cycleMS: 900))
    }

    /// There and back is the bell: out to To at the half way mark and home to
    /// From by the end of the cycle, so a loop is not a jump cut.
    @Test func thereAndBackReachesToInTheMiddleAndComesHome() {
        let motion = Self.rotationMotion(from: -12, to: 12, over: 900,
                                         repeats: .foreverThereAndBack)
        #expect(motion.value(atMS: 0, cycleMS: 900) == .number(-12))
        #expect(motion.value(atMS: 450, cycleMS: 900) == .number(12))
        #expect(motion.value(atMS: 899, cycleMS: 900) != .number(12))
        // ...and the next cycle starts exactly where the last one ended, so
        // there is no seam to see.
        #expect(motion.value(atMS: 900, cycleMS: 900) == .number(-12))
    }

    /// A motion switched off holds at From however far the clock has run: the
    /// switch keeps every number on the row and stops it moving, which is the
    /// same bargain the eye on an effect strikes.
    @Test func aMotionSwitchedOffDoesNotMove() {
        var motion = Self.rotationMotion(from: -12, to: 12)
        motion.isOn = false
        #expect(motion.value(atMS: 450, cycleMS: 900) == .number(-12))
        #expect(motion.hasSettled(atMS: 0, cycleMS: 900))
    }

    @Test func aPositionMovesOnBothAxesAtOnce() {
        let motion = LayerMotion(property: .position,
                                 from: .point(CGPoint(x: 0, y: 0)),
                                 to: .point(CGPoint(x: 10, y: 20)),
                                 timing: MotionTiming(startMS: 0, durationMS: 100),
                                 curve: .linear, repeats: .once)
        #expect(motion.value(atMS: 50, cycleMS: 100) == .point(CGPoint(x: 5, y: 10)))
    }

    @Test func aColourIsBlendedChannelByChannel() {
        let motion = LayerMotion(property: .color,
                                 from: .color("#000000"), to: .color("#FFFFFF"),
                                 timing: MotionTiming(startMS: 0, durationMS: 100),
                                 curve: .linear, repeats: .once)
        #expect(motion.value(atMS: 50, cycleMS: 100) == .color("#808080"))
    }

    /// A From and a To of different kinds cannot be blended, and the model
    /// says so by standing still rather than by guessing.
    @Test func mismatchedValuesDoNotMove() {
        let motion = LayerMotion(property: .rotation,
                                 from: .number(0), to: .color("#FFFFFF"),
                                 timing: MotionTiming(startMS: 0, durationMS: 100),
                                 curve: .linear, repeats: .once)
        #expect(motion.value(atMS: 50, cycleMS: 100) == .number(0))
    }

    // MARK: - Timing is two numbers, modelled once

    /// The timeline strip carries the same start and duration this panel does,
    /// so they are one type, and a duration of nought would be a division by
    /// nought however it got typed.
    @Test func aDurationIsNeverNought() {
        let timing = MotionTiming(startMS: -50, durationMS: 0)
        #expect(timing.startMS == 0)
        #expect(timing.durationMS >= 1)
        #expect(timing.endMS == timing.startMS + timing.durationMS)
    }

    // MARK: - The whole picture at a moment

    @Test func theCycleIsAsLongAsTheLastThingToFinish() {
        var layer = Self.shape()
        layer.motions = [Self.rotationMotion(start: 0, over: 900),
                         LayerMotion(property: .opacity, from: .number(100), to: .number(0),
                                     timing: MotionTiming(startMS: 200, durationMS: 1000),
                                     curve: .linear, repeats: .forever)]
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [layer])
        #expect(document.motionCycleLengthMS == 1200)
    }

    /// Nothing moving is a cycle nobody has to draw: the preview asks this
    /// before it starts a clock.
    @Test func aDocumentWithNoMotionHasNoCycle() {
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [Self.shape()])
        #expect(!document.hasMotion)
        #expect(document.motionCycleLengthMS == 0)
    }

    @Test func theDocumentAtAMomentWearsWhatTheMotionSays() {
        var layer = Self.shape()
        layer.motions = [Self.rotationMotion(from: 0, to: 90, over: 1000, repeats: .once)]
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [layer])

        let halfWay = document.moved(toMotionTimeMS: 500)
        let turned = halfWay.layer(id: layer.id)
        #expect(abs((turned?.transform.rotation ?? 0) - .pi / 4) < 1e-6)
        // ...and the document itself is untouched, because motion is never
        // baked in: the stored layer is still the one you can drag.
        #expect(document.layer(id: layer.id)?.transform.rotation == 0)
    }

    /// A motion on a layer INSIDE a group moves with the rest of them: the
    /// walk has to reach all the way down or half an icon would animate.
    @Test func aMotionInsideAGroupIsFoundAndApplied() {
        var child = Self.shape()
        child.motions = [LayerMotion(property: .opacity, from: .number(100), to: .number(0),
                                     timing: MotionTiming(startMS: 0, durationMS: 1000),
                                     curve: .linear, repeats: .once)]
        let childID = child.id
        let group = Layer(name: "Icon", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [group])

        #expect(document.motionCycleLengthMS == 1000)
        let faded = document.moved(toMotionTimeMS: 500)
        #expect(abs((faded.layer(id: childID)?.style.opacity ?? 1) - 0.5) < 1e-6)
    }

    @Test func scaleGrowsTheLayerAboutItsOwnMiddle() {
        var layer = Self.shape()
        layer.motions = [LayerMotion(property: .scale, from: .number(100), to: .number(200),
                                     timing: MotionTiming(startMS: 0, durationMS: 1000),
                                     curve: .linear, repeats: .once)]
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [layer])
        let grown = document.moved(toMotionTimeMS: 1000).layer(id: layer.id)
        #expect(grown?.frame.width == 80)
        #expect(grown?.frame.midX == layer.frame.midX)
        #expect(grown?.frame.midY == layer.frame.midY)
    }

    @Test func aColourMotionRepaintsTheShape() {
        var layer = Self.shape()
        layer.motions = [LayerMotion(property: .color,
                                     from: .color("#000000"), to: .color("#FFFFFF"),
                                     timing: MotionTiming(startMS: 0, durationMS: 1000),
                                     curve: .linear, repeats: .once)]
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [layer])
        let lit = document.moved(toMotionTimeMS: 1000).layer(id: layer.id)
        // A box's colour is the colour of its inside, which is what the paint
        // bucket means by the same gesture (`Fill.filled`), so the property
        // the menu read and the thing the motion changed are one colour.
        #expect(lit?.annotation?.fillColorHex == "#FFFFFF")
        #expect(lit.map { MotionProperty.color.current(of: $0) } == .color("#FFFFFF"))
    }

    /// The preview stops on its own once nothing is moving any more, rather
    /// than burning frames for ever on an icon that has finished.
    @Test func theDocumentSaysWhenEverythingHasFinished() {
        var layer = Self.shape()
        layer.motions = [Self.rotationMotion(from: 0, to: 20, over: 400, repeats: .once)]
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [layer])
        #expect(!document.motionHasSettled(atMS: 399))
        #expect(document.motionHasSettled(atMS: 400))
    }

    // MARK: - What the row says about itself

    /// The summary is the row. It has to be readable straight back as a
    /// sentence about the drawing, not as a dump of the fields.
    @Test func theRowReadsBackAsASentence() {
        let motion = Self.rotationMotion(from: -12, to: 12, over: 900)
        #expect(motion.summary == "-12° → 12° over 0.9s")
    }

    @Test func eachKindOfValueIsWrittenInItsOwnUnits() {
        let opacity = LayerMotion(property: .opacity, from: .number(100), to: .number(0),
                                  timing: MotionTiming(startMS: 0, durationMS: 600),
                                  curve: .linear, repeats: .once)
        #expect(opacity.summary == "100% → 0% over 0.6s")

        let position = LayerMotion(property: .position,
                                   from: .point(CGPoint(x: 6, y: 4)),
                                   to: .point(CGPoint(x: 6, y: -4)),
                                   timing: MotionTiming(startMS: 0, durationMS: 500),
                                   curve: .linear, repeats: .once)
        #expect(position.summary == "6, 4 → 6, -4 over 0.5s")

        let stroke = LayerMotion(property: .strokeWidth, from: .number(1.7), to: .number(3),
                                 timing: MotionTiming(startMS: 0, durationMS: 250),
                                 curve: .linear, repeats: .once)
        #expect(stroke.summary == "1.7 pt → 3 pt over 0.25s")
    }

    /// A motion that does not start at nought says so, because "over 0.9s"
    /// alone would be a summary that leaves out the lag.
    @Test func aLateStartIsSaidOutLoud() {
        let motion = Self.rotationMotion(start: 300, over: 600)
        #expect(motion.summary.contains("after 0.3s"))
    }

    // MARK: - What a fresh motion starts as

    /// Adding a motion must MOVE something. A row that arrives reading
    /// "0° → 0°" is a feature that looks broken on the first press.
    @Test func afreshMotionAlreadyMovesSomething() {
        let layer = Self.shape()
        for property in MotionProperty.offered(for: layer).map(\.property) where property != .color {
            let motion = LayerMotion.starting(property, on: layer)
            #expect(motion.from != motion.to, "\(property) arrives standing still")
            #expect(motion.timing.durationMS > 0)
        }
    }

    @Test func afreshRotationIsTheSwingTheAcceptanceAsksFor() {
        let motion = LayerMotion.starting(.rotation, on: Self.shape())
        #expect(motion.summary == "-12° → 12° over 0.9s")
        #expect(motion.repeats == .foreverThereAndBack)
    }

    /// ...and it swings about the angle the shape is ALREADY at, so a shape
    /// somebody turned on purpose does not jerk upright the moment it is told
    /// to move.
    @Test func afreshRotationSwingsAboutWhereTheShapeAlreadyIs() {
        let turned = Self.shape(rotation: .pi / 2)
        let motion = LayerMotion.starting(.rotation, on: turned)
        #expect(motion.from == .number(78))
        #expect(motion.to == .number(102))
    }

    /// A layer that is already invisible fades IN rather than fading from
    /// nothing to nothing.
    @Test func afreshOpacityOnAnInvisibleLayerBringsItBack() {
        let motion = LayerMotion.starting(.opacity, on: Self.shape(opacity: 0))
        #expect(motion.from == .number(0))
        #expect(motion.to == .number(100))
    }

    /// Position and scale on one layer give the same box whichever order the
    /// two motions are in: a position that set the top-left outright would be
    /// pointing at a corner scale had just moved.
    @Test func positionAndScaleTogetherDoNotDependOnTheirOrder() {
        let base = Self.shape()
        let move = LayerMotion(property: .position,
                               from: .point(base.frame.origin),
                               to: .point(CGPoint(x: base.frame.origin.x + 20,
                                                  y: base.frame.origin.y)),
                               timing: MotionTiming(startMS: 0, durationMS: 100),
                               curve: .linear, repeats: .once)
        let grow = LayerMotion(property: .scale, from: .number(100), to: .number(200),
                               timing: MotionTiming(startMS: 0, durationMS: 100),
                               curve: .linear, repeats: .once)
        var oneWay = base
        oneWay.motions = [move, grow]
        var theOther = base
        theOther.motions = [grow, move]
        let cycle = 100
        #expect(oneWay.moved(toMotionTimeMS: 100, cycleMS: cycle).frame
                == theOther.moved(toMotionTimeMS: 100, cycleMS: cycle).frame)
    }

    // MARK: - Codable, Sendable, and nothing from AppKit

    @Test func aDocumentWithMotionSurvivesBeingWrittenAndRead() throws {
        var layer = Self.shape()
        layer.motions = [Self.rotationMotion(curve: .custom(x1: 0.34, y1: 1.4, x2: 0.5, y2: 1),
                                             repeats: .times(3)),
                         LayerMotion(property: .color, from: .color("#000000"),
                                     to: .color("#FFFFFF"),
                                     timing: MotionTiming(startMS: 100, durationMS: 400),
                                     curve: .steps(4), repeats: .foreverThereAndBack)]
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [layer])

        let data = try JSONEncoder().encode(document)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.layer(id: layer.id)?.motions == layer.motions)
    }

    /// Every document ever written was written before motion existed, and has
    /// to come back exactly as it went in.
    @Test func aDocumentWrittenBeforeMotionExistedReadsBackWithNone() throws {
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [Self.shape()])
        let data = try JSONEncoder().encode(document)
        #expect(!String(decoding: data, as: UTF8.self).contains("motions"))
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.layers.first?.motions == nil)
        #expect(!back.hasMotion)
    }

    /// Copying a layer copies what it does, not just what it looks like.
    @Test func aDuplicatedLayerKeepsItsMotions() {
        var layer = Self.shape()
        layer.motions = [Self.rotationMotion()]
        #expect(layer.duplicated().motions == layer.motions)
        #expect(layer.reidentified().motions == layer.motions)
    }
}
