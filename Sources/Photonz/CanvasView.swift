import AppKit
import PhotonzCore
import PhotonzRender
import SwiftUI

/// Pre-rendered pieces for a cheap drag preview: the canvas composites
/// `sprite` over `underlay` in Core Animation, so per-mouse-move cost is pure
/// layer geometry — no Core Image.
struct DragPreview {
    let layerID: UUID
    /// The document composited with the dragged layer hidden.
    let underlay: CGImage
    /// The dragged layer rendered alone, padded by `padding` on every side.
    let sprite: CGImage
    /// Document points of shadow/blur padding baked into the sprite.
    let padding: CGFloat
    let blendMode: PhotonzCore.BlendMode
}

/// The document canvas: a layer-backed NSView that draws the rendered composite
/// positioned by `Viewport`. All geometry decisions live in `Viewport`
/// (PhotonzCore, tested); this view only mirrors them into Core Animation.
struct CanvasView: NSViewRepresentable {
    let image: CGImage?
    /// What you can see, redrawn at the zoom you are seeing it through, so
    /// placed words stay as sharp as the ones being typed. Nil at or below 1:1,
    /// where the composite already has a pixel for every pixel.
    var crispTile: CrispTile?
    /// The camera `crispTile` was drawn for; it only shows while that is still
    /// where the camera is.
    var crispTileViewport: Viewport?
    let viewport: Viewport?
    let document: PhotonzDocument?
    let selection: SelectionRegion?
    /// True when the region came from a region tool (pixel semantics: ⌫
    /// erases the region); false for the arrow marquee (layer semantics).
    let selectionTargetsPixels: Bool
    /// Pending crop rect + aspect lock while the crop tool is active.
    let cropRect: CGRect?
    let cropAspect: CropAspect
    /// What the crop rect is confined to (canvas, or a layer's frame).
    let cropBounds: CGRect?
    let selectedLayerID: UUID?
    let selectedLayerFrame: CGRect?
    /// The group the pointer is inside, echoed from EditorState. Nil = the
    /// canvas. See `CanvasGroups.swift`.
    let groupContext: UUID?
    /// The marquee's multi-selection, echoed from EditorState.
    let multiSelectedLayerIDs: Set<UUID>
    let dragPreview: DragPreview?
    let tool: Tool
    /// See `EditorState.captionCloseRequest`: each bump closes an open caption
    /// field with the tool kept.
    let captionCloseRequest: Int
    /// Styled content the active tool draws (color/width from the style
    /// popover), so the drag preview matches what commit will rasterize.
    let annotationContent: AnnotationContent?
    /// What the Zoom Callout tool is set to draw (`next-callout-shape`), so the
    /// box you drag out previews and flies in the shape that lands.
    let calloutShape: ZoomCalloutShape
    /// The non-destructive style a freshly drawn shape inherits (border, corner
    /// radius…). The live preview needs it because a shape's visible outline can
    /// live in the LAYER border (rectangles) instead of the annotation's own
    /// stroke — without it, an outline-only rectangle draft looks empty.
    let annotationStyle: LayerStyle?
    /// Current text style (string empty); the inline editor mirrors it so the
    /// draft matches what commit will rasterize.
    let textContent: TextContent?
    /// The active measure tool's style, mirrored into the in-flight preview.
    let measureContent: MeasureContent?
    /// What the Measure tool does when you click (Next): the two-point caliper,
    /// the element under the pointer, the gap under the pointer, or an
    /// alignment guide. Only Size and Gap draw anything before you click.
    let measureToolMode: MeasureToolMode
    /// Which rung of the detected element ladder Size mode shows, moved by
    /// `[` and `]`.
    let measureCandidateLevel: Int
    /// The Measure tool's Snap option (Next flag `next-measure-center-snap`):
    /// measure points also magnetize to element/gap centers, not just edges.
    let measureSnapsToCenters: Bool
    /// Detected UI edges for snapping measure corners (empty unless a measure is
    /// active/selected).
    let edgeMap: EdgeMap
    /// The same analysis's brightness field: element detection walks it to find
    /// how far each boundary runs, which is what tells a settings row from the
    /// card around it. Empty until the sweep lands.
    let lumaField: LumaField
    let onViewSizeChange: (CGSize) -> Void
    let onViewportChange: (Viewport) -> Void
    /// (region, captureLayers): capture is true for the arrow tool's marquee
    /// (which doubles as rubber-band layer selection), false for the region
    /// selection tools.
    let onSelectionChange: (SelectionRegion?, Bool, UUID?) -> Void
    /// Magic-wand click: (document point, combine mode). Flood fill runs
    /// app-side (off-main) and lands via the `selection` prop.
    let onWandAt: (CGPoint, SelectionRegion.Mode) -> Void
    /// ⌫ with a pixel region: erase it (app-side decides erase vs BG-fill).
    let onDeleteRegion: () -> Void
    /// Select-tool drag inside a pixel region: lift and float the region's
    /// content (arg = ⌥, move a copy). Returns the floating content's doc
    /// frame, or nil when nothing under the region can be baked.
    let onRegionMoveBegin: (Bool) -> CGRect?
    /// Mouse-up: bake the floated content at start + delta (doc coords).
    let onRegionMoveCommit: (CGPoint) -> Void
    /// Esc / no movement: drop the float without touching the document.
    let onRegionMoveCancel: () -> Void
    let onCropRectChange: (CGRect) -> Void
    let onCropCommit: () -> Void
    let onSelectLayer: (UUID?) -> Void
    /// A click that resolved through the group walk: the layer it picked and
    /// the group it picked it inside.
    let onSelectLayerInGroup: (UUID?, UUID?) -> Void
    let onExtendSelection: (UUID) -> Void
    let onAddSweptLayers: (SelectionRegion, UUID?) -> Void
    /// A name typed on the canvas: the layer and what it is now called.
    let onRenameLayer: (UUID, String) -> Void
    /// A component's name typed on the canvas: the component and what it is now
    /// called. Separate from `onRenameLayer` because renaming a component is
    /// its own act, the one the Library tile and every copy read from.
    var onRenameComponent: (UUID, String) -> Void = { _, _ in }
    /// Escape while inside a group: step out one level, leaving that group
    /// selected. Returns false at the top level, where Escape means what it
    /// always meant.
    let onExitGroup: () -> Bool
    /// A click that landed on nothing. The Library needs it: a tile stays
    /// picked until something else is, and clicking past every layer is a
    /// person saying they are done with it, even though the canvas selection
    /// itself did not change (there was nothing selected to change).
    let onClickedNothing: () -> Void
    let onDragBegin: (UUID) -> Void
    let onFramePreview: (UUID, CGRect) -> Void
    let onFrameCommit: (UUID, CGRect) -> Void
    /// A layer let go of at the end of a DRAG, as opposed to resized or nudged:
    /// the only move that can also change which screen holds it.
    var onDropCommit: (UUID, CGRect) -> Void = { _, _ in }
    /// A multi-selection dragged on the picture: where every layer it carries
    /// sits right now, and where they all land. Canvas coordinates. `dropped`
    /// is true for a real drag and false for an arrow-key nudge or an Esc, so
    /// only a drag can change which screen holds what it carried.
    var onMoveSelectionPreview: ([UUID: CGPoint]) -> Void = { _ in }
    var onMoveSelectionCommit: ([UUID: CGPoint], Bool) -> Void = { _, _ in }
    /// ⌥-drag: the originals stay and copies travel to these canvas origins.
    var onCopyDragPreview: ([UUID: CGPoint]) -> Void = { _ in }
    var onCopyDragCommit: ([UUID: CGPoint]) -> Void = { _ in }
    var onCopyDragCancel: () -> Void = { }
    let onTransformPreview: (UUID, LayerTransform) -> Void
    let onTransformCommit: (UUID, LayerTransform) -> Void
    let onAnnotationCommit: (CGPoint, CGPoint) -> Layer?
    let onAnnotationEndpointsCommit: (UUID, CGPoint, CGPoint) -> Void
    let onZoomCalloutCommit: (CGPoint, CGPoint) -> Void
    /// The frame tool's drag, in document coordinates. A drag that is really a
    /// click arrives with both points equal, and drops the last size used.
    let onFrameCreate: (CGPoint, CGPoint) -> Void
    let onMeasureCommit: (CGPoint, CGPoint, MeasureMode, CGFloat?) -> Void
    let onMeasureEndpointPreview: (UUID, CGPoint, CGPoint, CGFloat, MeasureReadoutPlacement?) -> Void
    let onMeasureEndpointCommit: (UUID, CGPoint, CGPoint, CGFloat, MeasureReadoutPlacement?) -> Void
    /// A selected arrow's caption pill dragged to a spot: live, drop, Esc.
    let onCaptionPlacePreview: (UUID, CGPoint) -> Void
    let onCaptionPlaceCommit: (UUID, CGPoint) -> Void
    let onCaptionPlaceCancel: () -> Void
    /// Completed alignment-guide drag: (guide axis, cross-axis position,
    /// along-axis span), all in document coordinates.
    let onAlignmentCommit: (MeasureMode, CGFloat, ClosedRange<CGFloat>) -> Void
    /// Size mode's click: the element rect to turn into width + height
    /// calipers, plus the elements touching it, which the two readouts steer
    /// around so neither number reads as the neighbour's.
    let onElementSizeCommit: (CGRect, [CGRect]) -> Void
    /// Gap mode's click: the whitespace reading to turn into one caliper.
    let onGapCommit: (GapMeasurement) -> Void
    /// `[` / `]` moved Size mode's pick to a different rung.
    let onCandidateLevelChange: (Int) -> Void
    let onToolChange: (Tool) -> Void
    let onTextEditBegin: (UUID?) -> Void
    /// Typing over a piece of a copy went nowhere, and why. Nothing on screen
    /// would say so otherwise: the field simply would not open.
    let onWordingRefused: (ComponentPieceRefusal) -> Void
    let onTextCommit: (UUID?, CGPoint, String, CGFloat) -> Void
    let onTextCancel: () -> Void
    let onCaptionEditBegin: (UUID) -> Void
    /// (layer, draft, keepTool): keepTool is the press that starts the next arrow.
    let onCaptionCommit: (UUID, String, CaptionPlacement, Bool) -> Void
    let onCaptionCancel: () -> Void
    let onDeleteLayer: (UUID) -> Void
    let onDeleteLayers: ([UUID]) -> Void
    let onDropImageURL: (URL, CGPoint) -> Void
    let onDropComponent: (UUID, CGPoint) -> Void
    let onDropImageURLIntoCollage: (URL, UUID, Int) -> Void
    let onAbsorbLayerIntoCollage: (UUID, UUID, Int) -> Void
    let onSwapCollageSlots: (UUID, Int, Int) -> Void
    let isCanvasSelected: Bool
    /// The canvas grid to draw, or nil for the canvas exactly as it was.
    let canvasGrid: CanvasGridSettings?
    /// The grid's zero point while it is being placed, or nil the rest of the
    /// time. Non-nil takes the canvas over: see `CanvasNSView.mouseDown`.
    let gridOriginAdjust: CGPoint?
    let onGridOriginChange: (CGPoint) -> Void
    let onGridOriginCommit: () -> Void
    let onGridOriginCancel: () -> Void
    let onCanvasResize: (CGSize, CanvasAnchor) -> Void
    let onFillAt: (CGPoint, UUID?, Bool) -> Void
    let onFillSelected: (Bool) -> Void
    let onClearBackground: () -> Void
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        update(view)
        return view
    }

    func updateNSView(_ view: CanvasNSView, context: Context) {
        update(view)
        view.apply(image: image, viewport: viewport, document: document,
                   selection: selection, selectionTargetsPixels: selectionTargetsPixels,
                   cropRect: cropRect, cropAspect: cropAspect,
                   cropBounds: cropBounds, selectedLayerID: selectedLayerID,
                   selectedLayerFrame: selectedLayerFrame, groupContext: groupContext,
                   multiSelectedLayerIDs: multiSelectedLayerIDs, dragPreview: dragPreview,
                   tool: tool, captionCloseRequest: captionCloseRequest,
                   annotationContent: annotationContent,
                   calloutShape: calloutShape,
                   annotationStyle: annotationStyle, textContent: textContent,
                   measureContent: measureContent,
                   measureToolMode: measureToolMode,
                   measureCandidateLevel: measureCandidateLevel,
                   measureSnapsToCenters: measureSnapsToCenters, edgeMap: edgeMap,
                   lumaField: lumaField, isCanvasSelected: isCanvasSelected,
                   canvasGrid: canvasGrid, gridOriginAdjust: gridOriginAdjust)
        view.applyCrispTile(crispTile, viewport: crispTileViewport)
    }

    private func update(_ view: CanvasNSView) {
        view.onViewSizeChange = onViewSizeChange
        view.onViewportChange = onViewportChange
        view.onSelectionChange = onSelectionChange
        view.onWandAt = onWandAt
        view.onDeleteRegion = onDeleteRegion
        view.onRegionMoveBegin = onRegionMoveBegin
        view.onRegionMoveCommit = onRegionMoveCommit
        view.onRegionMoveCancel = onRegionMoveCancel
        view.onCropRectChange = onCropRectChange
        view.onCropCommit = onCropCommit
        view.onSelectLayer = onSelectLayer
        view.onSelectLayerInGroup = onSelectLayerInGroup
        view.onExtendSelection = onExtendSelection
        view.onAddSweptLayers = onAddSweptLayers
        view.onRenameLayer = onRenameLayer
        view.onRenameComponent = onRenameComponent
        view.onClickedNothing = onClickedNothing
        view.onExitGroup = onExitGroup
        view.onDragBegin = onDragBegin
        view.onFramePreview = onFramePreview
        view.onFrameCommit = onFrameCommit
        view.onDropCommit = onDropCommit
        view.onMoveSelectionPreview = onMoveSelectionPreview
        view.onMoveSelectionCommit = onMoveSelectionCommit
        view.onCopyDragPreview = onCopyDragPreview
        view.onCopyDragCommit = onCopyDragCommit
        view.onCopyDragCancel = onCopyDragCancel
        view.onTransformPreview = onTransformPreview
        view.onTransformCommit = onTransformCommit
        view.onAnnotationCommit = onAnnotationCommit
        view.onAnnotationEndpointsCommit = onAnnotationEndpointsCommit
        view.onZoomCalloutCommit = onZoomCalloutCommit
        view.onFrameCreate = onFrameCreate
        view.onMeasureCommit = onMeasureCommit
        view.onAlignmentCommit = onAlignmentCommit
        view.onElementSizeCommit = onElementSizeCommit
        view.onGapCommit = onGapCommit
        view.onCandidateLevelChange = onCandidateLevelChange
        view.onMeasureEndpointPreview = onMeasureEndpointPreview
        view.onMeasureEndpointCommit = onMeasureEndpointCommit
        view.onCaptionPlacePreview = onCaptionPlacePreview
        view.onCaptionPlaceCommit = onCaptionPlaceCommit
        view.onCaptionPlaceCancel = onCaptionPlaceCancel
        view.onToolChange = onToolChange
        view.onTextEditBegin = onTextEditBegin
        view.onWordingRefused = onWordingRefused
        view.onTextCommit = onTextCommit
        view.onTextCancel = onTextCancel
        view.onCaptionEditBegin = onCaptionEditBegin
        view.onCaptionCommit = onCaptionCommit
        view.onCaptionCancel = onCaptionCancel
        view.onDeleteLayer = onDeleteLayer
        view.onDeleteLayers = onDeleteLayers
        view.onDropImageURL = onDropImageURL
        view.onDropImageURLIntoCollage = onDropImageURLIntoCollage
        view.onDropComponent = onDropComponent
        view.onAbsorbLayerIntoCollage = onAbsorbLayerIntoCollage
        view.onSwapCollageSlots = onSwapCollageSlots
        view.onCanvasResize = onCanvasResize
        view.onFillAt = onFillAt
        view.onFillSelected = onFillSelected
        view.onClearBackground = onClearBackground
        view.onWindowChange = onWindowChange
        view.onGridOriginChange = onGridOriginChange
        view.onGridOriginCommit = onGridOriginCommit
        view.onGridOriginCancel = onGridOriginCancel
    }
}

