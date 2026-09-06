import AppKit
import SwiftUI

// The design-language hint tooltip (UX-PATTERNS D12; tooltip.css / tooltip.js
// in the mock): one short label, an optional key printed quieter, on an
// opaque dark-slate plate with a blunted beak aimed at the control it names.
//
// Why not `.help()`: the system help tag is a bare yellow box that cannot be
// styled or placed, appears on its own schedule, and, on the floating tool
// bar, was not appearing at all for the person using the app. This one is
// owned end to end: hover detection, timing, placement and drawing.
//
// The contract, in the order the mock states it:
//  * It appears once the pointer has RESTED on a control, not merely crossed
//    it: every move restarts the clock, so sweeping the bar pops nothing.
//  * Once one is open, moving to the next control swaps the label almost at
//    once and in place, so a walk along the bar reads like one label
//    following the pointer.
//  * Leaving waits a short grace period, so slipping onto the gap between two
//    buttons does not evaporate the label you were reading. A press, a key,
//    a scroll, or the control leaving the window hides it at once.
//  * Placement: on the side the control asks for (above by default), by a
//    gap, flipped to the other side when there is no room, clamped to the
//    screen with the beak walked back to the control. It NEVER resizes to fit.
//  * It is never in the way: the panel ignores the mouse, so it cannot steal
//    a hover or block a click.

/// One floating panel for the whole app, moved and re-labelled as needed.
@MainActor
final class HintTooltipController {
    static let shared = HintTooltipController()

    /// Timings, from the mock's tooltip.js.
    static let restDelay: TimeInterval = 1.0
    static let swapDelay: TimeInterval = 0.06
    static let hideGrace: TimeInterval = 0.45
    /// Clear space between the beak's tip and the control.
    static let gap: CGFloat = 6
    /// Minimum distance from the screen's edge.
    static let edge: CGFloat = 6

    enum Side { case top, bottom }

    /// The anchor whose label is on screen.
    private(set) var current: HintAnchorView?
    /// The anchor a show is owed to. Tracked apart from `current` because
    /// there is a long window where a label is owed to a control the pointer
    /// may already have left.
    private var pending: HintAnchorView?
    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var panel: NSPanel?
    private var parent: NSWindow?
    private var side: Side = .top
    private var eventMonitor: Any?
    private var closeObserver: NSObjectProtocol?

    // MARK: - Pointer

    func pointerEntered(_ anchor: HintAnchorView) {
        hideWork?.cancel()
        hideWork = nil
        guard anchor !== current else { return }
        showWork?.cancel()
        pending = anchor
        let warm = current != nil && panel?.isVisible == true
        schedule(anchor, after: warm ? Self.swapDelay : Self.restDelay, warm: warm)
    }

    /// The rest clock: a move over the queued control pushes the show back.
    /// Once one is open the swap path owns the timing instead.
    func pointerMoved(_ anchor: HintAnchorView) {
        guard pending === anchor, current == nil else { return }
        showWork?.cancel()
        schedule(anchor, after: Self.restDelay, warm: false)
    }

    func pointerExited(_ anchor: HintAnchorView) {
        guard anchor === current || anchor === pending else { return }
        if current == nil {
            // Never opened: just cancel, so a quick pass leaves nothing owed.
            showWork?.cancel()
            pending = nil
            return
        }
        hide(after: Self.hideGrace)
    }

    /// The control left the window: a label never outlives what it labels.
    func anchorRemoved(_ anchor: HintAnchorView) {
        guard anchor === current || anchor === pending else { return }
        dismiss()
    }

    /// Hide at once: a press, a key, a scroll, the window closing.
    func dismiss() {
        showWork?.cancel()
        hideWork?.cancel()
        pending = nil
        current = nil
        fadeOut()
    }

    // MARK: - For the playtest harness

    /// Whether a label is on screen or owed for this control.
    func isWatching(_ anchor: HintAnchorView) -> Bool {
        anchor === current || anchor === pending
    }

    /// What is on screen, for a walk's log: "Arrow (A) above (x, y)".
    var visibleDescription: String? {
        guard let current, let panel, panel.isVisible, panel.alphaValue > 0 else { return nil }
        let key = current.key.map { " (\($0))" } ?? ""
        let f = panel.frame
        return "\(current.label)\(key) \(side == .top ? "above" : "below") at (\(Int(f.minX)), \(Int(f.minY))) \(Int(f.width))x\(Int(f.height))"
    }

    /// The tooltip panel while it floats over `window`, so an offscreen
    /// render of that window can include it.
    func panel(over window: NSWindow) -> NSPanel? {
        guard let panel, panel.isVisible, current != nil, parent === window else { return nil }
        return panel
    }

    // MARK: - Showing

