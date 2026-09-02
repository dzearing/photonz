import AppKit
import PhotonzCore

/// Full-screen "grab a rectangle" mode (⇧⌘4), freeze-frame style: every display
/// is screenshotted FIRST, the frozen images are shown full-screen on
/// shielding-level panels covering everything (nothing underneath stays
/// interactive or can float above the drag box), and the selection is dragged on
/// top of the frozen picture. Releasing crops the region out of the frozen
/// bitmap — atomically WYSIWYG, no re-capture race. Esc cancels.
///
/// With window picking on (`next-window-capture`), the window under the pointer
/// lights up with its app and size, and a click (a press that barely moves)
/// captures exactly that window's bounds from the frozen picture. A drag still
/// selects a region.
@MainActor
final class RectSelectionController {
    private var windows: [SelectionWindow] = []
    private var escMonitors: [Any] = []
    private let windowPicking: Bool
    /// The cropped frozen image is non-nil in screenshot mode; region-recording
    /// ignores it and uses the (screen, rect) to record live.
    private let onComplete: (NSScreen, CGRect, CGImage?) -> Void
    private let onCancel: () -> Void
    private var began = false

    init(windowPicking: Bool = false,
         onComplete: @escaping (NSScreen, CGRect, CGImage?) -> Void,
         onCancel: @escaping () -> Void) {
        self.windowPicking = windowPicking
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    func begin() {
        guard !began else { return }
        began = true
        Task { await freezeAndShow() }
    }

    /// Screenshots every display, then covers each with its frozen image.
    private func freezeAndShow() async {
        var frozen: [(screen: NSScreen, image: CGImage?)] = []
        for screen in NSScreen.screens {
            // A failed freeze (rare) degrades to the old dim-the-live-screen look
            // for that display; selection still works via the live-capture path.
            frozen.append((screen, try? await ScreenCapturer.capture(screen: screen)))
        }
        // The window list is taken with the freeze, so what lights up is what
        // the frozen picture shows.
        let onScreen = windowPicking ? WindowLister.onScreenWindows() : []
        guard windows.isEmpty else { return }
        for (screen, image) in frozen {
            let window = SelectionWindow(screen: screen, frozenImage: image)
            window.selectionView.windowPicking = windowPicking
            window.selectionView.candidates = WindowLister.windows(onScreen, localTo: screen)
            window.selectionView.onSelect = { [weak self] rect in
                self?.finish(screen: screen, rect: rect, frozen: image)
            }
            window.selectionView.onCancel = { [weak self] in self?.cancel() }
            // Order front WITHOUT activating: the windows are non-activating
            // panels so they take mouse/keys without pulling the app (and any
            // open editor window) to the foreground.
            window.orderFrontRegardless()
            windows.append(window)
        }
        // The shield panels themselves are the frontmost windows on every
        // display; they must never be what a click captures.
        let shields = Set(windows.map(\.windowNumber))
        for window in windows {
            window.selectionView.excludedWindowIDs = shields
        }
        // Key the panel under the mouse: a non-activating panel can be key
        // without activating the app, and being key is what lets it own the
        // cursor (crosshair) and receive Esc directly.
        let mouse = NSEvent.mouseLocation
        let keyWindow = windows.first { $0.screen?.frame.contains(mouse) == true } ?? windows.first
        keyWindow?.makeKey()
        NSCursor.crosshair.set()
        // The window under the pointer lights up the moment the overlay is
        // there, not after the first move.
        for window in windows { window.selectionView.refreshHover() }
        // Belt and braces for Esc: local (we're key) plus global (if focus moves).
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            if e.keyCode == 53 { self?.cancel(); return nil }
            return e
        }) { escMonitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            if e.keyCode == 53 { self?.cancel() }
        }) { escMonitors.append(global) }
    }

    /// Tears down the overlay windows.
    func dismiss() {
        escMonitors.forEach { NSEvent.removeMonitor($0) }
        escMonitors = []
        windows.forEach { $0.orderOut(nil) }
        windows = []
        NSCursor.arrow.set()
    }

    private func finish(screen: NSScreen, rect: CGRect, frozen: CGImage?) {
        dismiss()
        onComplete(screen, rect, frozen.flatMap { Self.crop($0, to: rect, scale: screen.backingScaleFactor) })
    }

    private func cancel() {
        dismiss()
        onCancel()
    }

    /// Crops a screen-local, top-left-origin points rect out of the frozen
    /// bitmap (which is at the screen's backing scale).
    private static func crop(_ image: CGImage, to rect: CGRect, scale: CGFloat) -> CGImage? {
        let pixelRect = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                               width: rect.width * scale, height: rect.height * scale).integral
        return image.cropping(to: pixelRect)
    }
}

