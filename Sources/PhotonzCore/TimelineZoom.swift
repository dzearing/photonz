import CoreGraphics
import Foundation

/// **How far the timeline is opened out, and which stretch of the document is
/// on screen** (`docs/design/video-surface.md`, the `.tlbar` row).
///
/// The timeline has always drawn the whole document across whatever width the
/// window happens to be. An eight second recording fits and reads fine. A five
/// minute one, which is what a real screen recording is, becomes a bar a few
/// hundred points wide: every cut is a guess and the waveform under it is a
/// smear.
///
/// Zoom is the window moving, and nothing else. The ruler stops measuring the
/// whole document and measures the stretch you are working on, so every bar,
/// join, waveform and playhead on it lands through the same one piece of
/// arithmetic it always did (`MotionStripRuler`). There is no second layout
/// and no zoomed mode.
///
/// Two numbers say all of it: how much smaller the window is than the
/// document, and where its left hand edge is.
public struct TimelineZoom: Hashable, Sendable, Codable {

    /// How many times smaller the window is than the document. One is the
    /// whole document across the width, which is what the strip has always
    /// done and what Fit goes back to. Under one is wider than the document:
    /// the document on the left and empty room after its end.
    public var scale: Double
    /// The moment at the left hand edge of the strip.
    public var startMS: Double

    /// The whole document, across the width.
    public static let fit = TimelineZoom()

    /// As far in as it goes: a quarter of a second of the recording across
    /// the whole width. On a lane six hundred points wide one frame of a
    /// thirty frame recording is eighty points, so a pinch runs from the whole
    /// document down to single frames you can put a cut between (user
    /// 2026-09-28). It was a whole second, thirty frames across, until then.
    public static let closestVisibleMS: Double = 250

    /// As far out as it goes: twice the document across the width, so there
    /// is room after the last clip to drop a new one into (user 2026-10-27).
    /// Fit used to be the widest view, and a clip could only be dropped past
    /// the end by aiming at the very last pixel of the lane.
    public static let farthestOutScale: Double = 0.5

    /// One press of the plus or the minus. Doubling is the step every timeline
    /// in the world uses, and it means five minutes reaches its closest window
    /// in eight presses rather than in fifty.
    public static let step: Double = 2

    public init(scale: Double = 1, startMS: Double = 0) {
        self.scale = scale
        self.startMS = startMS
    }

    // MARK: How far in it is allowed to go

    /// The most a document of this length can be opened out. A document
    /// already shorter than the closest window has nothing to open out into,
    /// so it goes no further in than fit.
    public static func widestScale(documentMS: Double) -> Double {
        max(1, documentMS / closestVisibleMS)
    }

    /// A scale kept between as far out and as far in as this document goes.
    static func allowed(_ scale: Double, documentMS: Double) -> Double {
        min(max(farthestOutScale, scale), widestScale(documentMS: documentMS))
    }

    /// How much time is on screen. More than the document once it is zoomed
    /// out past Fit.
    public func visibleMS(documentMS: Double) -> Double {
        let length = max(1, documentMS)
        return length / Self.allowed(scale, documentMS: length)
    }

    /// Exactly the whole document across the width: what Fit puts back.
    public var isFit: Bool { abs(scale - 1) <= 0.0001 }

    /// All of the document is on screen, at Fit or zoomed out past it into
    /// the room after its end. Nothing is hidden, so there is nothing to
    /// scroll to and nothing for a playhead to chase.
    public var showsWholeDocument: Bool { scale <= 1.0001 }

    public var canZoomOut: Bool { scale > Self.farthestOutScale + 0.0001 }

    public func canZoomIn(documentMS: Double) -> Bool {
        scale < Self.widestScale(documentMS: documentMS) - 0.0001
    }

    /// Inside the document, at a scale it is allowed to be. Every way of
    /// making one of these ends here, so a window can never hang off the
    /// start of the strip, and only runs past the end when it is wider than
    /// the whole document, which is the room a clip is dropped into.
    public func clamped(documentMS: Double) -> TimelineZoom {
        let length = max(1, documentMS)
        let scale = Self.allowed(self.scale, documentMS: length)
        let span = length / scale
        let start = min(max(0, startMS), max(0, length - span))
        return TimelineZoom(scale: scale, startMS: start)
    }

