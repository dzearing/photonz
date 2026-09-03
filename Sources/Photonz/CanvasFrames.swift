import AppKit
import PhotonzCore

/// What a frame looks like on the canvas beyond the pixels it paints, and what
/// its name does when you click it (Next, `next-frames`).
///
/// Two pieces of chrome, and both are chrome: they are drawn by the canvas, not
/// by the renderer, so they sit above the picture, stay the same size at every
/// zoom, and never land in an export.
///
/// - **Its name, above its top left corner.** A screen with no label is a white
///   rectangle; the label is how a canvas of several screens stays readable.
///   The name is also the frame's handle: clicking it picks the frame and
///   double clicking it opens the name for typing, so renaming a screen never
///   means going hunting in the Layers list.
/// - **A hairline at its edge.** A frame whose surface matches the canvas
///   behind it would otherwise have no edge at all, and the edge is the thing
///   the whole feature is about.
extension CanvasNSView {

    /// The one font the name is drawn in, measured with, and typed in, so the
    /// letters do not move when the field opens over them.
    static let frameLabelFont = NSFont.systemFont(ofSize: 10, weight: .medium)

    // MARK: Drawing

    func refreshFrameChrome() {
        guard framesEnabled, let viewport, let document, document.hasFrames else {
            frameChromeLayer.isHidden = true
            frameChromeLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            frameEdgeLayer.isHidden = true
            layoutFrameNameField()
            return
        }
        frameChromeLayer.isHidden = false
        frameChromeLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let edges = CGMutablePath()
        for frame in document.frames {
            guard frame.isVisible, let bounds = document.canvasBounds(of: frame.id),
                  bounds.width > 0, bounds.height > 0 else { continue }
            let rect = viewRect(forDocRect: bounds, in: viewport)
            edges.addRect(rect.insetBy(dx: 0.5, dy: 0.5))

            // A frame that has been promoted to a component wears the component
            // mark and name in that same spot, so it keeps its edge but drops
            // this label: one box, one name.
            if frame.isMainComponent, componentsEnabled { continue }
            // The frame being renamed has a field standing where its name was.
            if frame.id == frameRenameID { continue }

            let label = CATextLayer()
            label.string = frame.name
            label.font = Self.frameLabelFont
            label.fontSize = Self.frameLabelFont.pointSize
            // A neutral grey, NOT a theme label color: this text sits on the
            // picture, which may be white, dark, or a screenshot of anything,
            // and a label that follows the app's theme goes invisible on half
            // of them. The accent means "this name is live": the frame is
            // selected, or the pointer is resting on the name, which is the
            // only hint anywhere that the name can be clicked.
            let live = frame.id == selectedLayerID || multiSelectedLayerIDs.contains(frame.id)
                || frame.id == hoveredFrameLabelID
            label.foregroundColor = live
                ? NSColor.controlAccentColor.cgColor
                : CGColor(gray: 0.45, alpha: 1)
            label.contentsScale = window?.backingScaleFactor ?? 2
            label.alignmentMode = .left
            label.truncationMode = .end
            // The label hangs above the frame's top left corner and is never
            // part of it: it does not move the frame, and clicking through it
            // reaches whatever is behind.
            label.frame = FrameNameLabels.box(forFrameRect: rect)
            frameChromeLayer.addSublayer(label)
        }
        frameEdgeLayer.path = edges
        frameEdgeLayer.isHidden = edges.isEmpty
        layoutFrameNameField()
    }

    /// Whether frame chrome is drawn at all. A document with no frames in it
    /// never sees any of this, which is every screenshot anybody has taken.
    private var framesEnabled: Bool { Experiments.shared.framesEnabled }

    // MARK: Clicking a name

    /// Every frame name on screen, in the order they draw, paired with the
    /// frame it belongs to. Empty when frames are off or the document has none.
    private func frameNameLabels() -> [(frame: Layer, label: FrameNameLabel)] {
        guard framesEnabled, let viewport, let document, document.hasFrames else { return [] }
        return document.frames.compactMap { frame in
            guard frame.isVisible, let bounds = document.canvasBounds(of: frame.id),
                  bounds.width > 0, bounds.height > 0 else { return nil }
            // A promoted frame shows the component's name instead, which is
            // renamed in the Component section: it is not this name.
            if frame.isMainComponent, componentsEnabled { return nil }
            let rect = viewRect(forDocRect: bounds, in: viewport)
            let width = (frame.name as NSString)
                .size(withAttributes: [.font: Self.frameLabelFont]).width
            return (frame, FrameNameLabel(id: frame.id, frameRect: rect, textWidth: width.rounded(.up)))
        }
    }

    /// The frame whose name is under `viewPoint`, or nil for anywhere else.
    /// A locked frame answers nothing, the same way its picture does not.
    func frameLabelHit(at viewPoint: CGPoint) -> UUID? {
        let labels = frameNameLabels().filter { !$0.frame.isLocked }.map(\.label)
        return FrameNameLabels.hit(at: viewPoint, labels: labels)
    }