// This class is spread over the files below, one job each. THIS file holds
// every stored property, because a Swift extension cannot declare one, plus
// init and the few members that belong to no single job. Everything a member
// here carries beyond `private` is for those files, not for the rest of the
// app: nothing outside a Canvas*.swift file should touch it.
//
//   CanvasDisplay.swift             draws it: composite, selection, handles,
//                                   crop chrome, marquee, drag sprite, snap guides
//   CanvasPointerDrags.swift        press, drag, release, for every tool
//   CanvasPointerCue.swift          what the pointer says before you press
//   CanvasKeys.swift                keys the canvas itself answers
//   CanvasZoom.swift                pan, pinch, double-tap
//   CanvasDrop.swift                dropping a file or a component onto it
//   CanvasAnnotationPreview.swift   the shape under the pointer while drawing
//   CanvasTextEditing.swift         the inline text and caption editors
//   CanvasMeasure.swift             the Measure tool: Size and Gap hover
//                                   previews, caliper placement, handle geometry
//   CanvasGroups.swift, CanvasFrames.swift, CanvasComponents.swift,
//   CanvasNames.swift, CanvasGridChrome.swift, CanvasColumnChrome.swift
final class CanvasNSView: NSView {
    var onViewSizeChange: ((CGSize) -> Void) = { _ in }
    var onViewportChange: ((Viewport) -> Void) = { _ in }
    var onSelectionChange: ((SelectionRegion?, Bool, UUID?) -> Void) = { _, _, _ in }
    var onWandAt: ((CGPoint, SelectionRegion.Mode) -> Void) = { _, _ in }
    var onDeleteRegion: () -> Void = {}
    var onRegionMoveBegin: ((Bool) -> CGRect?) = { _ in nil }
    var onRegionMoveCommit: ((CGPoint) -> Void) = { _ in }
    var onRegionMoveCancel: () -> Void = {}
    var onCropRectChange: ((CGRect) -> Void) = { _ in }
    var onCropCommit: (() -> Void) = {}
    var onSelectLayer: ((UUID?) -> Void) = { _ in }
    var onSelectLayerInGroup: ((UUID?, UUID?) -> Void) = { _, _ in }
    var onExtendSelection: ((UUID) -> Void) = { _ in }
    var onAddSweptLayers: ((SelectionRegion, UUID?) -> Void) = { _, _ in }
    var onRenameLayer: ((UUID, String) -> Void) = { _, _ in }
    var onRenameComponent: ((UUID, String) -> Void) = { _, _ in }
    var onClickedNothing: (() -> Void) = {}
    var onExitGroup: (() -> Bool) = { false }
    var onDragBegin: ((UUID) -> Void) = { _ in }
    var onFramePreview: ((UUID, CGRect) -> Void) = { _, _ in }
    var onFrameCommit: ((UUID, CGRect) -> Void) = { _, _ in }
    var onDropCommit: ((UUID, CGRect) -> Void) = { _, _ in }
    var onMoveSelectionPreview: (([UUID: CGPoint]) -> Void) = { _ in }
    var onMoveSelectionCommit: (([UUID: CGPoint], Bool) -> Void) = { _, _ in }
    var onCopyDragPreview: (([UUID: CGPoint]) -> Void) = { _ in }
    var onCopyDragCommit: (([UUID: CGPoint]) -> Void) = { _ in }
    var onCopyDragCancel: (() -> Void) = { }
    var onTransformPreview: ((UUID, LayerTransform) -> Void) = { _, _ in }
    var onTransformCommit: ((UUID, LayerTransform) -> Void) = { _, _ in }
    var onAnnotationCommit: ((CGPoint, CGPoint) -> Layer?) = { _, _ in nil }
    var onAnnotationEndpointsCommit: ((UUID, CGPoint, CGPoint) -> Void) = { _, _, _ in }
    var onZoomCalloutCommit: ((CGPoint, CGPoint) -> Void) = { _, _ in }
    var onFrameCreate: ((CGPoint, CGPoint) -> Void) = { _, _ in }
    var onMeasureCommit: ((CGPoint, CGPoint, MeasureMode, CGFloat?) -> Void) = { _, _, _, _ in }
    var onAlignmentCommit: ((MeasureMode, CGFloat, ClosedRange<CGFloat>) -> Void) = { _, _, _ in }
    var onElementSizeCommit: ((CGRect, [CGRect]) -> Void) = { _, _ in }
    var onGapCommit: ((GapMeasurement) -> Void) = { _ in }
    var onCandidateLevelChange: ((Int) -> Void) = { _ in }
    var onMeasureEndpointPreview: ((UUID, CGPoint, CGPoint, CGFloat, MeasureReadoutPlacement?) -> Void) = { _, _, _, _, _ in }
    var onMeasureEndpointCommit: ((UUID, CGPoint, CGPoint, CGFloat, MeasureReadoutPlacement?) -> Void) = { _, _, _, _, _ in }
    /// A selected arrow's caption pill being dragged: live (no history), the
    /// drop (one undo step), and Esc (restores the render).
    var onCaptionPlacePreview: ((UUID, CGPoint) -> Void) = { _, _ in }
    var onCaptionPlaceCommit: ((UUID, CGPoint) -> Void) = { _, _ in }
    var onCaptionPlaceCancel: (() -> Void) = {}
    var onToolChange: ((Tool) -> Void) = { _ in }
    var onTextEditBegin: ((UUID?) -> Void) = { _ in }
    var onWordingRefused: ((ComponentPieceRefusal) -> Void) = { _ in }
    var onTextCommit: ((UUID?, CGPoint, String, CGFloat) -> Void) = { _, _, _, _ in }
    var onTextCancel: (() -> Void) = {}
    var onCaptionEditBegin: ((UUID) -> Void) = { _ in }
    var onCaptionCommit: ((UUID, String, CaptionPlacement, Bool) -> Void) = { _, _, _, _ in }
    var onCaptionCancel: (() -> Void) = {}
    var onDeleteLayer: ((UUID) -> Void) = { _ in }
    var onDeleteLayers: (([UUID]) -> Void) = { _ in }
    /// A file (image) dropped onto the canvas — e.g. a history-overlay thumbnail
    /// or a Finder file. Handled here on the canvas NSView (which covers the
    /// document) rather than a SwiftUI `.dropDestination`, which doesn't reliably
    /// receive drops layered over an NSViewRepresentable.
    /// The point is where the drop landed, in document coordinates, so a file
    /// let go over a frame can join that frame.
    var onDropImageURL: ((URL, CGPoint) -> Void) = { _, _ in }
    /// A file dropped straight into a collage slot: (url, collage layer, slot).
    var onDropImageURLIntoCollage: ((URL, UUID, Int) -> Void) = { _, _, _ in }
    /// A component dragged off the Library shelf, dropped at a document point
    /// (Next, `next-components`).
    var onDropComponent: ((UUID, CGPoint) -> Void) = { _, _ in }
    /// A photo layer dropped onto a collage slot: (photo layer, collage, slot).
    var onAbsorbLayerIntoCollage: ((UUID, UUID, Int) -> Void) = { _, _, _ in }
    /// Two slots of one collage swapped by dragging: (collage, from, to).
    var onSwapCollageSlots: ((UUID, Int, Int) -> Void) = { _, _, _ in }
    /// A canvas-boundary handle drag ended: (new size, anchor of the pinned side).
    var onCanvasResize: ((CGSize, CanvasAnchor) -> Void) = { _, _ in }
    /// Bucket click: (document point, hit layer if any, ⌥ = background color).
    var onFillAt: ((CGPoint, UUID?, Bool) -> Void) = { _, _, _ in }
    /// ⌥⌫ — fill the selected layer (false = foreground color).
    var onFillSelected: ((Bool) -> Void) = { _ in }
    /// ⌫ with the locked Background selected — reset it to the bg fill color.
    var onClearBackground: (() -> Void) = {}
    /// The canvas landed in (or left) a window — the reliable moment to size the
    /// window to a just-opened image (mirrors the video preview's hook).
    var onWindowChange: ((NSWindow?) -> Void) = { _ in }
    /// The zero point moved to here (live, while placing the grid).
    var onGridOriginChange: ((CGPoint) -> Void) = { _ in }
    /// ⏎ / ⎋ while placing the grid.
    var onGridOriginCommit: (() -> Void) = { }
    var onGridOriginCancel: (() -> Void) = { }

