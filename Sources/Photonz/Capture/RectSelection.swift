import AppKit

/// Full-screen "grab a rectangle" mode (⌘⇧4): dims every screen behind a
/// crosshair; drag selects, releasing captures, Esc cancels.
@MainActor
final class RectSelectionController {
    private var windows: [SelectionWindow] = []
    private let onComplete: (NSScreen, CGRect) -> Void
    private let onCancel: () -> Void

    init(onComplete: @escaping (NSScreen, CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    func begin() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen)
            window.selectionView.onSelect = { [weak self] rect in self?.finish(screen: screen, rect: rect) }
            window.selectionView.onCancel = { [weak self] in self?.cancel() }
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.set()
    }

    /// Tears down the overlay windows so they don't appear in the capture.
    func dismiss() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        NSCursor.arrow.set()
    }

    private func finish(screen: NSScreen, rect: CGRect) {
        dismiss()
        onComplete(screen, rect)
    }

    private func cancel() {
        dismiss()
        onCancel()
    }
}

private final class SelectionWindow: NSWindow {
    let selectionView = SelectionView()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = selectionView
    }

    // Borderless windows refuse key status by default; we need Esc.
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

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

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
        // …except the selection, which shows through with a crisp outline.
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        outline.lineWidth = 1
        outline.stroke()
    }
}
