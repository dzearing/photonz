import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

// The measurements list and its inspector: showing, hiding, copying and
// restyling what has been measured.
//
// Split out of EditorState.swift; nothing here changed on the way over.
extension EditorState {
    // MARK: - Measurements panel (§6-7, `next-measure-panel`)

    /// The Measurements panel's rows: the document's measure layers, top-most
    /// first. A filtered view of the layer stack — never separate state, so
    /// selection, visibility, and delete are the layer operations.
    var measurePanelLayers: [Layer] {
        guard let document else { return [] }
        return MeasureSpecList.measureLayers(in: document)
    }

    /// How many measurements the document holds (the toolbar pill's number).
    var measurementCount: Int { measurePanelLayers.count }

    /// Panel menu Show all / Hide all: every measure layer's eye, ONE undo
    /// step. Layers already in the requested state stay untouched, so an
    /// all-visible "Show all" records nothing.
    func setAllMeasurementsVisible(_ visible: Bool) {
        discardDragPreview()
        let ids = measurePanelLayers.filter { $0.isVisible != visible }.map(\.id)
        guard !ids.isEmpty else { return }
        perform { doc in
            for id in ids { doc.updateLayer(id: id) { $0.isVisible = visible } }
        }
    }

    /// Panel menu Clear measurements: every measure layer deleted in one undo
    /// step. Undo is the safety net — no confirmation dialog (the mock's rule).
    func clearAllMeasurements() {
        let ids = measurePanelLayers.map(\.id)
        guard !ids.isEmpty else { return }
        deleteLayers(ids: ids)
    }

    /// The toolbar count pill's click (§6): reveal the docked inspector and
    /// un-collapse the Measurements group so the rows are on screen.
    func revealMeasurementsPanel() {
        setInspectorVisible(true)
        let key = "inspector.collapsed"
        let collapsed = UserDefaults.standard.string(forKey: key) ?? ""
        var set = Set(collapsed.split(separator: ",").map(String.init))
        if set.remove(InspectorSectionID.measurements.rawValue) != nil {
            UserDefaults.standard.set(set.sorted().joined(separator: ","), forKey: key)
        }
    }

    /// The spec list's header name: the document's own name (no extension),
    /// never the decorated window title with its release tag.
    var specListName: String {
        (documentURL ?? openedFileURL)?.deletingPathExtension().lastPathComponent ?? untitledName
    }

    /// How many measurements a spec list would carry right now: the visible
    /// ones. Copy as Spec List is offered only while this is above zero, so
    /// hiding every row disables it rather than copying a bare header.
    var visibleMeasurementCount: Int {
        guard let document else { return 0 }
        return CompositeCopy.visibleMeasurementCount(in: document)
    }

    /// Copy as spec list (§7): the pinned plain-text form of the visible
    /// measurements goes on the clipboard. The panel menu and the menu bar's
    /// Measure menu both land here. With every row hidden there is nothing to
    /// list, so the key does nothing and the menus show it disabled.
    func copyMeasureSpecList() {
        guard let document else { return }
        let listed = CompositeCopy.visibleMeasurementCount(in: document)
        guard listed > 0 else { return }
        copyText(MeasureSpecList.render(document: document, name: specListName))
        showCopyConfirmation(.specList(measurements: listed))
    }

    /// The selected measurements, panel order: the primary selection when it
    /// is a measure layer, or the measure members of a marquee multi-selection.
    var selectedMeasureLayerIDs: [UUID] {
        var ids = multiSelectedLayerIDs
        if let id = selectedLayerID { ids.insert(id) }
        return measurePanelLayers.map(\.id).filter { ids.contains($0) }
    }

    /// Copy Measurement: the selected measurements' spec lines (no header)
    /// go on the clipboard as text, so one row pastes into a thread as one
    /// line. Nothing selected, nothing copied.
    func copySelectedMeasurements() {
        guard let document else { return }
        let ids = Set(selectedMeasureLayerIDs)
        guard !ids.isEmpty else { return }
        copyText(MeasureSpecList.render(document: document, ids: ids))
        showCopyConfirmation(.measurements(count: ids.count))
    }

    /// A row's context menu Copy Measurement: that one row's line, whether or
    /// not it is selected, without disturbing the selection.
    func copyMeasurement(id: UUID) {
        guard let document, let layer = document.layer(id: id),
              let line = MeasureSpecList.specLine(for: layer, in: document) else { return }
        copyText(line)
        showCopyConfirmation(.measurements(count: 1))
    }

