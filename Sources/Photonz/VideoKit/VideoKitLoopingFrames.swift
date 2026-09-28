import AppKit
import QuartzCore
import SwiftUI

extension VideoKit {

    /// A tile's loop, drawn once and played for ever by Core Animation: the
    /// frames that differ as pictures, swapped at the moments
    /// they start by the render server, so nothing on the main thread runs
    /// while it plays.
    ///
    /// The caption style tiles and the transition tiles used to redraw
    /// through a `TimelineView` thirty times a second each, and every redraw
    /// laid the whole window out again: a recording open with nothing playing
    /// kept the main thread more than half busy, and every click landed on
    /// top of that (2026-09-27). Played here, the same wait reads quiet.
    ///
    /// Every loop runs on the one clock, so tiles side by side stay in step.
    struct PlayedReel: Sendable {
        let frames: [CGImage]
        let keyTimes: [Double]
        let lapSeconds: Double
    }

    /// One shadow under the frames, the way SwiftUI's `.shadow` draws one.
    struct FrameShadow: Equatable {
        var color: CGColor
        var radius: CGFloat
        var offset: CGSize = .zero
    }

    /// The played reel on a layer, centred at its own size, under as many
    /// shadows as it is given (the first nearest the pictures). Clicks go
    /// straight through to whatever holds it.
    struct LoopingFrames: NSViewRepresentable {
        let reel: PlayedReel
        let scale: CGFloat
        var shadows: [FrameShadow] = []

        func makeNSView(context: Context) -> LoopingFramesView {
            let view = LoopingFramesView()
            view.show(reel, scale: scale, shadows: shadows)
            return view
        }

        func updateNSView(_ view: LoopingFramesView, context: Context) {
            view.show(reel, scale: scale, shadows: shadows)
        }
    }

    final class LoopingFramesView: NSView {
        /// Innermost: the pictures. Each layer out from it carries one shadow
        /// of everything inside it, as stacked `.shadow`s do.
        private let pictures = CALayer()
        private var rings: [CALayer] = []
        private var playing: [CGImage] = []
        private var shadows: [FrameShadow] = []

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layer?.masksToBounds = false
            pictures.contentsGravity = .center
            layer?.addSublayer(pictures)
            setAccessibilityElement(false)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for ring in rings { ring.frame = bounds }
            pictures.frame = bounds
            CATransaction.commit()
        }

        func show(_ reel: PlayedReel, scale: CGFloat, shadows: [FrameShadow]) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            pictures.contentsScale = scale
            if shadows != self.shadows { wear(shadows) }
            // Only a new reel starts again: setting the same one on every
            // pass would restart the words mid-sentence.
            guard reel.frames.count != playing.count
                || !zip(reel.frames, playing).allSatisfy({ $0 === $1 }) else { return }
            playing = reel.frames
            pictures.removeAnimation(forKey: "loop")
            pictures.contents = reel.frames.first
            guard reel.frames.count > 1, reel.lapSeconds > 0 else { return }
            let loop = CAKeyframeAnimation(keyPath: "contents")
            loop.values = reel.frames
            loop.keyTimes = reel.keyTimes.map { NSNumber(value: $0) }
            loop.calculationMode = .discrete
            loop.duration = reel.lapSeconds
            loop.repeatCount = .infinity
            loop.isRemovedOnCompletion = false
            // On the one clock: a tile that starts late joins the others part
            // way through the lap rather than from the top.
            let now = CACurrentMediaTime()
            loop.beginTime = pictures.convertTime(now, from: nil)
                - now.truncatingRemainder(dividingBy: reel.lapSeconds)
            pictures.add(loop, forKey: "loop")
        }

        private func wear(_ shadows: [FrameShadow]) {
            self.shadows = shadows
            for ring in rings { ring.removeFromSuperlayer() }
            pictures.removeFromSuperlayer()
            rings = []
            var inside: CALayer = pictures
            for shadow in shadows {
                let ring = CALayer()
                ring.frame = bounds
                ring.masksToBounds = false
                ring.addSublayer(inside)
                ring.shadowColor = shadow.color
                ring.shadowOpacity = 1
                ring.shadowRadius = shadow.radius
                // Layers here are drawn bottom-left up; SwiftUI's offset is
                // top-down.
                ring.shadowOffset = CGSize(width: shadow.offset.width, height: -shadow.offset.height)
                rings.append(ring)
                inside = ring
            }
            layer?.addSublayer(inside)
        }
    }

    /// Played reels already drawn, by what they show and the size they show
    /// it at, so a panel coming back or a tile scrolled into view again plays
    /// at once instead of drawing its frames over.
    @MainActor enum PlayedReels {
        private static var drawn: [AnyHashable: PlayedReel] = [:]
        private static var order: [AnyHashable] = []
        /// A few panels' worth of tiles at a couple of sizes.
        private static let limit = 48

        static subscript(key: AnyHashable) -> PlayedReel? { drawn[key] }

        static func keep(_ reel: PlayedReel, for key: AnyHashable) {
            if drawn.updateValue(reel, forKey: key) == nil { order.append(key) }
            while order.count > limit { drawn[order.removeFirst()] = nil }
        }
    }
}
