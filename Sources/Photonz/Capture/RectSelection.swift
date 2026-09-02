import AppKit
import PhotonzCore

/// Full-screen "grab a rectangle" mode (⇧⌘4), freeze-frame style: every display
/// is covered by a shielding-level panel (nothing underneath stays interactive
/// or can float above the drag box) and the selection is dragged on top.
///
/// The panels go up FIRST, in the same turn of the run loop as the shortcut, so
/// the screen dims the instant the capture starts. The freeze follows a frame
/// or two later: each display is screenshotted and its picture slides in under
/// the dim, and because the panels are marked `sharingType = .none` they are
/// invisible to that screenshot, so the frozen picture is the true screen and
/// not a picture of our own dim. Releasing crops the region out of the frozen
/// bitmap — atomically WYSIWYG, no re-capture race. A release that somehow beats
/// the freeze falls back to a live capture of the same rect. Esc cancels.
///
/// With window picking on (`next-window-capture`), the window under the pointer
/// lights up with its app and size, and a click (a press that barely moves)
/// captures exactly that window: on its own, with its shadow and see-through
/// rounded corners like the built-in window capture (Option while clicking for
/// the bare bounds, or the other way round when the flag's shadow choice is
/// off). That shot is taken live at the click; if it cannot be, the window's
/// bounds are cropped from the frozen picture instead. A drag still selects a
/// region.
@MainActor
final class RectSelectionController {
    private var windows: [SelectionWindow] = []
    private var escMonitors: [Any] = []
    private let windowPicking: Bool
    /// Whether a clicked window is shot with its shadow (Option flips it).
    private let windowShadow: Bool
    /// Whether the caller wants pixels at all. Region recording only wants
    /// the rect, so it skips the crop and the per-window shot.
    private let producesImage: Bool
    /// The cropped frozen image is non-nil in screenshot mode; region-recording
    /// ignores it and uses the (screen, rect) to record live.
    private let onComplete: (NSScreen, CGRect, CGImage?) -> Void
    private let onCancel: () -> Void
    private var began = false

