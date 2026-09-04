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
    let onSelectionChange: (SelectionRegion?, Bool) -> Void
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
    let onAddSweptLayers: (SelectionRegion) -> Void
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
                   lumaField: lumaField, isCanvasSelected: isCanvasSelected)
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
    }
}

// The Measure tool's share of this view lives in CanvasMeasure.swift: the
// Size and Gap hover previews, the three-click caliper placement, the
// alignment-guide drag and a placed caliper's handle geometry. The members
// below that carry no `private` are the ones that file reaches for; they are
// still this view's alone, and nothing else in the app should touch them.
final class CanvasNSView: NSView {
    var onViewSizeChange: ((CGSize) -> Void) = { _ in }
    var onViewportChange: ((Viewport) -> Void) = { _ in }
    var onSelectionChange: ((SelectionRegion?, Bool) -> Void) = { _, _ in }
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
    var onAddSweptLayers: ((SelectionRegion) -> Void) = { _ in }
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

    private let contentLayer = CALayer()
    /// The visible part of the document redrawn at the zoom, laid exactly over
    /// the stretched composite underneath it. Same picture, more pixels.
    private let crispLayer = CALayer()
    private var crispTile: CrispTile?
    private var crispTileViewport: Viewport?
    /// Floats the dragged layer's pre-rendered sprite over the underlay during
    /// drags — positioned in pure Core Animation, no per-move rendering.
    private let previewSpriteLayer = CALayer()
    /// Marching ants: a solid white stroke underneath…
    private let selectionBaseLayer = CAShapeLayer()
    /// …and animated black dashes on top, giving the classic alternating crawl.
    private let selectionAntsLayer = CAShapeLayer()
    /// Accent outline around the selected layer.
    private let layerOutlineLayer = CAShapeLayer()
    /// Outlines around every layer the marquee fully contains (rubber-band
    /// multi-selection) — live during the drag, standing once committed, so
    /// it's obvious what ⌫ will delete.
    private let multiSelectOutlineLayer = CAShapeLayer()
    /// The eight resize handles on the selected layer's outline.
    private let handlesLayer = CAShapeLayer()
    /// Rotate knob: a circle floated off the layer's top edge plus its stem.
    private let rotateKnobLayer = CAShapeLayer()
    /// The faint box around the group you are currently INSIDE, so descending
    /// into one is visible rather than a mode you have to remember.
    let groupContextLayer = CAShapeLayer()
    /// A frame's name, above its top left corner: one text sublayer per frame.
    let frameChromeLayer = CALayer()
    /// The hairline at every frame's edge, so a screen has a visible boundary
    /// even where its surface matches the canvas behind it.
    let frameEdgeLayer = CAShapeLayer()
    /// A main component's mark and name, above its top left corner: one glyph
    /// and one text sublayer per component.
    let componentChromeLayer = CALayer()
    /// Snap guides shown while a move drag is captured by an edge/center.
    private let snapGuideLayer = CAShapeLayer()
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
    private let collageWellsLayer = CAShapeLayer()
    /// The collage slot a drag (file drop / photo layer / slot swap) is
    /// currently over — filled accent highlight.
    private let slotHighlightLayer = CAShapeLayer()
    /// The screen a drag holding these boxes would join, nil when it would
    /// change nothing. Asked once per mouse move, so it is skipped outright in
    /// a document that has no screens in it — which is every screenshot
    /// anybody has taken.
    private func adoptionHost(moving boxes: [UUID: CGRect]) -> UUID? {
        guard framesEnabled, !boxes.isEmpty, let document, document.hasFrames else { return nil }
        return document.frameAdoptionHost(moving: boxes)
    }

    /// What the canvas is currently promising a move drag, for a playtest to
    /// read back.
    var adoptionHostDescription: UUID? { adoptionHost }

    /// Where whatever is being dragged over the canvas would land: an outline
    /// the exact size of the thing, in the exact spot letting go would put it.
    private let dropLandingLayer = CAShapeLayer()
    /// The frame it would join, lit up so joining a screen is visible before
    /// the button comes up rather than discovered afterwards.
    private let dropHostFrameLayer = CAShapeLayer()
    /// What the canvas is promising the drag in the air: the box it would fill
    /// and the frame it would join. Nil whenever no drag is over this canvas.
    /// A component off the Library shelf and a picture from the Finder both
    /// write here, because a person letting go wants the same answer either
    /// way: where does this land, and how big is it.
    private var dropLanding: (rect: CGRect, host: UUID?)?
    /// The file the drag in flight is carrying and what the canvas can make of
    /// it, kept for the life of that one drag session. See `draggedFile`.
    private var draggedImage: (sequence: Int, url: URL, drop: CanvasFileDrop)?

    /// The screen a move drag in flight would drop what it carries INTO,
    /// outlined while the pointer is still down. Without it the drop changes
    /// what holds a layer with nothing on screen having said so. It is the same
    /// dashed box a component dragged off the Library shelf draws, because it
    /// is the same promise. See `FrameAdoption.swift`.
    private var adoptionHost: UUID?
    /// Crop mode chrome: dimmed surround (even-odd fill), thirds grid,
    /// border, and handles.
    private let cropDimLayer = CAShapeLayer()
    private let cropGridLayer = CAShapeLayer()
    private let cropBorderLayer = CAShapeLayer()
    private let cropHandlesLayer = CAShapeLayer()
    /// Live preview of an in-progress drag-to-create annotation.
    let annotationPreviewLayer = CAShapeLayer()
    /// Arrowheads are filled but never stroked (matching the rasterizer), so
    /// they need their own shape layer under the stroked shaft.
    let annotationPreviewHeadLayer = CAShapeLayer()
    /// A just-created zoom callout flying from its source box to its placed
    /// frame: the magnified sprite, plus the source outline and leader lines
    /// fading in underneath it.
    private let calloutFlightLayer = CALayer()
    private let calloutFlightOutlineLayer = CAShapeLayer()
    private let calloutFlightLeaderLayer = CAShapeLayer()
    /// The pre-commit composite, held on screen for the flight's duration so
    /// the baked-in callout doesn't show at its destination mid-flight.
    private var calloutHoldImage: CGImage?
    /// Invalidates a flight's completion cleanup when a newer flight starts.
    private var calloutFlightGeneration = 0
    private var lastReportedSize: CGSize = .zero
    /// The viewport currently on screen. Gesture handlers mutate from this and
    /// apply locally before notifying, so panning/zooming never waits a runloop
    /// tick for SwiftUI to echo the state back.
    var viewport: Viewport?
    private var image: CGImage?
    /// Committed document (hit-testing source). Previews never land here.
    var document: PhotonzDocument?
    /// Committed selection region in document coordinates.
    private var selection: SelectionRegion?
    /// Whether the committed region has pixel semantics (region tools) —
    /// routes ⌫/⌥⌫ to region ops instead of layer ops.
    private var selectionTargetsPixels = false
    /// Pending crop rect (document coordinates), echoed from EditorState.
    private var cropRect: CGRect?
    /// Crop aspect lock, echoed from EditorState; drags constrain through it.
    private var cropAspect: CropAspect = .free
    /// Crop confinement (canvas, or the target layer's frame), echoed from
    /// EditorState. Nil falls back to the full document.
    private var cropBounds: CGRect?

    /// In-progress crop-rect drag. `startRect` restores on Esc and on
    /// click-without-drag.
    private struct CropDrag {
        enum Kind {
            case resize(ResizeHandle)
            case move
            case define(anchor: CGPoint)
        }
        let kind: Kind
        let startRect: CGRect?
        var lastPoint: CGPoint
    }
    private var cropDrag: CropDrag?
    /// Selected layer (committed state, echoed from EditorState).
    private(set) var selectedLayerID: UUID?
    /// Selected layer's frame in document coordinates (committed state).
    private var selectedLayerFrame: CGRect?
    /// The group the pointer is inside, echoed from EditorState (`CanvasGroups.swift`).
    private(set) var groupContext: UUID?
    /// The marquee's multi-selection, echoed from EditorState (committed).
    /// Read by the frame chrome too, so every picked screen's name tints.
    private(set) var multiSelectedLayerIDs: Set<UUID> = []
    /// Every layer currently picked, however it got there: the multi-selection
    /// plus the single primary selection. What a ⇧-sweep adds to.
    private var pickedLayerIDs: Set<UUID> {
        multiSelectedLayerIDs.union(selectedLayerID.map { [$0] } ?? [])
    }
    /// Pre-rendered drag preview from EditorState; arrives async after drag start
    /// and outlives the drag until the post-commit render lands.
    private var dragPreview: DragPreview?
    /// In-progress marquee (document coordinates). While set, it is what the
    /// ants display — same zero-latency-echo pattern as pan/zoom.
    private var marquee: MarqueeDrag?
    /// What the press that started `marquee` meant for the selection, latched
    /// at gesture start: plain replaces it, ⇧ spares it (a ⇧-click that missed
    /// the layer it was aimed at).
    private var marqueePress: BareCanvasPress = .replaces
    /// In-progress region-select drag (rect/ellipse tools). The combine mode
    /// is latched from the modifiers at gesture start (⇧ add, ⌥ subtract,
    /// ⇧⌥ intersect); the ants preview the live boolean combination.
    private var regionDrag: (drag: MarqueeDrag, mode: SelectionRegion.Mode, isEllipse: Bool)?
    /// Live modifier state, for the selection cursor's +/−/× badge.
    private var pointerModifiers: NSEvent.ModifierFlags = []
    /// In-flight region CONTENT move (select tool dragging inside a pixel
    /// region — Photoshop Move-tool semantics). EditorState holds the lifted
    /// bitmaps; `frame` is the content's doc frame at drag start.
    private var regionContentDrag: (start: CGPoint, current: CGPoint, frame: CGRect)?
    /// Post-commit sprite hold for a region move: the content frame isn't the
    /// layer frame, so the standard selectedLayerFrame hold can't cover it.
    private var regionMoveHoldFrame: CGRect?
    /// In-flight outline-only move (marquee tool plain-drag starting inside
    /// the region): moves the ants, never pixels (Photoshop).
    private var regionOutlineDrag: (start: CGPoint, current: CGPoint, base: SelectionRegion)?

    /// Whole-pixel drag delta so moved content/outlines stay pixel-aligned.
    private func roundedDelta(from start: CGPoint, to current: CGPoint) -> CGPoint {
        CGPoint(x: (current.x - start.x).rounded(), y: (current.y - start.y).rounded())
    }
    /// The active tool, echoed from EditorState. Annotation tools reroute the
    /// pointer from hit-test/marquee into drag-to-create.
    var tool: Tool = .select
    private var captionCloseRequest = 0
    /// In-progress drag-to-create (document coordinates).
    private var annotationDrag: AnnotationDrag?
    /// Set by a press that committed the fresh arrow's caption field with the
    /// Arrow tool still in hand; mouse-up decides whether it was a click (hand
    /// back to Select) or a drag (the next arrow).
    private var pressClosedCaptionField = false
    /// Styled content for the active tool, echoed from EditorState; the in-flight
    /// preview strokes with this so it matches the committed rasterization.
    private var annotationContent: AnnotationContent?
    /// What the Zoom Callout tool is set to draw, echoed from EditorState. The
    /// drag box previews in it and the creation flight lands in it, so choosing
    /// Circle is visible from the first drag rather than after it.
    private var calloutShape: ZoomCalloutShape = .rectangle
    /// The draft layer style for the active shape tool (border/corner radius);
    /// the create preview draws its border so outline-only rectangles show.
    private var annotationStyle: LayerStyle?
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
    private var measureHandleDrag: MeasureHandleDrag?
    /// Dragging a selected arrow's caption pill to the spot you want (Next
    /// `next-arrow-captions`). The grip is kept, like the caliper's readout
    /// grab: a pill taken hold of near its edge stays under the pointer.
    private struct CaptionDrag {
        let layerID: UUID
        /// Pointer minus pill center at the grab, document space.
        let grip: CGSize
        let startCenter: CGPoint
        var current: CGPoint
        /// Where the pill centers with this drag applied.
        var center: CGPoint { CGPoint(x: current.x - grip.width, y: current.y - grip.height) }
    }
    private var captionDrag: CaptionDrag?
    /// Detected UI edges, mirrored from EditorState; measure corners magnetize to
    /// these (and the pixel grid) while dragging.
    var edgeMap = EdgeMap.empty
    var lumaField = LumaField.empty
    /// Document-space x/y of the edge(s) a measure corner is currently snapped to,
    /// drawn as a highlight while the corner is held. Cleared on mouse-up.
    var snapGuide: (x: CGFloat?, y: CGFloat?)?
    /// Decayed accumulator of recent drag motion (doc px). When the user is
    /// clearly resizing along ONE axis, the perpendicular axis stops grabbing
    /// edges — dragging a leg up/down shouldn't flash vertical snap guides.
    private var dragMotion = CGVector.zero
    private var lastDragPoint: CGPoint?
    /// In-flight swap drag: a filled slot of the SELECTED collage picked up.
    private var slotDrag: (collageID: UUID, from: Int)?
    /// The slot any eligible drag is currently hovering (drop/absorb/swap target).
    private var hoverSlot: (collageID: UUID, index: Int)?
    /// The Canvas pseudo-selection, echoed from EditorState: boundary handles
    /// on the document rect; drags resize the canvas itself.
    private var isCanvasSelected = false
    /// In-flight canvas-boundary resize: the proposed rect may grow in any
    /// direction (negative origin = space added on the left/top); commit maps
    /// it to setCanvasSize + the anchor opposite the dragged handle — or
    /// `.center` when ⇧ made the drag symmetric (content stays centered).
    private var canvasResizeDrag: (handle: ResizeHandle, rect: CGRect, centered: Bool)?

    /// Suppresses edge captures on the axis perpendicular to decisive motion.
    /// The suppressed axis falls back to the pixel grid.
    func axisGated(_ snap: EdgeSnapping.Snap, raw p: CGPoint) -> EdgeSnapping.Snap {
        var snap = snap
        let ax = abs(dragMotion.dx), ay = abs(dragMotion.dy)
        if ay > 2 * ax, ay > 2, snap.guideX != nil {
            snap.point.x = p.x.rounded()
            snap.guideX = nil
        } else if ax > 2 * ay, ax > 2, snap.guideY != nil {
            snap.point.y = p.y.rounded()
            snap.guideY = nil
        }
        return snap
    }

    /// Feeds the motion accumulator; call once per mouseDragged before snapping.
    func trackDragMotion(_ p: CGPoint) {
        if let last = lastDragPoint {
            dragMotion.dx = dragMotion.dx * 0.7 + (p.x - last.x)
            dragMotion.dy = dragMotion.dy * 0.7 + (p.y - last.y)
        }
        lastDragPoint = p
    }

    func resetDragMotion(_ p: CGPoint) {
        dragMotion = .zero
        lastDragPoint = p
    }