    let contentLayer = CALayer()
    /// The visible part of the document redrawn at the zoom, laid exactly over
    /// the stretched composite underneath it. Same picture, more pixels.
    let crispLayer = CALayer()
    var crispTile: CrispTile?
    var crispTileViewport: Viewport?
    /// Floats the dragged layer's pre-rendered sprite over the underlay during
    /// drags — positioned in pure Core Animation, no per-move rendering.
    let previewSpriteLayer = CALayer()
    /// The grid you build against (Next, `next-canvas-grid`): one shape layer
    /// per rung of the level-of-detail ladder, coarsest last, each carrying its
    /// own strength. Chrome, so it is out of every export, and on whichever
    /// side of the picture the grid is switched to. See `CanvasGridChrome.swift`
    /// and `placeCanvasGrid(overPicture:)`.
    let canvasGridLayers = [CAShapeLayer(), CAShapeLayer(), CAShapeLayer()]
    /// The three rungs together, so the whole grid changes sides of the picture
    /// in one move. See `placeCanvasGrid(overPicture:)`.
    let canvasGridContainer = CALayer()
    /// The two markers, one across and one down, that say where the grid
    /// starts while the zero point is being placed. Chrome above everything,
    /// so they are never lost in the grid they are moving.
    let gridOriginLayer = CAShapeLayer()
    /// The grid line a drag is standing on, lit up while it holds. It is one of
    /// the lines already on screen drawn again at full strength, not a rule
    /// laid over them, so the answer to "what did it snap to" is a line you
    /// were already looking at. See `refreshGridSnapLines(in:)`.
    let gridSnapLayer = CAShapeLayer()
    /// The zero point being placed, in document points, or nil when the canvas
    /// is not in that mode. Set by `apply`, read by the grid chrome, the mouse
    /// and the keyboard.
    var gridOriginAdjust: CGPoint?
    /// Which side of the picture the grid is currently on, or nil before it has
    /// been placed at all.
    private var canvasGridOverPicture: Bool?
    /// What the grid should be, echoed from `EditorState`; nil when the
    /// feature is off, and then nothing is drawn. The grid being switched OFF
    /// is not nothing: the surround still carries it.
    var canvasGrid: CanvasGridSettings?
    /// Marching ants: a solid white stroke underneath…
    let selectionBaseLayer = CAShapeLayer()
    /// …and animated black dashes on top, giving the classic alternating crawl.
    let selectionAntsLayer = CAShapeLayer()
    /// Accent outline around the selected layer.
    let layerOutlineLayer = CAShapeLayer()
    /// Outlines around every layer the marquee fully contains (rubber-band
    /// multi-selection) — live during the drag, standing once committed, so
    /// it's obvious what ⌫ will delete.
    let multiSelectOutlineLayer = CAShapeLayer()
    /// The eight resize handles on the selected layer's outline.
    let handlesLayer = CAShapeLayer()
    /// Rotate knob: a circle floated off the layer's top edge plus its stem.
    let rotateKnobLayer = CAShapeLayer()
    /// The faint box around the group you are currently INSIDE, so descending
    /// into one is visible rather than a mode you have to remember.
    let groupContextLayer = CAShapeLayer()
    /// The columns a screen is designed to (Next, `next-frames`): one filled
    /// path holding every band of every screen showing them. See
    /// `CanvasColumnChrome.swift`.
    let columnChromeLayer = CAShapeLayer()
    /// A frame's name, above its top left corner: one text sublayer per frame.
    let frameChromeLayer = CALayer()
    /// The hairline at every frame's edge, so a screen has a visible boundary
    /// even where its surface matches the canvas behind it.
    let frameEdgeLayer = CAShapeLayer()
    /// A main component's mark and name, above its top left corner: one glyph
    /// and one text sublayer per component.
    let componentChromeLayer = CALayer()
    /// Snap guides shown while a move drag is captured by an edge/center.
    let snapGuideLayer = CAShapeLayer()
    /// Hover snap dot: while the measure tool is active and idle, a dot follows
    /// the cursor and magnetizes to the nearest detected edge (⌘ bypasses),
    /// marking where a drag will begin.
    let snapDotLayer = CAShapeLayer()
    /// Hover-to-measure readout (`next-measure-hover`, Next release): while the
    /// Measure tool idles over the image, the element rect under the pointer
    /// gets a tinted outline plus two transient size calipers (width along the
    /// bottom edge, height along the right), rasterized exactly like committed
    /// calipers. Canvas chrome only — nothing here touches the document, makes
    /// history entries, or triggers a composite re-render.
    let hoverBoundsLayer = CAShapeLayer()
    let hoverWidthCaliperLayer = CALayer()
    let hoverHeightCaliperLayer = CALayer()
    /// A rasterized transient caliper, cached so resting on one element (or
    /// gliding within it) never re-renders text per mouse move.
    struct HoverCaliperSprite {
        let key: String
        let image: CGImage
        /// Document-space frame of the rasterized caliper layer.
        let frame: CGRect
    }
    var hoverWidthSprite: HoverCaliperSprite?
    var hoverHeightSprite: HoverCaliperSprite?
    /// Latest pointer location in view space, for the hover snap dot.
    var hoverPoint: CGPoint?
    /// Dashed wells + a plus glyph over every EMPTY collage slot — editor
    /// chrome only; empty slots render transparent in the composite.
    let collageWellsLayer = CAShapeLayer()
    /// The collage slot a drag (file drop / photo layer / slot swap) is
    /// currently over — filled accent highlight.
    let slotHighlightLayer = CAShapeLayer()
    /// The screen a drag holding these boxes would join, nil when it would
    /// change nothing. Asked once per mouse move, so it is skipped outright in
    /// a document that has no screens in it — which is every screenshot
    /// anybody has taken.
    func adoptionHost(moving boxes: [UUID: CGRect]) -> UUID? {
        guard framesEnabled, !boxes.isEmpty, let document, document.hasFrames else { return nil }
        return document.frameAdoptionHost(moving: boxes)
    }

