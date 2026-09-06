import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

// Arrows, boxes, captions and zoom callouts: making them, wording them,
// placing them, and styling them.
//
// Split out of EditorState.swift; nothing here changed on the way over.
extension EditorState {
    /// Completed drag-to-create from the canvas (document coords, ⇧ already
    /// applied). Adds one annotation layer as a single undo step. Returns the
    /// created layer when the canvas should immediately offer caption entry
    /// (a fresh arrow with the Next captions flag on), nil otherwise.
    @discardableResult
    func addAnnotation(from start: CGPoint, to end: CGPoint) -> Layer? {
        guard let shape = activeTool.annotationShape,
              let content = activeAnnotationContent else { return nil }
        var layer = AnnotationBuilder.layer(content: content, from: start, to: end)
        // Inherit this shape's last non-destructive effects (e.g. a drop shadow
        // added to the previous arrow carries to the next).
        layer.style = annotationStyles.layerStyle(forShape: shape)
        // ...and any SAVED colour the tool is holding, so the new shape wears
        // the name rather than a copy of it and still follows the name the day
        // it is edited. The document has the last word: a name it has never
        // heard of falls back to the flat colour the tool remembers with it.
        if let document {
            layer = document.wearingArmedColorStyles(layer, styles: annotationStyles)
        }
        perform { [layer] in $0.addLayerDrawnOnFrame(layer) }
        // ...and if the name could not come along, one line saying so, rather
        // than a shape that is quietly not the colour the swatch promised.
        // After the edit, so it wins the canvas slot the way a break does.
        announceMissingArmedColorStyle(layer)
        // An arrow that is about to offer its caption is not finished yet: the
        // Arrow tool stays in hand while the field is open (a drag draws the
        // next arrow), and the hand-back to Select happens when the field
        // closes (`commitCaptionEdit` / `cancelCaptionEdit`).
        let offersCaption = shape == .arrow && Experiments.shared.arrowCaptionsEnabled
        finishCreating(layer.id,
                       tool: ArrowCaptionEntry.toolAfterLanding(activeTool, offersCaption: offersCaption))
        return offersCaption ? layer : nil
    }

    /// A caption edit session opened on `layerID`'s arrow. While it's open the
    /// composite renders that arrow WITHOUT its pill — the inline editor
    /// overlay stands in for it, like the text tool's editor stands in for its
    /// layer.
    func beginCaptionEdit(layerID: UUID) {
        guard let layer = document?.layer(id: layerID),
              layer.annotation?.shape == .arrow else { return }
        editingCaptionLayerID = layerID
        if let document { submit(document) }
    }

    /// Caption entry finished. Whitespace-only text clears the caption (or
    /// leaves a fresh arrow plain); anything else lands as one undo step.
    /// Newlines collapse to spaces — the pill is a single line. Closing the
    /// field finishes the arrow, so the Arrow tool that stayed live hands back
    /// to Select; `keepTool` is the canvas drag that starts the NEXT arrow with
    /// this same press and wants the tool to stay put.
    func commitCaptionEdit(layerID: UUID, string: String,
                           placement: CaptionPlacement? = nil, keepTool: Bool = false) {
        editingCaptionLayerID = nil
        if !keepTool { setTool(ArrowCaptionEntry.toolAfterClosing(activeTool)) }
        guard let layer = document?.layer(id: layerID),
              let annotation = layer.annotation else {
            rerender()
            return
        }
        let newCaption = ArrowCaptionEntry.caption(from: string)
        guard annotation.caption != newCaption else {
            rerender() // un-suppress the pill
            return
        }
        perform { document in
            guard let current = document.layer(id: layerID) else { return }
            // The field already picked the pill's spot when it opened and held
            // it through every keystroke, so committing writes that same spot:
            // the label lands where it was, with no jump on Return. A caption
            // set without a field (the inspector) has no spot yet, so the
            // planner picks one against the picture.
            let restyled: Layer
            if let placement {
                restyled = AnnotationBuilder.captioning(current, caption: newCaption,
                                                        placement: placement)
            } else {
                let recaptioned = AnnotationBuilder.restyled(current,
                                                             caption: .some(newCaption))
                restyled = AnnotationBuilder.planningCaption(
                    recaptioned, canvas: document.canvasSize,
                    captionPillSize: recaptioned.measuredCaptionPillSize)
            }
            document.updateLayer(id: layerID) {
                $0.content = restyled.content
                $0.frame = restyled.frame
            }
        }
    }

