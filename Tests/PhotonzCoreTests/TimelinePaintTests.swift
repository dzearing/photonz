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
            { $0.showsPictures = true },
            { $0.waveformMissing = true },
        ]
        for change in changes {
            var clip = plain
            change(&clip)
            #expect(!TimelinePaint.paints(clip))
        }
    }
}
