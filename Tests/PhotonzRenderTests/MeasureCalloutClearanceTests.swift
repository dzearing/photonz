import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// The thumb test from UX-PATTERNS D14, run on the real capture the measure
/// audits are written against (`Fixtures/settings-pane-2x.png`): cover each
/// callout with your thumb and the picture must still show everything the
/// callout is claiming.
///
/// These are deliberately end-to-end — scan real edges, plan the readout the
/// way the app does, then check the readout's footprint against what it is
/// describing — because the bug this suite exists for only appeared once real
/// geometry met a real chip size.
@Suite("Callouts stay off their subjects on a real capture")
struct MeasureCalloutClearanceTests {

    private static let analysis: EdgeMapAnalyzer.Analysis = {
        guard let url = Bundle.module.url(forResource: "Fixtures/settings-pane-2x",
                                          withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = ImageCodec.decode(data) else { return .empty }
        return EdgeMapAnalyzer.analyzeFully(image)
    }()

    private static let canvas = CGSize(width: 1440, height: 960)

    /// The measurement the app would commit for a guide drawn at `position`
    /// down `span`, with its readout already placed.
    private func alignmentCheck(position: CGFloat,
                                span: ClosedRange<CGFloat>) -> MeasureContent {
        let items = AlignmentScan.items(axis: .vertical, position: position, span: span,
                                        in: Self.analysis.edges)
        var content = MeasureContent(headOffset: 0, mode: .vertical, unit: .points)
        content.alignment = AlignmentCheck(items: items, tolerance: 1)
        let reference = content.alignment?.verdict?.reference ?? position
        let start = CGPoint(x: reference, y: span.lowerBound)
        let end = CGPoint(x: reference, y: span.upperBound)
        var probe = content
        probe.start = start
        probe.end = end
        let plan = MeasureLabelPlanner.plan(for: probe, canvas: Self.canvas)
        probe.apply(plan)
        return probe
    }

    /// The left edge of a settings row, read off the capture rather than
    /// hard-coded, so the test still means something if the fixture is redrawn.
    private var rowLeftEdge: CGFloat {
        ElementBounds.candidates(at: CGPoint(x: 700, y: 192), in: Self.analysis.edges,
                                 luma: Self.analysis.luma).first?.minX ?? 0
    }

    @Test func theCaptureIsTheOneTheAuditsMeasured() {
        #expect(Self.analysis.edges.width == 1440)
        #expect(rowLeftEdge > 0)
    }

    /// A guide down the left edge of the three settings rows — the exact shape
    /// of the playtest that found the bug.
    @Test func anAlignmentVerdictNeverCoversTheRowsItJudges() {
        let check = alignmentCheck(position: rowLeftEdge, span: 150...410)
        #expect(check.alignment?.items.count ?? 0 >= 2, "the guide found edges to compare")
        let readout = check.labelRect(chipSize: check.estimatedLabelSize)
        for subject in check.subjectRects {
            #expect(!readout.intersects(subject),
                    "the verdict covers a row it is judging: \(readout) vs \(subject)")
        }
    }

    /// And it stays on the picture: a readout half off the image is not a
    /// readout.
    @Test func anAlignmentVerdictStaysOnTheCapture() {
        let check = alignmentCheck(position: rowLeftEdge, span: 150...410)
        let readout = check.labelRect(chipSize: check.estimatedLabelSize)
        #expect(CGRect(origin: .zero, size: Self.canvas).contains(readout))
    }

    /// A guide that runs the full height of the capture has no room past
    /// either end, so the verdict has to step sideways instead — and still
    /// clear everything.
    @Test func aFullHeightGuideStillFindsSomewhereClear() {
        let check = alignmentCheck(position: rowLeftEdge, span: 20...940)
        let readout = check.labelRect(chipSize: check.estimatedLabelSize)
        for subject in check.subjectRects {
            #expect(!readout.intersects(subject))
        }
        #expect(CGRect(origin: .zero, size: Self.canvas).contains(readout))
    }