    /// Live inspector-slider caption size (no undo step), over every picked
    /// arrow: three labelled arrows resize their words together.
    func previewCaptionFontSize(ids: [UUID], _ size: CGFloat) {
        guard var doc = document else { return }
        let targets = captionTargets(ids, in: doc)
        guard !targets.isEmpty else { return }
        discardDragPreview()
        for id in targets {
            doc.updateLayer(id: id) { $0 = AnnotationBuilder.restyled($0, captionFontSize: size) }
        }
        submit(doc)
    }

    func previewCaptionFontSize(layerID: UUID, _ size: CGFloat) {
        previewCaptionFontSize(ids: [layerID], size)
    }

    /// Slider release: ONE undo step however many arrows it reached; each
    /// pill re-picks its spot for the new size, and the next arrow's caption
    /// starts at it.
    func commitCaptionFontSize(ids: [UUID], _ size: CGFloat) {
        guard let doc = document else { return }
        let targets = captionTargets(ids, in: doc)
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { document in
            let canvas = document.canvasSize
            for id in targets {
                document.updateLayer(id: id) {
                    let resized = AnnotationBuilder.restyled($0, captionFontSize: size)
                    $0 = AnnotationBuilder.planningCaption(
                        resized, canvas: canvas,
                        captionPillSize: resized.measuredCaptionPillSize)
                }
            }
        }
        annotationStyles.setCaptionFontSize(size, forShape: .arrow)
        saveAnnotationStyles()
    }

    func commitCaptionFontSize(layerID: UUID, _ size: CGFloat) {
        commitCaptionFontSize(ids: [layerID], size)
    }

    /// The picked layers a caption row may touch: arrows, unlocked.
    private func captionTargets(_ ids: [UUID], in doc: PhotonzDocument) -> [UUID] {
        ids.filter {
            doc.layer(id: $0).map { $0.annotation?.shape == .arrow && !$0.isLocked } == true
        }
    }

    /// Live drag of a caption pill (no history): the pill follows the pointer,
    /// pulled back onto the picture at the edges, and the frame follows it.
    func previewCaptionPlacement(id: UUID, center: CGPoint) {
        let center = parentPoint(center, of: id)
        guard var doc = document, doc.layer(id: id)?.annotation?.hasCaption == true else { return }
        discardDragPreview()
        let canvas = doc.canvasSize
        doc.updateLayer(id: id) {
            $0 = AnnotationBuilder.placingCaption($0, at: center, canvas: canvas,
                                                  captionPillSize: $0.measuredCaptionPillSize)
        }
        if let frame = doc.canvasLayer(id: id)?.frame { previewMoves = [id: frame] }
        submit(doc)
    }

    /// The drop: one undo step that pins the pill where it landed. Undo
    /// returns it to the spot the app picked; so does Reset position in the
    /// inspector (`resetCaptionPlacement`).
    func commitCaptionPlacement(id: UUID, center: CGPoint) {
        let center = parentPoint(center, of: id)
        previewMoves = [:]
        guard document?.layer(id: id)?.annotation?.hasCaption == true else {
            rerender()
            return
        }
        perform { document in
            let canvas = document.canvasSize
            document.updateLayer(id: id) {
                $0 = AnnotationBuilder.placingCaption($0, at: center, canvas: canvas,
                                                      captionPillSize: $0.measuredCaptionPillSize)
            }
        }
    }

    /// Esc mid-drag, or a press on the pill that never moved: nothing was
    /// committed, so the last committed document just renders again.
    func cancelCaptionPlacement() {
        previewMoves = [:]
        rerender()
    }

