import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// D14: a callout never covers what it is talking about. These pin the
/// placement model (where the readout sits) and the planner (which side it
/// picks), both pure geometry in PhotonzCore.
struct MeasureLabelPlacementTests {

    /// A horizontal caliper 200 px wide with its head 40 px below the feet.
    private func caliper(headOffset: CGFloat = 40) -> MeasureContent {
        MeasureContent(start: CGPoint(x: 100, y: 300), end: CGPoint(x: 300, y: 300),
                       headOffset: headOffset, mode: .horizontal)
    }

    /// A vertical alignment guide at x = 100 running y 200…400, checking three
    /// left edges, one of which is `outlier` px to the right of the others.
    private func alignment(outlier: CGFloat = 5) -> MeasureContent {
        var m = MeasureContent(start: CGPoint(x: 100, y: 200), end: CGPoint(x: 100, y: 400),
                               headOffset: 0, mode: .vertical)
        m.alignment = AlignmentCheck(items: [
            AlignmentItem(edge: 100, spanStart: 200, spanEnd: 260),
            AlignmentItem(edge: 100 + outlier, spanStart: 270, spanEnd: 330),
            AlignmentItem(edge: 100, spanStart: 340, spanEnd: 400),
        ], tolerance: 1)
        return m
    }

    private let chip = CGSize(width: 90, height: 34)

    // MARK: - The placement model

    @Test func onLineKeepsTheReadoutOnTheAnchor() {
        var m = caliper()
        m.labelPlacement = .onLine
        #expect(m.labelPosition(chipSize: chip) == m.labelAnchor)
    }

    @Test func afterEndPutsTheChipEntirelyPastThePositiveEnd() {
        var m = caliper()
        m.labelPlacement = .afterEnd
        let rect = m.labelRect(chipSize: chip)
        // Fully clear of the caliper's own span, in the +x direction.
        #expect(rect.minX > 300)
        // Still centred on the head line, so it reads as its continuation.
        #expect(rect.midY == m.labelAnchor.y)
    }

    @Test func beforeStartMirrorsAfterEnd() {
        var m = caliper()
        m.labelPlacement = .beforeStart
        #expect(m.labelRect(chipSize: chip).maxX < 100)
    }

    /// The inner edge of an end-placed chip lands the same distance past the
    /// end whatever size the chip is — a bigger readout grows outward, so the
    /// clearance can never go stale.
    @Test func endPlacementClearanceIsIndependentOfChipSize() {
        var m = caliper()
        m.labelPlacement = .afterEnd
        let small = m.labelRect(chipSize: CGSize(width: 40, height: 20)).minX
        let large = m.labelRect(chipSize: CGSize(width: 200, height: 60)).minX
        #expect(abs(small - large) < 0.001)
    }

    @Test func clearPushesPerpendicularPastTheFurthestCheckedEdge() {
        var m = alignment(outlier: 30)
        m.labelPlacement = .clearPositive
        let rect = m.labelRect(chipSize: chip)
        // Past the outlier's edge (x = 130), not just past the guide (x = 100).
        #expect(rect.minX > 130)
    }

    @Test func clearNeverPullsAChipInTowardWhatItMeasures() {
        var m = caliper(headOffset: 40)
        m.labelPlacement = .clearPositive
        // The head already stands 40 px clear: nothing to gain, nothing moves.
        #expect(m.labelPosition(chipSize: chip) == m.labelAnchor)
    }

    @Test func clearRescuesAChipWhoseHeadSitsOnTheMeasuredLine() {
        var m = caliper(headOffset: 4)
        m.labelPlacement = .clearPositive
        let rect = m.labelRect(chipSize: chip)
        #expect(rect.minY > 300)
    }

    @Test func nudgeShiftsAlongTheAxisOnly() {
        var m = caliper()
        m.labelPlacement = .onLine
        m.labelNudge = 25
        let p = m.labelPosition(chipSize: chip)
        #expect(p.x == m.labelAnchor.x + 25)
        #expect(p.y == m.labelAnchor.y)
    }

    // MARK: - What a measurement is describing

    @Test func aCaliperSubjectIsTheLineBetweenItsFeet() {
        let rects = caliper().subjectRects
        #expect(rects.count == 1)
        #expect(rects[0].minX <= 100)
        #expect(rects[0].maxX >= 300)
        #expect(rects[0].contains(CGPoint(x: 200, y: 300)))
    }

