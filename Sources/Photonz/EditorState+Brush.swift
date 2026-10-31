import AppKit
import Foundation
import PhotonzCore

// The Brush's side of the editor (Next, `next-brush`): a finished stroke lands
// in the document as one undo step, and the brush stays in hand for the next
// (`docs/design/brushes.md`).

extension EditorState {

    /// A stroke the canvas finished, in canvas points. One undo step.
    ///
    /// With a paint layer picked the stroke is added to it; otherwise it makes
    /// a new Paint layer just above whatever is picked (on top with nothing
    /// picked) and picks it, so the next stroke goes to the same layer
    /// (`PhotonzDocument.paintStroke`). The Brush stays in hand: it is the one
    /// making tool that does not hand back Select
    /// (`ArrowCaptionEntry.toolAfterLanding`). An agent's stroke lands
    /// through this same call with `picksUpBrush` false: the document and the
    /// pick change exactly as for the pointer, and the tool in the person's
    /// hand stays what it was.
    func addBrushStroke(_ stroke: BrushStroke, picksUpBrush: Bool = true) {
        guard !stroke.samples.isEmpty, document != nil else { return }
        // A smudge drags paint that is already there: it lands on that paint
        // layer and never makes one (decision 7). With no paint under it,
        // nothing happens and nothing goes on the undo list.
        if stroke.settings.mode == .smudge {
            guard document?.smudgeTarget(at: stroke.samples[0].point, picked: selectedLayerID) != nil
            else { return }
            let picked = selectedLayerID
            crispTileForLandingStroke = true
            defer { crispTileForLandingStroke = false }
            perform { $0.smudgeStroke(stroke, onto: picked) }
            return
        }
        let picked = selectedLayerID
        var landed: UUID?
        // The sharp copy of what you can see follows the stroke straight away
        // and the one on screen stays up until it does (`refreshCrispTile`).
        crispTileForLandingStroke = true
        defer { crispTileForLandingStroke = false }
        perform { landed = $0.paintStroke(stroke, onto: picked) }
        guard let landed, landed != picked else { return }
        if picksUpBrush {
            finishCreating(landed, tool: ArrowCaptionEntry.toolAfterLanding(.brush, offersCaption: false))
        } else {
            groupContextID = document?.parentID(of: landed)
            selectedLayerID = landed
        }
    }

    /// What the next stroke is painted with: the armed brush, and the colour
    /// on the tool bar's swatch.
    var armedBrush: BrushSettings { annotationStyles.armedBrush }

    /// What the brush paints with. Picking another medium finds it as it was
    /// last left, or at its own defaults (its own Size among them) if it has
    /// never been used, still painting or smudging as the brush was
    /// (`AnnotationStyles.armBrush`).
    var armedBrushMedium: BrushMedium {
        get { annotationStyles.armedBrush.medium }
        set {
            guard newValue != armedBrushMedium else { return }
            annotationStyles.armBrush(newValue)
            saveAnnotationStyles()
        }
    }

    /// Sets one of the armed brush's settings, from the capsule over the tool
    /// bar or the panel. The next stroke paints with it; strokes already made
    /// keep the brush they were painted with.
    func setArmedBrushSetting(_ id: String, to value: Double) {
        var brush = annotationStyles.armedBrush
        brush.set(id, to: value)
        guard brush != annotationStyles.armedBrush else { return }
        annotationStyles.setArmedBrush(brush)
        saveAnnotationStyles()
    }

    /// ] grows the brush and [ shrinks it, in Photoshop's steps (`BrushSize`).
    func stepBrushSize(larger: Bool) {
        setArmedBrushSetting("size", to: BrushSize.stepped(armedBrush.size, larger: larger))
    }

    /// Whether [ and ] step the brush now: with it in hand on a picture.
    var bracketsStepBrushSize: Bool {
        Experiments.shared.brushEnabled && activeTool == .brush && document != nil
    }

