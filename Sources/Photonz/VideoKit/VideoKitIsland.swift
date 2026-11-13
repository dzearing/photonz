import AppKit
import Observation
import QuartzCore
import SwiftUI

// MARK: - What moves with the playhead, drawn without SwiftUI

extension VideoKit {
    /// A piece of the window that follows the playhead on every frame, drawn
    /// with Core Animation layers that it moves itself: the line across the
    /// tracks, the played part and the knob of the scrub bar, the time on the
    /// transport, the mark on the time scroller.
    ///
    /// Each pass SwiftUI makes over the editor window costs about as much again
    /// as the timeline has views, whatever starts it (`docs/design/video.md`
    /// 8f). As SwiftUI views these four pieces each started a pass per frame of
    /// playback and per move of a hand scrubbing, and so did each in a little
    /// SwiftUI host of its own, because a host that draws again is laid out
    /// again, and the window with it. On the 6 minute reference edit a medium
    /// scrub was answered at 73 to 82 of the display's 240 refreshes; with
    /// nothing in the window following the playhead, at 240 (2026-11-13,
    /// `a-long-edit-with-transitions-plays-scrubs-and-ed`). Moving a layer
    /// lays nothing out.
    ///
    /// `value` is read and watched here, outside any pass of the window's, so
    /// the window never watches what it reads; read inside a SwiftUI body it
    /// would be. `paint` is called with what it returned, only when that comes
    /// back different, and whenever the island is resized or changes
    /// appearance; round the value to what can be seen (half a point, a
    /// whole second) and a frame that changes nothing paints nothing. Clicks
    /// go through to whatever is under the island: it only ever draws, and
    /// the control it sits in keeps its gestures, its hover and its menu.
    struct LayerIsland<Value: Equatable>: NSViewRepresentable {
        let value: () -> Value
        let paint: (Value, IslandCanvas) -> Void

        init(_ value: @escaping () -> Value, paint: @escaping (Value, IslandCanvas) -> Void) {
            self.value = value
            self.paint = paint
        }

        func makeNSView(context: Context) -> IslandView<Value> {
            IslandView(value: value, paint: paint)
        }

        func updateNSView(_ view: IslandView<Value>, context: Context) {
            view.update(value: value, paint: paint)
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsView: IslandView<Value>,
                          context: Context) -> CGSize? {
            proposal.replacingUnspecifiedDimensions(by: .zero)
        }
    }

    /// What an island paints on: a layer-backed view that never takes a click,
    /// with its layers kept by name. Its layers measure from the bottom left,
    /// as Core Animation's do.
    class IslandCanvas: NSView {
        private var named: [String: CALayer] = [:]

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override var wantsUpdateLayer: Bool { true }

        /// Never takes a click: what is under it does.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// The layer called `name`, made by `make` the first time it is asked
        /// for and laid over the ones before it.
        func layer<L: CALayer>(_ name: String, _ make: () -> L) -> L {
            if let kept = named[name] as? L { return kept }
            let made = make()
            made.contentsScale = window?.backingScaleFactor ?? 2
            layer?.addSublayer(made)
            named[name] = made
            return made
        }

        /// Whether the island is drawn dark.
        var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

        /// One of the kit's tones as the island's appearance draws it.
        func color(_ tone: Tone, opacity: Double = 1) -> CGColor {
            color(tone.color(isDark ? .dark : .light), opacity: opacity)
        }

        /// A colour as the island's appearance draws it.
        func color(_ color: Color, opacity: Double = 1) -> CGColor {
            var resolved = CGColor(gray: 0, alpha: 0)
            effectiveAppearance.performAsCurrentDrawingAppearance {
                resolved = NSColor(color).withAlphaComponent(NSColor(color).alphaComponent * opacity).cgColor
            }
            return resolved
        }

        fileprivate func repaint() {}

        override func layout() {
            super.layout()
            repaint()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            repaint()
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            let scale = window?.backingScaleFactor ?? 2
            for kept in named.values { kept.contentsScale = scale }
            repaint()
        }
    }

    /// The island as the window holds it: it reads and watches its value, and
    /// paints when that changes.
    final class IslandView<Value: Equatable>: IslandCanvas {
        private var value: () -> Value
        private var paint: (Value, IslandCanvas) -> Void
        private var shown: Value
        /// Which watch is the live one: one left over from before an update
        /// says nothing when it fires.
        private var watch = 0
        private var watchQueued = false

        init(value: @escaping () -> Value, paint: @escaping (Value, IslandCanvas) -> Void) {
            self.value = value
            self.paint = paint
            // Read once where the island is made, so its first frame is right;
            // the window watches this one read until its next pass over the
            // island, which reads nothing.
            shown = value()
            super.init(frame: .zero)
            queueWatch()
        }

        /// New ways to read and paint, from a pass of the window's: painted at
        /// once with what was last read, read again (and watched) after it.
        func update(value: @escaping () -> Value, paint: @escaping (Value, IslandCanvas) -> Void) {
            self.value = value
            self.paint = paint
            repaint()
            queueWatch()
        }

        /// Watching starts on a turn of its own, never inside a pass of the
        /// window's, which would watch what it reads too.
        private func queueWatch() {
            watch += 1
            guard !watchQueued else { return }
            watchQueued = true
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.watchQueued = false
                    self?.readAndWatch()
                }
            }
        }

        private func readAndWatch() {
            let mine = watch
            let now = withObservationTracking { value() } onChange: { [weak self] in
                // Told before the change lands: read on the next turn.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.watch == mine else { return }
                        self.readAndWatch()
                    }
                }
            }
            if now != shown {
                shown = now
                repaint()
            }
        }

        fileprivate override func repaint() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            paint(shown, self)
            CATransaction.commit()
        }
    }
}
