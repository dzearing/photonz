// Probe-only: which of the editor's properties a step actually wrote.
//
// A view's body re-runs when ANY property it read is written, and @Observable
// does not say which one. This says which one: it arms one tracker per
// property the editor's own body reads, and a walk step reports the names that
// fired. Written for `layer-pick-latency-walk`, where one click was re-running
// the whole editor body and nobody could say why.
#if PHOTONZ_PLAYTEST
import Foundation
import Observation

@MainActor
enum EditorReadWatch {
    private(set) static var fired: [String] = []
    private static var armed = false

    static func reset() { fired.removeAll() }

    static func arm(_ e: EditorState) {
        guard !armed else { return }
        armed = true
        for (name, read) in probes(e) { watch(name, read) }
    }

    private static func watch(_ name: String, _ read: @escaping @MainActor () -> Void) {
        withObservationTracking {
            read()
        } onChange: {
            Task { @MainActor in
                if !fired.contains(name) { fired.append(name) }
                watch(name, read)
            }
        }
    }

    static var report: String {
        fired.isEmpty ? "nothing the editor body reads changed" : "wrote: " + fired.joined(separator: ", ")
    }

    private static func probes(_ e: EditorState) -> [(String, @MainActor () -> Void)] { [
        ("activeTool", { _ = e.activeTool }),
        ("activeToolFillPaint", { _ = e.activeToolFillPaint }),
        ("annotationStyles", { _ = e.annotationStyles }),
        ("armedTextStyle", { _ = e.armedTextStyle }),
        ("backgroundFillHex", { _ = e.backgroundFillHex }),
        ("canRearmToolColorStyle", { _ = e.canRearmToolColorStyle }),
        ("canvasGrid", { _ = e.canvasGrid }),
        ("colorWellBinding", { _ = e.colorWellBinding }),
        ("copyConfirmation", { _ = e.copyConfirmation }),
        ("cropAspect", { _ = e.cropAspect }),
        ("cropRect", { _ = e.cropRect }),
        ("displayZoom", { _ = e.displayZoom }),
        ("document", { _ = e.document }),
        ("drawnCanvasGrid", { _ = e.drawnCanvasGrid }),
        ("foregroundFillHex", { _ = e.foregroundFillHex }),
        ("gridAdjustment", { _ = e.gridAdjustment }),
        ("holdCanvasNotice", { _ = e.holdCanvasNotice }),
        ("iconPreviewFrameID", { _ = e.iconPreviewFrameID }),
        ("iconPreviewTiles", { _ = e.iconPreviewTiles }),
        ("isAdjustingGrid", { _ = e.isAdjustingGrid }),
        ("isBlankCanvasDialogPresented", { _ = e.isBlankCanvasDialogPresented }),
        ("isCanvasSizeDialogPresented", { _ = e.isCanvasSizeDialogPresented }),
        ("isExportDialogPresented", { _ = e.isExportDialogPresented }),
        ("isGridSettingsPresented", { _ = e.isGridSettingsPresented }),
        ("isImporterPresented", { _ = e.isImporterPresented }),
        ("isInspectorAutoHidden", { _ = e.isInspectorAutoHidden }),
        ("isInspectorShown", { _ = e.isInspectorShown }),
        ("isLayersPanelVisible", { _ = e.isLayersPanelVisible }),
        ("isNewFrameDialogPresented", { _ = e.isNewFrameDialogPresented }),
        ("isResizeDialogPresented", { _ = e.isResizeDialogPresented }),
        ("lastTool", { _ = e.lastTool }),
        ("letGoNotice", { _ = e.letGoNotice }),
        ("measureHintText", { _ = e.measureHintText }),
        ("measureHintTitle", { _ = e.measureHintTitle }),
        ("measureLegendAnchor", { _ = e.measureLegendAnchor }),
        ("measureLegendEntries", { _ = e.measureLegendEntries }),
        ("measureLegendTopInset", { _ = e.measureLegendTopInset }),
        ("measureModeHint", { _ = e.measureModeHint }),
        ("measureToolMode", { _ = e.measureToolMode }),
        ("paintBorderTurningItOn", { _ = e.paintBorderTurningItOn }),
        ("pathEditHintText", { _ = e.pathEditHintText }),
        ("penHintText", { _ = e.penHintText }),
        ("selectedAnnotationLayer", { _ = e.selectedAnnotationLayer }),
        ("selectedTextLayer", { _ = e.selectedTextLayer }),
        ("showsMeasureHint", { _ = e.showsMeasureHint }),
        ("showsPathEditHint", { _ = e.showsPathEditHint }),
        ("showsPenHint", { _ = e.showsPenHint }),
        ("textStyles", { _ = e.textStyles }),
        ("toolBarWidth", { _ = e.toolBarWidth }),
        ("toolColorStyle", { _ = e.toolColorStyle }),
        ("toolSavedColor", { _ = e.toolSavedColor }),
        ("toolSettingsSize", { _ = e.toolSettingsSize }),
        ("toolStyleWelcome", { _ = e.toolStyleWelcome }),
        ("useToolColorStyle", { _ = e.useToolColorStyle }),
        ("wandTolerance", { _ = e.wandTolerance }),
    ] }
}
#endif