    /// Hands a hand-placed pill back to the app's placement (one undo step).
    func resetCaptionPlacement(id: UUID) { resetCaptionPlacement(ids: [id]) }

    /// The same over every picked arrow whose pill was moved by hand: they all
    /// go back to the spot the app picks, in one undo step.
    func resetCaptionPlacement(ids: [UUID]) {
        guard let doc = document else { return }
        let targets = ids.filter { doc.layer(id: $0)?.annotation?.captionPinned == true }
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { document in
            let canvas = document.canvasSize
            for id in targets {
                document.updateLayer(id: id) {
                    $0 = AnnotationBuilder.releasingCaption(
                        $0, canvas: canvas, captionPillSize: $0.measuredCaptionPillSize)
                }
            }
        }
    }

    /// Caption entry abandoned (Esc): the arrow keeps whatever caption it had,
    /// and is finished, so the Arrow tool that stayed live hands back to Select.
    func cancelCaptionEdit() {
        editingCaptionLayerID = nil
        setTool(ArrowCaptionEntry.toolAfterClosing(activeTool))
        rerender()
    }

    /// Docked-inspector caption edit: same semantics as a committed inline
    /// session (empty clears), without any canvas session.
    func setAnnotationCaption(layerID: UUID, _ caption: String) {
        commitCaptionEdit(layerID: layerID, string: caption)
    }

    /// What every draw tool does the moment its object exists: hand the editor
    /// back to Select with the new layer selected, so it can be nudged with the
    /// arrow keys, restyled, or dragged without a trip to the toolbar. (Reverses
    /// 17.12's sticky Photoshop-style tools — user request 2026-08-21: "when I
    /// draw a line or a measure or any object, I want the tool to switch to V
    /// and the object selected, so I can left/right arrow".)
    ///
    /// Re-affirmed for Measure on 2026-09-02: the end-to-end redline walk
    /// counted seven presses of I for four measurements and asked whether the
    /// ruler should stay in hand instead. The answer was no — every drawing
    /// tool hands back, and a ruler that did not would be the one exception.
    /// The cost is paid back by the mode being sticky: one press of I returns
    /// to Measure in the mode you left it in, never a hunt through the modes.
    /// `Scripts/playtest/measure-handback.json` walks all four Measure modes
    /// and is the guard on this, so do not change it without a new decision.
    func finishCreating(_ layerID: UUID, tool: Tool = .select) {
        setTool(tool)
        // A layer drawn onto a frame is selected INSIDE that frame, so Escape
        // steps back out to the frame rather than dropping the selection, and
        // the next click on a sibling stays at that level.
        groupContextID = document?.parentID(of: layerID)
        selectedLayerID = layerID
    }

    /// Completed source-box drag from the zoom tool. One undo step adds the
    /// callout (placement picked by Geometry), then the editor returns to select
    /// with it selected.
    ///
    /// Placement is handed the callouts already on the picture, so the new box
    /// steps clear of them rather than landing on the last one drawn.
    func addZoomCallout(from start: CGPoint, to end: CGPoint) {
        guard let document,
              let layer = ZoomCalloutBuilder.layer(from: start, to: end,
                                                   canvas: document.canvasSize,
                                                   magnification: calloutToolMagnification,
                                                   shape: calloutToolShape,
                                                   avoiding: document.placedZoomCalloutRects) else { return }
        perform { $0.addLayerDrawnOnFrame(layer) }
        finishCreating(layer.id)
    }

    // MARK: - Annotation styling

    /// Styled content the active tool would draw, for the canvas drag preview.
    /// Each shape remembers its OWN color (and width/heads/fill) — the toolbar's
    /// single color swatch edits the active tool's color, so a red line and a
    /// blue arrow stay independent (17.12; supersedes 16.12's shared-FG model,
    /// which conflated shape color with the paint-bucket foreground color). The
    /// FG/BG swatch is now only the fill/bucket paint pair.
    var activeAnnotationContent: AnnotationContent? {
        annotationStyles.content(for: activeTool)
    }