    /// Tints the name the pointer is resting on. Nothing else on the canvas
    /// says a name is more than a caption, so this is the whole invitation.
    func refreshFrameLabelHover(at viewPoint: CGPoint?) {
        let hit = viewPoint.flatMap { point -> UUID? in
            guard tool == .select, frameNameField == nil else { return nil }
            return frameLabelHit(at: point)
        }
        guard hit != hoveredFrameLabelID else { return }
        hoveredFrameLabelID = hit
        refreshFrameChrome()
    }

    // MARK: Typing a name

    /// Opens a frame's name for typing, right where it is drawn, with the whole
    /// name selected so typing replaces it.
    func beginFrameRename(_ id: UUID) {
        guard frameNameField == nil, let entry = frameNameLabels().first(where: { $0.frame.id == id }),
              !entry.frame.isLocked else { return }
        // Renaming a screen picks it: the name you are typing and the box the
        // handles are on are the same thing, and a real double click has
        // already selected it on the press before this one.
        if selectedLayerID != id {
            onSelectLayerInGroup(id, document?.parentID(of: id))
            refreshOverlays()
        }
        let field = FrameNameFieldView(frame: .zero)
        field.string = entry.frame.name
        field.font = Self.frameLabelFont
        field.textColor = .labelColor
        field.insertionPointColor = .labelColor
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.isRichText = false
        field.isFieldEditor = false
        field.isVerticallyResizable = false
        field.isHorizontallyResizable = false
        field.textContainerInset = NSSize(width: 2, height: 2)
        field.textContainer?.lineFragmentPadding = 0
        field.textContainer?.maximumNumberOfLines = 1
        field.delegate = self
        field.wantsLayer = true
        field.layer?.cornerRadius = 3
        field.layer?.borderWidth = 1
        field.layer?.borderColor = NSColor.controlAccentColor.cgColor
        field.onCommit = { [weak self] in self?.commitFrameRename() }
        field.onCancel = { [weak self] in self?.cancelFrameRename() }
        addSubview(field)
        frameNameField = field
        frameRenameID = id
        hoveredFrameLabelID = nil
        refreshFrameChrome()
        window?.makeFirstResponder(field)
        // The whole name, so typing replaces it and one keystroke is a rename.
        field.selectAll(nil)
    }

    /// Keeps the open field over the name it is replacing while the canvas
    /// moves under it (zoom, pan, a nudge of the frame itself), and hugs it to
    /// what is typed so a five letter name does not sit in a field wide enough
    /// for a sentence.
    func layoutFrameNameField() {
        guard let field = frameNameField, let id = frameRenameID else { return }
        guard let entry = frameNameLabels().first(where: { $0.frame.id == id }) else {
            // The frame went away mid-edit (undo, delete). Nothing to rename.
            cancelFrameRename()
            return
        }
        let box = FrameNameLabels.box(forFrameRect: entry.label.frameRect)
        let typed = (field.string as NSString)
            .size(withAttributes: [.font: Self.frameLabelFont]).width
        // Room for a few more letters past what is there, so the field grows
        // ahead of the typing rather than under it.
        let width = min(max(typed.rounded(.up) + 28, 72), FrameNameLabels.maximumWidth)
        field.frame = CGRect(x: box.minX - 3, y: box.minY - 2, width: width, height: box.height + 4)
    }

    /// Return, or a click anywhere else: the typed name lands as one undo step.
    /// An empty name is no name at all, so it leaves the frame as it was.
    func commitFrameRename() {
        guard let field = frameNameField, let id = frameRenameID else { return }
        let typed = field.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = document?.layer(id: id)?.name
        teardownFrameRename()
        if !typed.isEmpty, typed != previous { onRenameLayer(id, typed) }
    }

    /// Escape: the frame keeps the name it had, and nothing reaches history.
    func cancelFrameRename() {
        guard frameNameField != nil else { return }
        teardownFrameRename()
    }

    private func teardownFrameRename() {
        let field = frameNameField
        frameNameField = nil
        frameRenameID = nil
        if let field {
            if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: field) {
                window?.makeFirstResponder(self)
            }
            field.removeFromSuperview()
        }
        refreshFrameChrome()
    }
}

/// The field a frame's name is typed in. A text view rather than a text field
/// because a text field borrows the window's field editor, and AppKit takes
/// that back the moment the window is not key — which is every moment of an
/// unmanned playtest, so the rename could never be driven or photographed. A
/// text view is its own responder and stays open, exactly like the canvas's
/// other inline editors.
final class FrameNameFieldView: NSTextView {
    var onCommit: () -> Void = {}
    var onCancel: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        // A name is one line: Return lands it rather than typing a newline.
        if event.keyCode == 36 || event.keyCode == 76 {
            onCommit()
            return
        }
        if event.keyCode == 53 {
            onCancel()
            return
        }
        super.keyDown(with: event)
    }
}