    /// A captioned arrow's pill footprint in document space (the same estimate
    /// the model hits and reserves with). Dragging it moves the label.
    private func captionPillRect(_ layer: Layer) -> CGRect? {
        guard let a = layer.annotation, a.hasCaption else { return nil }
        let anchor = a.captionAnchor()
        let size = a.estimatedCaptionSize
        return CGRect(x: layer.frame.minX + anchor.x - size.width / 2,
                      y: layer.frame.minY + anchor.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// The composite that was on screen when an annotation was committed. The
    /// preview shape stays up until a *different* image arrives, so the new
    /// annotation doesn't flash out while the re-render is in flight.
    private var annotationCommitImage: CGImage?
    /// Current text style, echoed from EditorState; the inline editor restyles
    /// live when the font picker changes it. The string field is ignored.
    private var textContent: TextContent?

    /// In-progress inline text edit (or arrow caption entry, which reuses the
    /// same editor overlay).
    private struct TextEditSession {
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
    private var textSession: TextEditSession?
    /// The session's editor overlay, positioned/scaled to track the viewport.
    private var textEditor: NSTextView?
    /// The bubble drawn behind an arrow caption's editor, so the draft sits in
    /// the same pill the committed caption renders in. Nil for text sessions.
    private var captionPill: CaptionPillView?
    /// The zoom `textEditor`'s font was last scaled for.
    private var textEditorZoom: CGFloat = 0
    /// The style `textEditor` was last configured with (string empty), so
    /// font-picker changes mid-edit restyle the draft exactly once.
    private var textEditorContent: TextContent?

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
    private struct MoveDrag {
        let layerID: UUID
        /// Pointer offset from the frame origin at grab time (doc coords).
        let grabOffset: CGPoint
        let size: CGSize
        let startOrigin: CGPoint
        /// The boxes this drag can line itself up with, in canvas coordinates.
        /// Gathered ONCE at grab time: nothing but the dragged layer moves
        /// during a drag, so a crowded document costs nothing per frame.
        var peers: [CGRect] = []
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
    private var moveDrag: MoveDrag?

    /// In-progress move of a whole multi-selection. What is being dragged is
    /// the BOX the selection makes: every member is offset by the same amount,
    /// so the group of layers keeps its shape and lines up by its outer edges
    /// rather than by whichever piece happens to be under the pointer.
    private struct MultiMoveDrag {
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
    private var multiMove: MultiMoveDrag?

    /// In-progress handle resize.
    private struct ResizeDrag {
        let layerID: UUID
        let handle: ResizeHandle
        let startFrame: CGRect
        var frame: CGRect
    }
    private var resizeDrag: ResizeDrag?

    /// True only between a move/resize COMMIT and the post-commit composite
    /// landing — the window in which the sprite must be held at the committed
    /// frame so it doesn't flash. A static click-select sets up a drag preview
    /// (for a possible drag) but must NOT hold the sprite: the sprite is a baked
    /// bitmap CALayer composites in gamma space, which renders semi-transparent
    /// effects (notably shadows) slightly differently than the linear-space CI
    /// composite — so a held sprite makes a selected layer's shadow visibly
    /// darker. Showing the real composite for a static selection avoids that.
    private var holdSpriteUntilRender = false

    /// In-progress rotate (knob) or skew (⌥-corner) drag.
    private struct TransformDragSession {
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
    private var transformDrag: TransformDragSession?
    /// After a transform commit, the sprite keeps the final delta applied
    /// until the re-rendered composite lands (no flash-back).
    private var transformHold: (layerID: UUID, start: LayerTransform, transform: LayerTransform)?

    /// Maps a document point into the selected layer's untransformed frame
    /// space, so frame-handle hit-testing and resizing agree with where the
    /// (transformed) chrome draws.
    private func handleSpacePoint(_ p: CGPoint, layer: Layer?) -> CGPoint {
        guard let layer else { return p }
        return CanvasPointer.handleSpacePoint(p, layer: layer)
    }

    /// The resized frame for a handle drag: the standard opposite-anchor resize,
    /// plus — for text — width-only sizing with a re-wrapped height (the top edge
    /// stays put, the block grows downward), plus anchor compensation so the
    /// corner opposite the dragged handle stays fixed in screen space under any
    /// rotation/skew (a plain resize would swing it — the "resize after rotate"
    /// bug).
    private func resizedFrame(for layer: Layer?, start: CGRect, handle: ResizeHandle,
                             pointer p: CGPoint, preserveAspect: Bool) -> CGRect {
        let local = handleSpacePoint(p, layer: layer)
        var frame = Handles.resize(start, dragging: handle, to: local, preserveAspect: preserveAspect)
        if let layer, layer.resizeWidthOnly, case .text(let content) = layer.content {
            let w = max(frame.width, TextRasterizer.minimumTextWidth)
            let measured = TextRasterizer.naturalSize(content, maxWidth: w,
                                                      minWidth: TextRasterizer.minimumTextWidth)
            let minX = handle.movesMinX ? frame.maxX - w : frame.minX
            frame = CGRect(x: minX, y: start.minY, width: w, height: measured.height)
        }
        if let layer {
            frame = Handles.anchoredFrame(start: start, proposed: frame, handle: handle,
                                          transform: layer.transform)
        }
        return frame
    }

    /// In-progress endpoint drag on a selected line/arrow. The geometry lives
    /// in `AnnotationEndpointDrag` (core, tested); this wraps it with what the
    /// canvas needs for preview styling and Esc-cancel.
    private struct EndpointDragSession {
        let layerID: UUID
        /// The layer's content, for styling the vector preview.
        let content: AnnotationContent
        let originalStart: CGPoint
        let originalEnd: CGPoint
        var drag: AnnotationEndpointDrag
    }
    private var endpointDrag: EndpointDragSession?
    /// After an endpoint commit, the underlay + vector preview stay up until
    /// the re-rendered composite lands — the sprite can't represent the
    /// re-shaped layer, so this replaces the `previewedFrame` hold.
    private var endpointHoldLayerID: UUID?

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

        annotationPreviewLayer.isHidden = true
        annotationPreviewLayer.lineCap = .round
        annotationPreviewLayer.lineJoin = .round
        annotationPreviewLayer.fillColor = nil
        annotationPreviewHeadLayer.strokeColor = nil
        annotationPreviewLayer.addSublayer(annotationPreviewHeadLayer)
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
                      multiSelectOutlineLayer, snapGuideLayer, handlesLayer] {
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

    // MARK: - Drag destination (drop an image to add it as a layer)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if droppedComponent(sender) != nil { return trackComponentDrag(sender) }
        return trackImageDrag(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        // A component off the shelf lands wherever the pointer is: there is no
        // collage slot to highlight, and the copy is centred on the drop. What
        // it needs instead is the box it would fill and the frame it would
        // join, drawn while the button is still down.
        if droppedComponent(sender) != nil { return trackComponentDrag(sender) }
        return trackImageDrag(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hoverSlot = nil
        dropLanding = nil
        draggedImage = nil
        refreshOverlays()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hoverSlot = nil
        dropLanding = nil
        draggedImage = nil
        refreshOverlays()
        if let componentID = droppedComponent(sender) {
            return dropComponent(componentID, atViewPoint: convert(sender.draggingLocation, from: nil))
        }
        // The same reading the pointer answered with: a file the canvas refused
        // in the air is refused on the way down too, so nothing can slip past a
        // no-entry pointer and land anyway.
        guard let url = droppedURL(sender) else { return false }
        let file = CanvasFileDrop.of(url)
        guard file.isAccepted else { return false }
        if file != .package, let target = dropTarget(for: sender) {
            onDropImageURLIntoCollage(url, target.collageID, target.index)
        } else if let viewport {
            onDropImageURL(url, viewport.documentPoint(fromView: convert(sender.draggingLocation, from: nil)))
        } else {
            return false
        }
        return true
    }

    private func dropTarget(for sender: NSDraggingInfo) -> (collageID: UUID, index: Int)? {
        guard let viewport else { return nil }
        let p = viewport.documentPoint(fromView: convert(sender.draggingLocation, from: nil))
        return collageSlotTarget(at: p)
    }

    /// The component a drag off the Library shelf is carrying, nil for
    /// everything else. Its own pasteboard type, so a dropped file and a
    /// dropped component can never be mistaken for each other.
    private func droppedComponent(_ sender: NSDraggingInfo) -> UUID? {
        ComponentDrag.componentID(on: sender.draggingPasteboard)
    }

    /// Follows a component drag across the canvas: works out the box the copy
    /// would fill and the frame it would join, draws both, and answers the drag
    /// with what letting go here would actually do. A drop that would be
    /// refused (a copy landing inside its own original) says so with the
    /// ordinary no-entry pointer instead of accepting the drag and scolding
    /// afterwards.
    private func trackComponentDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let componentID = droppedComponent(sender) else {
            dropLanding = nil
            refreshOverlays()
            return []
        }
        return trackComponentDrag(componentID,
                                  atViewPoint: convert(sender.draggingLocation, from: nil))
    }

    /// The same tracking from a point in this view. Internal so a playtest can
    /// hold a component over the canvas without synthesising a drag session,
    /// which is the only way to photograph what a drag looks like mid air.
    @discardableResult
    func trackComponentDrag(_ componentID: UUID, atViewPoint viewPoint: CGPoint) -> NSDragOperation {
        guard let viewport, let document else {
            dropLanding = nil
            refreshOverlays()
            return []
        }
        let point = viewport.documentPoint(fromView: viewPoint)
        let target = document.componentDropTarget(of: componentID, at: point)
        guard target != .refused,
              let size = document.componentDropSize(of: componentID,
                                                    measure: { TextRasterizer.naturalSize($0) }) else {
            dropLanding = nil
            refreshOverlays()
            return []
        }
        let host: UUID? = if case .frame(let id) = target { id } else { nil }
        dropLanding = (CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                              width: size.width, height: size.height),
                       host)
        refreshOverlays()
        return .copy
    }

    /// What the canvas is currently showing the drag in the air: the box it
    /// would fill and the frame it would join, for a playtest to read back.
    var dropLandingDescription: (rect: CGRect, host: UUID?)? { dropLanding }

    /// Places a copy at a point in this view, which is what a drag from the
    /// shelf ends in. Internal so a playtest can land the same drop without
    /// synthesising a drag session.
    func dropComponent(_ componentID: UUID, atViewPoint point: CGPoint) -> Bool {
        guard let viewport else { return false }
        onDropComponent(componentID, viewport.documentPoint(fromView: point))
        return true
    }

    /// Follows a file dragged in from the Finder (or off the Library shelf,
    /// which carries a file too) across the canvas, and draws the box letting
    /// go here would fill.
    ///
    /// A picture arriving from outside is fitted to the screen under the
    /// pointer, or to the canvas when there is no screen there, and nudged
    /// wholly inside it — so how big it lands is not something you can work out
    /// by looking at the file. Drawing the real box removes the surprise, and
    /// it is drawn from the very call the drop makes (`placementForIncomingImage`)
    /// so the promise and the result cannot drift apart.
    ///
    /// Two cases deliberately draw nothing. Over a collage slot the drop fills
    /// that slot instead, and the slot lights up to say so; a second box would
    /// promise something else. And a `.photonz` file opens a window rather than
    /// landing on this canvas.
    ///
    /// A file the canvas can do nothing with — a text file, an archive, a
    /// folder — is refused from the moment it is over the canvas, so the
    /// pointer shows the no-entry sign instead of a copy badge that promises a
    /// layer and then leaves nothing behind.
    private func trackImageDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let url = droppedURL(sender),
              draggedFile(url, sequence: sender.draggingSequenceNumber).isAccepted else {
            dropLanding = nil
            hoverSlot = nil
            refreshOverlays()
            return []
        }
        // Highlight the collage slot under the pointer — dropping there fills
        // the slot instead of adding a floating layer.
        hoverSlot = dropTarget(for: sender)
        dropLanding = hoverSlot == nil ? landingForFile(url, sender: sender) : nil
        refreshOverlays()
        return .copy
    }

    /// The box the file under the pointer would land in, in canvas
    /// coordinates, and the screen it would join.
    private func landingForFile(_ url: URL, sender: NSDraggingInfo) -> (rect: CGRect, host: UUID?)? {
        guard let viewport, let document,
              let size = draggedFile(url, sequence: sender.draggingSequenceNumber).pictureSize
        else { return nil }
        let point = viewport.documentPoint(fromView: convert(sender.draggingLocation, from: nil))
        let rect = document.placementForIncomingImage(size: size, at: point)
        guard !rect.isEmpty else { return nil }
        return (rect, document.frameID(under: point))
    }

    /// What the file on the pasteboard is, read once per drag.
    /// `draggingUpdated` fires on every mouse move and the file cannot change
    /// under it, so reading the header again on each one would be pure waste.
    /// A refusal is remembered too: a file that is not a picture stays not a
    /// picture, and re-reading it on every move to be told so again is the
    /// same waste.
    private func draggedFile(_ url: URL, sequence: Int) -> CanvasFileDrop {
        if let measured = draggedImage, measured.sequence == sequence, measured.url == url {
            return measured.drop
        }
        let drop = CanvasFileDrop.of(url)
        draggedImage = (sequence, url, drop)
        return drop
    }

    private func droppedURL(_ sender: NSDraggingInfo) -> URL? {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true])?.first as? URL
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

    // MARK: Hover snap dot (measure tool)

    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited,
                                            .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        handleMeasureHover(event)
        refreshNameLabelHover(at: convert(event.locationInWindow, from: nil))
        refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoverPoint = nil
        refreshNameLabelHover(at: nil)
        applyGrabCursor(nil)
        if tool == .measure { refreshMeasureCreation(modifierFlags: event.modifierFlags) }
    }

    // MARK: Pointer cue (what every handle says it does)

    /// The cursor currently forced onto the pointer by `applyGrabCursor`, so a
    /// move that changes nothing leaves the cursor alone and clearing it can
    /// hand control back to the tool's cursor rects.
    private var grabCursor: NSCursor?

    /// What a press at `p` (document coords) would take hold of, for cue
    /// purposes: a caption pill, or a caliper's number, feet or head dot, on
    /// the SELECTED layer. Nil for every other press.
    private func grabCue(at p: CGPoint) -> CanvasGrab? {
        guard Experiments.shared.grabCueEnabled, tool == .select, let viewport,
              let layer = selectedLayerID.flatMap({ id in document?.canvasLayer(id: id) })
        else { return nil }
        return CanvasGrab.hit(at: p, layer: layer, zoom: viewport.zoom,
                               captionsEnabled: Experiments.shared.arrowCaptionsEnabled)
    }

    /// What a press at `p` (document coords) would do, and the transform to
    /// read it through — the whole answer the pointer gives, for every handle
    /// on the canvas rather than just the ones you drag with a hand.
    ///
    /// The order MIRRORS `mouseDown`: the canvas's own boundary handles are
    /// captured before anything else, then the selected layer's handles in
    /// `CanvasPointer`'s order. A cue that ran ahead of the press would be
    /// confidently wrong about the one thing it exists to answer.
    private func pointerCue(at p: CGPoint) -> (cue: CanvasPointerCue, transform: LayerTransform)? {
        guard Experiments.shared.grabCueEnabled, let viewport else { return nil }
        // Crop is its own mode with its own pointer, and its crosshair keeps
        // every spot the crosshair is still true of: inside the box, where a
        // press moves it, and outside, where a press draws a fresh one. It
        // gives way only on the eight handles, which are the one press you
        // cannot see coming. The box is axis-aligned, so no transform.
        if tool == .crop {
            return CanvasPointer.cropCue(at: p, cropRect: cropRect, zoom: viewport.zoom)
                .map { ($0, .identity) }
        }
        guard tool == .select else { return nil }
        if isCanvasSelected,
           let handle = Handles.hit(at: p, frame: CGRect(origin: .zero, size: viewport.documentSize),
                                    zoom: viewport.zoom, screenTolerance: 8) {
            return (.resize(handle), .identity)
        }
        guard let layer = selectedLayerID.flatMap({ id in document?.canvasLayer(id: id) })
        else { return nil }
        // No live frame means no frame handles were offered, so none is cued.
        let cue = CanvasPointer.cue(at: p, layer: layer, frame: selectedLayerFrame,
                                    zoom: viewport.zoom,
                                    captionsEnabled: Experiments.shared.arrowCaptionsEnabled,
                                    offersRotation: offersRotation(layer))
        return cue.map { ($0, layer.transform) }
    }

    /// Whether this event asks for the drag to leave the original behind and
    /// carry a copy (⌥, the Photoshop and Figma gesture). Select only: every
    /// other tool has its own meaning for ⌥, and the ones on the canvas that
    /// do — skewing from a corner handle, the region tools — are read before
    /// a layer drag can ever start.
    private func copyDragModifier(_ event: NSEvent) -> Bool {
        tool == .select && event.modifierFlags.contains(.option)
    }

    /// Whether a press at `p` (document coords) would start a layer drag that
    /// ⌥ could copy: something pickable, and not one of the selected layer's
    /// own handles, where ⌥ already means skew.
    private func copyDragCue(at p: CGPoint) -> Bool {
        guard tool == .select, let viewport,
              groupAwarePick(at: p, zoom: viewport.zoom) != nil else { return false }
        let selected = selectedLayerID.flatMap { id in document?.canvasLayer(id: id) }
        guard let frame = selectedLayerFrame, selected?.allowsFrameResize ?? true,
              Handles.hit(at: handleSpacePoint(p, layer: selected),
                          frame: frame, zoom: viewport.zoom) != nil else { return true }
        return false
    }

    /// Every handle on the canvas says what it does before you press it: an
    /// open hand over the parts that drag on their own (a pill, one of a
    /// caliper's dots, either end of a line), the platform's resize arrows over
    /// the eight handles round a frame, and a curved arrow over the rotate
    /// knob. Nothing else on the canvas says a small square on top of a big
    /// object is a different press, so this is the whole invitation.
    ///
    /// A drag in flight keeps the pointer it started with — the hand closes,
    /// resize and rotate hold — so nothing switches under way. That is why
    /// every drag session bails out here rather than re-reading the pointer.
    private func refreshGrabCursor(at viewPoint: CGPoint? = nil) {
        guard captionDrag == nil, measureHandleDrag == nil, resizeDrag == nil,
              endpointDrag == nil, transformDrag == nil, canvasResizeDrag == nil,
              cropDrag == nil else { return }
        let point = viewPoint ?? window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        guard let viewport, let point, bounds.contains(point) else { return applyGrabCursor(nil) }
        let doc = viewport.documentPoint(fromView: point)
        let hit = pointerCue(at: doc)
        #if PHOTONZ_PLAYTEST
        recordPlaytestCue(hit)
        #endif
        if let hit {
            return applyGrabCursor(CanvasCursor.cursor(for: hit.cue, transform: hit.transform))
        }
        // Nothing on the canvas says a drag can leave a copy behind, so the
        // badged pointer is the whole invitation: hold ⌥ over a layer and the
        // cursor answers before you have pressed anything.
        applyGrabCursor(pointerModifiers.contains(.option) && copyDragCue(at: doc) ? .dragCopy : nil)
    }

#if PHOTONZ_PLAYTEST
    /// What the canvas last decided was under the pointer, in words, so a walk
    /// can tell "the cue was wrong" apart from "the cue was right and the
    /// pointer did not follow it". A walk's pointer is synthesized, so this is
    /// recorded as the cue is read rather than re-derived from where the real
    /// OS pointer happens to be.
    private(set) var playtestPointerCue = "none"

    private func recordPlaytestCue(_ hit: (cue: CanvasPointerCue, transform: LayerTransform)?) {
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

    /// Forces `cursor` onto the pointer, or gives it back. Only a CHANGE
    /// touches `NSCursor`: mouseMoved fires constantly and re-setting the same
    /// cursor flickers it on some setups. `force` overrides that for the one
    /// case where nothing here changed but the pointer still has to be re-read:
    /// a TOOL switch, where the crosshair on screen belongs to the tool being
    /// put down and no cue of ours is holding it.
    private func applyGrabCursor(_ cursor: NSCursor?, force: Bool = false) {
        guard force || cursor !== grabCursor else { return }
        grabCursor = cursor
        if let cursor {
            cursor.set()
        } else {
            // Hand the pointer back to whatever the tool asks for.
            window?.invalidateCursorRects(for: self)
            (toolCursor ?? .arrow).set()
        }
    }

    // MARK: Pointer: layer move or marquee

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let viewport else { return }
        // A click outside the inline text editor commits it; the click is
        // swallowed so committing never doubles as starting something else.
        // The one exception is the fresh arrow's caption field: the Arrow tool
        // stayed in hand while it is open, so this press commits the draft AND
        // starts the next arrow (a plain click hands back to Select on mouse-up).
        // A press anywhere else on the canvas lands the name being typed above a
        // screen or component, and is swallowed: committing never doubles as
        // starting something else. (A press INSIDE the field never reaches here.)
        if canvasNameField != nil {
            commitCanvasRename()
            return
        }
        if let session = textSession {
            if session.captionStyle != nil,
               ArrowCaptionEntry.pressOutsideField(tool: tool) == .commitAndDraw {
                commitTextSession(keepTool: true)
                pressClosedCaptionField = true
            } else {
                commitTextSession()
                return
            }
        }
        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)
        let p = viewport.documentPoint(fromView: viewPoint)
        // The name above a screen or component is a handle on it: click it to
        // pick that box, double click it to rename it where it sits. It is chrome,
        // the same size at every zoom, so it is resolved in view space and
        // before anything document-shaped runs — including the double click on
        // bare canvas that zooms the window, which is what this strip does
        // everywhere the letters are not.
        if tool == .select, let named = nameLabelHit(at: viewPoint) {
            if event.clickCount == 2 {
                beginCanvasRename(named)
            } else if event.modifierFlags.contains(.shift) {
                // ⇧-click on a name does what ⇧-click on the picture does: adds
                // that box to the selection, or drops it when it is in.
                onExtendSelection(named)
                refreshOverlays()
            } else {
                selectedLayerFrame = document?.canvasLayer(id: named)?.frame
                onSelectLayerInGroup(named, document?.parentID(of: named))
                refreshOverlays()
            }
            return
        }
        // Double-click the window background — the matte OR the locked base image,
        // i.e. anywhere that isn't an editable layer — performs the standard
        // window zoom. `.hiddenTitleBar` leaves no real title bar to double-click,
        // and on an image that fills the window the matte alone wasn't reachable,
        // so this makes "double-click the bg to maximize" work everywhere. Editable
        // layers (text/annotations) stay double-click-to-edit.
        if event.clickCount == 2, document?.canvasHitTest(p, zoom: viewport.zoom) == nil {
            performWindowTitleBarAction()
            return
        }
        // The text tool places a new block wherever you click.
        if tool == .text {
            beginTextSession(layerID: nil, at: p)
            return
        }
        // Crop mode owns the pointer: handles resize, inside moves, outside
        // draws a fresh rect. Double-click inside commits.
        if tool == .crop {
            if event.clickCount == 2, let rect = cropRect, rect.contains(p) {
                cropDrag = nil
                onCropCommit()
                return
            }
            if let rect = cropRect,
               let handle = Handles.hit(at: p, frame: rect, zoom: viewport.zoom,
                                        screenTolerance: CanvasPointer.cropTolerance) {
                cropDrag = CropDrag(kind: .resize(handle), startRect: rect, lastPoint: p)
                // The hover cue already put these arrows up, but a press that
                // arrived without one (a click straight onto a handle) still
                // has to hold them for the drag.
                if Experiments.shared.grabCueEnabled {
                    applyGrabCursor(CanvasCursor.cursor(for: .resize(handle), transform: .identity))
                }
            } else if let rect = cropRect, rect.contains(p) {
                cropDrag = CropDrag(kind: .move, startRect: rect, lastPoint: p)
            } else {
                cropDrag = CropDrag(kind: .define(anchor: p), startRect: cropRect, lastPoint: p)
            }
            return
        }
        // Paint bucket: click fills the hit layer (or the locked Background,
        // resolved app-side since hit-testing skips locked layers). ⌥ fills
        // with the background color.
        if tool == .fill {
            onFillAt(p, document?.canvasHitTest(p, zoom: viewport.zoom)?.id,
                     event.modifierFlags.contains(.option))
            return
        }
        // Region selection tools. The wand floods app-side (async — the
        // composite sweep is heavy); rect/ellipse start a marquee whose
        // corners magnetize to detected edges (⌘ = free). The combine mode
        // (⇧ add / ⌥ subtract / ⇧⌥ intersect) latches at gesture start.
        if tool == .wand {
            onWandAt(p, SelectionRegion.Mode(shift: event.modifierFlags.contains(.shift),
                                             option: event.modifierFlags.contains(.option)))
            return
        }
        if tool == .rectSelect || tool == .ellipseSelect {
            let mode = SelectionRegion.Mode(shift: event.modifierFlags.contains(.shift),
                                            option: event.modifierFlags.contains(.option))
            // A plain drag starting INSIDE the region moves its PIXELS (user
            // expectation 2026-07-05 — deliberate deviation from Photoshop,
            // where a marquee drag moves only the outline). ⌘-drag moves
            // just the outline; so does a region with nothing bakeable under
            // it. A ⇧/⌥ modifier still starts a new combining shape.
            if mode == .replace, let base = selection, base.contains(p) {
                if !event.modifierFlags.contains(.command), selectionTargetsPixels,
                   let frame = onRegionMoveBegin(false) {
                    regionContentDrag = (p, p, frame)
                } else {
                    regionOutlineDrag = (p, p, base)
                }
                refreshOverlays()
                return
            }
            var anchor = p
            if !event.modifierFlags.contains(.command) {
                anchor = EdgeSnapping.snap(p, edges: edgeMap, zoom: viewport.zoom).point
            }
            resetDragMotion(p)
            regionDrag = (MarqueeDrag(anchor: anchor), mode, tool == .ellipseSelect)
            refreshOverlays()
            return
        }
        // Drawing tools own the pointer: every drag creates a new annotation
        // (or, for the zoom tool, defines the callout's source box).
        if tool.createsAnnotationByDrag || tool == .zoomCallout || tool == .frame {
            annotationDrag = AnnotationDrag(anchor: p)
            refreshAnnotationPreview(constrained: event.modifierFlags.contains(.shift))
            return
        }
        // The measure tool: the measuring line is drawn EITHER by click/click OR
        // by press-drag-release; the head is a final click. On the first press we
        // place foot A and remember the down point so mouse-up can tell a click
        // (stay for a foot-B click) from a drag (line done → set the head).
        if tool == .measure {
            // Alignment mode: the press anchors a guide drag (snapped onto the
            // nearby edge — the edge you meant, not the pixel you hit).
            if measureChecksAlignment {
                let anchor = snapMeasureAnchor(p, modifiers: event.modifierFlags)
                alignmentDrag = (anchor, anchor)
                refreshAlignmentPreview()
                return
            }
            // Size and Gap commit on the click itself, so the press only tracks
            // the pointer; mouse-up does the work.
            if measureToolMode.commitsOnClick {
                measurePressDownView = convert(event.locationInWindow, from: nil)
                hoverPoint = measurePressDownView
                refreshMeasureCreation(modifierFlags: event.modifierFlags)
                return
            }
            measurePressDownView = convert(event.locationInWindow, from: nil)
            hoverPoint = measurePressDownView
            if measurePlacement == nil {
                resetDragMotion(p)
                measurePlacement = .firstPlaced(foot1: snapMeasureAnchor(p, modifiers: event.modifierFlags))
                measureFirstFootPress = true
            } else {
                measureFirstFootPress = false
            }
            refreshMeasureCreation(modifierFlags: event.modifierFlags)
            return
        }
        // Canvas pseudo-selection: the boundary handles resize the CANVAS.
        // Only handle hits are captured — clicks elsewhere fall through to
        // normal layer selection / marquee (which also deselects the canvas).
        if isCanvasSelected, tool == .select,
           let handle = Handles.hit(at: p, frame: CGRect(origin: .zero, size: viewport.documentSize),
                                    zoom: viewport.zoom, screenTolerance: 8) {
            canvasResizeDrag = (handle, CGRect(origin: .zero, size: viewport.documentSize), false)
            applyGrabCursor(CanvasCursor.cursor(for: .resize(handle), transform: .identity))
            refreshOverlays()
            return
        }
        // A double click always DESCENDS: on a group it picks the piece under
        // the pointer, and only once there is nothing left to go into does it
        // mean what it always meant — opening a text layer to type, or an
        // arrow's caption. That is what makes double clicking a group holding
        // a label select the label, and double clicking again start typing.
        if event.clickCount == 2, let step = groupAwareDescent(at: p, zoom: viewport.zoom) {
            selectedLayerFrame = document?.canvasLayer(id: step.id)?.frame
            onSelectLayerInGroup(step.id, step.context)
            refreshOverlays()
            return
        }
        // A double click on the words of a COPY types them, in ONE gesture.
        // A copy is one object — clicking it picks the whole thing and there
        // is nothing inside to select — so the extra step a group asks for
        // would buy nothing here. The words land on the copy's own wording
        // knob; with no knob for them, `beginTextSession` says so instead of
        // opening a field whose contents would be thrown away.
        if event.clickCount == 2, componentsEnabled,
           let pieceID = document?.textPiece(at: p, zoom: viewport.zoom),
           let piece = document?.canvasLayer(id: pieceID) {
            beginTextSession(layerID: pieceID, at: piece.frame.origin)
            return
        }
        // Double-click on a text layer re-opens it for inline editing. Checked
        // before handles: on a small text layer the handle hit zones cover the
        // whole frame and would eat the double-click.
        if event.clickCount == 2, let hit = document?.canvasHitTest(p, zoom: viewport.zoom),
           case .text = hit.content {
            beginTextSession(layerID: hit.id, at: hit.frame.origin)
            return
        }
        // Double-click an arrow to add or edit its caption (Next flag).
        if event.clickCount == 2, Experiments.shared.arrowCaptionsEnabled,
           let hit = document?.canvasHitTest(p, zoom: viewport.zoom),
           hit.annotation?.shape == .arrow {
            beginCaptionSession(layer: hit)
            return
        }
        // Handles take priority over moves: they extend past the layer's frame.
        // Lines/arrows expose their endpoints; everything else (that resizes)
        // gets the eight frame handles.
        let selectedLayer = selectedLayerID.flatMap { id in document?.canvasLayer(id: id) }
        if let id = selectedLayerID, let layer = selectedLayer, offersOwnHandles(layer),
           let content = layer.annotation,
           let endpoint = AnnotationEndpoints.hit(at: p, layer: layer, zoom: viewport.zoom),
           let drag = AnnotationEndpointDrag(layer: layer, endpoint: endpoint),
           let start = layer.annotationEndpoint(.start), let end = layer.annotationEndpoint(.end) {
            endpointDrag = EndpointDragSession(layerID: id, content: content,
                                               originalStart: start, originalEnd: end, drag: drag)
            // The hand that invited this drag closes for its duration, the same
            // as a caliper foot or a caption pill.
            applyGrabCursor(.closedHand)
            onDragBegin(id)
            refreshEndpointPreview(constrained: event.modifierFlags.contains(.shift))
            refreshOverlays()
            return
        }
        // A selected arrow's caption pill is a grab of its own: drag it to the
        // spot you want and it stays there (Next flag). Endpoint handles won
        // above, so the tail handle keeps priority where the two overlap.
        if let id = selectedLayerID, let layer = selectedLayer, !layer.isLocked,
           Experiments.shared.arrowCaptionsEnabled,
           let pill = captionPillRect(layer) {
            let tolerance = viewport.zoom > 0 ? 6 / viewport.zoom : 6
            if pill.insetBy(dx: -tolerance, dy: -tolerance).contains(p) {
                let center = CGPoint(x: pill.midX, y: pill.midY)
                captionDrag = CaptionDrag(layerID: id,
                                          grip: CGSize(width: p.x - center.x, height: p.y - center.y),
                                          startCenter: center, current: p)
                applyGrabCursor(.closedHand)
                refreshOverlays()
                return
            }
        }
        // A placed caliper is edited by dragging one of its three handles (the
        // two feet or the head); the others stay put and the value/label update
        // live. The readout pill is the head's grab too: dragging the number
        // moves it, and it is the only grab while it sits on the head dot.
        if let id = selectedLayerID, let layer = selectedLayer, offersOwnHandles(layer),
           let m = layer.measure,
           let s = layer.measureEndpoint(.start), let e = layer.measureEndpoint(.end) {
            let tolerance = viewport.zoom > 0 ? 9 / viewport.zoom : 9
            var best: (handle: MeasureHandle, distance: CGFloat)?
            for h in measureHandles(layer) {
                let d = hypot(p.x - h.point.x, p.y - h.point.y)
                if d <= tolerance, d < (best?.distance ?? .infinity) {
                    best = (h.handle, d)
                }
            }
            if best == nil, let pill = measureReadoutRect(layer),
               pill.insetBy(dx: -tolerance, dy: -tolerance).contains(p) {
                best = (.head, 0)
            }
            if let best {
                resetDragMotion(p)
                var drag = MeasureHandleDrag(
                    layerID: id, handle: best.handle, mode: m.mode,
                    originalStart: s, originalEnd: e, originalHeadOffset: m.headOffset,
                    originalReadout: MeasureReadoutPlacement(nudge: m.labelNudge,
                                                             pinned: m.labelPinned),
                    current: p)
                if best.handle == .head {
                    let head = MeasureContent.caliperGeometry(mode: m.mode, start: s, end: e,
                                                              headOffset: m.headOffset).labelAnchor
                    drag.grabCross = m.mode == .horizontal ? p.y - head.y : p.x - head.x
                    if let dm = documentMeasure(layer) {
                        let pill = dm.labelPosition(chipSize: dm.estimatedLabelSize)
                        drag.grabAlong = m.mode == .horizontal ? p.x - pill.x : p.y - pill.y
                    }
                    drag.guides = measureChipGuideLines(excluding: id)
                } else {
                    drag.guides = measureGuideLines(excluding: id)
                }
                measureHandleDrag = drag
                // The hand that invited this drag closes for its duration —
                // number, foot or head dot alike.
                if grabCue(at: p) != nil { applyGrabCursor(.closedHand) }
                refreshOverlays()
                return
            }
        }
        // Rotate knob, floated off the selected layer's top edge.
        if let id = selectedLayerID, let layer = selectedLayer, offersRotation(layer),
           let knob = layer.rotateKnobPoint(zoom: viewport.zoom),
           hypot(p.x - knob.x, p.y - knob.y) * viewport.zoom <= CanvasPointer.rotateTolerance {
            let center = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
            transformDrag = TransformDragSession(
                layerID: id, kind: .rotate(grabAngle: TransformDrag.pointerAngle(p, around: center)),
                startTransform: layer.transform, center: center,
                frameSize: layer.frame.size, transform: layer.transform)
            applyGrabCursor(CanvasCursor.cursor(for: .rotate, transform: layer.transform))
            onDragBegin(id)
            refreshOverlays()
            return
        }
        // Frame handles. The pointer maps through the layer's inverse
        // transform so handles on a rotated/skewed layer hit where they draw.
        // ⌥ on a corner skews instead of resizing.
        if let id = selectedLayerID, let frame = selectedLayerFrame,
           selectedLayer.map(offersOwnHandles) ?? true, selectedLayer?.allowsFrameResize ?? true,
           let handle = Handles.hit(at: handleSpacePoint(p, layer: selectedLayer),
                                    frame: frame, zoom: viewport.zoom) {
            if event.modifierFlags.contains(.option), handle.isCorner, let layer = selectedLayer {
                transformDrag = TransformDragSession(
                    layerID: id, kind: .skew(corner: handle, grabPoint: p),
                    startTransform: layer.transform,
                    center: CGPoint(x: layer.frame.midX, y: layer.frame.midY),
                    frameSize: layer.frame.size, transform: layer.transform)
            } else {
                resizeDrag = ResizeDrag(layerID: id, handle: handle, startFrame: frame, frame: frame)
                applyGrabCursor(CanvasCursor.cursor(for: .resize(handle),
                                                    transform: selectedLayer?.transform ?? .identity))
            }
            onDragBegin(id)
            refreshOverlays()
            return
        }
        // A SELECTED collage exposes its filled cells for swap-by-drag (like
        // measure corners: selection first, then inner manipulation). Grabbing
        // a gutter, the backdrop margin, or an empty well still moves the layer,
        // and anything drawn OVER the cell (hit-test winner) keeps the click.
        if tool == .select, let id = selectedLayerID, let layer = selectedLayer,
           !layer.isLocked, let content = layer.collage,
           document?.canvasHitTest(p, zoom: viewport.zoom)?.id == id,
           let slot = Collage.slotIndex(at: p, in: layer),
           content.slots[slot].imageRef != nil {
            slotDrag = (id, slot)
            refreshOverlays()
            return
        }
        // Select (V) drag starting inside a pixel region moves the region's
        // CONTENT within its layer (Photoshop Move tool); ⌥ moves a copy.
        // Falls through to normal layer moves when nothing bakeable is there.
        if selectionTargetsPixels, let region = selection, region.contains(p),
           let frame = onRegionMoveBegin(event.modifierFlags.contains(.option)) {
            regionContentDrag = (p, p, frame)
            refreshOverlays()
            return
        }
        if let pick = groupAwarePick(at: p, zoom: viewport.zoom),
           let hit = document?.canvasLayer(id: pick.id) {
            // ⇧-click adds what you clicked to the selection, or drops it when
            // it is already in — the Layers list gesture, on the picture. It
            // resolves through the same walk a plain click does, so at the top
            // level you add whole groups and inside a group you add its own
            // pieces. The press is swallowed either way: it is about what is
            // selected, and starting a move here would drag one member of a
            // selection out from under the rest.
            if tool == .select, event.clickCount == 1,
               event.modifierFlags.contains(.shift) {
                if let extend = groupAwareExtend(at: p, zoom: viewport.zoom) {
                    onExtendSelection(extend)
                }
                refreshOverlays()
                return
            }
            // The press landed on something already picked: the whole
            // selection travels with the pointer, and the press KEEPS that
            // selection instead of replacing it with the one layer underneath.
            // Selecting first and moving one piece is what a press on anything
            // else does, and it is what a click that never moves still does.
            if tool == .select, event.clickCount == 1,
               multiSelectedLayerIDs.contains(pick.id),
               let plan = document?.multiLayerDrag(moving: multiSelectedLayerIDs),
               plan.members.count > 1, plan.members.contains(where: { $0.id == pick.id }) {
                multiMove = MultiMoveDrag(
                    plan: plan,
                    pick: pick,
                    grabOffset: CGPoint(x: p.x - plan.bounds.origin.x,
                                        y: p.y - plan.bounds.origin.y),
                    peers: Experiments.shared.alignLayersEnabled
                        ? (document?.snapPeers(excluding: multiSelectedLayerIDs) ?? []) : [],
                    snapped: Snapping.Result(origin: plan.bounds.origin),
                    copying: copyDragModifier(event))
                refreshOverlays()
                return
            }
            let copying = copyDragModifier(event)
            onSelectLayerInGroup(pick.id, pick.context)
            // Dragging a PIECE inside a copy drags the whole copy. The piece
            // itself cannot move: its place comes from the original and the
            // next sync puts it back, so a drag on it would look like the
            // canvas ignoring the pointer. Moving the copy is what the person
            // grabbing its label meant anyway.
            var hit = hit
            if let piece = componentPiece(of: pick.id),
               let copy = document?.canvasLayer(id: piece.instance) {
                hit = copy
            }
            // The drag preview (two full renders, then a pass to hand the
            // canvas its sprite) starts once the pointer really travels, in
            // mouseDragged, not here: most presses on a layer are clicks that
            // never move, and a click has no use for a sprite. Per-move
            // previews fall back to full submits until the renders land, so a
            // drag loses nothing but the head start. A copy drag still never
            // gets a sprite at all; mouseDragged checks that before it asks.
            selectedLayerFrame = hit.frame
            moveDrag = MoveDrag(layerID: hit.id,
                                grabOffset: CGPoint(x: p.x - hit.frame.origin.x,
                                                    y: p.y - hit.frame.origin.y),
                                size: hit.frame.size,
                                startOrigin: hit.frame.origin,
                                peers: Experiments.shared.alignLayersEnabled
                                    ? (document?.snapPeers(excluding: hit.id) ?? []) : [],
                                snapped: Snapping.Result(origin: hit.frame.origin),
                                copying: copying)
        } else {
            // A ⇧-click is aimed at a layer, so one that lands on bare canvas
            // is a miss, not a deselect: it must not throw away the selection
            // it was about to be added to. The rubber band still starts either
            // way, so ⇧-dragging out on the canvas is unchanged; only the
            // press that never moves is spared, and mouse-up finishes the rule.
            let press = BareCanvasPress(shift: tool == .select
                && event.modifierFlags.contains(.shift))
            marqueePress = press
            if press.clearsSelectionOnPress {
                onClickedNothing()
                if selectedLayerFrame != nil || isCanvasSelected {
                    selectedLayerFrame = nil
                    onSelectLayer(nil) // also drops the Canvas pseudo-selection
                }
            }
            marquee = MarqueeDrag(anchor: p)
        }
        refreshOverlays()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let viewport else { return }
        let p = viewport.documentPoint(fromView: convert(event.locationInWindow, from: nil))
        if var drag = cropDrag {
            let bounds = cropBounds ?? CGRect(origin: .zero, size: viewport.documentSize)
            switch drag.kind {
            case .resize(let handle):
                guard let start = drag.startRect else { break }
                cropRect = Crop.resize(start, dragging: handle, to: p,
                                       aspect: cropAspect, bounds: bounds)
            case .move:
                if let rect = cropRect {
                    cropRect = Crop.moved(rect, by: CGPoint(x: p.x - drag.lastPoint.x,
                                                            y: p.y - drag.lastPoint.y),
                                          in: bounds)
                }
            case .define(let anchor):
                // An empty drag (a stray click) keeps the existing rect.
                cropRect = Crop.dragRect(anchor: anchor, current: p, aspect: cropAspect,
                                         bounds: bounds) ?? drag.startRect
            }
            drag.lastPoint = p
            cropDrag = drag
            refreshOverlays()
        } else if var drag = annotationDrag {
            drag.update(to: p)
            annotationDrag = drag
            refreshAnnotationPreview(constrained: event.modifierFlags.contains(.shift))
        } else if var drag = alignmentDrag {
            drag.current = p
            alignmentDrag = drag
            refreshAlignmentPreview()
        } else if tool == .measure {
            // Caliper creation is click-based; a drag between clicks just updates
            // the placement preview (same as moving with the button up).
            handleMeasureHover(event)
        } else if var drag = measureHandleDrag {
            // A FOOT magnetizes to detected UI edges (per-axis), to the lines the
            // other measurements already put down, and to the pixel grid. The
            // HEAD is the label position, not a measured point, so the picture's
            // edges have no say over it — but the other readouts do: it lines up
            // with the chips around it. ⌘ drags either one free.
            if drag.handle == .head {
                snapGuide = snapMeasureHead(&drag, pointer: p, zoom: viewport.zoom,
                                            snapping: !event.modifierFlags.contains(.command))
            } else if event.modifierFlags.contains(.command) {
                drag.current = p
                snapGuide = nil
            } else {
                trackDragMotion(p)
                // Window the edge candidates by the span from the opposite foot to
                // the pointer, exactly like the create drag.
                let fixed = drag.handle == .footA ? drag.originalEnd : drag.originalStart
                let snap = axisGated(
                    EdgeSnapping.snap(p, edges: edgeMap, zoom: viewport.zoom,
                                      xSpan: min(fixed.x, p.x)...max(fixed.x, p.x),
                                      ySpan: min(fixed.y, p.y)...max(fixed.y, p.y),
                                      includeCenters: measureSnapsToCenters,
                                      guides: drag.guides),
                    raw: p)
                drag.current = snap.point
                snapGuide = (snap.guideX, snap.guideY)
            }
            measureHandleDrag = drag
            // Live re-render so the measured value updates as the handle moves.
            let (start, end, off, readout) = drag.params()
            onMeasureEndpointPreview(drag.layerID, start, end, off, readout)
            refreshOverlays()
        } else if var drag = captionDrag {
            drag.current = p
            captionDrag = drag
            // Live re-render so the pill follows the pointer.
            onCaptionPlacePreview(drag.layerID, drag.center)
            refreshOverlays()
        } else if var session = endpointDrag {
            session.drag.update(to: p)
            endpointDrag = session
            refreshEndpointPreview(constrained: event.modifierFlags.contains(.shift))
            refreshOverlays()
        } else if var session = transformDrag {
            switch session.kind {
            case .rotate(let grabAngle):
                session.transform.rotation = TransformDrag.rotation(
                    from: session.startTransform.rotation, grabAngle: grabAngle,
                    currentAngle: TransformDrag.pointerAngle(p, around: session.center),
                    snapped: event.modifierFlags.contains(.shift))
            case .skew(let corner, let grabPoint):
                session.transform = TransformDrag.skewed(
                    session.startTransform, corner: corner,
                    by: CGPoint(x: p.x - grabPoint.x, y: p.y - grabPoint.y),
                    frameSize: session.frameSize)
            }
            transformDrag = session
            onTransformPreview(session.layerID, session.transform)
            refreshOverlays()
        } else if var drag = resizeDrag {
            let layer = document?.canvasLayer(id: drag.layerID)
            drag.frame = resizedFrame(for: layer, start: drag.startFrame, handle: drag.handle,
                                      pointer: p, preserveAspect: event.modifierFlags.contains(.shift))
            resizeDrag = drag
            onFramePreview(drag.layerID, drag.frame)
            refreshOverlays()
        } else if var drag = moveDrag {
            let proposed = CGPoint(x: p.x - drag.grabOffset.x, y: p.y - drag.grabOffset.y)
            // Read the copy modifier BEFORE deciding to float a sprite: a copy
            // drag never gets one, because the sprite's underlay hides the layer
            // it lifts and the original has to stay visible where it is.
            if copyDragModifier(event) { drag.copying = true }
            if !drag.moved {
                let travel = hypot(proposed.x - drag.startOrigin.x, proposed.y - drag.startOrigin.y)
                drag.moved = travel * viewport.zoom >= 4
                // The press has become a drag: now the sprite is worth making.
                if drag.moved, !drag.copying { onDragBegin(drag.layerID) }
            }
            if drag.moved {
                // ⌘ drags free, the way it already does for a measure foot or a
                // region corner: one key that means "ignore the magnets"
                // everywhere on the canvas.
                if event.modifierFlags.contains(.command) {
                    drag.snapped = Snapping.Result(origin: proposed)
                } else {
                    drag.snapped = Snapping.snapFrameOrigin(proposed, size: drag.size,
                                                            canvas: viewport.documentSize,
                                                            peers: drag.peers,
                                                            zoom: viewport.zoom)
                }
                if drag.copying {
                    onCopyDragPreview([drag.layerID: drag.snapped.origin])
                } else {
                    onFramePreview(drag.layerID, CGRect(origin: drag.snapped.origin, size: drag.size))
                }
            }
            // A dragged photo layer offers itself to collage slots under the
            // pointer — releasing over the highlighted cell absorbs it. A copy
            // drag never does: being swallowed by a cell is not what "leave the
            // original and take a copy" asked for.
            if drag.moved, !drag.copying, document?.canvasLayer(id: drag.layerID)?.imageRef != nil {
                hoverSlot = collageSlotTarget(at: p, excluding: drag.layerID)
            } else {
                hoverSlot = nil
            }
            applyGrabCursor(drag.copying ? .dragCopy : nil)
            adoptionHost = drag.moved
                ? adoptionHost(moving: [drag.layerID: CGRect(origin: drag.snapped.origin,
                                                             size: drag.size)])
                : nil
            moveDrag = drag
            refreshOverlays()
        } else if var drag = multiMove {
            let proposed = CGPoint(x: p.x - drag.grabOffset.x, y: p.y - drag.grabOffset.y)
            if !drag.moved {
                let travel = hypot(proposed.x - drag.plan.bounds.origin.x,
                                   proposed.y - drag.plan.bounds.origin.y)
                drag.moved = travel * viewport.zoom >= 4
            }
            if copyDragModifier(event) { drag.copying = true }
            if drag.moved {
                // ⌘ drags free of the magnets, exactly as it does for one layer.
                if event.modifierFlags.contains(.command) {
                    drag.snapped = Snapping.Result(origin: proposed)
                } else {
                    drag.snapped = Snapping.snapFrameOrigin(proposed, size: drag.plan.bounds.size,
                                                            canvas: viewport.documentSize,
                                                            peers: drag.peers,
                                                            zoom: viewport.zoom)
                }
                let origins = drag.plan.origins(movingBoundsTo: drag.snapped.origin)
                if drag.copying {
                    onCopyDragPreview(origins)
                } else {
                    onMoveSelectionPreview(origins)
                }
            }
            // Several layers dropped into one collage cell means nothing, so a
            // multi-drag never offers itself to one.
            hoverSlot = nil
            applyGrabCursor(drag.copying ? .dragCopy : nil)
            adoptionHost = adoptionHost(moving: drag.plan.members.reduce(into: [:]) { boxes, member in
                guard let origins = drag.liveOrigins, let origin = origins[member.id] else { return }
                boxes[member.id] = CGRect(origin: origin, size: member.bounds.size)
            })
            multiMove = drag
            refreshOverlays()
        } else if let drag = slotDrag {
            // Swap drag: highlight the destination cell (same collage only).
            if let target = collageSlotTarget(at: p), target.collageID == drag.collageID,
               target.index != drag.from {
                hoverSlot = target
            } else {
                hoverSlot = nil
            }
            refreshOverlays()
        } else if var drag = canvasResizeDrag {
            let base = CGRect(origin: .zero, size: viewport.documentSize)
            var rect = Handles.resize(base, dragging: drag.handle, to: p,
                                      preserveAspect: false, minSize: 16)
            // ⇧ resizes symmetrically around the center: the opposite edge(s)
            // mirror the drag, so content stays centered on commit.
            drag.centered = event.modifierFlags.contains(.shift)
            if drag.centered {
                let dx = drag.handle.movesMaxX ? rect.maxX - base.maxX
                    : (drag.handle.movesMinX ? base.minX - rect.minX : 0)
                let dy = drag.handle.movesMaxY ? rect.maxY - base.maxY
                    : (drag.handle.movesMinY ? base.minY - rect.minY : 0)
                let width = max(16, base.width + 2 * dx)
                let height = max(16, base.height + 2 * dy)
                rect = CGRect(x: base.midX - width / 2, y: base.midY - height / 2,
                              width: width, height: height)
            }
            drag.rect = rect
            canvasResizeDrag = drag
            refreshOverlays()
        } else if var session = regionContentDrag {
            session.current = p
            regionContentDrag = session
            refreshOverlays()
        } else if var session = regionOutlineDrag {
            session.current = p
            regionOutlineDrag = session
            refreshOverlays()
        } else if var session = regionDrag {
            // Same corner magnetizing as a measure drag: the growing edges
            // window the candidates; ⌘ drags free.
            if event.modifierFlags.contains(.command) {
                session.drag.update(to: p)
                snapGuide = nil
            } else {
                trackDragMotion(p)
                let snap = axisGated(
                    EdgeSnapping.snap(p, edges: edgeMap, zoom: viewport.zoom,
                                      xSpan: min(session.drag.anchor.x, p.x)...max(session.drag.anchor.x, p.x),
                                      ySpan: min(session.drag.anchor.y, p.y)...max(session.drag.anchor.y, p.y)),
                    raw: p)
                session.drag.update(to: snap.point)
                snapGuide = (snap.guideX, snap.guideY)
            }
            regionDrag = session
            refreshOverlays()
        } else if var drag = marquee {
            drag.update(to: p)
            marquee = drag
            refreshOverlays()
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let viewport else { return }
        // The measure tool advances its placement on mouse-up (click/click) or on
        // a press-drag release (down/drag/release draws the line).
        if let drag = alignmentDrag {
            alignmentDrag = nil
            alignmentPreviewLayer.isHidden = true
            finishAlignmentDrag(from: drag.anchor,
                                to: viewport.documentPoint(fromView: convert(event.locationInWindow, from: nil)))
            return
        }
        if tool == .measure, measureToolMode.commitsOnClick {
            let up = convert(event.locationInWindow, from: nil)
            measurePressDownView = nil
            hoverPoint = up
            // Commit exactly what the preview was showing. A miss stays a quiet
            // no-op rather than dropping a caliper somewhere arbitrary.
            refreshMeasureCreation(modifierFlags: event.modifierFlags)
            if let rect = measureElementPreview {
                // Grab what the preview steered around before the preview goes:
                // the commit has to place the readouts against the same picture.
                let around = measureElementNeighbors
                hideMeasureHoverReadout()
                onElementSizeCommit(rect, around)
            } else if let gap = measureGapPreview {
                hideMeasureHoverReadout()
                onGapCommit(gap)
            }
            return
        }
        if tool == .measure {
            let up = convert(event.locationInWindow, from: nil)
            let down = measurePressDownView ?? up
            let dragged = hypot(up.x - down.x, up.y - down.y) > 4
            advanceMeasurePlacement(at: viewport.documentPoint(fromView: up),
                                    dragged: dragged, modifiers: event.modifierFlags)
            measurePressDownView = nil
            return
        }
        if cropDrag != nil {
            cropDrag = nil
            if let rect = cropRect { onCropRectChange(rect) }
            // The box just moved under the resting pointer (a fresh rect drawn,
            // a corner dragged), so the pointer has to say what is under it NOW.
            refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
            refreshOverlays()
        } else if let drag = annotationDrag {
            annotationDrag = nil
            let closedField = pressClosedCaptionField
            pressClosedCaptionField = false
            // The frame tool answers a click as well as a drag: a click drops a
            // frame at the size you made last, which is how a second screen
            // costs one click rather than a trip to a dialog.
            if tool == .frame {
                clearAnnotationPreview()
                let end = drag.isClick(atZoom: viewport.zoom)
                    ? drag.anchor
                    : drag.end(constrained: event.modifierFlags.contains(.shift), shape: .rectangle)
                onFrameCreate(drag.anchor, end)
            } else if drag.isClick(atZoom: viewport.zoom) {
                clearAnnotationPreview()
                // The press only dismissed the caption field: the arrow is
                // finished, so Select comes back as it does for Return or Esc.
                if closedField { onToolChange(ArrowCaptionEntry.toolAfterClosing(tool)) }
            } else if tool == .zoomCallout {
                clearAnnotationPreview()
                let end = drag.end(constrained: event.modifierFlags.contains(.shift), shape: .rectangle)
                // Build the same layer EditorState will commit, to drive the
                // flight animation from source box to placed frame.
                if let layer = ZoomCalloutBuilder.layer(from: drag.anchor, to: end,
                                                        canvas: viewport.documentSize,
                                                        shape: calloutShape,
                                                        avoiding: document?.placedZoomCalloutRects ?? []) {
                    beginCalloutFlight(for: layer)
                    onZoomCalloutCommit(drag.anchor, end)
                }
            } else {
                // Leave the preview shape up until the re-rendered composite
                // (which includes the new layer) lands — no flash.
                annotationCommitImage = image
                let shape = tool.annotationShape ?? .line
                let created = onAnnotationCommit(drag.anchor,
                                                 drag.end(constrained: event.modifierFlags.contains(.shift),
                                                          shape: shape))
                // A fresh arrow immediately offers its caption (Next flag):
                // type to label it, Esc or an empty commit leaves it plain.
                if let created { beginCaptionSession(layer: created) }
            }
        } else if let drag = measureHandleDrag {
            measureHandleDrag = nil
            snapGuide = nil
            let (start, end, off, readout) = drag.params()
            onMeasureEndpointCommit(drag.layerID, start, end, off, readout)
            refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
            refreshOverlays()
        } else if let drag = captionDrag {
            captionDrag = nil
            // A press with no movement is a click on the pill, not a placement:
            // no undo step, the render just settles back.
            let moved = hypot(drag.center.x - drag.startCenter.x,
                              drag.center.y - drag.startCenter.y) * viewport.zoom >= 2
            if moved {
                onCaptionPlaceCommit(drag.layerID, drag.center)
            } else {
                onCaptionPlaceCancel()
            }
            refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
            refreshOverlays()
        } else if let session = endpointDrag {
            endpointDrag = nil
            let (start, end) = session.drag.endpoints(constrained: event.modifierFlags.contains(.shift))
            // Same no-flash hold as drag-to-create: the vector preview (over
            // the underlay) stands in until the re-rendered composite lands.
            annotationCommitImage = image
            endpointHoldLayerID = session.layerID
            onAnnotationEndpointsCommit(session.layerID, start, end)
            refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
            refreshOverlays()
        } else if let session = transformDrag {
            transformDrag = nil
            if session.transform != session.startTransform {
                // Hold the sprite at the final transform until the post-commit
                // composite lands — otherwise it flashes back.
                transformHold = (session.layerID, session.startTransform, session.transform)
                onTransformCommit(session.layerID, session.transform)
            }
            refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
            refreshOverlays()
        } else if let drag = resizeDrag {
            resizeDrag = nil
            if drag.frame != drag.startFrame {
                selectedLayerFrame = drag.frame
                holdSpriteUntilRender = true
                onFrameCommit(drag.layerID, drag.frame)
            }
            refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
            refreshOverlays()
        } else if let drag = moveDrag {
            moveDrag = nil
            applyGrabCursor(nil)
            if drag.copying {
                hoverSlot = nil
                if drag.moved {
                    let frame = CGRect(origin: drag.snapped.origin, size: drag.size)
                    // The copy is what ends up selected, and it is the same
                    // size in the same place, so the handles stay put.
                    selectedLayerFrame = frame
                    onCopyDragCommit([drag.layerID: drag.snapped.origin])
                } else {
                    // ⌥ and a click that never travelled: a plain click, and
                    // nothing was ever made.
                    onCopyDragCancel()
                }
                refreshOverlays()
                return
            }
            if drag.moved, let target = hoverSlot,
               document?.canvasLayer(id: drag.layerID)?.imageRef != nil {
                // Released over a collage cell: the photo layer becomes that
                // slot's content instead of landing at the drop position.
                hoverSlot = nil
                onAbsorbLayerIntoCollage(drag.layerID, target.collageID, target.index)
            } else if drag.moved {
                let frame = CGRect(origin: drag.snapped.origin, size: drag.size)
                selectedLayerFrame = frame
                holdSpriteUntilRender = true
                onDropCommit(drag.layerID, frame)
            }
            hoverSlot = nil
            adoptionHost = nil
            refreshOverlays()
        } else if let drag = multiMove {
            multiMove = nil
            applyGrabCursor(nil)
            if drag.copying {
                if let origins = drag.liveOrigins { onCopyDragCommit(origins) }
                else { onCopyDragCancel() }
            } else if let origins = drag.liveOrigins {
                onMoveSelectionCommit(origins, true)
            }
            // The press kept the whole selection so the group could travel.
            // If it never travelled it was a click on one layer, so now it
            // narrows to that layer — the press-keeps/click-narrows rule every
            // other Mac app follows. ⌥ makes no difference: an ⌥ press that
            // never moved made no copy, so it is a plain click too.
            if PickedMemberPress(moved: drag.moved).narrowsSelection {
                // The frame goes in first so the handles land on the layer in
                // the same beat as the click, rather than a refresh later.
                selectedLayerFrame = document?.canvasLayer(id: drag.pick.id)?.frame
                onSelectLayerInGroup(drag.pick.id, drag.pick.context)
            }
            adoptionHost = nil
            refreshOverlays()
        } else if let drag = slotDrag {
            slotDrag = nil
            if let target = hoverSlot, target.collageID == drag.collageID {
                onSwapCollageSlots(drag.collageID, drag.from, target.index)
            }
            hoverSlot = nil
            refreshOverlays()
        } else if let drag = canvasResizeDrag {
            canvasResizeDrag = nil
            let size = CGSize(width: drag.rect.width.rounded(), height: drag.rect.height.rounded())
            if size != viewport.documentSize {
                onCanvasResize(size, drag.centered ? .center : .fixing(oppositeOf: drag.handle))
            }
            refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
            refreshOverlays()
        } else if let session = regionContentDrag {
            regionContentDrag = nil
            let delta = roundedDelta(from: session.start, to: session.current)
            if delta == .zero {
                onRegionMoveCancel()
            } else {
                // Hold the sprite at its destination until the baked
                // composite lands (the standard no-flash trick).
                regionMoveHoldFrame = session.frame.offsetBy(dx: delta.x, dy: delta.y)
                onRegionMoveCommit(delta)
            }
            refreshOverlays()
        } else if let session = regionOutlineDrag {
            regionOutlineDrag = nil
            let delta = roundedDelta(from: session.start, to: session.current)
            if delta != .zero,
               let moved = session.base.translated(by: CGVector(dx: delta.x, dy: delta.y)) {
                commitSelection(moved, capture: false)
            } else {
                refreshOverlays()
            }
        } else if let session = regionDrag {
            regionDrag = nil
            snapGuide = nil
            if session.drag.isClick(atZoom: viewport.zoom) {
                // A plain click deselects (Photoshop); a click with a combine
                // modifier held contributes nothing and changes nothing.
                if session.mode == .replace {
                    commitSelection(nil, capture: false)
                } else {
                    refreshOverlays()
                }
            } else {
                let shape = session.drag.selectionRect(in: viewport.documentSize)
                    .map(Geometry.pixelAligned)
                    .flatMap { session.isEllipse ? SelectionRegion.ellipse(in: $0) : SelectionRegion.rect($0) }
                if let shape {
                    commitSelection(SelectionRegion.combine(selection, with: shape, mode: session.mode),
                                    capture: false)
                } else {
                    refreshOverlays()
                }
            }
        } else if let drag = marquee {
            marquee = nil
            let press = marqueePress
            marqueePress = .replaces
            guard press.commitsOnRelease(isClick: drag.isClick(atZoom: viewport.zoom)) else {
                // A ⇧-click that landed on nothing: the band comes down and
                // the selection stays exactly as it was.
                refreshOverlays()
                return
            }
            if drag.isClick(atZoom: viewport.zoom) {
                commitSelection(nil, capture: true) // a plain click deselects
                return
            }
            // A sweep decides the selection whatever started it, so the
            // Library tile lets go here the way the plain press already did.
            if !press.clearsSelectionOnPress { onClickedNothing() }
            let region = drag.selectionRect(in: viewport.documentSize)
                .map(Geometry.pixelAligned).flatMap(SelectionRegion.rect)
            if press.sweepAddsToSelection {
                // ⇧-sweep: the catch joins what was already picked. The band
                // itself comes down, because it describes only this sweep and
                // not the whole selection — the outlines carry that, the same
                // way they do after a ⇧-click on the picture. A pixel region
                // belongs to the region tools, so that one stays put.
                if let region {
                    if !selectionTargetsPixels { selection = nil }
                    onAddSweptLayers(region)
                } else {
                    refreshOverlays() // swept only empty space: nothing changes
                }
                return
            }
            commitSelection(region, capture: true)
        }
    }

    override func keyDown(with event: NSEvent) {
        // Size mode: [ shrinks the pick, ] grows it. A flat screenshot has no
        // element tree, so the first guess is a guess — these two keys are what
        // make a wrong guess a half-second correction instead of a dead end.
        if tool == .measure, measureToolMode.picksAmongCandidates,
           event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           let characters = event.charactersIgnoringModifiers,
           characters == "[" || characters == "]" {
            let level = max(0, measureCandidateLevel + (characters == "]" ? 1 : -1))
            measureCandidateLevel = level
            onCandidateLevelChange(level)
            refreshMeasureCreation(modifierFlags: event.modifierFlags)
            return
        }
        if tool == .crop, event.keyCode == 36 || event.keyCode == 76 { // ⏎ / keypad ⏎
            cropDrag = nil
            onCropCommit()
            return
        }
        // Enter / Return edits the selected text layer's content (same as a
        // double-click). Only when idle — while the inline editor is up the
        // NSTextView owns Return (newline).
        if event.keyCode == 36 || event.keyCode == 76,
           moveDrag == nil, resizeDrag == nil, transformDrag == nil,
           let id = selectedLayerID, let layer = document?.canvasLayer(id: id), !layer.isLocked,
           case .text = layer.content {
            beginTextSession(layerID: id, at: layer.frame.origin)
            return
        }
        // ⌥⌫ fills the selected layer — or the pixel region — with the
        // foreground color (Photoshop). EditorState routes region vs layer.
        if event.keyCode == 51 || event.keyCode == 117,
           event.modifierFlags.contains(.option),
           selectedLayerID != nil || (selectionTargetsPixels && selection != nil) {
            onFillSelected(false)
            return
        }
        // ⌫ with a pixel region erases the region (or fills the locked
        // Background with the BG color) instead of touching layers.
        if event.keyCode == 51 || event.keyCode == 117,
           selectionTargetsPixels, selection != nil {
            onDeleteRegion()
            return
        }
        // Delete / forward-delete with a marquee multi-selection removes them
        // all (one undo step) — the "sweep around a bunch of annotations and
        // hit ⌫" cleanup gesture.
        if event.keyCode == 51 || event.keyCode == 117, !multiSelectedLayerIDs.isEmpty {
            onDeleteLayers(Array(multiSelectedLayerIDs))
            return
        }
        // ⌫ on the locked Background (which the delete path below skips):
        // reset it to the background fill color — "clear to default".
        if event.keyCode == 51 || event.keyCode == 117,
           let id = selectedLayerID, let layer = document?.canvasLayer(id: id),
           layer.isLocked, layer.imageRef != nil {
            onClearBackground()
            return
        }
        // Delete / forward-delete removes the selected (unlocked) layer.
        if event.keyCode == 51 || event.keyCode == 117,
           let id = selectedLayerID, let layer = document?.canvasLayer(id: id), !layer.isLocked {
            onDeleteLayer(id)
            return
        }
        // Arrow keys nudge a whole multi-selection (1pt, ⇧ for 10pt): every
        // picked layer travels the same distance, in ONE undo step, exactly as
        // dragging the selection on the canvas does. Same plan, so a locked
        // layer stays put and a piece inside a picked group is not moved twice.
        // This comes first because a multi-selection has no primary layer at
        // all — `selectedLayerID` is nil — so the branch below can never fire.
        if let delta = Nudge.delta(keyCode: event.keyCode,
                                   large: event.modifierFlags.contains(.shift)),
           moveDrag == nil, resizeDrag == nil, transformDrag == nil,
           pickedLayerIDs.count > 1,
           let plan = document?.multiLayerDrag(moving: pickedLayerIDs) {
            onMoveSelectionCommit(plan.origins(offsetBy: delta), false)
            refreshOverlays()
            return
        }
        // Arrow keys nudge the selected layer (1pt, ⇧ for 10pt).
        if let delta = Nudge.delta(keyCode: event.keyCode,
                                   large: event.modifierFlags.contains(.shift)),
           moveDrag == nil, resizeDrag == nil, transformDrag == nil,
           let id = selectedLayerID, let layer = document?.canvasLayer(id: id), !layer.isLocked {
            let frame = layer.frame.offsetBy(dx: delta.dx, dy: delta.dy)
            selectedLayerFrame = frame
            onFrameCommit(id, frame)
            refreshOverlays()
            return
        }
        if event.keyCode == 53 { // Esc, in priority order: cancel drag → ants → layer → tool
            if let drag = cropDrag {
                cropDrag = nil
                cropRect = drag.startRect
                refreshOverlays()
                return
            }
            if measurePlacement != nil || alignmentDrag != nil {
                cancelMeasurePlacement()
                refreshOverlays()
                return
            }
            if annotationDrag != nil {
                annotationDrag = nil
                snapGuide = nil
                clearAnnotationPreview()
                refreshOverlays()
                return
            }
            if let session = endpointDrag {
                endpointDrag = nil
                clearAnnotationPreview()
                // Committing the original endpoints is a History no-op but
                // resets the preview render, like the resize-drag cancel.
                onAnnotationEndpointsCommit(session.layerID, session.originalStart, session.originalEnd)
                refreshOverlays()
                return
            }
            if captionDrag != nil {
                captionDrag = nil
                onCaptionPlaceCancel() // no history was touched; restores the render
                refreshGrabCursor()
                refreshOverlays()
                return
            }
            if let drag = measureHandleDrag {
                measureHandleDrag = nil
                snapGuide = nil
                let (start, end, off, readout) = drag.originalParams()
                onMeasureEndpointCommit(drag.layerID, start, end, off, readout) // History no-op; restores render
                refreshGrabCursor()
                refreshOverlays()
                return
            }
            if let session = transformDrag {
                transformDrag = nil
                // Committing the start transform is a History no-op but resets
                // the preview render.
                onTransformCommit(session.layerID, session.startTransform)
                refreshOverlays()
                return
            }
            if let drag = resizeDrag {
                resizeDrag = nil
                selectedLayerFrame = drag.startFrame
                // Committing the start frame is a History no-op but resets the preview render.
                onFrameCommit(drag.layerID, drag.startFrame)
                refreshOverlays()
                return
            }
            if let drag = moveDrag {
                moveDrag = nil
                applyGrabCursor(nil)
                let frame = CGRect(origin: drag.startOrigin, size: drag.size)
                selectedLayerFrame = frame
                // A copy drag never wrote anything down, so Esc is simply
                // "put the real picture back" — no copy is left behind.
                if drag.copying { onCopyDragCancel() } else { onFrameCommit(drag.layerID, frame) }
                adoptionHost = nil
                refreshOverlays()
                return
            }
            if let drag = multiMove {
                multiMove = nil
                applyGrabCursor(nil)
                if drag.copying {
                    onCopyDragCancel()
                } else {
                    // Putting everything back where it started is a History
                    // no-op, and it resets the preview render.
                    onMoveSelectionCommit(drag.plan.origins(movingBoundsTo: drag.plan.bounds.origin), false)
                }
                adoptionHost = nil
                refreshOverlays()
                return
            }
            if regionContentDrag != nil {
                regionContentDrag = nil
                onRegionMoveCancel()
                refreshOverlays()
                return
            }
            if regionOutlineDrag != nil {
                regionOutlineDrag = nil
                refreshOverlays()
                return
            }
            if regionDrag != nil {
                regionDrag = nil
                snapGuide = nil
                refreshOverlays()
                return
            }
            if marquee != nil || selection != nil {
                marquee = nil
                commitSelection(nil, capture: true)
                return
            }
            // Stepping out of a group comes ahead of clearing the selection:
            // inside one, Escape leaves it with the group selected; only at the
            // top does Escape deselect, the way it always has.
            if onExitGroup() {
                selectedLayerFrame = nil // re-read from the selection that lands
                refreshOverlays()
                return
            }
            if selectedLayerFrame != nil {
                selectedLayerFrame = nil
                onSelectLayer(nil)
                refreshOverlays()
                return
            }
            if tool != .select {
                onToolChange(.select)
                return
            }
        }
        super.keyDown(with: event)
    }

    private func commitSelection(_ region: SelectionRegion?, capture: Bool) {
        selection = region
        refreshOverlays()
        onSelectionChange(region, capture)
    }

    // MARK: Gestures

    /// Two-finger scroll pans. Deltas already arrive in natural-scrolling
    /// orientation, and view coords are flipped, so they apply directly.
    override func scrollWheel(with event: NSEvent) {
        guard let viewport else { return }
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        commit(viewport.panned(by: CGPoint(x: event.scrollingDeltaX * scale,
                                           y: event.scrollingDeltaY * scale)))
    }

    /// Pinch zooms around the cursor.
    override func magnify(with event: NSEvent) {
        guard let viewport else { return }
        let anchor = convert(event.locationInWindow, from: nil)
        commit(viewport.zoomed(to: viewport.zoom * (1 + event.magnification), anchorInView: anchor))
    }

    /// Two-finger double-tap: toggle between fit and 100% at the cursor.
    override func smartMagnify(with event: NSEvent) {
        guard let viewport else { return }
        let fit = Viewport.fit(documentSize: viewport.documentSize, in: viewport.viewSize)
        if abs(viewport.zoom - fit.zoom) < 0.001 {
            let anchor = convert(event.locationInWindow, from: nil)
            commit(viewport.zoomed(to: viewport.zoom >= 1 ? 2 : 1, anchorInView: anchor))
        } else {
            commit(fit)
        }
    }

    /// Mirrors the system "Double-click a window's title bar to" preference for
    /// a double-click on the empty surround (we hide the real title bar).
    private func performWindowTitleBarAction() {
        WindowTitleBarAction.perform(on: window)
    }

    private func commit(_ next: Viewport) {
        apply(image: image, viewport: next, document: document, selection: selection,
              selectionTargetsPixels: selectionTargetsPixels,
              cropRect: cropRect, cropAspect: cropAspect, cropBounds: cropBounds,
              selectedLayerID: selectedLayerID, selectedLayerFrame: selectedLayerFrame,
              multiSelectedLayerIDs: multiSelectedLayerIDs,
              dragPreview: dragPreview, tool: tool, annotationContent: annotationContent,
              textContent: textContent, measureContent: measureContent,
              measureToolMode: measureToolMode, measureCandidateLevel: measureCandidateLevel,
              measureSnapsToCenters: measureSnapsToCenters, edgeMap: edgeMap,
              lumaField: lumaField)
        onViewportChange(next)
    }

    // MARK: Display

    func apply(image: CGImage?, viewport: Viewport?, document: PhotonzDocument?,
               selection: SelectionRegion?, selectionTargetsPixels: Bool = false,
               cropRect: CGRect?, cropAspect: CropAspect,
               cropBounds: CGRect?, selectedLayerID: UUID?, selectedLayerFrame: CGRect?,
               groupContext: UUID? = nil,
               multiSelectedLayerIDs: Set<UUID>,
               dragPreview: DragPreview?, tool: Tool, captionCloseRequest: Int = 0,
               annotationContent: AnnotationContent?,
               calloutShape: ZoomCalloutShape = .rectangle,
               annotationStyle: LayerStyle? = nil,
               textContent: TextContent?, measureContent: MeasureContent?,
               measureToolMode: MeasureToolMode = .distance,
               measureCandidateLevel: Int = 0,
               measureSnapsToCenters: Bool = false,
               edgeMap: EdgeMap, lumaField: LumaField,
               isCanvasSelected: Bool = false) {
        self.multiSelectedLayerIDs = multiSelectedLayerIDs
        if self.isCanvasSelected != isCanvasSelected {
            self.isCanvasSelected = isCanvasSelected
            if !isCanvasSelected { canvasResizeDrag = nil }
        }
        self.annotationContent = annotationContent
        self.calloutShape = calloutShape
        self.annotationStyle = annotationStyle
        self.textContent = textContent
        self.measureContent = measureContent
        if measureToolMode != self.measureToolMode {
            // Switching Measure modes abandons whichever draft was in flight.
            self.measureToolMode = measureToolMode
            cancelMeasurePlacement()
            // Picking a mode in the tool options leaves the focus on a button, so
            // the canvas takes it back: otherwise `[` and `]` would go nowhere
            // until you had clicked the image at least once.
            if measureToolMode.picksAmongCandidates { window?.makeFirstResponder(self) }
        }
        if measureCandidateLevel != self.measureCandidateLevel {
            self.measureCandidateLevel = measureCandidateLevel
            refreshMeasureCreation(modifierFlags: [])
        }
        self.measureSnapsToCenters = measureSnapsToCenters
        self.edgeMap = edgeMap
        self.lumaField = lumaField
        self.cropAspect = cropAspect
        self.cropBounds = cropBounds
        if tool != self.tool {
            self.tool = tool
            // A tool switch mid-drag abandons the draft annotation/endpoint edit
            // and any in-progress caliper placement.
            annotationDrag = nil
            measurePlacement = nil
            measureFirstFootPress = false
            measurePressDownView = nil
            measureHandleDrag = nil
            if captionDrag != nil {
                captionDrag = nil
                onCaptionPlaceCancel()
            }
            alignmentDrag = nil
            alignmentPreviewLayer.isHidden = true
            regionDrag = nil
            regionOutlineDrag = nil
            if regionContentDrag != nil {
                regionContentDrag = nil
                onRegionMoveCancel()
            }
            snapGuide = nil
            applyGrabCursor(nil, force: true)
            endpointDrag = nil
            cropDrag = nil
            transformDrag = nil
            transformHold = nil
            hideMeasureHoverReadout()
            clearAnnotationPreview()
            // …but a typed text draft is worth keeping: commit it. Deferred a
            // tick because this runs inside a SwiftUI update. (A fresh arrow's
            // caption field no longer sees a tool switch on landing: the Arrow
            // tool stays in hand until the field closes.)
            if textSession != nil {
                DispatchQueue.main.async { [weak self] in self?.commitTextSession() }
            }
            pressClosedCaptionField = false
            window?.invalidateCursorRects(for: self)
        }
        if captionCloseRequest != self.captionCloseRequest {
            self.captionCloseRequest = captionCloseRequest
            // The tool bar re-picked the tool in hand while the caption field
            // was open: commit the draft and keep the tool. Deferred a tick,
            // like the tool-switch commit above, because this runs inside a
            // SwiftUI update.
            if textSession?.captionStyle != nil {
                DispatchQueue.main.async { [weak self] in self?.commitTextSession(keepTool: true) }
            }
        }
        // Undo while editing can delete the layer behind the editor.
        if let session = textSession, let layerID = session.layerID,
           let document, document.canvasLayer(id: layerID) == nil {
            DispatchQueue.main.async { [weak self] in self?.cancelTextSession() }
        }
        // The post-commit composite (a different image) now includes the new
        // annotation layer; the held preview shape can come down.
        if annotationCommitImage != nil, image !== annotationCommitImage {
            clearAnnotationPreview()
        }
        self.image = image
        self.viewport = viewport
        self.document = document
        self.selectedLayerID = selectedLayerID
        self.dragPreview = dragPreview
        // The post-commit composite has landed once the preview is cleared; the
        // sprite hold is no longer needed (and must not linger over a selection).
        if dragPreview == nil {
            holdSpriteUntilRender = false
            regionMoveHoldFrame = nil
        }
        // The held delta is only needed while the sprite is still floating.
        if let hold = transformHold, dragPreview?.layerID != hold.layerID {
            transformHold = nil
        }
        // While the user is mid-drag the local state is the truth; don't let an
        // unrelated SwiftUI update echo stale committed values over it.
        if marquee == nil, regionDrag == nil, regionOutlineDrag == nil, regionContentDrag == nil {
            self.selection = selection
            self.selectionTargetsPixels = selectionTargetsPixels
        }
        if cropDrag == nil {
            self.cropRect = cropRect
        }
        if moveDrag == nil, resizeDrag == nil {
            self.selectedLayerFrame = selectedLayerFrame
        }
        self.groupContext = groupContext
        // The document or the selection just changed under a resting pointer (a
        // drag landed, an undo moved a pill): the grab cue has to agree with
        // what is under the pointer NOW, not at the next mouse move.
        refreshGrabCursor()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let image, let viewport else {
            endCalloutFlight()
            contentLayer.isHidden = true
            crispLayer.isHidden = true
            previewSpriteLayer.isHidden = true
            selectionBaseLayer.isHidden = true
            selectionAntsLayer.isHidden = true
            layerOutlineLayer.isHidden = true
            snapGuideLayer.isHidden = true
            snapDotLayer.isHidden = true
            hideMeasureHoverReadout()
            handlesLayer.isHidden = true
            rotateKnobLayer.isHidden = true
            annotationPreviewLayer.isHidden = true
            cropDimLayer.isHidden = true
            cropGridLayer.isHidden = true
            cropBorderLayer.isHidden = true
            cropHandlesLayer.isHidden = true
            if textSession != nil {
                DispatchQueue.main.async { [weak self] in self?.cancelTextSession() }
            }
            return
        }
        contentLayer.isHidden = false
        // refreshPreviewSprite (below) swaps in the underlay + floated sprite
        // while a drag preview is active; the full render replaces both after.
        // A callout flight holds the pre-commit composite so the baked-in
        // callout doesn't show at its destination before the sprite lands.
        contentLayer.contents = calloutHoldImage ?? image
        contentLayer.frame = viewport.documentFrameInView
        contentLayer.shadowPath = CGPath(rect: contentLayer.bounds, transform: nil)
        // Past 2× the user is inspecting pixels — show them squarely instead of smearing.
        contentLayer.magnificationFilter = viewport.zoom >= 2 ? .nearest : .linear

        refreshOverlaysInsideTransaction()
    }

    /// Takes delivery of a redrawn patch of what you can see.
    func applyCrispTile(_ tile: CrispTile?, viewport tileViewport: Viewport?) {
        guard crispTile?.image !== tile?.image || crispTileViewport != tileViewport else { return }
        crispTile = tile
        crispTileViewport = tileViewport
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        refreshCrispDisplay()
        CATransaction.commit()
    }

    /// Lays the redrawn patch over the composite, or takes it away.
    ///
    /// It only goes up while it is still a picture of THIS moment: the camera
    /// where it was drawn, the composite it was drawn from. A drag floats a
    /// sprite over a held-back composite and a callout flight holds the frame
    /// from before the callout landed, so both of those hide it rather than
    /// let a sharp copy of the settled document contradict what is on screen.
    private func refreshCrispDisplay() {
        guard let viewport, let tile = crispTile, crispTileViewport == viewport,
              !contentLayer.isHidden, dragPreview == nil, calloutHoldImage == nil else {
            if !crispLayer.isHidden {
                crispLayer.isHidden = true
                crispLayer.contents = nil
            }
            return
        }
        crispLayer.contents = tile.image
        crispLayer.frame = viewRect(forDocRect: tile.region, in: viewport)
        crispLayer.contentsScale = window?.backingScaleFactor ?? 2
        // At 1:1 with the screen this never resamples; the filter only matters
        // if a fractional zoom leaves it a hair off.
        crispLayer.magnificationFilter = viewport.zoom >= 2 ? .nearest : .linear
        crispLayer.isHidden = false
    }

    func refreshOverlays() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        refreshOverlaysInsideTransaction()
        CATransaction.commit()
    }

    private func refreshOverlaysInsideTransaction() {
        refreshCrispDisplay()
        refreshMarqueeDisplay()
        refreshLayerSelectionDisplay()
        refreshCropDisplay()
        refreshPreviewSprite()
        refreshTextEditorDisplay()
        refreshCollageChrome()
        refreshDropLanding()
        refreshMeasureCreation(modifierFlags: NSEvent.modifierFlags)
    }

    /// Editor-only collage chrome: dashed wells with a plus glyph over every
    /// empty slot (drop discovery), and the accent highlight on whichever slot
    /// an eligible drag currently hovers. Wells skip transformed collages —
    /// axis-aligned chrome on a rotated layer would lie about the target.
    private func refreshCollageChrome() {
        guard let viewport, let document else {
            collageWellsLayer.isHidden = true
            slotHighlightLayer.isHidden = true
            return
        }
        let wells = CGMutablePath()
        for layer in document.layers
        where layer.isVisible && layer.collage != nil && layer.transform.isIdentity {
            guard let content = layer.collage else { continue }
            let cells = Collage.slotFrames(for: content, in: layer.frame.size)
            for (slot, cell) in zip(content.slots, cells) where slot.imageRef == nil {
                let docRect = cell.offsetBy(dx: layer.frame.minX, dy: layer.frame.minY)
                let rect = viewRect(forDocRect: docRect, in: viewport).insetBy(dx: 2, dy: 2)
                guard rect.width > 8, rect.height > 8 else { continue }
                let radius = min(6, rect.width / 2, rect.height / 2)
                wells.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
                let arm = min(10, rect.width / 4, rect.height / 4)
                let center = CGPoint(x: rect.midX, y: rect.midY)
                wells.move(to: CGPoint(x: center.x - arm, y: center.y))
                wells.addLine(to: CGPoint(x: center.x + arm, y: center.y))
                wells.move(to: CGPoint(x: center.x, y: center.y - arm))
                wells.addLine(to: CGPoint(x: center.x, y: center.y + arm))
            }
        }
        collageWellsLayer.path = wells
        collageWellsLayer.isHidden = wells.isEmpty

        if let hoverSlot, let layer = document.canvasLayer(id: hoverSlot.collageID),
           let content = layer.collage {
            let cells = Collage.slotFrames(for: content, in: layer.frame.size)
            if cells.indices.contains(hoverSlot.index) {
                let docRect = cells[hoverSlot.index].offsetBy(dx: layer.frame.minX, dy: layer.frame.minY)
                slotHighlightLayer.path = CGPath(rect: viewRect(forDocRect: docRect, in: viewport),
                                                 transform: nil)
                slotHighlightLayer.isHidden = false
                return
            }
        }
        slotHighlightLayer.isHidden = true
    }

    /// Where the drag in the air would land: a filled outline the exact size of
    /// what it is carrying, plus a dashed box around the frame it would join.
    /// Both are gone the moment the drag leaves or lands.
    private func refreshDropLanding() {
        guard let viewport else {
            dropLandingLayer.isHidden = true
            dropHostFrameLayer.isHidden = true
            return
        }
        guard let landing = dropLanding else {
            dropLandingLayer.isHidden = true
            // A move drag draws no landing box — the layer itself is already
            // under the pointer, so a second outline of the same size would
            // just double the edge — but it draws the same dashed screen.
            outlineHostFrame(adoptionHost, in: viewport)
            return
        }
        let rect = viewRect(forDocRect: landing.rect, in: viewport)
        let radius = min(6, rect.width / 2, rect.height / 2)
        dropLandingLayer.path = CGPath(roundedRect: rect, cornerWidth: radius,
                                            cornerHeight: radius, transform: nil)
        dropLandingLayer.isHidden = false

        outlineHostFrame(landing.host, in: viewport)
    }

    /// The dashed box around the screen a drop would join. Drawn just OUTSIDE
    /// the frame: something the same size as the screen it is joining would
    /// otherwise hide the very cue that says so.
    private func outlineHostFrame(_ host: UUID?, in viewport: Viewport) {
        guard let host, let bounds = document?.canvasBounds(of: host) else {
            dropHostFrameLayer.isHidden = true
            return
        }
        let box = viewRect(forDocRect: bounds, in: viewport).insetBy(dx: -3, dy: -3)
        dropHostFrameLayer.path = CGPath(rect: box, transform: nil)
        dropHostFrameLayer.isHidden = false
    }

    /// The topmost visible, unlocked collage layer whose slot contains the
    /// document-space point (gutters and backdrop margins don't count).
    private func collageSlotTarget(at p: CGPoint,
                                   excluding excluded: UUID? = nil) -> (collageID: UUID, index: Int)? {
        guard let document else { return nil }
        for layer in document.layers.reversed()
        where layer.collage != nil && layer.id != excluded && layer.isVisible && !layer.isLocked {
            if let slot = Collage.slotIndex(at: p, in: layer) { return (layer.id, slot) }
        }
        return nil
    }

    /// Crop chrome: dimmed surround (even-odd: document frame minus the crop
    /// rect), rule-of-thirds grid, white border, eight handles.
    private func refreshCropDisplay() {
        guard tool == .crop, let viewport, let rect = cropRect else {
            cropDimLayer.isHidden = true
            cropGridLayer.isHidden = true
            cropBorderLayer.isHidden = true
            cropHandlesLayer.isHidden = true
            return
        }
        let rectInView = viewRect(forDocRect: rect, in: viewport)

        // For a per-layer crop the dim covers just the layer's frame — only
        // that layer's pixels outside the rect go away.
        let dim = CGMutablePath()
        if let cropBounds {
            dim.addRect(viewRect(forDocRect: cropBounds, in: viewport))
        } else {
            dim.addRect(viewport.documentFrameInView)
        }
        dim.addRect(rectInView)
        cropDimLayer.path = dim

        let grid = CGMutablePath()
        for line in Crop.thirdsLines(in: rect) {
            grid.move(to: viewport.viewPoint(fromDocument: line.from))
            grid.addLine(to: viewport.viewPoint(fromDocument: line.to))
        }
        cropGridLayer.path = grid

        cropBorderLayer.path = CGPath(rect: rectInView, transform: nil)

        let handles = CGMutablePath()
        for handle in ResizeHandle.allCases {
            let p = viewport.viewPoint(fromDocument: Handles.point(for: handle, in: rect))
            handles.addRect(CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9))
        }
        cropHandlesLayer.path = handles

        cropDimLayer.isHidden = false
        cropGridLayer.isHidden = false
        cropBorderLayer.isHidden = false
        cropHandlesLayer.isHidden = false
    }

