import AppKit
import PhotonzCore

/// The name above a box on the canvas, and what it does when you click it
/// (Next, `next-frames` and `next-components`).
///
/// A screen wears its name above its top left corner; a screen or group that
/// has been promoted to a component wears the component's name in that same
/// spot, behind the four-diamond mark. **They are the same handle**: click it to
/// pick the box, double click it to open the name for typing where it sits, so
/// renaming never means going hunting in a panel. The only differences are the
/// paint (grey for a screen, violet for a component) and the few points the
/// mark takes at the left.
///
/// The names are chrome: drawn by the canvas rather than the renderer, so they
/// sit above the picture, stay the same size at every zoom, and never land in
/// an export. That is why every measurement here is in view space, and why the
/// geometry lives in `CanvasNameLabels` (PhotonzCore) where it can be tested.
extension CanvasNSView {

    /// The one font a name is drawn in, measured with, and typed in, so the
    /// letters do not move when the field opens over them.
    static let nameLabelFont = NSFont.systemFont(ofSize: 10, weight: .medium)

    /// The room a component's mark takes in front of its name: the glyph plus
    /// the space after it. A screen's name starts at the box's left edge, so
    /// its inset is zero.
    static let componentMarkInset = componentGlyphSize + 4

    // MARK: What is on screen

    /// Every name on screen, in the order they draw, paired with the layer it
    /// belongs to. Screens first, then components, which is the order the two
    /// chrome layers sit in, so where two names overlap the one you can read
    /// is the one a click finds.
    ///
    /// Empty when the document has nothing that wears a name, which is every
    /// screenshot anybody has taken.
    func canvasNameLabels() -> [(layer: Layer, label: CanvasNameLabel)] {
        guard let viewport, let document else { return [] }
        var labels: [(layer: Layer, label: CanvasNameLabel)] = []
        func append(_ layer: Layer, inset: CGFloat) {
            guard layer.isVisible, let bounds = document.canvasBounds(of: layer.id),
                  bounds.width > 0, bounds.height > 0 else { return }
            let rect = viewRect(forDocRect: bounds, in: viewport)
            let width = (layer.name as NSString)
                .size(withAttributes: [.font: Self.nameLabelFont]).width
            labels.append((layer, CanvasNameLabel(id: layer.id, frameRect: rect,
                                                  textWidth: width.rounded(.up),
                                                  leadingInset: inset)))
        }
        if framesEnabled, document.hasFrames {
            for frame in document.frames {
                // A promoted screen shows the component's name instead: one
                // box, one name, so it is skipped here and picked up below.
                if frame.isMainComponent, componentsEnabled { continue }
                append(frame, inset: 0)
            }
        }
        for main in markedComponents { append(main, inset: Self.componentMarkInset) }
        return labels
    }

    // MARK: Clicking a name

    /// The layer whose name is under `viewPoint`, or nil for anywhere else.
    /// A locked box answers nothing, the same way its picture does not.
    func nameLabelHit(at viewPoint: CGPoint) -> UUID? {
        let labels = canvasNameLabels().filter { !$0.layer.isLocked }.map(\.label)
        return CanvasNameLabels.hit(at: viewPoint, labels: labels)
    }

    /// Tints the name the pointer is resting on. Nothing else on the canvas
    /// says a name is more than a caption, so this is the whole invitation.
    func refreshNameLabelHover(at viewPoint: CGPoint?) {
        let hit = viewPoint.flatMap { point -> UUID? in
            guard tool == .select, canvasNameField == nil else { return nil }
            return nameLabelHit(at: point)
        }
        guard hit != hoveredNameLabelID else { return }
        hoveredNameLabelID = hit
        refreshFrameChrome()
        refreshComponentChrome()
    }

    /// Whether a name is live: its box is selected, or the pointer is resting
    /// on the name. The only hint anywhere that a name can be clicked at all.
    func isNameLabelLive(_ id: UUID) -> Bool {
        id == selectedLayerID || multiSelectedLayerIDs.contains(id) || id == hoveredNameLabelID
    }

    // MARK: Typing a name