    /// What the canvas is currently promising a move drag, for a playtest to
    /// read back.
    var adoptionHostDescription: UUID? { adoptionHost }

    /// Where whatever is being dragged over the canvas would land: an outline
    /// the exact size of the thing, in the exact spot letting go would put it.
    let dropLandingLayer = CAShapeLayer()
    /// The frame it would join, lit up so joining a screen is visible before
    /// the button comes up rather than discovered afterwards.
    let dropHostFrameLayer = CAShapeLayer()
    /// What the canvas is promising the drag in the air: the box it would fill
    /// and the frame it would join. Nil whenever no drag is over this canvas.
    /// A component off the Library shelf and a picture from the Finder both
    /// write here, because a person letting go wants the same answer either
    /// way: where does this land, and how big is it.
    var dropLanding: (rect: CGRect, host: UUID?)?
    /// The file the drag in flight is carrying and what the canvas can make of
    /// it, kept for the life of that one drag session. See `draggedFile`.
    var draggedImage: (sequence: Int, url: URL, drop: CanvasFileDrop)?

    /// The screen a move drag in flight would drop what it carries INTO,
    /// outlined while the pointer is still down. Without it the drop changes
    /// what holds a layer with nothing on screen having said so. It is the same
    /// dashed box a component dragged off the Library shelf draws, because it
    /// is the same promise. See `FrameAdoption.swift`.
    var adoptionHost: UUID?
    /// Crop mode chrome: dimmed surround (even-odd fill), thirds grid,
    /// border, and handles.
    let cropDimLayer = CAShapeLayer()
    let cropGridLayer = CAShapeLayer()
    let cropBorderLayer = CAShapeLayer()
    let cropHandlesLayer = CAShapeLayer()
    /// Live preview of an in-progress drag-to-create annotation.
    let annotationPreviewLayer = CAShapeLayer()
    /// Arrowheads are filled but never stroked (matching the rasterizer), so
    /// they need their own shape layer under the stroked shaft.
    let annotationPreviewHeadLayer = CAShapeLayer()
    /// A captioned arrow's pill, held over the same preview. It is a picture
    /// rather than a shape because a pill is mostly type, and the vector
    /// preview has no way to set type. Dragging an end used to hide the label
    /// for the whole drag, so you could not see where it would land until you
    /// let go (reported 2026-09-05).
    let captionPreviewLayer = CALayer()
    /// What `captionPreviewLayer.contents` was baked from, so the pill is
    /// rasterized once per drag instead of once per mouse move: the words and
    /// their size do not change while an endpoint moves, only where they land.
    var captionPreviewKey: String?
    /// The baked pill bitmap's size in document points (the pill plus room for
    /// its shadow), so it can be scaled to the zoom it is shown at.
    var captionPreviewSize: CGSize?
    /// A just-created zoom callout flying from its source box to its placed
    /// frame: the magnified sprite, plus the source outline and leader lines
    /// fading in underneath it.
    let calloutFlightLayer = CALayer()
    let calloutFlightOutlineLayer = CAShapeLayer()
    let calloutFlightLeaderLayer = CAShapeLayer()
    /// The pre-commit composite, held on screen for the flight's duration so
    /// the baked-in callout doesn't show at its destination mid-flight.
    var calloutHoldImage: CGImage?
    /// Invalidates a flight's completion cleanup when a newer flight starts.
    var calloutFlightGeneration = 0
    private var lastReportedSize: CGSize = .zero
    /// The viewport currently on screen. Gesture handlers mutate from this and
    /// apply locally before notifying, so panning/zooming never waits a runloop
    /// tick for SwiftUI to echo the state back.
    var viewport: Viewport?
    var image: CGImage?
    /// Committed document (hit-testing source). Previews never land here.
    var document: PhotonzDocument?
    /// Committed selection region in document coordinates.
    var selection: SelectionRegion?
    /// Whether the committed region has pixel semantics (region tools) —
    /// routes ⌫/⌥⌫ to region ops instead of layer ops.
    var selectionTargetsPixels = false
    /// Pending crop rect (document coordinates), echoed from EditorState.
    var cropRect: CGRect?
    /// Crop aspect lock, echoed from EditorState; drags constrain through it.
    var cropAspect: CropAspect = .free
    /// Crop confinement (canvas, or the target layer's frame), echoed from
    /// EditorState. Nil falls back to the full document.
    var cropBounds: CGRect?

    /// In-progress crop-rect drag. `startRect` restores on Esc and on
    /// click-without-drag.
    struct CropDrag {
        enum Kind {
            case resize(ResizeHandle)
            case move
            case define(anchor: CGPoint)
        }
        let kind: Kind
        let startRect: CGRect?
        var lastPoint: CGPoint
    }
    var cropDrag: CropDrag?
    /// Selected layer (committed state, echoed from EditorState). Only
    /// `apply` writes this and the two below; it lives in CanvasDisplay.swift,
    /// and an extension in another file cannot reach a private setter.
    var selectedLayerID: UUID?
    /// Selected layer's frame in document coordinates (committed state).
    var selectedLayerFrame: CGRect?
    /// The group the pointer is inside, echoed from EditorState (`CanvasGroups.swift`).
    var groupContext: UUID?
    /// The marquee's multi-selection, echoed from EditorState (committed).
    /// Read by the frame chrome too, so every picked screen's name tints.
    var multiSelectedLayerIDs: Set<UUID> = []
    /// Every layer currently picked, however it got there: the multi-selection
    /// plus the single primary selection. What a ⇧-sweep adds to.
    var pickedLayerIDs: Set<UUID> {
        multiSelectedLayerIDs.union(selectedLayerID.map { [$0] } ?? [])
    }
    /// Pre-rendered drag preview from EditorState; arrives async after drag start
    /// and outlives the drag until the post-commit render lands.
    var dragPreview: DragPreview?
    /// In-progress marquee (document coordinates). While set, it is what the
    /// ants display — same zero-latency-echo pattern as pan/zoom.
    var marquee: MarqueeDrag?
    /// What the press that started `marquee` meant for the selection, latched
    /// at gesture start: plain replaces it, ⇧ spares it (a ⇧-click that missed
    /// the layer it was aimed at).
    var marqueePress: BareCanvasPress = .replaces
    /// The group the press that started `marquee` was standing inside, latched
    /// at gesture start. It has to be latched: a plain press on bare canvas
    /// lets go of the selection, and letting go of the selection is what puts
    /// you back at the top level, so by the time the band is released the
    /// level it was swept at is already gone.
    var marqueeContext: UUID?
    /// In-progress region-select drag (rect/ellipse tools). The combine mode
    /// is latched from the modifiers at gesture start (⇧ add, ⌥ subtract,
    /// ⇧⌥ intersect); the ants preview the live boolean combination.
    var regionDrag: (drag: MarqueeDrag, mode: SelectionRegion.Mode, isEllipse: Bool)?
    /// Live modifier state, for the selection cursor's +/−/× badge.
    var pointerModifiers: NSEvent.ModifierFlags = []
    /// In-flight region CONTENT move (select tool dragging inside a pixel
    /// region — Photoshop Move-tool semantics). EditorState holds the lifted
    /// bitmaps; `frame` is the content's doc frame at drag start.
    var regionContentDrag: (start: CGPoint, current: CGPoint, frame: CGRect)?
    /// Post-commit sprite hold for a region move: the content frame isn't the
    /// layer frame, so the standard selectedLayerFrame hold can't cover it.
    var regionMoveHoldFrame: CGRect?
    /// In-flight outline-only move (marquee tool plain-drag starting inside
    /// the region): moves the ants, never pixels (Photoshop).
    var regionOutlineDrag: (start: CGPoint, current: CGPoint, base: SelectionRegion)?

