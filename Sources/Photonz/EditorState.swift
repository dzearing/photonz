import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

/// One editor window's state: the document it is holding, what is selected,
/// what tool is up, and every intent the UI can issue against it.
///
/// This file holds the state itself and the core of the window: opening and
/// saving, the viewport, tools, undo/redo, and rendering. Everything else is
/// grouped by what it is for and lives in `EditorState+<Area>.swift` beside
/// it, one extension per file. Add an intent to the file that names its area;
/// add a new area by adding a file.
///
/// One consequence of the split: a member two of those files share cannot stay
/// `private`, because `private` in Swift means "this file". Anything reached
/// from more than one of them is module-internal instead. The type is still
/// the only owner of its state; the compiler just cannot say so as narrowly.
@MainActor
@Observable
final class EditorState {
    private(set) var history: History?
    let store = ImageStore()
    /// Per-image detected UI edges, computed lazily on first use and reused for
    /// every measure-corner snap. Keyed by `ImageRef`, so it survives undo/redo.
    @ObservationIgnored let edgeMapCache = EdgeMapCache()
    /// Edge maps that finished analysis, ready for synchronous access during a
    /// drag. Observable so the canvas picks the map up when analysis lands.
    var readyEdgeMaps: [UUID: EdgeMapAnalyzer.Analysis] = [:]
    /// Refs whose analysis is in flight (don't kick it twice).
    @ObservationIgnored var edgeMapAnalysisPending: Set<UUID> = []
    /// Created lazily (not in init) so its frame-delivery closure can capture self.
    private var scheduler: RenderScheduler?

    /// The composited document, refreshed asynchronously after every edit
    /// (latest-wins: rapid edits coalesce instead of queueing renders).
    private(set) var renderedImage: CGImage?

    /// Zoomed in, the canvas would be stretching one document-sized picture
    /// over four or sixteen screen pixels each, which is what makes a label you
    /// placed go soft while the one you are typing stays sharp. This is the
    /// part of the document you can see, drawn again at the resolution it is
    /// being shown at, laid over the stretched picture.
    private(set) var crispTile: CrispTile?
    /// The camera the tile was drawn for. It only goes on screen while that is
    /// still where the camera is, so a pan or a zoom never leaves a sharp copy
    /// of the old framing sitting in the wrong place.
    private(set) var crispTileViewport: Viewport?
    /// Its own renderer, so redrawing what you can see never competes for the
    /// content caches the interactive composite depends on.
    @ObservationIgnored private let tileRenderer = DocumentRenderer()
    @ObservationIgnored private var crispTileTask: Task<Void, Never>?
    var isImporterPresented = false
    var isResizeDialogPresented = false
    var isCanvasSizeDialogPresented = false
    /// Live inspector visibility. The view drives this from BOTH the user's
    /// show/hide and the width-based auto-collapse, so it is transient — the
    /// persisted *preference* that survives relaunch (and feeds window sizing)
    /// is `inspectorPreferredVisible`, written only on an explicit toggle.
    var isLayersPanelVisible = EditorState.inspectorPreferredVisibleDefault
    /// Whether the right dock carries the Library shelf (Next,
    /// `next-library`). Its own switch, separate from the dock's: the dock is
    /// where someone who only redlines lives, so the Library is there only
    /// once View ▸ Show Library asks for it, and the answer persists.
    var isLibraryVisible = EditorState.libraryVisibleDefault {
        didSet { UserDefaults.standard.set(isLibraryVisible, forKey: Self.libraryVisibleKey) }
    }
    var isExportDialogPresented = false
    /// The "how big?" sheet the empty window's Blank canvas row opens.
    var isBlankCanvasDialogPresented = false
    /// The size sheet Layer ▸ New Frame… opens (Next, `next-frames`).
    var isNewFrameDialogPresented = false

    /// The user's persisted show/hide preference for the docked inspector.
    /// Distinct from `isLayersPanelVisible`: auto-collapse never touches this,
    /// so `sizeWindowToImage()` can reserve the pane's width for a fresh window
    /// even before layout has decided whether the pane is currently shown.
    var inspectorPreferredVisible = EditorState.inspectorPreferredVisibleDefault {
        didSet { UserDefaults.standard.set(inspectorPreferredVisible, forKey: Self.inspectorVisibleKey) }
    }

    // MARK: Persisted inspector state (shared with EditorView's @AppStorage)

    static let inspectorVisibleKey = "inspector.visible"
    static let libraryVisibleKey = "inspector.libraryVisible"
    /// Off until asked for: with the Library holding nothing but your
    /// captures, a dock that grew a new section on its own would be a change
    /// nobody asked for.
    static var libraryVisibleDefault: Bool {
        UserDefaults.standard.object(forKey: libraryVisibleKey) as? Bool ?? false
    }
    static let inspectorWidthKey = "inspector.width"
    /// Default matches EditorView's `@AppStorage("inspector.width")` seed.
    static let inspectorWidthDefault: CGFloat = 264
    /// A 1pt resize-handle border sits to the left of the panel content, so the
    /// pane occupies `width + 1` in the window (mirrors EditorView's layout).
    static let inspectorHandleWidth: CGFloat = 1

    static var inspectorPreferredVisibleDefault: Bool {
        UserDefaults.standard.object(forKey: inspectorVisibleKey) as? Bool ?? true
    }
    /// The persisted docked-inspector width, in points.
    static var persistedInspectorWidth: CGFloat {
        (UserDefaults.standard.object(forKey: inspectorWidthKey) as? Double).map { CGFloat($0) }
            ?? inspectorWidthDefault
    }

    /// Explicit user show/hide of the inspector (menu or in-window toggle):
    /// updates the live visibility AND persists the preference. Auto-collapse
    /// must NOT route through here — it only mutates `isLayersPanelVisible`.
    /// Explicit user show/hide of the Library shelf (the View menu). Showing
    /// it opens the dock too, because a shelf inside a hidden dock is a menu
    /// item that appears to do nothing; hiding it drops any tile that was
    /// picked, so the inspector is not left describing something off screen.
    func setLibraryVisible(_ visible: Bool) {
        isLibraryVisible = visible
        if visible {
            setInspectorVisible(true)
            // ...and ask the dock to scroll it into view. The dock is one tall
            // column and the shelf sits at the bottom of it, so on a normal
            // window opening the Library without this is a menu item that
            // changes nothing you can see.
            pendingLibraryReveal = true
        } else {
            selectedLibraryItemID = nil
            pendingLibraryReveal = false
            pendingLibraryTileID = nil
        }
    }

    /// True from the moment the app opens the Library shelf until the dock has
    /// put it on screen, whether you asked through the View menu or a command
    /// opened it for you. A flag rather than a call so it survives the dock
    /// being closed at the time: showing the Library opens the dock too, and
    /// the panel that has to do the scrolling is drawn a beat later.
    ///
    /// The dock clears it with `libraryRevealHandled()`, and it clears itself
    /// if the shelf is put away first. Scrolling is the dock's own business,
    /// so what happens next lives there (`DockReveal` decides whether anything
    /// needs to move at all).
    private(set) var pendingLibraryReveal = false

    func libraryRevealHandled() { pendingLibraryReveal = false }

    /// The tile the shelf itself has to scroll to, until it has.
    ///
    /// Bringing the Library into view puts the SHELF on screen; it says nothing
    /// about where a tile sits inside the shelf's own scroll, and the shelf
    /// shows about two rows. A component you just made is listed after the ones
    /// already in the document, so with a handful saved it lands below that
    /// inner fold: the shelf is on screen and your work is not. A command that
    /// makes something the shelf holds names it here, and the shelf scrolls to
    /// it if it has to (`LibraryShelfLayout.tileReveal` decides whether it has
    /// to, so a tile already showing never moves).
    var pendingLibraryTileID: String?

    func libraryTileRevealHandled() { pendingLibraryTileID = nil }

    func setInspectorVisible(_ visible: Bool) {
        isLayersPanelVisible = visible
        inspectorPreferredVisible = visible
    }

    /// Canvas camera. Nil until a document is open. All zoom/pan flows through
    /// `Viewport` (PhotonzCore) so the math stays tested.
    private(set) var viewport: Viewport? {
        didSet {
            // Move the camera and the sharp copy of what you were looking at is
            // about the wrong place; draw the new framing.
            if viewport != oldValue { refreshCrispTile() }
        }
    }
    /// The selected REGION (Photoshop-style) in document coordinates: any
    /// path — marquee rect, ellipse, wand blob, or boolean combinations.
    /// Nil = no selection. Distinct from layer selection; while a region
    /// exists, region ops (fill, copy, promote) target it.
    var selection: SelectionRegion?
    /// True when the region was made by a region tool (rect/ellipse/wand) —
    /// pixel semantics: ⌫ erases pixels, ⌘C copies the clipped composite,
    /// bucket fills the region. False for the arrow tool's marquee, which
    /// keeps its layer semantics (rubber-band capture, batch delete).
    private(set) var selectionTargetsPixels = false
    /// Magic-wand color tolerance (Euclidean RGBA distance, 0–255 units).
    /// Persisted like the fill colors — a tuned tolerance outlives relaunch.
    var wandTolerance: Double = UserDefaults.standard.object(forKey: EditorState.wandToleranceKey)
        .flatMap { $0 as? Double } ?? 32 {
        didSet { UserDefaults.standard.set(wandTolerance, forKey: Self.wandToleranceKey) }
    }
    static let wandToleranceKey = "wand.tolerance"

    /// The grid you build against (Next, `next-canvas-grid`). A VIEW
    /// preference: remembered between launches, carried by no document, and
    /// drawn by the canvas rather than the renderer, so it never reaches an
    /// export, a copied picture or a redline sheet. Not the same thing as a
    /// screen's column overlay, which belongs to one frame and is saved with
    /// the document.
    /// One grid for the whole app, so two windows open side by side are never
    /// showing different ones, and switching it on in either switches it on in
    /// both. See `CanvasGridStore`.
    var canvasGrid: CanvasGridSettings {
        get { CanvasGridStore.shared.settings }
        set { CanvasGridStore.shared.settings = newValue }
    }
    static let canvasGridKey = CanvasGridStore.defaultsKey