    /// Whether the brush paints or smudges.
    var armedBrushMode: BrushMode {
        get { annotationStyles.armedBrush.mode }
        set {
            guard newValue != armedBrushMode else { return }
            var brush = annotationStyles.armedBrush
            brush.mode = newValue
            annotationStyles.setArmedBrush(brush)
            saveAnnotationStyles()
        }
    }

    var armedBrushColorHex: String {
        annotationStyles.colorHex(for: .brush) ?? AnnotationStyles.defaultBrushColorHex
    }
}

// MARK: - Picking a brush from its tile

extension EditorState {

    /// How many tiles the chooser lays across.
    static let brushChooserColumns = 3

    /// A brush tile picked, in the Library or the chooser: that brush is the
    /// one in hand and the Brush tool with it, so the next stroke paints with
    /// it (`brush-library.html`: "Picking a tile sets the active brush").
    func pickBrush(_ medium: BrushMedium) {
        armedBrushMedium = medium
        if activeTool != .brush { setTool(.brush) }
    }

    /// The settings a brush's tile is painted at: what picking it would give
    /// you, as that brush was last left (`AnnotationStyles.brush(for:)`).
    func brushTileSettings(_ medium: BrushMedium) -> BrushSettings {
        annotationStyles.brush(for: medium)
    }

    /// The tiles the chooser shows for the chip it is on.
    var brushChooserBrushes: [BrushMedium] { BrushLibrary.brushes(in: brushChooserGroup) }

    /// Opens or closes the chooser. Open, the arrow keys move between its
    /// tiles, Return picks the one reached and Escape closes it, wherever the
    /// keyboard is: the chooser floats over the picture, which keeps it.
    func setBrushChooserOpen(_ open: Bool) {
        guard open != isBrushChooserOpen || (open && brushChooserKeys == nil) else { return }
        isBrushChooserOpen = open
        if open {
            brushChooserHighlight = armedBrush.medium
            if !brushChooserBrushes.contains(armedBrush.medium) { brushChooserGroup = nil }
            watchBrushChooserKeys()
        } else {
            if let monitor = brushChooserKeys { NSEvent.removeMonitor(monitor) }
            brushChooserKeys = nil
        }
    }

    /// One key in the open chooser. True when the chooser took it.
    @discardableResult
    func brushChooserKey(_ key: BrushChooserKey) -> Bool {
        guard isBrushChooserOpen else { return false }
        let tiles = brushChooserBrushes
        switch key {
        case .arrow(let arrow):
            let from = brushChooserHighlight.flatMap { tiles.firstIndex(of: $0) }
            if let to = BrushLibrary.step(from: from, arrow, count: tiles.count,
                                          columns: Self.brushChooserColumns) {
                brushChooserHighlight = tiles[to]
            }
        case .pick:
            if let medium = brushChooserHighlight, tiles.contains(medium) { pickBrush(medium) }
            setBrushChooserOpen(false)
        case .close:
            setBrushChooserOpen(false)
        }
        return true
    }

    private func watchBrushChooserKeys() {
        guard brushChooserKeys == nil else { return }
        brushChooserKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let key = BrushChooserKey(keyCode: event.keyCode),
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty
            else { return event }
            let took = MainActor.assumeIsolated { self?.brushChooserKey(key) ?? false }
            return took ? nil : event
        }
    }
}

/// A key the open brush chooser answers.
enum BrushChooserKey: Equatable {
    case arrow(BrushLibrary.Arrow)
    case pick
    case close

    init?(keyCode: UInt16) {
        switch keyCode {
        case 123: self = .arrow(.left)
        case 124: self = .arrow(.right)
        case 125: self = .arrow(.down)
        case 126: self = .arrow(.up)
        case 36, 76: self = .pick       // Return, and Enter on the keypad
        case 53: self = .close          // Escape
        default: return nil
        }
    }
}

extension EditorState {
    /// Whether the Library offers its Brushes shelf: while the Brush is in
    /// hand, the way a tool's own section is in the panel only while its
    /// tool is (`PanelToolSettings`). A shelf left on Brushes opens on it
    /// again the next time the Brush is picked up.
    var libraryOffersBrushes: Bool {
        Experiments.shared.brushEnabled && activeTool == .brush
    }
}