    /// Whole-pixel drag delta so moved content/outlines stay pixel-aligned.
    func roundedDelta(from start: CGPoint, to current: CGPoint) -> CGPoint {
        CGPoint(x: (current.x - start.x).rounded(), y: (current.y - start.y).rounded())
    }
    /// The active tool, echoed from EditorState. Annotation tools reroute the
    /// pointer from hit-test/marquee into drag-to-create.
    var tool: Tool = .select
    var captionCloseRequest = 0
    /// In-progress drag-to-create (document coordinates).
    var annotationDrag: AnnotationDrag?
    /// Set by a press that committed the fresh arrow's caption field with the
    /// Arrow tool still in hand; mouse-up decides whether it was a click (hand
    /// back to Select) or a drag (the next arrow).
    var pressClosedCaptionField = false
    /// Styled content for the active tool, echoed from EditorState; the in-flight
    /// preview strokes with this so it matches the committed rasterization.
    var annotationContent: AnnotationContent?
    /// What the Zoom Callout tool is set to draw, echoed from EditorState. The
    /// drag box previews in it and the creation flight lands in it, so choosing
    /// Circle is visible from the first drag rather than after it.
    var calloutShape: ZoomCalloutShape = .rectangle
    /// The draft layer style for the active shape tool (border/corner radius);
    /// the create preview draws its border so outline-only rectangles show.
    var annotationStyle: LayerStyle?
    var measureContent: MeasureContent?
    /// Live label-size preview for the selected caliper during a slider drag.
    /// In-progress 3-click caliper placement: click foot A → move → click foot B →
    /// move → click sets the head (depth + direction). Nil = idle (hover only).
    enum MeasurePlacement {
        case firstPlaced(foot1: CGPoint)                                   // seeking foot B
        case secondPlaced(foot1: CGPoint, foot2: CGPoint, mode: MeasureMode) // seeking head
    }
    var measurePlacement: MeasurePlacement?
    /// What the Measure tool does when you click (Next). Distance is the only
    /// mode that draws nothing under an idle pointer.
    var measureToolMode: MeasureToolMode = .distance
    /// Which rung of the element ladder Size mode shows (`[` / `]`).
    var measureCandidateLevel = 0
    /// The rect Size mode is previewing right now — exactly what a click
    /// commits, so what you see and what you get can never disagree.
    var measureElementPreview: CGRect?
    /// The elements touching that rect, read off the capture. Detection costs
    /// real milliseconds and the pick only changes when the pointer crosses
    /// into another element, so the answer is kept until it does.
    var measureElementNeighbors: [CGRect] = []
    var measureNeighborCache: (rect: CGRect, reach: CGFloat, neighbors: [CGRect])?
    /// The two elements bounding the gap under the pointer, kept until the gap
    /// itself changes so a mouse move inside one gap costs no detection.
    var measureGapSubjectCache: (gap: GapMeasurement, subjects: [CGRect])?
    /// The gap Gap mode is previewing right now, same contract.
    var measureGapPreview: GapMeasurement?
    /// Alignment mode (Next `next-measure-align`): whether Measure drags draw a
    /// checking guide, and the in-flight guide drag (document coordinates).
    var measureChecksAlignment: Bool { measureToolMode == .alignment }
    /// Snap option (Next `next-measure-center-snap`): measure snapping also
    /// offers element/gap centers, echoed from EditorState via the wrapper.
    var measureSnapsToCenters = false
    var alignmentDrag: (anchor: CGPoint, current: CGPoint)?
    /// Dashed live preview of the guide being dragged.
    let alignmentPreviewLayer = CAShapeLayer()
    /// The mouse-down location (view space) of the current measure press, to tell
    /// a click from a press-drag on release.
    var measurePressDownView: CGPoint?
    /// True between the mouse-down that first placed foot A and its mouse-up, so a
    /// no-drag release stays in click/click mode while a dragged release completes
    /// the measuring line (down/drag/release).
    var measureFirstFootPress = false
    /// In-flight drag of one of a placed caliper's three handles (a foot or head).
    var measureHandleDrag: MeasureHandleDrag?
    /// Dragging a selected arrow's caption pill to the spot you want (Next
    /// `next-arrow-captions`). The grip is kept, like the caliper's readout
    /// grab: a pill taken hold of near its edge stays under the pointer.
    struct CaptionDrag {
        let layerID: UUID
        /// Pointer minus pill center at the grab, document space.
        let grip: CGSize
        let startCenter: CGPoint
        var current: CGPoint
        /// Where the pill centers with this drag applied.
        var center: CGPoint { CGPoint(x: current.x - grip.width, y: current.y - grip.height) }
    }
    var captionDrag: CaptionDrag?
    /// Detected UI edges, mirrored from EditorState; measure corners magnetize to
    /// these (and the pixel grid) while dragging.
    var edgeMap = EdgeMap.empty
    var lumaField = LumaField.empty
    /// Document-space x/y of the edge(s) a measure corner is currently snapped to,
    /// drawn as a highlight while the corner is held. Cleared on mouse-up.
    var snapGuide: (x: CGFloat?, y: CGFloat?)?
    /// Which axes this drag is still allowed to catch lines on, from the
    /// direction the hand is actually travelling: dragging a leg up and down
    /// shouldn't flash vertical guides past it. The gate keeps its decision
    /// while the travel is ambiguous, so it cannot toggle under a wobble.
    private var dragGate = DragAxisGate()
    /// The lines THIS drag is standing on, and whether ⌘ has freed it. Every
    /// snapping drag on the canvas — a measure foot, a layer edge, a corner, a
    /// whole layer, a region — reads and writes this one piece of state, which
    /// is what makes all of them behave the same way: a line that is showing
    /// keeps the drag until the pointer is clearly away from it.
    var snapHold = SnapHold()
    /// In-flight swap drag: a filled slot of the SELECTED collage picked up.
    var slotDrag: (collageID: UUID, from: Int)?
    /// The slot any eligible drag is currently hovering (drop/absorb/swap target).
    var hoverSlot: (collageID: UUID, index: Int)?
    /// The Canvas pseudo-selection, echoed from EditorState: boundary handles
    /// on the document rect; drags resize the canvas itself.
    var isCanvasSelected = false
    /// In-flight canvas-boundary resize: the proposed rect may grow in any
    /// direction (negative origin = space added on the left/top); commit maps
    /// it to setCanvasSize + the anchor opposite the dragged handle — or
    /// `.center` when ⇧ made the drag symmetric (content stays centered).
    var canvasResizeDrag: (handle: ResizeHandle, rect: CGRect, centered: Bool)?

    /// Suppresses edge captures on the axis the drag is not travelling along.
    /// The suppressed axis falls back to the pixel grid, and drops whatever it
    /// was holding: a line nobody may catch is not a line anyone is standing on.
    func axisGated(_ snap: EdgeSnapping.Snap, raw p: CGPoint) -> EdgeSnapping.Snap {
        var snap = snap
        if !dragGate.capturesX, snap.guideX != nil {
            snap.point.x = p.x.rounded()
            snap.guideX = nil
        }
        if !dragGate.capturesY, snap.guideY != nil {
            snap.point.y = p.y.rounded()
            snap.guideY = nil
        }
        return snap
    }

    /// The document point an annotation end should take this event: magnetized
    /// onto the picture's own edges, or left exactly under the pointer when the
    /// magnet is refused. Sets the yellow guide as a side effect, so drawing an
    /// arrow says what it caught the same way a caliper does.
    ///
    /// Two keys refuse the magnet and they refuse it differently. ⌘ is the
    /// deliberate one and it LATCHES, the same as everywhere else on the
    /// canvas: a magnet that came back when the key came up would move the
    /// thing you had just placed by hand. ⇧ refuses it only while it is held —
    /// a constrained drag pins the mark to 45 degrees around its other end, so
    /// the angle owns the point and a magnet could only fight it, but ⇧ is a
    /// live constraint a hand presses and lets go of mid-drag.
    func snappedAnnotationPoint(_ p: CGPoint, shape: AnnotationShape?,
                                        opposite: CGPoint?, event: NSEvent) -> CGPoint {
        guard let viewport, let shape else {
            snapGuide = nil
            return p
        }
        let held = snapHold(freeing: event.modifierFlags.contains(.command))
        let refused = held.isFree || event.modifierFlags.contains(.shift)
        let snap = AnnotationSnapping.snap(p, shape: shape, opposite: opposite,
                                           edges: edgeMap, zoom: viewport.zoom,
                                           free: refused, holding: held)
        snapGuide = (snap.guideX, snap.guideY)
        snapHold.caught(x: snap.guideX, y: snap.guideY)
        return snap.point
    }

    /// Feeds the direction gate; call once per mouseDragged before snapping.
    func trackDragMotion(_ p: CGPoint) {
        dragGate.track(p)
    }

    /// A new drag starts with no direction and nothing caught.
    func resetDragMotion(_ p: CGPoint) {
        dragGate.reset(at: p)
        snapHold = .none
    }

    /// The lines a snapping drag may keep holding this event. ⌘ empties it and
    /// latches it empty for the rest of the drag: a magnet that came back when
    /// the key came up would move the thing you had just placed by hand.
    func snapHold(freeing free: Bool) -> SnapHold {
        if free { snapHold.free() }
        return snapHold
    }

    /// A captioned arrow's pill footprint in document space, at the width the
    /// label is really drawn at. Dragging it moves the label.
    func captionPillRect(_ layer: Layer) -> CGRect? {
        CanvasGrab.captionPillRect(of: layer,
                                   captionPillSize: layer.measuredCaptionPillSize)
    }

    /// The composite that was on screen when an annotation was committed. The
    /// preview shape stays up until a *different* image arrives, so the new
    /// annotation doesn't flash out while the re-render is in flight.
    var annotationCommitImage: CGImage?
    /// Current text style, echoed from EditorState; the inline editor restyles
    /// live when the font picker changes it. The string field is ignored.
    var textContent: TextContent?