    private func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// The role memory a style edit files under: the SELECTED measurement's
    /// role (§5's absorb rule), or the last-used role when no measure is
    /// selected and the edit only retunes the tool's defaults.
    private var editedMeasureRole: MeasureRole {
        selectedMeasureLayer?.measure?.role ?? measureStyles.role
    }

    /// The Role control (§5, `next-measure-roles`): switching the selected
    /// measurement's role applies that role's remembered ink in ONE undo step,
    /// and the role becomes what the next caliper starts as.
    func setMeasureRole(_ role: MeasureRole) {
        updateMeasureStyles { $0.role = role }
        let ink = measureStyles.colors(for: role)
        applyMeasureRestyle {
            MeasureBuilder.restyled($0, strokeColorHex: ink.strokeColorHex,
                                    chipColorHex: ink.chipColorHex,
                                    chipOpacity: ink.chipOpacity,
                                    textColorHex: ink.textColorHex, role: role)
        }
    }

    /// The unit shown by new measures and the selected one. Each setter restyles
    /// the selected measure (re-padding its frame via the builder) in one undo step.
    func setMeasureUnit(_ unit: MeasureUnit) {
        updateMeasureStyles { $0.unit = unit }
        applyMeasureRestyle { MeasureBuilder.restyled($0, unit: unit) }
    }

    /// Sizer line thickness in logical pixels.
    func setMeasureThickness(_ width: CGFloat) {
        updateMeasureStyles { $0.strokeWidth = width }
        applyMeasureRestyle { MeasureBuilder.restyled($0, strokeWidth: width) }
    }

    /// Live label-size slider drag: re-render the baked strokes/gap for the new
    /// size and publish the preview so the glass pill resizes too (no history).
    func previewMeasureLabelScale(_ scale: CGFloat) {
        updateMeasureStyles { $0.labelSizePx = scale * MeasureContent.labelFontSize }
        guard let layer = selectedMeasureLayer, var doc = document else { return }
        measureLabelPreview = (layer.id, scale)
        doc.updateLayer(id: layer.id) { $0 = MeasureBuilder.restyled($0, labelScale: scale) }
        if let frame = doc.canvasLayer(id: layer.id)?.frame { previewMoves = [layer.id: frame] }
        submit(doc)
    }

    /// Slider release: commit the label size in one undo step.
    func commitMeasureLabelScale(_ scale: CGFloat) {
        measureLabelPreview = nil
        previewMoves = [:]
        updateMeasureStyles { $0.labelSizePx = scale * MeasureContent.labelFontSize }
        // A much bigger readout can no longer fit where the small one did, so
        // it gets to pick again (UX-PATTERNS D14).
        let canvas = document?.canvasSize
        let others = placedReadoutRects(excluding: selectedMeasureLayer?.id)
        applyMeasureRestyle {
            MeasureBuilder.replanningLabel(MeasureBuilder.restyled($0, labelScale: scale),
                                           canvas: canvas, avoiding: others)
        }
    }

    /// The caliper's ink: legs, head line, and the chip's border. Absorbs into
    /// the edited measurement's ROLE memory (§5), so retuning a Spacing caliper
    /// never repaints what the next Size caliper starts as.
    func setMeasureStrokeColor(_ hex: String, commit: Bool) {
        let role = editedMeasureRole
        updateMeasureStyles { $0.updateColors(for: role) { $0.strokeColorHex = hex } }
        applyMeasureRestyle { MeasureBuilder.restyled($0, strokeColorHex: hex) }
        if commit { recordRecentColor(hex: hex) }
    }

    /// The label chip's fill — color and alpha together, because the inspector
    /// picks both from one swatch (its opacity slider IS the chip's alpha).
    func setMeasureChipColor(_ hex: String, opacity: CGFloat, commit: Bool) {
        let role = editedMeasureRole
        updateMeasureStyles {
            $0.updateColors(for: role) { $0.chipColorHex = hex; $0.chipOpacity = opacity }
        }
        applyMeasureRestyle {
            MeasureBuilder.restyled($0, chipColorHex: hex, chipOpacity: opacity)
        }
        if commit { recordRecentColor(hex: hex) }
    }