    /// Size mode's two calipers for an element, placed exactly the way
    /// `EditorState.addElementSize` places them: each readout knows the element
    /// it is describing, both steer around the neighbours the canvas read off
    /// the capture, and the height one also dodges the width one.
    private func elementSize(_ rect: CGRect,
                             neighbors: [CGRect]? = nil) -> (width: MeasureContent,
                                                             height: MeasureContent) {
        let widthFeet = (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY))
        let heightFeet = (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
        func caliper(_ mode: MeasureMode, _ feet: (CGPoint, CGPoint),
                     avoiding others: [CGRect]) -> MeasureContent {
            var c = MeasureContent(mode: mode, unit: .points)
            c.headOffset = MeasureBuilder.clearingHeadOffset(content: c, from: feet.0, to: feet.1,
                                                             canvas: Self.canvas)
            c.start = feet.0
            c.end = feet.1
            let plan = MeasureLabelPlanner.plan(for: c, canvas: Self.canvas, avoiding: others,
                                                describing: [rect])
            c.apply(plan)
            return c
        }
        let around = neighbors ?? []
        let w = caliper(.horizontal, widthFeet, avoiding: around)
        let h = caliper(.vertical, heightFeet,
                        avoiding: around + [w.labelRect(chipSize: w.estimatedLabelSize)])
        return (w, h)
    }

    /// What the canvas hands the planner: the elements touching the pick, plus
    /// whatever sits as far out as a number would travel. Mirrors
    /// `CanvasView.neighbors(of:reach:)`.
    private func neighbors(of rect: CGRect) -> [CGRect] {
        var w = MeasureContent(mode: .horizontal, unit: .points)
        w.start = CGPoint(x: rect.minX, y: rect.maxY)
        w.end = CGPoint(x: rect.maxX, y: rect.maxY)
        var h = MeasureContent(mode: .vertical, unit: .points)
        h.start = CGPoint(x: rect.maxX, y: rect.minY)
        h.end = CGPoint(x: rect.maxX, y: rect.maxY)
        let wHead = MeasureBuilder.clearingHeadOffset(content: w, from: w.start, to: w.end,
                                                      canvas: Self.canvas)
        let hHead = MeasureBuilder.clearingHeadOffset(content: h, from: h.start, to: h.end,
                                                      canvas: Self.canvas)
        let reach = max(abs(wHead) + w.estimatedLabelSize.height / 2,
                        abs(hHead) + h.estimatedLabelSize.width / 2)
        return ElementBounds.neighbors(of: rect, in: Self.analysis.edges, luma: Self.analysis.luma,
                                       reaches: [ElementBounds.neighborProbeReach, Double(reach)])
    }

    /// The element the pointer lands on at `point`, read off the capture the
    /// same way Size mode reads it.
    private func element(at point: CGPoint) -> CGRect? {
        ElementBounds.candidates(at: point, in: Self.analysis.edges,
                                 luma: Self.analysis.luma).first
    }

    // MARK: - Size mode: the number never lands on what it just measured

    /// Point at a settings row, press once: neither number may sit on the row.
    @Test func theSizeOfASettingsRowKeepsBothNumbersOffTheRow() {
        guard let row = element(at: CGPoint(x: 700, y: 192)) else {
            Issue.record("no row detected on the capture")
            return
        }
        let pair = elementSize(row, neighbors: neighbors(of: row))
        for c in [pair.width, pair.height] {
            let chip = c.labelRect(chipSize: c.estimatedLabelSize)
            #expect(!chip.intersects(row), "the \(c.mode) readout sits on the row: \(chip)")
            #expect(CGRect(origin: .zero, size: Self.canvas).contains(chip))
        }
    }

