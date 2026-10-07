// The zoom control that floats in the canvas's bottom right corner while
// somebody is zooming, and goes away by itself five seconds after they stop
// (Next, `next-canvas-zoom-control`).
//
// The user, 2026-10-07: "when I zoom in, I would like a zoom toolbar to appear
// briefly, and then fade out after 5s of not zooming, or fade back in on
// hover. I want to be able to quickly double click the zoom to get to actual
// size (100%)". Zoom is not a tool (2026-09-29), so this is not in the tool
// bar: it is canvas furniture that is only there while zooming is what you are
// doing, and the placement contract names it as the exception it is.
//
// When it is up is `CanvasZoomControl.Clock`; where it sits is
// `CanvasZoomControl.frame`. Both are pure and tested. This file is the clock
// running in real time, and the glass.
import AppKit
import PhotonzCore
import SwiftUI

/// The clock behind one window's canvas zoom control, ticking in real time.
///
/// Held by the editor and told about every zoom, but its own object, so the
/// one view that reads `isShown` is the only view that redraws when it fades.
@MainActor @Observable
final class CanvasZoomControlModel {
    /// Whether the control is up. Changed inside the fade's own animation.
    private(set) var isShown = false
    @ObservationIgnored private var clock = CanvasZoomControl.Clock()
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    /// The canvas zoom changed, by any route a person zooms: a pinch, a key,
    /// a menu row, a double tap, one of the control's own buttons.
    func zoomed() {
        clock.zoomed(at: now)
        settle()
    }

    /// One of the control's buttons was pressed.
    func used() {
        clock.used(at: now)
        settle()
    }

    /// The pointer came onto its spot or left it, or its menu opened or shut.
    func hold(_ hold: CanvasZoomControl.Hold, _ on: Bool) {
        clock.hold(hold, on, at: now)
        settle()
    }

    /// Puts `isShown` where the clock says, fading, and wakes up again when the
    /// clock says it goes.
    private func settle() {
        let shown = clock.isShown(at: now)
        if shown != isShown {
            withAnimation(shown ? .easeOut(duration: CanvasZoomControl.fadeInSeconds)
                                : .easeIn(duration: CanvasZoomControl.fadeOutSeconds)) {
                isShown = shown
            }
        }
        hideTask?.cancel()
        hideTask = nil
        guard shown, let hidesAt = clock.hidesAt else { return }
        let wait = max(0, hidesAt - now)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.settle()
        }
    }
}

/// The control's place on the canvas, and the control while it is up.
///
/// Laid over the whole canvas. The spot it lives on always watches the pointer
/// (so resting there brings it back) but never takes a click, and the control
/// itself is only in the window while it is up, so with it gone a click or a
/// drag in that corner lands on the picture.
struct CanvasZoomControlOverlay: View {
    @Environment(EditorState.self) private var editorState
    /// The control's last measured size, so the spot it watches while hidden
    /// is the size it will come back at.
    @State private var size = CanvasZoomControl.reservedSize

    var body: some View {
        GeometryReader { proxy in
            let frame = CanvasZoomControl.frame(canvasSize: proxy.size, size: size,
                                                avoiding: editorState.canvasZoomControlAvoids(
                                                    canvasSize: proxy.size))
            let model = editorState.canvasZoomControl
            // Pinned by its bottom right corner, so a control that comes back
            // a few points wider or narrower than last time grows to the left
            // and never jumps.
            ZStack(alignment: .bottomTrailing) {
                ZoomSpotWatcher { model.hold(.pointer, $0) }
                    .frame(width: frame.width, height: frame.height)
                if model.isShown {
                    CanvasZoomControlBar(model: model)
                        .fixedSize()
                        .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
                        .transition(.opacity)
                }
            }
            .frame(width: frame.maxX, height: frame.maxY, alignment: .bottomTrailing)
        }
    }
}

/// Zoom out, the percent, zoom in, Fit, on one piece of glass.
private struct CanvasZoomControlBar: View {
    @Environment(EditorState.self) private var editorState
    let model: CanvasZoomControlModel