    /// The non-destructive style a freshly drawn shape inherits (border, corner
    /// radius, shadow…). The live draw preview needs it because a shape's visible
    /// outline can live in the LAYER border (rectangles: strokeWidth 0 + a border
    /// width) rather than the annotation's own stroke — without it the draft looks
    /// empty until commit. Nil for non-shape tools.
    var activeAnnotationStyle: LayerStyle? {
        guard let shape = activeTool.annotationShape else { return nil }
        return annotationStyles.layerStyle(forShape: shape)
    }

    /// The selected annotation layer when the select tool is active — the
    /// style popover edits this layer instead of the new-annotation defaults.
    var selectedAnnotationLayer: Layer? {
        guard activeTool == .select, let id = selectedLayerID,
              let layer = document?.layer(id: id), layer.annotation != nil else { return nil }
        return layer
    }

    /// A pick from the toolbar's colour row restyles the selected annotation
    /// (one undo step) when there is one; either way it becomes the default
    /// for new annotations.
    ///
    /// It takes a whole paint, so the tool in your hand can be armed with a
    /// gradient and a run of shapes comes out gradient without painting each
    /// one afterwards.
    func setAnnotationPaint(_ paint: Paint) {
        // Per-tool color (17.12): a shape's color is its OWN, not the shared
        // paint-bucket foreground — picking here never touches the FG swatch.
        if let layer = selectedAnnotationLayer, let shape = layer.annotation?.shape {
            discardDragPreview() // a click-select's held sprite shows the old style
            perform { $0.updateLayer(id: layer.id) { $0 = AnnotationBuilder.restyled($0, paint: paint) } }
            annotationStyles.setPaint(paint, forShape: shape)
        } else {
            // A plain colour is a plain colour: this is where a tool holding a
            // saved one lets go of it, so it is where the app says so.
            pickingPlainColor(slot: .stroke) { annotationStyles.setPaint(paint, for: activeTool) }
        }
        saveAnnotationStyles()
        // The recents row is a row of colors, so a gradient leaves its flat
        // color there rather than nothing.
        recordRecentColor(hex: paint.hex)
    }

    /// What the current selection/tool draws its outline in, gradient and all.
    var activeToolPaint: Paint? {
        if let layer = selectedAnnotationLayer { return layer.annotation?.paint }
        return annotationStyles.paint(for: activeTool)
    }

    /// The interior fill the current selection/tool draws with (rectangle /
    /// ellipse), gradient and all; nil = no fill.
    var activeToolFillPaint: Paint? {
        if let layer = selectedAnnotationLayer { return layer.annotation?.fill }
        return annotationStyles.fillPaint(for: activeTool)
    }

    /// A fill pick for the selected box (one undo step) or, with none selected,
    /// the active tool's new-shape default, so the next box comes out of the
    /// tool already carrying it. nil = no fill (outline only).
    func setAnnotationFillPaint(_ paint: Paint?) {
        if let layer = selectedAnnotationLayer, let shape = layer.annotation?.shape {
            discardDragPreview()
            perform { $0.updateLayer(id: layer.id) { $0 = AnnotationBuilder.restyled($0, fill: .some(paint)) } }
            annotationStyles.setFillPaint(paint, forShape: shape)
        } else {
            // Including "no fill": taking the inside away is a pick like any
            // other, and the box stops being Accent just the same.
            pickingPlainColor(slot: .fill) { annotationStyles.setFillPaint(paint, for: activeTool) }
        }
        saveAnnotationStyles()
        if let paint { recordRecentColor(hex: paint.hex) }
    }

    /// The shape a toolbar-popover style edit applies to: the selected
    /// annotation's shape (select tool) or the active drawing tool's shape.
    private var styleTargetShape: AnnotationShape? {
        selectedAnnotationLayer?.annotation?.shape ?? activeTool.annotationShape
    }