    /// In-progress inline text edit (or arrow caption entry, which reuses the
    /// same editor overlay).
    struct TextEditSession {
        /// Nil while placing a new text block; set when re-editing a layer
        /// (or always, for a caption session).
        let layerID: UUID?
        /// The text frame's top-left in document coordinates — or, for a
        /// caption session, the pill's CENTER (the editor stays centered on it).
        let origin: CGPoint
        /// Non-nil marks this as an arrow-caption session and carries the
        /// caption's fixed style (white text at the caption font size).
        var captionStyle: TextContent?
        /// The arrow being captioned, so the editor can sit exactly where the
        /// pill for the CURRENT draft will render (it grows away from the tail
        /// and slides onto the picture the same way the committed pill does).
        var captionLayer: Layer?
        /// Where the pill hangs from and which way it grows, picked once when
        /// the field opened and held for the whole session: what you type
        /// extends the bubble away from the arrow, and nothing slides under the
        /// cursor mid-word. Committing writes this same spot.
        var captionPlacement = CaptionPlacement()
        /// Where the words sit in the box being re-edited. The font picker's
        /// style carries no placement, so restyling mid-edit used to drop a
        /// centred label to the left edge for as long as you were typing it;
        /// the session holds the placement and stamps it back on instead.
        var alignment: TextAlign?
        var verticalAlignment: TextVerticalAlign?
    }
    var textSession: TextEditSession?
    /// The session's editor overlay, positioned/scaled to track the viewport.
    var textEditor: NSTextView?
    /// The bubble drawn behind an arrow caption's editor, so the draft sits in
    /// the same pill the committed caption renders in. Nil for text sessions.
    var captionPill: CaptionPillView?
    /// The zoom `textEditor`'s font was last scaled for.
    var textEditorZoom: CGFloat = 0
    /// The style `textEditor` was last configured with (string empty), so
    /// font-picker changes mid-edit restyle the draft exactly once.
    var textEditorContent: TextContent?

    /// The layer whose name is open for typing on the canvas, and the field
    /// doing the typing. A name above a box is chrome rather than a text layer,
    /// so it gets a plain one-line field of its own instead of the inline
    /// editor above. See `CanvasNames.swift`.
    var canvasRenameID: UUID?
    var canvasNameField: CanvasNameFieldView?
    /// The name under the pointer, a screen's or a component's. It tints, which
    /// is the only thing telling anyone the name can be clicked at all.
    var hoveredNameLabelID: UUID?

    /// In-progress layer move.
    struct MoveDrag {
        let layerID: UUID
        /// Pointer offset from the frame origin at grab time (doc coords).
        let grabOffset: CGPoint
        let size: CGSize
        let startOrigin: CGPoint
        /// The boxes this drag can line itself up with, in canvas coordinates.
        /// Gathered ONCE at grab time: nothing but the dragged layer moves
        /// during a drag, so a crowded document costs nothing per frame.
        var peers: [CGRect] = []
        /// The columns of every screen showing them, in canvas coordinates,
        /// gathered ONCE at grab time beside the peers. They pull sideways
        /// only, so nothing on a screen quietly sticks to its top edge, and
        /// they are empty for every document with no screen showing columns —
        /// which is a screenshot, a plain canvas, and a screen with the switch
        /// off. See `FrameColumns`.
        var columns: [CGRect] = []
        var snapped: Snapping.Result
        /// Becomes true once the pointer travels past the click tolerance;
        /// a click that never moves selects without committing a move.
        var moved = false
        /// ⌥ was held: the original stays put and a copy is what travels.
        /// It latches ON and never off, so pressing ⌥ after the drag started
        /// still copies and letting go before the mouse does not take the copy
        /// away — a modifier released a moment early is not a change of mind.
        var copying = false
    }
    var moveDrag: MoveDrag?

    /// In-progress move of a whole multi-selection. What is being dragged is
    /// the BOX the selection makes: every member is offset by the same amount,
    /// so the group of layers keeps its shape and lines up by its outer edges
    /// rather than by whichever piece happens to be under the pointer.
    struct MultiMoveDrag {
        let plan: MultiLayerDrag
        /// The layer the press landed on, and the group it was resolved in.
        /// A press that never travels is a click on that one layer, and a
        /// click on one of several picked things narrows the selection to it.
        let pick: (id: UUID, context: UUID?)
        /// Pointer offset from the selection box's origin at grab time.
        let grabOffset: CGPoint
        /// The boxes this drag can line itself up with, in canvas coordinates,
        /// gathered ONCE at grab time. Every member is left out: they all
        /// travel with the drag, so none of them is something to line up with.
        var peers: [CGRect] = []
        /// The columns of every screen showing them, in canvas coordinates,
        /// gathered ONCE at grab time beside the peers. They pull sideways
        /// only, so nothing on a screen quietly sticks to its top edge, and
        /// they are empty for every document with no screen showing columns —
        /// which is a screenshot, a plain canvas, and a screen with the switch
        /// off. See `FrameColumns`.
        var columns: [CGRect] = []
        var snapped: Snapping.Result
        /// Becomes true once the pointer travels past the click tolerance; a
        /// press that never moves keeps the selection and does nothing else.
        var moved = false
        /// ⌥ was held: the originals stay put and copies are what travel.
        /// Latches on and never off, exactly as it does for one layer.
        var copying = false

        /// How far everything has travelled from where it started.
        var delta: CGPoint {
            CGPoint(x: snapped.origin.x - plan.bounds.origin.x,
                    y: snapped.origin.y - plan.bounds.origin.y)
        }
        /// Where each member sits right now, or nil before the drag moved.
        var liveOrigins: [UUID: CGPoint]? {
            moved ? plan.origins(movingBoundsTo: snapped.origin) : nil
        }
    }
    var multiMove: MultiMoveDrag?

    /// In-progress handle resize.
    struct ResizeDrag {
        let layerID: UUID
        let handle: ResizeHandle
        let startFrame: CGRect
        var frame: CGRect
        /// The boxes the dragged EDGE lines itself up with, in canvas
        /// coordinates. Gathered ONCE at grab time, exactly as a move gathers
        /// them: nothing but this layer changes during the drag, so a crowded
        /// document costs nothing per frame. Empty for a layer that is rotated
        /// or skewed, whose handle space is not canvas space.
        var peers: [CGRect] = []
        /// The columns of every screen showing them, in canvas coordinates,
        /// gathered ONCE at grab time beside the peers. They pull sideways
        /// only, so nothing on a screen quietly sticks to its top edge, and
        /// they are empty for every document with no screen showing columns —
        /// which is a screenshot, a plain canvas, and a screen with the switch
        /// off. See `FrameColumns`.
        var columns: [CGRect] = []
        /// The guides the last snap put down, for the overlay to draw. A resize
        /// draws the same yellow lines a move does, because it is lining up
        /// with the same things.
        var snapped = Snapping.FrameResult(frame: .zero)
    }
    var resizeDrag: ResizeDrag?

    /// True only between a move/resize COMMIT and the post-commit composite
    /// landing — the window in which the sprite must be held at the committed
    /// frame so it doesn't flash. A static click-select sets up a drag preview
    /// (for a possible drag) but must NOT hold the sprite: the sprite is a baked
    /// bitmap CALayer composites in gamma space, which renders semi-transparent
    /// effects (notably shadows) slightly differently than the linear-space CI
    /// composite — so a held sprite makes a selected layer's shadow visibly
    /// darker. Showing the real composite for a static selection avoids that.
    var holdSpriteUntilRender = false

    /// In-progress rotate (knob) or skew (⌥-corner) drag.
    struct TransformDragSession {
        enum Kind {
            case rotate(grabAngle: CGFloat)
            case skew(corner: ResizeHandle, grabPoint: CGPoint)
        }
        let layerID: UUID
        let kind: Kind
        let startTransform: LayerTransform
        let center: CGPoint
        let frameSize: CGSize
        var transform: LayerTransform
    }
    var transformDrag: TransformDragSession?
    /// After a transform commit, the sprite keeps the final delta applied
    /// until the re-rendered composite lands (no flash-back).
    var transformHold: (layerID: UUID, start: LayerTransform, transform: LayerTransform)?

    /// Puts the grid on the right side of the picture.
    ///
    /// Switched ON it goes over the picture, so it is still there once you have
    /// drawn something on top of it. Switched off, when only the surround
    /// carries it, it goes UNDER, so the canvas's own drop shadow falls across
    /// the graph paper and the paper reads as the surface the picture is lying
    /// on. Above `previewSpriteLayer` is exactly where it used to sit, so the
    /// switched-on case is unchanged, and re-ordering only happens when the
    /// side actually changes.
    func placeCanvasGrid(overPicture: Bool) {
        guard let host = layer else { return }
        guard canvasGridOverPicture != overPicture
                || canvasGridContainer.superlayer !== host else { return }
        canvasGridOverPicture = overPicture
        canvasGridContainer.removeFromSuperlayer()
        if overPicture {
            host.insertSublayer(canvasGridContainer, above: previewSpriteLayer)
        } else {
            host.insertSublayer(canvasGridContainer, below: contentLayer)
        }
    }

    /// Maps a document point into the selected layer's untransformed frame
    /// space, so frame-handle hit-testing and resizing agree with where the
    /// (transformed) chrome draws.
    func handleSpacePoint(_ p: CGPoint, layer: Layer?) -> CGPoint {
        guard let layer else { return p }
        return CanvasPointer.handleSpacePoint(p, layer: layer)
    }