    var body: some View {
        HStack(spacing: 2) {
            Button {
                model.used()
                editorState.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.tool())
            .toolTip("Zoom Out", key: "\u{2318}-")
            .playtestControl("Zoom Out", detail: "Canvas zoom control")

            percent

            Button {
                model.used()
                editorState.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.tool())
            .toolTip("Zoom In", key: "\u{2318}+")
            .playtestControl("Zoom In", detail: "Canvas zoom control")

            Divider().frame(height: 16).padding(.horizontal, 2)

            Button {
                model.used()
                editorState.zoomToFit()
            } label: {
                Text("Fit").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.tool())
            .toolTip("Zoom to Fit", key: "\u{2318}0")
            .playtestControl("Zoom to Fit", detail: "Canvas zoom control")
        }
        .padding(.horizontal, 4)
        .frame(height: 34)
        .glassEffect(.regular, in: .capsule)
        // The whole capsule takes the click, rim included, so a press aimed a
        // little wide of a button never starts a drag on the picture behind.
        .contentShape(.capsule)
    }

    /// The percent: one click opens the zoom stops, a double click goes to
    /// 100% (`ZoomReadoutClickLid`, the same lid the tool bar's percent had).
    private var percent: some View {
        Menu {
            ForEach(EditorView.zoomStops, id: \.self) { stop in
                Button(stop.formatted(.percent.precision(.fractionLength(0)))) {
                    editorState.setDisplayZoom(CGFloat(stop))
                }
            }
            Divider()
            Button("Fit") { editorState.zoomToFit() }
                .keyboardShortcut("0", modifiers: .command)
            // The key the menu bar's Actual Size has: on a document with time
            // \u{2318}1 is View mode, so there it is \u{2325}\u{2318}0 (`EditorCommands`).
            Button("Actual Size") { editorState.zoomToActualSize() }
                .keyboardShortcut(editorState.documentHasTime ? "0" : "1",
                                  modifiers: editorState.documentHasTime ? [.command, .option] : .command)
        } label: {
            Text(Double(editorState.displayZoom).formatted(.percent.precision(.fractionLength(0))))
                .font(.callout.monospacedDigit())
                .frame(width: 46)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .panelHelp(EditorView.zoomMenuHelp)
        .overlay {
            ZoomReadoutClickLid(isLive: editorState.hasDocument,
                                onActualSize: {
                                    model.used()
                                    editorState.zoomToActualSize()
                                },
                                onMenuOpen: { model.hold(.menu, $0) })
        }
        .playtestControl("Zoom level", detail: "Canvas zoom control")
    }
}

/// The control's spot, watching for the pointer and taking nothing.
///
/// A tracking area rather than `.onHover`: `.onHover` answers only a view
/// that hit tests, and this one must not, or the corner would stop taking
/// clicks while the control is away. Walks rest their pointer on the
/// `playtestHover` marker beside it, since a walk's pointer never moves the
/// real one (`PlaytestPointer`).
private struct ZoomSpotWatcher: View {
    let onPointer: (Bool) -> Void

    var body: some View {
        ZoomSpotTracker(onPointer: onPointer)
            .playtestHover("Canvas zoom spot", perform: onPointer)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct ZoomSpotTracker: NSViewRepresentable {
    let onPointer: (Bool) -> Void

    func makeNSView(context: Context) -> ZoomSpotTrackingView {
        let view = ZoomSpotTrackingView()
        view.onPointer = onPointer
        return view
    }

    func updateNSView(_ view: ZoomSpotTrackingView, context: Context) {
        view.onPointer = onPointer
    }
}

final class ZoomSpotTrackingView: NSView {
    var onPointer: (Bool) -> Void = { _ in }

    /// Never the view a click lands on.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        // No `.enabledDuringMouseDrag`: a drag on the picture that passes
        // through the corner is drawing, not reaching for the zoom.
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onPointer(true) }
    override func mouseExited(with event: NSEvent) { onPointer(false) }
}

extension EditorState {
    /// What the canvas zoom control must keep clear of on a canvas this size:
    /// the floating tool bar while it is up, and the tool settings capsule
    /// above it when one is.
    func canvasZoomControlAvoids(canvasSize: CGSize) -> [CGRect] {
        guard !isWatching else { return [] }
        let bar = Experiments.shared.toolBar
        return [EditorChromeLayout.toolBarFrame(canvasSize: canvasSize,
                                                toolBarWidth: toolBarWidth, bar: bar)]
            + (EditorChromeLayout.toolSettingsFrame(canvasSize: canvasSize,
                                                    width: toolSettingsSize.width,
                                                    height: toolSettingsSize.height,
                                                    bar: bar).map { [$0] } ?? [])
    }
}