    /// The numeric readout's color.
    func setMeasureTextColor(_ hex: String, commit: Bool) {
        let role = editedMeasureRole
        updateMeasureStyles { $0.updateColors(for: role) { $0.textColorHex = hex } }
        applyMeasureRestyle { MeasureBuilder.restyled($0, textColorHex: hex) }
        if commit { recordRecentColor(hex: hex) }
    }

    /// Mutate the measure tool's remembered style and persist it — every measure
    /// setter goes through here so "it stays how I left it" needs no bookkeeping
    /// at the call sites.
    func updateMeasureStyles(_ mutate: (inout MeasureStyles) -> Void) {
        mutate(&measureStyles)
        if let data = try? JSONEncoder().encode(measureStyles) {
            UserDefaults.standard.set(data, forKey: Self.measureStylesKey)
        }
    }

    static let measureStylesKey = "measureStyles"

    static func loadMeasureStyles() -> MeasureStyles {
        guard let data = UserDefaults.standard.data(forKey: measureStylesKey),
              let styles = try? JSONDecoder().decode(MeasureStyles.self, from: data) else {
            return MeasureStyles()
        }
        return styles
    }

    static let calloutStylesKey = "calloutStyles"

    static func loadCalloutStyles() -> CalloutStyles {
        guard let data = UserDefaults.standard.data(forKey: calloutStylesKey),
              let styles = try? JSONDecoder().decode(CalloutStyles.self, from: data) else {
            return CalloutStyles()
        }
        return styles
    }

    /// What the NEXT callout is drawn as. The tool section reads and writes
    /// this; with the flag off it is always a rectangle, which is what Current
    /// has always drawn.
    var calloutToolShape: ZoomCalloutShape {
        get { Experiments.shared.calloutShapeEnabled ? calloutStyles.shape : .rectangle }
        set { rememberCalloutShape(newValue) }
    }

    /// Absorbs a shape choice into the tool's memory and persists it.
    func rememberCalloutShape(_ shape: ZoomCalloutShape) {
        guard Experiments.shared.calloutShapeEnabled, calloutStyles.shape != shape else { return }
        calloutStyles.shape = shape
        saveCalloutStyles()
    }

    /// How much the NEXT callout magnifies what it points at. The tool section
    /// and the capsule read and write this; with the flag off it is always two,
    /// which is what every callout has always been drawn at.
    ///
    /// Deliberately one-way: this is written only from the tool's own control,
    /// never from a placed callout's slider or a pull on its corners, so the
    /// tool cannot quietly pick up whatever the last resize left behind.
    var calloutToolMagnification: CGFloat {
        get {
            Experiments.shared.calloutMagnificationEnabled
                ? calloutStyles.magnification : ZoomCalloutBuilder.defaultMagnification
        }
        set { rememberCalloutMagnification(newValue) }
    }

    /// Absorbs a magnification choice into the tool's memory and persists it.
    func rememberCalloutMagnification(_ magnification: CGFloat) {
        let clamped = ZoomCalloutBuilder.clampedMagnification(magnification)
        guard Experiments.shared.calloutMagnificationEnabled,
              calloutStyles.magnification != clamped else { return }
        calloutStyles.magnification = clamped
        saveCalloutStyles()
    }

    /// One writer for the callout tool's memory, so "it stays how I left it"
    /// needs no bookkeeping at the call sites.
    private func saveCalloutStyles() {
        if let data = try? JSONEncoder().encode(calloutStyles) {
            UserDefaults.standard.set(data, forKey: Self.calloutStylesKey)
        }
    }

    /// The document's pixels-per-point scale, driving the points readout. A Retina
    /// screenshot is 2×. Changing it re-renders every measure's label.
    func setDocumentPixelScale(_ scale: CGFloat) {
        guard let document, document.pixelScale != scale else { return }
        perform { $0.pixelScale = scale }
    }

    /// Live handle drag of a placed caliper (no history) — re-renders so the
    /// measured value updates as a foot or the head moves.
    func previewMeasureEndpoints(id: UUID, start: CGPoint, end: CGPoint, headOffset: CGFloat,
                                 readout: MeasureReadoutPlacement? = nil) {
        let start = parentPoint(start, of: id)
        let end = parentPoint(end, of: id)
        guard var doc = document, doc.layer(id: id)?.measure != nil else { return }
        doc.updateLayer(id: id) {
            $0 = MeasureBuilder.updating($0, start: start, end: end, headOffset: headOffset,
                                         readout: readout)
        }
        if let frame = doc.canvasLayer(id: id)?.frame { previewMoves = [id: frame] }
        submit(doc)
    }