    /// The resized frame for a handle drag: the standard opposite-anchor resize,
    /// plus the magnets on the edge the pointer is holding, plus — for text —
    /// width-only sizing with a re-wrapped height (the top edge stays put, the
    /// block grows downward), plus anchor compensation so the corner opposite
    /// the dragged handle stays fixed in screen space under any rotation/skew
    /// (a plain resize would swing it — the "resize after rotate" bug).
    ///
    /// The guides come back with the frame, so the canvas can draw the line
    /// that says what the edge just caught.
    func resizedFrame(for layer: Layer?, start: CGRect, handle: ResizeHandle,
                              pointer p: CGPoint, preserveAspect: Bool,
                              peers: [CGRect] = [], columns: [CGRect] = [],
                              gridSpacing: CGFloat? = nil,
                              gridOrigin: CGPoint = .zero,
                              gridAxes: CanvasGridAxes = .columnsAndRows,
                              holding held: SnapHold = .none)
        -> Snapping.FrameResult {
        let local = handleSpacePoint(p, layer: layer)
        var frame = Handles.resize(start, dragging: handle, to: local, preserveAspect: preserveAspect)
        // The magnets act on the edge the pointer is holding, before anything
        // downstream re-derives a height from it, so a re-wrapped text block is
        // measured at the width the drag actually settled on.
        var result = Snapping.snapResizedFrame(frame, handle: handle,
                                               canvas: viewport?.documentSize ?? .zero,
                                               peers: peers, columnBands: columns,
                                               gridSpacing: gridSpacing,
                                               gridOrigin: gridOrigin,
                                               gridAxes: gridAxes,
                                               zoom: viewport?.zoom ?? 1,
                                               holding: held)
        frame = result.frame
        if let layer, layer.resizeWidthOnly, case .text(let content) = layer.content {
            // Every number here is the box a person SEES: the handles are on
            // the words, so the width dragged out is the words' width and the
            // height handed back is how tall they came out. The room the
            // renderer draws them in goes on top for the measurement, and is
            // taken off again for the answer, so the outline keeps hugging
            // the letters through the whole drag.
            let slack = layer.boxSlack
            let w = max(frame.width, TextMeasurement.minimumContentWidth)
            let measured = TextRasterizer.naturalSize(content, maxWidth: w + slack.width,
                                                      minWidth: TextRasterizer.minimumTextWidth)
            let minX = handle.movesMinX ? frame.maxX - w : frame.minX
            frame = CGRect(x: minX, y: start.minY, width: w,
                           height: max(0, measured.height - slack.height))
        }
        if let layer {
            frame = Handles.anchoredFrame(start: start, proposed: frame, handle: handle,
                                          transform: layer.transform)
        }
        result.frame = frame
        return result
    }

    /// How far apart the lines a drag pulls to are, or nil when nothing is
    /// pulling: the feature off, the grid switched off, Snap to grid switched
    /// off, or nothing on the ladder far enough apart on screen to aim at.
    ///
    /// It follows the ZOOM, because it follows the lines actually drawn: what
    /// a drag lands on is always something you can watch it land on. See
    /// `CanvasGridSettings.snapSpacing(atZoom:)`.
    var canvasSnapSpacing: CGFloat? {
        guard canvasGridEnabled, let viewport else { return nil }
        return canvasGrid?.snapSpacing(atZoom: viewport.zoom)
    }

    /// The grid an arrow key steps by: the same lines, counted from the same
    /// place, as the ones a drag lands on. Nil when nothing is pulling, and
    /// then the keys are the one and ten points they have always been.
    var canvasNudgeGrid: NudgeGrid? {
        guard let spacing = canvasSnapSpacing else { return nil }
        return NudgeGrid(spacing: spacing, origin: canvasSnapOrigin, axes: canvasSnapAxes)
    }

    /// The columns a drag can catch, gathered at grab time.
    ///
    /// Only a screen showing its columns offers any, so a screenshot, a plain
    /// canvas and a screen with the switch off each hand back nothing and drag
    /// exactly as they always have. Switching the columns off is therefore the
    /// whole of "stop pulling": there is no second switch to forget.
    func columnBands(excluding ids: Set<UUID>) -> [CGRect] {
        guard framesEnabled else { return [] }
        return document?.columnBands(excluding: ids) ?? []
    }

    /// Where the grid the drag is pulling to starts. Counting from the same
    /// point the lines are counted from is what keeps a snapped edge ON a line
    /// rather than beside it.
    var canvasSnapOrigin: CGPoint {
        guard canvasGridEnabled else { return .zero }
        return canvasGrid?.origin ?? .zero
    }

    /// Which ways the grid's lines run, so a grid set to columns pulls sideways
    /// and leaves the other axis alone: there is no line across to land on.
    var canvasSnapAxes: CanvasGridAxes {
        canvasGrid?.axes ?? .columnsAndRows
    }

    /// The zero point's own drag: a press anywhere on the canvas picks the
    /// markers up, so there is no one-point line to aim at and the pair is
    /// always exactly where you last put the pointer.
    var gridOriginDragging = false

    /// Move the markers to a point on screen, pulling to the same edges and
    /// middles a dragged layer pulls to: the canvas's, and every layer's. It is
    /// the same call a layer drag makes, with no box around the point. ⌘ drops
    /// the magnets for the rest of the drag, as it does everywhere else.
    func moveGridOrigin(toViewPoint viewPoint: CGPoint, freeing: Bool) {
        guard let viewport, gridOriginAdjust != nil else { return }
        let proposed = viewport.documentPoint(fromView: viewPoint)
        let held = snapHold(freeing: freeing)
        guard !held.isFree else {
            snapGuide = nil
            onGridOriginChange(proposed)
            refreshOverlays()
            return
        }
        // No grid spacing: the zero point catches real edges, never the grid it
        // is itself placing.
        let snapped = Snapping.snapFrameOrigin(proposed, size: .zero,
                                               canvas: viewport.documentSize,
                                               peers: document?.snapPeers(excluding: Set<UUID>()) ?? [],
                                               gridSpacing: nil,
                                               zoom: viewport.zoom,
                                               holding: held)
        snapHold.caught(x: snapped.guideX, y: snapped.guideY)
        snapGuide = (snapped.guideX, snapped.guideY)
        onGridOriginChange(snapped.origin)
        refreshOverlays()
    }

    /// One arrow-key press while the markers are up.
    func nudgeGridOrigin(by delta: CGVector) {
        guard let origin = gridOriginAdjust else { return }
        snapGuide = nil
        onGridOriginChange(CGPoint(x: origin.x + delta.dx, y: origin.y + delta.dy))
        refreshOverlays()
    }

    /// In-progress endpoint drag on a selected line/arrow. The geometry lives
    /// in `AnnotationEndpointDrag` (core, tested); this wraps it with what the
    /// canvas needs for preview styling and Esc-cancel.
    struct EndpointDragSession {
        let layerID: UUID
        /// The layer's content, for styling the vector preview.
        let content: AnnotationContent
        let originalStart: CGPoint
        let originalEnd: CGPoint
        var drag: AnnotationEndpointDrag
    }
    var endpointDrag: EndpointDragSession?
    /// After an endpoint commit, the underlay + vector preview stay up until
    /// the re-rendered composite lands — the sprite can't represent the
    /// re-shaped layer, so this replaces the `previewedFrame` hold.
    var endpointHoldLayerID: UUID?

    // Viewport math is top-left origin; flipping makes view coords match.
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never

        contentLayer.contentsGravity = .resize
        contentLayer.minificationFilter = .linear
        contentLayer.shadowColor = CGColor(gray: 0, alpha: 1)
        contentLayer.shadowOpacity = 0.45
        contentLayer.shadowRadius = 24
        contentLayer.shadowOffset = .zero
        layer?.addSublayer(contentLayer)

        crispLayer.contentsGravity = .resize
        crispLayer.minificationFilter = .linear
        crispLayer.isHidden = true
        layer?.addSublayer(crispLayer)

        previewSpriteLayer.contentsGravity = .resize
        previewSpriteLayer.isHidden = true
        layer?.addSublayer(previewSpriteLayer)

        // The column bands (Next, `next-frames`) sit right on the picture: over
        // everything a person has drawn, because a wash you build against has
        // to survive the first white screen, and UNDER every piece of chrome,
        // so a selection outline, a handle or the yellow line that says which
        // column just caught is never seen through a wash. Their colour lands
        // per refresh, from the surface of the screen they are drawn on.
        columnChromeLayer.strokeColor = nil
        columnChromeLayer.isHidden = true
        layer?.addSublayer(columnChromeLayer)

        // The grid sits on the canvas surface, and which side of the picture
        // that is depends on whether it is switched on over it: see
        // `placeCanvasGrid(overPicture:)`. Either way it is below every piece
        // of chrome, so a selection outline or a measurement is never competing
        // with it. Its colour and strength land per refresh.
        for shape in canvasGridLayers {
            shape.fillColor = nil
            shape.lineWidth = 1
            shape.isHidden = true
            canvasGridContainer.addSublayer(shape)
        }
        layer?.addSublayer(canvasGridContainer)

        annotationPreviewLayer.isHidden = true
        annotationPreviewLayer.lineCap = .round
        annotationPreviewLayer.lineJoin = .round
        annotationPreviewLayer.fillColor = nil
        annotationPreviewHeadLayer.strokeColor = nil
        annotationPreviewLayer.addSublayer(annotationPreviewHeadLayer)
        // Over the shaft, exactly as the rasterizer draws it: the pill covers
        // the round cap at the tail, so the arrow runs into the label.
        captionPreviewLayer.isHidden = true
        annotationPreviewLayer.addSublayer(captionPreviewLayer)
        layer?.addSublayer(annotationPreviewLayer)

        calloutFlightLeaderLayer.fillColor = nil
        calloutFlightLeaderLayer.lineCap = .round
        calloutFlightOutlineLayer.fillColor = nil
        calloutFlightLayer.contentsGravity = .resize
        calloutFlightLayer.masksToBounds = true
        for flightLayer in [calloutFlightLeaderLayer, calloutFlightOutlineLayer, calloutFlightLayer] {
            flightLayer.isHidden = true
            layer?.addSublayer(flightLayer)
        }