    /// The frame the drag preview should float at, or nil when the preview
    /// isn't applicable (no preview, or it belongs to another layer).
    private var previewedFrame: CGRect? {
        guard let dragPreview else { return nil }
        // Only float the sprite once a drag is genuinely under way. On mere
        // mouse-DOWN (or before the move threshold) the frame hasn't changed, so
        // showing the sprite would needlessly swap the live composite for the
        // gamma-composited bitmap — which shifts semi-transparent effects like
        // shadows. Keep the real composite until the layer actually moves/resizes.
        if let resizeDrag, resizeDrag.layerID == dragPreview.layerID,
           resizeDrag.frame != resizeDrag.startFrame {
            return resizeDrag.frame
        }
        if let moveDrag, moveDrag.layerID == dragPreview.layerID, moveDrag.moved {
            return CGRect(origin: moveDrag.snapped.origin, size: moveDrag.size)
        }
        // Region content move: the sprite is the lifted region, positioned by
        // its own content frame (not the layer's).
        if let session = regionContentDrag {
            let delta = roundedDelta(from: session.start, to: session.current)
            guard delta != .zero else { return nil }
            return session.frame.offsetBy(dx: delta.x, dy: delta.y)
        }
        if let hold = regionMoveHoldFrame, moveDrag == nil, resizeDrag == nil {
            return hold
        }
        // Drag ended but the post-commit render hasn't landed yet: hold the
        // sprite at the committed frame so nothing flashes. Only after a real
        // commit — never for a static selection (see `holdSpriteUntilRender`).
        if moveDrag == nil, resizeDrag == nil, holdSpriteUntilRender,
           selectedLayerID == dragPreview.layerID {
            return selectedLayerFrame
        }
        return nil
    }