    public func contains(ms: Double, documentMS: Double) -> Bool {
        let span = visibleMS(documentMS: documentMS)
        return ms >= startMS - 0.001 && ms <= startMS + span + 0.001
    }

    // MARK: Moving in and out

    /// Open out (or close up) to a given scale, **keeping the moment you are
    /// looking at exactly where it is on screen**.
    ///
    /// This is the whole of what makes a zoom control usable. Zooming about
    /// the left hand edge would throw you back towards the start of the
    /// recording on every press, so the cut you were lining up would be the
    /// first thing you lost.
    public func zoomed(toScale wanted: Double, anchorMS: Double,
                       documentMS: Double) -> TimelineZoom {
        let length = max(1, documentMS)
        let span = visibleMS(documentMS: length)
        let through = min(max(0, (anchorMS - startMS) / span), 1)
        let scale = Self.allowed(wanted, documentMS: length)
        let landing = length / scale
        return TimelineZoom(scale: scale, startMS: anchorMS - through * landing)
            .clamped(documentMS: length)
    }

    /// A press stops on Fit when it crosses it, whichever way it is going, so
    /// the whole document across the width is always one press away rather
    /// than skipped between 1.2x and 0.6x.
    public func steppedIn(anchorMS: Double, documentMS: Double) -> TimelineZoom {
        let wanted = scale * Self.step
        return zoomed(toScale: scale < 0.9999 && wanted > 1 ? 1 : wanted,
                      anchorMS: anchorMS, documentMS: documentMS)
    }

    public func steppedOut(anchorMS: Double, documentMS: Double) -> TimelineZoom {
        let wanted = scale / Self.step
        return zoomed(toScale: scale > 1.0001 && wanted < 1 ? 1 : wanted,
                      anchorMS: anchorMS, documentMS: documentMS)
    }

    // MARK: Moving along

    public func panned(byMS delta: Double, documentMS: Double) -> TimelineZoom {
        TimelineZoom(scale: scale, startMS: startMS + delta).clamped(documentMS: documentMS)
    }

    /// The window put around a moment, which is what clicking somewhere on the
    /// overview means.
    public func centred(onMS ms: Double, documentMS: Double) -> TimelineZoom {
        TimelineZoom(scale: scale, startMS: ms - visibleMS(documentMS: documentMS) / 2)
            .clamped(documentMS: documentMS)
    }

    /// The least the window has to move for a moment to be on screen.
    ///
    /// What playing a zoomed timeline does. It **pages**: when the playhead
    /// runs off the end the window jumps a whole span forward and the playhead
    /// lands near its left hand edge, so what is about to happen is on screen.
    /// A window that crept along a frame at a time would put the playhead
    /// permanently against the right hand edge, where there is nothing ahead
    /// of it to see and the whole strip slides under the pointer.
    public func revealing(ms: Double, documentMS: Double) -> TimelineZoom {
        guard !showsWholeDocument, !contains(ms: ms, documentMS: documentMS) else { return self }
        let span = visibleMS(documentMS: documentMS)
        return TimelineZoom(scale: scale, startMS: ms - span * 0.1)
            .clamped(documentMS: documentMS)
    }

    // MARK: What it says

    /// What is on screen, in the words the transport uses: `1:00 to 1:30`, or
    /// `all 5:00` when the whole thing is.
    public func reading(documentMS: Double) -> String {
        guard !showsWholeDocument else { return "all " + MotionStripRuler.timecode(documentMS) }
        let span = visibleMS(documentMS: documentMS)
        return MotionStripRuler.timecode(startMS) + " to "
            + MotionStripRuler.timecode(startMS + span)
    }
}

