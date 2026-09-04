import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// Element detection measured against a REAL screenshot whose true geometry is
/// known, because that is the only kind of test that can catch this heuristic
/// going wrong. A synthetic scene draws exactly the boundaries the algorithm is
/// looking for; a screenshot brings antialiasing, drop shadows, rounded corners,
/// text and a switch with a knob inside it — every one of which broke an earlier
/// version of this code.
///
/// The fixture is `Fixtures/settings-pane-2x.png`, the capture the measure audit
/// of 2026-08-23 was written against (`queue/audits/2026-08-23-measure-*`). It is
/// a 2x render of a settings pane, so one logical point is two image pixels and
/// every expectation below is the number a spec would quote:
///
/// | element | logical size | probe (image px) |
/// | --- | --- | --- |
/// | "Save Changes" button | 124 x 30 | 295, 786 |
/// | "Reset" button | 72 x 30 | 150, 786 |
/// | switch, pointer at its center | 42 x 24 | 1302, 191 |
/// | settings row | 624 x 44 | 700, 192 |
/// | empty text field | 220 x 26 | 1124, 495 |
@Suite("Element detection on a real capture")
struct ElementDetectionFixtureTests {

    /// What the two calipers a click would commit actually SAY, formatted by the
    /// shipping formatter. Pinning the readout rather than the raw geometry is
    /// the point: detection is allowed half a pixel of slack, a person reading
    /// "125 px" off a 124 px button is not.
    private struct Reading: CustomStringConvertible, Equatable {
        var width: String
        var height: String
        var description: String { "\(width) by \(height)" }

        init(_ width: String, _ height: String) {
            self.width = width
            self.height = height
        }

        /// The capture is stamped 144 DPI, so Photonz opens it at pixelScale 2
        /// and the calipers read in logical points.
        init(_ rect: CGRect) {
            func label(_ span: CGFloat, _ mode: MeasureMode) -> String {
                MeasureContent(start: .zero,
                               end: CGPoint(x: mode == .horizontal ? span : 0,
                                            y: mode == .vertical ? span : 0),
                               mode: mode, unit: .points).label(pixelScale: 2)
            }
            width = label(rect.width, .horizontal)
            height = label(rect.height, .vertical)
        }
    }