    private func refreshPreviewSprite() {
        // Endpoint drags re-shape the layer per move — a stretched sprite
        // can't represent that, so the vector preview draws over the underlay
        // alone (during the drag and through the post-commit hold).
        if let dragPreview, let holdID = endpointDrag?.layerID ?? endpointHoldLayerID,
           holdID == dragPreview.layerID {
            contentLayer.contents = dragPreview.underlay
            previewSpriteLayer.isHidden = true
            return
        }
        guard let viewport, let dragPreview, let frame = previewedFrame else {
            previewSpriteLayer.isHidden = true
            if let image, !contentLayer.isHidden { contentLayer.contents = image }
            return
        }
        contentLayer.contents = dragPreview.underlay
        previewSpriteLayer.contents = dragPreview.sprite
        let padded = frame.insetBy(dx: -dragPreview.padding, dy: -dragPreview.padding)
        let spriteRect = viewRect(forDocRect: padded, in: viewport)
        // Bounds + position instead of frame: a rotate/skew drag floats the
        // sprite with a delta transform (set below), and CALayer.frame is
        // undefined under a non-identity transform.
        previewSpriteLayer.bounds = CGRect(origin: .zero, size: spriteRect.size)
        previewSpriteLayer.position = CGPoint(x: spriteRect.midX, y: spriteRect.midY)
        previewSpriteLayer.setAffineTransform(spriteDeltaTransform(for: dragPreview.layerID))
        switch dragPreview.blendMode {
        case .normal: previewSpriteLayer.compositingFilter = nil
        case .multiply: previewSpriteLayer.compositingFilter = "multiplyBlendMode"
        case .screen: previewSpriteLayer.compositingFilter = "screenBlendMode"
        }
        previewSpriteLayer.isHidden = false
    }