    /// Size-click the Launch at login label. Its width number belongs in the
    /// band under the words, between the label and the divider, where the
    /// heading's number already lands — not back above the label on a leader,
    /// which is where the next row being close beneath used to send it.
    @Test func aRowLabelsWidthNumberLandsUnderTheLabel() {
        guard let label = element(at: CGPoint(x: 190, y: 192)) else {
            Issue.record("no row label detected on the capture")
            return
        }
        #expect(label.height < 40, "the pick climbed to the row: \(label)")
        let width = elementSize(label, neighbors: neighbors(of: label)).width
        let chip = width.labelRect(chipSize: width.estimatedLabelSize)
        #expect(width.labelPlacement == .onLine,
                "the number left its line for \(width.labelPlacement)")
        #expect(chip.minY > label.maxY, "the number climbed over the label: \(chip)")
        #expect(!chip.intersects(label))
        #expect(CGRect(origin: .zero, size: Self.canvas).contains(chip))
    }

    /// And the heading above it is untouched: its number has always sat under
    /// the words and still does.
    @Test func theHeadingsWidthNumberIsWhereItAlwaysWas() {
        guard let heading = element(at: CGPoint(x: 140, y: 83)) else {
            Issue.record("no heading detected on the capture")
            return
        }
        let width = elementSize(heading, neighbors: neighbors(of: heading)).width
        let chip = width.labelRect(chipSize: width.estimatedLabelSize)
        #expect(width.labelPlacement == .onLine)
        #expect(width.labelNudge == 0)
        #expect(chip.minY > heading.maxY)
    }

    /// The Reset button, with Save Changes 25 px to its right: the height
    /// number reaches out over the neighbour unless it is told to steer.
    @Test func theHeightOfAButtonKeepsItsNumberOffTheButtonBesideIt() {
        guard let reset = element(at: CGPoint(x: 136, y: 786)) else {
            Issue.record("no button detected on the capture")
            return
        }
        let around = neighbors(of: reset)
        #expect(around.contains { $0.minX > reset.maxX }, "the button beside it was not seen")
        let height = elementSize(reset, neighbors: around).height
        let chip = height.labelRect(chipSize: height.estimatedLabelSize)
        for neighbor in around {
            #expect(!chip.intersects(neighbor), "the readout sits on a neighbour: \(chip)")
        }
        #expect(!chip.intersects(reset))
    }

    /// And the promise that keeps this from being a nuisance: measuring
    /// something with room around it does not move the number at all.
    @Test func anElementWithRoomAroundItKeepsThePlacementItAlwaysHad() {
        let button = CGRect(x: 400, y: 400, width: 248, height: 60)
        let pair = elementSize(button, neighbors: neighbors(of: button))
        #expect(pair.width.labelPlacement == .onLine)
        #expect(pair.width.labelNudge == 0)
        #expect(pair.height.labelPlacement == .onLine)
        #expect(pair.height.labelNudge == 0)
    }

    /// The right-most element on the capture: the settings card, whose edge is
    /// 64 px from the image edge. Its height caliper has to fit its number into
    /// that margin instead of hanging half of it off the picture.
    @Test func theHeightOfTheRightMostElementKeepsItsWholeNumberOnTheCapture() {
        let card = CGRect(x: 64, y: 148, width: 1312, height: 88)
        let height = elementSize(card).height
        let chip = height.labelRect(chipSize: height.estimatedLabelSize)
        #expect(CGRect(origin: .zero, size: Self.canvas).contains(chip),
                "the height readout hangs off the right edge: \(chip)")
        #expect(height.headOffset > 0,
                "the caliper doubled back over the element instead of using the margin")
    }

    /// The same against the bottom edge, with a width caliper reaching down
    /// into a margin too thin for its full standoff.
    @Test func theWidthOfABottomEdgeElementKeepsItsWholeNumberOnTheCapture() {
        let strip = CGRect(x: 400, y: 820, width: 300, height: 90)
        let width = elementSize(strip).width
        let chip = width.labelRect(chipSize: width.estimatedLabelSize)
        #expect(CGRect(origin: .zero, size: Self.canvas).contains(chip),
                "the width readout hangs off the bottom edge: \(chip)")
        #expect(width.headOffset > 0,
                "the caliper doubled back over the element instead of using the margin")
    }

    /// An element flush with the very bottom has no margin to tuck into, so the
    /// caliper does turn round — and the number is still whole and on the
    /// picture, which is the promise that matters.
    @Test func anElementFlushWithTheEdgeStillKeepsItsWholeNumberOnTheCapture() {
        let flush = CGRect(x: 400, y: 860, width: 300, height: 100)
        let pair = elementSize(flush)
        for c in [pair.width, pair.height] {
            #expect(CGRect(origin: .zero, size: Self.canvas)
                .contains(c.labelRect(chipSize: c.estimatedLabelSize)))
        }
    }

    /// A caliper with room on both sides is left exactly as it was.
    @Test func aCaliperWithRoomOnBothSidesIsUnchanged() {
        let button = CGRect(x: 400, y: 400, width: 248, height: 60)
        let pair = elementSize(button)
        var plainWidth = MeasureContent(mode: .horizontal, unit: .points)
        plainWidth.start = CGPoint(x: button.minX, y: button.maxY)
        plainWidth.end = CGPoint(x: button.maxX, y: button.maxY)
        var plainHeight = MeasureContent(mode: .vertical, unit: .points)
        plainHeight.start = CGPoint(x: button.maxX, y: button.minY)
        plainHeight.end = CGPoint(x: button.maxX, y: button.maxY)
        #expect(pair.width.headOffset
                == MeasureBuilder.clearingHeadOffset(content: plainWidth, from: plainWidth.start,
                                                     to: plainWidth.end))
        #expect(pair.height.headOffset
                == MeasureBuilder.clearingHeadOffset(content: plainHeight, from: plainHeight.start,
                                                     to: plainHeight.end))
    }

    /// Every element Size mode can be pointed at, anywhere on the capture,
    /// keeps its whole number on the picture and off the element itself. The edge cases are not a handful
    /// of positions, they are a whole border, so this sweeps it.
    @Test func noElementAnywhereOnTheCaptureHangsItsNumberOffTheEdge() {
        let bounds = CGRect(origin: .zero, size: Self.canvas)
        var offenders: [String] = []
        for x in stride(from: CGFloat(0), through: 1420, by: 20) {
            for y in stride(from: CGFloat(0), through: 940, by: 20) {
                for size in [CGSize(width: 24, height: 24), CGSize(width: 120, height: 44),
                             CGSize(width: 600, height: 200)] {
                    let rect = CGRect(x: x, y: y,
                                      width: min(size.width, Self.canvas.width - x),
                                      height: min(size.height, Self.canvas.height - y))
                    if rect.width < 4 || rect.height < 4 { continue }
                    let pair = elementSize(rect)
                    for c in [pair.width, pair.height] {
                        let chip = c.labelRect(chipSize: c.estimatedLabelSize)
                        // A full-bleed element leaves nowhere clear at all, and
                        // a number you can read beats a number that is out of
                        // the way: those keep the classic spot on the line.
                        let boxedIn = rect.width >= Self.canvas.width - 8
                            || rect.height >= Self.canvas.height - 8
                        let bad = !bounds.contains(chip) || (!boxedIn && chip.intersects(rect))
                        if bad && offenders.count < 8 {
                            offenders.append("\(rect) \(c.mode) head=\(c.headOffset) chip=\(chip)")
                        }
                    }
                }
            }
        }
        #expect(offenders.isEmpty, "readouts off the canvas or on their own element: \(offenders)")
    }

    /// Size mode drops a width and a height caliper on the same element; their
    /// readouts meet at a corner, so this is the likeliest stack in the app.
    @Test func theWidthAndHeightReadoutsOfOneElementDoNotStack() {
        // The "Save Changes" button: 248 x 60 image px at (171, 756).
        let rect = CGRect(x: 171, y: 756, width: 248, height: 60)
        var width = MeasureContent(mode: .horizontal, unit: .points)
        let widthFeet = (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY))
        width.headOffset = MeasureBuilder.clearingHeadOffset(content: width, from: widthFeet.0,
                                                             to: widthFeet.1, canvas: Self.canvas)
        var height = MeasureContent(mode: .vertical, unit: .points)
        let heightFeet = (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
        height.headOffset = MeasureBuilder.clearingHeadOffset(content: height, from: heightFeet.0,
                                                              to: heightFeet.1, canvas: Self.canvas)

        func placed(_ content: MeasureContent, _ feet: (CGPoint, CGPoint),
                    avoiding others: [CGRect]) -> MeasureContent {
            var probe = content
            probe.start = feet.0
            probe.end = feet.1
            let plan = MeasureLabelPlanner.plan(for: probe, canvas: Self.canvas, avoiding: others)
            probe.apply(plan)
            return probe
        }
        let w = placed(width, widthFeet, avoiding: [])
        let wRect = w.labelRect(chipSize: w.estimatedLabelSize)
        let h = placed(height, heightFeet, avoiding: [wRect])
        let hRect = h.labelRect(chipSize: h.estimatedLabelSize)

        #expect(!wRect.intersects(hRect), "two readouts stacked: \(wRect) vs \(hRect)")
        // Neither covers the button they are measuring.
        #expect(!wRect.intersects(rect))
        #expect(!hRect.intersects(rect))
    }

    // MARK: - Distance and Gap: the number stays off what the feet landed on

    /// A hand-drawn caliper placed the way `EditorState.addMeasure` places it:
    /// the elements at its feet are read off the capture and handed to the
    /// planner as what the caliper describes.
    private func caliper(from start: CGPoint, to end: CGPoint, mode: MeasureMode,
                         headOffset: CGFloat) -> (content: MeasureContent, subjects: [CGRect]) {
        let subjects = ElementBounds.subjects(from: start, to: end, mode: mode,
                                              in: Self.analysis.edges, luma: Self.analysis.luma)
        var c = MeasureContent(mode: mode, unit: .points)
        c.headOffset = headOffset
        c.start = start
        c.end = end
        c.apply(MeasureLabelPlanner.plan(for: c, canvas: Self.canvas, describing: subjects))
        return (c, subjects)
    }

    /// Whether any spot in the planner's vocabulary (its placements, its
    /// nudges, its bounded sideways reach) keeps the chip whole on the capture
    /// and off every subject. Where none does, the classic spot is the answer
    /// and the sweep below does not count it against the planner.
    private func clearSpotExists(for content: MeasureContent, subjects: [CGRect]) -> Bool {
        let chip = content.estimatedLabelSize
        let step = content.chipAxisHalfExtent(chipSize: chip) + MeasureContent.chipLineGap
        let bounds = CGRect(origin: .zero, size: Self.canvas)
        let limit = MeasureLabelPlanner.maxCrossReach(for: content, chip: chip)
        let line = content.lineCross
        let horizontal = content.mode == .horizontal
        // The far side of each subject, either way, as far as the planner is
        // allowed to go.
        let reaches = [CGFloat(0)] + subjects.flatMap { rect -> [CGFloat] in
            let lo = horizontal ? rect.minY : rect.minX
            let hi = horizontal ? rect.maxY : rect.maxX
            return [hi - line, line - lo]
        }.filter { $0 > 0 && $0 <= limit }
        for placement in MeasureLabelPlacement.allCases {
            for multiple in [0, 1, -1, 2, -2] {
                for cross in reaches {
                    var probe = content
                    probe.labelPlacement = placement
                    probe.labelNudge = step * CGFloat(multiple)
                    probe.labelCrossReach = cross
                    let rect = probe.labelRect(chipSize: chip)
                    if bounds.contains(rect), !subjects.contains(where: { $0.intersects(rect) }) {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// The whitespace between the Reset and Save Changes buttons, read the way
    /// Gap mode reads it.
    private var buttonGap: GapMeasurement? {
        // Reset ends at x 208 and Save Changes starts at 232.
        ElementBounds.gap(at: CGPoint(x: 220, y: 786), in: Self.analysis.edges)
    }

    @Test func aCaliperAcrossTheGapBetweenTwoButtonsKnowsBothButtons() {
        guard let gap = buttonGap, gap.axis == .horizontal else {
            Issue.record("no horizontal gap read between the buttons")
            return
        }
        let subjects = ElementBounds.subjects(from: gap.start, to: gap.end, mode: gap.axis,
                                              in: Self.analysis.edges, luma: Self.analysis.luma)
        #expect(subjects.contains { $0.maxX <= gap.start.x + 8 && $0.width > 100 },
                "Reset was not seen: \(subjects)")
        #expect(subjects.contains { $0.minX >= gap.end.x - 8 && $0.width > 200 },
                "Save Changes was not seen: \(subjects)")
    }

    /// The exact misread this exists for: a hand-drawn caliper across that gap
    /// with its head dropped a little below the line lands its number ON Save
    /// Changes, where it reads as that button's width. Now it steps below both
    /// buttons instead.
    @Test func aHandDrawnCaliperBetweenTwoButtonsKeepsItsNumberOffBoth() {
        guard let gap = buttonGap, gap.axis == .horizontal else {
            Issue.record("no horizontal gap read between the buttons")
            return
        }
        let drawn = caliper(from: gap.start, to: gap.end, mode: gap.axis, headOffset: 12)
        let chip = drawn.content.labelRect(chipSize: drawn.content.estimatedLabelSize)
        for subject in drawn.subjects {
            #expect(!chip.intersects(subject), "the number sits on a button: \(chip) vs \(subject)")
        }
        #expect(CGRect(origin: .zero, size: Self.canvas).contains(chip))
        // And it did not fly off somewhere: it is just below the buttons.
        #expect(chip.minY > 816 && chip.minY < 816 + 40, "\(chip)")
    }

    /// The 33 px space between the two settings cards, read the way Gap mode
    /// reads it at `x`: the bottom of the Play sound row to the top of the row
    /// beneath it.
    private func cardGap(atX x: CGFloat) -> GapMeasurement? {
        guard let gap = ElementBounds.gap(at: CGPoint(x: x, y: 432), in: Self.analysis.edges),
              gap.axis == .vertical, gap.length > 20, gap.length < 60 else { return nil }
        return gap
    }

    /// Whether `subjects` includes the settings row whose bottom edge is at
    /// `y`: something row-sized, wider than any label, ending there.
    private func rowEnding(at y: CGFloat, among subjects: [CGRect]) -> Bool {
        subjects.contains { abs($0.maxY - y) <= 8 && $0.height > 60 && $0.width > 1000 }
    }

    /// The exact misread this exists for: a caliper across the space between
    /// the two cards, dropped under the words "Play sound on capture". The
    /// label's glyph edges sit between the probe and the row's top, and they
    /// used to send the candidate ladder past the row's bottom before it ever
    /// paired the row's top with it, so the upper row went missing and the
    /// number climbed onto the label.
    @Test func aCaliperUnderARowLabelStillKnowsTheRowAboveIt() {
        guard let gap = cardGap(atX: 330) else {
            Issue.record("no vertical gap read between the cards at x 330")
            return
        }
        let subjects = ElementBounds.subjects(from: gap.start, to: gap.end, mode: gap.axis,
                                              in: Self.analysis.edges, luma: Self.analysis.luma)
        #expect(rowEnding(at: gap.start.y, among: subjects),
                "the row above the foot was not seen: \(subjects)")
        // And the number stays off the label: the label's cap-to-baseline band
        // at that x is roughly y 362 to 379 on the capture.
        var ink = MeasureContent(mode: gap.axis, unit: .points)
        let head = MeasureBuilder.clearingHeadOffset(content: ink, from: gap.start, to: gap.end,
                                                     canvas: Self.canvas)
        ink = caliper(from: gap.start, to: gap.end, mode: gap.axis, headOffset: head).content
        let chip = ink.labelRect(chipSize: ink.estimatedLabelSize)
        let label = CGRect(x: 300, y: 360, width: 240, height: 22)
        #expect(!chip.intersects(label), "the number sits on the row label: \(chip)")
    }

    /// What a foot stands on cannot depend on what is painted beside it. Along
    /// the whole space between the two cards, over blank row and label text
    /// alike, both rows have to come back as the caliper's subjects.
    @Test func aCaliperBetweenTheCardsKnowsBothRowsWhereverItStands() {
        var offenders: [String] = []
        var checked = 0
        for x in stride(from: CGFloat(110), through: 1330, by: 10) {
            guard let gap = cardGap(atX: x) else { continue }
            checked += 1
            let subjects = ElementBounds.subjects(from: gap.start, to: gap.end, mode: gap.axis,
                                                  in: Self.analysis.edges, luma: Self.analysis.luma)
            let upper = rowEnding(at: gap.start.y, among: subjects)
            let lower = subjects.contains { abs($0.minY - gap.end.y) <= 8 && $0.height > 60 }
            if !(upper && lower), offenders.count < 8 {
                offenders.append("x=\(x) upper=\(upper) lower=\(lower) subjects=\(subjects)")
            }
        }
        #expect(checked > 50, "the gap between the cards was not read along its length")
        #expect(offenders.isEmpty, "a foot lost its row: \(offenders)")
    }

    /// Every gap Gap mode can read anywhere on the capture, measured with the
    /// head Gap mode commits and with a hand-placed head on either side: no
    /// readout may sit on an element its feet landed on when any spot in the
    /// planner's vocabulary is clear.
    @Test func noCaliperAnywhereOnTheCaptureParksItsNumberOnWhatItsFeetLandedOn() {
        var seen = Set<String>()
        var gaps: [GapMeasurement] = []
        for x in stride(from: CGFloat(20), through: 1420, by: 40) {
            for y in stride(from: CGFloat(20), through: 940, by: 40) {
                guard let gap = ElementBounds.gap(at: CGPoint(x: x, y: y), in: Self.analysis.edges),
                      gap.length >= 4 else { continue }
                let key = "\(gap.axis)|\(gap.start)|\(gap.end)"
                if seen.insert(key).inserted { gaps.append(gap) }
            }
        }
        #expect(!gaps.isEmpty)
        var protected = 0
        var offenders: [String] = []
        for gap in gaps {
            var ink = MeasureContent(mode: gap.axis, unit: .points)
            ink.mode = gap.axis
            let gapHead = MeasureBuilder.clearingHeadOffset(content: ink, from: gap.start,
                                                            to: gap.end, canvas: Self.canvas)
            for head in [gapHead, 16, -16] {
                let drawn = caliper(from: gap.start, to: gap.end, mode: gap.axis, headOffset: head)
                guard !drawn.subjects.isEmpty else { continue }
                protected += 1
                let chip = drawn.content.labelRect(chipSize: drawn.content.estimatedLabelSize)
                guard drawn.subjects.contains(where: { chip.intersects($0) }),
                      clearSpotExists(for: drawn.content, subjects: drawn.subjects) else { continue }
                if offenders.count < 8 {
                    offenders.append("\(gap.axis) \(gap.start)->\(gap.end) head=\(head) "
                                     + "chip=\(chip) placement=\(drawn.content.labelPlacement)")
                }
            }
        }
        #expect(protected > 0, "no gap on the capture had elements at its feet")
        #expect(offenders.isEmpty, "readouts on what their feet landed on: \(offenders)")
    }
}
