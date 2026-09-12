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

    /// One chip in the strip above the boxes: a screen's name, a component's
    /// name behind its mark, or the mark a copy wears.
    struct CanvasNameChip {
        enum Kind { case screen, component, copyMark }
        let layer: Layer
        let label: CanvasNameLabel
        let kind: Kind
        /// What this chip says when nobody is looking at it: the layer's name,
        /// or which version of its component the drawing is, never both
        /// (`CanvasNameLabels.caption`).
        let caption: CanvasNameLabels.Caption
        /// What it says while it IS the drawing you are looking at: the
        /// component's name, and which version this one is when there is more
        /// than one.
        let liveCaption: CanvasNameLabels.Caption
        /// Whether it is saying the longer thing right now. Only ever true when
        /// the two differ, so a screen and a plain component never change a
        /// pixel when you point at them.
        let spelledOut: Bool

        /// The one word printed above the drawing, nil for a copy of the first
        /// version nobody is looking at, which wears its mark and nothing else.
        var word: String? { (spelledOut ? liveCaption : caption).word }
    }

    /// How wide `word` prints in the name font, zero for nothing to print.
    static func captionWidth(_ word: String?) -> CGFloat {
        guard let word, !word.isEmpty else { return 0 }
        return (word as NSString)
            .size(withAttributes: [.font: nameLabelFont]).width.rounded(.up)
    }

    /// Everything drawn in that strip, in the order it draws, back to front:
    /// screens, then components, then the marks on copies. That order is what
    /// decides who moves when two of them want the same spot, and a screen
    /// wants its own name against its own edge.
    ///
    /// Names that would print on top of each other are stacked here, ONCE, so
    /// drawing a name, clicking a name and typing in a name all agree about
    /// where it ended up. A copy's bare mark is in the list too: a diamond over
    /// a screen's name is the same mess as a word over a word.
    ///
    /// Empty when the document has nothing that wears a name, which is every
    /// screenshot anybody has taken.
    /// The box a name hangs above once turning is in the picture: the box the
    /// turn puts the drawing in, so the mark on a copy on a slant sits over
    /// the slanted copy rather than over the upright box it used to fill.
    ///
    /// It is the box AROUND the turned drawing, not a turned box: a name is
    /// read left to right whatever the thing under it is doing, and a label
    /// printed on a slant would be a second thing to decipher.
    private func turned(_ bounds: CGRect, of layer: Layer) -> CGRect {
        let own = layer.transform.isIdentity
            ? CGAffineTransform.identity
            : layer.transform.affineTransform(
                around: CGPoint(x: bounds.midX, y: bounds.midY))
        let map = own.concatenating(inheritedTurn(of: layer.id))
        guard !map.isIdentity else { return bounds }
        let corners = [CGPoint(x: bounds.minX, y: bounds.minY),
                       CGPoint(x: bounds.maxX, y: bounds.minY),
                       CGPoint(x: bounds.maxX, y: bounds.maxY),
                       CGPoint(x: bounds.minX, y: bounds.maxY)].map { $0.applying(map) }
        return corners.dropFirst().reduce(CGRect(origin: corners[0], size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
    }

    func canvasNameChips() -> [CanvasNameChip] {
        guard let viewport, let document else { return [] }
        var chips: [CanvasNameChip] = []
        // Which drawings say which version they are, worked out once for the
        // whole canvas rather than per chip, and empty for every document that
        // has never been given a second version.
        let versions = componentsEnabled ? document.canvasVersionNames() : [:]
        func append(_ layer: Layer, inset: CGFloat, kind: CanvasNameChip.Kind) {
            // Live, so a name keeps its place above the corner it belongs to
            // while that corner is being dragged (`liveCanvasBounds`).
            guard layer.isVisible, let bounds = liveCanvasBounds(of: layer.id),
                  bounds.width > 0, bounds.height > 0 else { return }
            let rect = viewRect(forDocRect: turned(bounds, of: layer), in: viewport)
            let version = kind == .screen ? nil : versions[layer.id]
            let caption = CanvasNameLabels.caption(name: layer.name, version: version,
                                                   isCopy: kind == .copyMark)
            let live = CanvasNameLabels.caption(name: layer.name, version: version,
                                                isCopy: kind == .copyMark, isLive: true)
            chips.append(CanvasNameChip(layer: layer,
                                        label: CanvasNameLabel(id: layer.id, frameRect: rect,
                                                               textWidth: Self.captionWidth(caption.word),
                                                               leadingInset: inset,
                                                               // A version is the word that tells
                                                               // two drawings apart, so a small box
                                                               // widens its caption rather than
                                                               // cutting it off.
                                                               fitsWholeText: caption.version != nil),
                                        kind: kind, caption: caption, liveCaption: live,
                                        spelledOut: false))
        }
        if framesEnabled, document.hasFrames {
            for frame in document.frames {
                // A promoted screen shows the component's name instead: one
                // box, one name, so it is skipped here and picked up below.
                if frame.isMainComponent, componentsEnabled { continue }
                append(frame, inset: 0, kind: .screen)
            }
        }
        for main in markedComponents { append(main, inset: Self.componentMarkInset, kind: .component) }
        for copy in markedComponentInstances {
            // A copy with a version to say gets the same air after its mark
            // that a component's name gets; a bare mark needs none.
            append(copy, inset: versions[copy.id] == nil
                    ? Self.componentGlyphSize : Self.componentMarkInset,
                   kind: .copyMark)
        }
        // Where the names sit is worked out from what they say AT REST, so the
        // one you are looking at growing its word never shuffles the rest of
        // the row out from under your pointer. It draws over its neighbours on
        // its own plate instead.
        let stacked = CanvasNameLabels.stacked(chips.map(\.label))
        return zip(chips, stacked).map { chip, placed in
            guard chip.liveCaption != chip.caption, isNameSpelledOut(chip.layer.id) else {
                return CanvasNameChip(layer: chip.layer, label: placed, kind: chip.kind,
                                      caption: chip.caption, liveCaption: chip.liveCaption,
                                      spelledOut: false)
            }
            // The letters start after the mark with a little air, even on a
            // copy whose bare diamond needed none, and the whole name prints
            // rather than being cut back to the width of the drawing: a name
            // that appeared because you looked at it and then said "Save b…"
            // would be worse than the diamond it replaced.
            let label = CanvasNameLabel(id: placed.id, frameRect: placed.frameRect,
                                        textWidth: Self.captionWidth(chip.liveCaption.word),
                                        leadingInset: Self.componentMarkInset,
                                        fitsWholeText: true)
            return CanvasNameChip(layer: chip.layer, label: label, kind: chip.kind,
                                  caption: chip.caption, liveCaption: chip.liveCaption,
                                  spelledOut: true)
        }
    }

    /// Every name a click can land on, paired with the layer it belongs to. A
    /// copy's mark is not one of them: it says what the copy is, it is not a
    /// handle.
    func canvasNameLabels() -> [(layer: Layer, label: CanvasNameLabel)] {
        canvasNameChips().filter { $0.kind != .copyMark }.map { ($0.layer, $0.label) }
    }

    // MARK: Clicking a name

    /// The layer whose name is under `viewPoint`, or nil for anywhere else.
    /// A locked box answers nothing, the same way its picture does not.
    func nameLabelHit(at viewPoint: CGPoint) -> UUID? {
        let labels = canvasNameLabels().filter { !$0.layer.isLocked }.map(\.label)
        return CanvasNameLabels.hit(at: viewPoint, labels: labels)
    }

    /// The component drawing a point on the canvas belongs to: the copy itself,
    /// or the main component the piece under the pointer is part of. Nil out on
    /// bare canvas and on everything that is not a component, which is every
    /// screenshot anybody has taken.
    ///
    /// A copy answers for its own insides already, so the walk up the tree is
    /// for an ORIGINAL: pointing at the word on a button lands on the text
    /// layer, and the thing you are looking at is the button.
    func lookedAtComponent(at viewPoint: CGPoint) -> UUID? {
        guard componentsEnabled, tool == .select, canvasNameField == nil,
              let viewport, let document,
              !markedComponents.isEmpty || !markedComponentInstances.isEmpty
        else { return nil }
        let point = viewport.documentPoint(fromView: viewPoint)
        guard let hit = document.canvasHitTest(point, zoom: viewport.zoom) else { return nil }
        var step: UUID? = hit.id
        while let id = step, let layer = document.layer(id: id) {
            if layer.isComponentInstance || layer.isMainComponent { return id }
            step = document.parentID(of: id)
        }
        return nil
    }

    /// Tints the name the pointer is resting on, and spells out the name of the
    /// component drawing it is resting on. Nothing else on the canvas says a
    /// name is more than a caption, so the tint is the whole invitation; the
    /// spelled-out name is the answer to "which component is this one".
    func refreshNameLabelHover(at viewPoint: CGPoint?) {
        let looked = viewPoint.flatMap { lookedAtComponent(at: $0) }
        let previous = lookedAtComponentID
        // Set before the labels are asked anything: the drawing you are looking
        // at has a wider name than the one it wears at rest, and the click that
        // name answers has to be the one a person can see.
        lookedAtComponentID = looked
        let hit = viewPoint.flatMap { point -> UUID? in
            guard tool == .select, canvasNameField == nil else { return nil }
            return nameLabelHit(at: point)
        }
        guard hit != hoveredNameLabelID || looked != previous else { return }
        hoveredNameLabelID = hit
        refreshFrameChrome()
        refreshComponentChrome()
    }

    /// Whether a name is live: its box is selected, or the pointer is resting
    /// on the name. The only hint anywhere that a name can be clicked at all.
    func isNameLabelLive(_ id: UUID) -> Bool {
        id == selectedLayerID || multiSelectedLayerIDs.contains(id) || id == hoveredNameLabelID
    }

    /// The ONE drawing saying its whole name rather than the short word it
    /// wears at rest: the one your pointer is resting on, or, when the pointer
    /// is not on anything, the one you have picked.
    ///
    /// Exactly one, because the name it spells out is the component's and every
    /// drawing of that component carries the same one. Two of them side by side
    /// print "Primary · Default" hard against "Primary · Off" and read as one
    /// long bar saying Primary twice, which is the very shape the short labels
    /// exist to avoid. A whole box selection would print it a dozen times.
    ///
    /// Pointing at something wins over having picked something: whatever you
    /// picked a moment ago, the drawing under your hand right now is the one
    /// you are asking about.
    var spelledOutComponentID: UUID? {
        if let lookedAtComponentID { return lookedAtComponentID }
        if let hoveredNameLabelID { return hoveredNameLabelID }
        // A band swept round a dozen buttons picked all of them and asked
        // about none of them.
        guard multiSelectedLayerIDs.count <= 1 else { return nil }
        return selectedLayerID
    }

    /// Whether this drawing is the one saying its whole name.
    func isNameSpelledOut(_ id: UUID) -> Bool { id == spelledOutComponentID }

    /// Which version this drawing is, when the word above it says the version
    /// rather than the component's name.
    ///
    /// The word on the canvas is a handle, so it has to be the word that gets
    /// typed over: a label reading "Disabled" that opened a field saying
    /// "Button" would be a rename nobody asked for. So where the label shows a
    /// version, double clicking it renames the VERSION, through the same call
    /// the Versions list in the Component panel makes.
    func canvasRenameVersion(of id: UUID) -> (component: UUID, version: ComponentVersion)? {
        guard componentsEnabled, let document,
              let chip = canvasNameChips().first(where: { $0.layer.id == id }),
              chip.kind == .component, chip.caption.version != nil,
              let componentID = chip.layer.componentID,
              let version = document.componentVersions(of: componentID)
                  .first(where: { $0.layerID == id })
        else { return nil }
        return (componentID, version)
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
        // The word on screen, not the layer's name: on a drawing labelled with
        // its version those are two different words.
        field.string = canvasRenameVersion(of: id)?.version.name ?? entry.layer.name
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
    /// Whatever word was on the canvas is the word that changes. A drawing
    /// labelled with its version renames the version; a component renames as a
    /// component rather than as a layer, because that is the call the Library
    /// tile and every copy read from; anything else renames the layer.
    func commitCanvasRename() {
        guard let field = canvasNameField, let id = canvasRenameID else { return }
        let typed = field.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let layer = document?.layer(id: id)
        let renaming = canvasRenameVersion(of: id)
        let previous = renaming?.version.name ?? layer?.name
        let componentID = (layer?.isMainComponent == true && componentsEnabled)
            ? layer?.componentID : nil
        teardownCanvasRename()
        guard !typed.isEmpty, typed != previous else { return }
        if let renaming {
            onRenameComponentVersion(renaming.component, renaming.version.id, typed)
        } else if let componentID {
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