/// **A stretch of the timeline as it is actually drawn.**
///
/// A clip's bar on a timeline opened right out is wider than any screen: at
/// three hundred times, five minutes of recording is a hundred and eighty
/// thousand points. Nobody can see the ends of it, and a waveform sampled
/// across it is a hundred and eighty thousand columns of nothing.
///
/// So what is drawn is the part of it in the window, plus enough slack either
/// side to carry its rounded ends and its grips off screen where the strip
/// clips them away. The drawing is identical and the work is bounded by the
/// width of the window rather than by how far in the zoom has gone.
public struct TimelineSpan: Hashable, Sendable {
    /// Where to draw it, in the lane's own points.
    public let x: CGFloat
    /// How wide to draw it. Nought where none of it is on screen.
    public let width: CGFloat
    /// How much of the original was cut off the front, as a share of it, so
    /// anything drawn INSIDE the span — a waveform, a level line — can be
    /// sampled over the part that is still on screen.
    public let startFraction: CGFloat
    public let endFraction: CGFloat

    /// Room left either side of the window so a clipped end never shows a
    /// rounded corner in the middle of the strip.
    public static let slack: CGFloat = 60

    public static func drawn(x: CGFloat, width: CGFloat, across visibleWidth: CGFloat,
                             slack: CGFloat = TimelineSpan.slack) -> TimelineSpan {
        drawn(x: x, width: width, from: 0, to: visibleWidth, slack: slack)
    }

    /// The same, kept to what lies between two edges rather than to a width
    /// from nought: a bar drawn in its own points, from its own start, is cut
    /// down to the stretch it is drawn across (`TimelineDrawnStretch`).
    public static func drawn(x: CGFloat, width: CGFloat, from leading: CGFloat, to trailing: CGFloat,
                             slack: CGFloat = TimelineSpan.slack) -> TimelineSpan {
        let left = leading - slack
        let right = trailing + slack
        let start = max(x, left)
        let end = min(x + width, right)
        guard width > 0, end > start else {
            return TimelineSpan(x: x, width: 0, startFraction: 0, endFraction: 0)
        }
        return TimelineSpan(x: start, width: end - start,
                            startFraction: (start - x) / width,
                            endFraction: (end - x) / width)
    }
}

/// **The stretch of the timeline a clip's bar is drawn across**: the window and
/// at least half a window more either side.
///
/// A scroll along time moves the window every frame. A bar cut down to the
/// window itself had to be drawn again on every one of those frames, every bar
/// on every track, and a scroll held at an edge ran one frame in twenty late
/// (`scrolling-the-timeline-along-time-keeps-every-fr`). Cut down to this
/// instead, a bar only has to be drawn again once the window has gone half its
/// own width; in between it is slid along as it stands.
///
/// It is written down where the window is written and read back against the
/// document as it is when read, which may have grown or shrunk since: so what
/// is kept is where the window's left edge stood, rounded down to a step of
/// half a window, and the step.
public struct TimelineDrawnStretch: Hashable, Sendable {
    /// The window's left edge when this was written, rounded down to a whole
    /// number of steps.
    public let anchorMS: Double
    /// Half the window, when this was written.
    public let stepMS: Double

    public init(windowStartMS: Double, visibleMS: Double) {
        let step = max(1, visibleMS / 2)
        stepMS = step
        anchorMS = (max(0, windowStartMS) / step).rounded(.down) * step
    }

    /// Where the window's left edge is, somewhere inside: the edge written
    /// down is no more than a step past the anchor, and a window held back
    /// against the end of a shorter document is held back no further than
    /// the anchor is.
    public func leftEdgeMS(visibleMS: Double, documentMS: Double) -> ClosedRange<Double> {
        let anchor = min(anchorMS, max(0, documentMS - visibleMS))
        return anchor...(anchor + stepMS)
    }

    /// What a bar is drawn across: wherever in its range the window's left
    /// edge is, the window and a step more either side.
    public func stretchMS(visibleMS: Double, documentMS: Double) -> ClosedRange<Double> {
        let edge = leftEdgeMS(visibleMS: visibleMS, documentMS: documentMS)
        return max(0, edge.lowerBound - stepMS)...(edge.upperBound + stepMS + visibleMS)
    }
}
