// A drag held near an edge of the timeline scrolls it that way: along time at
// the lanes' left and right, up and down the tracks at their top and bottom,
// both at once in a corner (`EdgeAutoscroll` in PhotonzCore has the curve).

import AppKit
import PhotonzCore
import QuartzCore

/// The timeline's edges, for every drag on it that can reach past them: the
/// box over the tracks (`EditorState+TrackRange`), a clip's bar or its edges
/// (`ClipPiecesBar`) and a zoom bar (`ZoomLane`).
///
/// A drag gesture hears nothing while the pointer is still, so the scrolling
/// runs off the display, once a frame, from the last place the drag reported
/// the hand. Each frame it scrolls by what the curve says and hands back to
/// the drag how far it has gone in all (`pannedMS`, `scrolledY`), and the drag
/// puts its own end where the hand now is in the scrolled content. Moving out
/// of the band stops it on the next frame; letting go stops it at once.
@MainActor
final class TimelineEdgeScroll: NSObject {

    /// Where the hand is: across the lanes from their left hand edge, and
    /// down the tracks' own (scrolled) space. No `contentY` for a drag that
    /// only moves along time.
    struct Hand: Equatable {
        var laneX: CGFloat
        var contentY: CGFloat?
    }

    /// What one run did, kept after it ends for a walk to read.
    struct Run: Equatable {
        var pannedMS: Double = 0
        var scrolledY: CGFloat = 0
        /// The time between every two frames it scrolled on, in seconds.
        var frames: [Double] = []
    }

    private(set) var hand: Hand?
    /// The last run, kept after it ends for a walk to read.
    private(set) var run = Run()
    /// How far this run has scrolled, which a drag read as a travel adds to
    /// its own. Nought between runs.
    var pannedMS: Double { hand == nil ? 0 : run.pannedMS }
    var scrolledY: CGFloat { hand == nil ? 0 : run.scrolledY }
    var isFollowing: Bool { hand != nil }

    private var timeArming = EdgeAutoscroll.Arming.armed
    private var rowArming = EdgeAutoscroll.Arming.armed
    /// What the drag does once the timeline has scrolled under the hand.
    /// False ends the run: the drag it belonged to is over.
    private var onScroll: (@MainActor (TimelineEdgeScroll) -> Bool)?
    private weak var editor: EditorState?
    private var link: CADisplayLink?
    private var lastFrame: CFTimeInterval?

    /// The drag's hand, every time it moves. The first call starts a run.
    func follow(_ hand: Hand, editor: EditorState,
                onScroll: @escaping @MainActor (TimelineEdgeScroll) -> Bool) {
        let laneWidth = editor.timelineLaneWidth
        let rows = editor.timelineTracksScrollGeometry
        if self.hand == nil {
            run = Run()
            timeArming = .init(startingAt: hand.laneX, along: laneWidth,
                               band: EdgeAutoscroll.time(laneWidth: laneWidth).band)
            rowArming = hand.contentY.map {
                .init(startingAt: $0 - rows.offsetY, along: rows.viewportHeight, band: EdgeAutoscroll.rows.band)
            } ?? .armed
        } else {
            timeArming.moved(to: hand.laneX, along: laneWidth, band: EdgeAutoscroll.time(laneWidth: laneWidth).band)
            if let y = hand.contentY {
                rowArming.moved(to: y - rows.offsetY, along: rows.viewportHeight, band: EdgeAutoscroll.rows.band)
            }
        }
        self.hand = hand
        self.editor = editor
        self.onScroll = onScroll
        startTicking()
    }

    /// The hand came up, or the drag was called off.
    func end() {
        guard hand != nil else { return }
        hand = nil
        onScroll = nil
        link?.invalidate()
        link = nil
        lastFrame = nil
        if run.pannedMS != 0 { editor?.rememberTimelineView() }
    }

    // MARK: Once a frame

    private func startTicking() {
        guard link == nil else { return }
        let screen = NSApp.windows.first(where: \.isVisible)?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let link = screen.displayLink(target: self, selector: #selector(frame(_:)))
        // Sixty a second, evenly, rather than a ProMotion screen's hundred and
        // twenty: every step redraws the timeline, and a step that cannot
        // finish inside a 120 Hz frame lands on an uneven beat.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func frame(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastFrame = now }
        guard let last = lastFrame else { return }
        // A frame held up for long does not throw the timeline a long way.
        step(seconds: min(now - last, 0.05), interval: now - last)
    }

    /// One frame's worth of scrolling. Public to a walk, which drives it with
    /// its own clock when it needs to.
    func step(seconds: Double, interval: Double? = nil) {
        guard let editor, var hand else { return end() }
        var moved = false

        let laneWidth = editor.timelineLaneWidth
        if editor.isTimelineOpenedOut, laneWidth > 0 {
            let points = EdgeAutoscroll.time(laneWidth: laneWidth)
                .speed(at: hand.laneX, along: laneWidth, arming: timeArming)
                * CGFloat(seconds)
            if points != 0 {
                let before = editor.timelineWindow.startMS
                editor.edgePanTimeline(byMS: Double(points / laneWidth) * editor.motionStripRuler.spanMS)
                let gone = editor.timelineWindow.startMS - before
                if gone != 0 {
                    run.pannedMS += gone
                    moved = true
                }
            }
        }

        if let contentY = hand.contentY {
            let rows = editor.timelineTracksScrollGeometry
            if rows.overflows {
                let next = EdgeAutoscroll.rows.scrolled(offset: rows.offsetY, contentLength: rows.contentHeight,
                                                        viewport: rows.viewportHeight,
                                                        at: contentY - rows.offsetY, seconds: seconds,
                                                        arming: rowArming)
                let gone = next - rows.offsetY
                if abs(gone) > 0.01 {
                    editor.timelineTracksScroll.scrollTo(y: next)
                    // Written now rather than when the scroller reports
                    // back, so the next frame never scrolls from a stale
                    // place and never counts the same points twice.
                    editor.timelineTracksScrollGeometry.offsetY = next
                    // The hand has not moved on the screen, so it has moved
                    // through the tracks by as much as they scrolled.
                    hand.contentY = contentY + gone
                    self.hand = hand
                    run.scrolledY += gone
                    moved = true
                }
            }
        }

        guard moved else { return }
        if let interval { run.frames.append(interval) }
        if onScroll?(self) == false { end() }
    }
}