    @Test func anAlignmentSubjectCoversEveryCheckedRunAndReachesTheOutlier() {
        let rects = alignment(outlier: 30).subjectRects
        #expect(rects.count == 3)
        // Every checked run is protected…
        #expect(rects.contains { $0.contains(CGPoint(x: 100, y: 230)) })
        #expect(rects.contains { $0.contains(CGPoint(x: 100, y: 370)) })
        // …and the outlier's real edge, out at x = 130, is inside its own rect.
        #expect(rects.contains { $0.contains(CGPoint(x: 130, y: 300)) })
    }

    // MARK: - What a hand-drawn caliper describes

    /// Two short elements either side of a caliper drawn through their middle,
    /// head 10 px below the line: nowhere on the line is clear, so the number
    /// steps down past both elements, and the plan carries the reach it took.
    @Test func aCaliperBetweenTwoShortElementsDropsItsNumberBelowThem() {
        // The elements reach over the caliper's ends, so the chip cannot sit
        // between them either.
        let m = caliper(headOffset: 10)
        let left = CGRect(x: 0, y: 270, width: 180, height: 60)
        let right = CGRect(x: 220, y: 270, width: 280, height: 60)
        let plan = MeasureLabelPlanner.plan(for: m, canvas: CGSize(width: 500, height: 600),
                                            describing: [left, right])
        #expect(plan.placement == .clearPositive)
        #expect(plan.crossReach == 30)
        var placed = m
        placed.apply(plan)
        let rect = placed.labelRect(chipSize: m.estimatedLabelSize)
        #expect(rect.minY >= 330, "\(rect)")
        #expect(!rect.intersects(left))
        #expect(!rect.intersects(right))
    }

    /// The same, drawn between two tall columns: clearing them would carry the
    /// number hundreds of pixels sideways, so it stays where it always has.
    @Test func aBoxedInCaliperKeepsTheClassicSpot() {
        // The columns reach over the caliper's ends, leaving a 40 px slot no
        // chip fits in, and run the full height of the picture.
        let m = caliper(headOffset: 10)
        let left = CGRect(x: 0, y: 0, width: 180, height: 600)
        let right = CGRect(x: 220, y: 0, width: 280, height: 600)
        let plan = MeasureLabelPlanner.plan(for: m, canvas: CGSize(width: 500, height: 600),
                                            describing: [left, right])
        #expect(plan.placement == .onLine)
        #expect(plan.nudge == 0)
        #expect(plan.crossReach == 0)
    }

    /// A reach the planner did not take is not stored, so an ordinary caliper
    /// draws exactly as it did before the field existed.
    @Test func aClearCaliperCarriesNoReach() {
        let plan = MeasureLabelPlanner.plan(for: caliper(), canvas: CGSize(width: 800, height: 800))
        #expect(plan.placement == .onLine)
        #expect(plan.crossReach == 0)
    }

    // MARK: - How far a number may travel to find whitespace