    private func schedule(_ anchor: HintAnchorView, after delay: TimeInterval, warm: Bool) {
        let work = DispatchWorkItem { [weak self, weak anchor] in
            guard let self, let anchor else { return }
            self.show(anchor, warm: warm)
        }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func show(_ anchor: HintAnchorView, warm: Bool) {
        pending = nil
        guard let window = anchor.window, let target = anchor.screenFrame else { return }
        hideWork?.cancel()
        hideWork = nil
        current = anchor

        let panel = ensurePanel()
        if parent !== window {
            parent?.removeChildWindow(panel)
            parent = window
            watchForClose(window)
        }

        // Measure the plate with a neutral beak, then place, then draw for
        // real with the beak aimed at the control.
        let probe = NSHostingView(rootView: HintTooltipView(label: anchor.label, key: anchor.key, side: .top, beakX: 12))
        let size = probe.fittingSize
        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1600, height: 1000)

        // The control says which side reads better for it and the screen gets
        // the last word. Above is right for the tool bar, which sits low; the
        // capture history is pinned to the TOP of the screen and its buttons
        // sit under the picture they belong to, so a label above one would
        // land on that picture. Either way, no room means the other side.
        var side = anchor.preferredSide
        func place(_ side: Side) -> CGPoint {
            CGPoint(x: target.midX - size.width / 2,
                    y: side == .top ? target.maxY + Self.gap : target.minY - Self.gap - size.height)
        }
        var origin = place(side)
        let fits = side == .top
            ? origin.y + size.height <= visible.maxY - Self.edge
            : origin.y >= visible.minY + Self.edge
        if !fits {
            side = side == .top ? .bottom : .top
            origin = place(side)
        }
        origin.x = min(max(origin.x, visible.minX + Self.edge), visible.maxX - size.width - Self.edge)
        origin.y = max(origin.y, visible.minY + Self.edge)
        // The beak points at the control, not at the tooltip's own middle.
        let beakX = min(max(target.midX - origin.x, 14), size.width - 14)
        self.side = side

        let hosting = NSHostingView(rootView: HintTooltipView(label: anchor.label, key: anchor.key, side: side, beakX: beakX))
        hosting.frame = CGRect(origin: .zero, size: size)
        panel.contentView = hosting
        let frame = CGRect(origin: origin, size: size)
        // The tooltip is part of the window it labels: it follows the window's
        // own alpha (a playtest keeps its window invisible) and sits above it.
        let alpha = window.alphaValue
        if warm {
            panel.setFrame(frame, display: true)
            panel.alphaValue = alpha
        } else {
            // Cold: rise into place from the control's side.
            var from = frame
            from.origin.y += side == .top ? -5 : 5
            panel.alphaValue = 0
            panel.setFrame(from, display: true)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
                panel.animator().alphaValue = alpha
                panel.animator().setFrame(frame, display: true)
            }
        }
        if !panel.isVisible || panel.parent !== window {
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        panel.invalidateShadow()
        installMonitor()
    }

    private func hide(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.current = nil
            self.fadeOut()
        }
        hideWork?.cancel()
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func fadeOut() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.current == nil, let panel = self.panel else { return }
                self.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            }
        })
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The window server shadows the opaque plate and beak, so the label
        // floats at the mock's elevation without a second shape to draw.
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.fullScreenAuxiliary, .transient]
        self.panel = panel
        return panel
    }

    /// Anything that means "gone" rather than "moving on".
    private func installMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            Task { @MainActor in self?.dismiss() }
            return event
        }
    }

    private func watchForClose(_ window: NSWindow) {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }
}

/// The invisible view behind a control that watches the pointer for it. It
/// is a tracking area and nothing else: it never takes a click (`hitTest`
/// returns nil) and never draws.
final class HintAnchorView: NSView {
    var label: String
    var key: String?
    /// The side the control would rather be labelled on. The screen still
    /// overrules it when there is no room there.
    var preferredSide: HintTooltipController.Side

    private var trackingArea: NSTrackingArea?

    init(label: String, key: String?, preferredSide: HintTooltipController.Side) {
        self.label = label
        self.key = key
        self.preferredSide = preferredSide
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Where the control is on screen right now, for placement.
    var screenFrame: NSRect? {
        guard let window else { return nil }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // Always active: the tool bar explains itself whether or not the
        // window is key, the way the system's own help tags do.
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        HintTooltipController.shared.pointerEntered(self)
    }

    override func mouseMoved(with event: NSEvent) {
        HintTooltipController.shared.pointerMoved(self)
    }

    override func mouseExited(with event: NSEvent) {
        HintTooltipController.shared.pointerExited(self)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            HintTooltipController.shared.anchorRemoved(self)
        }
    }
}

private struct HintAnchor: NSViewRepresentable {
    let label: String
    let key: String?
    let side: HintTooltipController.Side

    func makeNSView(context: Context) -> HintAnchorView {
        HintAnchorView(label: label, key: key, preferredSide: side)
    }

    func updateNSView(_ view: HintAnchorView, context: Context) {
        view.label = label
        view.key = key
        view.preferredSide = side
    }
}

/// The label itself: the plate, the text, the quieter key, and the beak.
struct HintTooltipView: View {
    let label: String
    let key: String?
    let side: HintTooltipController.Side
    /// The beak's tip, measured from the tooltip's left edge.
    let beakX: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    /// One dark-slate identity in both themes (the mock's --tip-bg): the
    /// classic inverted tooltip in light, a lifted plate in dark. Never the
    /// brightest thing on a dark screen.
    private var plate: Color {
        colorScheme == .dark
            ? Color(red: 0x2F / 255, green: 0x35 / 255, blue: 0x42 / 255)
            : Color(red: 0x26 / 255, green: 0x2B / 255, blue: 0x35 / 255)
    }