        for shape in [collageWellsLayer, slotHighlightLayer,
                      dropLandingLayer, dropHostFrameLayer,
                      selectionBaseLayer, selectionAntsLayer, layerOutlineLayer,
                      multiSelectOutlineLayer, gridSnapLayer, gridOriginLayer,
                      snapGuideLayer, handlesLayer] {
            shape.fillColor = nil
            shape.lineWidth = 1
            shape.isHidden = true
            layer?.addSublayer(shape)
        }
        collageWellsLayer.strokeColor = NSColor.secondaryLabelColor.withAlphaComponent(0.55).cgColor
        collageWellsLayer.lineWidth = 1.5
        collageWellsLayer.lineDashPattern = [6, 4]
        slotHighlightLayer.strokeColor = NSColor.controlAccentColor.cgColor
        slotHighlightLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        slotHighlightLayer.lineWidth = 2
        // The landing box is solid where the thing will be and the host frame
        // is dashed around it, so the two never read as one shape.
        dropLandingLayer.strokeColor = NSColor.controlAccentColor.cgColor
        dropLandingLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        dropLandingLayer.lineWidth = 2
        dropHostFrameLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        dropHostFrameLayer.fillColor = nil
        dropHostFrameLayer.lineWidth = 2
        dropHostFrameLayer.lineDashPattern = [5, 4]
        // Crop chrome stacks above the composite and the selection chrome
        // (which is hidden in crop mode anyway).
        cropDimLayer.fillColor = CGColor(gray: 0, alpha: 0.55)
        cropDimLayer.fillRule = .evenOdd
        cropGridLayer.fillColor = nil
        cropGridLayer.strokeColor = CGColor(gray: 1, alpha: 0.35)
        cropGridLayer.lineWidth = 1
        cropBorderLayer.fillColor = nil
        cropBorderLayer.strokeColor = CGColor(gray: 1, alpha: 1)
        cropBorderLayer.lineWidth = 2
        cropHandlesLayer.fillColor = CGColor(gray: 1, alpha: 1)
        cropHandlesLayer.strokeColor = CGColor(gray: 0, alpha: 0.4)
        cropHandlesLayer.lineWidth = 1
        for cropLayer in [cropDimLayer, cropGridLayer, cropBorderLayer, cropHandlesLayer] {
            cropLayer.isHidden = true
            layer?.addSublayer(cropLayer)
        }

        selectionBaseLayer.strokeColor = CGColor(gray: 1, alpha: 1)
        selectionAntsLayer.strokeColor = CGColor(gray: 0, alpha: 1)
        selectionAntsLayer.lineDashPattern = [4, 4]
        let crawl = CABasicAnimation(keyPath: "lineDashPhase")
        crawl.fromValue = 0
        crawl.toValue = 8
        crawl.duration = 0.4
        crawl.repeatCount = .infinity
        selectionAntsLayer.add(crawl, forKey: "marchingAnts")

        // Selection outline: bright blue, dotted, 2px, 60% opaque.
        layerOutlineLayer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.6).cgColor
        layerOutlineLayer.lineWidth = 2
        layerOutlineLayer.lineCap = .round
        layerOutlineLayer.lineDashPattern = [2, 4]
        // The group you are inside: the same blue, quieter and finer, so it
        // reads as the room you are standing in rather than as a selection.
        groupContextLayer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.28).cgColor
        groupContextLayer.fillColor = nil
        groupContextLayer.lineWidth = 1
        groupContextLayer.lineDashPattern = [1, 3]
        groupContextLayer.isHidden = true
        // Marquee-captured layers share the selection-outline styling.
        multiSelectOutlineLayer.strokeColor = layerOutlineLayer.strokeColor
        multiSelectOutlineLayer.lineWidth = 2
        multiSelectOutlineLayer.lineCap = .round
        multiSelectOutlineLayer.lineDashPattern = [2, 4]
        snapGuideLayer.strokeColor = NSColor.systemYellow.cgColor
        // The lit grid line: the grid's own accent, brought up to full strength
        // from the wash it is drawn at. One point wide and unbroken, like the
        // line underneath it, so it reads as that line lighting up rather than
        // as a second line arriving.
        gridSnapLayer.strokeColor = NSColor.controlAccentColor.cgColor
        // The zero point's two markers: the accent at full strength, twice as
        // wide as a grid line and unbroken, so they never read as two of the
        // lines they are placing.
        gridOriginLayer.strokeColor = NSColor.controlAccentColor.cgColor
        gridOriginLayer.lineWidth = 2
        handlesLayer.fillColor = CGColor(gray: 1, alpha: 1)
        handlesLayer.strokeColor = NSColor.controlAccentColor.cgColor
        rotateKnobLayer.fillColor = CGColor(gray: 1, alpha: 1)
        rotateKnobLayer.strokeColor = NSColor.controlAccentColor.cgColor
        rotateKnobLayer.lineWidth = 1
        rotateKnobLayer.isHidden = true
        layer?.addSublayer(rotateKnobLayer)
        layer?.addSublayer(groupContextLayer)

        // Frame chrome (Next, `next-frames`): the edge hairline under the
        // labels, both above the picture and both out of the export.
        // Mid grey rather than a theme separator: a frame's edge has to read
        // on a white surface and on a dark screenshot alike.
        frameEdgeLayer.strokeColor = CGColor(gray: 0.5, alpha: 0.7)
        frameEdgeLayer.fillColor = nil
        frameEdgeLayer.lineWidth = 1
        frameEdgeLayer.isHidden = true
        layer?.addSublayer(frameEdgeLayer)
        // (The column bands go in near the picture, not here: see the block
        // beside the preview sprite.)
        columnChromeLayer.strokeColor = nil
        columnChromeLayer.isHidden = true
        frameChromeLayer.isHidden = true
        layer?.addSublayer(frameChromeLayer)
        // Component chrome (Next, `next-components`) sits above the frame's,
        // because a promoted frame shows this instead of its own label.
        componentChromeLayer.isHidden = true
        layer?.addSublayer(componentChromeLayer)

        // Hover snap dot: an accent-filled dot with a white ring, on top.
        snapDotLayer.fillColor = NSColor.controlAccentColor.cgColor
        snapDotLayer.strokeColor = CGColor(gray: 1, alpha: 0.95)
        snapDotLayer.lineWidth = 1.5
        snapDotLayer.isHidden = true
        layer?.addSublayer(snapDotLayer)

        // Hover-to-measure readout: outline styling lands per-refresh (it
        // follows the measure style's ink); the caliper sprites sit at reduced
        // opacity so a transient readout never reads as a committed caliper.
        hoverBoundsLayer.lineWidth = 1.5
        for hoverLayer in [hoverBoundsLayer, hoverWidthCaliperLayer, hoverHeightCaliperLayer] {
            hoverLayer.isHidden = true
            hoverLayer.zPosition = 95
            layer?.addSublayer(hoverLayer)
        }
        hoverWidthCaliperLayer.opacity = 0.85
        hoverHeightCaliperLayer.opacity = 0.85

        // Alignment-guide drag preview: dashed, in the measure ink (set per
        // refresh), above the composite but under handles/snap chrome.
        alignmentPreviewLayer.fillColor = nil
        alignmentPreviewLayer.lineDashPattern = [6, 4]
        alignmentPreviewLayer.lineCap = .round
        alignmentPreviewLayer.isHidden = true
        alignmentPreviewLayer.zPosition = 95
        layer?.addSublayer(alignmentPreviewLayer)

        // Selection handles and the snap dot sit above every other overlay.
        // (A caliper's head dot is not drawn while its readout pill covers
        // it, see `drawnMeasureHandles`, so nothing here draws on a number.)
        handlesLayer.zPosition = 100
        snapDotLayer.zPosition = 100

        registerForDraggedTypes([.fileURL, ComponentDrag.pasteboardType])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Light to dark and back: the grid's ink is mixed against the window's
    /// appearance, so it is drawn again rather than left in yesterday's theme.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshOverlays()
    }


    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange(window)
    }

    override func layout() {
        super.layout()
        if bounds.size != lastReportedSize {
            lastReportedSize = bounds.size
            onViewSizeChange(bounds.size)
        }
    }


    var hoverTrackingArea: NSTrackingArea?

    /// The cursor currently forced onto the pointer by `applyGrabCursor`, so a
    /// move that changes nothing leaves the cursor alone and clearing it can
    /// hand control back to the tool's cursor rects.
    var grabCursor: NSCursor?

#if PHOTONZ_PLAYTEST
    /// What the canvas last decided was under the pointer, in words, so a walk
    /// can tell "the cue was wrong" apart from "the cue was right and the
    /// pointer did not follow it". A walk's pointer is synthesized, so this is
    /// recorded as the cue is read rather than re-derived from where the real
    /// OS pointer happens to be.
    private(set) var playtestPointerCue = "none"

    func recordPlaytestCue(_ hit: (cue: CanvasPointerCue, transform: LayerTransform)?) {
        guard let hit else { return playtestPointerCue = "none" }
        switch hit.cue {
        case .grab: playtestPointerCue = "grab"
        case .rotate: playtestPointerCue = "rotate"
        case .resize(let handle):
            playtestPointerCue = "resize-"
                + Handles.screenHandle(for: handle, transform: hit.transform).axis.rawValue
        }
    }
#endif

    func viewRect(forDocRect r: CGRect, in viewport: Viewport) -> CGRect {
        let topLeft = viewport.viewPoint(fromDocument: r.origin)
        return CGRect(x: topLeft.x, y: topLeft.y,
                      width: r.width * viewport.zoom, height: r.height * viewport.zoom)
    }
}