    func setAnnotationStrokeWidth(_ width: CGFloat) {
        if let layer = selectedAnnotationLayer, layer.annotation?.shape != .highlight {
            discardDragPreview()
            perform { $0.updateLayer(id: layer.id) { $0 = AnnotationBuilder.restyled($0, strokeWidth: width) } }
        }
        if let shape = styleTargetShape, shape != .highlight {
            annotationStyles.setStrokeWidth(width, forShape: shape)
        }
        saveAnnotationStyles()
    }

    /// Live slider drag: restyle the selected stroke/arrow WITHOUT recording an
    /// undo step (the canvas updates immediately), keeping that shape's default
    /// in sync so the value also applies to the next-drawn annotation. Commit on
    /// release via `setAnnotationStrokeWidth` / `setAnnotationArrowheadScale`.
    func previewAnnotationRestyle(strokeWidth: CGFloat? = nil, arrowheadScale: CGFloat? = nil) {
        if let shape = styleTargetShape {
            if let strokeWidth, shape != .highlight { annotationStyles.setStrokeWidth(strokeWidth, forShape: shape) }
            if let arrowheadScale { annotationStyles.setArrowheadScale(arrowheadScale, forShape: shape) }
        }
        guard let layer = selectedAnnotationLayer, var doc = document else { return }
        discardDragPreview()
        doc.updateLayer(id: layer.id) {
            $0 = AnnotationBuilder.restyled($0, strokeWidth: strokeWidth, arrowheadScale: arrowheadScale)
        }
        submit(doc)
    }

    /// Arrow-only: the arrowhead size multiplier. Restyles the selected arrow
    /// (one undo step) and updates the arrow default for new arrows.
    func setAnnotationArrowheadScale(_ scale: CGFloat) {
        if let layer = selectedAnnotationLayer, layer.annotation?.shape == .arrow {
            discardDragPreview()
            perform { $0.updateLayer(id: layer.id) { $0 = AnnotationBuilder.restyled($0, arrowheadScale: scale) } }
        }
        if let shape = styleTargetShape, shape == .arrow {
            annotationStyles.setArrowheadScale(scale, forShape: .arrow)
        }
        saveAnnotationStyles()
    }

    // MARK: - Layers-panel annotation inspector (targets a specific layer,
    // independent of the active tool — so editing a selected line/arrow's style
    // from the docked panel always reaches the document and that shape's default).

    /// Live inspector-slider restyle of `layerID` (no undo step). Updates the
    /// shape's persisted default too, so the next-drawn object of that type
    /// inherits it.
    func previewAnnotationRestyle(layerID: UUID, strokeWidth: CGFloat? = nil, arrowheadScale: CGFloat? = nil,
                                  cornerRadius: CGFloat? = nil) {
        previewAnnotationRestyle(ids: [layerID], strokeWidth: strokeWidth,
                                 arrowheadScale: arrowheadScale, cornerRadius: cornerRadius)
    }

    /// Inspector slider release: one undo step + persist the shape default.
    func commitAnnotationRestyle(layerID: UUID, strokeWidth: CGFloat? = nil, arrowheadScale: CGFloat? = nil,
                                 cornerRadius: CGFloat? = nil) {
        commitAnnotationRestyle(ids: [layerID], strokeWidth: strokeWidth,
                                arrowheadScale: arrowheadScale, cornerRadius: cornerRadius)
    }

    /// The same drag, over EVERY picked shape: one pull on Thickness reaches
    /// all of them at once. No undo step while the knob is moving.
    ///
    /// Each shape kind remembers the number for itself, so a rectangle and an
    /// arrow both set to 6pt each start their next object at 6pt.
    func previewAnnotationRestyle(ids: [UUID], strokeWidth: CGFloat? = nil,
                                  arrowheadScale: CGFloat? = nil, cornerRadius: CGFloat? = nil) {
        guard var doc = document else { return }
        let targets = annotationRestyleTargets(ids, in: doc)
        guard !targets.isEmpty else { return }
        rememberAnnotationDefaults(targets, in: doc, strokeWidth: strokeWidth,
                                   arrowheadScale: arrowheadScale, cornerRadius: nil)
        discardDragPreview()
        for id in targets {
            doc.updateLayer(id: id) {
                $0 = AnnotationBuilder.restyled($0, strokeWidth: strokeWidth,
                                                arrowheadScale: arrowheadScale,
                                                cornerRadius: cornerRadius)
            }
        }
        submit(doc)
    }

