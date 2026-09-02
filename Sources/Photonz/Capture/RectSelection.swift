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
/// captures exactly that window: on its own, with its shadow and see-through
/// rounded corners like the built-in window capture (Option while clicking for
/// the bare bounds, or the other way round when the flag's shadow choice is
/// off). That shot is taken live at the click; if it cannot be, the window's
/// bounds are cropped from the frozen picture instead. A drag still selects a
/// region.
///
/// With the loupe on (`next-capture-loupe`), a magnified patch of the frozen
/// picture rides beside the pointer with the pointer's coordinates and, while
/// dragging, the selection's size, so a crop starts and stops on the pixel you
/// mean. It is cut from the bitmap the overlay already holds: no extra capture.
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
    /// Pixels the loupe shows across, or nil for no loupe.
    private let loupePixels: Int?
    /// The cropped frozen image is non-nil in screenshot mode; region-recording
    /// ignores it and uses the (screen, rect) to record live.
    private let onComplete: (NSScreen, CGRect, CGImage?) -> Void
    private let onCancel: () -> Void
    private var began = false

    init(windowPicking: Bool = false,
         windowShadow: Bool = true,
         producesImage: Bool = true,
         loupe: Int? = nil,
         onComplete: @escaping (NSScreen, CGRect, CGImage?) -> Void,
         onCancel: @escaping () -> Void) {
        self.windowPicking = windowPicking
        self.windowShadow = windowShadow
        self.producesImage = producesImage
        self.loupePixels = loupe
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
            window.selectionView.loupePixels = loupePixels
            window.selectionView.frozenImage = image
            window.selectionView.candidates = WindowLister.windows(onScreen, localTo: screen)
            window.selectionView.onSelect = { [weak self] rect, picked, optionHeld in
                self?.finish(screen: screen, rect: rect, frozen: image, picked: picked, optionHeld: optionHeld)
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
        // The window under the pointer lights up, and the loupe appears, the
        // moment the overlay is there, not after the first move.
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

    /// The loupe (`next-capture-loupe`): how many device pixels it shows
    /// across, or nil for no loupe.
    var loupePixels: Int?
    /// The frozen picture this display shows, at its backing scale. The loupe
    /// magnifies a patch of it.
    var frozenImage: CGImage?

    /// Where the pointer is, in this view's coordinates, while it is over this
    /// display. Drives the loupe.
    private var pointer: CGPoint?
    /// The loupe as last laid out, so a move can invalidate exactly what it
    /// covered and what it will cover next.
    private var shownLoupe: CGRect = .null

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
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
        updatePointer(point)
    }
    override func mouseExited(with event: NSEvent) {
        // The pointer crossed onto another display: that display's overlay
        // picks up the highlight and the loupe, this one lets go of both.
        updateHover(at: nil)
        updatePointer(nil)
    }
    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
        updatePointer(point)
    }

    /// Highlights the window under the pointer right now, without waiting for
    /// a mouse event: called when the overlay first appears.
    func refreshHover() {
        guard let window else { return }
        let inWindow = window.mouseLocationOutsideOfEventStream
        let point = convert(inWindow, from: nil)
        let inside = bounds.contains(point) ? point : nil
        updateHover(at: inside)
        updatePointer(inside)
    }

    /// Moves the loupe with the pointer: whatever it covered before and
    /// wherever it lands now are the only pixels redrawn.
    private func updatePointer(_ point: CGPoint?) {
        pointer = point
        relayoutLoupe()
    }

    private func relayoutLoupe() {
        let next = loupeLayout?.dirty ?? .null
        guard next != shownLoupe else { return }
        invalidate(shownLoupe.union(next))
        shownLoupe = next
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
        updatePointer(point)
    }

    override func mouseDragged(with event: NSEvent) {
        // A drag delivers only `mouseDragged` (never `mouseMoved`/`cursorUpdate`),
        // so this is the ONLY place the cursor can be kept as the crosshair while
        // dragging out the region — without it the pointer reverts to the arrow.
        NSCursor.crosshair.set()
        let previous = selectionRect
        dragCurrent = convert(event.locationInWindow, from: nil)
        defer { updatePointer(dragCurrent) }
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
        // Dim everything…
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        if let rect = selectionRect {
            // …except the selection, which shows the frozen picture through a
            // crisp outline.
            cutOut(rect, lineWidth: 1)
            // The size pill steps aside while the loupe carries the size, so a
            // drag has one readout, at the corner being placed.
            if windowPicking, loupeLayout == nil { drawLabel(sizeOnlyLabel(for: rect), for: rect) }
        } else if let hovered, let rect = WindowPick.captureRect(for: hovered, within: bounds) {
            // …or the window under the pointer, which is what a click captures.
            cutOut(rect, lineWidth: 2)
            drawLabel(highlightLabel(for: hovered, in: rect), for: rect)
        }
        if let layout = loupeLayout, layout.dirty.intersects(dirtyRect), let frozenImage {
            drawLoupe(layout, from: frozenImage)
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
    private func drawLabel(_ label: WindowLabel, for rect: CGRect) {
        let frame = labelFrame(for: rect, label: label)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).fill()
        attributedLabel(label).draw(at: CGPoint(x: frame.minX + Self.labelPadding.width,
                                                y: frame.minY + Self.labelPadding.height))
    }

    // MARK: - Loupe

    private static let loupePadding: CGFloat = 4
    private static let loupeReadoutSpacing: CGFloat = 5
    private static let loupeLineHeight: CGFloat = 15
    private static let loupeShadowReach: CGFloat = 14
    private static let loupeFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    /// One frame's worth of loupe: where the panel and its picture sit, what
    /// the readout says, and the pointer it was laid out for.
    private struct LoupeLayout {
        var frame: CGRect
        var square: CGRect
        var lines: [String]
        var pointer: CGPoint
        var pixels: Int
        var scale: CGFloat
        /// The panel plus its shadow: everything a move has to repaint.
        var dirty: CGRect { frame.insetBy(dx: -SelectionView.loupeShadowReach, dy: -SelectionView.loupeShadowReach) }
    }

    /// The frozen picture's pixels per point on this display.
    private var frozenScale: CGFloat {
        guard let frozenImage, bounds.width > 0 else { return 1 }
        return CGFloat(frozenImage.width) / bounds.width
    }

    private var loupeLayout: LoupeLayout? {
        guard let pixels = loupePixels, let pointer, frozenImage != nil else { return nil }
        let square = CGFloat(pixels) * CaptureLoupe.pointsPerPixel
        let lines = CaptureLoupe.readout(pointer: pointer, scale: frozenScale, selection: selectionRect?.size)
        let size = CGSize(width: square + Self.loupePadding * 2,
                          height: Self.loupePadding + square + Self.loupeReadoutSpacing
                              + CGFloat(lines.count) * Self.loupeLineHeight + Self.loupePadding)
        var origin = CaptureLoupe.origin(pointer: pointer, anchor: isDragging ? dragStart : nil,
                                         size: size, gap: CaptureLoupe.gap, within: bounds)
        // Whole points, so every magnified pixel lands on a crisp boundary.
        origin = CGPoint(x: floor(origin.x), y: floor(origin.y))
        let frame = CGRect(origin: origin, size: size)
        let squareRect = CGRect(x: frame.minX + Self.loupePadding, y: frame.minY + Self.loupePadding,
                                width: square, height: square)
        return LoupeLayout(frame: frame, square: squareRect, lines: lines, pointer: pointer,
                           pixels: pixels, scale: frozenScale)
    }

    private func drawLoupe(_ layout: LoupeLayout, from image: CGImage) {
        // The panel: the overlay's own readout-pill look, with a soft shadow so
        // it reads over a bright picture too.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = CGSize(width: 0, height: -3)
        shadow.set()
        let panel = NSBezierPath(roundedRect: layout.frame, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.72).setFill()
        panel.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        let rim = NSBezierPath(roundedRect: layout.frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 9.5, yRadius: 9.5)
        rim.lineWidth = 1
        rim.stroke()

        // The magnified patch, nearest-neighbour so each device pixel is a
        // crisp square. Past the picture's edge the square stays dark.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: layout.square, xRadius: 6, yRadius: 6).addClip()
        NSColor.black.withAlphaComponent(0.85).setFill()
        layout.square.fill()
        if let sample = CaptureLoupe.sample(pointer: layout.pointer, scale: layout.scale,
                                            pixelsAcross: layout.pixels,
                                            imageSize: CGSize(width: image.width, height: image.height),
                                            square: layout.square.width),
           let patch = image.cropping(to: sample.source) {
            NSGraphicsContext.current?.imageInterpolation = .none
            NSGraphicsContext.current?.cgContext.interpolationQuality = .none
            NSImage(cgImage: patch, size: sample.source.size)
                .draw(in: sample.destination.offsetBy(dx: layout.square.minX, dy: layout.square.minY),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                      hints: [.interpolation: NSImageInterpolation.none])
        }
        // Crosshair lines lead to the pointer's pixel and stop short of it, so
        // that one cell is boxed rather than covered.
        let cell = CaptureLoupe.centerCell(pixelsAcross: layout.pixels, square: layout.square.width)
            .offsetBy(dx: layout.square.minX, dy: layout.square.minY)
        // Two-tone, a dark hairline beside a light one, so they read on
        // light and dark pixels alike.
        func crosshair(offset: CGFloat) -> NSBezierPath {
            let lines = NSBezierPath()
            lines.lineWidth = 1
            let midX = round(cell.midX) + offset, midY = round(cell.midY) + offset
            lines.move(to: CGPoint(x: layout.square.minX, y: midY)); lines.line(to: CGPoint(x: cell.minX - 2, y: midY))
            lines.move(to: CGPoint(x: cell.maxX + 2, y: midY)); lines.line(to: CGPoint(x: layout.square.maxX, y: midY))
            lines.move(to: CGPoint(x: midX, y: layout.square.minY)); lines.line(to: CGPoint(x: midX, y: cell.minY - 2))
            lines.move(to: CGPoint(x: midX, y: cell.maxY + 2)); lines.line(to: CGPoint(x: midX, y: layout.square.maxY))
            return lines
        }
        NSColor.black.withAlphaComponent(0.45).setStroke()
        crosshair(offset: -0.5).stroke()
        NSColor.white.withAlphaComponent(0.6).setStroke()
        crosshair(offset: 0.5).stroke()
        // The pixel under the pointer: a white box with a dark rim, visible on
        // any ink.
        NSColor.black.withAlphaComponent(0.7).setStroke()
        let outer = NSBezierPath(rect: cell.insetBy(dx: -1.5, dy: -1.5))
        outer.lineWidth = 1
        outer.stroke()
        NSColor.white.setStroke()
        let inner = NSBezierPath(rect: cell.insetBy(dx: -0.5, dy: -0.5))
        inner.lineWidth = 1
        inner.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // The readout.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.loupeFont,
            .foregroundColor: NSColor.white,
        ]
        var y = layout.square.maxY + Self.loupeReadoutSpacing
        for line in layout.lines {
            NSAttributedString(string: line, attributes: attributes)
                .draw(at: CGPoint(x: layout.square.minX + 2, y: y))
            y += Self.loupeLineHeight
        }
    }
}
