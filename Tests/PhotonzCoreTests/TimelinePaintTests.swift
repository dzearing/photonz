import CoreGraphics
import Testing
@testable import PhotonzCore

/// Which clips a busy lane paints as one layer rather than as a view each
/// (`TimelinePaint`, `the-timeline-of-an-hour-long-edit-scrolls-zooms`).
@Suite struct TimelinePaintTests {
    private let plain = TimelinePaint.Clip()

    @Test func aQuietLaneBuildsEveryClip() {
        #expect(!TimelinePaint.lanePaints(clipsInSight: TimelinePaint.busyLane - 1))
        #expect(TimelinePaint.lanePaints(clipsInSight: TimelinePaint.busyLane))
        #expect(TimelinePaint.lanePaints(clipsInSight: 500))
    }

    /// A long track paints whatever of it is in sight, a handful of clips
    /// zoomed right in included: on the hour-long reference edit a lane
    /// zoomed to half a minute holds a few clips, each a full bar of pictures
    /// slid along on every frame of a scroll (2026-11-15).
    @Test func aLongTrackPaintsWhateverIsInSight() {
        #expect(TimelinePaint.lanePaints(clipsInSight: 3, clipsOnTrack: TimelinePaint.busyLane))
        #expect(TimelinePaint.lanePaints(clipsInSight: 0, clipsOnTrack: 500))
        #expect(!TimelinePaint.lanePaints(clipsInSight: 3, clipsOnTrack: TimelinePaint.busyLane - 1))
        #expect(TimelinePaint.lanePaints(clipsInSight: TimelinePaint.busyLane,
                                         clipsOnTrack: TimelinePaint.busyLane))
    }


    @Test func aPlainClipIsPainted() {
        #expect(TimelinePaint.paints(plain))
    }

    @Test func aClipSomebodyIsWorkingOnKeepsItsView() {
        var kept = plain
        kept.isKept = true
        #expect(!TimelinePaint.paints(kept))
    }

    /// Everything the full bar draws that the painting does not: each keeps
    /// the clip a view, so what the timeline shows never changes.
    @Test func whatThePaintingDoesNotDrawKeepsTheView() {
        let changes: [(inout TimelinePaint.Clip) -> Void] = [
            { $0.isPlainKind = false },
            { $0.pieceCount = 2 },
            { $0.isHeld = true },
            { $0.pictureHidden = true },
            { $0.hasBadge = true },
            { $0.hasKeys = true },
            { $0.hasDrift = true },
            { $0.levelHasPoints = true },
            { $0.soundHasBadge = true },
            { $0.waveformMissing = true },
        ]
        for change in changes {
            var clip = plain
            change(&clip)
            #expect(!TimelinePaint.paints(clip))
        }
    }

    // MARK: - Laid against a fixed origin

    private static let hour = 60 * 60 * 1000

    private static func window(scale: Double, startMS: Double) -> MotionStripRuler {
        MotionStripRuler(documentMS: hour, zoom: TimelineZoom(scale: scale, startMS: startMS))
    }

    /// A scroll that stays inside one drawn stretch hands the painting the
    /// very same canvas, so it is slid along rather than painted again.
    @Test func aScrollInsideOneStretchKeepsTheSameCanvas() {
        let visible = Double(Self.hour) / 120
        let stretch = TimelineDrawnStretch(windowStartMS: 600_000, visibleMS: visible)
            .stretchMS(visibleMS: visible, documentMS: Double(Self.hour))
        let first = TimelinePaint.Canvas(drawnMS: stretch, ruler: Self.window(scale: 120, startMS: 600_000),
                                         laneWidth: 1200)
        for start in stride(from: 600_000.0, to: 600_000 + visible / 2, by: 997) {
            let later = TimelinePaint.Canvas(drawnMS: stretch, ruler: Self.window(scale: 120, startMS: start),
                                             laneWidth: 1200)
            #expect(later == first)
        }
    }

    /// Slid by its offset, every moment on the canvas lands where the
    /// window's own ruler puts it, to within a pixel.
    @Test func slidByItsOffsetEveryMomentLandsWhereTheWindowPutsIt() {
        let visible = Double(Self.hour) / 120
        let stretch = TimelineDrawnStretch(windowStartMS: 600_000, visibleMS: visible)
            .stretchMS(visibleMS: visible, documentMS: Double(Self.hour))
        for start in stride(from: 600_000.0, to: 600_000 + visible / 2, by: 1531) {
            let window = Self.window(scale: 120, startMS: start)
            let canvas = TimelinePaint.Canvas(drawnMS: stretch, ruler: window, laneWidth: 1200)
            let offset = canvas.offset(in: window, laneWidth: 1200, scale: 2)
            // On a pixel, so the painting never sits between two.
            #expect((offset * 2).rounded() == offset * 2)
            for ms in stride(from: stretch.lowerBound, through: stretch.upperBound, by: 4111) {
                let painted = 1200 * canvas.ruler.fraction(ofMS: ms) + offset
                let lane = 1200 * window.fraction(ofMS: ms)
                #expect(abs(painted - lane) <= 0.5)
            }
        }
    }

    @Test func theCanvasIsAsWideAsTheStretch() {
        let window = Self.window(scale: 4, startMS: 0)
        let canvas = TimelinePaint.Canvas(drawnMS: 1000...(1000 + window.spanMS * 2), ruler: window,
                                          laneWidth: 1000)
        #expect(abs(canvas.width - 2000) < 1e-6)
        #expect(canvas.ruler.startMS == 1000)
        #expect(canvas.ruler.spanMS == window.spanMS)
    }

    /// A name is kept in sight while its clip runs off the lane's left edge,
    /// which moves with every frame of a scroll: only a clip that may hang
    /// off it somewhere in this stretch has its name drawn against the
    /// window rather than the canvas.
    @Test func onlyAClipAcrossTheLeftEdgeHasItsNameFollowTheWindow() {
        let edge = 10_000.0...12_000.0
        #expect(TimelinePaint.nameFollowsTheEdge(fromMS: 9_000, toMS: 20_000, leftEdgeMS: edge))
        #expect(TimelinePaint.nameFollowsTheEdge(fromMS: 11_000, toMS: 20_000, leftEdgeMS: edge))
        #expect(!TimelinePaint.nameFollowsTheEdge(fromMS: 12_500, toMS: 20_000, leftEdgeMS: edge))
        #expect(!TimelinePaint.nameFollowsTheEdge(fromMS: 2_000, toMS: 9_500, leftEdgeMS: edge))
    }
}