    /// What a rotate/skew drag adds on top of the sprite bitmap (which was
    /// rendered with the start transform baked in): current ∘ start⁻¹, the
    /// linear parts only — CALayer applies it about the sprite's center,
    /// which coincides with the layer's transform center.
    private func spriteDeltaTransform(for layerID: UUID) -> CGAffineTransform {
        let session: (start: LayerTransform, current: LayerTransform)?
        if let transformDrag, transformDrag.layerID == layerID {
            session = (transformDrag.startTransform, transformDrag.transform)
        } else if let transformHold, transformHold.layerID == layerID {
            session = (transformHold.start, transformHold.transform)
        } else {
            session = nil
        }
        guard let session, session.start != session.current else { return .identity }
        return session.start.affineTransform(around: .zero).inverted()
            .concatenating(session.current.affineTransform(around: .zero))
    }

    private func refreshMarqueeDisplay() {
        // The ants show, in priority order: the live region-tool combination
        // (base region ⊕ in-flight shape as ONE path), the live arrow
        // marquee, else the committed region.
        var antsDocPath: CGPath?
        var marqueeRect: CGRect? // the arrow marquee's live rubber-band rect
        if let session = regionOutlineDrag {
            // Outline-only move: the ants slide with the pointer.
            let delta = roundedDelta(from: session.start, to: session.current)
            antsDocPath = session.base.translated(by: CGVector(dx: delta.x, dy: delta.y))?.path
        } else if let session = regionContentDrag {
            // Content move: the outline travels with the floated pixels.
            let delta = roundedDelta(from: session.start, to: session.current)
            antsDocPath = selection?.translated(by: CGVector(dx: delta.x, dy: delta.y))?.path
        } else if let viewport, let session = regionDrag {
            let shape = session.drag.selectionRect(in: viewport.documentSize)
                .flatMap { session.isEllipse ? SelectionRegion.ellipse(in: $0) : SelectionRegion.rect($0) }
            if let shape {
                antsDocPath = SelectionRegion.combine(selection, with: shape, mode: session.mode)?.path
            } else {
                antsDocPath = selection?.path
            }
        } else if let viewport, let marquee {
            let rect = marquee.selectionRect(in: viewport.documentSize)
            antsDocPath = rect.map { CGPath(rect: $0, transform: nil) }
            marqueeRect = rect
        } else {
            antsDocPath = selection?.path
        }
        if let viewport, let docPath = antsDocPath {
            // Document space → view space is a pure scale + translate (the view
            // is flipped, so no y-inversion).
            let docOrigin = viewport.viewPoint(fromDocument: .zero)
            var docToView = CGAffineTransform(translationX: docOrigin.x, y: docOrigin.y)
                .scaledBy(x: viewport.zoom, y: viewport.zoom)
            let path = docPath.copy(using: &docToView) ?? docPath
            selectionBaseLayer.path = path
            selectionAntsLayer.path = path
            selectionBaseLayer.isHidden = false
            selectionAntsLayer.isHidden = false
        } else {
            selectionBaseLayer.isHidden = true
            selectionAntsLayer.isHidden = true
        }
        refreshMultiSelectOutlines(marqueeRect: marqueeRect)
    }