    /// What the canvas should actually draw: nothing at all unless the feature
    /// is on AND the grid is switched on, so with either off the canvas is
    /// exactly what it was.
    var drawnCanvasGrid: CanvasGridSettings? {
        guard Experiments.shared.canvasGridEnabled, canvasGrid.isVisible else { return nil }
        return canvasGrid
    }

    func toggleCanvasGrid() { canvasGrid.isVisible.toggle() }

    func setCanvasGridAxes(_ axes: CanvasGridAxes) { canvasGrid.axes = axes }

    /// Typing a spacing switches the grid ON: nobody sets a number for a grid
    /// they cannot see.
    func setCanvasGridSpacing(_ spacing: CGFloat) {
        canvasGrid.spacing = CanvasGridSettings.clamped(spacing: spacing)
        canvasGrid.isVisible = true
    }

    func setCanvasGridMajorEvery(_ every: Int) {
        canvasGrid.majorEvery = CanvasGridSettings.clamped(majorEvery: every)
        canvasGrid.isVisible = true
    }
    /// The active editor tool. Drawing tools are STICKY (Photoshop-style, 17.12):
    /// after a shape is drawn the tool stays active so you can draw more of them.
    /// Switch to `.select` (V) to adjust a placed shape.
    private(set) var activeTool: Tool = .select
    /// The pending crop rect (document coords) while the crop tool is active.
    var cropRect: CGRect?
    /// Crop aspect lock; the crop rect always honors it.
    var cropAspect: CropAspect = .free
    /// When set, crop mode targets this layer (non-destructive content crop)
    /// instead of the whole document.
    private(set) var cropTargetLayerID: UUID?
    /// Styling for new annotations, set from the style popover. Persisted so
    /// the user's color/width survive relaunches.
    var annotationStyles: AnnotationStyles = EditorState.loadAnnotationStyles()
    /// Styling for new text blocks, set from the font picker. Persisted like
    /// annotation styles.
    var textStyles: TextStyles = EditorState.loadTextStyles()
    /// The measure tool's persisted memory: colors, thickness, label size, unit.
    /// Every measure setter writes it back to UserDefaults, so the next caliper —
    /// this session or after a relaunch — starts where the last one left off.
    // strokeWidth is in LOGICAL pixels (rendered ×pixelScale) so a 1px sizer line
    // aligns with the image's pixel grid.
    var measureStyles: MeasureStyles = EditorState.loadMeasureStyles()
    /// The zoom callout tool's persisted memory: box or circle. The Zoom
    /// Callout Tool section sets it, drawing a callout reads it, and changing a
    /// picked callout's shape absorbs into it the way every other style edit
    /// absorbs into the tool that drew it.
    var calloutStyles: CalloutStyles = EditorState.loadCalloutStyles()
    /// Template content for a new caliper. The axis, feet, and head offset are
    /// set per placement, so mode/start/end/headOffset here are placeholders.
    var measureStyle: MeasureContent { measureStyles.content }
    /// Recently committed colors, SHARED across annotations/text/borders (13.2).
    /// Recorded on commit only (never on live preview) and persisted.
    var recentColors: RecentColors = EditorState.loadRecentColors()
    /// The text layer being re-edited inline. Hidden from renders while the
    /// canvas's editor overlay visually replaces it.
    var editingTextLayerID: UUID?
    /// The arrow whose caption is being edited inline. Its pill (not the
    /// arrow) is suppressed from renders while the editor overlay stands in.
    var editingCaptionLayerID: UUID?
    /// Bumped when the tool bar asks the open caption field to close while
    /// keeping the tool in hand (re-picking the active tool). The canvas owns
    /// the draft, so it answers by committing with `keepTool`.
    private(set) var captionCloseRequest = 0
    /// The layer targeted by click-to-select / drag-to-move. Nil = none.
    /// Any change to the primary selection dissolves a marquee multi-selection —
    /// the two never coexist.
    ///
    /// Every store this touches is written ONLY when it actually changes.
    /// `@Observable` tells the views about a write whether or not the value
    /// moved, and a click that set five unchanged properties re-ran every
    /// section of the inspector that reads any of them (measured 2026-09-03:
    /// part of a 40-60ms main-thread stall per click).
    var selectedLayerID: UUID? {
        didSet {
            if oldValue != selectedLayerID {
                if !multiSelectedLayerIDs.isEmpty { multiSelectedLayerIDs = [] }
                // A fresh primary selection is what the next shift-click in
                // a list ranges from, wherever it came from (canvas, panel,
                // a new layer).
                rowSelection = ListSelection(selected: selectedLayerID.map { [$0] } ?? [],
                                             anchor: selectedLayerID)
                // The list agrees with the canvas: double clicking into a
                // group on the canvas opens the groups above it in the panel,
                // so the row that is selected is a row you can see.
                if let selectedLayerID { revealInLayersList(selectedLayerID) }
            }
            // Selecting anything (or explicitly deselecting) drops the Canvas
            // pseudo-selection; selectCanvas() re-raises the flag afterwards.
            if isCanvasSelected { isCanvasSelected = false }
            // ...and drops the Library tile, for the same reason: one thing is
            // selected in this window at a time, wherever it was picked.
            // selectLibraryItem() re-raises it afterwards.
            if selectedLibraryItemID != nil { selectedLibraryItemID = nil }
            // A half-typed style name belongs to the row that opened it, and
            // that row is gone (Next, `next-styles`).
            if colorStyleNaming != nil { colorStyleNaming = nil }
        }
    }
    /// The "Canvas" pseudo-layer selection: no layer is selected, the canvas
    /// boundary shows resize handles, and the inspector offers W/H. Mutually
    /// exclusive with any layer selection.
    private(set) var isCanvasSelected = false
    /// The marquee's rubber-band multi-selection (two or more layers). REAL
    /// state, not derived from the selection rect — so panel operations like
    /// hiding a member (which would make it fail a rect containment check)
    /// don't silently drop it from the selection.
    var multiSelectedLayerIDs: Set<UUID> = [] {
        didSet {
            for id in multiSelectedLayerIDs where !oldValue.contains(id) { revealInLayersList(id) }
            if !multiSelectedLayerIDs.isEmpty, selectedLibraryItemID != nil { selectedLibraryItemID = nil }
            // A half-typed style name belongs to the layers that were picked
            // when the field opened, and those are not the layers any more
            // (Next, `next-styles`).
            if multiSelectedLayerIDs != oldValue { colorStyleNaming = nil }
        }
    }
    /// The Library tile that is picked, by `LibraryEntry.id` (Next,
    /// `next-library`). It shares the layer selection's rule rather than
    /// running beside it: picking a tile clears the layer and canvas
    /// selection, and picking anything on the canvas or in the layers list
    /// clears the tile. So the inspector always describes exactly one thing.
    var selectedLibraryItemID: String?
    /// Row-click bookkeeping for the Layers and Measurements lists: the anchor
    /// a shift-click ranges from and the rows the last shift-click swept in.
    /// The selection itself lives in `selectedLayerID` /
    /// `multiSelectedLayerIDs`; this only remembers how the list got there,
    /// and is re-seeded from those stores before every click.
    var rowSelection = ListSelection()
    /// Frame overrides while a move drag is in flight — rendered as a preview,
    /// committed to history only on mouse-up. In CANVAS coordinates, which is
    /// the space the canvas drags in; for a layer sitting loose on the canvas
    /// that is the frame it stores, which is why nothing about a document
    /// without groups changes. Usually one layer; a multi-selection dragged on
    /// the canvas puts every layer it carries in here at once, so the numbers
    /// in the inspector track all of them rather than just one.
    var previewMoves: [UUID: CGRect] = [:]
    /// Cheap drag preview: underlay + sprite the canvas composites in Core
    /// Animation, so mouse moves cost zero Core Image work. Nil until the
    /// session's two renders finish (the full-submit path covers the gap).
    var dragPreview: DragPreview?
    /// Renders preview sessions off the scheduler's queue.
    let previewRenderer = DocumentRenderer()
    var dragPreviewGeneration = 0
    /// Set on commit: the preview must survive until the post-commit frame
    /// lands, or the dragged layer would flash back to its pre-drag position.
    var clearPreviewAfterNextFrame = false
    /// Last known canvas view size, so a document opened before/after the first
    /// layout pass can still be fit correctly.
    private var canvasViewSize: CGSize = .zero

    var zoom: CGFloat { viewport?.zoom ?? 1 }

    var document: PhotonzDocument? { history?.current }
    var canUndo: Bool { history?.canUndo ?? false }
    var canRedo: Bool { history?.canRedo ?? false }

    /// The .photonz package backing this document; nil until first save (or
    /// always, for plain-image documents the user hasn't saved as a package).
    private(set) var documentURL: URL?

    /// The capture file this window was opened to edit, if it lives in the
    /// capture folder (phase 11.5). Lets "Save to Capture History" offer
    /// Override-in-place vs Save-as-new, and gives plain ⌘S its save-back target.
    private(set) var sourceCaptureURL: URL?

    /// The agent's capture center, captured at seed time so ⌘S on a history
    /// capture can save back into its file through the store (cache + reload).
    @ObservationIgnored private weak var captureCenter: CaptureCenter?

    /// The file this window was opened from (screenshot/image/package), for the
    /// window title. Distinct from `documentURL`, which is only set once saved as
    /// a `.photonz` package.
    private(set) var openedFileURL: URL?

    /// "Untitled N" name for a brand-new (unsaved) window, assigned once at seed
    /// so windows are tellable apart in the ⌘` switcher / Window menu / Dock.
    private(set) var untitledName = "Untitled"
    private static var untitledCount = 0
    private static func nextUntitledName() -> String {
        untitledCount += 1
        return "Untitled \(untitledCount)"
    }

    /// The window title: the saved package name, else the opened file's name,
    /// else "Untitled N". Reactive — updates when the document is saved.
    var windowTitle: String {
        let name = (documentURL ?? openedFileURL)?.lastPathComponent ?? untitledName
        // Feature flag (phase 18): Next tags its windows so you can tell which
        // release a window belongs to. Off in Current, so nothing changes there.
        return Experiments.shared.decorated(windowTitle: name)
    }

