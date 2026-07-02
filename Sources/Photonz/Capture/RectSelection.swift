import AppKit

/// Full-screen "grab a rectangle" mode (⌘⇧4), freeze-frame style: every display
/// is screenshotted FIRST, the frozen images are shown full-screen on
/// shielding-level panels covering everything (nothing underneath stays
/// interactive or can float above the drag box), and the selection is dragged on
/// top of the frozen picture. Releasing crops the region out of the frozen
/// bitmap — atomically WYSIWYG, no re-capture race. Esc cancels.
@MainActor
final class RectSelectionController {
    private var windows: [SelectionWindow] = []
    private var escMonitors: [Any] = []
    /// The cropped frozen image is non-nil in screenshot mode; region-recording
    /// ignores it and uses the (screen, rect) to record live.
    private let onComplete: (NSScreen, CGRect, CGImage?) -> Void
    private let onCancel: () -> Void
    private var began = false

    init(onComplete: @escaping (NSScreen, CGRect, CGImage?) -> Void,
         onCancel: @escaping () -> Void) {
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
        guard windows.isEmpty else { return }
        for (screen, image) in frozen {
            let window = SelectionWindow(screen: screen, frozenImage: image)
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
        // Key the panel under the mouse: a non-activating panel can be key
        // without activating the app, and being key is what lets it own the
        // cursor (crosshair) and receive Esc directly.
        let mouse = NSEvent.mouseLocation
        let keyWindow = windows.first { $0.screen?.frame.contains(mouse) == true } ?? windows.first
        keyWindow?.makeKey()
        NSCursor.crosshair.set()
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
        // Shielding level: above every app window, panel, and system alert —
        // nothing can float over the frozen picture or the drag box.
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

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
    override func mouseEntered(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; dragCurrent = nil }
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
        guard let a = dragStart, let b = dragCurrent else { return nil }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: abs(a.x - b.x), height: abs(a.y - b.y)).standardized
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim everything…
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        guard let rect = selectionRect else { return }
        // …except the selection, which shows the frozen picture through a crisp
        // outline.
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        outline.lineWidth = 1
        outline.stroke()
    }
}
