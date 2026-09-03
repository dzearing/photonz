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
    let onTextCommit: (UUID?, CGPoint, String, CGFloat) -> Void
    let onTextCancel: () -> Void
    let onCaptionEditBegin: (UUID) -> Void
    /// (layer, draft, keepTool): keepTool is the press that starts the next arrow.
    let onCaptionCommit: (UUID, String, CaptionPlacement, Bool) -> Void
    let onCaptionCancel: () -> Void
    let onDeleteLayer: (UUID) -> Void
    let onDeleteLayers: ([UUID]) -> Void
    let onDropImageURL: (URL) -> Void
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
                   annotationStyle: annotationStyle, textContent: textContent,
                   measureContent: measureContent,
                   measureToolMode: measureToolMode,
                   measureCandidateLevel: measureCandidateLevel,
                   measureSnapsToCenters: measureSnapsToCenters, edgeMap: edgeMap,
                   lumaField: lumaField, isCanvasSelected: isCanvasSelected)
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
        view.onClickedNothing = onClickedNothing
        view.onExitGroup = onExitGroup
        view.onDragBegin = onDragBegin
        view.onFramePreview = onFramePreview
        view.onFrameCommit = onFrameCommit
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
        view.onTextCommit = onTextCommit
        view.onTextCancel = onTextCancel
        view.onCaptionEditBegin = onCaptionEditBegin
        view.onCaptionCommit = onCaptionCommit
        view.onCaptionCancel = onCaptionCancel
        view.onDeleteLayer = onDeleteLayer
        view.onDeleteLayers = onDeleteLayers
        view.onDropImageURL = onDropImageURL
        view.onDropImageURLIntoCollage = onDropImageURLIntoCollage
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
    var onClickedNothing: (() -> Void) = {}
    var onExitGroup: (() -> Bool) = { false }
    var onDragBegin: ((UUID) -> Void) = { _ in }
    var onFramePreview: ((UUID, CGRect) -> Void) = { _, _ in }
    var onFrameCommit: ((UUID, CGRect) -> Void) = { _, _ in }
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
    var onDropImageURL: ((URL) -> Void) = { _ in }
    /// A file dropped straight into a collage slot: (url, collage layer, slot).
    var onDropImageURLIntoCollage: ((URL, UUID, Int) -> Void) = { _, _, _ in }
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
    private var multiSelectedLayerIDs: Set<UUID> = []
    /// Pre-rendered drag preview from EditorState; arrives async after drag start
    /// and outlives the drag until the post-commit render lands.
    private var dragPreview: DragPreview?
    /// In-progress marquee (document coordinates). While set, it is what the
    /// ants display — same zero-latency-echo pattern as pan/zoom.
    private var marquee: MarqueeDrag?
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

    /// In-progress layer move.
    private struct MoveDrag {
        let layerID: UUID
        /// Pointer offset from the frame origin at grab time (doc coords).
        let grabOffset: CGPoint
        let size: CGSize
        let startOrigin: CGPoint
        var snapped: Snapping.Result
        /// Becomes true once the pointer travels past the click tolerance;
        /// a click that never moves selects without committing a move.
        var moved = false
    }
    private var moveDrag: MoveDrag?

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
        guard let layer, !layer.transform.isIdentity else { return p }
        let center = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
        return p.applying(layer.transform.affineTransform(around: center).inverted())
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

    /// The rotate knob's position in document coordinates: floated off the
    /// midpoint of the layer's (transformed) top edge, 18 screen points out.
    private func rotateKnobPoint(for layer: Layer, zoom: CGFloat) -> CGPoint? {
        let corners = layer.transformedCorners
        guard corners.count == 4, zoom > 0 else { return nil }
        let topMid = CGPoint(x: (corners[0].x + corners[1].x) / 2,
                             y: (corners[0].y + corners[1].y) / 2)
        let center = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
        let dx = topMid.x - center.x
        let dy = topMid.y - center.y
        let length = hypot(dx, dy)
        guard length > 0 else { return CGPoint(x: topMid.x, y: topMid.y - 18 / zoom) }
        let offset = 18 / zoom
        return CGPoint(x: topMid.x + dx / length * offset, y: topMid.y + dy / length * offset)
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

        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Drag destination (drop an image to add it as a layer)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedURL(sender) != nil ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard droppedURL(sender) != nil else { return [] }
        // Highlight the collage slot under the pointer — dropping there fills
        // the slot instead of adding a floating layer.
        hoverSlot = dropTarget(for: sender)
        refreshOverlays()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hoverSlot = nil
        refreshOverlays()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hoverSlot = nil
        refreshOverlays()
        guard let url = droppedURL(sender) else { return false }
        if url.pathExtension.lowercased() != "photonz", let target = dropTarget(for: sender) {
            onDropImageURLIntoCollage(url, target.collageID, target.index)
        } else {
            onDropImageURL(url)
        }
        return true
    }

    private func dropTarget(for sender: NSDraggingInfo) -> (collageID: UUID, index: Int)? {
        guard let viewport else { return nil }
        let p = viewport.documentPoint(fromView: convert(sender.draggingLocation, from: nil))
        return collageSlotTarget(at: p)
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
        refreshGrabCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoverPoint = nil
        applyGrabCursor(nil)
        if tool == .measure { refreshMeasureCreation(modifierFlags: event.modifierFlags) }
    }

    // MARK: Grab cue (draggable readout pills)

    /// The hand currently forced onto the pointer by `applyGrabCursor`, so a
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

    /// Open hand while the pointer rests on something that drags on its own —
    /// a pill, or one of a caliper's dots. Nothing else on the canvas said
    /// those could be moved, so this is the whole invitation. A drag in flight
    /// keeps its closed hand.
    private func refreshGrabCursor(at viewPoint: CGPoint? = nil) {
        guard captionDrag == nil, measureHandleDrag == nil else { return }
        let point = viewPoint ?? window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        guard let viewport, let point, bounds.contains(point) else { return applyGrabCursor(nil) }
        let hit = grabCue(at: viewport.documentPoint(fromView: point))
        applyGrabCursor(hit == nil ? nil : .openHand)
    }

    /// Forces `cursor` onto the pointer, or gives it back. Only a CHANGE
    /// touches `NSCursor`: mouseMoved fires constantly and re-setting the same
    /// cursor flickers it on some setups.
    private func applyGrabCursor(_ cursor: NSCursor?) {
        guard cursor !== grabCursor else { return }
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
        let p = viewport.documentPoint(fromView: convert(event.locationInWindow, from: nil))
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
               let handle = Handles.hit(at: p, frame: rect, zoom: viewport.zoom, screenTolerance: 8) {
                cropDrag = CropDrag(kind: .resize(handle), startRect: rect, lastPoint: p)
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
        if let id = selectedLayerID, let layer = selectedLayer, let content = layer.annotation,
           let endpoint = AnnotationEndpoints.hit(at: p, layer: layer, zoom: viewport.zoom),
           let drag = AnnotationEndpointDrag(layer: layer, endpoint: endpoint),
           let start = layer.annotationEndpoint(.start), let end = layer.annotationEndpoint(.end) {
            endpointDrag = EndpointDragSession(layerID: id, content: content,
                                               originalStart: start, originalEnd: end, drag: drag)
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
        if let id = selectedLayerID, let layer = selectedLayer, let m = layer.measure,
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
           let knob = rotateKnobPoint(for: layer, zoom: viewport.zoom),
           hypot(p.x - knob.x, p.y - knob.y) * viewport.zoom <= 8 {
            let center = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
            transformDrag = TransformDragSession(
                layerID: id, kind: .rotate(grabAngle: TransformDrag.pointerAngle(p, around: center)),
                startTransform: layer.transform, center: center,
                frameSize: layer.frame.size, transform: layer.transform)
            onDragBegin(id)
            refreshOverlays()
            return
        }
        // Frame handles. The pointer maps through the layer's inverse
        // transform so handles on a rotated/skewed layer hit where they draw.
        // ⌥ on a corner skews instead of resizing.
        if let id = selectedLayerID, let frame = selectedLayerFrame,
           selectedLayer?.allowsFrameResize ?? true,
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
            onSelectLayerInGroup(pick.id, pick.context)
            onDragBegin(hit.id)
            selectedLayerFrame = hit.frame
            moveDrag = MoveDrag(layerID: hit.id,
                                grabOffset: CGPoint(x: p.x - hit.frame.origin.x,
                                                    y: p.y - hit.frame.origin.y),
                                size: hit.frame.size,
                                startOrigin: hit.frame.origin,
                                snapped: Snapping.Result(origin: hit.frame.origin))
        } else {
            onClickedNothing()
            if selectedLayerFrame != nil || isCanvasSelected {
                selectedLayerFrame = nil
                onSelectLayer(nil) // also drops the Canvas pseudo-selection
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
            if !drag.moved {
                let travel = hypot(proposed.x - drag.startOrigin.x, proposed.y - drag.startOrigin.y)
                drag.moved = travel * viewport.zoom >= 4
            }
            if drag.moved {
                drag.snapped = Snapping.snapFrameOrigin(proposed, size: drag.size,
                                                        canvas: viewport.documentSize,
                                                        zoom: viewport.zoom)
                onFramePreview(drag.layerID, CGRect(origin: drag.snapped.origin, size: drag.size))
            }
            // A dragged photo layer offers itself to collage slots under the
            // pointer — releasing over the highlighted cell absorbs it.
            if drag.moved, document?.canvasLayer(id: drag.layerID)?.imageRef != nil {
                hoverSlot = collageSlotTarget(at: p, excluding: drag.layerID)
            } else {
                hoverSlot = nil
            }
            moveDrag = drag
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
            refreshOverlays(constrainSquare: event.modifierFlags.contains(.shift))
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
                                                        canvas: viewport.documentSize) {
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
            refreshOverlays()
        } else if let session = transformDrag {
            transformDrag = nil
            if session.transform != session.startTransform {
                // Hold the sprite at the final transform until the post-commit
                // composite lands — otherwise it flashes back.
                transformHold = (session.layerID, session.startTransform, session.transform)
                onTransformCommit(session.layerID, session.transform)
            }
            refreshOverlays()
        } else if let drag = resizeDrag {
            resizeDrag = nil
            if drag.frame != drag.startFrame {
                selectedLayerFrame = drag.frame
                holdSpriteUntilRender = true
                onFrameCommit(drag.layerID, drag.frame)
            }
            refreshOverlays()
        } else if let drag = moveDrag {
            moveDrag = nil
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
                onFrameCommit(drag.layerID, frame)
            }
            hoverSlot = nil
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
            if drag.isClick(atZoom: viewport.zoom) {
                commitSelection(nil, capture: true) // a plain click deselects
            } else {
                let square = event.modifierFlags.contains(.shift)
                let rect = drag.selectionRect(constrainSquare: square, in: viewport.documentSize)
                commitSelection(rect.map(Geometry.pixelAligned).flatMap(SelectionRegion.rect),
                                capture: true)
            }
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
                let frame = CGRect(origin: drag.startOrigin, size: drag.size)
                selectedLayerFrame = frame
                onFrameCommit(drag.layerID, frame)
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
            applyGrabCursor(nil)
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

    func refreshOverlays(constrainSquare: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        refreshOverlaysInsideTransaction(constrainSquare: constrainSquare)
        CATransaction.commit()
    }

    private func refreshOverlaysInsideTransaction(constrainSquare: Bool = false) {
        refreshMarqueeDisplay(constrainSquare: constrainSquare)
        refreshLayerSelectionDisplay()
        refreshCropDisplay()
        refreshPreviewSprite()
        refreshTextEditorDisplay()
        refreshCollageChrome()
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

    private func refreshMarqueeDisplay(constrainSquare: Bool) {
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
            let rect = marquee.selectionRect(constrainSquare: constrainSquare, in: viewport.documentSize)
            antsDocPath = rect.map { CGPath(rect: $0, transform: nil) }
            marqueeRect = rect
        } else {
            antsDocPath = selection?.path
        }
        guard let viewport, let docPath = antsDocPath else {
            selectionBaseLayer.isHidden = true
            selectionAntsLayer.isHidden = true
            multiSelectOutlineLayer.isHidden = true
            return
        }
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

        // Rubber-band capture (arrow marquee only — the region tools select
        // pixels, not layers): outline every captured layer so it's obvious
        // what the marquee holds. Mid-drag the capture is derived live from
        // the rect; once committed it's the echoed selection state, which
        // survives rect-independent edits (a hidden member stays outlined).
        let outlines = CGMutablePath()
        if let document, regionDrag == nil {
            let captured = marquee != nil
                ? marqueeRect.map { Set(document.layerIDs(fullyInside: $0)) } ?? []
                : multiSelectedLayerIDs
            for layer in document.layers where captured.contains(layer.id) {
                let corners = layer.transformedCorners.map { viewport.viewPoint(fromDocument: $0) }
                outlines.addLines(between: corners)
                outlines.closeSubpath()
            }
        }
        multiSelectOutlineLayer.path = outlines
        multiSelectOutlineLayer.isHidden = outlines.isEmpty
    }

    private func refreshLayerSelectionDisplay() {
        refreshGroupContextOutline()
        refreshFrameChrome()
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
            if !dragInFlight {
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
            if !dragInFlight, selectedLayer.allowsFrameResize {
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
               let knob = rotateKnobPoint(for: selectedLayer, zoom: viewport.zoom) {
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

        // Guides span the whole document so the alignment target is obvious.
        // Driven by layer-move snapping OR a measure corner snapping to a detected
        // UI edge — both magnetize to a document x/y and want the same full-span line.
        let guides = CGMutablePath()
        let docFrame = viewport.documentFrameInView
        let guideX = moveDrag?.snapped.guideX ?? snapGuide?.x
        let guideY = moveDrag?.snapped.guideY ?? snapGuide?.y
        if let x = guideX {
            let vx = viewport.viewPoint(fromDocument: CGPoint(x: x, y: 0)).x
            guides.move(to: CGPoint(x: vx, y: docFrame.minY))
            guides.addLine(to: CGPoint(x: vx, y: docFrame.maxY))
        }
        if let y = guideY {
            let vy = viewport.viewPoint(fromDocument: CGPoint(x: 0, y: y)).y
            guides.move(to: CGPoint(x: docFrame.minX, y: vy))
            guides.addLine(to: CGPoint(x: docFrame.maxX, y: vy))
        }
        snapGuideLayer.path = guides
        snapGuideLayer.isHidden = guides.isEmpty
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

    /// What the zoom tool's drag box previews with: a rectangle in the
    /// callout's border style, so the box that flies out matches the draft.
    private var calloutDraftContent: AnnotationContent {
        let style = ZoomCalloutBuilder.defaultStyle
        return AnnotationContent(shape: .rectangle, strokeWidth: max(1, style.borderWidth / 2),
                                 colorHex: style.borderColorHex)
    }

    /// What the frame tool's drag previews with: a hairline rectangle, so what
    /// you are dragging out reads as the edge of a screen rather than as a
    /// shape you are about to draw.
    private var frameDraftContent: AnnotationContent {
        AnnotationContent(shape: .rectangle, strokeWidth: 1, colorHex: "#8E8E93")
    }

    /// In-flight drag-to-create: preview the active tool's styled content.
    private func refreshAnnotationPreview(constrained: Bool) {
        var draft = tool == .zoomCallout ? calloutDraftContent : nil
        if tool == .frame { draft = frameDraftContent }
        guard let drag = annotationDrag,
              let content = annotationContent ?? draft ?? tool.defaultAnnotation else {
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
        let sourceRadius = (style.cornerRadius / magnification) * zoom
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
                                      to: style.cornerRadius * zoom),
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
        calloutFlightLayer.cornerRadius = style.cornerRadius * zoom
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
        textSession = TextEditSession(layerID: layerID, origin: origin)

        let editor = makeInlineEditor()
        editor.string = string
        addSubview(editor)
        textEditor = editor
        textEditorZoom = 0 // force the style pass below to apply
        styleTextEditor(with: style)
        window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: string.utf16.count, length: 0))
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
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
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

    /// The face a caption draft is set in: the caption's DOCUMENT-size font with
    /// a scale transform for the zoom, never the zoomed point size. SF spaces
    /// letters differently at different point sizes, so a draft set at
    /// (size x zoom) is a few percent wider or narrower than the pill the
    /// rasterizer bakes at the document size and the canvas then scales. That
    /// gap is what made a long caption's far edge jump on Return. Scaling the
    /// document-size face instead gives the draft exactly the committed
    /// letter spacing, so the words you type occupy the pill they will land in.
    private static func captionDraftFont(_ content: TextContent, fontSize: CGFloat,
                                         zoom: CGFloat) -> NSFont {
        var document = content
        document.fontSize = fontSize
        let ctFont = TextRasterizer.font(for: document)
        let descriptor = (CTFontCopyFontDescriptor(ctFont) as NSFontDescriptor).withSize(fontSize)
        var transform = AffineTransform()
        transform.scale(zoom)
        return NSFont(descriptor: descriptor, textTransform: transform)
            ?? NSFont.systemFont(ofSize: fontSize * zoom)
    }

    /// Applies font/color to the editor, scaled to the current zoom so the
    /// draft is the same apparent size as the rasterized layer will be.
    /// `content.string` is ignored.
    private func styleTextEditor(with content: TextContent) {
        guard let editor = textEditor, let viewport else { return }
        var stored = content
        stored.string = ""
        textEditorContent = stored
        textEditorZoom = viewport.zoom

        let font: NSFont
        if textSession?.captionStyle != nil {
            font = Self.captionDraftFont(stored, fontSize: content.fontSize, zoom: viewport.zoom)
        } else {
            var scaled = stored
            scaled.fontSize = content.fontSize * viewport.zoom
            // The rasterizer picks the face (family + weight); reuse it via its
            // PostScript name so the draft and the final render match.
            let ctFont = TextRasterizer.font(for: scaled)
            font = NSFont(name: CTFontCopyPostScriptName(ctFont) as String, size: scaled.fontSize)
                ?? NSFont.systemFont(ofSize: scaled.fontSize)
        }
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
        layoutTextEditor()
    }

    /// The wrap cap (document points) for a text block placed at `origin`: the
    /// box wraps at 60% of the canvas, but never past the right edge and never
    /// below the minimum width. The committed frame re-measures with the same cap.
    private func textWrapWidth(origin: CGPoint) -> CGFloat {
        guard let viewport else { return TextRasterizer.minimumTextWidth }
        let toEdge = viewport.documentSize.width - origin.x
        let cap = viewport.documentSize.width * 0.6
        return max(min(toEdge, cap), TextRasterizer.minimumTextWidth)
    }

    /// Positions the editor over the session origin and sizes it: the box wraps
    /// at `textWrapWidth` but its frame HUGS the laid-out text (floored at the
    /// minimum width), so it grows with what you type instead of spanning to the
    /// canvas edge. Height hugs the laid-out text.
    ///
    /// A caption session is a different shape and hands off to
    /// `layoutCaptionEditor`: its frame IS the pill it commits to, measured once
    /// by the renderer rather than a second time here.
    private func layoutTextEditor() {
        guard let editor = textEditor, let viewport, let session = textSession else { return }
        if session.captionStyle != nil, let caption = session.captionLayer?.annotation {
            layoutCaptionEditor(editor, caption: caption, session: session, viewport: viewport)
            return
        }
        let topLeft = viewport.viewPoint(fromDocument: session.origin)
        let minView = TextRasterizer.minimumTextWidth * viewport.zoom
        let capView = max(minView, textWrapWidth(origin: session.origin) * viewport.zoom)
        var contentWidth = minView
        var height = (editor.font?.pointSize ?? 20) * 1.4
        if let container = editor.textContainer, let layoutManager = editor.layoutManager {
            container.containerSize = NSSize(width: capView, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container)
            // Hug the longest laid-out line (+ caret slack), floored at the
            // minimum and capped at the wrap width.
            contentWidth = min(capView, max(minView, ceil(used.width) + 3))
            height = max(height, used.height + 2)
        }
        editor.frame = CGRect(x: topLeft.x, y: topLeft.y, width: contentWidth, height: ceil(height))
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
        guard textSession?.captionStyle != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.commitTextSession() }
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
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
