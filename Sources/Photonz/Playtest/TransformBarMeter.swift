// When the transform bar came and went, and where it sat, for a walk to hold
// it to one frame and to the canvas (`expectTransformBar`).
//
// "Within one frame" is counted in display refreshes, not milliseconds: from
// the moment the editor asks for the bar to come or go, how many times the
// screen refreshed before the bar joined or left the window. A refresh with
// the main thread free and the bar not yet there is a frame shown without
// it; while the canvas is busy drawing the picture a turn just changed, no
// refresh fires at all, and the bar arrives on the very frame the turned
// picture does.
//
// Probe builds only; the shipping app carries none of this.
#if PHOTONZ_PLAYTEST
import AppKit
import CoreGraphics
import PhotonzCore
import QuartzCore

@MainActor
final class TransformBarMeter: NSObject {
    static let shared = TransformBarMeter()

    /// Everything the bar was placed by, as it was last laid out.
    struct Place: Equatable {
        var canvas: CGSize
        var floor: CGFloat
        var box: CGRect
        var side: TransformBar.Side
    }

    /// When the editor last asked for the bar to come or go.
    private var askedAt: CFTimeInterval?
    private var refreshes = 0
    private var link: CADisplayLink?
    /// How long the last ask took to reach the window, in milliseconds.
    private(set) var lastLatencyMS: Double?
    /// How many times the screen refreshed between the last ask and the bar
    /// reaching the window.
    private(set) var lastFrames: Int?
    /// Whether the bar is in the window right now.
    private(set) var isDrawn = false
    var size: CGSize = .zero
    var place: Place?

    /// The editor took the bar up or down.
    func asked() {
        askedAt = CACurrentMediaTime()
        refreshes = 0
        if link == nil, let screen = NSScreen.main {
            let link = screen.displayLink(target: self, selector: #selector(refreshed))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    @objc private func refreshed(_ link: CADisplayLink) {
        refreshes += 1
        // Nobody arrived for a long while: stop counting rather than tick on.
        if refreshes > 120 { stop() }
    }

    /// The bar joined the window, or left it.
    func drawn(_ shown: Bool) {
        isDrawn = shown
        if let askedAt {
            lastLatencyMS = (CACurrentMediaTime() - askedAt) * 1000
            lastFrames = refreshes
        }
        askedAt = nil
        stop()
    }

    private func stop() {
        link?.invalidate()
        link = nil
    }

    /// Where the bar sits, in the canvas view's points.
    var frame: CGRect? {
        guard let place, size != .zero else { return nil }
        return TransformBar.frame(around: place.box, bar: size, canvas: place.canvas,
                                  floor: place.floor, side: place.side)
    }
}
#endif