    /// Mouse-up on a caliper handle: one undoable step. Committing the original
    /// values is a History no-op (the Esc-cancel path).
    func commitMeasureEndpoints(id: UUID, start: CGPoint, end: CGPoint, headOffset: CGFloat,
                                readout: MeasureReadoutPlacement? = nil) {
        let start = parentPoint(start, of: id)
        let end = parentPoint(end, of: id)
        previewMoves = [:]
        let others = placedReadoutRects(excluding: id)
        let canvas = document?.canvasSize
        // The feet may have moved onto different elements, so they are read
        // again; an alignment guide's subjects are its own checked runs.
        let subjects: [CGRect] = {
            guard let m = document?.layer(id: id)?.measure, m.alignment == nil else { return [] }
            return caliperSubjects(from: start, to: end, mode: m.mode)
        }()
        perform {
            $0.updateLayer(id: id) {
                $0 = MeasureBuilder.updating($0, start: start, end: end, headOffset: headOffset,
                                             readout: readout)
                // The measurement moved, so where its readout can sit changed.
                $0 = MeasureBuilder.replanningLabel($0, canvas: canvas, avoiding: others,
                                                    describing: subjects)
            }
        }
    }

    var documentPixelScale: CGFloat { document?.pixelScale ?? 1 }

    /// Detected UI edges for snapping, but ONLY while a tool that snaps to
    /// them is active (measure, rect/ellipse region select, any drawing tool)
    /// or a layer whose handles snap is selected — so the edge sweep never
    /// runs for documents that aren't being redlined. Analysis takes ~seconds
    /// on a Retina screenshot, so it runs OFF the main thread: the first
    /// access kicks it off and returns `.empty` (snapping is a no-op until it
    /// lands), then the observable `readyEdgeMaps` update re-feeds the canvas
    /// the real map. Picking the arrow tool is therefore what starts the sweep
    /// for an arrow, well before the first drag.
    var snappingEdgeMap: EdgeMap {
        let selected = selectedLayerID.flatMap { document?.layer(id: $0) }
        // A caliper handle and an arrow endpoint both magnetize to the picture.
        let selectionSnaps = selected?.measure != nil || selected?.hasEndpointHandles == true
        let toolSnaps = activeTool == .measure
            || activeTool == .rectSelect || activeTool == .ellipseSelect
            || activeTool.createsAnnotationByDrag
        guard toolSnaps || selectionSnaps,
              let ref = document?.layers.compactMap(\.imageRef).first else { return .empty }
        if let ready = readyEdgeMaps[ref.id] { return ready.edges }
        analyzeEdgeMap(for: ref)
        return .empty
    }

    /// The same analysis's brightness field, which element detection walks to
    /// find how far a boundary runs (`ElementBounds`). Empty until the sweep
    /// lands, exactly like `snappingEdgeMap`, so Size mode simply draws nothing
    /// for the first moment after a screenshot opens.
    var measureLumaField: LumaField {
        guard let ref = document?.layers.compactMap(\.imageRef).first,
              let ready = readyEdgeMaps[ref.id] else { return .empty }
        return ready.luma
    }

    /// Runs the edge analysis for `ref` in the background, once.
    private func analyzeEdgeMap(for ref: ImageRef) {
        guard !edgeMapAnalysisPending.contains(ref.id) else { return }
        edgeMapAnalysisPending.insert(ref.id)
        let cache = edgeMapCache
        let store = store
        Task.detached(priority: .userInitiated) { [weak self] in
            let analysis = cache.analysis(for: ref, store: store)
            await MainActor.run {
                guard let self else { return }
                self.readyEdgeMaps[ref.id] = analysis
                self.edgeMapAnalysisPending.remove(ref.id)
            }
        }
    }

    private func applyMeasureRestyle(_ restyle: (Layer) -> Layer) {
        guard let layer = selectedMeasureLayer else { return }
        let updated = restyle(layer)
        perform { $0.updateLayer(id: layer.id) { $0 = updated } }
    }
}
