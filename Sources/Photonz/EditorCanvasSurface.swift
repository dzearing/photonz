import AppKit
import PhotonzCore
import SwiftUI

/// The picture itself, and nothing else around it.
///
/// This is a view of its own rather than a stretch of `EditorView.body`, and
/// the reason is measured. The canvas reads the selection — `selectedLayerID`,
/// `selectedLayerFrame`, `multiSelectedLayerIDs`, `isCanvasSelected`, the group
/// context — and while those reads sat inside `EditorView.body`, every one of
/// them made picking a layer re-run the WHOLE editor body: canvas, tool bar,
/// zoom bar, side capsules, dock. SwiftUI then re-measured every stack in the
/// window, so a click that changes an outline cost 53ms of main thread work on
/// a TWO ROW document, three frames at sixty hertz
/// (`layer-pick-latency-walk`, 2026-09-14).
///
/// Reading them in here instead means a pick re-runs this one body and hands
/// the new selection to the same NSView, which is all the canvas ever wanted.
/// Nothing else about the window is invalidated.
///
/// Keep it that way: anything added here must be something the PICTURE needs.
/// Chrome that sits over the canvas (the notice chip, the crop bar, the icon
/// previews, the measure legend) stays in `EditorView`, where it is an overlay
/// on this view.
struct EditorCanvasSurface: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        CanvasView(image: editorState.renderedImage,
                   crispTile: editorState.crispTile,
                   crispTileViewport: editorState.crispTileViewport,
                   viewport: editorState.viewport,
                   document: editorState.document,
                   selection: editorState.selection,
                   selectionTargetsPixels: editorState.selectionTargetsPixels,
                   cropRect: editorState.cropRect,
                   cropAspect: editorState.cropAspect,
                   cropBounds: editorState.cropBounds,
                   backgroundFillHex: editorState.backgroundFillHex,
                   selectedLayerID: editorState.selectedLayerID,
                   selectedLayerFrame: editorState.selectedLayerFrame,
                   groupContext: editorState.groupContextID,
                   multiSelectedLayerIDs: editorState.multiSelectedLayerIDs,
                   dragPreview: editorState.dragPreview,
                   tool: editorState.activeTool,
                   captionCloseRequest: editorState.captionCloseRequest,
                   typeInLayer: editorState.typeInLayer,
                   annotationContent: editorState.activeAnnotationContent,
                   calloutShape: editorState.calloutToolShape,
                   calloutMagnification: editorState.calloutToolMagnification,
                   lensMagnifies: editorState.lensToolMagnifies,
                   annotationStyle: editorState.activeAnnotationStyle,
                   textContent: editorState.activeTextContent,
                   measureContent: editorState.measureStyleForActiveMode,
                   measureToolMode: editorState.measureToolMode,
                   measureCandidateLevel: editorState.measureCandidateLevel,
                   measureSnapsToCenters: editorState.measureSnapsToCenters
                       && Experiments.shared.measureCenterSnapEnabled,
                   edgeMap: editorState.snappingEdgeMap,
                   lumaField: editorState.measureLumaField,
                   onViewSizeChange: { editorState.canvasViewSizeChanged($0) },
                   onViewportChange: { editorState.setViewport($0) },
                   onSelectionChange: {
                       editorState.setSelection($0, captureLayers: $1, inside: $2, run: $3)
                   },
                   onWandAt: { editorState.wandSelect(at: $0, mode: $1) },
                   onDeleteRegion: { editorState.deleteRegion() },
                   onRegionMoveBegin: { editorState.beginRegionMove(copy: $0) },
                   onRegionMoveCommit: { editorState.commitRegionMove(delta: $0) },
                   onRegionMoveCancel: { editorState.cancelRegionMove() },
                   onCropRectChange: { editorState.setCropRect($0) },
                   onCropCommit: { editorState.commitCrop() },
                   onSelectLayer: { editorState.selectLayer($0) },
                   onSelectLayerInGroup: { editorState.selectLayer($0, inGroup: $1) },
                   onReadTheWordsThenType: { editorState.readTheWordsThenType(id: $0) },
                   onExtendSelection: { editorState.extendSelection(toLayer: $0) },
                   onAddSweptLayers: { editorState.addSweptLayersToSelection(in: $0, inside: $1) },
                   onRenameLayer: { editorState.renameLayer(id: $0, to: $1) },
                   onRenameComponent: { editorState.renameComponent(componentID: $0, to: $1) },
                   onRenameComponentVersion: {
                       editorState.renameComponentVersion(componentID: $0, version: $1, to: $2)
                   },
                   onExitGroup: { editorState.exitGroupContext() },
                   canvasMenu: { hit, context in
                       editorState.aimCanvasMenu(at: hit, inside: context)
                       return editorState.canvasMenuRows
                   },
                   onClickedNothing: { editorState.clearLibraryPick() },
                   onPointerIconFrameChange: { editorState.pointerIconFrameID = $0 },
                   onDragBegin: { editorState.beginLayerDrag(id: $0) },
                   onFramePreview: { editorState.previewCanvasFrame(id: $0, frame: $1) },
                   onFrameCommit: { editorState.commitCanvasFrame(id: $0, frame: $1) },
                   onDropCommit: { editorState.commitCanvasDrop(id: $0, frame: $1) },
                   onMoveSelectionPreview: { editorState.previewCanvasOrigins($0) },
                   onMoveSelectionCommit: { editorState.commitCanvasOrigins($0, joiningScreens: $1) },
                   onCopyDragPreview: { editorState.previewCopyDrag($0) },
                   onCopyDragCommit: { editorState.commitCopyDrag($0) },
                   onCopyDragCancel: { editorState.cancelCopyDrag() },
                   onTransformPreview: { editorState.previewLayerTransform(id: $0, transform: $1) },
                   onTransformCommit: { editorState.commitLayerTransform(id: $0, transform: $1) },
                   onAnnotationCommit: { editorState.addAnnotation(from: $0, to: $1) },
                   onAnnotationEndpointsCommit: { editorState.commitAnnotationEndpoints(id: $0, start: $1, end: $2) },
                   onZoomCalloutCommit: { editorState.addZoomCallout(from: $0, to: $1) },
                   onFrameCreate: { editorState.addFrame(from: $0, to: $1) },
                   onLensCreate: { editorState.addLensDrag(from: $0, to: $1) },
                   penPaint: editorState.armedPenPaint,
                   penStrokeWidth: editorState.armedPenStrokeWidth,
                   armedStrokeWidthIsChosen: editorState.armedStrokeWidthIsChosen,
                   onPathCommit: { editorState.addPath($0) },
                   onPenHintChange: { editorState.penHint = $0 },
                   onPathPreview: { editorState.previewPath($0, $1) },
                   onPathEditCommit: { editorState.commitPath($0, $1) },
                   onPathEditHintChange: { editorState.pathEditHint = $0 },
                   motionPivot: editorState.motionPivotHandle,
                   onMotionPivotBegin: { editorState.beginMotionPivotDrag() },
                   onMotionPivotMove: { editorState.previewMotionPivot(at: $0) },
                   onMotionPivotCommit: { editorState.commitMotionPivot() },
                   onMotionPivotCancel: { editorState.cancelMotionPivot() },
                   onMotionPlayToggle: { editorState.toggleMotionPreview() },
                   canPlayMotion: editorState.canPlayMotion,
                   onDocumentPlayToggle: { editorState.toggleDocumentPlayback() },
                   onDocumentStepFrames: { editorState.stepDocument(byFrames: $0) },
                   documentHasTime: editorState.documentHasTime,
                   documentTimeMS: editorState.documentTimeMS,
                   onMeasureCommit: { editorState.addMeasure(from: $0, to: $1, mode: $2, headOffset: $3) },
                   onMeasureEndpointPreview: { editorState.previewMeasureEndpoints(id: $0, start: $1, end: $2, headOffset: $3, readout: $4) },
                   onMeasureEndpointCommit: { editorState.commitMeasureEndpoints(id: $0, start: $1, end: $2, headOffset: $3, readout: $4) },
                   onMeasureEndpointCancel: { editorState.cancelMeasureEndpointDrag() },
                   onCornerRadiiPreview: { editorState.previewCornerRadii(ids: [$0], $1) },
                   onCornerRadiiCommit: { editorState.commitCornerRadii(ids: [$0], $1) },
                   onCaptionPlacePreview: { editorState.previewCaptionPlacement(id: $0, center: $1) },
                   onCaptionPlaceCommit: { editorState.commitCaptionPlacement(id: $0, center: $1) },
                   onCaptionPlaceCancel: { editorState.cancelCaptionPlacement() },
                   onAlignmentCommit: { editorState.addAlignmentCheck(axis: $0, position: $1, span: $2) },
                   onElementSizeCommit: { editorState.addElementSize($0, neighbors: $1) },
                   onGapCommit: { editorState.addGapMeasure($0) },
                   onCandidateLevelChange: { editorState.measureCandidateLevel = $0 },
                   onToolChange: { editorState.setTool($0) },
                   onTextEditBegin: { editorState.beginTextEdit(layerID: $0) },
                   onWordingRefused: { editorState.refuseWordingEdit($0) },
                   onTextCommit: { editorState.commitTextEdit(layerID: $0, origin: $1, string: $2, maxWidth: $3) },
                   onTextCancel: { editorState.cancelTextEdit() },
                   onCaptionEditBegin: { editorState.beginCaptionEdit(layerID: $0) },
                   onCaptionCommit: {
                       editorState.commitCaptionEdit(layerID: $0, string: $1,
                                                     placement: $2, keepTool: $3)
                   },
                   onCaptionCancel: { editorState.cancelCaptionEdit() },
                   onDeleteLayer: { editorState.deleteLayer(id: $0) },
                   onDeleteLayers: { editorState.deleteLayers(ids: $0) },
                   onDropImageURL: { editorState.addImageLayerOrOpen(at: $0, droppedAt: $1) },
                   onDropMediaURL: { editorState.dropMedia(at: $0, droppedAt: $1) },
                   mediaDropAnswer: { editorState.mediaDropAnswer(for: $0) },
                   onDropComponent: { componentID, version, point in
                       editorState.placeComponent(componentID: componentID, at: point,
                                                  version: version)
                   },
                   onComponentDragMoved: { componentID, version, point in
                       editorState.holdRoomForComponentDrag(componentID: componentID,
                                                            version: version, at: point)
                   },
                   onComponentDragEnded: { editorState.releaseRoomForComponentDrag() },
                   arrivingComponentDrawing: { componentID in
                       editorState.sharedComponent(entryID: componentID.uuidString)?
                           .drawings.first
                   },
                   onDropTextStyle: { styleID, layerIDs in
                       editorState.dropTextStyle(styleID: styleID, onLayers: layerIDs)
                   },
                   onDropImageURLIntoCollage: { url, collageID, slot in
                       editorState.dropImage(at: url, intoCollage: collageID, slot: slot)
                   },
                   onAbsorbLayerIntoCollage: { layerID, collageID, slot in
                       editorState.absorbLayer(id: layerID, intoCollage: collageID, slot: slot)
                   },
                   onSwapCollageSlots: { collageID, from, to in
                       editorState.swapCollageSlots(collageID: collageID, from, to)
                   },
                   isCanvasSelected: editorState.isCanvasSelected,
                   canvasGrid: editorState.drawnCanvasGrid,
                   iconKeylines: editorState.iconKeylinesShowing,
                   canvasGridOrigin: editorState.canvasGridOrigin,
                   canvasGuides: editorState.canvasGuides,
                   gridAdjust: editorState.gridAdjustment?.origin,
                   selectedGuideID: editorState.selectedGuideID,
                   onGridOriginChange: { editorState.moveGridOrigin(to: $0) },
                   onGridAdjustCommit: { editorState.commitGridAdjustment() },
                   onGridAdjustCancel: { editorState.cancelGridAdjustment() },
                   onGuidePin: { editorState.pinGuide($0) },
                   onGuideSelect: { editorState.selectGuide($0) },
                   onGuideMove: { editorState.moveSelectedGuide(to: $0) },
                   onGuideDelete: { editorState.deleteSelectedGuide() },
                   onCanvasResize: { size, anchor in
                       editorState.setCanvasSize(to: size, anchor: anchor)
                   },
                   onFillAt: { point, hit, useBackground in
                       editorState.fillLayer(at: point, hit: hit, useBackground: useBackground)
                   },
                   onFillSelected: { editorState.fillSelectedLayer(useBackground: $0) },
                   onClearBackground: { editorState.clearBackgroundLayer() },
                   onWindowChange: { editorState.canvasDidMoveToWindow($0) })
            // The exact position and size numbers, hung off the selection
            // itself (`ExactPlacement`). Here rather than on the panel because
            // the anchor is worked out in the canvas view's own coordinates,
            // and this view IS the canvas view.
            .exactPlacementPopover(editorState)

    }
}