    /// The .photonz document package type. The bundle's Info.plist exports
    /// the same identifier so Finder treats packages as files.
    static let photonzType = UTType(exportedAs: "com.photonz.document", conformingTo: .package)

    func openImage(at url: URL) {
        if url.pathExtension.lowercased() == "photonz" {
            openPackage(at: url)
            return
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        // A Retina screenshot embeds 144 DPI (2×); honor it so 100% = its on-
        // screen point size, not double (17.14).
        openCapture(image, pixelScale: Self.pixelScale(of: source))
    }

    /// The display scale implied by an image file's DPI metadata (2 for a Retina
    /// screenshot, else 1). See `DisplayScale`.
    private static func pixelScale(of source: CGImageSource) -> CGFloat {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let dpi = props[kCGImagePropertyDPIWidth] as? Double else { return 1 }
        return DisplayScale.pixelScale(forDPI: dpi)
    }

    /// Drag-and-drop / drop of an image URL (from the history overlay, Finder, …):
    /// when a document is already open, the image lands as a **new layer**
    /// (centered, aspect-fit) so it can be cropped/moved/styled; with no
    /// document open, it opens as a fresh document. `.photonz` packages always
    /// open as a document.
    ///
    /// `point` is where the drop landed, in canvas coordinates, when the drop
    /// came down on the canvas itself. A file dropped on a frame joins that
    /// frame; everywhere else the image lands centred on the canvas as it
    /// always has. Either way the new layer is named after the file, so a
    /// stack of placed pictures reads in the Layers list.
    ///
    /// `landing` is the slot in the LAYERS STACK a drop on the right hand
    /// panel pointed at — the one the drop line drew — so the picture arrives
    /// where the panel promised instead of always on top.
    func addImageLayerOrOpen(at url: URL, droppedAt point: CGPoint? = nil,
                             landingAt landing: LayerDrop? = nil) {
        if url.pathExtension.lowercased() == "photonz" || document == nil {
            openImage(at: url)
            return
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        pasteImage(image, at: point, fileName: url.lastPathComponent, landingAt: landing)
    }

    /// Opens a CGImage (from a file or a screen capture) as a fresh document.
    /// `pixelScale` carries the capture's backing scale (2 for a Retina
    /// screenshot) so zoom and measures read in points.
    func openCapture(_ image: CGImage, pixelScale: CGFloat = 1) {
        let ref = store.register(image)
        installDocument(.withBaseImage(ref, pixelScale: pixelScale), url: nil)
    }

    /// Starts a picture from nothing: an opaque white canvas at `size`, which
    /// every tool can draw on immediately. The white is a real full-size
    /// bitmap, not a stretched swatch, so a marquee fill or an eraser stroke on
    /// the background redraws at full resolution.
    ///
    /// Downstream this is indistinguishable from an opened file — locked
    /// Background layer, window sized to the canvas, clean undo baseline — so
    /// save, export and history need to know nothing about it.
    func newBlankCanvas(size: CGSize) {
        let size = BlankCanvas.normalized(size)
        guard let white = SolidImage.make(size: size, hex: Self.blankCanvasBackgroundHex) else { return }
        let ref = store.register(white)
        installDocument(.withBaseImage(ref), url: nil)
    }

    /// How this window opens another one holding a blank canvas. Set once by
    /// the window root, which is where the app coordinator lives; the editor
    /// itself stays free of window plumbing.
    @ObservationIgnored var openBlankCanvasWindow: ((CGSize) -> Void)?

    /// Answers the New Canvas sheet, from whichever route opened it. An empty
    /// window fills itself; a window already holding a picture keeps it and the
    /// canvas arrives in a window of its own.
    func createBlankCanvas(size: CGSize) {
        switch BlankCanvas.destination(windowHasDocument: document != nil) {
        case .thisWindow: newBlankCanvas(size: size)
        case .newWindow: openBlankCanvasWindow?(size)
        }
    }

    /// What a blank canvas starts as. White, not transparent: it is what the
    /// canvas already looks like on screen and what it exports as, so there is
    /// no gap between the two.
    static let blankCanvasBackgroundHex = "#FFFFFF"

    /// Seeds a freshly created editor window from its window identity (phase
    /// 11.1). Called once when the window appears; window reuse (re-opening the
    /// same id) keeps the existing state, giving focus-existing for free, so
    /// this never reloads a window that already holds a document.
    func seed(from windowID: EditorWindowID, capture: CaptureCenter) {
        guard document == nil else { return }
        captureCenter = capture
        switch windowID {
        case .file(let url):
            openImageOrSidecar(at: url)
            openedFileURL = url
            // A plain image keeps its layers in a sidecar, so the window's
            // document has no url of its own; the file it was opened from is
            // what its open groups are filed under, and it is known only now.
            restoreExpandedGroups()
            // A file opened from the capture folder can round-trip back to history.
            if url.deletingLastPathComponent().standardizedFileURL == capture.store.directory.standardizedFileURL {
                sourceCaptureURL = url
            }
        case .clipboard:
            newFromClipboard()
            untitledName = Self.nextUntitledName()
        case .fresh:
            untitledName = Self.nextUntitledName() // empty editor; onboarding card guides next step
            #if PHOTONZ_PLAYTEST
            // An empty window has no canvas view, so nothing else announces it.
            // A walk that starts from a blank canvas needs to find it.
            PlaytestHarness.register(self)
            #endif
        case .blankCanvas(_, let size):
            untitledName = Self.nextUntitledName()
            if let size {
                newBlankCanvas(size: size)
            } else {
                // Nobody has picked a size yet: this window opens empty and
                // asks. Only reached when the question came from a window with
                // no canvas of its own to ask over.
                isBlankCanvasDialogPresented = true
                #if PHOTONZ_PLAYTEST
                PlaytestHarness.register(self)
                #endif
            }
        case .video:
            break // routed to the video editor (VideoEditorState), never here
        }
    }

    /// The document as it was last opened or saved — the clean baseline for
    /// close confirmation. Value equality means undoing back to the last save
    /// counts as clean again.
    @ObservationIgnored private var savedDocument: PhotonzDocument?

    /// The window hosting this editor, captured by `WindowCloseGuard` so the
    /// close confirmation can attach and the edited-dot can track dirtiness.
    @ObservationIgnored weak var hostWindow: NSWindow?

    /// Whether closing this window would lose work.
    var hasUnsavedChanges: Bool {
        ClosePrompt.needsSavePrompt(current: document, savedBaseline: savedDocument)
    }

    /// The document was persisted somewhere the user considers safe (package
    /// save, capture-history save): the current state becomes the clean baseline.
    func markSaved() {
        savedDocument = document
    }

    // MARK: - State the intent extensions work on
    //
    // An extension cannot hold a stored property, so the state behind the
    // intents in the EditorState+*.swift files lives here with the rest of
    // the state. Each one sits next to the doc comment it arrived with.

    var storedMeasureToolMode: MeasureToolMode = {
        let raw = UserDefaults.standard.string(forKey: EditorState.measureModeKey) ?? ""
        return MeasureToolMode(rawValue: raw) ?? .distance
    }() {
        didSet { UserDefaults.standard.set(storedMeasureToolMode.rawValue, forKey: Self.measureModeKey) }
    }

    /// Which rung of the detected element ladder Size mode is showing, moved by
    /// `[` and `]`. Session chrome; clamped against the live candidate list by
    /// the canvas, so a level that outruns a simpler element just pins to its
    /// outermost rung.
    var measureCandidateLevel: Int = 0

    /// Current: once the first caliper lands in this document, the measure hint
    /// chip is gone for good — deleting every measurement doesn't bring it back.
    /// Session-scoped on purpose: hint state is chrome and never persists into
    /// the document.
    var measureHintDismissed = false

    /// Next (`next-measure-modes`): the mode hint that is up right now, if any.
    /// Raised on pickup and on every mode change, and dropped by its own clock
    /// (`MeasureModeHint.lifetime`) or by the measurement it was explaining.
    var measureModeHint: MeasureModeHint?
    var measureModeHintTimer: Task<Void, Never>?

    /// Next (`next-measure-panel`): the "Copied" notice that is up right now,
    /// if any. Raised by Copy as Spec List, Copy Measurement and Copy Image,
    /// and dropped
    /// by its own clock (`CopyConfirmation.lifetime`). It shares the
    /// canvas-bottom slot with the mode hint: whichever was raised last is the
    /// one on screen, so two pills never stack.
    var copyConfirmation: CopyConfirmation?
    var copyConfirmationTimer: Task<Void, Never>?

    /// The tool options' Show filter. Session chrome like a temporary eye-off:
    /// never persisted, never in the model, and exports render the document
    /// itself so every visible layer stays in them regardless.
    var measureShowFilter: MeasureShowFilter = .all

    /// The floating tool bar's measured width, reported by the editor view so
    /// the legend can keep clear of it. Zero until the first measurement, and
    /// the placement then reserves the whole budget. Session chrome only.
    var toolBarWidth: CGFloat = 0

    /// The selected caliper's live label-size preview during a slider drag (no
    /// history); the canvas overlay reads it so the pill resizes live.
    var measureLabelPreview: (id: UUID, scale: CGFloat)?

    /// Photoshop-style foreground/background fill pair, shared across windows
    /// via UserDefaults. Defaults: black over white, like Photoshop's D.
    var foregroundFillHex: String = UserDefaults.standard.string(forKey: EditorState.foregroundFillKey) ?? "#000000" {
        didSet { UserDefaults.standard.set(foregroundFillHex, forKey: Self.foregroundFillKey) }
    }
    var backgroundFillHex: String = UserDefaults.standard.string(forKey: EditorState.backgroundFillKey) ?? "#FFFFFF" {
        didSet { UserDefaults.standard.set(backgroundFillHex, forKey: Self.backgroundFillKey) }
    }

    /// In-flight region content move: the region's pixels lifted from the
    /// target layer. `holed` is the layer bitmap with the region removed
    /// (transparent, or BG color on the locked Background); `content` is the
    /// extracted pixels; `contentFrame` is where they sit in DOC coords.
    var regionMove: (targetID: UUID, content: CGImage, contentFrame: CGRect,
                             holed: CGImage, copy: Bool)?

    /// The groups whose contents are showing in the layers list. Interface
    /// state, not document state: opening a group is not an edit, so it never
    /// touches the file or the undo stack, and it survives selection changes,
    /// undo and redo for as long as the window is open.
    ///
    /// It also survives quitting. Which groups a file had open is filed beside
    /// the document in the app's own settings (`OpenGroupMemory`), the same
    /// place the app already keeps which panels were showing and how wide they
    /// were, so a picture opens looking the way you left it without a byte of
    /// it living in the file.
    var expandedGroupIDs: Set<UUID> = [] {
        didSet {
            guard !isRestoringOpenGroups, expandedGroupIDs != oldValue else { return }
            rememberExpandedGroups()
        }
    }

    /// True only while the open groups are being reset or read back for a
    /// document that is arriving, so setting them up cannot overwrite the
    /// record of the file that is leaving.
    @ObservationIgnored var isRestoringOpenGroups = false

    var panelDropOffer: PanelDropOffer?

    /// Which target last spoke. A pointer crossing from one target to the next
    /// enters the new one BEFORE it leaves the old, so a clear from a target
    /// that no longer owns the offer is the stale half of a crossing and is
    /// ignored — without this the panel's highlight blinks out every time the
    /// pointer crosses a row boundary.
    @ObservationIgnored var panelDropOwner: AnyHashable?

    /// The group the pointer is currently INSIDE, or nil for the canvas.
    ///
    /// A click picks the outermost thing you are not already inside, so this is
    /// the whole of what "inside" means: a double click sets it (going one
    /// level deeper), Escape clears one level of it, and clicking anywhere
    /// outside drops it. Nothing about it is stored in the document — step out
    /// and the tree is exactly what it was.
    var groupContextID: UUID?

    /// A component whose Name field should be waiting for typing, set by the
    /// command that just made it. The Component section consumes it and puts it
    /// back to nil, so it fires once rather than every redraw.
    ///
    /// This is the New Folder idiom: the thing appears already named, with the
    /// name selected, so naming it is typing and ignoring it is fine. It is the
    /// Component section's field rather than the layers row because that field
    /// visibly IS a field, focus ring and all, and a row that silently became
    /// editable is a row nobody knows they can type in.
    var componentAwaitingName: UUID?

    /// A layer whose row in the Layers or Measurements list should open its
    /// rename field, set by the Rename command. Whichever list is showing that
    /// row consumes it and puts it back to nil, so it fires once rather than
    /// every redraw. Same idiom as `componentAwaitingName` above, and the way a
    /// walk reaches a field that only exists while you are renaming.
    var layerAwaitingRename: UUID?

    /// Which color well has its picker open, by the key the well gives itself
    /// ("selection.fill", "shadow", "backdrop"). Nil means none.
    ///
    /// One field rather than a flag inside each well, for two reasons: two
    /// pickers can never be open at once, and a walk can open one from outside
    /// the dock, which the pointer cannot reach.
    var openColorWell: String?

    /// The color row that is asking for a name right now, raised by its Save as
    /// Style button and lowered when the name lands, when Escape drops it, or
    /// when the selection moves on. It lives here rather than inside the row so
    /// only one field is ever open, and so a walk can open one.
    var colorStyleNaming: ColorStyleNamingRequest?

    /// A colour drag in flight: the paint being pushed at the canvas frame by
    /// frame, held out of history until the drag is let go of.
    ///
    /// Deliberately NOT what `selectionPaint` reads. That reading is what the
    /// picker is opened on, and a picker reopened on its own live frames would
    /// hand the ramp's selection back to the first stop halfway through a pull.
    /// The document stays the opening colour for the whole gesture; only the
    /// canvas and the row's chip follow.
    var paintPreview: (slot: ColorSlot, ids: [UUID], paint: Paint)?
    /// The same thing for a colour knob on a copy, keyed by the knob rather
    /// than by a slot: the row paints the copies' answers, not their layers.
    var knobPaintPreview: (instances: [UUID], property: UUID, paint: Paint)?

    /// Exposes one layer inside an original as a knob.
    /// A knob the author just added and has not named yet, so its name field
    /// can take the focus with its text selected. Same New Folder idiom the
    /// component's own Name field follows: a knob lands with a name that says
    /// what it does ("Wording"), and saying what it IS is one word of typing.
    var componentPropertyAwaitingName: UUID?

    /// The piece somebody last tried to type over and could not, when the
    /// original could still be given a knob for it. It puts the offer on the
    /// copy's own section, which is what the notice tells them to look at: the
    /// piece itself is never selected, so there is nowhere else to put it.
    var wordingOffer: ComponentPiece?

    /// The size the next frame gets when it is dropped with a plain click, and
    /// what the New Frame dialog opens on: whatever you made last, so building
    /// a second phone screen costs one click.
    @ObservationIgnored
    @AppStorage("frames.lastSize") var lastFrameSizeRaw = ""

    /// Every copy this window has pasted off the clipboard as it stands now,
    /// in the order they landed. Pasting again steps past the last of them, so
    /// a run of ⌘V walks down the picture instead of stacking every copy in one
    /// spot where only the layers list shows anything happened (`PasteCascade`).
    ///
    /// The clipboard's change count is what makes it "the same paste again":
    /// copying anything else, here or in another app, starts the ladder over.
    var pasteLadder: (clipboard: Int, rungs: [(layer: UUID, frame: CGRect)])?

    // MARK: - Layered sidecar (rich format next to the flattened capture)

    /// The layered `.photonz` sidecar for a flattened media file: same folder,
    /// same basename. Saving a capture flattens it into the PNG; the sidecar is
    /// what lets the layers come back on the next edit.
    static func sidecarURL(for mediaURL: URL) -> URL {
        mediaURL.deletingPathExtension().appendingPathExtension("photonz")
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Opens an image file, preferring its layered sidecar when one exists and
    /// isn't stale (the PNG was rewritten by something else since the sidecar
    /// was saved — then the PNG is the truth and the layers are gone).
    private func openImageOrSidecar(at url: URL) {
        let sidecar = Self.sidecarURL(for: url)
        if url.pathExtension.lowercased() != "photonz",
           let sidecarDate = Self.modificationDate(sidecar),
           let mediaDate = Self.modificationDate(url),
           sidecarDate >= mediaDate.addingTimeInterval(-2),
           let document = try? PackageIO.read(from: sidecar, into: store) {
            // documentURL stays nil: ⌘S keeps meaning "save back to the capture
            // file (and refresh this sidecar)", not "save the package in place".
            installDocument(document, url: nil)
            return
        }
        openImage(at: url)
    }

    /// Auto-saves the layered document next to a flattened capture file, so
    /// reopening that capture recalls the layers instead of baked pixels.
    private func writeCaptureSidecar(nextTo mediaURL: URL) {
        guard let document else { return }
        try? PackageIO.write(document, store: store, to: Self.sidecarURL(for: mediaURL))
    }

    #if PHOTONZ_PLAYTEST
    /// Probe only: keeps the layers beside the picture this window was opened
    /// from, the same write a saved capture makes. A walk needs it because the
    /// ordinary Save As puts up a dialog, and a background process cannot
    /// answer one.
    func playtestSaveLayers() {
        guard let openedFileURL else { return }
        writeCaptureSidecar(nextTo: openedFileURL)
        markSaved()
    }
    #endif

    /// A "Save to Capture History" landed at `url` (override or save-as-new):
    /// adopt it as this window's source, refresh the layered sidecar, and mark
    /// the window clean.
    func savedToCaptureHistory(at url: URL) {
        sourceCaptureURL = url
        writeCaptureSidecar(nextTo: url)
        markSaved()
    }

    /// Installs a freshly opened document, resetting every per-document bit
    /// of editor state.
    private func installDocument(_ document: PhotonzDocument, url: URL?) {
        history = History(document: document)
        savedDocument = document
        documentURL = url
        // The outgoing picture's open groups mean nothing to the incoming one,
        // and clearing them must not be mistaken for the user shutting them.
        withoutRememberingOpenGroups { expandedGroupIDs = [] }
        viewport = .fit(documentSize: document.canvasSize, in: canvasViewSize)
        selection = nil
        selectedLayerID = nil
        activeTool = .select
        previewMoves = [:]
        dragPreview = nil
        editingTextLayerID = nil
        editingCaptionLayerID = nil
        stylePreview = nil
        paintPreview = nil
        knobPaintPreview = nil
        thumbnailCache = [:]
        shelfThumbnails = [:]
        dragPreviewGeneration += 1
        rerender()
        // Size the window to the image (100% when it fits, reduced only when a
        // maxed window can't). The `.fit` above is the fallback for when there
        // is no host window yet — the real sizing runs once one is available.
        needsOpenSizing = true
        sizeWindowToImageIfReady()
        restoreExpandedGroups()
    }

    // MARK: - Fit window to image on open

    /// True from `installDocument` until the window has been sized to the image.
    @ObservationIgnored private var needsOpenSizing = false
    /// The display scale the open-sizing settled on, waiting to be applied to
    /// the viewport once the resulting canvas view size is known.
    @ObservationIgnored private var pendingOpenScale: CGFloat?

    /// Called when the canvas view lands in (or leaves) a window. Adopts the
    /// window and, for a just-opened document, hides it until it's been sized so
    /// it appears fully formed instead of snapping from SwiftUI's default size.
    func canvasDidMoveToWindow(_ window: NSWindow?) {
        #if PHOTONZ_PLAYTEST
        PlaytestHarness.register(self)
        #endif
        if let window {
            hostWindow = window
            // A fresh mount during an open: hide until sized (a re-open into an
            // already-visible window never reaches here — the canvas doesn't
            // remount — so it animates its resize instead).
            if needsOpenSizing {
                window.alphaValue = 0
                scheduleOpenRevealSafetyNet(for: window)
            }
        }
        sizeWindowToImageIfReady()
    }

    /// Grow/shrink the host window to the just-opened image and record the zoom
    /// to apply once the canvas is laid out. No-op until a window + screen exist.
    private func sizeWindowToImageIfReady() {
        guard needsOpenSizing, let document,
              let window = hostWindow,
              let screen = window.screen ?? NSScreen.main else { return }
        needsOpenSizing = false

        let pixelScale = max(1, document.pixelScale)
        let imagePointSize = CGSize(width: document.canvasSize.width / pixelScale,
                                    height: document.canvasSize.height / pixelScale)
        let paneWidth = inspectorPreferredVisible
            ? Self.persistedInspectorWidth + Self.inspectorHandleWidth : 0

        // Usable window CONTENT area = the screen's visible frame minus this
        // window's chrome (title bar etc.). With a hidden title bar that's ~0,
        // but compute it so the math is correct on any window style.
        let frame = window.frame
        let content = window.contentRect(forFrameRect: frame)
        let chrome = CGSize(width: frame.width - content.width,
                            height: frame.height - content.height)
        let visible = screen.visibleFrame
        let maxContent = CGSize(width: max(1, visible.width - chrome.width),
                                height: max(1, visible.height - chrome.height))

        // Floor: the window won't go below its own enforced content minimum —
        // which is the SwiftUI `.frame(minWidth:minHeight:)` plus the hidden
        // title bar's band — so target that, not a smaller ideal the OS ignores.
        let minContent = CGSize(
            width: max(EditorChromeLayout.minWindowWidth, window.contentMinSize.width),
            height: max(EditorChromeLayout.minWindowHeight, window.contentMinSize.height))

        let plan = EditorWindowFit.plan(
            imagePointSize: imagePointSize,
            sidePaneWidth: paneWidth,
            maxContentSize: maxContent,
            minContentSize: minContent)
        pendingOpenScale = plan.imageScale

        // Content → frame, top-left anchored (windows grow down/right), clamped
        // back inside the visible frame.
        let frameSize = CGSize(width: plan.contentSize.width + chrome.width,
                               height: plan.contentSize.height + chrome.height)
        var origin = CGPoint(x: frame.minX, y: frame.maxY - frameSize.height)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - frameSize.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - frameSize.height)
        let target = CGRect(origin: origin, size: frameSize)

        // Snap while hidden (fresh window); animate a resize of a visible window
        // (opening another image into an existing one).
        let animate = window.isVisible && window.alphaValue >= 1
        window.setFrame(target, display: true, animate: animate)
    }

    /// Backstop: if the window is still hidden a beat after an open (canvas never
    /// reported a size, empty clipboard, …), reveal it anyway so it can't get
    /// stuck invisible.
    private func scheduleOpenRevealSafetyNet(for window: NSWindow) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak window] in
            guard let window, window.alphaValue < 1 else { return }
            window.alphaValue = 1
        }
    }

    /// Reveal the host window once the open-sizing zoom has been applied.
    private func revealHostWindowIfHidden() {
        guard let window = hostWindow, window.alphaValue < 1 else { return }
        window.alphaValue = 1
    }

    // MARK: - Save / open packages

    /// ⌘S: saves the package in place; a document opened FROM a history capture
    /// (and never saved as a package) writes the flattened composite back into
    /// that capture file — history items are real files, and Save means "save
    /// back to where it came from". Everything else runs Save As.
    func saveDocument() {
        if let documentURL {
            save(to: documentURL)
        } else if let sourceCaptureURL, let store = captureCenter?.store,
                  store.entries.contains(where: { $0.url == sourceCaptureURL }),
                  let image = compositeImage() {
            store.replace(at: sourceCaptureURL, with: image, scale: documentPixelScale)
            writeCaptureSidecar(nextTo: sourceCaptureURL)
            markSaved()
        } else {
            saveDocumentAs()
        }
    }

    /// ⇧⌘S.
    func saveDocumentAs() {
        guard document != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.photonzType]
        panel.nameFieldStringValue = documentURL?.lastPathComponent
            ?? openedFileURL.map { $0.deletingPathExtension().lastPathComponent + ".photonz" }
            ?? "\(untitledName).photonz"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save(to: url)
    }

    private func save(to url: URL) {
        guard let document else { return }
        do {
            try PackageIO.write(document, store: store, to: url)
            documentURL = url
            markSaved()
            // Saved under a new name: the open groups belong to the new file
            // too, so it opens looking the way this window looks now.
            rememberExpandedGroups()
        } catch {
            presentError("Couldn't save the document.", error)
        }
    }

    func openPackage(at url: URL) {
        do {
            let document = try PackageIO.read(from: url, into: store)
            installDocument(document, url: url)
        } catch {
            presentError("Couldn't open the document.", error)
        }
    }

    // MARK: - Export

    /// The flattened composite at 1× — used by the capture-history round-trip
    /// (phase 11.5) to write an edited capture back to the store.
    func compositeImage() -> CGImage? {
        guard let document else { return nil }
        return previewRenderer.render(document, store: store)
    }

    /// Renders the composite at `scale` and writes it where the user picks.
    ///
    /// `frameID` narrows the picture to one frame (Next, `next-frames`): the
    /// frame's own box becomes the canvas, so what comes out is that screen and
    /// nothing else — not the canvas behind it, not the layer overlapping it
    /// from outside — and the file is named after the frame.
    func exportComposite(format: ImageCodec.Format, scale: CGFloat, quality: Double = 0.9,
                         frameID: UUID? = nil) {
        guard let document else { return }
        let frame = frameID.flatMap { document.layer(id: $0)?.isFrame == true ? $0 : nil }
        let target = frame.flatMap { document.frameDocument(id: $0) } ?? document
        guard let image = previewRenderer.render(target, store: store, scale: scale),
              let data = ImageCodec.encode(image, format: format, quality: quality) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        let base = frame.flatMap { document.layer(id: $0)?.name }
            ?? documentURL?.deletingPathExtension().lastPathComponent
            ?? "Photonz Export"
        panel.nameFieldStringValue = "\(base)\(scale == 2 ? "@2x" : "").\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            presentError("Couldn't export the image.", error)
        }
    }

    /// ⇧⌘C: the flattened composite goes on the pasteboard as PNG + TIFF
    /// (PNG for modern consumers, TIFF for the long tail of AppKit apps).
    /// Next (`next-measure-panel`): when the document has a visible
    /// measurement, the spec list rides beside the picture as plain text
    /// (`CompositeCopy`), declared after the image types so image-aware apps
    /// take the picture and text-only fields take the list. One copy, one
    /// hand-off; the "Copied" notice says which of the two landed.
    func copyCompositeToClipboard() {
        guard let document,
              let image = previewRenderer.render(document, store: store) else { return }
        let carriesSpecList = Experiments.shared.measurePanelEnabled
        let specList = carriesSpecList
            ? CompositeCopy.specListText(document: document, name: specListName) : nil
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for representation in CompositeCopy.representations(specList: specList) {
            switch representation {
            case .png:
                if let png = ImageCodec.encode(image, format: .png) {
                    pasteboard.setData(png, forType: .png)
                }
            case .tiff:
                let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                if let tiff = nsImage.tiffRepresentation {
                    pasteboard.setData(tiff, forType: .tiff)
                }
            case .text(let text):
                pasteboard.setString(text, forType: .string)
            }
        }
        guard carriesSpecList else { return }
        let listed = specList == nil ? 0 : CompositeCopy.visibleMeasurementCount(in: document)
        showCopyConfirmation(.image(measurements: listed))
    }

    private func presentError(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = String(describing: error)
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Viewport

    func canvasViewSizeChanged(_ size: CGSize) {
        let hadNoSize = canvasViewSize == .zero
        canvasViewSize = size
        guard let current = viewport else { return }
        // The window was just sized to the image on open: adopt the planned
        // zoom (100%, or reduced) centered in the now-known canvas, then reveal
        // the (until-now hidden) window fully formed.
        if let scale = pendingOpenScale, let document, size.width > 0, size.height > 0 {
            pendingOpenScale = nil
            let zoom = scale / max(1, document.pixelScale)
            viewport = Viewport(documentSize: document.canvasSize, viewSize: size,
                                zoom: zoom, origin: .zero).clamped()
            revealHostWindowIfHidden()
            return
        }
        // The first real layout after opening re-fits; later resizes keep the
        // user's framing (center-preserving).
        viewport = hadNoSize
            ? .fit(documentSize: current.documentSize, in: size)
            : current.resized(viewSize: size)
    }

    /// Gesture-driven camera updates from the canvas (already clamped by Viewport).
    func setViewport(_ vp: Viewport) {
        viewport = vp
    }

    /// Selection result from the canvas (document coords). `captureLayers`
    /// is the arrow-tool marquee behavior: it doubles as rubber-band layer
    /// selection — layers fully inside become the REAL selection (one layer
    /// promotes to the primary selection, several become the multi-selection
    /// so the panel highlights them and group ops can target them). The
    /// region tools (rect/ellipse/wand) pass false: their selection is a
    /// pixel region, independent of layers.
    func setSelection(_ region: SelectionRegion?, captureLayers: Bool = true) {
        selection = region
        selectionTargetsPixels = region != nil && !captureLayers
        guard captureLayers else { return }
        let captured = region.flatMap { document?.layerIDs(fullyInside: $0.bounds) } ?? []
        if captured.count == 1 {
            selectedLayerID = captured[0] // didSet clears any multi-selection
        } else {
            if !captured.isEmpty { selectedLayerID = nil }
            multiSelectedLayerIDs = Set(captured)
            // A marquee has no anchor row: the next shift-click in a list
            // starts over from the row it lands on.
            rowSelection = ListSelection(selected: multiSelectedLayerIDs)
        }
    }

    /// Magic wand: flood-fill the composite from `point` (document coords)
    /// and combine the blob with the existing region per `mode`. The render +
    /// flood sweep run off-main (a Retina screenshot is a 12MP walk); the
    /// combine hops back to main and is dropped if the canvas changed size
    /// underneath (its coordinates would lie).
    func wandSelect(at point: CGPoint, mode: SelectionRegion.Mode) {
        guard let document else { return }
        let store = store
        let tolerance = wandTolerance
        let base = selection
        Task.detached(priority: .userInitiated) { [weak self] in
            let renderer = DocumentRenderer()
            let canvas = CGRect(origin: .zero, size: document.canvasSize)
            guard let composite = renderer.rasterize(region: canvas, of: document, store: store),
                  let path = FloodFill.path(in: composite, from: point, tolerance: tolerance),
                  let blob = SelectionRegion(path: path) else { return }
            await MainActor.run {
                guard let self, self.document?.canvasSize == document.canvasSize else { return }
                self.setSelection(SelectionRegion.combine(base, with: blob, mode: mode),
                                  captureLayers: false)
            }
        }
    }

    /// ⌘-click a layer row: load its opaque pixels as a selection (Photoshop's
    /// "load layer transparency"). The shape's silhouette becomes a pixel-region
    /// selection so fill/copy/delete/promote target it; the layer stays selected.
    /// No-op (leaving any existing selection) when the layer draws nothing opaque.
    func selectLayerPixels(id: UUID) {
        guard let document, document.layer(id: id) != nil else { return }
        selectedLayerID = id
        guard let path = previewRenderer.layerSelectionPath(for: id, in: document, store: store),
              let region = SelectionRegion(path: path) else { return }
        setSelection(region, captureLayers: false)
    }

    /// Whether a layer is part of the current selection — the primary single
    /// selection or the marquee multi-selection.
    func isLayerSelected(_ id: UUID) -> Bool {
        selectedLayerID == id || multiSelectedLayerIDs.contains(id)
    }

    // MARK: - Tools

    func setTool(_ tool: Tool) {
        guard activeTool != tool else {
            // The Arrow button clicked while the fresh arrow's caption field is
            // open: "done with this caption, next arrow". The field closes and
            // the Arrow tool stays, where a different tool button would close
            // it and switch.
            if ArrowCaptionEntry.repickClosesField(picked: tool, current: activeTool,
                                                   fieldOpen: editingCaptionLayerID != nil) {
                captionCloseRequest += 1
            }
            return
        }
        if tool == .crop {
            // A selected image layer makes this a per-layer crop; otherwise
            // the marquee selection seeds the rect (a common flow: marquee
            // the region, then C to crop to it).
            if let id = selectedLayerID, let layer = document?.layer(id: id),
               layer.supportsContentCrop {
                cropTargetLayerID = id
                cropRect = Crop.fitted(layer.frame, to: cropAspect)
            } else {
                cropTargetLayerID = nil
                cropRect = defaultCropRect()
            }
        } else {
            cropTargetLayerID = nil
            cropRect = nil
        }
        activeTool = tool
        remember(tool)
        if tool == .measure { showMeasureModeHint() }
        // Drawing tools own the pointer; select-mode chrome (marquee ants,
        // layer handles) would read as interactive when it isn't. The
        // selection REGION survives within the selection family + fill
        // (Photoshop keeps the ants up; filling the region needs it).
        if !tool.preservesSelectionRegion {
            selection = nil
        } else if tool.isRegionSelectionTool, selection != nil {
            // Picking up a region tool makes any live selection a PIXEL
            // region: an arrow-made marquee carried into M must move pixels
            // on drag, erase on ⌫, etc. — the tool in hand declares intent.
            selectionTargetsPixels = true
        }
        // The LAYER selection also survives into the selection family + fill:
        // it's the target of region ops (fill/⌫/move bake into the selected
        // layer). Its handles are select-mode chrome and hide meanwhile —
        // the canvas gates them on the active tool.
        if !tool.preservesSelectionRegion {
            selectedLayerID = nil
        }
    }

    // MARK: - Tool groups

    /// The member each tool family showed last (`ToolGroup`), so a group's
    /// button wears the tool you last used and its key picks that one up.
    /// Persisted per family; the selection family keeps the key it has had
    /// since the marquee slot was born, so nobody's remembered selector moves.
    private var lastGroupTools: [ToolGroup: Tool] = [:]

    static func groupMemoryKey(_ group: ToolGroup) -> String {
        group == .selection ? "tool.marquee.last" : "tool.\(group.rawValue).last"
    }

    /// Every family's remembered tool, for a walk that asks to start from the
    /// tools a fresh machine would have.
    static var toolMemoryKeys: [String] { ToolGroup.allCases.map(groupMemoryKey) }

    /// The tool `group`'s button stands for right now.
    func lastTool(in group: ToolGroup) -> Tool {
        if let tool = lastGroupTools[group] { return tool }
        return group.member(from: UserDefaults.standard.string(forKey: Self.groupMemoryKey(group)))
    }

    /// Records `tool` as its family's last member. Called from every route
    /// that picks a tool up (button, key, overflow menu, script), so the
    /// memory can never lag the tool in hand.
    private func remember(_ tool: Tool) {
        guard let group = ToolGroup.containing(tool) else { return }
        lastGroupTools[group] = tool
        UserDefaults.standard.set(tool.rawValue, forKey: Self.groupMemoryKey(group))
    }

    // MARK: - Drag preview

    /// Drops a live drag preview whose sprite no longer matches the layer
    /// (content edits, undo/redo). The canvas falls back to the last composite
    /// until the re-render lands, so nothing flashes.
    func discardDragPreview() {
        dragPreviewGeneration += 1
        dragPreview = nil
        clearPreviewAfterNextFrame = false
    }

    // MARK: - Layers panel

    /// Style override while an inspector slider drag is in flight — rendered
    /// as a preview, committed to history only on release (one undo step per
    /// gesture, same pattern as move/resize drags).
    ///
    /// A drag can be aimed at several layers at once: one pull on Corner Radius
    /// rounds every picked button, and one undo puts them all back.
    var stylePreview: (ids: [UUID], styles: [UUID: LayerStyle])?
    /// Thumbnail cache keyed by layer id; `hash` invalidates on any layer edit.
    var thumbnailCache: [UUID: (hash: Int, image: CGImage)] = [:]
    var thumbnailsInFlight: Set<Int> = []
    /// The starter set's subtrees and their shelf pictures. The five never
    /// change, so both are built once, on the first look at the Components
    /// shelf, and nothing about them is per document.
    var starterPreviewLayers: [StarterComponent: Layer] = [:]
    var starterThumbnails: [ShelfPictureKey: CGImage] = [:]
    /// Shelf pictures for the document's own components. Kept apart from the
    /// layers panel's thumbnails because a shelf tile asks for a much sharper
    /// picture than a 24 point row does, and the same component is often in
    /// both lists at once.
    var shelfThumbnails: [ShelfPictureKey: (hash: Int, image: CGImage)] = [:]
    var shelfThumbnailsInFlight: Set<ShelfPictureKey> = []

    // MARK: - Layer selection & move

    /// The selected layer's frame (preview-aware), for the canvas outline.
    /// Canvas coordinates: a group's outline goes around the box it actually
    /// occupies, and a piece picked inside a group draws where it looks.
    var selectedLayerFrame: CGRect? {
        guard let id = selectedLayerID else { return nil }
        return canvasFrame(of: id)
    }

    /// A layer with its frame in CANVAS coordinates, which is the space the
    /// canvas draws handles, knobs and outlines in. Identical to the layer
    /// itself for anything sitting loose on the canvas.
    func canvasLayer(id: UUID) -> Layer? {
        guard var layer = document?.canvasLayer(id: id) else { return nil }
        if let frame = previewMoves[id] { layer.frame = frame }
        return layer
    }

    /// A layer's canvas-space frame, preview-aware — the box a person can
    /// SEE, which is the words for a text layer rather than the stored box
    /// with its slack on the far edges. Everything the canvas draws chrome
    /// against comes through here, so an outline hugs the letters and a handle
    /// sits on the corner it looks like it sits on. What the canvas hands back
    /// gains the slack again at `storedCanvasFrame`.
    func canvasFrame(of id: UUID) -> CGRect? {
        guard let layer = document?.layer(id: id) else { return nil }
        if let frame = previewMoves[id] { return layer.withoutSlack(frame) }
        return document?.canvasLayer(id: id).map { layer.withoutSlack($0.frame) }
    }

    /// The other direction: a canvas-space box as the canvas SHOWS it, turned
    /// back into the box to store, in the space the layer is stored in. The
    /// one door every canvas commit goes through, so the words never lose the
    /// room they are drawn in.
    func storedCanvasFrame(_ frame: CGRect, of id: UUID) -> CGRect? {
        guard let document, let layer = document.layer(id: id) else { return nil }
        return document.parentSpaceFrame(layer.withSlack(frame), of: id)
    }

    /// A layer's frame in the space it is STORED in — its parent's, which is
    /// the canvas for a layer sitting loose on it. This is what the Position &
    /// Size fields show: typing Y = 0 on a piece inside a group puts it at the
    /// top of its group, which is what the number on that layer says and what
    /// every other design tool does (`docs/design/ui-building.md`).
    ///
    /// Preview-aware: while a move or resize drag is in flight the document
    /// still holds the pre-drag frame, so anything that reads a number off a
    /// layer has to read the preview or it would sit still until mouse-up.
    func previewedFrame(of id: UUID) -> CGRect? {
        if let frame = previewMoves[id], let document {
            return document.parentSpaceFrame(frame, of: id)
        }
        // A group's stored frame is an anchor, not a box: the number to show
        // is the box it occupies, in the same parent space.
        guard let layer = document?.layer(id: id) else { return nil }
        return layer.isGroup ? layer.localBounds : layer.frame
    }

    /// The layers the Position & Size fields speak for: the whole
    /// multi-selection when there is one, else the one selected layer. Frames
    /// are in the space each layer's numbers are shown in — its parent's —
    /// and preview-aware, so a drag in flight is what the fields read.
    ///
    /// A layer inside a selected group takes no place of its own: the group
    /// already carries it, and setting both would move it twice. Locked layers
    /// stay in the list but accept nothing, so the section can say honestly
    /// how many of the picked layers a number reaches.
    var geometrySelection: LayerGeometrySelection {
        guard let document else { return LayerGeometrySelection([]) }
        let selected = actionableLayerIDs
        guard !selected.isEmpty else { return LayerGeometrySelection([]) }
        // Draw order, so the fields read the same way twice running.
        let members = document.allLayers.compactMap { layer -> LayerGeometrySelection.Member? in
            guard selected.contains(layer.id), let frame = previewedFrame(of: layer.id) else {
                return nil
            }
            var parent = document.parentID(of: layer.id)
            while let up = parent {
                if selected.contains(up) { return nil }
                parent = document.parentID(of: up)
            }
            // The group it sits in comes along, because a group that arranges
            // itself owns where its contents sit and the fields must say so
            // rather than taking a number and putting it back.
            let holder = document.parentID(of: layer.id).flatMap { document.layer(id: $0) }
            // The fields speak the box a person can see. A label's W is how
            // wide its words are, and typing one back puts the room the
            // renderer draws them in underneath it again.
            return LayerGeometrySelection.Member(id: layer.id,
                                                 frame: layer.withoutSlack(frame),
                                                 editing: LayerGeometryEditing(layer: layer,
                                                                               in: holder),
                                                 slack: layer.boxSlack)
        }
        return LayerGeometrySelection(members)
    }

    /// A typed geometry field landing (Return, Tab, or a click away): every
    /// selected layer that accepts the field goes to the typed number, in ONE
    /// undo step. A locked layer, a field a layer does not accept, and a value
    /// that changes nothing are all no-ops, so tabbing through the fields
    /// without editing never puts anything in the undo stack.
    func setLayerGeometry(field: LayerGeometryField, to value: CGFloat) {
        commitGeometry(geometrySelection.applying(value, to: field))
    }

    /// An arrow-key press in a field: every selected layer steps from its own
    /// number, in ONE undo step, so a row that is spread out moves together
    /// and stays spread out.
    func stepLayerGeometry(field: LayerGeometryField, direction: Int, coarse: Bool) {
        commitGeometry(geometrySelection.stepping(field, direction: direction, coarse: coarse))
    }

    /// One undo step for a whole selection's worth of typed frames.
    private func commitGeometry(_ moves: [UUID: CGRect]) {
        guard !moves.isEmpty, let document else { return }
        previewMoves = [:]
        dragPreviewGeneration += 1 // cancels an in-flight preview session
        clearPreviewAfterNextFrame = dragPreview != nil
        // Resolved here, in draw order, so the one undo step lands the same way
        // every time. A group's box is the box its contents make, and
        // `resized(to:)` re-fits it: typing X moves it, typing W scales what is
        // inside it.
        let ordered: [(id: UUID, frame: CGRect)] = document.allLayers
            .compactMap { layer in
                guard let frame = moves[layer.id] else { return nil }
                return (layer.id, frame)
            }
        perform { document in
            let canvas = document.canvasSize
            for move in ordered {
                document.updateLayer(id: move.id) {
                    $0 = AnnotationBuilder.planningCaption($0.resized(to: move.frame),
                                                           canvas: canvas)
                }
            }
        }
    }

    func selectLayer(_ id: UUID?) {
        // Selecting from anywhere but the canvas walk (a panel row, a fresh
        // layer, a deselect) puts you back at the top level: the only thing
        // that puts you inside a group is deliberately going into it.
        let context = id.flatMap { document?.parentID(of: $0) }
        if groupContextID != context { groupContextID = context }
        selectedLayerID = id
        // Explicit deselection dissolves the multi-selection even when the
        // primary was already nil (didSet only fires on change).
        if id == nil, !multiSelectedLayerIDs.isEmpty { multiSelectedLayerIDs = [] }
    }

    /// A click on a Layers or Measurements row, with the modifier keys read
    /// the Finder's way: plain selects the row, shift ranges from the anchor,
    /// command toggles. `order` is that list's rows top to bottom (the Layers
    /// list and the Measurements list are different orders of the same
    /// stack). One row becomes the primary selection, two or more the same
    /// multi-selection a canvas marquee produces, so delete, hide, lock and
    /// Copy Measurements need no new paths.
    func clickRow(_ id: UUID, _ click: RowClick, in order: [UUID]) {
        var next = rowSelection
        next.selected = multiSelectedLayerIDs
        if let selectedLayerID { next.selected.insert(selectedLayerID) }
        next.click(id, click, in: order)
        // A row click puts you wherever the row lives, so picking a top-level
        // layer from the list steps you out of any group you were inside.
        let context = document?.parentID(of: id)
        if groupContextID != context { groupContextID = context }
        switch next.selected.count {
        case 0:
            selectLayer(nil)
        case 1:
            selectedLayerID = next.selected.first
        default:
            selectedLayerID = nil // didSet clears the multi-selection first
            multiSelectedLayerIDs = next.selected
        }
        // After the stores: setting the primary re-seeds the anchor, and a
        // toggle that leaves one row selected still anchors on the toggled row.
        rowSelection = next
    }

    /// Selects the Canvas pseudo-layer (panel row click): boundary handles
    /// appear on canvas and the Canvas inspector section opens.
    /// Picks a tile in the Library, or clears the pick with nil. Routed
    /// through the layer selection so the canvas, the layers list and the
    /// inspector all agree on what is selected.
    func selectLibraryItem(_ id: String?) {
        selectLayer(nil)             // ...which clears any tile in its didSet
        selectedLibraryItemID = id   // ...so this is the only thing selected
    }

    /// Puts the picked Library media into the open picture as a new layer, the
    /// same way a file dragged in from the Finder lands. One method, so the
    /// tile's double click, the item section's button and a playtest all run
    /// the same code. Media ids ARE the file's path (`LibraryEntry.id`), which
    /// is what lets this live here rather than in the panel.
    func placeLibraryPick() {
        guard let id = selectedLibraryItemID else { return }
        addImageLayerOrOpen(at: URL(fileURLWithPath: id))
    }

    /// Lets go of the Library tile without touching the layer selection: what
    /// a click on the canvas that landed on nothing means.
    func clearLibraryPick() {
        if selectedLibraryItemID != nil { selectedLibraryItemID = nil }
    }

    func selectCanvas() {
        guard document != nil else { return }
        selectedLayerID = nil     // didSet clears the flag…
        isCanvasSelected = true   // …then it's raised for the pseudo-selection
    }

    /// A drag is starting on `id`: kick off the underlay + sprite renders.
    /// Until they land, per-move previews fall back to full submits.
    func beginLayerDrag(id: UUID) {
        guard dragPreview?.layerID != id else { return }
        dragPreview = nil
        clearPreviewAfterNextFrame = false
        dragPreviewGeneration += 1
        let generation = dragPreviewGeneration
        guard let doc = document, let layer = doc.layer(id: id) else { return }
        // Zoom callouts can't be sprited: their content samples the backdrop,
        // and the leader lines must track the frame live. Text can't either: it
        // re-wraps on resize, so a stretched start-bitmap would distort glyphs.
        // Both fall back to full re-renders per move, which keeps them right.
        guard layer.zoomCallout == nil else { return }
        if case .text = layer.content { return }
        // A group's own style is usually plain, but the shadows and blur of the
        // pieces INSIDE it still reach past the box they make, so the sprite is
        // padded by the furthest any of them reaches or they would be clipped
        // the moment the drag started.
        var padding = layer.style.previewPadding
        if layer.isGroup {
            let box = layer.localBounds
            let reach = layer.renderBounds
            padding = max(padding, box.minX - reach.minX, box.minY - reach.minY,
                          reach.maxX - box.maxX, reach.maxY - box.maxY).rounded(.up)
        }
        let blend = layer.effectiveBlendMode
        let renderer = previewRenderer
        let store = store
        let displayDoc = displayFiltered(doc)
        Task.detached(priority: .userInitiated) {
            let underlay = renderer.render(displayDoc, store: store, hiding: id)
            let sprite = renderer.renderSprite(for: id, in: doc, store: store, padding: padding)
            await MainActor.run { [weak self] in
                guard let self, self.dragPreviewGeneration == generation,
                      let underlay, let sprite else { return }
                self.dragPreview = DragPreview(layerID: id, underlay: underlay, sprite: sprite,
                                               padding: padding, blendMode: blend)
            }
        }
    }

    // MARK: - Zoom

    func zoomIn() { zoomTowardCenter(zoom * 1.25) }
    func zoomOut() { zoomTowardCenter(zoom / 1.25) }

    func zoomToFit() {
        guard let viewport else { return }
        self.viewport = .fit(documentSize: viewport.documentSize, in: viewport.viewSize)
    }

    /// Actual size = the image at its on-screen POINT size (Preview-style): a
    /// Retina (pixelScale 2) screenshot shows at half its pixel dimensions so it
    /// matches how it looked on screen (17.14).
    func zoomToActualSize() { zoomTowardCenter(1 / documentPixelScale) }

    /// Absolute zoom (the toolbar slider / stop menu); Viewport clamps.
    func setZoom(_ newZoom: CGFloat) { zoomTowardCenter(newZoom) }

    /// Zoom expressed in POINTS (logical), not image pixels — what the toolbar
    /// shows. For a Retina capture (pixelScale 2), displayZoom 100% = actual
    /// zoom 0.5, so "100%" matches the on-screen size the user expects.
    var displayZoom: CGFloat { zoom * documentPixelScale }
    func setDisplayZoom(_ display: CGFloat) { setZoom(display / documentPixelScale) }

    private func zoomTowardCenter(_ newZoom: CGFloat) {
        guard let viewport else { return }
        let center = CGPoint(x: viewport.viewSize.width / 2, y: viewport.viewSize.height / 2)
        self.viewport = viewport.zoomed(to: newZoom, anchorInView: center)
    }

    // MARK: - One undoable edit, and undo/redo

    /// One undoable edit. `announcing` is off for edits whose whole effect is
    /// in front of the person making them — setting a knob on the copy they
    /// have selected — because the pill exists to report what moved OUT OF
    /// SIGHT, and one that fires on every keystroke in a field is noise.
    /// `reportingLinkBreaks` is off for the few commands whose whole point IS
    /// the break — Unlink takes a color off its style on purpose — because a
    /// notice there is the app repeating your own command back at you.
    func perform(announcing: Bool = true, reportingLinkBreaks: Bool = true,
                 _ mutate: (inout PhotonzDocument) -> Void) {
        // Anything recorded supersedes a colour drag's live frames, including
        // the release that ends one.
        paintPreview = nil
        let report = history?.perform(mutate) ?? EditReport()
        rerender()
        if announcing { announceComponentSync(report.componentSync) }
        // Last, so a break wins the one canvas slot: an edit that reached ten
        // copies is expected, and one that quietly severed something is not.
        if reportingLinkBreaks { announceLinkBreaks(report.linkBreaks) }
    }

    /// Says how many copies followed the edit that just landed
    /// (`docs/design/ui-building.md`, step C5). Editing an original changes
    /// things that are elsewhere on the canvas, often scrolled off it, so
    /// without this you change one thing and have no idea what else moved.
    /// Placing a copy and moving one both report nothing, because neither is
    /// an edit that reached anywhere.
    private func announceComponentSync(_ report: ComponentSyncReport) {
        guard Experiments.shared.componentsEnabled, !report.isEmpty else { return }
        let named = report.componentIDs.count == 1
            ? report.componentIDs.first.flatMap { document?.mainComponent(componentID: $0)?.name }
            : nil
        raiseCanvasNotice(.componentInstances(count: report.updatedInstances, component: named))
    }

    /// Says that something stopped following what it came from, the same way
    /// for all four kinds of break (`LinkBreakReport`).
    ///
    /// Every break is silent by nature: painting over a color that wore a style
    /// looks exactly like painting a color, and deleting an original leaves the
    /// copies drawing what they always drew. You find out later, when an edit
    /// to the original stops arriving. This is the moment it is still cheap to
    /// press Command Z.
    ///
    /// Each kind is dropped when the feature it belongs to is switched off, so
    /// the pill never names a thing this build does not have.
    private func announceLinkBreaks(_ report: LinkBreakReport) {
        guard !report.isEmpty else { return }
        let styles = Experiments.shared.colorStylesEnabled
        let components = Experiments.shared.componentsEnabled
        let kept = report.breaks.filter { $0.kind == .colorStyle ? styles : components }
        guard !kept.isEmpty else { return }
        raiseCanvasNotice(.linksBroken(LinkBreakReport(breaks: kept)))
    }

    func undo() {
        discardDragPreview() // undone edits may invalidate a held sprite
        stylePreview = nil
        paintPreview = nil
        dropStaleBreakNotice()
        history?.undo()
        rerender()
    }

    func redo() {
        discardDragPreview()
        stylePreview = nil
        paintPreview = nil
        dropStaleBreakNotice()
        history?.redo()
        rerender()
    }

    /// A "stopped following" notice is about the edit that just happened, so
    /// stepping over that edit takes it off screen. Leaving it up would have
    /// the canvas saying a link is broken a second after undo put it back.
    private func dropStaleBreakNotice() {
        guard case .linksBroken = copyConfirmation?.subject else { return }
        copyConfirmationTimer?.cancel()
        copyConfirmation = nil
    }

    // MARK: - Rendering

    func rerender() {
        guard let document = history?.current else {
            renderedImage = nil
            viewport = nil
            selection = nil
            cropRect = nil
            selectedLayerID = nil
            groupContextID = nil
            previewMoves = [:]
            dragPreview = nil
            editingTextLayerID = nil
            editingCaptionLayerID = nil
            stylePreview = nil
            paintPreview = nil
            thumbnailCache = [:]
            shelfThumbnails = [:]
            return
        }
        // Thumbnails for layers that no longer exist are dead weight.
        if thumbnailCache.count != document.layers.count {
            let ids = Set(document.layers.map(\.id))
            thumbnailCache = thumbnailCache.filter { ids.contains($0.key) }
            let living = Set(document.layers.flatMap { $0.selfAndDescendants.map(\.id) })
            shelfThumbnails = shelfThumbnails.filter { living.contains($0.key.id) }
        }
        // Crop/resize/undo can change the canvas size; keep the camera in sync.
        if var vp = viewport, vp.documentSize != document.canvasSize {
            vp.documentSize = document.canvasSize
            viewport = vp.clamped()
            // A selection from the old canvas no longer means anything reliable.
            selection = nil
            // Same for a pending crop rect (undo/redo mid-crop): restart from
            // the full new canvas.
            if activeTool == .crop {
                cropRect = Crop.fitted(CGRect(origin: .zero, size: document.canvasSize), to: cropAspect)
            }
        }
        // Undo can remove the selected layer out from under us.
        if let id = selectedLayerID, document.layer(id: id) == nil {
            selectedLayerID = nil
        }
        // Undoing a ⌘G takes the group you were standing inside away with it.
        if let id = groupContextID, document.layer(id: id) == nil {
            groupContextID = nil
        }
        // Where you are follows what you are holding. Dragging a layer off a
        // screen takes it out of that screen, and if the context stayed behind,
        // Escape would jump back to the screen the layer just left.
        if Experiments.shared.layerGroupsEnabled, let id = selectedLayerID,
           groupContextID != document.parentID(of: id) {
            groupContextID = document.parentID(of: id)
        }
        // Same for the multi-selection (undoing a batch duplicate takes the
        // copies it selected away), so the Layers menu never stays enabled
        // over layers that no longer exist. One survivor becomes the primary.
        if !multiSelectedLayerIDs.isEmpty {
            let alive = multiSelectedLayerIDs.filter { document.layer(id: $0) != nil }
            if alive.count != multiSelectedLayerIDs.count {
                if alive.count == 1 { selectedLayerID = alive.first }
                else { multiSelectedLayerIDs = alive }
            }
        }
        // Same for a per-layer crop target: fall back to a document crop.
        if let id = cropTargetLayerID, document.layer(id: id) == nil {
            cropTargetLayerID = nil
            if activeTool == .crop {
                cropRect = Crop.fitted(CGRect(origin: .zero, size: document.canvasSize), to: cropAspect)
            }
        }
        // Same for the layer behind an inline text edit (the canvas cancels
        // its editor when the layer disappears).
        if let id = editingTextLayerID, document.layer(id: id) == nil {
            editingTextLayerID = nil
        }
        if let id = editingCaptionLayerID, document.layer(id: id) == nil {
            editingCaptionLayerID = nil
        }
        submit(document)
    }

    /// What the CANVAS shows, which is not quite the document: the measure Show
    /// filter, the layer standing behind an open inline editor, and the pill
    /// behind an open caption field are all editing state rather than content.
    /// Export paths rasterize the document itself and never come through here.
    private func displayDocument(_ document: PhotonzDocument) -> PhotonzDocument {
        var document = displayFiltered(document)
        // The inline editor overlay stands in for the layer being edited.
        if let id = editingTextLayerID {
            document.updateLayer(id: id) { $0.isVisible = false }
        }
        // A caption edit suppresses just the pill; the arrow stays visible.
        if let id = editingCaptionLayerID {
            document.updateLayer(id: id) { layer in
                if var a = layer.annotation {
                    a.caption = nil
                    layer.content = .annotation(a)
                }
            }
        }
        return document
    }

    /// Redraws the part of the document you can see at the resolution it is
    /// being shown at, so placed words stay as sharp as the ones being typed.
    ///
    /// Only worth doing when the canvas is showing the picture bigger than it
    /// is: at or below 1:1 the stretched composite already has a pixel for
    /// every pixel and a second copy of it would buy nothing. Skipped mid-drag
    /// too, where the canvas is floating a sprite over a held-back composite
    /// and a sharp copy of the settled document would contradict it.
    private func refreshCrispTile() {
        crispTileTask?.cancel()
        crispTileTask = nil
        // Anything on screen was drawn for a different moment than this one.
        crispTile = nil
        crispTileViewport = nil

        guard Experiments.shared.crispZoomEnabled,
              dragPreview == nil,
              let viewport,
              let document = history?.current else { return }
        let scale = viewport.zoom * (hostWindow?.backingScaleFactor ?? 2)
        guard scale > 1.01, let region = visibleDocumentRect(viewport) else { return }

        let display = displayDocument(document)
        let renderer = tileRenderer
        let store = self.store
        // Past 2x somebody is inspecting pixels and wants to see them squarely,
        // which is the rule the canvas already follows for the whole composite.
        let nearest = viewport.zoom >= 2
        crispTileTask = Task { [weak self] in
            // Let the edit or the gesture settle first. The composite lands
            // immediately either way; this only decides how soon the sharp copy
            // follows it, and drawing one per keystroke would spend a whole
            // window's worth of pixels on a frame nobody looks at.
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            let tile = await Task.detached(priority: .userInitiated) {
                renderer.renderTile(display, store: store, region: region,
                                    scale: scale, magnifyNearest: nearest)
            }.value
            guard !Task.isCancelled, let self else { return }
            // The camera or the document may have moved on while this drew.
            guard self.viewport == viewport, self.history?.current == document else { return }
            self.crispTile = tile
            self.crispTileViewport = viewport
        }
    }

    /// The part of the document inside the window, in document points.
    private func visibleDocumentRect(_ viewport: Viewport) -> CGRect? {
        guard viewport.zoom > 0 else { return nil }
        let visible = CGRect(x: -viewport.origin.x / viewport.zoom,
                             y: -viewport.origin.y / viewport.zoom,
                             width: viewport.viewSize.width / viewport.zoom,
                             height: viewport.viewSize.height / viewport.zoom)
        let canvas = CGRect(origin: .zero, size: viewport.documentSize)
        let inside = visible.intersection(canvas)
        guard !inside.isNull, inside.width >= 1, inside.height >= 1 else { return nil }
        return inside
    }

    /// Hands a document (committed or move-preview) to the render scheduler.
    func submit(_ document: PhotonzDocument) {
        let document = displayDocument(document)
        defer { refreshCrispTile() }
        if scheduler == nil {
            scheduler = RenderScheduler(store: store) { [weak self] image in
                await MainActor.run {
                    // Drop the frame if the document was closed while rendering.
                    guard let self, self.history != nil else { return }
                    self.renderedImage = image
                    if self.clearPreviewAfterNextFrame {
                        self.clearPreviewAfterNextFrame = false
                        self.dragPreview = nil
                    }
                }
            }
        }
        guard let scheduler else { return }
        Task { await scheduler.submit(document) }
    }
}