    init(windowPicking: Bool = false,
         windowShadow: Bool = true,
         producesImage: Bool = true,
         onComplete: @escaping (NSScreen, CGRect, CGImage?) -> Void,
         onCancel: @escaping () -> Void) {
        self.windowPicking = windowPicking
        self.windowShadow = windowShadow
        self.producesImage = producesImage
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    func begin() {
        guard !began else { return }
        began = true
        // Dim now, synchronously: no await stands between the shortcut and the
        // screen going dark.
        show()
        // The picture catches up.
        Task { await freeze() }
    }

    /// Covers every display with its overlay, dimming the live screen. Runs to
    /// completion in one turn of the run loop, before any screenshot exists.
    private func show() {
        // Taken before the shields are up, so the list is windows a person can
        // actually pick and never our own panels.
        let onScreen = windowPicking ? WindowLister.onScreenWindows() : []
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen)
            window.selectionView.windowPicking = windowPicking
            window.selectionView.candidates = WindowLister.windows(onScreen, localTo: screen)
            window.selectionView.onSelect = { [weak self, weak window] rect, picked, optionHeld in
                self?.finish(screen: screen, rect: rect, frozen: window?.frozenImage,
                             picked: picked, optionHeld: optionHeld)
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

    /// Screenshots each display and slides its picture in under the dim. The
    /// overlay is already on screen and excluded from the shot, so what comes
    /// back is the world as it was, not the world plus our dim. A display whose
    /// freeze fails (rare) keeps the dim over the live screen and still selects,
    /// via the live-capture path.
    private func freeze() async {
        for window in windows {
            let image = try? await ScreenCapturer.capture(screen: window.targetScreen)
            // Esc, or a finished selection, while the shot was in flight.
            guard windows.contains(where: { $0 === window }) else { return }
            guard let image else { continue }
            window.showFrozen(image)
        }
        // Every shot is in, so the overlay has nothing left to hide from and
        // goes back to being an ordinary window: a screen recording running
        // beside us, or a person shooting Photonz with another tool, sees the
        // dim and the box the way they see everything else.
        for window in windows { window.sharingType = .readOnly }
    }

    /// Tears down the overlay windows.
    func dismiss() {
        escMonitors.forEach { NSEvent.removeMonitor($0) }
        escMonitors = []
        windows.forEach { $0.orderOut(nil) }
        windows = []
        NSCursor.arrow.set()
    }

    /// `picked` is the window a click landed on (nil for a drag); `optionHeld`
    /// whether Option was down at the release.
    private func finish(screen: NSScreen, rect: CGRect, frozen: CGImage?,
                        picked: ScreenWindow? = nil, optionHeld: Bool = false) {
        dismiss()
        guard producesImage else {
            onComplete(screen, rect, nil)
            return
        }
        let scale = screen.backingScaleFactor
        let cropped = { frozen.flatMap { Self.crop($0, to: rect, scale: scale) } }
        guard let picked else {
            onComplete(screen, rect, cropped())
            return
        }
        // A clicked window: shot on its own by the window server, live, in
        // the look the click asked for. A shadowed shot that comes back no
        // bigger than the window had the shadow squeezed inside it, so try
        // the bare bounds; a failed or unfaithful bare shot leaves the frozen
        // crop, exactly what a click captured before.
        let style = WindowShot.style(includeShadow: windowShadow, optionHeld: optionHeld)
        Task {
            let image = await Self.windowShot(of: picked, style: style, scale: scale)
            onComplete(screen, rect, image ?? cropped())
        }
    }

    private static func windowShot(of window: ScreenWindow, style: WindowShot.Style,
                                   scale: CGFloat) async -> CGImage? {
        let styles: [WindowShot.Style] = style == .withShadow ? [.withShadow, .bareBounds] : [.bareBounds]
        for candidate in styles {
            guard let image = try? await ScreenCapturer.captureWindow(
                id: window.id, includeShadow: candidate == .withShadow) else { continue }
            let size = CGSize(width: image.width, height: image.height)
            if WindowShot.isFaithful(pixelSize: size, windowSize: window.frame.size, scale: scale,
                                     style: candidate) {
                return image
            }
            NSLog("Window shot (\(candidate)) came back \(image.width)x\(image.height) for a "
                  + "\(window.frame.size) pt window at \(scale)x; trying the next fallback")
        }
        return nil
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

    #if PHOTONZ_PLAYTEST
    /// Probe only: drags a box on the first display's overlay without a mouse,
    /// so an unmanned run can photograph what a drag looks like. The overlay
    /// covers the screen and owns the pointer, which is why a walk cannot get
    /// at it any other way.
    func simulateDrag(from start: CGPoint, to end: CGPoint) {
        guard let window = windows.first else { return }
        let view = window.selectionView
        func send(_ type: NSEvent.EventType, _ point: CGPoint) {
            guard let event = NSEvent.mouseEvent(
                with: type, location: view.convert(point, to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1) else { return }
            switch type {
            case .leftMouseDown: view.mouseDown(with: event)
            case .leftMouseDragged: view.mouseDragged(with: event)
            default: view.mouseUp(with: event)
            }
        }
        send(.leftMouseDown, start)
        for step in 1...8 {
            let t = CGFloat(step) / 8
            send(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t,
                                            y: start.y + (end.y - start.y) * t))
        }
    }

    #endif
}

private final class SelectionWindow: NSPanel {
    let selectionView = SelectionView()
    /// Holds the frozen picture, and nothing else, under the selection chrome.
    private let frozenView = NSView()
    /// The dim over the picture, with a hole where the selection is. Its own
    /// view rather than a fill in `SelectionView.draw`: a view only repaints
    /// the rectangles it is told are dirty, so a full-screen fill there covered
    /// whatever had recently been redrawn and left the rest of the display at
    /// full brightness. The compositor keeps this right for free.
    private let dimView = DimView()
    /// The display this panel covers. Held rather than read back from
    /// `NSWindow.screen`, which reports where the window happens to be.
    let targetScreen: NSScreen
    /// This display's frozen picture, once the freeze lands. Nil until then,
    /// and nil for good if that display's shot failed.
    private(set) var frozenImage: CGImage?

    init(screen: NSScreen) {
        targetScreen = screen
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
        // Invisible to any screen capture, including the one this overlay is
        // about to take of the screen it is covering. Without this the freeze
        // would photograph our own dim and the picture would slide in darker
        // than the world it replaces.
        sharingType = .none

        // The frozen screenshot sits beneath the selection chrome, so the world
        // appears unchanged but is actually a still image we own. It arrives a
        // frame or two after the panel: until then this view is empty and the
        // dim falls on the live screen.
        //
        // It gets a view (and so a layer) of its OWN, under a layer-backed
        // selection view. Handing the picture to the layer the chrome draws
        // into replaces whatever the chrome had drawn there, which is how the
        // dim quietly disappeared the moment the freeze landed.
        let container = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        container.wantsLayer = true
        frozenView.frame = container.bounds
        frozenView.autoresizingMask = [.width, .height]
        frozenView.wantsLayer = true
        container.addSubview(frozenView)
        dimView.frame = container.bounds
        dimView.autoresizingMask = [.width, .height]
        dimView.wantsLayer = true
        container.addSubview(dimView)
        // Dim from the very first frame, before the pointer has moved and
        // before anything has been drawn.
        dimView.open(on: nil)
        selectionView.frame = container.bounds
        selectionView.autoresizingMask = [.width, .height]
        selectionView.wantsLayer = true
        selectionView.dim = dimView
        container.addSubview(selectionView)
        contentView = container
    }

    /// Puts this display's frozen picture under the selection chrome. Nothing
    /// else on screen moves, so with no implicit animation anywhere the swap
    /// from the live screen to its own photograph is invisible.
    func showFrozen(_ image: CGImage) {
        frozenImage = image
        guard let layer = frozenView.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = image
        layer.contentsGravity = .resize
        CATransaction.commit()
    }

    override var canBecomeKey: Bool { true }
}

/// The dim, as one shape the compositor owns: the whole display with a hole
/// where the selection is. Backed by a shape layer through `makeBackingLayer`,
/// the one way to hand AppKit a layer it will keep — a sublayer added by hand
/// is thrown away when the view joins a layer-backed window.
private final class DimView: NSView {
    override func makeBackingLayer() -> CALayer {
        let shape = CAShapeLayer()
        shape.fillRule = .evenOdd
        shape.fillColor = NSColor.black.withAlphaComponent(0.25).cgColor
        // Never animate: the hole belongs where the pointer is, this frame.
        shape.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull()]
        return shape
    }

    /// The whole display, minus `hole`. Nil dims everything, which is what a
    /// capture looks like before the first drag.
    func open(on hole: CGRect?) {
        guard let shape = layer as? CAShapeLayer else { return }
        let path = CGMutablePath()
        path.addRect(bounds)
        if let hole {
            // This view is not flipped; the selection is in top-left points.
            path.addRect(CGRect(x: hole.minX, y: bounds.height - hole.maxY,
                                width: hole.width, height: hole.height))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.path = path
        CATransaction.commit()
    }
}

private final class SelectionView: NSView {
    /// Selected rect in this screen's local, top-left-origin points, the
    /// window it is (for a click on one; nil for a drag), and whether Option
    /// was held at the release.
    var onSelect: ((CGRect, ScreenWindow?, Bool) -> Void)?
    var onCancel: (() -> Void)?

    /// Window picking (`next-window-capture`): highlight the window under the
    /// pointer and capture it on a click. Off keeps the overlay drag only.
    var windowPicking = false
    /// On-screen windows front to back, frames in this view's coordinates.
    var candidates: [ScreenWindow] = []
    /// The overlay's own shield panels, never pickable.
    var excludedWindowIDs: Set<Int> = []

    /// The dim this view punches its hole in. It lives under this view, in its
    /// own layer, so it covers the whole display from the first frame whether
    /// or not anything has asked this view to redraw.
    weak var dim: DimView?

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
        // picks up the highlight, this one lets go of it.
        updateHover(at: nil)
    }
    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    /// Highlights the window under the pointer right now, without waiting for
    /// a mouse event: called when the overlay first appears.
    func refreshHover() {
        guard let window else { return }
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
                onSelect?(rect, hovered, event.modifierFlags.contains(.option))
            } else {
                onCancel?()
            }
            return
        }
        guard let rect = selectionRect, rect.width >= 2, rect.height >= 2 else {
            onCancel?()
            return
        }
        onSelect?(rect, nil, false)
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
    /// The window title sits between the app and the size in a lighter voice,
    /// so a long title reads as detail rather than shouting over the outline.
    private static let titleFont = NSFont.systemFont(ofSize: 12, weight: .regular)

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
        return chrome(for: rect, label: highlightLabel(for: window, in: rect))
    }