    /// An outline around every layer in the multi-selection, so what is picked
    /// is obvious on the picture and not just in the Layers list.
    ///
    /// Mid-sweep the set is derived live from the marquee rect; the rest of the
    /// time it is the echoed selection state, whatever put it there — a
    /// committed sweep, a ⇧-click on the canvas, a row click in the list. It
    /// does NOT hang off the rubber band: a ⇧-click selection has no band, and
    /// before this it drew nothing at all.
    private func refreshMultiSelectOutlines(marqueeRect: CGRect?) {
        // The region tools select pixels rather than layers, so their in-flight
        // shape never outlines anything.
        guard let viewport, let document, regionDrag == nil else {
            multiSelectOutlineLayer.isHidden = true
            return
        }
        // Mid-sweep the band says what is picked. A ⇧-press that has not moved
        // is not a sweep — it spares the selection — so what is already picked
        // stays outlined rather than blinking out while the button is down.
        let captured: Set<UUID>
        if marquee != nil, let rect = marqueeRect {
            // With ⇧ the band adds, so mid-sweep it outlines the layers it has
            // taken in AND the ones already picked: what you let go on is what
            // you saw.
            captured = marqueePress.selection(afterSweeping: document.layerIDs(fullyInside: rect),
                                              startingFrom: pickedLayerIDs)
        } else if marquee != nil, marqueePress.clearsSelectionOnPress {
            captured = []
        } else {
            captured = multiSelectedLayerIDs
        }
        let outlines = CGMutablePath()
        // A drag in flight moves the picture per mouse move, but the document
        // still holds the pre-drag positions, so the outlines carry the same
        // offset or they would come away from the layers they belong to. Only
        // what the drag actually carries moves: a locked member holds still.
        let travelling = multiMove?.moved == true
            ? Set(multiMove?.plan.members.map(\.id) ?? []) : []
        let delta = multiMove?.delta ?? .zero
        // Canvas coordinates, so a member that lives inside a group is outlined
        // where it draws rather than where it is stored.
        for id in captured.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let layer = document.canvasLayer(id: id) else { continue }
            let shift = travelling.contains(id) ? delta : .zero
            let corners = layer.transformedCorners.map {
                viewport.viewPoint(fromDocument: CGPoint(x: $0.x + shift.x, y: $0.y + shift.y))
            }
            outlines.addLines(between: corners)
            outlines.closeSubpath()
        }
        multiSelectOutlineLayer.path = outlines
        multiSelectOutlineLayer.isHidden = outlines.isEmpty
    }

    private func refreshLayerSelectionDisplay() {
        refreshGroupContextOutline()
        refreshFrameChrome()
        refreshComponentChrome()
        // The Canvas pseudo-selection: outline + eight handles on the document
        // boundary (or the in-flight proposed boundary). No rotate knob — the
        // canvas doesn't rotate.
        if isCanvasSelected, let viewport {
            rotateKnobLayer.isHidden = true
            snapGuideLayer.isHidden = true
            let docRect = canvasResizeDrag?.rect ?? CGRect(origin: .zero, size: viewport.documentSize)
            let rect = viewRect(forDocRect: docRect, in: viewport).insetBy(dx: 0.5, dy: 0.5)
            layerOutlineLayer.path = CGPath(rect: rect, transform: nil)
            layerOutlineLayer.isHidden = false
            let handles = CGMutablePath()
            for handle in ResizeHandle.allCases {
                let p = viewport.viewPoint(fromDocument: Handles.point(for: handle, in: docRect))
                handles.addRect(CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
            }
            handlesLayer.path = handles
            handlesLayer.isHidden = false
            return
        }
        // A selected layer carries into the region/fill tools (it's the
        // target of region ops), but its outline/handles are SELECT-mode
        // chrome — grabbing them does nothing elsewhere, so hide them.
        guard tool == .select else {
            layerOutlineLayer.isHidden = true
            snapGuideLayer.isHidden = true
            handlesLayer.isHidden = true
            rotateKnobLayer.isHidden = true
            return
        }
        // A multi-selection has no primary layer, so no outline, handles or
        // knob of its own — each member carries its own outline. Its drag still
        // lines up with the picture and with the layers that stayed behind, so
        // the guide is drawn here rather than being lost with the rest.
        if multiMove != nil, let viewport {
            layerOutlineLayer.isHidden = true
            handlesLayer.isHidden = true
            rotateKnobLayer.isHidden = true
            refreshSnapGuides(in: viewport)
            return
        }
        let frame: CGRect?
        if let resizeDrag {
            frame = resizeDrag.frame
        } else if let moveDrag {
            frame = CGRect(origin: moveDrag.snapped.origin, size: moveDrag.size)
        } else {
            frame = selectedLayerFrame
        }
        guard let viewport, let frame else {
            layerOutlineLayer.isHidden = true
            snapGuideLayer.isHidden = true
            handlesLayer.isHidden = true
            rotateKnobLayer.isHidden = true
            return
        }
        guard let selectedLayer = selectedLayerID.flatMap({ id in document?.canvasLayer(id: id) }) else {
            layerOutlineLayer.isHidden = true
            snapGuideLayer.isHidden = true
            handlesLayer.isHidden = true
            rotateKnobLayer.isHidden = true
            return
        }
        let dragInFlight = moveDrag != nil || resizeDrag != nil || transformDrag != nil
            || endpointDrag != nil || endpointHoldLayerID != nil || measureHandleDrag != nil
            || captionDrag != nil
        // The blue selection outline hides during a RESIZE (frame handles,
        // annotation endpoints, a caliper handle, or a caption pill drag that
        // re-shapes the frame) so the edges being aligned stay unobstructed;
        // it still tracks moves and rotates.
        let resizing = resizeDrag != nil || endpointDrag != nil || measureHandleDrag != nil
            || captionDrag != nil

        // The outline (and frame-handle placement) follows the layer's
        // transform — the in-flight one during a rotate/skew drag.
        let activeTransform = transformDrag?.transform ?? selectedLayer.transform
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let docToHandle = activeTransform.isIdentity
            ? CGAffineTransform.identity
            : activeTransform.affineTransform(around: center)
        func chromePoint(_ docPoint: CGPoint) -> CGPoint {
            viewport.viewPoint(fromDocument: docPoint.applying(docToHandle))
        }

        // Universal blue selection box around the frame, for every object type.
        if resizing {
            layerOutlineLayer.isHidden = true
        } else {
            let outline = CGMutablePath()
            outline.addLines(between: [
                chromePoint(CGPoint(x: frame.minX, y: frame.minY)),
                chromePoint(CGPoint(x: frame.maxX, y: frame.minY)),
                chromePoint(CGPoint(x: frame.maxX, y: frame.maxY)),
                chromePoint(CGPoint(x: frame.minX, y: frame.maxY)),
            ])
            outline.closeSubpath()
            layerOutlineLayer.path = outline
            layerOutlineLayer.isHidden = false
        }

        if selectedLayer.hasEndpointHandles {
            // Lines/arrows/measures edit by their endpoints (round handles), not
            // the eight frame handles; no rotate knob.
            rotateKnobLayer.isHidden = true
            if !dragInFlight, offersOwnHandles(selectedLayer) {
                let handles = CGMutablePath()
                // Calipers expose their three handles (two feet + head); lines/
                // arrows their two ends.
                let points: [CGPoint] = selectedLayer.measure != nil
                    ? drawnMeasureHandles(selectedLayer)
                    : AnnotationEndpoint.allCases.compactMap { selectedLayer.editEndpoint($0) }
                for dp in points {
                    let p = viewport.viewPoint(fromDocument: dp)
                    handles.addEllipse(in: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                }
                handlesLayer.path = handles
                handlesLayer.isHidden = false
            } else {
                handlesLayer.isHidden = true
            }
        } else {
            // Eight square frame handles, hidden mid-drag and for text (which
            // resizes width-only via its own affordance).
            if !dragInFlight, offersOwnHandles(selectedLayer), selectedLayer.allowsFrameResize {
                let handles = CGMutablePath()
                for handle in ResizeHandle.allCases {
                    let p = chromePoint(Handles.point(for: handle, in: frame))
                    handles.addRect(CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                }
                handlesLayer.path = handles
                handlesLayer.isHidden = false
            } else {
                handlesLayer.isHidden = true
            }

            // Rotate knob with its stem, off the (transformed) top edge.
            if !dragInFlight, offersRotation(selectedLayer),
               let knob = selectedLayer.rotateKnobPoint(zoom: viewport.zoom) {
                let knobInView = viewport.viewPoint(fromDocument: knob)
                let topMid = chromePoint(CGPoint(x: frame.midX, y: frame.minY))
                let path = CGMutablePath()
                path.move(to: topMid)
                path.addLine(to: knobInView)
                path.addEllipse(in: CGRect(x: knobInView.x - 5, y: knobInView.y - 5,
                                           width: 10, height: 10))
                rotateKnobLayer.path = path
                rotateKnobLayer.isHidden = false
            } else {
                rotateKnobLayer.isHidden = true
            }
        }

        refreshSnapGuides(in: viewport)
    }

    /// The lines that say what a drag just lined itself up with. Guides span
    /// the whole document so the alignment target is obvious. Driven by
    /// layer-move snapping OR a measure corner snapping to a detected UI edge —
    /// both magnetize to a document x/y and want the same full-span line.
    private func refreshSnapGuides(in viewport: Viewport) {
        let guides = CGMutablePath()
        let docFrame = viewport.documentFrameInView
        // A multi-selection snaps by the box it makes, and draws the same
        // guide a one-layer drag does.
        let move = moveDrag?.snapped ?? multiMove.flatMap { $0.moved ? $0.snapped : nil }
        let guideX = move?.guideX ?? snapGuide?.x
        let guideY = move?.guideY ?? snapGuide?.y
        // A line to the picture's own edge or middle spans the whole picture,
        // because that is what it lines up with. A line to another LAYER
        // reaches only across the boxes it joins, with a little overhang, so a
        // canvas full of boxes does not fill with full-height rules every time
        // something is dragged.
        if let x = guideX {
            let vx = viewport.viewPoint(fromDocument: CGPoint(x: x, y: 0)).x
            let ends = viewSpan(move?.guideXSpan, vertical: true, in: viewport)
                ?? (docFrame.minY, docFrame.maxY)
            guides.move(to: CGPoint(x: vx, y: ends.0))
            guides.addLine(to: CGPoint(x: vx, y: ends.1))
        }
        if let y = guideY {
            let vy = viewport.viewPoint(fromDocument: CGPoint(x: 0, y: y)).y
            let ends = viewSpan(move?.guideYSpan, vertical: false, in: viewport)
                ?? (docFrame.minX, docFrame.maxX)
            guides.move(to: CGPoint(x: ends.0, y: vy))
            guides.addLine(to: CGPoint(x: ends.1, y: vy))
        }
        snapGuideLayer.path = guides
        snapGuideLayer.isHidden = guides.isEmpty
    }

    /// A guide's reach, from canvas points into view points, with a few points
    /// of overhang at each end so the line visibly passes THROUGH the boxes it
    /// joins rather than stopping exactly at their corners.
    private func viewSpan(_ span: Snapping.Span?, vertical: Bool,
                          in viewport: Viewport) -> (CGFloat, CGFloat)? {
        guard let span else { return nil }
        let a = vertical
            ? viewport.viewPoint(fromDocument: CGPoint(x: 0, y: span.start)).y
            : viewport.viewPoint(fromDocument: CGPoint(x: span.start, y: 0)).x
        let b = vertical
            ? viewport.viewPoint(fromDocument: CGPoint(x: 0, y: span.end)).y
            : viewport.viewPoint(fromDocument: CGPoint(x: span.end, y: 0)).x
        return (min(a, b) - 6, max(a, b) + 6)
    }

    // MARK: Annotation drag preview

    override func resetCursorRects() {
        if let toolCursor { addCursorRect(bounds, cursor: toolCursor) }
    }

    /// The cursor the ACTIVE TOOL paints over the whole canvas, or nil when it
    /// leaves the plain arrow (Select, Fill). The grab cue restores this when
    /// the pointer leaves a pill, so a hand never lingers over a crosshair tool.
    private var toolCursor: NSCursor? {
        if tool.isRegionSelectionTool {
            // The badge mirrors the LIVE modifiers so the combine mode is
            // visible before the drag starts (⇧ +, ⌥ −, ⇧⌥ ×).
            return SelectionCursor.cursor(for: selectionMode)
        }
        if tool.createsAnnotationByDrag || tool == .crop || tool == .zoomCallout
            || tool == .measure { return .crosshair }
        if tool == .text { return .iBeam }
        return nil
    }

    /// The combine mode the current modifier state implies.
    private var selectionMode: SelectionRegion.Mode {
        SelectionRegion.Mode(shift: pointerModifiers.contains(.shift),
                             option: pointerModifiers.contains(.option))
    }

    /// Modifier keys reach the first responder as flagsChanged, not keyDown;
    /// tracking them keeps the selection cursor's +/−/× badge live.
    override func flagsChanged(with event: NSEvent) {
        pointerModifiers = event.modifierFlags
        if tool.isRegionSelectionTool, let window {
            window.invalidateCursorRects(for: self)
            // invalidate alone waits for the next mouse move; set the cursor
            // now if the pointer is already over the canvas.
            let local = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if bounds.contains(local) {
                SelectionCursor.cursor(for: selectionMode).set()
            }
        }
        // ⌥ pressed or let go over a layer flips the copy badge on the pointer
        // while it rests there, rather than waiting for the next mouse move.
        if tool == .select, moveDrag == nil, multiMove == nil { refreshGrabCursor() }
        // ⌘ toggles measure snapping — refresh the hover dot so it jumps on/off
        // the edge live while held.
        refreshMeasureCreation(modifierFlags: event.modifierFlags)
        super.flagsChanged(with: event)
    }

    func clearAnnotationPreview() {
        annotationCommitImage = nil
        endpointHoldLayerID = nil
        annotationPreviewLayer.isHidden = true
        annotationPreviewLayer.path = nil
        annotationPreviewHeadLayer.path = nil
    }

    /// What the zoom tool's drag box previews with: a box in the callout's
    /// border style, rounded exactly as the source outline the renderer bakes
    /// will be. With the tool set to Circle that makes the draft round, so the
    /// shape you chose is visible while you are still dragging it out rather
    /// than a surprise when the callout lands.
    private func calloutDraftContent(docBox: CGRect) -> AnnotationContent {
        let style = ZoomCalloutBuilder.defaultStyle
        // Matches ZoomCalloutOverlayRasterizer: the callout's radius divided by
        // the magnification, so source outline and box read as one shape.
        let scaled = min(style.cornerRadius / ZoomCalloutBuilder.defaultMagnification,
                         min(docBox.width, docBox.height) / 2)
        let radius = ZoomCalloutContent(sourceRect: docBox, shape: calloutShape)
            .effectiveCornerRadius(boxSize: docBox.size, styleRadius: scaled)
        return AnnotationContent(shape: .rectangle, strokeWidth: max(1, style.borderWidth / 2),
                                 colorHex: style.borderColorHex, cornerRadius: radius)
    }

    /// What the frame tool's drag previews with: a hairline rectangle, so what
    /// you are dragging out reads as the edge of a screen rather than as a
    /// shape you are about to draw.
    private var frameDraftContent: AnnotationContent {
        AnnotationContent(shape: .rectangle, strokeWidth: 1, colorHex: "#8E8E93")
    }

    /// In-flight drag-to-create: preview the active tool's styled content.
    private func refreshAnnotationPreview(constrained: Bool) {
        guard let drag = annotationDrag else {
            clearAnnotationPreview()
            return
        }
        // The callout draft is rounded from the box being dragged, so it is
        // built here where the box is known.
        let docEnd = drag.end(constrained: constrained, shape: .rectangle)
        var draft = tool == .zoomCallout
            ? calloutDraftContent(docBox: CGRect(x: min(drag.anchor.x, docEnd.x),
                                                 y: min(drag.anchor.y, docEnd.y),
                                                 width: abs(docEnd.x - drag.anchor.x),
                                                 height: abs(docEnd.y - drag.anchor.y)))
            : nil
        if tool == .frame { draft = frameDraftContent }
        guard let content = annotationContent ?? draft ?? tool.defaultAnnotation else {
            clearAnnotationPreview()
            return
        }
        displayAnnotationPreview(content: content, docStart: drag.anchor,
                                 docEnd: drag.end(constrained: constrained, shape: content.shape),
                                 style: annotationStyle)
    }

    /// In-flight endpoint drag: preview the selected layer's content with the
    /// dragged endpoint applied.
    private func refreshEndpointPreview(constrained: Bool) {
        guard let session = endpointDrag else {
            clearAnnotationPreview()
            return
        }
        let (docStart, docEnd) = session.drag.endpoints(constrained: constrained)
        displayAnnotationPreview(content: session.content, docStart: docStart, docEnd: docEnd,
                                 style: document?.canvasLayer(id: session.layerID)?.style)
    }

    /// Draws an annotation as vector shapes in view coordinates — faithful to
    /// the rasterizer so the held preview swaps invisibly for the real
    /// composite after commit.
    private func displayAnnotationPreview(content: AnnotationContent,
                                          docStart: CGPoint, docEnd: CGPoint,
                                          style: LayerStyle? = nil) {
        guard let viewport else {
            clearAnnotationPreview()
            return
        }
        let start = viewport.viewPoint(fromDocument: docStart)
        let end = viewport.viewPoint(fromDocument: docEnd)
        let strokeWidth = content.strokeWidth * viewport.zoom
        let rgba = RGBA(hex: content.colorHex) ?? RGBA(r: 1, g: 0, b: 0)
        let color = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        let box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: abs(end.x - start.x), height: abs(end.y - start.y))

        let path = CGMutablePath()
        let headPath = CGMutablePath()
        var fill: CGColor?
        var stroke: CGColor? = color
        // The outline width the preview strokes with — the annotation's own
        // stroke by default, overridden below for box shapes whose outline is a
        // layer-style border.
        var lineWidth = strokeWidth
        var compositing: Any?
        switch content.shape {
        case .line:
            path.move(to: start)
            path.addLine(to: end)
        case .arrow:
            // Stop the shaft inside the head (doc space → view space) so its cap
            // doesn't poke past the tip, matching the rasterizer.
            let shaftEndDoc = Geometry.arrowShaftEnd(start: docStart, end: docEnd,
                                                     strokeWidth: content.strokeWidth,
                                                     scale: content.arrowheadScale)
            path.move(to: start)
            path.addLine(to: viewport.viewPoint(fromDocument: shaftEndDoc))
            // Head geometry in document space (its minimum size is in doc
            // points), then mapped to view coords.
            let head = Geometry.arrowhead(start: docStart, end: docEnd,
                                          strokeWidth: content.strokeWidth,
                                          scale: content.arrowheadScale)
            headPath.addLines(between: head.map { viewport.viewPoint(fromDocument: $0) })
            headPath.closeSubpath()
        case .rectangle, .ellipse:
            // A box shape's outline can be the annotation's own stroke OR a
            // layer-style border (the Border toggle — rectangles use this, with
            // strokeWidth 0). Draw whichever is set so the draft isn't invisible.
            if content.strokeWidth == 0, let border = style, border.borderWidth > 0 {
                lineWidth = border.borderWidth * viewport.zoom
                if let brgba = RGBA(hex: border.borderColorHex) {
                    stroke = CGColor(srgbRed: brgba.r, green: brgba.g, blue: brgba.b, alpha: brgba.a)
                }
            }
            // Inset by half the outline so it reads as an inner stroke, matching
            // the rasterizer and the layer border.
            let inset = box.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            if inset.width > 0, inset.height > 0 {
                if content.shape == .rectangle {
                    let radius = min(content.cornerRadius * viewport.zoom,
                                     min(inset.width, inset.height) / 2)
                    if radius > 0 {
                        path.addRoundedRect(in: inset, cornerWidth: radius, cornerHeight: radius)
                    } else {
                        path.addRect(inset)
                    }
                } else {
                    path.addEllipse(in: inset)
                }
            }
            // Interior fill previews live so the draft matches the commit.
            if let fillHex = content.fillColorHex, let rgba = RGBA(hex: fillHex) {
                fill = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
            }
            // Nothing to stroke if the shape carries no outline at all (fill
            // only): a zero line width would still draw a hairline.
            if lineWidth <= 0 { stroke = nil }
        case .highlight:
            path.addRect(box)
            fill = color
            stroke = nil
            compositing = "multiplyBlendMode"
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        annotationPreviewLayer.path = path
        annotationPreviewLayer.strokeColor = stroke
        annotationPreviewLayer.fillColor = fill
        annotationPreviewLayer.lineWidth = lineWidth
        // Match the rasterizer: rectangles corner with miters (no fake radius).
        annotationPreviewLayer.lineJoin = content.shape == .rectangle ? .miter : .round
        annotationPreviewLayer.compositingFilter = compositing
        annotationPreviewHeadLayer.path = headPath
        annotationPreviewHeadLayer.fillColor = color
        annotationPreviewLayer.isHidden = false
        CATransaction.commit()
    }

    // MARK: Zoom-callout creation flight

    /// Animates a just-committed callout from its source box to its placed
    /// frame: the sprite is the on-screen composite cropped to the source
    /// region (the pixels the callout magnifies), growing into the styled box
    /// while the source outline and leader lines fade in underneath. The
    /// pre-commit composite holds on screen for the duration; the baked render
    /// (already landed by then) is revealed when the flight ends.
    private func beginCalloutFlight(for calloutLayer: Layer) {
        guard let viewport, let image, let callout = calloutLayer.zoomCallout,
              viewport.documentSize.width > 0, viewport.documentSize.height > 0 else { return }
        let scaleX = CGFloat(image.width) / viewport.documentSize.width
        let scaleY = CGFloat(image.height) / viewport.documentSize.height
        let cropRect = CGRect(x: callout.sourceRect.minX * scaleX,
                              y: callout.sourceRect.minY * scaleY,
                              width: callout.sourceRect.width * scaleX,
                              height: callout.sourceRect.height * scaleY)
        guard let sprite = image.cropping(to: cropRect) else { return }

        calloutHoldImage = image
        calloutFlightGeneration += 1
        let generation = calloutFlightGeneration

        let zoom = viewport.zoom
        let style = calloutLayer.style
        let magnification = max(callout.magnification, 0.01)
        let startFrame = viewRect(forDocRect: callout.sourceRect, in: viewport)
        let endFrame = viewRect(forDocRect: calloutLayer.frame, in: viewport)
        let rgba = RGBA(hex: style.borderColorHex) ?? RGBA(r: 1, g: 0, b: 0)
        let borderColor = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)

        // Chrome that fades in: source outline + leader lines, matching what
        // the renderer bakes (ZoomCalloutOverlayRasterizer's styling).
        // Both radii go through the callout's own rule, so a circle flies as a
        // circle instead of landing square and snapping round a frame later.
        let sourceRadius = callout.effectiveCornerRadius(
            boxSize: startFrame.size,
            styleRadius: (style.cornerRadius / magnification) * zoom)
        let boxRadius = callout.effectiveCornerRadius(boxSize: endFrame.size,
                                                      styleRadius: style.cornerRadius * zoom)
        let outlinePath = CGPath(roundedRect: startFrame,
                                 cornerWidth: sourceRadius, cornerHeight: sourceRadius,
                                 transform: nil)
        let leaderPath = CGMutablePath()
        for line in Geometry.leaderLines(source: callout.sourceRect, callout: calloutLayer.frame) {
            leaderPath.move(to: viewport.viewPoint(fromDocument: line.from))
            leaderPath.addLine(to: viewport.viewPoint(fromDocument: line.to))
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        calloutFlightLayer.contents = sprite
        calloutFlightLayer.frame = startFrame
        calloutFlightLayer.borderColor = borderColor
        calloutFlightLayer.borderWidth = style.borderWidth * zoom
        calloutFlightLayer.cornerRadius = sourceRadius
        calloutFlightLayer.isHidden = false
        calloutFlightOutlineLayer.path = outlinePath
        calloutFlightOutlineLayer.strokeColor = borderColor
        calloutFlightOutlineLayer.lineWidth = style.borderWidth * zoom
        calloutFlightOutlineLayer.opacity = 0
        calloutFlightOutlineLayer.isHidden = false
        calloutFlightLeaderLayer.path = leaderPath
        calloutFlightLeaderLayer.strokeColor = borderColor.copy(alpha: 0.6 * borderColor.alpha)
        calloutFlightLeaderLayer.lineWidth = style.borderWidth * zoom
        calloutFlightLeaderLayer.opacity = 0
        calloutFlightLeaderLayer.isHidden = false
        CATransaction.commit()

        // The sprite springs into place (slight overshoot reads as the box
        // "landing"); the chrome fades in on a plain ease-out underneath.
        let startBounds = CGRect(origin: .zero, size: startFrame.size)
        let endBounds = CGRect(origin: .zero, size: endFrame.size)
        func spring(_ keyPath: String, from: Any?, to: Any?) -> CASpringAnimation {
            let animation = CASpringAnimation(perceptualDuration: 0.45, bounce: 0.25)
            animation.keyPath = keyPath
            animation.fromValue = from
            animation.toValue = to
            return animation
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.calloutFlightGeneration == generation else { return }
            self.endCalloutFlight()
        }
        calloutFlightLayer.add(spring("position",
                                      from: NSValue(point: CGPoint(x: startFrame.midX, y: startFrame.midY)),
                                      to: NSValue(point: CGPoint(x: endFrame.midX, y: endFrame.midY))),
                               forKey: "position")
        calloutFlightLayer.add(spring("bounds",
                                      from: NSValue(rect: startBounds),
                                      to: NSValue(rect: endBounds)),
                               forKey: "bounds")
        calloutFlightLayer.add(spring("cornerRadius",
                                      from: sourceRadius,
                                      to: boxRadius),
                               forKey: "cornerRadius")
        func fadeIn() -> CABasicAnimation {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.35
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            return fade
        }
        calloutFlightOutlineLayer.add(fadeIn(), forKey: "opacity")
        calloutFlightLeaderLayer.add(fadeIn(), forKey: "opacity")
        CATransaction.setDisableActions(true)
        calloutFlightLayer.position = CGPoint(x: endFrame.midX, y: endFrame.midY)
        calloutFlightLayer.bounds = endBounds
        calloutFlightLayer.cornerRadius = boxRadius
        calloutFlightOutlineLayer.opacity = 1
        calloutFlightLeaderLayer.opacity = 1
        CATransaction.commit()
    }

    /// Tears the flight down and reveals the latest composite (which has the
    /// callout baked in at its destination).
    private func endCalloutFlight() {
        guard calloutHoldImage != nil || !calloutFlightLayer.isHidden else { return }
        calloutHoldImage = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for flightLayer in [calloutFlightLayer, calloutFlightOutlineLayer, calloutFlightLeaderLayer] {
            flightLayer.isHidden = true
            flightLayer.removeAllAnimations()
        }
        calloutFlightLayer.contents = nil
        contentLayer.contents = image
        CATransaction.commit()
    }

    // MARK: Inline text editing

    /// Opens the inline editor at `origin` (document coords). For a re-edit,
    /// the editor takes over the layer's string and style; EditorState hides the
    /// layer underneath via `onTextEditBegin`.
    private func beginTextSession(layerID: UUID?, at origin: CGPoint) {
        guard textSession == nil else { return }
        // Nothing typed is ever thrown away: a piece inside a copy takes its
        // words from the original, so the field opens only when there is a
        // wording knob for those words to land on, and otherwise says why.
        if let layerID, componentsEnabled,
           case .refused(let refusal) = document?.wordingEdit(of: layerID) {
            onWordingRefused(refusal)
            return
        }
        var style = textContent ?? TextContent(string: "")
        var string = ""
        if let layerID, let layer = document?.canvasLayer(id: layerID),
           case .text(let existing) = layer.content {
            string = existing.string
            style = existing
            style.string = ""
            // The editor replaces the selection chrome.
            selectedLayerFrame = nil
            onSelectLayer(nil)
        }
        textSession = TextEditSession(layerID: layerID, origin: origin,
                                      alignment: style.alignment,
                                      verticalAlignment: style.verticalAlignment)

        let editor = makeInlineEditor()
        editor.string = string
        addSubview(editor)
        textEditor = editor
        textEditorZoom = 0 // force the style pass below to apply
        styleTextEditor(with: style)
        window?.makeFirstResponder(editor)
        // Words that are already there are offered ready to be replaced, the
        // way double clicking a label does everywhere else. With the caret
        // parked after them instead, a new label came out welded to the old
        // one ("ButtonSave all the changes", reported 2026-09-04). A click
        // inside the field afterwards drops the highlight and takes the caret
        // where it landed, so re-wording one word is still one click away.
        let opening = TextEntry.openingSelection(for: string)
        editor.setSelectedRange(NSRange(location: opening.location, length: opening.length))
        onTextEditBegin(layerID)
        refreshOverlays()
    }

    /// The spot a caption field takes for its whole session: a hand-placed pill
    /// keeps the spot it was dropped at, anything else is picked against the
    /// picture with room for a sentence, so a long caption never has to slide
    /// back or flip sides halfway through typing it.
    private func captionPlacement(for layer: Layer, canvas: CGSize) -> CaptionPlacement {
        guard var probe = layer.annotation,
              let tail = layer.annotationEndpoint(.start),
              let head = layer.annotationEndpoint(.end) else { return CaptionPlacement() }
        if probe.captionPinned, probe.captionOffset != nil {
            return CaptionPlacement(attach: probe.captionOffset, growth: probe.captionGrowth)
        }
        probe.start = tail
        probe.end = head
        // The planner only places a pill that has text; a fresh arrow's field
        // is empty, so it plans against the room a caption will need.
        if !probe.hasCaption { probe.caption = "A" }
        return CaptionPlanner.plan(for: probe, canvas: canvas,
                                   reserving: probe.captionRoomProbeSize)
    }

    /// Opens the inline caption editor on an arrow (Next `next-arrow-captions`):
    /// a single-line field centered where the pill renders, tinted with the
    /// pill's tone so the draft is legible over any image. Return commits, Esc
    /// abandons, clicking elsewhere commits — an empty commit means no caption.
    /// `layer` is passed in whole because the freshly created arrow may not
    /// have reached this view's `document` snapshot yet.
    func beginCaptionSession(layer: Layer) {
        guard textSession == nil, let viewport,
              let a = layer.annotation, a.shape == .arrow else { return }
        let placement = captionPlacement(for: layer, canvas: viewport.documentSize)
        var draft = a
        draft.captionOffset = placement.attach
        draft.captionGrowth = placement.growth
        let anchor = draft.captionAnchor()
        let center = CGPoint(x: layer.frame.minX + anchor.x, y: layer.frame.minY + anchor.y)
        let style = TextContent(string: "", fontName: "SF Pro", fontSize: a.captionFontSize,
                                colorHex: AnnotationContent.captionTextColorHex)
        textSession = TextEditSession(layerID: layer.id, origin: center, captionStyle: style,
                                      captionLayer: layer, captionPlacement: placement)

        let editor = makeInlineEditor()
        editor.commitsOnPlainReturn = true
        // A fresh (or never captioned) arrow says how to skip. A re-edit of an
        // existing label starts with that label selected instead.
        if a.caption == nil { editor.placeholder = ArrowCaptionEntry.placeholder }
        // The draft sits INSIDE the bubble the caption will render in: a pill
        // view behind the field carries the fill, border, capsule and shadow
        // (a text view's own background is a plain rect and would clip the
        // shadow), and the field's inset is the pill's padding. Typing and
        // committing are then one shape, not two controls.
        editor.drawsBackground = false
        editor.layer?.borderWidth = 0
        editor.layer?.cornerRadius = 0
        // Selecting the label (a re-edit starts that way) tints the words
        // rather than dropping a system-colored slab into the bubble.
        editor.selectedTextAttributes = [.backgroundColor: NSColor(white: 1, alpha: 0.3),
                                         .foregroundColor: NSColor.white]
        editor.string = a.caption ?? ""
        let pill = CaptionPillView()
        addSubview(pill)
        captionPill = pill
        addSubview(editor)
        textEditor = editor
        textEditorZoom = 0 // force the style pass below to apply
        styleTextEditor(with: style)
        window?.makeFirstResponder(editor)
        let opening = TextEntry.openingSelection(for: editor.string)
        editor.setSelectedRange(NSRange(location: opening.location, length: opening.length))
        onCaptionEditBegin(layer.id)
        refreshOverlays()
    }

    /// The inline editor overlay both text and caption sessions share, before
    /// their session-specific styling.
    private func makeInlineEditor() -> InlineTextView {
        let editor = InlineTextView()
        editor.onCommit = { [weak self] in self?.commitTextSession() }
        editor.onCancel = { [weak self] in self?.cancelTextSession() }
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isVerticallyResizable = false
        editor.isHorizontallyResizable = false
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        // The container wraps at an explicit cap (layoutTextEditor) while the
        // editor frame hugs the typed text, so the box grows with content instead
        // of spanning to the canvas edge.
        editor.textContainer?.widthTracksTextView = false
        editor.wantsLayer = true
        editor.layer?.borderColor = NSColor.controlAccentColor.cgColor
        editor.layer?.borderWidth = 1
        editor.layer?.cornerRadius = 2
        editor.delegate = self
        return editor
    }

    /// The face any draft is set in — a caption's or a text block's: the
    /// content's DOCUMENT-size font with a scale transform for the zoom, never
    /// the zoomed point size. SF spaces letters differently at different point
    /// sizes, so a draft set at (size x zoom) is a few percent wider or
    /// narrower than what the rasterizer bakes at the document size and the
    /// canvas then scales. That gap is what made a long caption's far edge jump
    /// on Return, and what made a text block wrap at a different word than the
    /// label it committed to. Scaling the document-size face instead gives the
    /// draft exactly the committed letter spacing.
    ///
    /// Going through the descriptor is also the only way the WEIGHT survives:
    /// the resolved system face has no name AppKit will answer to
    /// (".SFNS-Regular" resolves to nothing), so the old name lookup fell back
    /// to the plain system font and typed a bold label in regular.
    private static func draftFont(_ content: TextContent, zoom: CGFloat) -> NSFont {
        let descriptor = (TextRasterizer.faceDescriptor(for: content) as NSFontDescriptor)
            .withSize(content.fontSize)
        var transform = AffineTransform()
        transform.scale(zoom)
        return NSFont(descriptor: descriptor, textTransform: transform)
            ?? NSFont.systemFont(ofSize: content.fontSize * zoom)
    }

    /// Applies font/color to the editor, scaled to the current zoom so the
    /// draft is the same apparent size as the rasterized layer will be.
    /// `content.string` is ignored.
    private func styleTextEditor(with content: TextContent) {
        guard let editor = textEditor, let viewport else { return }
        var stored = content
        stored.string = ""
        // The font picker's style says nothing about where the words sit, so a
        // re-edit's placement rides on the session and gets stamped back on
        // here. Without it, restyling mid-edit dropped a centred label to the
        // left edge until Return put it back.
        if let session = textSession, session.captionStyle == nil {
            stored.alignment = session.alignment
            stored.verticalAlignment = session.verticalAlignment
        }
        textEditorContent = stored
        textEditorZoom = viewport.zoom

        let font = Self.draftFont(stored, zoom: viewport.zoom)
        let rgba = RGBA(hex: content.colorHex) ?? RGBA(r: 1, g: 1, b: 1)
        let color = NSColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        editor.font = font
        editor.textColor = color
        editor.insertionPointColor = color
        editor.typingAttributes = [.font: font, .foregroundColor: color]
        if let storage = editor.textStorage, storage.length > 0 {
            storage.addAttributes([.font: font, .foregroundColor: color],
                                  range: NSRange(location: 0, length: storage.length))
        }
        // The draft sits where the committed words will: a centred label is
        // typed centred rather than jumping on Return.
        if textSession?.captionStyle == nil {
            switch stored.usedAlignment {
            case .left: editor.alignment = .left
            case .center: editor.alignment = .center
            case .right: editor.alignment = .right
            }
        }
        layoutTextEditor()
    }

    /// The wrap cap (document points) for a text block placed at `origin`.
    /// `TextBlockMetrics` owns the rule; the committed frame asks it the same
    /// question, so nothing wraps in one place and not the other.
    private func textWrapWidth(origin: CGPoint) -> CGFloat {
        guard let viewport else { return TextRasterizer.minimumTextWidth }
        return TextBlockMetrics.wrapWidth(origin: origin, in: viewport.documentSize)
    }

    /// Positions the editor over the session origin and sizes it.
    ///
    /// The field IS the box it commits to: its frame comes straight from
    /// `TextBlockMetrics` — the same measurement `commitTextEdit` sizes the
    /// layer with — scaled to the zoom, and the text container is that same
    /// box, so AppKit breaks the draft's lines exactly where CoreText will
    /// break the placed label's. Nothing here measures the typed text a second
    /// way, which is what used to make the box drift and the wrap move on
    /// Return.
    ///
    /// A caption session is a different shape and hands off to
    /// `layoutCaptionEditor`.
    private func layoutTextEditor() {
        guard let editor = textEditor, let viewport, let session = textSession else { return }
        if session.captionStyle != nil, let caption = session.captionLayer?.annotation {
            layoutCaptionEditor(editor, caption: caption, session: session, viewport: viewport)
            return
        }
        let zoom = viewport.zoom
        var draft = textEditorContent ?? TextContent(string: "")
        draft.string = editor.string
        // A box bigger than its words — a paragraph, or a label told to stretch
        // across what holds it — keeps the room it has, exactly as the commit
        // does, so re-wording one re-wraps in place.
        let room = roomyBox(session)
        let box = TextBlockMetrics.frameSize(for: draft,
                                             maxWidth: textWrapWidth(origin: session.origin),
                                             roomyWidth: room.width, roomyHeight: room.height)
        // Words that sit low in a roomy box are typed low in it too.
        editor.textContainerInset = NSSize(width: 0,
                                           height: TextBlockMetrics.topInset(for: draft, in: box) * zoom)
        editor.textContainer?.containerSize = NSSize(width: box.width * zoom,
                                                     height: .greatestFiniteMagnitude)
        let topLeft = viewport.viewPoint(fromDocument: session.origin)
        editor.frame = CGRect(x: topLeft.x, y: topLeft.y,
                              width: box.width * zoom, height: box.height * zoom)
    }

    /// The room the box being re-edited has beyond its words; both nil for a
    /// new block and for a box that hugs what is in it.
    private func roomyBox(_ session: TextEditSession) -> (width: CGFloat?, height: CGFloat?) {
        guard Experiments.shared.placementEnabled,
              session.captionStyle == nil, let layerID = session.layerID,
              let layer = document?.canvasLayer(id: layerID),
              let words = layer.text else { return (nil, nil) }
        return TextBlockMetrics.roomyBox(for: words, frame: layer.frame)
    }

    /// A caption field IS the pill it commits to. Its frame comes straight from
    /// `CaptionMetrics` — the same measurement the rasterizer bakes the
    /// committed pill with — scaled to the zoom, so nothing here measures the
    /// typed text a second way and the bubble does not resize on Return. The
    /// draft lays out inside it at the pill's padding, in the document-size face
    /// (`captionDraftFont`), which is why the words fit the measurement.
    ///
    /// The bubble hangs off the spot the session froze when it opened: its near
    /// edge stays put on the arrow's tail and the words extend away from it, so
    /// what you watch while typing is where the caption lands.
    private func layoutCaptionEditor(_ editor: NSTextView, caption: AnnotationContent,
                                     session: TextEditSession, viewport: Viewport) {
        let zoom = viewport.zoom
        let inset = caption.captionPadding * zoom
        editor.textContainerInset = NSSize(width: inset, height: inset)
        var pill = CaptionMetrics.pillSize(for: editor.string, in: caption)
        if editor.string.isEmpty, let placeholder = (editor as? InlineTextView)?.placeholder,
           let font = editor.font {
            // An empty field is as wide as its hint, so the hint reads in one
            // line; the bubble shrinks to the text on the first keystroke.
            let hint = (placeholder as NSString).size(withAttributes: [.font: font]).width / zoom
            pill.width = max(pill.width, hint + 2 * caption.captionPadding + 4)
        }
        // A caption is one line at any length, exactly like the committed pill,
        // so the container is given the whole bubble and never wraps.
        editor.textContainer?.containerSize = NSSize(width: max(1, pill.width * zoom),
                                                     height: .greatestFiniteMagnitude)
        var center = session.origin
        if var probe = session.captionLayer?.annotation,
           let tail = session.captionLayer?.annotationEndpoint(.start),
           let head = session.captionLayer?.annotationEndpoint(.end) {
            probe.start = tail
            probe.end = head
            probe.captionOffset = session.captionPlacement.attach
            probe.captionGrowth = session.captionPlacement.growth
            center = probe.captionPillCenter(forPillSize: pill)
        }
        let pillCenter = viewport.viewPoint(fromDocument: center)
        let width = pill.width * zoom
        let height = pill.height * zoom
        // Not rounded to whole points: the committed pill is drawn at document
        // resolution and scaled, so it lands on fractions too, and snapping the
        // bubble to the screen grid would put its edges up to half a point off
        // the label it is standing in for.
        let frame = CGRect(x: pillCenter.x - width / 2, y: pillCenter.y - height / 2,
                           width: width, height: height)
        editor.frame = frame
        // The rasterizer's border straddles the pill's edge (a centered stroke)
        // while a layer's border is drawn inside its bounds, so the bubble is
        // grown by half a border and its inner stroke lands on the same band.
        // Without this the drawn edge sits half a border in from where the
        // committed one does.
        let straddle = caption.captionBorderWidth * zoom / 2
        captionPill?.frame = frame.insetBy(dx: -straddle, dy: -straddle)
        captionPill?.style(for: caption, zoom: zoom)
    }

    /// Keeps the editor glued to the document while panning/zooming, and
    /// restyles it when the font picker changes the style mid-edit.
    private func refreshTextEditorDisplay() {
        guard let session = textSession, let viewport else { return }
        // Caption sessions keep their fixed style; text sessions track the
        // font picker's live style.
        let desired = session.captionStyle ?? textContent
        if let content = desired, content != textEditorContent || viewport.zoom != textEditorZoom {
            styleTextEditor(with: content)
        } else {
            layoutTextEditor()
        }
    }

    /// `keepTool` is the canvas press that closes the fresh arrow's field and
    /// starts the next arrow in the same gesture: the Arrow tool stays in hand.
    private func commitTextSession(keepTool: Bool = false) {
        guard let session = textSession, let editor = textEditor else { return }
        let string = editor.string
        if session.captionStyle != nil, let layerID = session.layerID {
            teardownTextSession()
            onCaptionCommit(layerID, string, session.captionPlacement, keepTool)
            return
        }
        // Same wrap cap the live editor used, so layout doesn't shift on commit.
        let maxWidth = textWrapWidth(origin: session.origin)
        teardownTextSession()
        onTextCommit(session.layerID, session.origin, string, maxWidth)
    }

    private func cancelTextSession() {
        guard let session = textSession else { return }
        teardownTextSession()
        if session.captionStyle != nil {
            onCaptionCancel()
        } else {
            onTextCancel()
        }
    }

    private func teardownTextSession() {
        textSession = nil
        textEditorContent = nil
        textEditorZoom = 0
        captionPill?.removeFromSuperview()
        captionPill = nil
        guard let editor = textEditor else { return }
        textEditor = nil
        if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: editor) {
            window?.makeFirstResponder(self)
        }
        editor.removeFromSuperview()
    }

    func viewRect(forDocRect r: CGRect, in viewport: Viewport) -> CGRect {
        let topLeft = viewport.viewPoint(fromDocument: r.origin)
        return CGRect(x: topLeft.x, y: topLeft.y,
                      width: r.width * viewport.zoom, height: r.height * viewport.zoom)
    }
}

extension CanvasNSView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        // A name field on the canvas grows with the name being typed.
        if notification.object as AnyObject? === canvasNameField {
            layoutCanvasNameField()
            return
        }
        layoutTextEditor()
    }

    /// The caption editor losing keyboard focus (most often a click into the
    /// inspector's Caption field) commits its draft, so there is only ever one
    /// caption draft open and whichever field you type in next starts from the
    /// committed text. Deferred a tick: this fires inside AppKit's responder
    /// hand-off, and tearing the editor down there would re-enter
    /// `makeFirstResponder`. Text-tool sessions are exempt on purpose: the font
    /// picker takes focus mid-edit and the block must stay open through it.
    func textDidEndEditing(_ notification: Notification) {
        // A canvas name field losing the keyboard any other way — a click into
        // the Layers list, another window — lands the name rather than dropping
        // it, which is what a rename field does everywhere else on the Mac.
        if notification.object as AnyObject? === canvasNameField {
            DispatchQueue.main.async { [weak self] in self?.commitCanvasRename() }
            return
        }
        guard textSession?.captionStyle != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.commitTextSession() }
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // A canvas name field answers Return and Escape itself.
        if textView === canvasNameField { return false }
        // Esc abandons the draft (a re-edited layer reappears unchanged).
        // NSTextView routes Esc to completion in some states, so catch both.
        if commandSelector == #selector(NSResponder.cancelOperation(_:))
            || commandSelector == #selector(NSTextView.complete(_:)) {
            cancelTextSession()
            return true
        }
        return false
    }
}