    /// Opens a name for typing, right where it is drawn, with the whole name
    /// selected so typing replaces it.
    func beginCanvasRename(_ id: UUID) {
        guard canvasNameField == nil, let entry = canvasNameLabels().first(where: { $0.layer.id == id }),
              !entry.layer.isLocked else { return }
        // Renaming a box picks it: the name you are typing and the box the
        // handles are on are the same thing, and a real double click has
        // already selected it on the press before this one.
        if selectedLayerID != id {
            onSelectLayerInGroup(id, document?.parentID(of: id))
            refreshOverlays()
        }
        let field = CanvasNameFieldView(frame: .zero)
        field.string = entry.layer.name
        field.font = Self.nameLabelFont
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
        // A component's field is outlined in the component violet, the same as
        // the name it replaced, so the box you are typing in still says what
        // kind of thing you are naming.
        field.layer?.borderColor = entry.layer.isMainComponent && componentsEnabled
            ? ComponentGlyph.cgColor
            : NSColor.controlAccentColor.cgColor
        field.onCommit = { [weak self] in self?.commitCanvasRename() }
        field.onCancel = { [weak self] in self?.cancelCanvasRename() }
        addSubview(field)
        canvasNameField = field
        canvasRenameID = id
        hoveredNameLabelID = nil
        refreshFrameChrome()
        refreshComponentChrome()
        window?.makeFirstResponder(field)
        // The whole name, so typing replaces it and one keystroke is a rename.
        field.selectAll(nil)
    }

    /// Keeps the open field over the name it is replacing while the canvas
    /// moves under it (zoom, pan, a nudge of the box itself), and hugs it to
    /// what is typed so a five letter name does not sit in a field wide enough
    /// for a sentence.
    func layoutCanvasNameField() {
        guard let field = canvasNameField, let id = canvasRenameID else { return }
        guard let entry = canvasNameLabels().first(where: { $0.layer.id == id }) else {
            // The box went away mid-edit (undo, delete). Nothing to rename.
            cancelCanvasRename()
            return
        }
        let box = CanvasNameLabels.box(for: entry.label)
        let typed = (field.string as NSString)
            .size(withAttributes: [.font: Self.nameLabelFont]).width
        // Room for a few more letters past what is there, so the field grows
        // ahead of the typing rather than under it.
        let width = min(max(typed.rounded(.up) + 28, 72), CanvasNameLabels.maximumWidth)
        field.frame = CGRect(x: box.minX - 3, y: box.minY - 2, width: width, height: box.height + 4)
    }

    /// Return, or a click anywhere else: the typed name lands as one undo step.
    /// An empty name is no name at all, so it leaves the box as it was.
    ///
    /// A component is renamed as a component rather than as a layer. The name
    /// lives in one place either way, but the component call is the one that
    /// keeps the Library tile and every copy reading from it.
    func commitCanvasRename() {
        guard let field = canvasNameField, let id = canvasRenameID else { return }
        let typed = field.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let layer = document?.layer(id: id)
        let previous = layer?.name
        let componentID = (layer?.isMainComponent == true && componentsEnabled)
            ? layer?.componentID : nil
        teardownCanvasRename()
        guard !typed.isEmpty, typed != previous else { return }
        if let componentID {
            onRenameComponent(componentID, typed)
        } else {
            onRenameLayer(id, typed)
        }
    }

    /// Escape: the box keeps the name it had, and nothing reaches history.
    func cancelCanvasRename() {
        guard canvasNameField != nil else { return }
        teardownCanvasRename()
    }

    private func teardownCanvasRename() {
        let field = canvasNameField
        canvasNameField = nil
        canvasRenameID = nil
        if let field {
            if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: field) {
                window?.makeFirstResponder(self)
            }
            field.removeFromSuperview()
        }
        refreshFrameChrome()
        refreshComponentChrome()
    }
}

/// The field a name is typed in. A text view rather than a text field because a
/// text field borrows the window's field editor, and AppKit takes that back the
/// moment the window is not key — which is every moment of an unmanned
/// playtest, so the rename could never be driven or photographed. A text view
/// is its own responder and stays open, exactly like the canvas's other inline
/// editors.
final class CanvasNameFieldView: NSTextView {
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
