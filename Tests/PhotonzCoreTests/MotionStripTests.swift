import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The timing strip: one lap of the motion, a bar for every moving property.
///
/// Written before the strip, which is the rule for `PhotonzCore`. Everything
/// the bar across the bottom of the window decides is settled here, in a module
/// that has never heard of a window: what lanes there are and what layer each
/// belongs to, how long one lap is and where the ruler's ticks fall, what a
/// drag does to a start and to a duration, what it snaps to, and what number
/// the gap between two bars reads.
@Suite("The timing strip")
struct MotionStripTests {

    // MARK: - Fixtures

    static func shape(_ name: String, at origin: CGPoint = .zero) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
              frame: CGRect(origin: origin, size: CGSize(width: 40, height: 40)))
    }

    static func rotation(start: Int, over: Int, on: Bool = true) -> LayerMotion {
        LayerMotion(property: .rotation, from: .number(-12), to: .number(12),
                    timing: MotionTiming(startMS: start, durationMS: over), isOn: on)
    }

    static func opacity(start: Int, over: Int) -> LayerMotion {
        LayerMotion(property: .opacity, from: .number(100), to: .number(0),
                    timing: MotionTiming(startMS: start, durationMS: over))
    }

    /// The page's own example: a bell that swings, and a knob under it that
    /// swings the same way a tenth of a second later.
    static func bellAndKnob(knobStart: Int = 90) -> PhotonzDocument {
        var bell = shape("Bell body")
        bell.motions = [rotation(start: 0, over: 900)]
        var knob = shape("Knob", at: CGPoint(x: 10, y: 40))
        knob.motions = [rotation(start: knobStart, over: 900)]
        return PhotonzDocument(canvasSize: CGSize(width: 240, height: 240), layers: [bell, knob])
    }

    // MARK: - What lanes there are

    @Test("A document with nothing moving has no lanes at all, so there is no strip to show")
    func stillDocumentHasNoLanes() {
        let document = PhotonzDocument(canvasSize: CGSize(width: 240, height: 240),
                                       layers: [Self.shape("Bell")])
        #expect(document.motionStrip().isEmpty)
        #expect(!document.hasMotion)
    }

    @Test("Every moving property is a lane, grouped under the layer it belongs to")
    func lanesAreGroupedByLayer() {
        var bell = Self.shape("Bell body")
        bell.motions = [Self.rotation(start: 0, over: 900), Self.opacity(start: 100, over: 300)]
        var knob = Self.shape("Knob")
        knob.motions = [Self.rotation(start: 90, over: 900)]
        let document = PhotonzDocument(canvasSize: CGSize(width: 240, height: 240),
                                       layers: [bell, knob])

        let groups = document.motionStrip()
        #expect(groups.count == 2)
        // Topmost first, the way the layers panel reads it: the knob is the
        // last layer in the document, so it is the one drawn on top
        // (`LayerCompositing.swift`).
        #expect(groups.map(\.layerName) == ["Knob", "Bell body"])
        #expect(groups[1].lanes.map(\.title) == ["Rotation", "Opacity"])
        #expect(groups[0].lanes.map(\.title) == ["Rotation"])
        #expect(groups[1].lanes[0].layerID == bell.id)
        #expect(groups[0].lanes[0].motionID == knob.motions![0].id)
    }

    @Test("A layer with nothing moving is not in the strip, even between two that are")
    func stillLayersAreLeftOut() {
        var bell = Self.shape("Bell body")
        bell.motions = [Self.rotation(start: 0, over: 900)]
        let clapper = Self.shape("Clapper")
        var knob = Self.shape("Knob")
        knob.motions = [Self.rotation(start: 90, over: 900)]
        let document = PhotonzDocument(canvasSize: CGSize(width: 240, height: 240),
                                       layers: [bell, clapper, knob])
        #expect(document.motionStrip().map(\.layerName) == ["Knob", "Bell body"])
    }

    @Test("A motion switched off keeps its lane, drawn as switched off")
    func switchedOffKeepsItsLane() {
        var bell = Self.shape("Bell body")
        bell.motions = [Self.rotation(start: 0, over: 900, on: false)]
        let document = PhotonzDocument(canvasSize: CGSize(width: 240, height: 240), layers: [bell])
        let lanes = document.motionStrip().flatMap(\.lanes)
        #expect(lanes.count == 1)
        #expect(!lanes[0].isOn)
    }

    @Test("A motion inside a group is found, with the name of the layer it is really on")
    func motionInsideAGroupIsFound() {
        var knob = Self.shape("Knob")
        knob.motions = [Self.rotation(start: 90, over: 900)]
        var group = Layer(name: "Bell", content: .group(GroupContent(children: [knob])),
                          frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        group.motions = [Self.rotation(start: 0, over: 900)]
        let document = PhotonzDocument(canvasSize: CGSize(width: 240, height: 240), layers: [group])

        let groups = document.motionStrip()
        #expect(groups.map(\.layerName) == ["Bell", "Knob"])
    }

    // MARK: - How long one lap is

    @Test("With nothing said, one lap is as long as the last thing to finish")
    func cycleFollowsTheLongestMotion() {
        var bell = Self.shape("Bell body")
        bell.motions = [Self.rotation(start: 0, over: 900), Self.opacity(start: 100, over: 300)]
        let document = PhotonzDocument(canvasSize: CGSize(width: 240, height: 240), layers: [bell])
        #expect(document.motionCycleMS == nil)
        #expect(document.motionCycleLengthMS == 900)
        #expect(document.motionCycleIsAutomatic)
    }

    @Test("A lap length written down holds, and a bar is then allowed to run past it")
    func aWrittenCycleHolds() {
        var document = Self.bellAndKnob(knobStart: 90)
        document.motionCycleMS = 900
        #expect(document.motionCycleLengthMS == 900)
        #expect(!document.motionCycleIsAutomatic)
        // The knob finishes at 990, which is PAST the end of the lap: the whole
        // point of the dashed line, and what a lag in something that loops IS.
        let knob = document.motionStrip()[0].lanes[0]
        #expect(knob.timing.endMS == 990)
        #expect(knob.timing.endMS > document.motionCycleLengthMS)
    }

    @Test("Clearing the written lap length puts it back to following the longest motion")
    func clearingTheCycleGoesBackToAutomatic() {
        var document = Self.bellAndKnob(knobStart: 90)
        document.motionCycleMS = 1500
        #expect(document.motionCycleLengthMS == 1500)
        document.motionCycleMS = nil
        #expect(document.motionCycleLengthMS == 990)
    }

    @Test("A lap can never be nought milliseconds long, whatever is typed at it")
    func cycleIsNeverNought() {
        var document = Self.bellAndKnob()
        document.motionCycleMS = 0
        #expect(document.motionCycleLengthMS >= 1)
        document.motionCycleMS = -400
        #expect(document.motionCycleLengthMS >= 1)
    }

    @Test("A document saved before laps had a length reads back with none written, and one written survives the round trip")
    func cycleSurvivesTheRoundTrip() throws {
        var document = Self.bellAndKnob()
        let plain = try JSONDecoder().decode(
            PhotonzDocument.self, from: try JSONEncoder().encode(document))
        #expect(plain.motionCycleMS == nil)

        document.motionCycleMS = 1200
        let written = try JSONDecoder().decode(
            PhotonzDocument.self, from: try JSONEncoder().encode(document))
        #expect(written.motionCycleMS == 1200)
    }

    // MARK: - The ruler

    @Test("The ruler shows one whole lap with room to spare, so an overrun has somewhere to be drawn")
    func rulerLeavesRoomPastTheLap() {
        let ruler = MotionStripRuler(cycleMS: 900)
        #expect(ruler.spanMS > 900)
        // The dashed repeats line is inside the ruler rather than on its edge.
        #expect(ruler.fraction(ofMS: 900) < 1)
        #expect(ruler.fraction(ofMS: 900) > 0.6)
    }

    @Test("Nought is the left edge and the whole span is the right edge")
    func rulerEnds() {
        let ruler = MotionStripRuler(cycleMS: 900)
        #expect(ruler.fraction(ofMS: 0) == 0)
        #expect(abs(ruler.fraction(ofMS: ruler.spanMS) - 1) < 0.0001)
    }

    @Test("A millisecond and a fraction of the width say the same thing in both directions")
    func rulerRoundTrips() {
        let ruler = MotionStripRuler(cycleMS: 900)
        for ms in [0, 90, 450, 900, 1000] {
            #expect(ruler.ms(atFraction: ruler.fraction(ofMS: Double(ms))) == Double(ms))
        }
    }

    @Test("The ticks are numbers a person would say, and the last one carries the unit")
    func ticksAreRoundNumbers() {
        let ruler = MotionStripRuler(cycleMS: 900)
        let ticks = ruler.ticks
        #expect(ticks.first?.ms == 0)
        #expect(ticks.count >= 4)
        #expect(ticks.count <= 9)
        // Evenly spaced, and every one of them a round number of milliseconds.
        let step = ticks[1].ms - ticks[0].ms
        #expect(step.truncatingRemainder(dividingBy: 10) == 0)
        for (index, tick) in ticks.enumerated() {
            #expect(abs(tick.ms - Double(index) * step) < 0.001)
        }
        #expect(ticks.last?.label.hasSuffix("ms") == true)
        #expect(ticks.dropLast().allSatisfy { !$0.label.contains("ms") })
    }

    @Test("A very short lap and a very long one both get a readable ruler")
    func rulerCopesWithEveryLength() {
        for cycle in [1, 60, 120, 900, 5000, 60_000] {
            let ruler = MotionStripRuler(cycleMS: cycle)
            #expect(ruler.spanMS > Double(cycle))
            #expect(ruler.ticks.count >= 2)
            #expect(ruler.ticks.count <= 9)
        }
    }

    // MARK: - Dragging a bar

    @Test("Dragging a bar sideways moves when it starts and leaves how long it takes alone")
    func draggingTheBodyMovesTheStart() {
        let timing = MotionTiming(startMS: 0, durationMS: 900)
        let moved = MotionStripDrag(grab: .body, timing: timing).moved(byMS: 90)
        #expect(moved.startMS == 90)
        #expect(moved.durationMS == 900)
    }

    @Test("Dragging the right hand end changes how long it takes and leaves the start alone")
    func draggingTheRightEndChangesTheDuration() {
        let timing = MotionTiming(startMS: 100, durationMS: 900)
        let moved = MotionStripDrag(grab: .end, timing: timing).moved(byMS: 200)
        #expect(moved.startMS == 100)
        #expect(moved.durationMS == 1100)
    }

    @Test("Dragging the left hand end moves the start and keeps the finish where it was")
    func draggingTheLeftEndKeepsTheFinish() {
        let timing = MotionTiming(startMS: 100, durationMS: 900)
        let moved = MotionStripDrag(grab: .start, timing: timing).moved(byMS: 150)
        #expect(moved.startMS == 250)
        #expect(moved.endMS == 1000)
        #expect(moved.durationMS == 750)
    }

    @Test("A bar never starts before the top of the lap, however far left it is pushed")
    func aBarCannotStartBeforeTheTop() {
        let timing = MotionTiming(startMS: 100, durationMS: 900)
        let moved = MotionStripDrag(grab: .body, timing: timing).moved(byMS: -400)
        #expect(moved.startMS == 0)
        #expect(moved.durationMS == 900)
    }

    @Test("A bar can never be squeezed away to nothing")
    func aBarKeepsAMinimumLength() {
        let timing = MotionTiming(startMS: 100, durationMS: 900)
        let squeezed = MotionStripDrag(grab: .end, timing: timing).moved(byMS: -5000)
        #expect(squeezed.durationMS >= MotionStripDrag.shortestMS)
        let fromTheLeft = MotionStripDrag(grab: .start, timing: timing).moved(byMS: 5000)
        #expect(fromTheLeft.durationMS >= MotionStripDrag.shortestMS)
        #expect(fromTheLeft.endMS == 1000)
    }

    @Test("A drag is worked out from where it started, never from where it got to, so it cannot creep")
    func dragIsAbsolute() {
        let drag = MotionStripDrag(grab: .body, timing: MotionTiming(startMS: 0, durationMS: 900))
        // The same delta asked twice gives the same answer both times: the drag
        // holds the timing the bar had when it was GRABBED.
        #expect(drag.moved(byMS: 90).startMS == 90)
        #expect(drag.moved(byMS: 90).startMS == 90)
        #expect(drag.moved(byMS: 0).startMS == 0)
    }

    // MARK: - What a drag catches on

    @Test("A start dropped near another bar's start catches on it exactly")
    func aStartSnapsToAnotherBarsStart() {
        let drag = MotionStripDrag(grab: .body, timing: MotionTiming(startMS: 0, durationMS: 900),
                                   others: [MotionStripEdge(ms: 300, name: "Knob", isStart: true)],
                                   snapWithinMS: 8)
        let landed = drag.landing(byMS: 296)
        #expect(landed.timing.startMS == 300)
        #expect(landed.snappedTo?.name == "Knob")
    }

    @Test("A bar dropped well clear of everything catches on nothing and keeps the number you dragged it to")
    func noSnapWhenNothingIsNear() {
        let drag = MotionStripDrag(grab: .body, timing: MotionTiming(startMS: 0, durationMS: 900),
                                   others: [MotionStripEdge(ms: 300, name: "Knob", isStart: true)],
                                   snapWithinMS: 8)
        let landed = drag.landing(byMS: 150)
        #expect(landed.timing.startMS == 150)
        #expect(landed.snappedTo == nil)
    }

    @Test("The top of the lap is something to catch on too, so nought is easy to get back to")
    func theTopOfTheLapSnaps() {
        let drag = MotionStripDrag(grab: .body, timing: MotionTiming(startMS: 90, durationMS: 900),
                                   others: [MotionStripEdge(ms: 0, name: "the start", isStart: true)],
                                   snapWithinMS: 8)
        #expect(drag.landing(byMS: -85).timing.startMS == 0)
    }

    @Test("Ninety milliseconds of lag survives the catching, which is the whole job")
    func snappingDoesNotSwallowASmallLag() {
        // The bell starts at 0 and lasts 900. Pushing the knob to 90 has to
        // STAY at 90 rather than being dragged back onto the bell.
        let drag = MotionStripDrag(grab: .body, timing: MotionTiming(startMS: 0, durationMS: 900),
                                   others: [MotionStripEdge(ms: 0, name: "Bell body", isStart: true),
                                            MotionStripEdge(ms: 900, name: "Bell body", isStart: false)],
                                   snapWithinMS: 8)
        let landed = drag.landing(byMS: 90)
        #expect(landed.timing.startMS == 90)
        #expect(landed.snappedTo == nil)
    }

    // MARK: - What a drag does to the lap

    @Test("A bar dragged past the end of the lap holds the lap, so it really does overrun")
    func draggingPastTheEndHoldsTheLap() {
        // The bell is 0 to 900 and the knob was pushed to 90 to 990, so the
        // longest motion now ends at 990. Letting the lap grow to 990 would
        // mean nothing had overrun anything.
        #expect(MotionStripCycle.after(drag: 900, automatic: 990, current: nil) == 900)
    }

    @Test("A bar dragged back inside the lap hands it back to following the longest motion")
    func draggingBackInsideReleasesTheLap() {
        #expect(MotionStripCycle.after(drag: 900, automatic: 900, current: 900) == nil)
    }

    @Test("A drag that shortens the longest motion lets the lap shrink with it")
    func shorteningShrinksTheLap() {
        #expect(MotionStripCycle.after(drag: 900, automatic: 600, current: nil) == nil)
    }

    @Test("A lap somebody typed is not quietly thrown away by a drag that fits inside it")
    func aTypedLapSurvivesADrag() {
        #expect(MotionStripCycle.after(drag: 1500, automatic: 900, current: 1500) == 1500)
    }

    @Test("A typed lap is held too when a drag runs past it")
    func aTypedLapIsAlsoHeld() {
        #expect(MotionStripCycle.after(drag: 1500, automatic: 1600, current: 1500) == 1500)
    }

    @Test("The whole rule, played out on the page's own example")
    func theWholeRuleOnTheBellAndTheKnob() {
        var document = Self.bellAndKnob(knobStart: 0)
        #expect(document.motionCycleLengthMS == 900)

        // Push the knob 90 ms late, the way the strip does it.
        let held = document.motionCycleLengthMS
        let knob = document.layers[1]
        document.updateLayer(id: knob.id) { $0.motions?[0].timing.setStart(90) }
        document.motionCycleMS = MotionStripCycle.after(
            drag: held, automatic: document.automaticMotionCycleLengthMS,
            current: document.motionCycleMS)
        #expect(document.motionCycleLengthMS == 900)
        #expect(document.motionStrip()[0].lanes[0].timing.endMS == 990)

        // ...and push it back. The held number goes with it.
        let held2 = document.motionCycleLengthMS
        document.updateLayer(id: knob.id) { $0.motions?[0].timing.setStart(0) }
        document.motionCycleMS = MotionStripCycle.after(
            drag: held2, automatic: document.automaticMotionCycleLengthMS,
            current: document.motionCycleMS)
        #expect(document.motionCycleIsAutomatic)
        #expect(document.motionCycleLengthMS == 900)
    }

    // MARK: - The number between two bars

    @Test("While a bar is dragged the gap to the nearest other bar is a number with a name on it")
    func theGapNamesWhatItIsMeasuredFrom() {
        let others = [MotionStripEdge(ms: 0, name: "Bell body", isStart: true),
                      MotionStripEdge(ms: 900, name: "Bell body", isStart: false)]
        let gap = MotionStripGap(startMS: 90, others: others)
        #expect(gap?.ms == 90)
        #expect(gap?.fromMS == 0)
        #expect(gap?.name == "Bell body")
        #expect(gap?.reading == "90 ms after Bell body")
    }

    @Test("A bar dragged in front of the thing it is measured against reads 'before'")
    func aGapCanBeNegative() {
        let gap = MotionStripGap(startMS: 0, others: [MotionStripEdge(ms: 120, name: "Bell body",
                                                                     isStart: true)])
        #expect(gap?.ms == -120)
        #expect(gap?.reading == "120 ms before Bell body")
    }

    @Test("Two bars starting together read as together rather than as nought")
    func noGapReadsAsTogether() {
        let gap = MotionStripGap(startMS: 0, others: [MotionStripEdge(ms: 0, name: "Bell body",
                                                                     isStart: true)])
        #expect(gap?.ms == 0)
        #expect(gap?.reading == "together with Bell body")
    }

    @Test("The one bar in the document has nothing to be measured against, so no number is drawn")
    func aLoneBarHasNoGap() {
        #expect(MotionStripGap(startMS: 90, others: []) == nil)
    }

    @Test("The gap is measured from the NEAREST other edge, not from whichever is first")
    func theGapTakesTheNearestEdge() {
        let others = [MotionStripEdge(ms: 0, name: "Bell body", isStart: true),
                      MotionStripEdge(ms: 600, name: "Clapper", isStart: true)]
        #expect(MotionStripGap(startMS: 560, others: others)?.name == "Clapper")
        #expect(MotionStripGap(startMS: 120, others: others)?.name == "Bell body")
    }

    // MARK: - The edges a drag has to know about

    @Test("The edges offered to a drag are every OTHER bar's two ends, plus the top of the lap")
    func edgesComeFromEveryOtherBar() {
        let document = Self.bellAndKnob(knobStart: 90)
        let knob = document.motionStrip()[0].lanes[0]
        let edges = document.motionStripEdges(excluding: knob.motionID)
        #expect(edges.contains { $0.ms == 0 && $0.name == "Bell body" })
        #expect(edges.contains { $0.ms == 900 && $0.name == "Bell body" })
        // Its own two ends are not in there: a bar cannot catch on itself.
        #expect(!edges.contains { $0.ms == 90 })
        #expect(!edges.contains { $0.ms == 990 })
    }

    // MARK: - What the row says while the strip is put away

    @Test("The row names the layer you have picked, what is moving on it, and how long a lap is")
    func theRowNamesThePickedLayer() {
        let document = Self.bellAndKnob()
        let bell = document.layers[0]
        #expect(MotionStripSummary.text(groups: document.motionStrip(),
                                        selectedLayerID: bell.id,
                                        cycleMS: 900) == "Bell body · Rotation · 900 ms")
    }

    @Test("Two properties on the picked layer are both named")
    func twoPropertiesAreBothNamed() {
        var bell = Self.shape("Bell body")
        bell.motions = [Self.rotation(start: 0, over: 900), Self.opacity(start: 100, over: 300)]
        let document = PhotonzDocument(canvasSize: CGSize(width: 240, height: 240), layers: [bell])
        #expect(MotionStripSummary.text(groups: document.motionStrip(),
                                        selectedLayerID: bell.id,
                                        cycleMS: 900) == "Bell body · Rotation, Opacity · 900 ms")
    }

    @Test("Past two properties the row counts the rest rather than growing a list nobody reads")
    func manyPropertiesAreCounted() {
        var bell = Self.shape("Bell body")
        bell.motions = [Self.rotation(start: 0, over: 900),
                        Self.opacity(start: 100, over: 300),
                        LayerMotion(property: .scale, from: .number(1), to: .number(2),
                                    timing: MotionTiming(startMS: 0, durationMS: 200))]
        let document = PhotonzDocument(canvasSize: CGSize(width: 240, height: 240), layers: [bell])
        #expect(MotionStripSummary.text(groups: document.motionStrip(),
                                        selectedLayerID: bell.id,
                                        cycleMS: 900) == "Bell body · Rotation and 2 more · 900 ms")
    }

    @Test("With one thing moving and nothing picked, the row still names that one thing")
    func theLoneMoverIsNamedWithNothingPicked() {
        var bell = Self.shape("Bell body")
        bell.motions = [Self.rotation(start: 0, over: 900)]
        let document = PhotonzDocument(canvasSize: CGSize(width: 240, height: 240), layers: [bell])
        #expect(MotionStripSummary.text(groups: document.motionStrip(),
                                        selectedLayerID: nil,
                                        cycleMS: 900) == "Bell body · Rotation · 900 ms")
    }

    @Test("A layer that is picked but does not move cannot speak for the strip, so the row counts")
    func aStillPickedLayerFallsBackToTheCount() {
        var document = Self.bellAndKnob()
        document.layers.append(Self.shape("Rim"))
        let rim = document.layers[2]
        #expect(MotionStripSummary.text(groups: document.motionStrip(),
                                        selectedLayerID: rim.id,
                                        cycleMS: 900) == "2 layers moving · 900 ms")
    }

    @Test("With several movers and nothing picked, the row says how many are moving")
    func severalMoversAreCounted() {
        let document = Self.bellAndKnob()
        #expect(MotionStripSummary.text(groups: document.motionStrip(),
                                        selectedLayerID: nil,
                                        cycleMS: 900) == "2 layers moving · 900 ms")
    }

    @Test("Nothing moving has nothing to say, and there is no row to say it on")
    func nothingMovingSaysNothing() {
        #expect(MotionStripSummary.text(groups: [], selectedLayerID: nil, cycleMS: 900).isEmpty)
    }

    @Test("The lap in the row is the lap the ruler was drawn against")
    func theLapIsTheOneOnTheRuler() {
        let document = Self.bellAndKnob()
        let bell = document.layers[0]
        #expect(MotionStripSummary.text(groups: document.motionStrip(),
                                        selectedLayerID: bell.id,
                                        cycleMS: 1200).hasSuffix("1200 ms"))
    }
}