/// The bubble behind an open arrow caption. Everything it draws — the fill,
/// the border in the arrow's ink, the capsule corner, the drop shadow — comes
/// off `AnnotationContent`, the same values `AnnotationRasterizer` bakes into
/// the committed caption, so typing and committing are one shape.
///
/// It is a view of its own rather than the text field's own background because
/// a text view fills a plain rectangle and clips its layer to it: the capsule
/// and its shadow need to live outside the field's bounds. Clicks pass
/// straight through to the field on top of it.
private final class CaptionPillView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { nil }

    func style(for annotation: AnnotationContent, zoom: CGFloat) {
        guard let layer else { return }
        let chip = annotation.captionChipColor
        layer.backgroundColor = CGColor(srgbRed: chip.r, green: chip.g, blue: chip.b,
                                        alpha: AnnotationContent.captionChipOpacity)
        let ink = RGBA(hex: annotation.colorHex) ?? RGBA(r: 1, g: 0.23, b: 0.19)
        layer.borderColor = CGColor(srgbRed: ink.r, green: ink.g, blue: ink.b, alpha: ink.a)
        layer.borderWidth = max(1, annotation.captionBorderWidth * zoom)
        layer.cornerRadius = annotation.captionCornerRadius(pillHeight: bounds.height)
        // The rasterizer's shadow: a 4px blur two pixels down, black at 35%.
        // A CALayer's blur radius is half a CGContext's.
        layer.shadowColor = CGColor(gray: 0, alpha: 1)
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 2 * zoom
        layer.shadowOffset = CGSize(width: 0, height: 2 * zoom)
    }
}

