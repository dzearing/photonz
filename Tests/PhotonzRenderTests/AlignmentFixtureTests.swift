import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// The alignment guide measured against a REAL screenshot whose true geometry
/// is known, for the same reason `ElementDetectionFixtureTests` exists: a
/// synthetic scene draws exactly the boundaries the scan is looking for, and
/// every bug this feature has shipped came from the ones a screenshot brings —
/// antialiased glyph edges, block-summed bleed under a line of text, two local
/// peaks either side of a curved letter.
///
/// The fixture is `Fixtures/settings-pane-2x.png`, the capture the measure
/// audit of 2026-08-23 was written against. Its second card holds three labels
/// whose left edges are at logical x 48, **52** and 48 — the middle one is
/// deliberately 4 logical px out. At 2x that is device x 96, 104, 96.
@Suite("Alignment guide on a real capture")
struct AlignmentFixtureTests {

    private static let analysis: EdgeMapAnalyzer.Analysis = {
        guard let url = Bundle.module.url(forResource: "Fixtures/settings-pane-2x",
                                          withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = ImageCodec.decode(data) else { return .empty }
        return EdgeMapAnalyzer.analyzeFully(image)
    }()
    private static var edges: EdgeMap { analysis.edges }
    private static var luma: LumaField { analysis.luma }

    /// The drag the audit describes: down the left edge of the three labels in
    /// the second card. The press anchor snaps to the edge before the scan sees
    /// it, so device x 96 is what the shipping path hands over.
    private static let guideX: CGFloat = 96
    private static let guideSpan: ClosedRange<CGFloat> = 470...680

    /// The capture is stamped 144 DPI, so Photonz opens it at pixelScale 2 and
    /// every readout is in logical points.
    private static let pixelScale: CGFloat = 2

    /// The scan the app runs: the edge map for the runs, the picture for what
    /// the runs belong to, at the capture's own scale.
    private func scan(at position: CGFloat = AlignmentFixtureTests.guideX,
                      span: ClosedRange<CGFloat> = AlignmentFixtureTests.guideSpan,
                      axis: MeasureMode = .vertical,
                      in analysis: EdgeMapAnalyzer.Analysis = AlignmentFixtureTests.analysis) -> [AlignmentItem] {
        AlignmentScan.items(axis: axis, position: position, span: span, in: analysis.edges,
                            luma: analysis.luma, pixelScale: Self.pixelScale)
    }

    /// The committed guide, built the way `EditorState.addAlignmentCheck` builds
    /// it: scan, settle onto the reference edge, plan where the readout lands.
    private func committed(_ items: [AlignmentItem]) -> (content: MeasureContent,
                                                         start: CGPoint, end: CGPoint) {
        var content = MeasureContent(headOffset: 0, mode: .vertical, unit: .points)
        content.alignment = AlignmentCheck(items: items, tolerance: 1)
        let reference = content.alignment?.verdict?.reference ?? Self.guideX
        let start = CGPoint(x: reference, y: Self.guideSpan.lowerBound)
        let end = CGPoint(x: reference, y: Self.guideSpan.upperBound)
        content.start = start
        content.end = end
        let plan = MeasureLabelPlanner.plan(for: content,
                                            canvas: CGSize(width: Self.edges.width,
                                                           height: Self.edges.height))
        content.apply(plan)
        return (content, start, end)
    }

    @Test func theCaptureIsTheOneTheAuditMeasured() {
        #expect(Self.edges.width == 1440)
        #expect(Self.edges.height == 960)
    }

    /// One item per label, and nothing else. The bug this pins: the block-summed
    /// edge map keeps bleeding a faint ghost of the middle label's edge for a
    /// sample or two BELOW the text, at x≈108. That ghost used to become a
    /// fourth item and, being further out than the real edge at x≈106, used to
    /// win the worst-offender vote.
    @Test func theGuideFindsExactlyOneEdgePerLabel() {
        let items = scan()
        #expect(items.count == 3)
        guard items.count == 3 else { return }
        // Two labels agree near device x 96; the middle one sits ~8 device px out.
        #expect(abs(items[0].edge - 96) <= 2.5)
        #expect(abs(items[1].edge - 104) <= 2.5)
        #expect(abs(items[2].edge - 96) <= 2.5)
        // Every run has to be long enough to be a line of text, not a ghost.
        for item in items { #expect(item.spanEnd - item.spanStart >= 16) }
    }

    /// The labels' text runs to the RIGHT of the guide, so this is their left
    /// edge, and the row can say so: "Left edges, 3 items".
    @Test func theGuideKnowsItIsRunningDownLeftEdges() {
        let items = scan()
        #expect(items.count == 3)
        #expect(items.allSatisfy { $0.elementSide == .after })
        let (content, _, _) = committed(items)
        #expect(content.alignedEdge == .left)
        #expect(MeasureSpecList.derivedName(for: content) == "Left edges, 3 items")
    }

    /// The headline number. The true offset is 4 logical px; the chip used to
    /// say 5.
    @Test func theVerdictReadsTheRealOffset() {
        let (content, _, _) = committed(scan())
        #expect(content.label(pixelScale: Self.pixelScale) == "off 4 px")
    }

    /// What the exported picture says, with nothing else to read: the edge the
    /// guide judged and the verdict, in one line.
    @Test func theChipNamesTheEdgeOnTheCapture() {
        let (content, _, _) = committed(scan())
        #expect(content.chipText(pixelScale: Self.pixelScale) == "Left edges, off 4 px")
    }

    /// And it accuses the right row: the middle label, not the ghost under it.
    @Test func theOutlierIsTheMiddleLabel() {
        let items = scan()
        guard let verdict = AlignmentCheck(items: items, tolerance: 1).verdict,
              let outlier = verdict.outlierIndex else {
            Issue.record("no outlier on a capture with a 4px offender")
            return
        }
        let item = items[outlier]
        // The middle label's text band.
        #expect(item.spanStart >= 540 && item.spanEnd <= 610)
        #expect(abs(item.edge - 104) <= 2.5)
        // The guide settles on the two that agree, not between them and the outlier.
        #expect(abs(verdict.reference - 96) <= 2.5)
    }

    /// Whatever else the readout does, it may not sit on a row it is judging —
    /// the one thing you need to see is the thing it would be hiding.
    @Test func theVerdictPillClearsEveryRowItJudges() {
        let (content, _, _) = committed(scan())
        let pill = content.labelRect(chipSize: content.estimatedLabelSize)
        for (index, subject) in content.subjectRects.enumerated() {
            #expect(!subject.intersects(pill), "pill covers item \(index)")
        }
        // And it stays on the picture.
        #expect(pill.minX >= 0)
        #expect(pill.minY >= 0)
        #expect(pill.maxX <= CGFloat(Self.edges.width))
        #expect(pill.maxY <= CGFloat(Self.edges.height))
    }

    /// The whole guide — dashed line, ticks, the outlier's bracket and the
    /// readout — has to fit inside the layer the builder reserves for it, or the
    /// export clips something.
    @Test func theBuiltLayerHoldsEveryMarkTheGuideDraws() {
        let (content, start, end) = committed(scan())
        let layer = MeasureBuilder.layer(content: content, from: start, to: end)
        guard let local = layer.measure, let check = local.alignment else {
            Issue.record("built layer lost its alignment payload")
            return
        }
        let frame = CGRect(origin: .zero, size: layer.frame.size)
        #expect(frame.contains(local.labelRect(chipSize: local.estimatedLabelSize)))
        // Everything a guide inks for one item: the tick either side of the
        // guide, the bracket out to the element's real edge, and the stroke's
        // own overhang at every end.
        let guideX = local.start.x
        let over = local.renderPadding
        for item in check.items {
            let lo = min(guideX, item.edge) - MeasureBuilder.alignmentTickHalf - over
            let hi = max(guideX, item.edge) + MeasureBuilder.alignmentTickHalf + over
            let mark = CGRect(x: lo, y: item.spanStart - over,
                              width: hi - lo, height: item.spanEnd - item.spanStart + over * 2)
            #expect(frame.contains(mark))
        }
    }

    // MARK: The two buttons under the second card

    /// Reset (bordered) and Save Changes (filled) sit side by side with their
    /// tops level at device y 755. Reset's border is two boundaries 3 px
    /// apart, and the anchor snap can put the guide on the inner one, at 758.
    private static let buttonsY: CGFloat = 758
    private static let buttonsSpan: ClosedRange<CGFloat> = 60...500

    /// The tolerance the app uses on this capture: 1 logical px at 2x.
    private static let buttonsTolerance = AlignmentCheck.deviceTolerance(logical: 1, pixelScale: 2)

    private func buttonsContent(in analysis: EdgeMapAnalyzer.Analysis = AlignmentFixtureTests.analysis,
                                at position: CGFloat = AlignmentFixtureTests.buttonsY) -> MeasureContent {
        let items = scan(at: position, span: Self.buttonsSpan, axis: .horizontal, in: analysis)
        var content = MeasureContent(headOffset: 0, mode: .horizontal, unit: .points)
        content.alignment = AlignmentCheck(items: items, tolerance: Self.buttonsTolerance)
        let reference = content.alignment?.verdict?.reference ?? position
        content.start = CGPoint(x: Self.buttonsSpan.lowerBound, y: reference)
        content.end = CGPoint(x: Self.buttonsSpan.upperBound, y: reference)
        return content
    }

    /// One item per button. The bug this pins: the guide on the inner flank
    /// of Reset's border used to take that flank along the straight run and
    /// the outer edge at the rounded corners, so Reset alone became three
    /// items and the check said off 1 px with 4 items.
    @Test func theGuideAcrossTheButtonsCountsEachButtonOnce() {
        let content = buttonsContent()
        #expect(content.alignment?.items.count == 2)
        for item in content.alignment?.items ?? [] { #expect(abs(item.edge - 755) <= 1) }
        #expect(MeasureSpecList.derivedName(for: content) == "Top edges, 2 items")
    }

    @Test func buttonsThatLineUpToTheEyeReadAligned() {
        let content = buttonsContent()
        #expect(content.chipText(pixelScale: Self.pixelScale) == "Top edges aligned")
        #expect(content.label(pixelScale: Self.pixelScale) == "aligned")
    }

    /// Wherever along the border the press landed: on the outer edge, inside
    /// the border, or on the inner flank.
    @Test func everyReasonableDragAlongTheButtonTopsAgrees() {
        for position in [CGFloat(754), 756, 758, 760] {
            let content = buttonsContent(at: position)
            #expect(content.alignment?.items.count == 2, "guide at y \(position)")
            #expect(content.label(pixelScale: Self.pixelScale) == "aligned", "guide at y \(position)")
        }
    }

    /// The same capture with Save Changes moved down 2 logical px (4 device
    /// px): a real misalignment still reads as one, at its real size.
    @Test func aRealTwoPointMisalignmentIsStillReported() {
        guard let doctored = Self.captureWithSaveButtonLowered(by: 4) else {
            Issue.record("could not doctor the fixture")
            return
        }
        let content = buttonsContent(in: doctored)
        #expect(content.alignment?.items.count == 2)
        #expect(content.chipText(pixelScale: Self.pixelScale) == "Top edges, off 2 px")
    }

    /// The fixture with the Save Changes button (device x 220...492,
    /// y 736...820, with room for its antialiased sides) painted `dy` rows
    /// lower and the rows it vacated filled with the background above it.
    private static func captureWithSaveButtonLowered(by dy: Int) -> EdgeMapAnalyzer.Analysis? {
        guard let url = Bundle.module.url(forResource: "Fixtures/settings-pane-2x",
                                          withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = ImageCodec.decode(data),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        // Core Graphics is bottom-left (and drawing an image under a flipped
        // CTM would flip the image), so the top-left rects are converted.
        let h = CGFloat(image.height)
        func cg(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let button = CGRect(x: 220, y: 736, width: 272, height: 84)
        guard let crop = image.cropping(to: button),
              let bg = image.cropping(to: CGRect(x: 220, y: 728, width: 272, height: 1)) else {
            return nil
        }
        // Fill the vacated strip with the row of background just above.
        context.draw(bg, in: cg(CGRect(x: button.minX, y: button.minY,
                                       width: button.width, height: CGFloat(dy))))
        context.draw(crop, in: cg(button.offsetBy(dx: 0, dy: CGFloat(dy))))
        guard let doctored = context.makeImage() else { return nil }
        return EdgeMapAnalyzer.analyzeFully(doctored)
    }

    // MARK: Counting the way a person would

    /// The count a person would give, on the real capture, for each kind of
    /// thing the block-summed map used to split or merge. Each of these read
    /// wrong before the scan regrouped its runs by the pixels: the S of "Show
    /// in menu bar" was three left edges, a text line's top was ten, a toggle's
    /// rounded end was its own item, and a card edge vanished wherever bold
    /// text shared its block.
    private func count(axis: MeasureMode, at position: CGFloat,
                       span: ClosedRange<CGFloat>) -> Int {
        scan(at: position, span: span, axis: axis).count
    }

    /// Down the left edges of the first card's three labels: L, S and P.
    @Test func threeLabelsWithACurvedSCountThree() {
        #expect(count(axis: .vertical, at: 96, span: 170...400) == 3)
    }

    /// Down all six labels in both cards, five at x 48 and one at 52.
    @Test func sixLabelsDownBothCardsCountSix() {
        let items = scan(at: 96, span: 170...700)
        #expect(items.count == 6)
        let (content, _, _) = committed(items)
        #expect(MeasureSpecList.derivedName(for: content) == "Left edges, 6 items")
        #expect(content.label(pixelScale: Self.pixelScale) == "off 4 px")
    }

    /// Along the top of one label: its cap line and x-height line are one
    /// line of text.
    @Test func oneLabelAlongItsTopCountsOne() {
        #expect(count(axis: .horizontal, at: 180, span: 90...290) == 1)
    }

    /// Along the tops of the two button labels (Reset, Save Changes): two
    /// items, aligned, judged by the line most of their letters share.
    @Test func twoButtonLabelsAlongTheirTopsCountTwoAndAgree() {
        let items = scan(at: 775, span: 90...450, axis: .horizontal)
        #expect(items.count == 2)
        #expect(AlignmentCheck(items: items, tolerance: Self.buttonsTolerance).verdict?.isAligned == true)
    }

    /// Along their baselines too, descender or not.
    @Test func twoButtonLabelsAlongTheirBaselinesCountTwoAndAgree() {
        let items = scan(at: 798, span: 90...450, axis: .horizontal)
        #expect(items.count == 2)
        #expect(AlignmentCheck(items: items, tolerance: Self.buttonsTolerance).verdict?.isAligned == true)
    }

    /// Down the left ends of the four toggles: rounded ends and all.
    @Test func fourTogglesCountFour() {
        #expect(count(axis: .vertical, at: 1260, span: 160...700) == 4)
    }

    /// Down the page's left margin: the heading, two white cards on the light
    /// background, and the Reset button.
    @Test func headingCardsAndButtonCountFour() {
        let items = scan(at: 64, span: 60...820)
        #expect(items.count == 4)
        // A card is one item from its top to its bottom, not two halves.
        #expect(items.contains { $0.spanStart <= 170 && $0.spanEnd >= 390 })
        #expect(items.contains { $0.spanStart <= 470 && $0.spanEnd >= 690 })
    }

    /// A row's label and its toggle, on a guide drawn between their tops:
    /// the label is one item even though the guide only clips its ascenders.
    @Test func aLabelAndItsToggleCountTwo() {
        #expect(count(axis: .horizontal, at: 172, span: 90...1350) == 2)
    }

    /// The app commits what it scanned with the picture in hand, so the row
    /// shows the count; the same check without pixels does not.
    @Test func theRowCountsOnlyWhenThePixelsWereRead() {
        let withPixels = AlignmentCheck(items: scan(), tolerance: 1, itemsAreElements: true)
        var content = MeasureContent(headOffset: 0, mode: .vertical, unit: .points)
        content.alignment = withPixels
        #expect(MeasureSpecList.derivedName(for: content) == "Left edges, 3 items")
        content.alignment?.itemsAreElements = false
        #expect(MeasureSpecList.derivedName(for: content) == "Left edges")
    }

    /// A guide is drawn by hand, so the answer must not depend on hitting one
    /// exact pixel. Every press that snaps onto this edge has to agree.
    @Test func everyReasonableDragDownTheseLabelsAgrees() {
        for position in [CGFloat(94), 96, 98] {
            let (content, _, _) = committed(scan(at: position))
            #expect(content.label(pixelScale: Self.pixelScale) == "off 4 px",
                    "guide at x \(position)")
        }
    }
}