    /// The leash, as the user settled it. Asked how far a measurement's number
    /// may step sideways before it stops reading as that measurement's, they
    /// picked "keep the long leash": three of the pill's own extent across the
    /// line. Because the pill is wider than it is tall that is about a hundred
    /// pixels for a horizontal caliper and nearly three hundred for a vertical
    /// one, and the asymmetry is part of the verdict, not an oversight. The
    /// even leash and the caliper-sized leash were both on the table and both
    /// bought closeness by parking the number on a button's corner or between
    /// two fields with the connector running through one. See
    /// `queue/decisions/how-far-a-readout-may-travel-to-find-whitespace-how-far-may-a-measurement-s-numb.md`.
    @Test func theSidewaysLeashIsThreePillsAcrossTheLine() {
        let pill = CGSize(width: 90, height: 34)
        #expect(MeasureLabelPlanner.maxCrossReach(for: caliper(), chip: pill) == 3 * pill.height)
        #expect(MeasureLabelPlanner.maxCrossReach(for: alignment(), chip: pill) == 3 * pill.width)
        // Longer for a vertical measurement, deliberately.
        #expect(MeasureLabelPlanner.maxCrossReach(for: alignment(), chip: pill)
                > MeasureLabelPlanner.maxCrossReach(for: caliper(), chip: pill))
    }

    /// What the leash decides, in a picture: a caliper drawn inside a band that
    /// leaves nothing clear on its own line. While the band's far edge is
    /// within the leash the number steps past it and draws a connector home;
    /// one pixel further and the trip is not worth it, so the number stays in
    /// the classic spot even though the band is under it.
    @Test func aNumberStepsPastASubjectAtTheLimitAndStaysPutOnePixelBeyond() {
        let m = caliper(headOffset: 10)
        let canvas = CGSize(width: 500, height: 900)
        let limit = MeasureLabelPlanner.maxCrossReach(for: m, chip: m.estimatedLabelSize)
        // Deep above the line so the only way out is downward, past the edge
        // whose distance the leash is being tested against.
        func band(reaching depth: CGFloat) -> CGRect {
            CGRect(x: 0, y: 100, width: 500, height: 200 + depth)
        }

        let atTheLimit = MeasureLabelPlanner.plan(for: m, canvas: canvas,
                                                  describing: [band(reaching: limit)])
        #expect(atTheLimit.placement == .clearPositive)
        #expect(atTheLimit.crossReach == limit)
        var placed = m
        placed.apply(atTheLimit)
        #expect(!placed.labelRect(chipSize: m.estimatedLabelSize)
            .intersects(band(reaching: limit)))

        let pastIt = MeasureLabelPlanner.plan(for: m, canvas: canvas,
                                              describing: [band(reaching: limit + 1)])
        #expect(pastIt.placement == .onLine)
        #expect(pastIt.crossReach == 0)
    }

    @Test func theReachSurvivesARoundTripAndDefaultsToZero() throws {
        var m = caliper()
        m.labelPlacement = .clearPositive
        m.labelCrossReach = 30
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(MeasureContent.self, from: data)
        #expect(back.labelCrossReach == 30)
        #expect(back.labelRect(chipSize: chip) == m.labelRect(chipSize: chip))
        // A document saved before the field existed.
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        json.removeValue(forKey: "labelCrossReach")
        let old = try JSONDecoder().decode(
            MeasureContent.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.labelCrossReach == 0)
    }

    // MARK: - The planner

    /// The bug this task exists for: the verdict must not land on the rows.
    @Test func plannerMovesTheAlignmentVerdictOffTheCheckedRows() {
        let m = alignment()
        let plan = MeasureLabelPlanner.plan(for: m, canvas: CGSize(width: 800, height: 800))
        var placed = m
        placed.apply(plan)
        let rect = placed.labelRect(chipSize: m.estimatedLabelSize)
        for subject in m.subjectRects {
            #expect(!rect.intersects(subject))
        }
    }

    @Test func plannerKeepsTheVerdictOnTheCanvas() {
        // The guide runs to the bottom edge, so "past the end" would fall off.
        var m = MeasureContent(start: CGPoint(x: 100, y: 40), end: CGPoint(x: 100, y: 396),
                               headOffset: 0, mode: .vertical)
        m.alignment = AlignmentCheck(items: [
            AlignmentItem(edge: 100, spanStart: 40, spanEnd: 200),
            AlignmentItem(edge: 105, spanStart: 210, spanEnd: 396),
        ], tolerance: 1)
        let canvas = CGSize(width: 400, height: 400)
        let plan = MeasureLabelPlanner.plan(for: m, canvas: canvas)
        var placed = m
        placed.apply(plan)
        let rect = placed.labelRect(chipSize: m.estimatedLabelSize)
        #expect(CGRect(origin: .zero, size: canvas).contains(rect))
        for subject in m.subjectRects { #expect(!rect.intersects(subject)) }
    }

    /// A guide down the left edges of a column of labels runs close to the
    /// picture's left edge, and its chip, now carrying "Left edges, off 4 px",
    /// is wider than twice that margin. Centred on the guide it would hang off
    /// the picture, so the past-the-end spot slides across the line just far
    /// enough to stay on it, and still keeps off the rows it judged.
    @Test func aGuideNearThePictureEdgeSlidesItsChipOntoThePicture() {
        var m = MeasureContent(start: CGPoint(x: 40, y: 100), end: CGPoint(x: 40, y: 300),
                               headOffset: 0, mode: .vertical)
        m.alignment = AlignmentCheck(items: [
            AlignmentItem(edge: 40, spanStart: 100, spanEnd: 160, elementSide: .after),
            AlignmentItem(edge: 44, spanStart: 170, spanEnd: 230, elementSide: .after),
            AlignmentItem(edge: 40, spanStart: 240, spanEnd: 300, elementSide: .after),
        ], tolerance: 1)
        let canvas = CGSize(width: 600, height: 600)
        let chip = m.estimatedLabelSize
        #expect(chip.width / 2 > 40, "the test needs a chip wider than the margin")
        let plan = MeasureLabelPlanner.plan(for: m, canvas: canvas)
        var placed = m
        placed.apply(plan)
        let rect = placed.labelRect(chipSize: chip)
        #expect(plan.placement == .afterEnd)
        #expect(CGRect(origin: .zero, size: canvas).contains(rect), "\(rect)")
        for subject in m.subjectRects { #expect(!rect.intersects(subject)) }
        // It slid only as far as it had to: the chip's edge sits on the
        // picture's edge, not somewhere out in the middle.
        #expect(rect.minX == 0)
        // The slide is the plan's cross reach, so a saved document redraws it.
        #expect(plan.crossReach > 0)
    }

    /// The mirror: a guide down the right edges of things against the
    /// picture's right edge slides the other way.
    @Test func aGuideNearTheFarEdgeSlidesTheOtherWay() {
        var m = MeasureContent(start: CGPoint(x: 570, y: 100), end: CGPoint(x: 570, y: 300),
                               headOffset: 0, mode: .vertical)
        m.alignment = AlignmentCheck(items: [
            AlignmentItem(edge: 570, spanStart: 100, spanEnd: 160, elementSide: .before),
            AlignmentItem(edge: 570, spanStart: 240, spanEnd: 300, elementSide: .before),
        ], tolerance: 1)
        let canvas = CGSize(width: 600, height: 600)
        let plan = MeasureLabelPlanner.plan(for: m, canvas: canvas)
        var placed = m
        placed.apply(plan)
        let rect = placed.labelRect(chipSize: m.estimatedLabelSize)
        #expect(CGRect(origin: .zero, size: canvas).contains(rect), "\(rect)")
        #expect(rect.maxX == 600)
        #expect(plan.crossReach < 0)
    }

    /// A guide with room on both sides never slides: the chip stays centred
    /// on the line it belongs to, exactly as before the slide existed.
    @Test func aGuideWithRoomKeepsItsChipCentredOnTheLine() {
        var m = alignment()
        // The same guide, moved to the middle of the picture.
        m.start.x = 400
        m.end.x = 400
        let moved = (m.alignment?.items ?? []).map {
            AlignmentItem(edge: $0.edge + 300, spanStart: $0.spanStart, spanEnd: $0.spanEnd)
        }
        m.alignment?.items = moved
        let plan = MeasureLabelPlanner.plan(for: m, canvas: CGSize(width: 800, height: 800))
        var placed = m
        placed.apply(plan)
        #expect(plan.crossReach == 0)
        #expect(placed.labelRect(chipSize: m.estimatedLabelSize).midX == 400)
    }

    /// A caliper whose head already stands clear keeps the classic look: the
    /// fix must not shove labels that were never in the way.
    @Test func plannerLeavesAClearCaliperOnItsHeadLine() {
        let m = caliper(headOffset: 40)
        let plan = MeasureLabelPlanner.plan(for: m, canvas: CGSize(width: 800, height: 800))
        #expect(plan.placement == .onLine)
        #expect(plan.nudge == 0)
    }

    @Test func plannerRescuesACaliperWhoseReadoutSitsOnWhatItMeasures() {
        let m = caliper(headOffset: 3)
        let plan = MeasureLabelPlanner.plan(for: m, canvas: CGSize(width: 800, height: 800))
        var placed = m
        placed.apply(plan)
        let rect = placed.labelRect(chipSize: m.estimatedLabelSize)
        for subject in m.subjectRects { #expect(!rect.intersects(subject)) }
    }

    @Test func plannerNudgesTwoNearbyReadoutsApart() {
        let first = caliper(headOffset: 40)
        let firstRect = first.labelRect(chipSize: first.estimatedLabelSize)
        // A second caliper 6 px below the first: its readout would stack.
        var second = caliper(headOffset: 40)
        second.start.y += 6
        second.end.y += 6
        let plan = MeasureLabelPlanner.plan(for: second, canvas: CGSize(width: 800, height: 800),
                                            avoiding: [firstRect])
        var placed = second
        placed.apply(plan)
        let rect = placed.labelRect(chipSize: second.estimatedLabelSize)
        #expect(!rect.intersects(firstRect))
    }

    // MARK: - What Size mode adds: the element being measured

    /// Size mode's width caliper for an element flush with the bottom of the
    /// picture. `clearingHeadOffset` has already turned the head round over the
    /// element (there is no margin below to reach into), so the classic
    /// on-the-line spot is on top of the very thing being measured.
    @Test func plannerKeepsTheReadoutOffTheElementItMeasured() {
        let element = CGRect(x: 100, y: 320, width: 300, height: 80)
        var m = MeasureContent(start: CGPoint(x: element.minX, y: element.maxY),
                               end: CGPoint(x: element.maxX, y: element.maxY),
                               headOffset: -31, mode: .horizontal)
        let canvas = CGSize(width: 800, height: 400)
        let plan = MeasureLabelPlanner.plan(for: m, canvas: canvas, describing: [element])
        m.apply(plan)
        let rect = m.labelRect(chipSize: m.estimatedLabelSize)
        #expect(!rect.intersects(element), "the readout sits on the element it measured: \(rect)")
        #expect(CGRect(origin: .zero, size: canvas).contains(rect))
    }

    /// The row-label case, in the exact numbers the settings capture gives:
    /// a line of text 25 px tall with the next row starting 28 px below it, and
    /// a readout 43 px tall that cannot fit in that band whatever it does.
    ///
    /// The number stays under its own caliper and leans into the top of the row
    /// below, rather than jumping back over the label to the only spot that
    /// touches nothing. Nothing is covered either way, and the spot under the
    /// caliper is the one a redliner reads without following a leader line.
    @Test func aRowLabelsNumberStaysUnderItsCaliperRatherThanClimbOverTheLabel() {
        let label = CGRect(x: 98, y: 181, width: 181, height: 25)
        let rowBelow = CGRect(x: 96, y: 234.5, width: 1248, height: 89)
        let headingAbove = CGRect(x: 65, y: 66, width: 157, height: 34)
        var m = MeasureContent(start: CGPoint(x: label.minX, y: label.maxY),
                               end: CGPoint(x: label.maxX, y: label.maxY),
                               headOffset: 32.5, mode: .horizontal)
        let canvas = CGSize(width: 1440, height: 960)
        let plan = MeasureLabelPlanner.plan(for: m, canvas: canvas,
                                            avoiding: [headingAbove, rowBelow],
                                            describing: [label])
        m.apply(plan)
        let rect = m.labelRect(chipSize: m.estimatedLabelSize)
        #expect(plan.placement == .onLine, "the number left its line for \(plan.placement)")
        #expect(plan.nudge == 0, "the number drifted off centre by \(plan.nudge)")
        #expect(rect.minY > label.maxY, "the number climbed over the label: \(rect)")
        #expect(!rect.intersects(label))
    }

    /// And the limit on that leniency: once the neighbour would swallow the
    /// readout whole, leaning in is no longer leaning, and the number goes
    /// looking for room again. This is the same capture's whole settings row,
    /// whose number would land squarely on the next row's own label.
    @Test func aReadoutStillLeavesTheLineWhenTheNeighbourWouldSwallowIt() {
        let row = CGRect(x: 96, y: 147.5, width: 1248, height: 88)
        let rowBelow = CGRect(x: 96, y: 234.5, width: 1248, height: 89)
        var m = MeasureContent(start: CGPoint(x: row.minX, y: row.maxY),
                               end: CGPoint(x: row.maxX, y: row.maxY),
                               headOffset: 32.5, mode: .horizontal)
        let canvas = CGSize(width: 1440, height: 960)
        let plan = MeasureLabelPlanner.plan(for: m, canvas: canvas, avoiding: [rowBelow],
                                            describing: [row])
        m.apply(plan)
        let rect = m.labelRect(chipSize: m.estimatedLabelSize)
        #expect(plan.placement == .clearNegative)
        #expect(!rect.intersects(rowBelow), "the number parked in the row below: \(rect)")
        #expect(!rect.intersects(row))
    }

    /// The neighbour case: a row with another row directly below it. The head
    /// stands clear of the measured row, but lands in the row underneath.
    @Test func plannerSteersTheReadoutAroundTheNeighbourBelow() {
        let element = CGRect(x: 100, y: 100, width: 300, height: 80)
        let below = CGRect(x: 100, y: 180, width: 300, height: 80)
        var m = MeasureContent(start: CGPoint(x: element.minX, y: element.maxY),
                               end: CGPoint(x: element.maxX, y: element.maxY),
                               headOffset: 31, mode: .horizontal)
        let canvas = CGSize(width: 800, height: 400)
        let plan = MeasureLabelPlanner.plan(for: m, canvas: canvas, avoiding: [below],
                                            describing: [element])
        m.apply(plan)
        let rect = m.labelRect(chipSize: m.estimatedLabelSize)
        #expect(!rect.intersects(below), "the readout sits on the neighbour: \(rect)")
        #expect(!rect.intersects(element))
        #expect(CGRect(origin: .zero, size: canvas).contains(rect))
    }

    /// And the promise this must not break: a measurement with room around it
    /// keeps the placement it has today, element or no element.
    @Test func plannerLeavesAMeasurementWithOpenSpaceExactlyWhereItWas() {
        let element = CGRect(x: 100, y: 100, width: 300, height: 80)
        let m = MeasureContent(start: CGPoint(x: element.minX, y: element.maxY),
                               end: CGPoint(x: element.maxX, y: element.maxY),
                               headOffset: 31, mode: .horizontal)
        let canvas = CGSize(width: 800, height: 400)
        let before = MeasureLabelPlanner.plan(for: m, canvas: canvas)
        let after = MeasureLabelPlanner.plan(for: m, canvas: canvas, describing: [element])
        #expect(after.placement == before.placement)
        #expect(after.nudge == before.nudge)
        #expect(after.placement == .onLine)
    }

    /// A full-bleed bar flush with the bottom: nowhere along the line is clear
    /// and past either end is off the picture, but the bar is short enough
    /// that the number can step up over it, so it does, whole and on the
    /// picture, rather than sit on the bar or run off the edge.
    @Test func aReadoutOnAShortFullBleedBarStepsUpOverIt() {
        let canvas = CGSize(width: 800, height: 400)
        let element = CGRect(x: 0, y: 300, width: 800, height: 100)
        var m = MeasureContent(start: CGPoint(x: element.minX, y: element.maxY),
                               end: CGPoint(x: element.maxX, y: element.maxY),
                               headOffset: -31, mode: .horizontal)
        m.apply(MeasureLabelPlanner.plan(for: m, canvas: canvas, describing: [element]))
        let rect = m.labelRect(chipSize: m.estimatedLabelSize)
        #expect(CGRect(origin: .zero, size: canvas).contains(rect), "the readout ran off the picture: \(rect)")
        #expect(!rect.intersects(element), "the readout sits on the bar: \(rect)")
        #expect(m.labelPlacement == .clearNegative)
    }

    /// A full-bleed element too tall to step over has nowhere clear at all:
    /// every spot is either on the element or off the picture. The last resort
    /// is the one you can still read - the number stays whole and on the
    /// picture, exactly where it is today, rather than jumping off the edge.
    @Test func aReadoutWithNowhereClearStaysWholeAndOnThePicture() {
        let canvas = CGSize(width: 800, height: 400)
        let element = CGRect(x: 0, y: 0, width: 800, height: 400)
        var m = MeasureContent(start: CGPoint(x: element.minX, y: element.maxY),
                               end: CGPoint(x: element.maxX, y: element.maxY),
                               headOffset: -31, mode: .horizontal)
        let plan = MeasureLabelPlanner.plan(for: m, canvas: canvas, describing: [element])
        m.apply(plan)
        let rect = m.labelRect(chipSize: m.estimatedLabelSize)
        #expect(CGRect(origin: .zero, size: canvas).contains(rect), "the readout ran off the picture: \(rect)")
        #expect(plan.placement == .onLine, "it jumped instead of staying put: \(plan.placement)")
        #expect(plan.crossReach == 0)
    }

    // MARK: - Moving a label never moves the measurement (D14 rule 5)

    @Test func relocatingTheReadoutLeavesTheGeometryUntouched() {
        let base = alignment(outlier: 30)
        for placement in MeasureLabelPlacement.allCases {
            var moved = base
            moved.labelPlacement = placement
            moved.labelNudge = 17
            #expect(moved.caliperGeometry() == base.caliperGeometry(),
                    "\(placement) moved the guide")
            #expect(moved.alignment?.items == base.alignment?.items,
                    "\(placement) moved the ticks")
            #expect(moved.subjectRects == base.subjectRects,
                    "\(placement) moved what is being checked")
        }
    }

    @Test func rebuildingALayerAroundAMovedReadoutKeepsTheFeetWhereTheyWere() {
        var m = alignment()
        m.labelPlacement = .afterEnd
        let start = CGPoint(x: 100, y: 200), end = CGPoint(x: 100, y: 400)
        let layer = MeasureBuilder.layer(content: m, from: start, to: end)
        guard let built = layer.measure else { Issue.record("no measure"); return }
        #expect(abs(built.start.x + layer.frame.minX - start.x) < 0.001)
        #expect(abs(built.start.y + layer.frame.minY - start.y) < 0.001)
        #expect(abs(built.end.y + layer.frame.minY - end.y) < 0.001)
    }

    // MARK: - The head handle hides under a readout that sits on it

    /// Right after a caliper lands its readout rides the head line, centred
    /// on the very point the head handle is drawn at. Drawing the dot there
    /// puts it on the digits ("121 px" reads "12 px"), so the readout itself
    /// is the grab and the dot stays hidden.
    @Test func aReadoutOnTheLineCoversTheHeadHandle() {
        var m = caliper()
        m.labelPlacement = .onLine
        #expect(m.labelCoversHeadHandle(chipSize: chip))
        #expect(m.labelRect(chipSize: chip).contains(m.headHandle))
    }

    @Test func aRelocatedReadoutLeavesTheHeadHandleBare() {
        for placement in [MeasureLabelPlacement.afterEnd, .beforeStart] {
            var m = caliper()
            m.labelPlacement = placement
            #expect(!m.labelCoversHeadHandle(chipSize: chip), "\(placement) still covers the head")
        }
        // A sideways push only moves the chip when the head hugs the line; a
        // head already 40 px out is clear, so the chip (rightly) stays on it.
        for placement in [MeasureLabelPlacement.clearPositive, .clearNegative] {
            var m = caliper(headOffset: 0)
            m.labelPlacement = placement
            #expect(!m.labelCoversHeadHandle(chipSize: chip), "\(placement) still covers the head")
        }
    }

    /// A nudge slides the chip along the line; the dot stays hidden only while
    /// the chip is actually over it, and comes back the moment it is not.
    @Test func aNudgedReadoutHidesTheHandleOnlyWhileItIsOverIt() {
        var m = caliper()
        m.labelPlacement = .onLine
        m.labelNudge = 30            // chip is 90 wide: still over the anchor
        #expect(m.labelCoversHeadHandle(chipSize: chip))
        m.labelNudge = 60            // past its own half-width: the anchor is bare
        #expect(!m.labelCoversHeadHandle(chipSize: chip))
    }

    @Test func aVerticalCaliperCoversItsHeadTheSameWay() {
        var m = MeasureContent(start: CGPoint(x: 300, y: 100), end: CGPoint(x: 300, y: 300),
                               headOffset: 40, mode: .vertical)
        m.labelPlacement = .onLine
        #expect(m.labelCoversHeadHandle(chipSize: chip))
        m.labelPlacement = .afterEnd
        #expect(!m.labelCoversHeadHandle(chipSize: chip))
    }

    // MARK: - Persistence

    @Test func placementSurvivesACodableRoundTrip() throws {
        var m = alignment()
        m.labelPlacement = .afterEnd
        m.labelNudge = 12
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(MeasureContent.self, from: data)
        #expect(back.labelPlacement == .afterEnd)
        #expect(back.labelNudge == 12)
    }

    /// A document written before this feature has no placement key; it must
    /// come back looking exactly as it did, on the line.
    @Test func legacyDocumentsDecodeOnTheLine() throws {
        let json = """
        {"start":[10,10],"end":[110,10],"headOffset":40,"mode":"horizontal",
         "strokeWidth":2,"showLabel":true,"unit":"points","decimals":0}
        """
        let back = try JSONDecoder().decode(MeasureContent.self, from: Data(json.utf8))
        #expect(back.labelPlacement == .onLine)
        #expect(back.labelNudge == 0)
    }

    // MARK: - The frame reserves room where the chip actually lands

    @Test func theLayerFrameHoldsARelocatedReadout() {
        var m = alignment()
        m.labelPlacement = .afterEnd
        let layer = MeasureBuilder.layer(content: m, from: CGPoint(x: 100, y: 200),
                                         to: CGPoint(x: 100, y: 400))
        guard let built = layer.measure else { Issue.record("no measure"); return }
        let rect = built.labelRect(chipSize: built.estimatedLabelSize)
        #expect(CGRect(origin: .zero, size: layer.frame.size).contains(rect))
    }
}