/// The inline text editor. A plain `NSTextView` treats Return as a newline; this
/// subclass commits the edit on **⌘Return** (and keypad ⌘Enter) via `onCommit`,
/// leaving plain Return to insert a line break.
private final class InlineTextView: NSTextView {
    var onCommit: () -> Void = {}
    var onCancel: () -> Void = {}
    /// Caption entry is single-line: plain Return commits instead of inserting
    /// a newline. Text blocks keep Return-as-newline and commit on ⌘Return.
    var commitsOnPlainReturn = false
    /// Drawn in the text color at reduced opacity while the field is empty
    /// (NSTextView has no placeholder of its own).
    var placeholder: String? {
        didSet { needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        if commitsOnPlainReturn {
            // The caption field's keys are decided in PhotonzCore so the rule
            // (letters always type, even tool shortcuts) is tested there.
            let key: ArrowCaptionEntry.Key
            if event.keyCode == 36 || event.keyCode == 76 {
                key = .return
            } else if event.keyCode == 53 {
                key = .escape
            } else {
                key = .text(event.charactersIgnoringModifiers ?? "")
            }
            switch ArrowCaptionEntry.action(for: key) {
            case .commit: onCommit(); return
            case .cancel: onCancel(); return
            case .type: break
            }
        } else if (event.keyCode == 36 || event.keyCode == 76),
                  event.modifierFlags.contains(.command) {
            onCommit()
            return
        }
        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        if placeholder != nil { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let placeholder, string.isEmpty, let font else { return }
        let color = (textColor ?? .white).withAlphaComponent(0.55)
        let origin = textContainerOrigin
        (placeholder as NSString).draw(
            at: NSPoint(x: origin.x + (textContainer?.lineFragmentPadding ?? 0), y: origin.y),
            withAttributes: [.font: font, .foregroundColor: color])
    }
}