    /// Letting go of that slider: ONE undo step, however many shapes it
    /// reached, plus each kind's remembered default.
    func commitAnnotationRestyle(ids: [UUID], strokeWidth: CGFloat? = nil,
                                 arrowheadScale: CGFloat? = nil, cornerRadius: CGFloat? = nil) {
        guard let doc = document else { return }
        let targets = annotationRestyleTargets(ids, in: doc)
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { document in
            for id in targets {
                document.updateLayer(id: id) {
                    $0 = AnnotationBuilder.restyled($0, strokeWidth: strokeWidth,
                                                    arrowheadScale: arrowheadScale,
                                                    cornerRadius: cornerRadius)
                }
            }
        }
        rememberAnnotationDefaults(targets, in: doc, strokeWidth: strokeWidth,
                                   arrowheadScale: arrowheadScale, cornerRadius: cornerRadius)
        saveAnnotationStyles()
    }

    /// Live drag on the ONE Thickness row: sets the line round every picked
    /// shape without recording an undo step.
    ///
    /// A ring the old Effects Border slider left on a shape is folded onto its
    /// stroke here, color and all, so the box keeps the look it had and ends up
    /// with one ring instead of two. See `OutlineWidth.swift`.
    func previewOutlineWidth(ids: [UUID], _ width: CGFloat) {
        guard var doc = document else { return }
        let targets = annotationRestyleTargets(ids, in: doc)
        guard !targets.isEmpty else { return }
        rememberAnnotationDefaults(targets, in: doc, strokeWidth: width,
                                   arrowheadScale: nil, cornerRadius: nil)
        // This row writes the layer's LOOK as well as its shape, so anything a
        // previous style drag left in the preview would be read back over it.
        stylePreview = nil
        discardDragPreview()
        doc.setOutlineWidth(layerIDs: targets, to: width)
        submit(doc)
    }

    /// Letting go of it: ONE undo step, however many shapes it reached, plus
    /// the thickness the next shape of each kind starts at.
    func commitOutlineWidth(ids: [UUID], _ width: CGFloat) {
        guard let doc = document else { return }
        let targets = annotationRestyleTargets(ids, in: doc)
        guard !targets.isEmpty else { return }
        stylePreview = nil
        discardDragPreview()
        perform { $0.setOutlineWidth(layerIDs: targets, to: width) }
        rememberAnnotationDefaults(targets, in: doc, strokeWidth: width,
                                   arrowheadScale: nil, cornerRadius: nil)
        saveAnnotationStyles()
    }

    /// The picked layers a shape slider may touch: shapes, unlocked.
    private func annotationRestyleTargets(_ ids: [UUID], in doc: PhotonzDocument) -> [UUID] {
        ids.filter { doc.layer(id: $0).map { $0.annotation != nil && !$0.isLocked } == true }
    }

    /// What the next object of each picked kind starts at.
    private func rememberAnnotationDefaults(_ ids: [UUID], in doc: PhotonzDocument,
                                            strokeWidth: CGFloat?, arrowheadScale: CGFloat?,
                                            cornerRadius: CGFloat?) {
        for shape in Set(ids.compactMap { doc.layer(id: $0)?.annotation?.shape }) {
            if let strokeWidth, shape != .highlight {
                annotationStyles.setStrokeWidth(strokeWidth, forShape: shape)
            }
            if let arrowheadScale { annotationStyles.setArrowheadScale(arrowheadScale, forShape: shape) }
            if let cornerRadius { annotationStyles.setCornerRadius(cornerRadius, forShape: shape) }
        }
    }

    /// Inspector color pick on `layerID`: one undo step + persist the shape default.
    func setAnnotationColor(layerID: UUID, _ hex: String) {
        guard let shape = document?.layer(id: layerID)?.annotation?.shape else { return }
        discardDragPreview()
        perform { $0.updateLayer(id: layerID) { $0 = AnnotationBuilder.restyled($0, colorHex: hex) } }
        annotationStyles.setColorHex(hex, forShape: shape)
        saveAnnotationStyles()
        recordRecentColor(hex: hex)
    }