    private static let analysis: EdgeMapAnalyzer.Analysis = {
        guard let url = Bundle.module.url(forResource: "Fixtures/settings-pane-2x",
                                          withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = ImageCodec.decode(data) else { return .empty }
        return EdgeMapAnalyzer.analyzeFully(image)
    }()

    /// The logical size Size mode would show for the element under `probe`.
    private func reading(at x: Double, y: Double, level: Int = 0) -> Reading? {
        let ladder = ElementBounds.candidates(at: CGPoint(x: x, y: y),
                                              in: Self.analysis.edges,
                                              luma: Self.analysis.luma)
        guard level < ladder.count else { return nil }
        return Reading(ladder[level])
    }

    @Test func theCaptureIsTheOneTheAuditMeasured() {
        #expect(Self.analysis.edges.width == 1440)
        #expect(Self.analysis.edges.height == 960)
        #expect(Self.analysis.luma.width == 1440)
    }

    @Test func aPrimaryButtonReadsItsRealSize() {
        // Truly 124 x 30. Used to read nothing at all: the four directional
        // walks landed on glyph strokes and disagreed so badly the rect
        // inverted.
        #expect(reading(at: 295, y: 786) == Reading("124 px", "30 px"))
    }

    @Test func aButtonReadsTheSameFromOverItsLabel() {
        // The pick must not change as the pointer crosses the text inside the
        // button — a readout that flickers between a word and a button is worse
        // than one that is quietly wrong.
        #expect(reading(at: 340, y: 786) == Reading("124 px", "30 px"))
    }

    @Test func aSecondaryButtonReadsItsRealSize() {
        // Truly 72 x 30, and harder than the primary: its border is a whisper
        // against the page while its label is nearly black, so the boldest
        // boundary anywhere near the pointer belongs to the text.
        #expect(reading(at: 150, y: 786) == Reading("72 px", "30 px"))
    }

    @Test func aSwitchReadsTheSwitchNotItsKnob() {
        // Truly 42 x 24. The center of a switch lands ON the knob, which is a
        // perfectly real 20 x 20 element — but nobody pointing at the middle of
        // a switch means the knob. Used to read a 12 x 12 sliver of it.
        #expect(reading(at: 1302, y: 191) == Reading("42 px", "24 px"))
        // And from the green, well away from the knob.
        #expect(reading(at: 1275, y: 191) == Reading("42 px", "24 px"))
    }

    @Test func aSettingsRowReadsTheRowNotTheCard() {
        // Truly 624 x 44. The row has NO left or right border — its width is
        // only knowable from how far the hairline under it runs, which is why
        // detection reads pixels and not just the edge map. Used to stop at the
        // label text and read 490 x 42.
        #expect(reading(at: 700, y: 192) == Reading("624 px", "44 px"))
        #expect(reading(at: 700, y: 280) == Reading("624 px", "44 px"))
        #expect(reading(at: 700, y: 368) == Reading("624 px", "44 px"))
    }

    @Test func aSettingsRowIsOneStepUpFromItsLabel() {
        // Half of a settings row is its label, so this is where a person's
        // pointer actually lands. The label is the first rung (below); the
        // row is one press of `]` away, and reads as it always did.
        let row = reading(at: 200, y: 192, level: 1)
        #expect(row?.height == "44 px")
        #expect(row?.width == "623 px" || row?.width == "624 px")
    }

    // MARK: A line of text is an element

    /// The ink box of the text under `probe`, in image px, as Size mode's
    /// first pick.
    private func ink(at x: Double, y: Double) -> CGRect? {
        ElementBounds.candidates(at: CGPoint(x: x, y: y), in: Self.analysis.edges,
                                 luma: Self.analysis.luma).first
    }

    @Test func aHeadingReadsAsOneElement() {
        // "General", 157 x 34 image px of ink (the G's antialiased flank
        // counts), 17 logical points tall, on the bare page with no border
        // anywhere near it. Used to read nothing at all.
        let heading = CGRect(x: 65, y: 66, width: 157, height: 34)
        #expect(ink(at: 140, y: 82) == heading)
        #expect(reading(at: 140, y: 82)?.height == "17 px")
        // From the first letter and the last, the same heading.
        #expect(ink(at: 75, y: 90) == heading)
        #expect(ink(at: 215, y: 80) == heading)
        // Nothing else is offered: the page has no rung around a heading.
        #expect(reading(at: 140, y: 82, level: 1) == nil)
    }

    @Test func aRowLabelReadsAsOneElement() {
        // "Launch at login": 181 x 25 px of ink, cap top to the g's descender.
        // Two word spaces inside it (9 and 10 px) do not split it.
        #expect(ink(at: 200, y: 192) == CGRect(x: 98, y: 181, width: 181, height: 25))
        #expect(ink(at: 187, y: 192) == CGRect(x: 98, y: 181, width: 181, height: 25))
        #expect(ink(at: 260, y: 200) == CGRect(x: 98, y: 181, width: 181, height: 25))
    }

    @Test func aButtonLabelIsStillTheButton() {
        // The words inside a button belong to the button (pinned above); the
        // label is not offered as a rung at all, so `[` has nowhere to go.
        #expect(reading(at: 340, y: 786, level: 1) == nil
                || reading(at: 340, y: 786, level: 1)?.width != "85 px")
        let ladder = ElementBounds.candidates(at: CGPoint(x: 340, y: 786),
                                              in: Self.analysis.edges,
                                              luma: Self.analysis.luma)
        #expect(!ladder.contains { $0.width < 200 })
    }