private final class SelectionWindow: NSPanel {
    let selectionView = SelectionView()

    init(screen: NSScreen, frozenImage: CGImage?) {
        // A non-activating panel takes mouse/keys without making Photonz the
        // active app — so starting a capture never raises an open editor window.
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Shielding level: above every app window, panel, and MODAL alert —
        // nothing can float over the frozen picture or the drag box. Assigned
        // LAST: NSPanel property setters can silently rewrite `level`
        // (`isFloatingPanel = true` reset it to .floating(3), which lost to
        // modal dialogs at level 8 — the "selection behind the modal" bug).
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        // The freeze must be imperceptible: macOS animates panels in by default
        // (fade/pop), which reads as a visible "flash" to the screenshot.
        animationBehavior = .none

        // The frozen screenshot sits beneath the selection chrome, so the world
        // appears unchanged but is actually a still image we own.
        let container = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        container.wantsLayer = true
        if let frozenImage, let layer = container.layer {
            // No implicit CALayer transitions either — contents appear in the
            // same frame the window does.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contents = frozenImage
            layer.contentsGravity = .resize
            CATransaction.commit()
        }
        selectionView.frame = container.bounds
        selectionView.autoresizingMask = [.width, .height]
        container.addSubview(selectionView)
        contentView = container
    }

    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    /// Selected rect in this screen's local, top-left-origin points.
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    /// Window picking (`next-window-capture`): highlight the window under the
    /// pointer and capture it on a click. Off keeps the overlay drag only.
    var windowPicking = false
    /// On-screen windows front to back, frames in this view's coordinates.
    var candidates: [ScreenWindow] = []
    /// The overlay's own shield panels, never pickable.
    var excludedWindowIDs: Set<Int> = []

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    /// True once a press has travelled far enough to be a region drag rather
    /// than a click on the hovered window.
    private var isDragging = false
    private var hovered: ScreenWindow? {
        didSet {
            guard hovered != oldValue else { return }
            invalidate(chrome(for: oldValue).union(chrome(for: hovered)))
        }
    }

    // Flipped so view coords are exactly screen-local top-left coords —
    // the same space ScreenCapturer.capture(sourceRect:) expects.
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    // The app isn't active during capture, so the first click must register as a
    // drag (not just an activation) for drag-to-select to work.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Cursor rects are unreliable on borderless overlay windows (the crosshair
    // often never replaces the arrow). A tracking area that delivers
    // `.cursorUpdate` — plus pushing the cursor on enter/move — is the
    // dependable way to force the crosshair across the whole overlay.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate],
            owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
        updateHover(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseExited(with event: NSEvent) {
        // The pointer crossed onto another display: that display's overlay
        // picks up the highlight, this one lets go.
        updateHover(at: nil)
    }
    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    /// Highlights the window under the pointer right now, without waiting for
    /// a mouse event: called when the overlay first appears.
    func refreshHover() {
        guard let window, windowPicking else { return }
        let inWindow = window.mouseLocationOutsideOfEventStream
        let point = convert(inWindow, from: nil)
        updateHover(at: bounds.contains(point) ? point : nil)
    }

    private func updateHover(at point: CGPoint?) {
        guard windowPicking, !isDragging else { return }
        guard let point else { hovered = nil; return }
        hovered = WindowPick.frontmost(at: point, in: candidates, excluding: excludedWindowIDs)
    }

    override func mouseDown(with event: NSEvent) {
        // Re-assert on press: the app is inactive (non-activating overlay), so
        // AppKit's cursor management is unreliable and the one-shot crosshair may
        // have been clobbered back to the arrow before the first move.
        NSCursor.crosshair.set()
        let point = convert(event.locationInWindow, from: nil)
        // The press may land before any move was delivered; make sure the
        // highlight is the window under the press.
        updateHover(at: point)
        dragStart = point
        dragCurrent = point
        isDragging = !windowPicking
        if isDragging { needsDisplay = true }
    }

    override func mouseDragged(with event: NSEvent) {
        // A drag delivers only `mouseDragged` (never `mouseMoved`/`cursorUpdate`),
        // so this is the ONLY place the cursor can be kept as the crosshair while
        // dragging out the region — without it the pointer reverts to the arrow.
        NSCursor.crosshair.set()
        let previous = selectionRect
        dragCurrent = convert(event.locationInWindow, from: nil)
        if !isDragging, let start = dragStart, let current = dragCurrent,
           !WindowPick.isClick(from: start, to: current) {
            // Past the click threshold: the press became a region drag and the
            // window highlight steps aside.
            isDragging = true
            hovered = nil
            invalidate(dragChrome(for: selectionRect))
            return
        }
        guard isDragging else { return }
        invalidate(dragChrome(for: previous).union(dragChrome(for: selectionRect)))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragCurrent = nil
            isDragging = false
        }
        if windowPicking, !isDragging {
            // A click: capture the highlighted window, or, over nothing
            // pickable, treat it as today's bare click and let the capture go.
            if let hovered, let rect = WindowPick.captureRect(for: hovered, within: bounds) {
                onSelect?(rect)
            } else {
                onCancel?()
            }
            return
        }
        guard let rect = selectionRect, rect.width >= 2, rect.height >= 2 else {
            onCancel?()
            return
        }
        onSelect?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectionRect: CGRect? {
        guard isDragging, let a = dragStart, let b = dragCurrent else { return nil }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: abs(a.x - b.x), height: abs(a.y - b.y)).standardized
    }

