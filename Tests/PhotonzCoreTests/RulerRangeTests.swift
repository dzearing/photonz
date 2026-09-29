import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A range of time drawn on the ruler, and what it acts on**
/// (`RulerRange.swift`).
///
/// Final Cut's Range tool and Premiere's In and Out in one gesture: drag along
/// the ruler and the stretch you dragged over is marked, across every track.
/// A press on the playhead still scrubs, a press on either end of the stretch
/// moves that end, and a plain click moves the playhead. Then the stretch is
/// something to act on: a transition on every cut inside it, a cut at both of
/// its ends, captions for just that stretch.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("A range of time on the ruler")
struct RulerRangeTests {

    // MARK: What a press takes hold of

    @Test("A press away from everything draws a new range")
    func pressDrawsARange() {
        #expect(RulerRange.grip(atMS: 5000, playheadMS: 1000, markInMS: nil, markOutMS: nil, reachMS: 100)
                == .newRange)
    }

    @Test("A press on the playhead scrubs, the way it always has")
    func pressOnThePlayheadScrubs() {
        #expect(RulerRange.grip(atMS: 1050, playheadMS: 1000, markInMS: nil, markOutMS: nil, reachMS: 100)
                == .playhead)
    }

    @Test("A press on either end of the marked stretch takes hold of that end")
    func pressOnAnEdge() {
        #expect(RulerRange.grip(atMS: 2040, playheadMS: 9000, markInMS: 2000, markOutMS: 6000, reachMS: 100)
                == .inEdge)
        #expect(RulerRange.grip(atMS: 5950, playheadMS: 9000, markInMS: 2000, markOutMS: 6000, reachMS: 100)
                == .outEdge)
    }

    @Test("An edge is the handle drawn on the band, so it wins over a playhead standing on it")
    func edgeWinsOverThePlayhead() {
        #expect(RulerRange.grip(atMS: 6000, playheadMS: 6000, markInMS: 2000, markOutMS: 6000, reachMS: 100)
                == .outEdge)
    }

    @Test("Inside the stretch, away from its ends and the playhead, a press draws a new range")
    func pressInsideTheStretch() {
        #expect(RulerRange.grip(atMS: 4000, playheadMS: 9000, markInMS: 2000, markOutMS: 6000, reachMS: 100)
                == .newRange)
    }

    @Test("A stretch too narrow to grab both ends of gives the nearer end")
    func narrowStretchNearerEnd() {
        #expect(RulerRange.grip(atMS: 2030, playheadMS: 9000, markInMS: 2000, markOutMS: 2080, reachMS: 100)
                == .inEdge)
        #expect(RulerRange.grip(atMS: 2060, playheadMS: 9000, markInMS: 2000, markOutMS: 2080, reachMS: 100)
                == .outEdge)
    }

    @Test("Only a mark that is set has an end to take hold of")
    func onlySetMarksHaveEnds() {
        // An In alone runs to the document's end; there is no Out handle.
        #expect(RulerRange.grip(atMS: 6000, playheadMS: 9000, markInMS: 2000, markOutMS: nil, reachMS: 100)
                == .newRange)
    }

    // MARK: Drawing one

    @Test("Dragging right or left draws the same stretch, earliest end first")
    func drawnEitherWay() {
        #expect(RulerRange.drawn(fromMS: 2000, toMS: 6000, lengthMS: 10_000) == 2000..<6000)
        #expect(RulerRange.drawn(fromMS: 6000, toMS: 2000, lengthMS: 10_000) == 2000..<6000)
    }

    @Test("A drawn stretch stays on the ruler")
    func drawnClamped() {
        #expect(RulerRange.drawn(fromMS: 8000, toMS: 14_000, lengthMS: 10_000) == 8000..<10_000)
        #expect(RulerRange.drawn(fromMS: 1000, toMS: -500, lengthMS: 10_000) == 0..<1000)
    }

    @Test("A stretch too short to take hold of is no stretch")
    func drawnTooShort() {
        #expect(RulerRange.drawn(fromMS: 2000, toMS: 2010, lengthMS: 10_000) == nil)
    }

    @Test("The end being dragged snaps to a cut in reach, and the one pressed first stays put")
    func drawnSnaps() {
        let range = RulerRange.drawn(fromMS: 2000, toMS: 5930, lengthMS: 10_000,
                                     snapTo: [1990, 6000], reachMS: 100)
        #expect(range == 2000..<6000)
    }

    // MARK: Moving an end

    @Test("Dragging the In moves the start and leaves the Out")
    func movingTheIn() {
        #expect(RulerRange.moving(.inEdge, of: 2000..<6000, toMS: 3000, lengthMS: 10_000) == 3000..<6000)
    }

    @Test("Dragging the Out moves the end and leaves the In")
    func movingTheOut() {
        #expect(RulerRange.moving(.outEdge, of: 2000..<6000, toMS: 7500, lengthMS: 10_000) == 2000..<7500)
    }

    @Test("An end dragged past the other stops short of it rather than turning the stretch inside out")
    func movingStopsShort() {
        let range = RulerRange.moving(.inEdge, of: 2000..<6000, toMS: 9000, lengthMS: 10_000)
        #expect(range.upperBound == 6000)
        #expect(range.count == LayerTime.shortestMS)
        let back = RulerRange.moving(.outEdge, of: 2000..<6000, toMS: 0, lengthMS: 10_000)
        #expect(back.lowerBound == 2000)
        #expect(back.count == LayerTime.shortestMS)
    }

    @Test("A moved end snaps too")
    func movingSnaps() {
        #expect(RulerRange.moving(.outEdge, of: 2000..<6000, toMS: 7040, lengthMS: 10_000,
                                  snapTo: [7000], reachMS: 100) == 2000..<7000)
    }

    // MARK: The document

    static func twelveSeconds() -> (doc: PhotonzDocument, clip: UUID) {
        let doc = PhotonzDocument.recording(MarkedStretchTests.movie(), name: "Talk")
        return (doc, doc.layers[0].id)
    }

    @Test("Marking a range sets the In and the Out together")
    func markRange() {
        var (doc, _) = Self.twelveSeconds()
        doc.setMarkOut(atMS: 1000)
        doc.markRange(3000..<7000)
        #expect(doc.markInMS == 3000)
        #expect(doc.markOutMS == 7000)
        #expect(doc.markedRangeMS == 3000..<7000)
    }

    @Test("A range marked past the end of the video stops at it")
    func markRangeClamped() {
        var (doc, _) = Self.twelveSeconds()
        doc.markRange(10_000..<20_000)
        #expect(doc.markedRangeMS == 10_000..<12_000)
    }

    @Test("A click on the ruler outside the marked stretch clears it; inside, it stays")
    func clickClears() {
        var (doc, _) = Self.twelveSeconds()
        #expect(!doc.clickOnRulerClearsMarks(atMS: 5000))
        doc.markRange(3000..<7000)
        #expect(doc.clickOnRulerClearsMarks(atMS: 9000))
        #expect(doc.clickOnRulerClearsMarks(atMS: 1000))
        #expect(!doc.clickOnRulerClearsMarks(atMS: 5000))
        #expect(!doc.clickOnRulerClearsMarks(atMS: 7000))
    }

    @Test("A double-click on the ruler outside the marks clears them, whoever set them; inside, they stay")
    func doubleClickClears() {
        var (doc, _) = Self.twelveSeconds()
        #expect(!doc.rulerClickClearsMarks(atMS: 5000, clicks: 2, rangeInHand: false))
        doc.markRange(3000..<7000)
        // One click beside a range drawn on the ruler lets it go; beside marks
        // set with I and O it only moves the playhead, as in Premiere.
        #expect(doc.rulerClickClearsMarks(atMS: 9000, clicks: 1, rangeInHand: true))
        #expect(!doc.rulerClickClearsMarks(atMS: 9000, clicks: 1, rangeInHand: false))
        // Two clicks beside them let either go.
        #expect(doc.rulerClickClearsMarks(atMS: 9000, clicks: 2, rangeInHand: false))
        #expect(doc.rulerClickClearsMarks(atMS: 1000, clicks: 2, rangeInHand: true))
        #expect(doc.rulerClickClearsMarks(atMS: 1000, clicks: 3, rangeInHand: false))
        // Inside, ends included, nothing goes however many clicks.
        #expect(!doc.rulerClickClearsMarks(atMS: 5000, clicks: 2, rangeInHand: false))
        #expect(!doc.rulerClickClearsMarks(atMS: 3000, clicks: 2, rangeInHand: true))
        #expect(!doc.rulerClickClearsMarks(atMS: 7000, clicks: 2, rangeInHand: false))
    }

    @Test("A double-click beside an In alone clears it, and one beside an Out alone")
    func doubleClickClearsOneMark() {
        var (doc, _) = Self.twelveSeconds()
        doc.setMarkIn(atMS: 4000)
        #expect(doc.rulerClickClearsMarks(atMS: 2000, clicks: 2, rangeInHand: false))
        #expect(!doc.rulerClickClearsMarks(atMS: 9000, clicks: 2, rangeInHand: false))
        doc.clearMarkInOut()
        doc.setMarkOut(atMS: 6000)
        #expect(doc.rulerClickClearsMarks(atMS: 9000, clicks: 2, rangeInHand: false))
        #expect(!doc.rulerClickClearsMarks(atMS: 2000, clicks: 2, rangeInHand: false))
    }

    @Test("The ends of a range snap to cuts, clip ends and markers")
    func snapMoments() {
        var (doc, clip) = Self.twelveSeconds()
        _ = doc.splitClip(clip, atMS: 4000)
        doc.addMarker(atMS: 9000)
        let moments = doc.rangeSnapMoments()
        #expect(moments.contains(0))
        #expect(moments.contains(4000))
        #expect(moments.contains(9000))
        #expect(moments.contains(12_000))
    }

    // MARK: Split at the range's edges

    @Test("Split at Range Edges cuts every clip at both ends of the stretch")
    func splitAtEdges() throws {
        var (doc, clip) = Self.twelveSeconds()
        let cuts = doc.splitEveryClip(atEdgesOf: 3000..<7000)
        #expect(cuts == 2)
        let pieces = try #require(doc.layer(id: clip)?.clipPieces)
        #expect(pieces.count == 3)
        #expect(pieces.startMS(ofPiece: 1) == 3000)
        #expect(pieces.startMS(ofPiece: 2) == 7000)
    }

    @Test("An edge already on a cut, or off the clip, makes no second cut")
    func splitAtEdgesOnceEach() throws {
        var (doc, clip) = Self.twelveSeconds()
        _ = doc.splitClip(clip, atMS: 3000)
        #expect(doc.splitEveryClip(atEdgesOf: 3000..<12_000) == 0)
        #expect(doc.layer(id: clip)?.clipPieces?.count == 2)
    }

    // MARK: A transition on every cut inside it

    @Test("Add Transition puts one on every cut inside the stretch and none outside it")
    func transitionsInside() throws {
        var (doc, _, _) = try EveryCutTransitionTests.threeCuts()
        let cuts = doc.transitionCuts()
        #expect(cuts.count == 3)
        // A stretch round the first two cuts only.
        let range = (cuts[0].atMS - 200)..<(cuts[1].atMS + 200)
        #expect(doc.transitionCuts(within: range).map(\.place) == [cuts[0].place, cuts[1].place])
        let outcome = doc.putTransitionOnEveryCut(.dissolve, within: range)
        #expect(outcome.put == [cuts[0].place, cuts[1].place])
        #expect(doc.documentCut(at: cuts[0].place)?.cut.transition?.kind == .dissolve)
        #expect(doc.documentCut(at: cuts[1].place)?.cut.transition?.kind == .dissolve)
        #expect(doc.documentCut(at: cuts[2].place)?.cut.transition == nil)
    }

    @Test("A cut exactly on an end of the stretch counts as inside it")
    func transitionOnAnEdge() throws {
        let (doc, _, _) = try EveryCutTransitionTests.threeCuts()
        let cut = try #require(doc.transitionCuts().last)
        #expect(doc.transitionCuts(within: cut.atMS..<(cut.atMS + 1000)).map(\.place) == [cut.place])
        #expect(doc.transitionCuts(within: (cut.atMS - 1000)..<cut.atMS).map(\.place) == [cut.place])
    }

    @Test("A stretch with no cut in it puts nothing anywhere")
    func noCutInside() throws {
        var (doc, _) = Self.twelveSeconds()
        let before = doc
        let outcome = doc.putTransitionOnEveryCut(.dissolve, within: 2000..<5000)
        #expect(outcome.put.isEmpty)
        #expect(doc == before)
    }

    // MARK: Captions for the stretch

    static func cue(_ text: String, _ inMS: Int, _ outMS: Int) -> CaptionCue {
        MarkedStretchTests.cue(text, inMS, outMS)
    }

    @Test("Captions for a range replace only the lines that start inside it")
    func captionsReplacedInside() {
        let existing = [Self.cue("before", 1000, 2500), Self.cue("old middle", 4000, 5000),
                        Self.cue("after", 8000, 9000)]
        let heard = [Self.cue("new start", 500, 1500), Self.cue("new middle", 3500, 4500),
                     Self.cue("new more", 5000, 6000), Self.cue("new end", 8200, 9100)]
        let merged = CaptionCues.replacing(existing, with: heard, within: 3000..<7000)
        #expect(merged.map(\.text) == ["before", "new middle", "new more", "after"])
    }

    @Test("A line kept from before is cut short where a new one starts over it")
    func captionsNeverOverlap() {
        let existing = [Self.cue("before", 1000, 3400)]
        let heard = [Self.cue("new", 3000, 4000)]
        let merged = CaptionCues.replacing(existing, with: heard, within: 3000..<7000)
        #expect(merged.map(\.text) == ["before", "new"])
        #expect(merged[0].outMS == 3000)
    }
}