    @Test func aCaliperAcrossALabelKnowsTheLabel() {
        // Distance mode with its feet on the two ends of "Copy to clipboard"
        // (97...308 x 662...686): the label comes back as the caliper's
        // subject, so the readout planner keeps the number off the words.
        let subjects = ElementBounds.subjects(from: CGPoint(x: 97, y: 674),
                                              to: CGPoint(x: 309, y: 674),
                                              mode: .horizontal,
                                              in: Self.analysis.edges,
                                              luma: Self.analysis.luma)
        #expect(subjects.contains { abs($0.minX - 97) <= 2 && abs($0.maxX - 309) <= 2
                                    && abs($0.minY - 662) <= 2 && abs($0.maxY - 687) <= 2 },
                "subjects: \(subjects)")
    }

    @Test func blankPageAndHairlinesStillReadNothing() {
        // The row divider under "Launch at login" and the empty text field's
        // inside: no words, no rung from the text reader.
        #expect(ink(at: 700, y: 235) == nil || (ink(at: 700, y: 235)?.height ?? 0) >= 40)
        #expect(reading(at: 1124, y: 495)?.height == "26 px")
    }

    @Test func growingThePickReachesTheCard() {
        // `]` from a row must reach the card that holds it: truly 656 x 132.
        // The card's own outline is a white-on-near-white edge under a drop
        // shadow, so its width reads a couple of points narrow; the height,
        // which is what a card is measured for, is exact.
        let ladder = ElementBounds.candidates(at: CGPoint(x: 700, y: 192),
                                              in: Self.analysis.edges,
                                              luma: Self.analysis.luma)
        #expect(ladder.contains { rect in
            abs(Double(rect.width) / 2 - 656) <= 4 && abs(Double(rect.height) / 2 - 132) <= 1
        })
        // Strictly nested, innermost first — that is what makes `[` and `]` a
        // ladder rather than a shuffle.
        for (inner, outer) in zip(ladder, ladder.dropFirst()) {
            #expect(outer.insetBy(dx: -1, dy: -1).contains(inner))
        }
    }

    @Test func anEmptyFieldReadsCloseToItsRealSize() {
        // Truly 220 x 26. The height is exact; the width still reads 2 px short
        // because a 1 px border between two whites puts the gradient peak on its
        // inside flank on both sides. Pinned so the known error cannot grow.
        let field = reading(at: 1124, y: 495)
        #expect(field?.height == "26 px")
        #expect(field?.width == "218 px")
    }

    @Test func flatBackgroundStaysQuiet() {
        #expect(reading(at: 1500, y: 900) == nil)
        #expect(reading(at: 700, y: 40) == nil)
    }

    @Test func detectionCostsLittleMoreThanTheEdgeQueryItAlreadyMade() {
        // Spec budget: under 1 ms per mouse move, which an optimized build meets
        // with room to spare (under 100 µs on this capture for the whole
        // ladder, of which ~20 µs is the edge-map query snapping makes anyway
        // and ~10 µs the text reader). Tests build unoptimized, where
        // everything is ~100x slower, so the guard is RELATIVE: reading the
        // pixels to follow each boundary, and to read the words under the
        // pointer, must stay a small multiple of the query it rides on. That
        // catches the regression that matters — detection going back to
        // scanning whole rows of the image — at any build setting.
        //
        // Timed through `PerfClock`: the fastest of many rounds, on this
        // thread's CPU clock, with the query and the detection interleaved so
        // both see the same machine. On wall clock this went red on a loaded
        // machine on 2026-09-04, missing by a fifth, because the query half
        // was measured before the detection half and the load arrived in
        // between.
        let reading = PerfClock.compare("detect against its edge query",
                                        rounds: 20, callsPerRound: 10,
                                        subject: {
            _ = ElementBounds.detect(at: CGPoint(x: 295, y: 786),
                                     in: Self.analysis.edges, luma: Self.analysis.luma)
        }, reference: {
            _ = Self.analysis.edges.horizontalEdges(inXRange: 263...327)
            _ = Self.analysis.edges.verticalEdges(inYRange: 754...818)
        })
        let ratio = String(format: "%.2f", reading.ratio)
        #expect(reading.cost < reading.baseline * 4,
                "detection costs \(ratio)x the edge query it rides on")
    }
}