    // MARK: - Drawing

    private static let labelInset: CGFloat = 8
    private static let labelPadding = CGSize(width: 8, height: 4)
    private static let labelFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    /// Redraws only what changed: the old and new highlight (outline and label
    /// included), not the whole display, so tracking the pointer stays cheap
    /// on a 5K screen.
    private func invalidate(_ dirty: CGRect) {
        guard !dirty.isNull, !dirty.isEmpty else { return }
        setNeedsDisplay(dirty.intersection(bounds))
    }

    /// Everything the hover highlight for `window` paints: outline plus label.
    private func chrome(for window: ScreenWindow?) -> CGRect {
        guard let window, let rect = WindowPick.captureRect(for: window, within: bounds) else { return .null }
        return chrome(for: rect, text: WindowPick.label(for: window))
    }

    /// Everything the drag box for `rect` paints: outline plus size label.
    private func dragChrome(for rect: CGRect?) -> CGRect {
        guard let rect else { return .null }
        return chrome(for: rect, text: WindowPick.sizeLabel(for: rect.size))
    }

    private func chrome(for rect: CGRect, text: String) -> CGRect {
        rect.insetBy(dx: -2, dy: -2).union(labelFrame(for: rect, text: text))
    }

    private func attributedLabel(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: Self.labelFont,
            .foregroundColor: NSColor.white,
        ])
    }

    private func labelFrame(for rect: CGRect, text: String) -> CGRect {
        let textSize = attributedLabel(text).size()
        let size = CGSize(width: ceil(textSize.width) + Self.labelPadding.width * 2,
                          height: ceil(textSize.height) + Self.labelPadding.height * 2)
        let origin = WindowPick.labelOrigin(for: rect, labelSize: size, inset: Self.labelInset,
                                            within: bounds)
        return CGRect(origin: origin, size: size)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim everything…
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        if let rect = selectionRect {
            // …except the selection, which shows the frozen picture through a
            // crisp outline.
            cutOut(rect, lineWidth: 1)
            if windowPicking { drawLabel(WindowPick.sizeLabel(for: rect.size), for: rect) }
        } else if let hovered, let rect = WindowPick.captureRect(for: hovered, within: bounds) {
            // …or the window under the pointer, which is what a click captures.
            cutOut(rect, lineWidth: 2)
            drawLabel(WindowPick.label(for: hovered), for: rect)
        }
    }

    private func cutOut(_ rect: CGRect, lineWidth: CGFloat) {
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: rect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2))
        outline.lineWidth = lineWidth
        outline.stroke()
    }

    /// The readout pill: what a click (or the drag) would capture, in points.
    private func drawLabel(_ text: String, for rect: CGRect) {
        let frame = labelFrame(for: rect, text: text)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).fill()
        attributedLabel(text).draw(at: CGPoint(x: frame.minX + Self.labelPadding.width,
                                               y: frame.minY + Self.labelPadding.height))
    }
}