    private var ink: Color {
        colorScheme == .dark
            ? Color(red: 0xEE / 255, green: 0xF0 / 255, blue: 0xF5 / 255)
            : Color(red: 0xF2 / 255, green: 0xF4 / 255, blue: 0xF8 / 255)
    }

    static let beakSize = CGSize(width: 24, height: 9)

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
            if let key {
                Text(key)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(ink)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(plate))
        .overlay(alignment: side == .top ? .bottomLeading : .topLeading) {
            // Hung half a pixel into the plate, so two shapes meant to be one
            // show no hairline between them.
            HintBeak()
                .fill(plate)
                .frame(width: Self.beakSize.width, height: Self.beakSize.height)
                .rotationEffect(side == .top ? .zero : .degrees(180))
                .offset(x: beakX - Self.beakSize.width / 2,
                        y: side == .top ? Self.beakSize.height - 0.5 : -(Self.beakSize.height - 0.5))
        }
        .padding(side == .top ? .bottom : .top, Self.beakSize.height)
        .fixedSize()
    }
}

/// The mock's beak: shoulders that ease off the plate's edge, walls that
/// taper, and a blunted point. Box 24 x 9, tip at (12, 8.6), pointing down.
struct HintBeak: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24, sy = rect.height / 9
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(0, 0))
        path.addCurve(to: p(7, 4.2), control1: p(4.5, 0), control2: p(5.96, 3))
        path.addLine(to: p(9.6, 7.2))
        path.addQuadCurve(to: p(14.4, 7.2), control: p(12, 10))
        path.addLine(to: p(17, 4.2))
        path.addCurve(to: p(24, 0), control1: p(18.04, 3), control2: p(19.5, 0))
        path.closeSubpath()
        return path
    }
}

private struct ToolTipModifier: ViewModifier {
    let label: String
    let key: String?
    let fallback: String?
    let side: HintTooltipController.Side

    func body(content: Content) -> some View {
        if Experiments.shared.toolTipsEnabled {
            content.background { HintAnchor(label: label, key: key, side: side) }
        } else {
            content.help(fallback ?? "\(label)\(key.map { " (\($0))" } ?? "")")
        }
    }
}

extension View {
    /// The design-language tooltip for a control: `label` names it and `key`
    /// is what fires it, printed quieter. `below` asks for the label under the
    /// control rather than over it, for a control whose own picture is the
    /// thing above it. With the Next release's `next-tool-tips` flag off (so
    /// always in Current) this is the system help tag instead, reading
    /// `fallback` when given and "label (key)" otherwise, so Current keeps
    /// exactly the text it had.
    func toolTip(_ label: String, key: String? = nil, fallback: String? = nil,
                 below: Bool = false) -> some View {
        modifier(ToolTipModifier(label: label, key: key, fallback: fallback,
                                 side: below ? .bottom : .top))
    }
}

/// A row of pictures drawn as ONE segmented picker, with a tooltip on each
/// picture instead of one shared by the row.
///
/// A segmented picker takes a single tooltip for the whole control, so a row
/// of five little pictures answered every one of them with the same sentence:
/// resting on the hollow dot read out the SOLID head's description, which is
/// worse than saying nothing. The row itself has no idea which segment the
/// pointer is over.
///
/// The way in is the same invisible tracking view every other tooltip uses,
/// laid over the row once per segment. Segments carrying pictures of one size
/// share the row evenly, which is what an even row of anchors is. The anchors
/// take no clicks (`HintAnchorView.hitTest` returns nil, and the overlay is out
/// of SwiftUI's hit testing too), and an overlay is measured by what it covers,
/// so the row keeps exactly the size and spacing it had.
///
/// With `next-tool-tips` off — so always in Current — this is the row's own
/// system help tag, reading `fallback`, exactly as before.
private struct SegmentToolTips: ViewModifier {
    /// One per segment, in the order the segments are built in.
    let labels: [String]
    /// What the whole row says when the designed tooltip is off.
    let fallback: String
    let side: HintTooltipController.Side

    func body(content: Content) -> some View {
        if Experiments.shared.toolTipsEnabled, labels.count > 1 {
            content.overlay {
                HStack(spacing: 0) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { segment in
                        HintAnchor(label: segment.element, key: nil, side: side)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .allowsHitTesting(false)
            }
        } else {
            content.help(fallback)
        }
    }
}

extension View {
    /// Names each picture in a segmented row of pictures, one tooltip per
    /// segment. `labels` must be in the same order the segments are built in,
    /// which is why every caller builds both from one `allCases`. `fallback`
    /// is the row's system help tag for Current, where the designed tooltip
    /// does not exist.
    func segmentToolTips(_ labels: [String], fallback: String,
                         below: Bool = false) -> some View {
        modifier(SegmentToolTips(labels: labels, fallback: fallback,
                                 side: below ? .bottom : .top))
    }
}