    /// Interior fill for a box shape (nil = no fill). The value becomes the
    /// shape's default, so the next rectangle/ellipse drawn reuses it.
    func setAnnotationFill(layerID: UUID, _ hex: String?) {
        guard let shape = document?.layer(id: layerID)?.annotation?.shape else { return }
        discardDragPreview()
        perform { $0.updateLayer(id: layerID) { $0 = AnnotationBuilder.restyled($0, fillColorHex: .some(hex)) } }
        annotationStyles.setFillColorHex(hex, forShape: shape)
        saveAnnotationStyles()
        if let hex { recordRecentColor(hex: hex) }
    }

    // MARK: - Zoom-callout inspector

    /// The picked zoom-callout layer, whatever tool is in hand.
    ///
    /// It used to insist on the select tool, back when these controls lived in
    /// the tool bar's style popover and had to keep out of the way of the tool
    /// you were holding. They are the Zoom Callout section in the dock now
    /// (`CalloutInspector`), which is about the thing you picked rather than
    /// the thing in your hand, so the section stays put the way Color and
    /// Effects do.
    var selectedZoomCalloutLayer: Layer? {
        guard let id = selectedLayerID,
              let layer = document?.layer(id: id), layer.zoomCallout != nil else { return nil }
        return layer
    }

    /// The selected callout's magnification, preview-aware so the inspector
    /// slider doesn't snap back mid-drag (previews live in the frame, and
    /// frame ÷ source is the magnification by construction).
    var selectedCalloutMagnification: CGFloat? {
        guard let layer = selectedZoomCalloutLayer, let callout = layer.zoomCallout,
              callout.sourceRect.width > 0 else { return nil }
        return (selectedLayerFrame?.width ?? layer.frame.width) / callout.sourceRect.width
    }

    /// Slider movement: the box grows around its center via the regular
    /// frame-preview path (rendered live, no history).
    func previewCalloutMagnification(_ magnification: CGFloat) {
        guard let layer = selectedZoomCalloutLayer else { return }
        previewLayerFrame(id: layer.id, frame: ZoomCalloutBuilder.frame(for: magnification, of: layer))
    }

    /// Slider release: one undo step from the pre-drag frame to the last
    /// previewed one (a no-move release is a History no-op).
    func commitCalloutMagnification() {
        guard let layer = selectedZoomCalloutLayer, let frame = selectedLayerFrame else { return }
        commitLayerFrame(id: layer.id, frame: frame)
    }

    func setCalloutShape(_ shape: ZoomCalloutShape) {
        guard let layer = selectedZoomCalloutLayer, var callout = layer.zoomCallout,
              callout.shape != shape else { return }
        callout.shape = shape
        perform { $0.updateLayer(id: layer.id) { $0.content = .zoomCallout(callout) } }
        // Rounding one callout arms the tool, the way painting a shape arms the
        // tool that draws it: the next callout comes out the shape you just
        // chose rather than back to a rectangle.
        rememberCalloutShape(shape)
    }

    // A callout's ring has no setter of its own. It IS the layer's border, so
    // its colour goes through `setSelectionColor(slot: .border)` with every
    // other colour and its width through the Effects Border slider with every
    // other layer's — one control each, and the same one wherever you got to
    // it from.

    static let annotationStylesKey = "annotationStyles"

    static func loadAnnotationStyles() -> AnnotationStyles {
        guard let data = UserDefaults.standard.data(forKey: annotationStylesKey),
              let styles = try? JSONDecoder().decode(AnnotationStyles.self, from: data) else {
            return AnnotationStyles()
        }
        return styles
    }

    func saveAnnotationStyles() {
        if let data = try? JSONEncoder().encode(annotationStyles) {
            UserDefaults.standard.set(data, forKey: Self.annotationStylesKey)
        }
    }
}