    /// Everything the drag box for `rect` paints: outline plus size label.
    private func dragChrome(for rect: CGRect?) -> CGRect {
        guard let rect else { return .null }
        return chrome(for: rect, label: sizeOnlyLabel(for: rect))
    }

    private func chrome(for rect: CGRect, label: WindowLabel) -> CGRect {
        rect.insetBy(dx: -2, dy: -2).union(labelFrame(for: rect, label: label))
    }

    private func sizeOnlyLabel(for rect: CGRect) -> WindowLabel {
        WindowLabel(app: "", size: WindowPick.sizeLabel(for: rect.size))
    }

    /// The window's app, title and size, the title cut to keep the pill
    /// inside the window (or the display, when it hangs below a small one).
    private func highlightLabel(for window: ScreenWindow, in rect: CGRect) -> WindowLabel {
        WindowPick.fittedLabel(for: window, in: rect, within: bounds, inset: Self.labelInset) {
            pillSize(for: $0)
        }
    }

    /// The label's text with the app and size in bold and the title lighter,
    /// spelled out part by part so it always matches `WindowLabel.text`.
    private func attributedLabel(_ label: WindowLabel) -> NSAttributedString {
        let strong: [NSAttributedString.Key: Any] = [
            .font: Self.labelFont, .foregroundColor: NSColor.white,
        ]
        let soft: [NSAttributedString.Key: Any] = [
            .font: Self.titleFont, .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        let out = NSMutableAttributedString()
        func append(_ text: String, _ attributes: [NSAttributedString.Key: Any]) {
            out.append(NSAttributedString(string: text, attributes: attributes))
        }
        if !label.app.isEmpty { append(label.app, strong) }
        if let title = label.title, !title.isEmpty {
            if out.length > 0 { append(" · ", soft) }
            append(title, soft)
        }
        if out.length > 0 { append("  ", strong) }
        append(label.size, strong)
        return out
    }

    /// The pill's full size for `label`, padding included.
    private func pillSize(for label: WindowLabel) -> CGSize {
        let textSize = attributedLabel(label).size()
        return CGSize(width: ceil(textSize.width) + Self.labelPadding.width * 2,
                      height: ceil(textSize.height) + Self.labelPadding.height * 2)
    }

    private func labelFrame(for rect: CGRect, label: WindowLabel) -> CGRect {
        let size = pillSize(for: label)
        let origin = WindowPick.labelOrigin(for: rect, labelSize: size, inset: Self.labelInset,
                                            within: bounds)
        return CGRect(origin: origin, size: size)
    }

    override func draw(_ dirtyRect: NSRect) {
        // The dim belongs to the layer underneath; this view carries the chrome
        // alone, so a repaint starts by clearing what it is replacing rather
        // than painting over it.
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        if let rect = selectionRect {
            // The dim opens on the selection, which shows the frozen picture
            // through a crisp outline.
            dim?.open(on: rect)
            outline(rect, lineWidth: 1)
            // The size of the box being dragged, the one readout a drag gets.
            if windowPicking { drawLabel(sizeOnlyLabel(for: rect), for: rect) }
        } else if let hovered, let rect = WindowPick.captureRect(for: hovered, within: bounds) {
            // …or on the window under the pointer, which is what a click captures.
            dim?.open(on: rect)
            outline(rect, lineWidth: 2)
            drawLabel(highlightLabel(for: hovered, in: rect), for: rect)
        } else {
            dim?.open(on: nil)
        }
    }

    private func outline(_ rect: CGRect, lineWidth: CGFloat) {
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: rect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2))
        outline.lineWidth = lineWidth
        outline.stroke()
    }

    /// The readout pill: what a click (or the drag) would capture, in points.
    private func drawLabel(_ label: WindowLabel, for rect: CGRect) {
        let frame = labelFrame(for: rect, label: label)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).fill()
        attributedLabel(label).draw(at: CGPoint(x: frame.minX + Self.labelPadding.width,
                                                y: frame.minY + Self.labelPadding.height))
    }
}
