import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class EditorState {
    private(set) var history: History?
    let store = ImageStore()
    /// Per-image detected UI edges, computed lazily on first use and reused for
    /// every measure-corner snap. Keyed by `ImageRef`, so it survives undo/redo.
    @ObservationIgnored private let edgeMapCache = EdgeMapCache()
    /// Edge maps that finished analysis, ready for synchronous access during a
    /// drag. Observable so the canvas picks the map up when analysis lands.
    private var readyEdgeMaps: [UUID: EdgeMapAnalyzer.Analysis] = [:]
    /// Refs whose analysis is in flight (don't kick it twice).
    @ObservationIgnored private var edgeMapAnalysisPending: Set<UUID> = []
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
    private(set) var pendingLibraryTileID: String?

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
    private(set) var selection: SelectionRegion?
    /// True when the region was made by a region tool (rect/ellipse/wand) —
    /// pixel semantics: ⌫ erases pixels, ⌘C copies the clipped composite,
    /// bucket fills the region. False for the arrow tool's marquee, which
    /// keeps its layer semantics (rubber-band capture, batch delete).
    private(set) var selectionTargetsPixels = false
    /// Magic-wand color tolerance (Euclidean RGBA distance, 0–255 units).
    /// Persisted like the fill colors — a tuned tolerance outlives relaunch.
    var wandTolerance: Double = UserDefaults.standard.object(forKey: "wand.tolerance")
        .flatMap { $0 as? Double } ?? 32 {
        didSet { UserDefaults.standard.set(wandTolerance, forKey: "wand.tolerance") }
    }
    /// The active editor tool. Drawing tools are STICKY (Photoshop-style, 17.12):
    /// after a shape is drawn the tool stays active so you can draw more of them.
    /// Switch to `.select` (V) to adjust a placed shape.
    private(set) var activeTool: Tool = .select
    /// The pending crop rect (document coords) while the crop tool is active.
    private(set) var cropRect: CGRect?
    /// Crop aspect lock; the crop rect always honors it.
    private(set) var cropAspect: CropAspect = .free
    /// When set, crop mode targets this layer (non-destructive content crop)
    /// instead of the whole document.
    private(set) var cropTargetLayerID: UUID?
    /// Styling for new annotations, set from the style popover. Persisted so
    /// the user's color/width survive relaunches.
    private(set) var annotationStyles: AnnotationStyles = EditorState.loadAnnotationStyles()
    /// Styling for new text blocks, set from the font picker. Persisted like
    /// annotation styles.
    private(set) var textStyles: TextStyles = EditorState.loadTextStyles()
    /// The measure tool's persisted memory: colors, thickness, label size, unit.
    /// Every measure setter writes it back to UserDefaults, so the next caliper —
    /// this session or after a relaunch — starts where the last one left off.
    // strokeWidth is in LOGICAL pixels (rendered ×pixelScale) so a 1px sizer line
    // aligns with the image's pixel grid.
    private(set) var measureStyles: MeasureStyles = EditorState.loadMeasureStyles()
    /// Template content for a new caliper. The axis, feet, and head offset are
    /// set per placement, so mode/start/end/headOffset here are placeholders.
    var measureStyle: MeasureContent { measureStyles.content }
    /// Recently committed colors, SHARED across annotations/text/borders (13.2).
    /// Recorded on commit only (never on live preview) and persisted.
    private(set) var recentColors: RecentColors = EditorState.loadRecentColors()
    /// The text layer being re-edited inline. Hidden from renders while the
    /// canvas's editor overlay visually replaces it.
    private(set) var editingTextLayerID: UUID?
    /// The arrow whose caption is being edited inline. Its pill (not the
    /// arrow) is suppressed from renders while the editor overlay stands in.
    private(set) var editingCaptionLayerID: UUID?
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
    private(set) var selectedLayerID: UUID? {
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
    private(set) var multiSelectedLayerIDs: Set<UUID> = [] {
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
    private(set) var selectedLibraryItemID: String?
    /// Row-click bookkeeping for the Layers and Measurements lists: the anchor
    /// a shift-click ranges from and the rows the last shift-click swept in.
    /// The selection itself lives in `selectedLayerID` /
    /// `multiSelectedLayerIDs`; this only remembers how the list got there,
    /// and is re-seeded from those stores before every click.
    private var rowSelection = ListSelection()
    /// Frame overrides while a move drag is in flight — rendered as a preview,
    /// committed to history only on mouse-up. In CANVAS coordinates, which is
    /// the space the canvas drags in; for a layer sitting loose on the canvas
    /// that is the frame it stores, which is why nothing about a document
    /// without groups changes. Usually one layer; a multi-selection dragged on
    /// the canvas puts every layer it carries in here at once, so the numbers
    /// in the inspector track all of them rather than just one.
    private var previewMoves: [UUID: CGRect] = [:]
    /// Cheap drag preview: underlay + sprite the canvas composites in Core
    /// Animation, so mouse moves cost zero Core Image work. Nil until the
    /// session's two renders finish (the full-submit path covers the gap).
    private(set) var dragPreview: DragPreview?
    /// Renders preview sessions off the scheduler's queue.
    private let previewRenderer = DocumentRenderer()
    private var dragPreviewGeneration = 0
    /// Set on commit: the preview must survive until the post-commit frame
    /// lands, or the dragged layer would flash back to its pre-drag position.
    private var clearPreviewAfterNextFrame = false
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
    func addImageLayerOrOpen(at url: URL, droppedAt point: CGPoint? = nil) {
        if url.pathExtension.lowercased() == "photonz" || document == nil {
            openImage(at: url)
            return
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        pasteImage(image, at: point, fileName: url.lastPathComponent)
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

    private static func groupMemoryKey(_ group: ToolGroup) -> String {
        group == .selection ? "tool.marquee.last" : "tool.\(group.rawValue).last"
    }

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

    // MARK: - Crop mode

    private func defaultCropRect() -> CGRect? {
        guard let document else { return nil }
        let base = selection.map { Geometry.pixelAligned($0.bounds) }
            ?? CGRect(origin: .zero, size: document.canvasSize)
        return Crop.fitted(base, to: cropAspect)
    }

    /// What the crop rect is confined to: the target layer's frame for a
    /// per-layer crop, else the whole canvas.
    var cropBounds: CGRect? {
        guard activeTool == .crop, let document else { return nil }
        if let id = cropTargetLayerID, let layer = document.layer(id: id) {
            return layer.frame
        }
        return CGRect(origin: .zero, size: document.canvasSize)
    }

    /// Crop rect updates from the canvas (drags already aspect-locked and
    /// canvas-clamped by `Crop`).
    func setCropRect(_ rect: CGRect) {
        cropRect = rect
    }

    /// An aspect pick re-fits the pending rect so it holds immediately.
    func setCropAspect(_ aspect: CropAspect) {
        cropAspect = aspect
        if let rect = cropRect { cropRect = Crop.fitted(rect, to: aspect) }
    }

    /// ⏎ or the toolbar checkmark: one undo step, then back to select. A
    /// layer target gets a non-destructive content crop and stays selected;
    /// otherwise the whole document crops.
    func commitCrop() {
        guard let rect = cropRect else { return }
        let aligned = Geometry.pixelAligned(rect)
        let target = cropTargetLayerID
        if let target {
            perform { $0.updateLayer(id: target) { $0.cropContent(to: aligned) } }
        } else {
            perform { $0.crop(to: aligned) }
        }
        setTool(.select)
        selectedLayerID = target
    }

    /// ⎋ or the toolbar ✕: discard the pending rect.
    func cancelCrop() {
        setTool(.select)
    }

    /// Resize-dialog apply: scales the canvas and every layer frame in one
    /// undo step.
    func resizeDocument(to size: CGSize) {
        perform { $0.resize(to: size) }
    }

    /// Canvas-size apply: grows/shrinks the canvas around the anchor without
    /// scaling content, one undo step.
    func setCanvasSize(to size: CGSize, anchor: CanvasAnchor) {
        // Growing the canvas paints the newly exposed area with the current
        // BACKGROUND fill color (Photoshop behavior): the locked Background
        // layer's bitmap is rebuilt at canvas size — bg color under the old
        // pixels at their (anchor-shifted) position — in the same undo step.
        // Skipped when there's no plain locked background image to extend
        // (cropped/transformed backgrounds keep their exact look instead).
        var extendedBackground: (id: UUID, ref: ImageRef)?
        if let doc = document,
           size.width > doc.canvasSize.width || size.height > doc.canvasSize.height,
           let background = doc.layers.first, background.isLocked,
           let oldRef = background.imageRef, background.crop == nil,
           background.transform.isIdentity,
           let oldImage = store.image(for: oldRef) {
            let dx = (size.width - doc.canvasSize.width) * anchor.unit.x
            let dy = (size.height - doc.canvasSize.height) * anchor.unit.y
            let shifted = background.frame.offsetBy(dx: dx, dy: dy)
            if let merged = Self.backgroundExtended(oldImage, drawnAt: shifted, canvas: size,
                                                    fillHex: backgroundFillHex) {
                extendedBackground = (background.id, store.register(merged))
            }
        }
        perform { doc in
            doc.setCanvasSize(size, anchor: anchor)
            if let extendedBackground {
                doc.updateLayer(id: extendedBackground.id) { layer in
                    layer.content = .image(extendedBackground.ref)
                    layer.frame = CGRect(origin: .zero, size: size)
                }
            }
        }
    }

    /// A canvas-sized bitmap: `fillHex` everywhere, with `image` composited at
    /// `frame` (document coordinates, top-left origin).
    private static func backgroundExtended(_ image: CGImage, drawnAt frame: CGRect,
                                           canvas: CGSize, fillHex: String) -> CGImage? {
        let width = Int(canvas.width.rounded()), height = Int(canvas.height.rounded())
        guard width >= 1, height >= 1, let rgba = RGBA(hex: fillHex),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        // Flip the top-left document rect into CG's bottom-left space.
        context.draw(image, in: CGRect(x: frame.minX,
                                       y: CGFloat(height) - frame.maxY,
                                       width: frame.width, height: frame.height))
        return context.makeImage()
    }

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
        perform { [layer] in $0.addLayerDrawnOnFrame(layer) }
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
                restyled = AnnotationBuilder.planningCaption(
                    AnnotationBuilder.restyled(current, caption: .some(newCaption)),
                    canvas: document.canvasSize)
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
                    $0 = AnnotationBuilder.planningCaption(
                        AnnotationBuilder.restyled($0, captionFontSize: size), canvas: canvas)
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
        doc.updateLayer(id: id) { $0 = AnnotationBuilder.placingCaption($0, at: center, canvas: canvas) }
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
            document.updateLayer(id: id) { $0 = AnnotationBuilder.placingCaption($0, at: center, canvas: canvas) }
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
                    $0 = AnnotationBuilder.releasingCaption($0, canvas: canvas)
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
    private func finishCreating(_ layerID: UUID, tool: Tool = .select) {
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
    func addZoomCallout(from start: CGPoint, to end: CGPoint) {
        guard let document,
              let layer = ZoomCalloutBuilder.layer(from: start, to: end,
                                                   canvas: document.canvasSize) else { return }
        perform { $0.addLayerDrawnOnFrame(layer) }
        finishCreating(layer.id)
    }

    /// Every readout already on the canvas, in document space. A new
    /// measurement's readout steers around these so two numbers never stack
    /// (UX-PATTERNS D14 rule 4).
    private func placedReadoutRects(excluding id: UUID? = nil) -> [CGRect] {
        guard let document else { return [] }
        return document.layers.compactMap { layer in
            layer.id == id ? nil : MeasureBuilder.readoutRect(of: layer)
        }
    }

    /// Picks where a about-to-land measurement's readout sits, so it never
    /// covers the thing it is measuring (UX-PATTERNS D14). `start`/`end` and any
    /// alignment items on `content` must be in document space.
    private func planReadout(_ content: inout MeasureContent, from start: CGPoint, to end: CGPoint,
                             avoiding extra: [CGRect] = [], describing subjects: [CGRect] = []) {
        var probe = content
        probe.start = start
        probe.end = end
        let plan = MeasureLabelPlanner.plan(for: probe, canvas: document?.canvasSize,
                                            avoiding: placedReadoutRects() + extra,
                                            describing: subjects)
        content.apply(plan)
    }

    /// The elements a caliper's feet landed on, read off the capture once, at
    /// placement time, so the readout can stay off them the way a Size readout
    /// stays off the element it measured (UX-PATTERNS D14). Two probes per
    /// foot on a click or a handle release; nothing runs per mouse move.
    private func caliperSubjects(from start: CGPoint, to end: CGPoint,
                                 mode: MeasureMode) -> [CGRect] {
        let scale = document?.pixelScale ?? 1
        return ElementBounds.subjects(from: start, to: end, mode: mode,
                                      in: snappingEdgeMap, luma: measureLumaField,
                                      minElement: max(10, 10 * scale),
                                      textGap: AlignmentScan.visibleGap * max(1, scale))
    }

    /// Completed 3-click caliper placement: add the dimension layer with the
    /// active style, then auto-revert to Select and select the new caliper so its
    /// handles are immediately grabbable — matches other apps (the old sticky
    /// measure tool felt inconsistent).
    ///
    /// `headOffset` nil means the caliper landed on the release of the drag and
    /// there was never a third click to set the standoff: the head then reaches
    /// exactly as far as a Gap's does, far enough that the readout sits clear of
    /// the line it belongs to.
    func addMeasure(from start: CGPoint, to end: CGPoint, mode: MeasureMode,
                    headOffset: CGFloat?) {
        var content = measureStyle
        content.mode = mode
        content.headOffset = headOffset
            ?? MeasureBuilder.clearingHeadOffset(content: content, from: start, to: end,
                                                 canvas: document?.canvasSize)
        // A hand-drawn caliper knows what its feet landed on, so its number
        // stays off those elements and not just off its own thin line.
        planReadout(&content, from: start, to: end,
                    describing: caliperSubjects(from: start, to: end, mode: mode))
        var layer = MeasureBuilder.layer(content: content, from: start, to: end)
        // Inherit the last caliper's non-destructive effects (a drop shadow added
        // in Effects carries to the next measure), like annotations do per shape.
        layer.style = measureStyles.layerStyle
        perform { $0.addLayer(layer) }
        recordRecentColor(hex: content.strokeColorHex)
        noteMeasurementLanded()
        finishCreating(layer.id)
    }

    /// Size mode's click: the element under the pointer becomes a width caliper
    /// and a height caliper in ONE undo step, both the same caliper every other
    /// mode produces. Two layers rather than a combined badge on purpose — a
    /// mode that invented its own callout would be the only one with a look of
    /// its own, and each caliper stays individually movable and deletable.
    /// The heads point outward, away from the element, so neither sits on it —
    /// and both readouts are told what the element IS, so the one case the head
    /// cannot solve (an element flush with the edge of the picture, where the
    /// head has to double back over it) still lands its number somewhere clear.
    /// `neighbors` are the elements touching this one, read off the capture by
    /// the canvas: a number parked in the next row down reads as that row's
    /// number, so the readouts steer around them when there is room to.
    func addElementSize(_ rect: CGRect, neighbors: [CGRect] = []) {
        guard rect.width > 0, rect.height > 0, let canvas = document?.canvasSize else { return }
        let widthFeet = (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY))
        let heightFeet = (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
        // A width is a Size callout whatever you measured last: starting from
        // the popover's last-used role left both calipers tagged Spacing (and
        // listed as "Gap") right after a Gap click. With roles on they take
        // Size's own ink, like Gap mode takes Spacing's; with roles off the
        // one shared ink stays, only the role is pinned so the names derive.
        var template = Experiments.shared.measureRolesEnabled
            ? measureStyles.content(for: .size) : measureStyle
        template.role = .size
        var width = template
        width.mode = .horizontal
        width.headOffset = MeasureBuilder.clearingHeadOffset(content: width, from: widthFeet.0,
                                                             to: widthFeet.1, canvas: canvas)
        var height = template
        height.mode = .vertical
        height.headOffset = MeasureBuilder.clearingHeadOffset(content: height, from: heightFeet.0,
                                                              to: heightFeet.1, canvas: canvas)
        planReadout(&width, from: widthFeet.0, to: widthFeet.1,
                    avoiding: neighbors, describing: [rect])
        var widthLayer = MeasureBuilder.layer(content: width, from: widthFeet.0, to: widthFeet.1)
        // The height readout also dodges the width readout that just landed —
        // they meet at the element's corner, so they are the likeliest pair in
        // the whole app to stack.
        planReadout(&height, from: heightFeet.0, to: heightFeet.1,
                    avoiding: neighbors + [MeasureBuilder.readoutRect(of: widthLayer)]
                        .compactMap { $0 },
                    describing: [rect])
        var heightLayer = MeasureBuilder.layer(content: height, from: heightFeet.0, to: heightFeet.1)
        widthLayer.style = measureStyles.layerStyle
        heightLayer.style = measureStyles.layerStyle
        perform {
            $0.addLayer(widthLayer)
            $0.addLayer(heightLayer)
        }
        recordRecentColor(hex: width.strokeColorHex)
        noteMeasurementLanded()
        finishCreating(widthLayer.id)
    }

    /// The style the canvas should preview the active Measure mode in. Gap mode
    /// previews in the Spacing ink it will actually commit, and Size mode in
    /// Size's, so what you see under the pointer is what lands.
    var measureStyleForActiveMode: MeasureContent {
        guard Experiments.shared.measureRolesEnabled else { return measureStyle }
        switch measureToolMode {
        case .gap: return measureStyles.content(for: .spacing)
        case .size: return measureStyles.content(for: .size)
        case .distance, .alignment: return measureStyle
        }
    }

    /// Gap mode's click: one caliper across the whitespace, tagged Spacing when
    /// roles are on, because a gap between two elements is by definition a
    /// spacing callout and making the user set that by hand is busywork.
    func addGapMeasure(_ gap: GapMeasurement) {
        guard gap.length > 0, let canvas = document?.canvasSize else { return }
        var content = measureStyleForActiveMode
        content.mode = gap.axis
        // The head reaches far enough that the readout sits clear of the gap
        // itself — a pill parked on a 12 px space hides the very thing measured.
        content.headOffset = MeasureBuilder.clearingHeadOffset(content: content, from: gap.start,
                                                               to: gap.end, canvas: canvas)
        // The two elements bounding the gap are what the number must stay off.
        planReadout(&content, from: gap.start, to: gap.end,
                    describing: caliperSubjects(from: gap.start, to: gap.end, mode: gap.axis))
        var layer = MeasureBuilder.layer(content: content, from: gap.start, to: gap.end)
        layer.style = measureStyles.layerStyle
        perform { $0.addLayer(layer) }
        recordRecentColor(hex: content.strokeColorHex)
        noteMeasurementLanded()
        finishCreating(layer.id)
    }

    /// What the Measure tool does when you click (Next): the two-point caliper,
    /// the size of the element under the pointer, the gap under the pointer, or
    /// an alignment guide. Always visible in the tool options, session chrome,
    /// never persisted. Distance is the default and the only mode that draws
    /// nothing on the canvas until you act.
    /// The mode STICKS, across tool switches and across launches. A tool that
    /// forgets which mode you put it in makes you re-pick it every session, and
    /// the button's glyph is the only place the bar says what the tool will do,
    /// so a mode that resets is also a glyph that lies about your last choice.
    var measureToolMode: MeasureToolMode {
        get { Experiments.shared.measureModesEnabled ? storedMeasureToolMode : .distance }
        set {
            guard newValue != storedMeasureToolMode else { return }
            storedMeasureToolMode = newValue
            measureCandidateLevel = 0
            // Every way of switching (I, the button's flyout, the inspector)
            // lands here, so this is the one place the chip needs to be raised.
            showMeasureModeHint()
        }
    }
    private static let measureModeKey = "tool.measure.mode"
    private var storedMeasureToolMode: MeasureToolMode = {
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

    /// Whether the Measure tool is in its Alignment mode (Next flag
    /// `next-measure-align`): drags draw a checking guide instead of a caliper.
    var measureChecksAlignment: Bool { measureToolMode == .alignment }

    /// The Measure tool's Snap option (Next flag `next-measure-center-snap`):
    /// true = "Edges and centers" (the mock's default), false = "Edges".
    /// Persisted with the tool's styles, so it stays how you left it.
    var measureSnapsToCenters: Bool {
        get { measureStyles.snapsToCenters }
        set { updateMeasureStyles { $0.snapsToCenters = newValue } }
    }

    /// Completed alignment-guide drag (`next-measure-align`, decision D1): scan
    /// the element edges the guide crosses, settle the guide onto the reference
    /// edge (the median — the drawn drag was the question, the reference is the
    /// answer), and commit the check as one undoable layer in the caliper's ink.
    func addAlignmentCheck(axis: MeasureMode, position: CGFloat, span: ClosedRange<CGFloat>) {
        guard document != nil, Experiments.shared.measureAlignEnabled else { return }
        let pixelScale = document?.pixelScale ?? 1
        // The picture itself, so the scan counts elements rather than edge
        // runs; empty only in the moment before the analysis lands, and then
        // the check says its items are not counted.
        let luma = measureLumaField
        let items = AlignmentScan.items(axis: axis, position: position, span: span,
                                        in: snappingEdgeMap, luma: luma, pixelScale: pixelScale)
        var content = measureStyle
        content.mode = axis
        content.headOffset = 0
        // The Experiments number is in logical px, like every readout; the
        // items are device px, so a Retina capture gets twice the room.
        content.alignment = AlignmentCheck(
            items: items,
            tolerance: AlignmentCheck.deviceTolerance(logical: Experiments.shared.measureAlignTolerance,
                                                      pixelScale: pixelScale),
            itemsAreElements: !luma.isEmpty)
        let reference = content.alignment?.verdict?.reference ?? items.first?.edge ?? position
        let start: CGPoint, end: CGPoint
        switch axis {
        case .vertical:
            start = CGPoint(x: reference, y: span.lowerBound)
            end = CGPoint(x: reference, y: span.upperBound)
        case .horizontal:
            start = CGPoint(x: span.lowerBound, y: reference)
            end = CGPoint(x: span.upperBound, y: reference)
        }
        planReadout(&content, from: start, to: end)
        var layer = MeasureBuilder.layer(content: content, from: start, to: end)
        layer.style = measureStyles.layerStyle
        perform { $0.addLayer(layer) }
        recordRecentColor(hex: content.strokeColorHex)
        noteMeasurementLanded()
        finishCreating(layer.id)
    }

    /// Current: once the first caliper lands in this document, the measure hint
    /// chip is gone for good — deleting every measurement doesn't bring it back.
    /// Session-scoped on purpose: hint state is chrome and never persists into
    /// the document.
    private var measureHintDismissed = false

    /// Next (`next-measure-modes`): the mode hint that is up right now, if any.
    /// Raised on pickup and on every mode change, and dropped by its own clock
    /// (`MeasureModeHint.lifetime`) or by the measurement it was explaining.
    private(set) var measureModeHint: MeasureModeHint?
    private var measureModeHintTimer: Task<Void, Never>?

    /// Next (`next-measure-panel`): the "Copied" notice that is up right now,
    /// if any. Raised by Copy as Spec List, Copy Measurement and Copy Image,
    /// and dropped
    /// by its own clock (`CopyConfirmation.lifetime`). It shares the
    /// canvas-bottom slot with the mode hint: whichever was raised last is the
    /// one on screen, so two pills never stack.
    private(set) var copyConfirmation: CopyConfirmation?
    private var copyConfirmationTimer: Task<Void, Never>?

    /// Raise (or re-raise) the "Copied" notice after text landed on the
    /// clipboard. Never called when a copy did nothing: the copy paths guard
    /// before they get here. Re-raising restarts the clock, so two quick
    /// copies keep one pill up that fades from the last one.
    private func showCopyConfirmation(_ subject: CopyConfirmation.Subject) {
        guard Experiments.shared.measurePanelEnabled else { return }
        raiseCanvasNotice(subject)
    }

    /// Puts a notice in the canvas-bottom slot. The flag each caller lives
    /// under is checked by the caller, so one pill can answer more than one
    /// feature without either knowing about the other's switch.
    private func raiseCanvasNotice(_ subject: CopyConfirmation.Subject) {
        measureModeHintTimer?.cancel()
        measureModeHint = nil
        let now = Date()
        let notice = copyConfirmation?.reshown(as: subject, at: now)
            ?? CopyConfirmation(subject: subject, shownAt: now)
        copyConfirmation = notice
        copyConfirmationTimer?.cancel()
        copyConfirmationTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(notice.lifetime))
            guard !Task.isCancelled, let self, self.copyConfirmation == notice else { return }
            self.copyConfirmation = nil
        }
    }

    /// Raise (or re-raise) the mode hint. Re-raising restarts the clock, so
    /// three quick presses of I keep one chip up that fades from the last
    /// press; the chip's text follows the mode so it never names a stale one.
    private func showMeasureModeHint() {
        guard Experiments.shared.measureModesEnabled else { return }
        // The slot is shared with the "Copied" notice: the latest raise wins.
        copyConfirmationTimer?.cancel()
        copyConfirmation = nil
        let now = Date()
        let hint = measureModeHint?.reshown(as: measureToolMode, at: now)
            ?? MeasureModeHint(mode: measureToolMode, shownAt: now)
        measureModeHint = hint
        measureModeHintTimer?.cancel()
        measureModeHintTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(MeasureModeHint.lifetime))
            guard !Task.isCancelled, let self, self.measureModeHint == hint else { return }
            self.measureModeHint = nil
        }
    }

    /// A measurement just landed: the Current chip retires for the document,
    /// and the Next chip leaves early, since the click it was describing has
    /// happened and its words would only be sitting on the result.
    private func noteMeasurementLanded() {
        measureHintDismissed = true
        measureModeHintTimer?.cancel()
        measureModeHint = nil
    }

    /// Whether the Measure hint chip shows. It tells you what a click does in
    /// the mode you are in, which is the one thing a mode switcher costs you.
    /// Next (`next-measure-modes`): while a mode hint is live, on every pickup
    /// and every mode change. Current: the Measure tool is active and no
    /// measurement has ever landed in this document.
    var showsMeasureHint: Bool {
        guard activeTool == .measure, let document else { return false }
        if Experiments.shared.measureModesEnabled { return measureModeHint != nil }
        guard !measureHintDismissed else { return false }
        return !document.layers.contains { $0.measure != nil }
    }

    /// The chip's lead, set in its own weight: the mode's name. Nil in Current,
    /// where the chip is one plain line and only ever names Distance's click.
    var measureHintTitle: String? { measureModeHint?.title }

    /// That chip's line, for the current mode.
    var measureHintText: String {
        let landsOnRelease = Experiments.shared.measureDistanceLandsOnRelease
        guard let hint = measureModeHint else {
            return measureToolMode.hint(landsOnRelease: landsOnRelease)
        }
        return hint.detail(landsOnRelease: landsOnRelease)
    }

    // MARK: - Measure styling

    /// The selected layer, if it's a measure.
    var selectedMeasureLayer: Layer? {
        guard let id = selectedLayerID, let layer = document?.layer(id: id),
              layer.measure != nil else { return nil }
        return layer
    }

    /// The Measure tool's Show display filter (§5, `next-measure-roles`):
    /// which measurement roles the interactive canvas draws.
    enum MeasureShowFilter: String, CaseIterable {
        case all, size, spacing

        /// Whether the interactive canvas draws this measurement. Alignment
        /// guides are neither Size nor Spacing, so they always show.
        func shows(_ measure: MeasureContent) -> Bool {
            switch self {
            case .all: true
            case .size: measure.alignment != nil || measure.role == .size
            case .spacing: measure.alignment != nil || measure.role == .spacing
            }
        }

        var title: String {
            switch self {
            case .all: "All"
            case .size: "Size"
            case .spacing: "Spacing"
            }
        }
    }

    /// The tool options' Show filter. Session chrome like a temporary eye-off:
    /// never persisted, never in the model, and exports render the document
    /// itself so every visible layer stays in them regardless.
    private(set) var measureShowFilter: MeasureShowFilter = .all

    func setMeasureShowFilter(_ filter: MeasureShowFilter) {
        guard measureShowFilter != filter else { return }
        measureShowFilter = filter
        discardDragPreview()
        if let document { submit(document) }
    }

    /// The document as the INTERACTIVE canvas should draw it: measure layers
    /// the Show filter excludes become invisible, exactly like an eye-off.
    /// Export and pasteboard paths render the document directly, so the filter
    /// can never leak into what leaves the app.
    private func displayFiltered(_ document: PhotonzDocument) -> PhotonzDocument {
        guard measureShowFilter != .all,
              Experiments.shared.measureRolesEnabled else { return document }
        var document = document
        for layer in document.layers {
            if let m = layer.measure, !measureShowFilter.shows(m) {
                document.updateLayer(id: layer.id) { $0.isVisible = false }
            }
        }
        return document
    }

    /// Which slot the legend takes. It is a key TO the measurements, so
    /// parking it on top of one makes the same mistake a callout covering its
    /// subject makes (UX-PATTERNS D14): it walks to the first free corner,
    /// and when every corner is taken it steps down the left edge (then the
    /// right) rather than sit on a measurement.
    var measureLegendAnchor: PanelAnchor {
        guard let viewport, let document else { return .topLeading }
        let rows = measureLegendEntries.count
        guard rows > 0 else { return .topLeading }
        let occupied = document.layers.compactMap { layer -> CGRect? in
            guard layer.measure != nil, layer.isVisible else { return nil }
            let origin = viewport.viewPoint(fromDocument: layer.frame.origin)
            return CGRect(x: origin.x, y: origin.y,
                          width: layer.frame.width * viewport.zoom,
                          height: layer.frame.height * viewport.zoom)
        }
        // Chrome along the bottom is a hard no: a legend parked behind the
        // tool bar is invisible, and one under the mode hint's slot gets
        // covered for two seconds every time the mode changes. The slot is
        // reserved even while no pill is up, so the legend never jumps.
        let chrome = EditorChromeLayout.bottomChrome(canvasSize: viewport.viewSize,
                                                     toolBarWidth: toolBarWidth,
                                                     noticeSize: MeasureModeHint.reservedSize)
        // The inspector toggle already lives in the top-right corner. It is
        // neither content to dodge nor chrome that takes the corner away: the
        // top-right slot tucks in underneath it, one stack gap clear.
        return PanelPlacement.firstClear(size: Self.measureLegendSize(rows: rows),
                                          in: viewport.viewSize,
                                          inset: Self.measureLegendInset,
                                          avoiding: occupied,
                                          blocked: chrome,
                                          clearing: Self.measureLegendCornerChrome(in: viewport.viewSize),
                                          gap: EditorChromeLayout.toolBarStackGap)
    }

    /// How far the legend sits below the canvas's top edge in its slot: the
    /// plain inset, except in the top-right corner, where it hangs one stack
    /// gap under the inspector toggle so the two never touch. The view pads
    /// the legend by this on top and by `measureLegendInset` on every other
    /// side.
    var measureLegendTopInset: CGFloat {
        guard let viewport else { return Self.measureLegendInset }
        let anchor = measureLegendAnchor
        guard anchor == .topLeading || anchor == .topTrailing else { return Self.measureLegendInset }
        return PanelPlacement.frame(for: anchor,
                                    size: Self.measureLegendSize(rows: measureLegendEntries.count),
                                    in: viewport.viewSize,
                                    inset: Self.measureLegendInset,
                                    clearing: Self.measureLegendCornerChrome(in: viewport.viewSize),
                                    gap: EditorChromeLayout.toolBarStackGap).minY
    }

    /// The chrome parked in a canvas corner that a corner slot tucks in
    /// beside: today only the inspector toggle, which is up whenever a
    /// document is open.
    private static func measureLegendCornerChrome(in canvasSize: CGSize) -> [CGRect] {
        [EditorChromeLayout.inspectorToggleFrame(canvasSize: canvasSize)]
    }

    /// The floating tool bar's measured width, reported by the editor view so
    /// the legend can keep clear of it. Zero until the first measurement, and
    /// the placement then reserves the whole budget. Session chrome only.
    var toolBarWidth: CGFloat = 0

    /// A generous reservation for the legend's glass panel. It is chrome laid
    /// out by SwiftUI, so its exact size is not knowable here; over-reserving
    /// only makes it step aside a little sooner than strictly needed.
    static func measureLegendSize(rows: Int) -> CGSize {
        CGSize(width: 140, height: CGFloat(max(rows, 1)) * 21 + 16)
    }
    /// The legend's own padding inside the canvas: the one corner inset every
    /// piece of corner chrome shares, so the legend and the inspector toggle
    /// line up when they stack.
    static let measureLegendInset: CGFloat = EditorChromeLayout.cornerInset

    /// One row of the canvas legend (§5): a measurement kind present in the
    /// document, with the ink to swatch it in.
    struct MeasureLegendEntry: Equatable, Identifiable {
        let label: String
        let colorHex: String
        let isDashed: Bool
        var id: String { label }
    }

    /// The canvas legend (§5, `next-measure-roles`): shown while the Measure
    /// tool is active, listing only the kinds the document actually contains.
    /// Swatches take the top-most measurement of each kind's ink, so the legend
    /// matches the canvas even after per-measure recolors. Pure chrome, drawn
    /// as a SwiftUI overlay — never part of an export.
    var measureLegendEntries: [MeasureLegendEntry] {
        guard activeTool == .measure, Experiments.shared.measureRolesEnabled,
              let document else { return [] }
        let measures = document.layers.compactMap(\.measure)
        var entries: [MeasureLegendEntry] = []
        if let m = measures.last(where: { $0.alignment == nil && $0.role == .size }) {
            entries.append(MeasureLegendEntry(label: "Size", colorHex: m.strokeColorHex,
                                              isDashed: false))
        }
        if let m = measures.last(where: { $0.alignment == nil && $0.role == .spacing }) {
            entries.append(MeasureLegendEntry(label: "Spacing", colorHex: m.strokeColorHex,
                                              isDashed: false))
        }
        if let m = measures.last(where: { $0.alignment != nil }) {
            entries.append(MeasureLegendEntry(label: "Alignment", colorHex: m.strokeColorHex,
                                              isDashed: true))
        }
        return entries
    }

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
    private var specListName: String {
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

    /// The selected caliper's live label-size preview during a slider drag (no
    /// history); the canvas overlay reads it so the pill resizes live.
    private(set) var measureLabelPreview: (id: UUID, scale: CGFloat)?

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
    private func updateMeasureStyles(_ mutate: (inout MeasureStyles) -> Void) {
        mutate(&measureStyles)
        if let data = try? JSONEncoder().encode(measureStyles) {
            UserDefaults.standard.set(data, forKey: Self.measureStylesKey)
        }
    }

    private static let measureStylesKey = "measureStyles"

    private static func loadMeasureStyles() -> MeasureStyles {
        guard let data = UserDefaults.standard.data(forKey: measureStylesKey),
              let styles = try? JSONDecoder().decode(MeasureStyles.self, from: data) else {
            return MeasureStyles()
        }
        return styles
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
    /// them is active (measure, rect/ellipse region select) or a measure is
    /// selected — so the edge sweep never runs for documents that aren't
    /// being redlined. Analysis takes ~seconds on a Retina screenshot, so it
    /// runs OFF the main thread: the first access kicks it off and returns
    /// `.empty` (snapping is a no-op until it lands), then the observable
    /// `readyEdgeMaps` update re-feeds the canvas the real map.
    var snappingEdgeMap: EdgeMap {
        let selectedIsMeasure = selectedLayerID
            .flatMap { document?.layer(id: $0)?.measure } != nil
        let toolSnaps = activeTool == .measure
            || activeTool == .rectSelect || activeTool == .ellipseSelect
        guard toolSnaps || selectedIsMeasure,
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
            annotationStyles.setPaint(paint, for: activeTool)
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
            annotationStyles.setFillPaint(paint, for: activeTool)
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
    }

    // A callout's ring has no setter of its own. It IS the layer's border, so
    // its colour goes through `setSelectionColor(slot: .border)` with every
    // other colour and its width through the Effects Border slider with every
    // other layer's — one control each, and the same one wherever you got to
    // it from.

    /// Drops a live drag preview whose sprite no longer matches the layer
    /// (content edits, undo/redo). The canvas falls back to the last composite
    /// until the re-render lands, so nothing flashes.
    private func discardDragPreview() {
        dragPreviewGeneration += 1
        dragPreview = nil
        clearPreviewAfterNextFrame = false
    }

    // MARK: - Recent colors (13.2)

    private static let recentColorsKey = "recentColors"

    private static func loadRecentColors() -> RecentColors {
        guard let data = UserDefaults.standard.data(forKey: recentColorsKey),
              let recents = try? JSONDecoder().decode(RecentColors.self, from: data) else {
            return RecentColors()
        }
        return recents
    }

    /// The single funnel for the shared recents list. Called from every COMMIT
    /// path (not preview): annotation color, per-layer annotation color, text
    /// color, and LayerStyle border/shadow (which is what a callout's ring
    /// is). Malformed hex is ignored by `RecentColors.record`.
    func recordRecentColor(hex: String) {
        recentColors.record(hex: hex)
        if let data = try? JSONEncoder().encode(recentColors) {
            UserDefaults.standard.set(data, forKey: Self.recentColorsKey)
        }
    }

    // MARK: - Fill colors (paint bucket)

    /// Photoshop-style foreground/background fill pair, shared across windows
    /// via UserDefaults. Defaults: black over white, like Photoshop's D.
    var foregroundFillHex: String = UserDefaults.standard.string(forKey: "fill.foreground") ?? "#000000" {
        didSet { UserDefaults.standard.set(foregroundFillHex, forKey: "fill.foreground") }
    }
    var backgroundFillHex: String = UserDefaults.standard.string(forKey: "fill.background") ?? "#FFFFFF" {
        didSet { UserDefaults.standard.set(backgroundFillHex, forKey: "fill.background") }
    }

    /// X — swap foreground and background, like Photoshop.
    func swapFillColors() {
        (foregroundFillHex, backgroundFillHex) = (backgroundFillHex, foregroundFillHex)
    }

    /// Fills `id` with a color via the bucket semantics (`Fill.filled`): solid
    /// content for photos, interior fill for boxes, recolor for strokes/text/
    /// measures, backdrop for collages. One undo step; no-op when the content
    /// refuses (zoom callouts).
    func fillLayer(id: UUID, hex: String) {
        guard let layer = document?.layer(id: id) else { return }
        var solidRef: ImageRef?
        if layer.imageRef != nil {
            guard let solid = Self.solidImage(hex: hex) else { return }
            solidRef = store.register(solid)
        }
        guard let filled = Fill.filled(layer, colorHex: hex, solidRef: solidRef) else { return }
        discardDragPreview()
        perform { $0.updateLayer(id: id) { $0 = filled } }
        recordRecentColor(hex: hex)
    }

    /// Bucket click on the canvas: fill the hit layer — or, when the click
    /// lands on the locked Background (which hit-testing skips), fill that.
    /// `useBackground` (⌥) fills with the background color instead.
    func fillLayer(at point: CGPoint, hit: UUID?, useBackground: Bool) {
        // While a pixel region exists the bucket fills THE REGION, not the
        // layer — and clicks outside it do nothing (Photoshop).
        if selectionTargetsPixels, let region = selection {
            guard region.contains(point), let target = regionTargetID(preferring: hit) else { return }
            fillRegion(hex: useBackground ? backgroundFillHex : foregroundFillHex, into: target)
            return
        }
        let target = hit ?? document?.layers.first(where: {
            $0.isLocked && $0.imageRef != nil && $0.frame.contains(point)
        })?.id
        guard let target else { return }
        fillLayer(id: target, hex: useBackground ? backgroundFillHex : foregroundFillHex)
    }

    /// ⌥⌫ — fill the selected layer with the foreground (or background)
    /// color; with a pixel region active, fill the region instead.
    func fillSelectedLayer(useBackground: Bool) {
        let hex = useBackground ? backgroundFillHex : foregroundFillHex
        if selectionTargetsPixels, selection != nil {
            if let target = regionTargetID() { fillRegion(hex: hex, into: target) }
            return
        }
        guard let id = selectedLayerID else { return }
        fillLayer(id: id, hex: hex)
    }

    // MARK: - Region-targeted ops (17.5)

    /// The image layer a region op bakes into: the preferred (hit) layer when
    /// it's bakeable, else the selected layer, else the locked Background
    /// under the region. Only untransformed, uncropped image layers qualify —
    /// the axis-aligned doc→bitmap mapping would lie for anything else.
    private func regionTargetID(preferring hit: UUID? = nil) -> UUID? {
        guard let document, let region = selection else { return nil }
        func bakeable(_ layer: Layer?) -> Bool {
            guard let layer else { return false }
            return layer.imageRef != nil && layer.crop == nil && layer.transform.isIdentity
        }
        if let hit, bakeable(document.layer(id: hit)) { return hit }
        if let id = selectedLayerID, bakeable(document.layer(id: id)) { return id }
        return document.layers.first(where: {
            $0.isLocked && bakeable($0) && $0.frame.intersects(region.bounds)
        })?.id
    }

    /// Bakes a region op into an image layer's bitmap as ONE undo step. The
    /// region path maps from document space into bitmap pixels through the
    /// layer's frame (bitmaps stretch to their frame at render time).
    @discardableResult
    private func bakeRegion(into id: UUID, op: (CGImage, CGPath) -> CGImage?) -> Bool {
        guard let region = selection, let document,
              let layer = document.layer(id: id), let ref = layer.imageRef,
              layer.crop == nil, layer.transform.isIdentity,
              layer.frame.width > 0, layer.frame.height > 0,
              let bitmap = store.image(for: ref) else { return false }
        var docToBitmap = CGAffineTransform(scaleX: CGFloat(bitmap.width) / layer.frame.width,
                                            y: CGFloat(bitmap.height) / layer.frame.height)
            .translatedBy(x: -layer.frame.minX, y: -layer.frame.minY)
        let localPath = region.path.copy(using: &docToBitmap) ?? region.path
        guard let baked = op(bitmap, localPath) else { return false }
        let newRef = store.register(baked)
        discardDragPreview()
        perform { $0.updateLayer(id: id) { $0.content = .image(newRef) } }
        return true
    }

    /// Fills the selection region with `hex` into the target image layer's
    /// pixels. The selection stays up afterwards (Photoshop).
    @discardableResult
    func fillRegion(hex: String, into id: UUID) -> Bool {
        let filled = bakeRegion(into: id) { RegionOps.filled($0, path: $1, hex: hex) }
        if filled { recordRecentColor(hex: hex) }
        return filled
    }

    /// ⌫ with a pixel region: SLICE the target image layer — erase the
    /// region, then tighten the layer's frame to the surviving pixels
    /// (Photoshop's bounds are derived from content, so deletes shrink
    /// layers there too). Deleting every pixel removes the layer. The locked
    /// Background instead fills with the background color and keeps its
    /// size (it must stay canvas-sized).
    func deleteRegion() {
        guard selectionTargetsPixels, let region = selection, let id = regionTargetID(),
              let document, let layer = document.layer(id: id) else { return }
        if layer.isLocked {
            fillRegion(hex: backgroundFillHex, into: id)
            return
        }
        guard let ref = layer.imageRef, layer.crop == nil, layer.transform.isIdentity,
              layer.frame.width > 0, layer.frame.height > 0,
              let bitmap = store.image(for: ref) else { return }
        var docToBitmap = CGAffineTransform(scaleX: CGFloat(bitmap.width) / layer.frame.width,
                                            y: CGFloat(bitmap.height) / layer.frame.height)
            .translatedBy(x: -layer.frame.minX, y: -layer.frame.minY)
        let localPath = region.path.copy(using: &docToBitmap) ?? region.path
        guard let erased = RegionOps.erased(bitmap, path: localPath) else { return }
        discardDragPreview()
        guard let trimmed = RegionOps.trimmed(erased) else {
            deleteLayer(id: id) // the delete consumed the whole layer
            return
        }
        let newRef = store.register(trimmed.image)
        let newFrame = trimmed.rect.applying(docToBitmap.inverted())
        perform { $0.updateLayer(id: id) {
            $0.content = .image(newRef)
            $0.frame = newFrame
        } }
    }

    // MARK: Region content move (Photoshop Move-tool semantics)

    /// In-flight region content move: the region's pixels lifted from the
    /// target layer. `holed` is the layer bitmap with the region removed
    /// (transparent, or BG color on the locked Background); `content` is the
    /// extracted pixels; `contentFrame` is where they sit in DOC coords.
    private var regionMove: (targetID: UUID, content: CGImage, contentFrame: CGRect,
                             holed: CGImage, copy: Bool)?

    /// Select(V)-tool drag starting inside a pixel region: lift the region's
    /// pixels off the target layer and float them (⌥ floats a COPY, leaving
    /// the original). Returns the floating content's doc frame — the canvas
    /// drives the sprite with it — or nil when nothing bakeable is under the
    /// region. Preview pieces render off-main like a layer drag.
    func beginRegionMove(copy: Bool) -> CGRect? {
        guard selectionTargetsPixels, let region = selection, let document,
              let targetID = regionTargetID(), let layer = document.layer(id: targetID),
              let ref = layer.imageRef, layer.crop == nil, layer.transform.isIdentity,
              layer.frame.width > 0, layer.frame.height > 0,
              let bitmap = store.image(for: ref) else { return nil }
        var docToBitmap = CGAffineTransform(scaleX: CGFloat(bitmap.width) / layer.frame.width,
                                            y: CGFloat(bitmap.height) / layer.frame.height)
            .translatedBy(x: -layer.frame.minX, y: -layer.frame.minY)
        let localPath = region.path.copy(using: &docToBitmap) ?? region.path
        // The hole: transparent on normal layers; the locked Background gets
        // the background color (Photoshop's Move-from-Background behavior).
        let holed = layer.isLocked
            ? RegionOps.filled(bitmap, path: localPath, hex: backgroundFillHex)
            : RegionOps.erased(bitmap, path: localPath)
        guard let holed, let content = RegionOps.extracted(bitmap, path: localPath) else { return nil }
        let localBounds = localPath.boundingBoxOfPath.integral
            .intersection(CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        let contentFrame = localBounds.applying(docToBitmap.inverted())
        regionMove = (targetID, content, contentFrame, holed, copy)

        // Preview pieces (async, like beginLayerDrag): underlay = composite
        // with the hole showing (or unchanged for a copy), sprite = content.
        dragPreview = nil
        clearPreviewAfterNextFrame = false
        dragPreviewGeneration += 1
        let generation = dragPreviewGeneration
        var underlayDoc = displayFiltered(document)
        var tempRef: ImageRef?
        if !copy {
            let holedRef = store.register(holed)
            tempRef = holedRef
            underlayDoc.updateLayer(id: targetID) { $0.content = .image(holedRef) }
        }
        let blend = layer.effectiveBlendMode
        let renderer = previewRenderer
        let store = store
        Task.detached(priority: .userInitiated) { [weak self] in
            let underlay = renderer.render(underlayDoc, store: store)
            if let tempRef { store.remove(tempRef) }
            await MainActor.run {
                guard let self, self.dragPreviewGeneration == generation, let underlay else { return }
                self.dragPreview = DragPreview(layerID: targetID, underlay: underlay,
                                               sprite: content, padding: 0, blendMode: blend)
            }
        }
        return contentFrame
    }

    /// Mouse-up: bake the floated content into the target layer at its new
    /// spot — ONE undo step — and move the selection outline with it. A zero
    /// delta (a mere click) bakes nothing.
    func commitRegionMove(delta: CGPoint) {
        guard let session = regionMove, delta != .zero,
              let document, let layer = document.layer(id: session.targetID),
              let ref = layer.imageRef, let bitmap = store.image(for: ref),
              layer.frame.width > 0, layer.frame.height > 0 else {
            cancelRegionMove()
            return
        }
        let base = session.copy ? bitmap : session.holed
        // The stamp rect in bitmap pixels: content frame + delta, mapped back.
        let docToBitmap = CGAffineTransform(scaleX: CGFloat(bitmap.width) / layer.frame.width,
                                            y: CGFloat(bitmap.height) / layer.frame.height)
            .translatedBy(x: -layer.frame.minX, y: -layer.frame.minY)
        let stampRect = session.contentFrame.offsetBy(dx: delta.x, dy: delta.y)
            .applying(docToBitmap)
        guard let stamped = RegionOps.stamped(base, overlay: session.content, at: stampRect) else {
            cancelRegionMove()
            return
        }
        regionMove = nil
        dragPreviewGeneration += 1 // cancels an in-flight preview session
        clearPreviewAfterNextFrame = dragPreview != nil
        let newRef = store.register(stamped)
        perform { $0.updateLayer(id: session.targetID) { $0.content = .image(newRef) } }
        // The selection follows its content (Photoshop).
        if let moved = selection?.translated(by: CGVector(dx: delta.x, dy: delta.y)) {
            setSelection(moved, captureLayers: false)
        }
    }

    /// Esc / zero-move: drop the float; the document never changed.
    func cancelRegionMove() {
        regionMove = nil
        dragPreviewGeneration += 1
        dragPreview = nil
    }

    /// Layer ▸ New Layer: a canvas-sized transparent image layer on top,
    /// selected — with the selection region PRESERVED, so select → new layer
    /// → fill lands paint on the fresh layer (the Photoshop flow).
    func newEmptyLayer() {
        guard let document else { return }
        let size = document.canvasSize
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let transparent = context.makeImage() else { return }
        let ref = store.register(transparent)
        let layer = Layer(name: "Layer", content: .image(ref),
                          frame: CGRect(origin: .zero, size: size))
        perform { $0.addLayer(layer) }
        selectedLayerID = layer.id
    }

    /// ⌫ with the (locked) Background selected: reset it to the background
    /// color — "clear it / make the background default".
    func clearBackgroundLayer() {
        guard let id = selectedLayerID, let layer = document?.layer(id: id),
              layer.isLocked, layer.imageRef != nil else { return }
        fillLayer(id: id, hex: backgroundFillHex)
    }

    /// A tiny solid bitmap; layer frames stretch it (identical pixels resample
    /// to the same color).
    private static func solidImage(hex: String) -> CGImage? {
        guard let rgba = RGBA(hex: hex),
              let context = CGContext(data: nil, width: 8, height: 8,
                                      bitsPerComponent: 8, bytesPerRow: 32,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return context.makeImage()
    }

    private static let annotationStylesKey = "annotationStyles"

    private static func loadAnnotationStyles() -> AnnotationStyles {
        guard let data = UserDefaults.standard.data(forKey: annotationStylesKey),
              let styles = try? JSONDecoder().decode(AnnotationStyles.self, from: data) else {
            return AnnotationStyles()
        }
        return styles
    }

    private func saveAnnotationStyles() {
        if let data = try? JSONEncoder().encode(annotationStyles) {
            UserDefaults.standard.set(data, forKey: Self.annotationStylesKey)
        }
    }

    // MARK: - Text styling & inline editing

    /// Styled (empty) content for the current text style; the canvas's inline
    /// editor mirrors it so what you type matches what commit rasterizes.
    var activeTextContent: TextContent {
        var content = textStyles.content()
        // NEW text types in the current foreground color; re-edits keep the
        // layer's own color (the session seeds the styles).
        if editingTextLayerID == nil { content.colorHex = foregroundFillHex }
        return content
    }

    /// The selected text layer when the select tool is active — the properties
    /// panel edits its font face/size/weight/color (13.1) instead of only the
    /// new-text defaults. Mirrors `selectedAnnotationLayer`.
    var selectedTextLayer: Layer? {
        guard activeTool == .select, let id = selectedLayerID,
              let layer = document?.layer(id: id),
              case .text = layer.content else { return nil }
        return layer
    }

    /// Restyles the selected text layer through `TextBuilder.restyled` and
    /// re-measures its frame (the rasterizer needs CoreText, so it's done here),
    /// keeping the wrap width so layout doesn't shift. One undo step.
    private func restyleSelectedText(_ layer: Layer, fontName: String? = nil,
                                     fontSize: CGFloat? = nil, weight: TextWeight? = nil,
                                     colorHex: String? = nil) {
        discardDragPreview()
        let maxWidth = layer.frame.width
        perform { document in
            document.updateLayer(id: layer.id) { l in
                l = TextBuilder.restyled(layer: l, fontName: fontName, fontSize: fontSize,
                                         weight: weight, colorHex: colorHex)
                if case .text(let content) = l.content {
                    let size = TextRasterizer.naturalSize(content, maxWidth: maxWidth,
                                                          minWidth: TextRasterizer.minimumTextWidth)
                    l.frame = CGRect(origin: l.frame.origin, size: size)
                }
            }
        }
    }

    func setTextFont(_ name: String) {
        if let layer = selectedTextLayer { restyleSelectedText(layer, fontName: name) }
        textStyles.fontName = name
        saveTextStyles()
    }

    func setTextFontSize(_ size: CGFloat) {
        if let layer = selectedTextLayer { restyleSelectedText(layer, fontSize: size) }
        textStyles.fontSize = size
        saveTextStyles()
    }

    func setTextWeight(_ weight: TextWeight) {
        if let layer = selectedTextLayer { restyleSelectedText(layer, weight: weight) }
        textStyles.weight = weight
        saveTextStyles()
    }

    func setTextColor(_ hex: String) {
        if let layer = selectedTextLayer { restyleSelectedText(layer, colorHex: hex) }
        textStyles.colorHex = hex
        foregroundFillHex = hex // text color picks update the current color too
        saveTextStyles()
        recordRecentColor(hex: hex)
    }

    // MARK: - Docked text inspector (targets a specific layer, independent of
    // the active tool — so editing a selected text element's font from the
    // docked panel always reaches the document and updates the new-text default).

    /// Restyles `layerID` if it's a text layer, re-measuring its frame. One undo
    /// step. Also updates the new-text default so the next block inherits it.
    func setTextStyle(layerID: UUID, fontName: String? = nil, fontSize: CGFloat? = nil,
                      weight: TextWeight? = nil, colorHex: String? = nil) {
        setTextStyle(ids: [layerID], fontName: fontName, fontSize: fontSize,
                     weight: weight, colorHex: colorHex)
    }

    /// The same over EVERY picked text layer, in ONE undo step: three labels
    /// made 14pt is one trip round the panel and one press of undo, not three.
    ///
    /// Each label keeps its own wrap width while its words are re-set, so one
    /// dragged wide stays wide. The re-measure needs CoreText, which is why it
    /// happens here rather than in the core, and why several layers means
    /// several measurements inside the one step.
    func setTextStyle(ids: [UUID], fontName: String? = nil, fontSize: CGFloat? = nil,
                      weight: TextWeight? = nil, colorHex: String? = nil) {
        let targets = ids.filter { id in
            guard let layer = document?.layer(id: id), !layer.isLocked,
                  case .text(let words) = layer.content else { return false }
            // Only the labels this actually changes. Picking 14pt when they are
            // all already 14pt is a menu closing, not an undo step.
            if let fontName, words.fontName != fontName { return true }
            if let fontSize, words.fontSize != fontSize { return true }
            if let weight, words.weight != weight { return true }
            if let colorHex, words.colorHex != colorHex { return true }
            return false
        }
        guard !targets.isEmpty else {
            // Nothing to change in the document, but this is still what the
            // next block of text should start at.
            rememberTextDefaults(fontName: fontName, fontSize: fontSize,
                                 weight: weight, colorHex: colorHex)
            return
        }
        // How much room each label's words get at the new type. A box somebody
        // made bigger than its words — a paragraph, or a label told to stretch
        // — keeps the room it was given, so restyling re-wraps in place. A box
        // still hugging its words re-hugs them, instead of wrapping the moment
        // bold makes them a few points wider than the box they just fitted.
        // (Current has no stretching, so it keeps its old rule untouched.)
        let widths: [UUID: CGFloat] = targets.reduce(into: [:]) { widths, id in
            guard let layer = document?.layer(id: id) else { return }
            guard Experiments.shared.placementEnabled, let words = layer.text else {
                widths[id] = layer.frame.width
                return
            }
            let hugged = TextRasterizer.naturalSize(words, maxWidth: layer.frame.width,
                                                    minWidth: TextRasterizer.minimumTextWidth)
            widths[id] = layer.frame.width > hugged.width + 0.5
                ? layer.frame.width : .greatestFiniteMagnitude
        }
        discardDragPreview()
        perform { document in
            for id in targets {
                guard let maxWidth = widths[id] else { continue }
                document.updateLayer(id: id) { l in
                    l = TextBuilder.restyled(layer: l, fontName: fontName, fontSize: fontSize,
                                             weight: weight, colorHex: colorHex)
                    if case .text(let content) = l.content {
                        let size = TextRasterizer.naturalSize(
                            content, maxWidth: maxWidth,
                            minWidth: TextRasterizer.minimumTextWidth)
                        l.frame = CGRect(origin: l.frame.origin, size: size)
                    }
                }
            }
        }
        rememberTextDefaults(fontName: fontName, fontSize: fontSize,
                             weight: weight, colorHex: colorHex)
    }

    /// What the next block of text starts at.
    private func rememberTextDefaults(fontName: String?, fontSize: CGFloat?,
                                      weight: TextWeight?, colorHex: String?) {
        if let fontName { textStyles.fontName = fontName }
        if let fontSize { textStyles.fontSize = fontSize }
        if let weight { textStyles.weight = weight }
        if let colorHex { textStyles.colorHex = colorHex }
        saveTextStyles()
        if let colorHex { recordRecentColor(hex: colorHex) }
    }

    /// Moves a text layer's words across their box. One undo step, and the box
    /// itself never moves: alignment says where the words sit in the room they
    /// already have, so a label dragged wide or told to stretch stays that
    /// wide. It is not a new-text default either — a fresh block starts at the
    /// left, where text has always started.
    func setTextAlignment(layerID: UUID, _ alignment: TextAlign) {
        setTextAlignment(ids: [layerID], alignment)
    }

    /// The same, down the box.
    func setTextAlignment(layerID: UUID, _ alignment: TextVerticalAlign) {
        setTextAlignment(ids: [layerID], alignment)
    }

    /// Every picked label's words move across their boxes together, in one
    /// undo step.
    func setTextAlignment(ids: [UUID], _ alignment: TextAlign) {
        let targets = textAlignmentTargets(ids)
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { document in
            for id in targets { document.setTextAlignment(id: id, alignment) }
        }
    }

    /// And down them.
    func setTextAlignment(ids: [UUID], _ alignment: TextVerticalAlign) {
        let targets = textAlignmentTargets(ids)
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { document in
            for id in targets { document.setTextAlignment(id: id, alignment) }
        }
    }

    private func textAlignmentTargets(_ ids: [UUID]) -> [UUID] {
        ids.filter { document?.layer(id: $0).map { $0.text != nil && !$0.isLocked } == true }
    }

    /// An inline edit began. Re-editing an existing layer adopts its style (so
    /// the font picker edits what's on screen) and hides the layer until
    /// commit/cancel — the editor overlay visually replaces it.
    func beginTextEdit(layerID: UUID?) {
        guard let layerID, let layer = document?.layer(id: layerID),
              case .text(let content) = layer.content else { return }
        textStyles.adopt(content)
        saveTextStyles()
        editingTextLayerID = layerID
        if let document { submit(document) }
    }

    /// Inline edit finished. Empty text adds nothing (new block) or deletes the
    /// layer (re-edit); otherwise one undo step adds/updates the layer with its
    /// frame hugging the re-measured text. `maxWidth` is the wrap width the
    /// editor used (document points), so layout doesn't shift on commit.
    func commitTextEdit(layerID: UUID?, origin: CGPoint, string: String, maxWidth: CGFloat) {
        editingTextLayerID = nil
        let isEmpty = string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var content = textStyles.content(string: string)
        // Where the words sit belongs to the layer, not to the new-text style,
        // so re-wording a centred label keeps it centred instead of dropping it
        // back to the left edge.
        let edited = layerID.flatMap { document?.layer(id: $0) }
        if let existing = edited?.text {
            content.alignment = existing.alignment
            content.verticalAlignment = existing.verticalAlignment
        }
        // A box somebody made bigger than its words — a paragraph, or a label
        // told to stretch — keeps the room it was given, so re-wording it
        // re-wraps in place instead of collapsing back around the words and
        // pulling centred text off centre. A box still hugging its words
        // re-hugs them.
        var roomyWidth: CGFloat?
        var roomyHeight: CGFloat?
        // Next only, with the rest of placement: Current has no Align, so no
        // text in it can be pulled off centre by a box that re-hugs.
        if Experiments.shared.placementEnabled, let layer = edited, let words = layer.text {
            (roomyWidth, roomyHeight) = TextBlockMetrics.roomyBox(for: words, frame: layer.frame)
        }
        if let layerID {
            if isEmpty {
                perform { $0.removeLayer(id: layerID) }
            } else {
                // The same measurer the inline editor sized its field with, so
                // the words land in the box they were typed in.
                let size = TextBlockMetrics.frameSize(for: content, maxWidth: maxWidth,
                                                      roomyWidth: roomyWidth,
                                                      roomyHeight: roomyHeight)
                perform { document in
                    document.updateLayer(id: layerID) {
                        $0.content = .text(content)
                        $0.frame = CGRect(origin: origin, size: size)
                        // Re-edit may have changed the color; keep the
                        // auto-contrast shadow (3.6) opposing it.
                        $0.style.shadow = TextBuilder.autoContrastShadow(forColorHex: content.colorHex)
                    }
                }
            }
        } else {
            guard !isEmpty else { return }
            // New text commits in the current foreground color (16.12).
            var content = content
            content.colorHex = foregroundFillHex
            let size = TextBlockMetrics.frameSize(for: content, maxWidth: maxWidth)
            let layer = TextBuilder.layer(content: content, at: origin, naturalSize: size)
            perform { $0.addLayerDrawnOnFrame(layer) }
            // Re-editing existing text already runs with Select active, so only
            // the new-block path hands the editor back.
            finishCreating(layer.id)
        }
    }

    /// Inline edit abandoned (Esc): a hidden re-edited layer comes back as-is.
    func cancelTextEdit() {
        editingTextLayerID = nil
        rerender()
    }

    private static let textStylesKey = "textStyles"

    private static func loadTextStyles() -> TextStyles {
        guard let data = UserDefaults.standard.data(forKey: textStylesKey),
              let styles = try? JSONDecoder().decode(TextStyles.self, from: data) else {
            return TextStyles()
        }
        return styles
    }

    private func saveTextStyles() {
        if let data = try? JSONEncoder().encode(textStyles) {
            UserDefaults.standard.set(data, forKey: Self.textStylesKey)
        }
    }

    // MARK: - Layers panel

    /// Style override while an inspector slider drag is in flight — rendered
    /// as a preview, committed to history only on release (one undo step per
    /// gesture, same pattern as move/resize drags).
    ///
    /// A drag can be aimed at several layers at once: one pull on Corner Radius
    /// rounds every picked button, and one undo puts them all back.
    private var stylePreview: (ids: [UUID], styles: [UUID: LayerStyle])?
    /// Thumbnail cache keyed by layer id; `hash` invalidates on any layer edit.
    private var thumbnailCache: [UUID: (hash: Int, image: CGImage)] = [:]
    private var thumbnailsInFlight: Set<Int> = []
    /// The starter set's subtrees and their shelf pictures. The five never
    /// change, so both are built once, on the first look at the Components
    /// shelf, and nothing about them is per document.
    private var starterPreviewLayers: [StarterComponent: Layer] = [:]
    private var starterThumbnails: [ShelfPictureKey: CGImage] = [:]
    /// Shelf pictures for the document's own components. Kept apart from the
    /// layers panel's thumbnails because a shelf tile asks for a much sharper
    /// picture than a 24 point row does, and the same component is often in
    /// both lists at once.
    private var shelfThumbnails: [ShelfPictureKey: (hash: Int, image: CGImage)] = [:]
    private var shelfThumbnailsInFlight: Set<ShelfPictureKey> = []

    /// Layers in panel order (visual index 0 = topmost).
    var panelLayers: [Layer] {
        (document?.layers ?? []).reversed()
    }

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
    private(set) var expandedGroupIDs: Set<UUID> = [] {
        didSet {
            guard !isRestoringOpenGroups, expandedGroupIDs != oldValue else { return }
            rememberExpandedGroups()
        }
    }

    /// True only while the open groups are being reset or read back for a
    /// document that is arriving, so setting them up cannot overwrite the
    /// record of the file that is leaving.
    @ObservationIgnored private var isRestoringOpenGroups = false

    private func withoutRememberingOpenGroups(_ body: () -> Void) {
        isRestoringOpenGroups = true
        body()
        isRestoringOpenGroups = false
    }

    /// Where this window's open/shut record is filed: the file it is editing.
    /// Nil for a picture that has never been saved or opened from anywhere,
    /// which is simply not remembered — there is nothing to come back to.
    private var openGroupMemoryKey: String? {
        (documentURL ?? openedFileURL)?.standardizedFileURL.path
    }

    static let openGroupsKey = "layers.openGroups"

    private static func loadOpenGroupMemory() -> OpenGroupMemory {
        guard let data = UserDefaults.standard.data(forKey: openGroupsKey),
              let memory = try? JSONDecoder().decode(OpenGroupMemory.self, from: data)
        else { return OpenGroupMemory() }
        return memory
    }

    /// Files away which groups are open now, dropping any the document no
    /// longer has. Nothing is written when the record would be unchanged, so
    /// selecting your way around a picture is not a stream of writes.
    private func rememberExpandedGroups() {
        // Only the release that HAS groups keeps a record of them, so nothing
        // about this reaches a release whose layers list is flat.
        guard Experiments.shared.layerGroupsEnabled else { return }
        guard let key = openGroupMemoryKey, let document else { return }
        var memory = Self.loadOpenGroupMemory()
        let before = memory
        memory.remember(expandedGroupIDs, for: key, stillInDocument: document.openableGroupIDs)
        guard memory != before, let data = try? JSONEncoder().encode(memory) else { return }
        UserDefaults.standard.set(data, forKey: Self.openGroupsKey)
    }

    /// Reopens the groups this file had open last time. Called once the file
    /// the window is editing is known, which for a picture opened from disk is
    /// after the document has been installed.
    private func restoreExpandedGroups() {
        guard Experiments.shared.layerGroupsEnabled else { return }
        guard let key = openGroupMemoryKey, let document else { return }
        let remembered = Self.loadOpenGroupMemory()
            .openGroups(for: key, stillInDocument: document.openableGroupIDs)
        withoutRememberingOpenGroups { expandedGroupIDs.formUnion(remembered) }
        // Written straight back, so a group deleted while the file was closed
        // is gone from the record whether or not the list is ever touched.
        rememberExpandedGroups()
    }

    /// The rows the layers list draws, top down, with an open group's contents
    /// indented under it. With the groups flag off every group stays shut, so
    /// the list is the flat one it has always been.
    var panelRows: [LayerPanelRow] {
        document?.panelRows(expanded: Experiments.shared.layerGroupsEnabled ? expandedGroupIDs : [])
            ?? []
    }

    /// The same rows, each carrying what it draws — name, visibility, lock,
    /// whether it is selected, its component marks — from a single walk of the
    /// tree.
    ///
    /// The layers list reads THIS rather than holding ids and asking for each
    /// layer again while it draws: a lookup by id searches the whole document,
    /// so a hundred rows meant a hundred walks of a hundred layers on every
    /// click. It also makes each row a small value the list can compare, which
    /// is what lets an untouched row skip its redraw entirely.
    var layerRows: [LayerRowDisplay] {
        var selected = multiSelectedLayerIDs
        if let selectedLayerID { selected.insert(selectedLayerID) }
        return document?.layerRows(
            expanded: Experiments.shared.layerGroupsEnabled ? expandedGroupIDs : [],
            selected: selected) ?? []
    }

    /// The twist-open control on a group row.
    func toggleGroupExpanded(id: UUID) {
        if expandedGroupIDs.contains(id) { expandedGroupIDs.remove(id) } else { expandedGroupIDs.insert(id) }
    }

    /// Opens every group above a layer, so its row is on screen. Called
    /// whenever the selection changes, which is what keeps the canvas and the
    /// list saying the same thing.
    private func revealInLayersList(_ id: UUID) {
        guard let document else { return }
        let ancestors = document.ancestorIDs(of: id)
        // Only a group that is not open yet is worth a write: the layers list
        // animates on this set, so an unchanged write is a re-layout for nothing.
        guard ancestors.contains(where: { !expandedGroupIDs.contains($0) }) else { return }
        expandedGroupIDs.formUnion(ancestors)
    }

    /// Whether a drag carrying `ids` can land here — what decides between a
    /// drop line and the no-entry cursor.
    func canDropRows(ids: Set<UUID>, _ drop: LayerDrop) -> Bool {
        guard let document else { return false }
        if case .inside = drop, !Experiments.shared.layerGroupsEnabled { return false }
        return document.canDrop(ids: ids, drop)
    }

    /// Where a drag hovering over a row would land, which is what the drop
    /// line draws. Nil means nothing can land here.
    func dropProposal(carrying ids: Set<UUID>, over row: LayerPanelRow,
                      pointerY: CGFloat, rowHeight: CGFloat) -> LayerDrop? {
        document?.dropProposal(carrying: ids, over: row, pointerY: pointerY, rowHeight: rowHeight,
                               allowsInside: Experiments.shared.layerGroupsEnabled)
    }

    /// A finished drag in the layers list: one undo step, and the layers keep
    /// their place on the canvas.
    func dropRows(ids: Set<UUID>, _ drop: LayerDrop) {
        guard canDropRows(ids: ids, drop) else { return }
        discardDragPreview()
        var landed = false
        perform { landed = $0.dropLayers(ids: ids, drop) }
        guard landed else { return }
        // Dropping into a group opens it, so you can see where what you were
        // carrying went.
        if case .inside(let groupID) = drop { expandedGroupIDs.insert(groupID) }
        // What you just dragged is what you are now holding, so the inspector
        // and the canvas talk about the layer you acted on rather than
        // whatever happened to be selected before the drag.
        selectLayers(ids)
    }

    /// A layer's style, preview-aware so inspector sliders don't snap back
    /// mid-drag.
    func previewedStyle(of id: UUID) -> LayerStyle? {
        if let style = stylePreview?.styles[id] { return style }
        return document?.layer(id: id)?.style
    }

    /// Live inspector-slider update over every layer the row speaks for:
    /// renders the new style without touching history. The first preview of a
    /// gesture drops any held drag sprite (it shows the old style).
    func previewLayerStyle(ids: [UUID], _ mutate: (inout LayerStyle) -> Void) {
        guard !ids.isEmpty, var doc = document else { return }
        // A drag that has moved to a different row or a different selection is
        // a new gesture: nothing of the old one carries over.
        if stylePreview?.ids != ids {
            discardDragPreview()
            stylePreview = (ids, [:])
        }
        var styles = stylePreview?.styles ?? [:]
        for id in ids {
            guard var style = styles[id] ?? doc.layer(id: id)?.style else { continue }
            mutate(&style)
            styles[id] = style
            doc.updateLayer(id: id) { $0.style = style }
        }
        stylePreview = (ids, styles)
        submit(doc)
    }

    func previewLayerStyle(id: UUID, _ mutate: (inout LayerStyle) -> Void) {
        previewLayerStyle(ids: [id], mutate)
    }

    /// Slider release: ONE undo step from the pre-gesture styles to the last
    /// previewed ones, however many layers the drag reached (a no-change
    /// release is a History no-op).
    func commitLayerStyle(ids: [UUID]) {
        guard let preview = stylePreview, preview.ids == ids else { return }
        stylePreview = nil
        perform { doc in
            for (id, style) in preview.styles {
                doc.updateLayer(id: id) { $0.style = style }
            }
        }
        rememberStyleDefault(of: ids)
    }

    func commitLayerStyle(id: UUID) { commitLayerStyle(ids: [id]) }

    /// One-shot style edit (steppers, toggles, the shadow switch): a single
    /// undo step over the whole selection, no preview.
    func setLayerStyle(ids: [UUID], _ mutate: @escaping (inout LayerStyle) -> Void) {
        guard !ids.isEmpty else { return }
        stylePreview = nil
        discardDragPreview()
        perform { doc in _ = doc.updateLayerStyles(layerIDs: ids, mutate) }
        rememberStyleDefault(of: ids)
    }

    func setLayerStyle(id: UUID, _ mutate: @escaping (inout LayerStyle) -> Void) {
        setLayerStyle(ids: [id], mutate)
    }

    /// The next rectangle you draw inherits the one you just styled — but only
    /// when you styled ONE. Over a selection the layers still differ in every
    /// field the drag did not touch, so there is no "the style you just made"
    /// to hand the tool, and picking one of them would hand it three fields
    /// nobody set.
    private func rememberStyleDefault(of ids: [UUID]) {
        guard ids.count == 1, let only = ids.first else { return }
        captureStyleDefault(layerID: only)
    }

    /// Remember a styled layer's effects as its TOOL's default, so the next
    /// object of that kind inherits them — per shape for annotations, and for the
    /// measure tool as a whole.
    private func captureStyleDefault(layerID: UUID) {
        guard let layer = document?.layer(id: layerID) else { return }
        if let shape = layer.annotation?.shape {
            annotationStyles.setLayerStyle(layer.style, forShape: shape)
            saveAnnotationStyles()
        } else if layer.measure != nil {
            updateMeasureStyles { $0.layerStyle = layer.style }
        }
    }

    func toggleLayerVisibility(id: UUID) {
        discardDragPreview()
        // Toggling a member of the multi-selection drives the WHOLE selection
        // to the clicked layer's new state, in one undo step.
        if multiSelectedLayerIDs.contains(id) {
            let show = !(document?.layer(id: id)?.isVisible ?? true)
            let ids = multiSelectedLayerIDs
            perform { doc in
                for layerID in ids {
                    doc.updateLayer(id: layerID) { $0.isVisible = show }
                }
            }
            return
        }
        perform { $0.updateLayer(id: id) { $0.isVisible.toggle() } }
    }

    func toggleLayerLock(id: UUID) {
        // Locking a member of the multi-selection locks/unlocks all of it (and
        // locked layers leave the selection — they're no longer editable).
        if multiSelectedLayerIDs.contains(id) {
            let lock = !(document?.layer(id: id)?.isLocked ?? false)
            let ids = multiSelectedLayerIDs
            perform { doc in
                for layerID in ids {
                    doc.updateLayer(id: layerID) { $0.isLocked = lock }
                }
            }
            if lock { multiSelectedLayerIDs = [] }
            return
        }
        perform { $0.updateLayer(id: id) { $0.isLocked.toggle() } }
        if document?.layer(id: id)?.isLocked == true, selectedLayerID == id {
            selectedLayerID = nil
        }
    }

    func renameLayer(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform { $0.updateLayer(id: id) { $0.name = trimmed } }
    }

    func deleteLayer(id: UUID) {
        // Deleting a member of the multi-selection deletes the whole selection.
        if multiSelectedLayerIDs.contains(id) {
            deleteLayers(ids: Array(multiSelectedLayerIDs))
            return
        }
        discardDragPreview()
        if selectedLayerID == id { selectedLayerID = nil }
        perform { $0.removeLayer(id: id) }
    }

    // MARK: - Whole-selection commands (Layers menu)

    /// Every layer the Layers menu's Duplicate, Delete and arrange commands
    /// act on: the multi-selection when there is one (shift-click, command-
    /// click or a marquee), else the primary selection. Empty with no layer
    /// selected, which is when those menu items grey out.
    var actionableLayerIDs: Set<UUID> {
        if !multiSelectedLayerIDs.isEmpty { return multiSelectedLayerIDs }
        return selectedLayerID.map { [$0] } ?? []
    }

    var hasLayerSelection: Bool { !actionableLayerIDs.isEmpty }

    /// Layers > Delete Layer (⌘⌫): the whole selection in one undo step.
    func deleteSelectedLayers() {
        let ids = actionableLayerIDs
        guard !ids.isEmpty else { return }
        deleteLayers(ids: Array(ids))
    }

    /// Layers > Duplicate Layer over a selection: every member gets a copy
    /// directly above it, in one undo step, and the copies become the new
    /// selection so a follow-up nudge or arrange moves the copies, not the
    /// originals.
    func duplicateSelectedLayers() {
        let ids = actionableLayerIDs
        guard !ids.isEmpty else { return }
        if ids.count == 1, let only = ids.first {
            duplicateLayer(id: only)
            return
        }
        discardDragPreview()
        var copies: [Layer] = []
        perform { copies = $0.duplicateLayers(ids: ids, offsetBy: CGPoint(x: 16, y: 16)) }
        selectLayers(Set(copies.map(\.id)))
    }

    /// The four arrange commands over a selection: the members move together,
    /// keeping their relative order and gaps, and stop at the locked Background.
    func restackSelectedLayers(_ step: PhotonzDocument.RestackStep) {
        guard let document else { return }
        let ids = actionableLayerIDs
        guard !ids.isEmpty else { return }
        // Dry-run on a copy so a pinned selection never costs an undo step.
        var preview = document
        guard preview.restackLayers(ids: ids, step) else { return }
        discardDragPreview()
        perform { $0.restackLayers(ids: ids, step) }
    }

    // MARK: - Lining layers up (Next flag `next-align-layers`)

    /// The boxes the Arrange commands act on: every selected layer that is
    /// free to move, as the box it occupies on canvas. Canvas space, so a
    /// layer inside a group lines up with one outside it — what you see is
    /// what gets lined up, whatever the layers list says about parentage.
    /// Locked layers stay out: the picture underneath must not slide when you
    /// tidy the buttons on top of it.
    private var arrangeBoxes: [LayerArrangement.Box] {
        guard Experiments.shared.alignLayersEnabled, let document else { return [] }
        let selected = actionableLayerIDs
        return selected.compactMap { id in
            guard let layer = document.layer(id: id), !layer.isLocked,
                  let bounds = document.canvasBounds(of: id) else { return nil }
            // A layer inside a selected group is already carried by that
            // group, so it takes no place of its own here: moving both would
            // be lining a thing up against something it is part of.
            var parent = document.parentID(of: id)
            while let up = parent {
                if selected.contains(up) { return nil }
                parent = document.parentID(of: up)
            }
            return LayerArrangement.Box(id: id, frame: bounds)
        }
    }

    /// What ONE selected layer lines up inside, when something holds it.
    ///
    /// A layer picked on its own has nothing to line up with, unless something
    /// holds it. Two kinds of thing do, and the rule is `ArrangeContainer`'s:
    /// a screen hands over its own box, and a plain group hands over the box of
    /// everything ELSE inside it, which is what makes centring a word on a
    /// button mean the button's background.
    ///
    /// It is the layer's OWN parent or nothing: the search never climbs. A word
    /// inside a button inside a screen answers to the button, rather than flying
    /// to the middle of the screen and out of the button it belongs to.
    ///
    /// Nil for everything else, which keeps a multi-selection lining up with
    /// itself exactly as it did.
    private var arrangeReference: (holder: Layer, container: ArrangeContainer)? {
        guard let document else { return nil }
        let boxes = arrangeBoxes
        guard boxes.count == 1, let id = boxes.first?.id,
              let container = document.arrangeContainer(of: id),
              let holder = document.layer(id: container.id) else { return nil }
        // Each kind of holder rides its own flag: screens are `next-frames`,
        // groups are `next-layer-groups`.
        guard holder.isFrame ? Experiments.shared.framesEnabled
                             : Experiments.shared.layerGroupsEnabled else { return nil }
        return (holder, container)
    }

    /// What the Arrange row is lining things up against, in the words it shows:
    /// the screen's or the group's name when there is one, nil when the
    /// selection is its own reference. The row has to say this out loud,
    /// because six live buttons with only one layer on screen otherwise leave
    /// you guessing what moves where.
    var arrangeReferenceName: String? {
        guard let holder = arrangeReference?.holder else { return nil }
        let name = holder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty else { return name }
        return holder.isFrame ? "the screen around it" : "the group around it"
    }

    /// How many layers the Arrange row is speaking for, so it can say so.
    var arrangeableLayerCount: Int { arrangeBoxes.count }

    var canAlignSelection: Bool {
        LayerArrangement.canAlign(count: arrangeBoxes.count,
                                  hasContainer: arrangeReference != nil)
    }

    /// Whether ONE of the six align commands has anywhere to move what is
    /// picked. Inside a plain group an axis can be dead: a word as wide as the
    /// button it sits on cannot go left, centre or right, so those three dim
    /// and say why rather than pretending.
    func canAlignSelection(_ alignment: LayerAlignment) -> Bool {
        guard canAlignSelection else { return false }
        guard let container = arrangeReference?.container else { return true }
        return container.allows(alignment)
    }

    /// Why half the row is dim, in plain words, or nil when none of it is. The
    /// caption says this out loud as well as the hover tips: three grey buttons
    /// with no reason beside them are a puzzle, and the answer is one clause.
    var arrangeDeadAxisNote: String? {
        arrangeDeadAxisReason(.left) ?? arrangeDeadAxisReason(.top)
    }

    /// Why three of the buttons are dim, in plain words, or nil when they are
    /// not. Only a plain group can say this: it has no box of its own, so a
    /// piece that already spans everything else in it has nowhere to go.
    func arrangeDeadAxisReason(_ alignment: LayerAlignment) -> String? {
        guard let reference = arrangeReference,
              !reference.container.allows(alignment) else { return nil }
        // Never the holder's name: only a plain group can have a dead axis, and
        // the sentence beside it has just said which group this is.
        return alignment.isHorizontal
            ? "It is already as wide as the group, so only up and down can move it."
            : "It is already as tall as the group, so only sideways can move it."
    }

    var canDistributeSelection: Bool { LayerArrangement.canDistribute(count: arrangeBoxes.count) }

    /// Layer ▸ Align: every selected layer moves onto the selection's own
    /// edge or middle, in ONE undo step. The layer already on that edge does
    /// not move, so pressing it twice is a no-op rather than a slow drift.
    /// One layer inside a screen or a group moves onto ITS HOLDER'S edge or
    /// middle instead, so a single press centres a label inside a card or a
    /// word on a button.
    func alignSelection(_ alignment: LayerAlignment) {
        guard canAlignSelection(alignment) else { return }
        moveLayers(LayerArrangement.aligned(arrangeBoxes, to: alignment,
                                            within: arrangeReference?.container.bounds))
    }

    /// Layer ▸ Space Evenly: the outermost two hold still and everything
    /// between them slides so the gaps match, in ONE undo step.
    func distributeSelection(_ axis: LayerDistribution) {
        moveLayers(LayerArrangement.distributed(arrangeBoxes, along: axis))
    }

    /// One undo step for a whole set of moves. Each layer is placed at an
    /// origin worked out from where everything was BEFORE the command, so the
    /// order they are applied in cannot change the result.
    private func moveLayers(_ moves: [UUID: CGPoint]) {
        guard !moves.isEmpty else { return }
        discardDragPreview()
        perform { document in
            for (id, origin) in moves { document.moveLayer(id: id, toCanvasOrigin: origin) }
        }
    }

    // MARK: - Groups (Next flag `next-layer-groups`)

    /// The group the pointer is currently INSIDE, or nil for the canvas.
    ///
    /// A click picks the outermost thing you are not already inside, so this is
    /// the whole of what "inside" means: a double click sets it (going one
    /// level deeper), Escape clears one level of it, and clicking anywhere
    /// outside drops it. Nothing about it is stored in the document — step out
    /// and the tree is exactly what it was.
    private(set) var groupContextID: UUID?

    /// Whether Layer ▸ Group would do anything.
    var canGroupSelection: Bool {
        guard Experiments.shared.layerGroupsEnabled, let document else { return false }
        return document.canGroup(ids: actionableLayerIDs)
    }

    /// Whether Layer ▸ Ungroup would do anything.
    var canUngroupSelection: Bool {
        guard Experiments.shared.layerGroupsEnabled, let document else { return false }
        return document.canUngroup(ids: actionableLayerIDs)
    }

    /// Layer ▸ Group (⌘G): wraps the selection in a new group, in one undo
    /// step, and selects the group — so the very next drag moves the whole
    /// thing, which is the reason you pressed it.
    func groupSelection() {
        guard canGroupSelection else { return }
        let ids = actionableLayerIDs
        discardDragPreview()
        var madeID: UUID?
        perform { document in
            madeID = document.groupLayers(ids: ids, name: document.freshGroupName())?.id
        }
        groupContextID = madeID.flatMap { document?.parentID(of: $0) }
        selectedLayerID = madeID
        // The rubber band that picked the members no longer describes anything.
        setSelection(nil, captureLayers: false)
    }

    /// Layer ▸ Ungroup (⇧⌘G): takes the selected groups apart in one undo
    /// step, leaving the pieces exactly where they were and selected, so you
    /// can carry straight on with them.
    func ungroupSelection() {
        guard canUngroupSelection else { return }
        let ids = actionableLayerIDs
        discardDragPreview()
        // Anything selected that was not a group stays selected alongside the
        // pieces that just came out.
        let kept = ids.filter { document?.layer(id: $0)?.isGroup != true }
        var freed: [UUID] = []
        perform { freed = $0.ungroupLayers(ids: ids) }
        if groupContextID.map({ document?.layer(id: $0) == nil }) ?? false { groupContextID = nil }
        setSelection(nil, captureLayers: false)
        selectLayers(Set(freed).union(kept))
    }

    // MARK: - Groups that arrange themselves (Next flag `next-auto-layout`)

    /// The group whose Arrangement the Layout section is editing: the one group
    /// picked, and nothing when the selection is anything else.
    var arrangingGroupID: UUID? {
        guard Experiments.shared.autoLayoutEnabled, let document,
              document.canSetGroupLayout(ids: actionableLayerIDs) else { return nil }
        return actionableLayerIDs.first
    }

    /// How the picked group arranges its contents right now, or nil for a group
    /// that holds things wherever you put them.
    var arrangement: GroupLayout? {
        arrangingGroupID.flatMap { document?.layer(id: $0)?.group?.layout }
    }

    /// Whether Layer ▸ Stack Selection would do anything: one group to convert,
    /// or several layers to wrap up and arrange.
    var canStackSelection: Bool {
        guard Experiments.shared.autoLayoutEnabled, let document else { return false }
        let ids = actionableLayerIDs
        return document.canSetGroupLayout(ids: ids) || document.canGroup(ids: ids)
    }

    /// The Layout section's Arrangement row: this group becomes a stack, a
    /// grid, or goes back to holding things wherever they were put. Nothing
    /// moves at the moment it lands — the layout is read off where the contents
    /// already are.
    func setArrangement(id: UUID, kind: GroupLayoutKind?) {
        guard document?.layer(id: id)?.isGroup == true else { return }
        discardDragPreview()
        perform { $0.setGroupLayout(id: id, kind: kind) }
    }

    /// One typed number on a group's arrangement: the gap, the columns, the
    /// padding. Lands as one undo step, like every other typed number.
    func updateArrangement(id: UUID, _ change: @escaping (inout GroupLayout) -> Void) {
        guard document?.layer(id: id)?.group?.layout != nil else { return }
        perform { $0.updateGroupLayout(id: id, change) }
    }

    /// Layer ▸ Stack Selection (⇧⌘S) / Grid Selection: several layers become
    /// one group that arranges them, and a group already picked simply starts
    /// arranging itself. The group is left selected, so the very next thing you
    /// type is its gap.
    func stackSelection(_ kind: GroupLayoutKind) {
        guard canStackSelection else { return }
        let ids = actionableLayerIDs
        discardDragPreview()
        var madeID: UUID?
        perform { madeID = $0.stackSelection(ids: ids, kind: kind) }
        guard let madeID else { return }
        groupContextID = document?.parentID(of: madeID)
        selectedLayerID = madeID
        setSelection(nil, captureLayers: false)
    }

    // MARK: - Components (Next flag `next-components`)

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

    /// Opens the rename field on a row, the way double-clicking the name does.
    func beginRenamingLayer(id: UUID) {
        layerAwaitingRename = id
    }

    /// Whether Make Component, the canvas mark and the Components shelf exist
    /// at all.
    var componentsEnabled: Bool { Experiments.shared.componentsEnabled }

    /// Whether Layer > Make Component would do anything.
    var canMakeComponent: Bool {
        guard componentsEnabled, let document else { return false }
        return document.canMakeComponent(ids: actionableLayerIDs)
    }

    /// Layer > Make Component (Option Command K): promotes the selected group
    /// to a main, in one undo step, and then does the two things that make the
    /// command legible.
    ///
    /// It **shows the Library on the Components shelf**, because the whole
    /// point of the command is that the thing you drew lands somewhere you can
    /// fetch it from, and the shelf is off until asked for. Pressing a key and
    /// seeing nothing change anywhere you are looking is the failure this
    /// avoids.
    ///
    /// Then it **puts the Component section's Name field ready to type in**,
    /// with the name selected, so naming it is typing rather than hunting for a
    /// field. A component nobody named is a tile called "Component".
    func makeComponent() {
        guard canMakeComponent, let id = actionableLayerIDs.first else { return }
        discardDragPreview()
        var made: UUID?
        perform { made = $0.makeComponent(id: id) }
        guard let componentID = made else { return }
        selectedLayerID = id
        setLibraryVisible(true)
        UserDefaults.standard.set(LibraryScope.components.rawValue, forKey: LibraryPanel.scopeKey)
        // ...and the shelf scrolls to the new tile, which is listed after the
        // components already in the document and so is often below the shelf's
        // own fold.
        pendingLibraryTileID = componentID.uuidString
        // ...and setLibraryVisible cleared any picked tile, so the layer is
        // still the one selected thing. Name it.
        componentAwaitingName = componentID
    }

    /// Every main in the open document, as shelf items, and after them the
    /// starters this document has not taken yet (Next, `next-starter-components`).
    ///
    /// The document's own come first: what you made is what you are most
    /// likely reaching for, and the app's five are always there underneath.
    /// A starter you HAVE taken is listed by the document rather than twice,
    /// because a starter's id is its component id.
    var componentEntries: [LibraryEntry] {
        guard componentsEnabled else { return [] }
        let mine = document?.componentLibraryEntries ?? []
        guard starterComponentsEnabled else { return mine }
        return mine + (document?.starterComponentEntries ?? [])
    }

    /// Whether the shelf is stocked with the app's own components.
    var starterComponentsEnabled: Bool { Experiments.shared.starterComponentsEnabled }

    /// The starter behind a shelf tile, nil for a component somebody made.
    /// Only answers for one the document has NOT taken yet: once it is in the
    /// document it is an ordinary component and is described as one.
    func starterComponent(entryID: String) -> StarterComponent? {
        guard starterComponentsEnabled, let id = UUID(uuidString: entryID),
              document?.mainComponent(componentID: id) == nil else { return nil }
        return StarterComponent(componentID: id)
    }

    /// The starter behind the picked Components tile.
    var selectedStarterComponent: StarterComponent? {
        selectedLibraryItemID.flatMap { starterComponent(entryID: $0) }
    }

    /// What a shelf tile draws a picture of: a starter's subtree, built in the
    /// app's own colors at one to one. Not in any document, so it is built
    /// fresh and cached rather than looked up.
    func starterPreviewLayer(_ kind: StarterComponent) -> Layer {
        if let cached = starterPreviewLayers[kind] { return cached }
        let layer = StarterComponents.layer(kind, measure: { TextRasterizer.naturalSize($0) })
        starterPreviewLayers[kind] = layer
        return layer
    }

    /// The picture on a starter's tile, at least `dimension` pixels along its
    /// long side. Rendered off a one-layer document, on the same path every
    /// other thumbnail takes, and kept: the five never change, so this happens
    /// once per size per launch and only once the Components shelf has
    /// actually been looked at.
    ///
    /// The subtree is BUILT at the size it will be drawn rather than built
    /// small and blown up, so a badge on a tile is as crisp as a card is.
    func starterThumbnail(_ kind: StarterComponent, dimension: CGFloat) -> CGImage? {
        let key = ShelfPictureKey(id: kind.componentID, dimension: Int(dimension))
        if let cached = starterThumbnails[key] { return cached }
        let box = starterPreviewLayer(kind).localBounds
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = max(dimension / max(box.width, box.height), 1)
        var preview = StarterComponents.layer(kind, scale: scale,
                                              measure: { TextRasterizer.naturalSize($0) })
        let scaledBox = preview.localBounds
        guard scaledBox.width > 0, scaledBox.height > 0 else { return nil }
        preview.frame.origin = .zero
        let document = PhotonzDocument(canvasSize: scaledBox.size, layers: [preview])
        guard let image = previewRenderer.thumbnail(for: preview.id, in: document,
                                                    store: store,
                                                    maxDimension: dimension) else { return nil }
        starterThumbnails[key] = image
        return image
    }

    /// Puts a component in the picture, whether it is one of the app's or one
    /// of yours: the single path a drag from the shelf, a double click on a
    /// tile and the Layer menu row all run.
    ///
    /// A starter the document has not taken yet arrives as the ORIGINAL, with
    /// its named colors and its knobs; everything else, including a second
    /// drop of the same starter, is a copy.
    @discardableResult
    func placeComponent(componentID: UUID, at point: CGPoint) -> UUID? {
        if let starter = StarterComponent(componentID: componentID),
           document?.mainComponent(componentID: componentID) == nil {
            return insertStarterComponent(starter, at: point)
        }
        return insertComponentInstance(componentID: componentID, at: point)
    }

    /// Brings a starter into the open document, centred on a canvas point. One
    /// undo step: the component, the colors it paints from and the knobs it
    /// offers all arrive or none of them do.
    @discardableResult
    func insertStarterComponent(_ kind: StarterComponent, at point: CGPoint) -> UUID? {
        guard starterComponentsEnabled, document != nil else { return nil }
        discardDragPreview()
        var placed: UUID?
        perform {
            placed = $0.insertStarterComponent(kind, at: point,
                                               measure: { TextRasterizer.naturalSize($0) })
        }
        guard let placed else { return nil }
        selectedLibraryItemID = nil
        selectLayer(placed, inGroup: self.document?.parentID(of: placed))
        return placed
    }

    /// The main behind the picked Components tile, or nil when the pick is not
    /// a component.
    var selectedComponentLayer: Layer? {
        guard componentsEnabled, let raw = selectedLibraryItemID,
              let componentID = UUID(uuidString: raw) else { return nil }
        return document?.mainComponent(componentID: componentID)
    }

    /// The Component section's Name field. One name in one place: renaming here
    /// renames the layer, which is what the layers list, the canvas mark and
    /// the tile are all reading.
    func renameComponent(componentID: UUID, to name: String) {
        guard componentsEnabled else { return }
        perform { $0.renameComponent(componentID: componentID, to: name) }
    }

    /// The component id behind the picked Components tile, whatever it is
    /// called and wherever the original sits.
    var selectedComponentID: UUID? { selectedComponentLayer?.componentID }

    /// Whether Layer ▸ Insert Component would do anything: a component is
    /// picked on the shelf, whether it is one of yours or one of the app's.
    var canInsertPickedComponent: Bool {
        selectedComponentID != nil || selectedStarterComponent != nil
    }

    /// Layer ▸ Insert Component, and what a double click on a Components tile
    /// does: puts a copy in the middle of what you are looking at.
    ///
    /// The middle of the VIEW, not the middle of the canvas: on a document
    /// zoomed in on one screen, the middle of the canvas is usually off screen,
    /// and a copy you have to go and find is a copy you did not place.
    func insertPickedComponent() {
        if let componentID = selectedComponentID {
            insertComponentInstance(componentID: componentID, at: visibleCanvasCentre)
        } else if let starter = selectedStarterComponent {
            insertStarterComponent(starter, at: visibleCanvasCentre)
        }
    }

    /// The middle of what the canvas is showing, in document coordinates.
    var visibleCanvasCentre: CGPoint {
        guard let document else { return .zero }
        guard let viewport else {
            return CGPoint(x: document.canvasSize.width / 2, y: document.canvasSize.height / 2)
        }
        let visible = CGRect(x: -viewport.origin.x / viewport.zoom,
                             y: -viewport.origin.y / viewport.zoom,
                             width: viewport.viewSize.width / viewport.zoom,
                             height: viewport.viewSize.height / viewport.zoom)
            .intersection(CGRect(origin: .zero, size: document.canvasSize))
        guard !visible.isNull, visible.width > 0, visible.height > 0 else {
            return CGPoint(x: document.canvasSize.width / 2, y: document.canvasSize.height / 2)
        }
        return CGPoint(x: visible.midX, y: visible.midY)
    }

    /// Places a copy of a component with its centre on a canvas point: the one
    /// path a drag from the shelf, a double click on a tile and the menu row
    /// all run, so all three land the same copy in the same place.
    ///
    /// The copy becomes the selection, because the thing you just placed is the
    /// thing you want to move next, and the shelf lets go of its tile so the
    /// dock talks about the copy rather than the component you took it from.
    @discardableResult
    func insertComponentInstance(componentID: UUID, at point: CGPoint) -> UUID? {
        guard Experiments.shared.componentsEnabled, let document else { return nil }
        guard document.mainComponent(componentID: componentID) != nil else { return nil }
        // Dropping a component onto its own original would make a thing that
        // draws forever, so it is refused out loud rather than quietly ignored.
        // The same answer is what the canvas draws mid-drag, so a drag that is
        // going to be refused says so before the button comes up.
        if document.componentDropTarget(of: componentID, at: point) == .refused {
            raiseComponentCycleNotice()
            return nil
        }
        discardDragPreview()
        var placed: UUID?
        perform { placed = $0.insertComponentInstance(of: componentID, at: point) }
        guard let placed else { return nil }
        selectedLibraryItemID = nil
        selectLayer(placed, inGroup: self.document?.parentID(of: placed))
        return placed
    }

    private func raiseComponentCycleNotice() {
        guard Experiments.shared.componentsEnabled else { return }
        raiseCanvasNotice(.componentCycle)
    }

    /// "Select on Canvas" on a Components tile: answers "where is this thing?"
    /// by selecting the main itself, which hands the dock back to the layer.
    func selectComponentOnCanvas(componentID: UUID) {
        guard let main = document?.mainComponent(componentID: componentID) else { return }
        selectLayer(main.id, inGroup: document?.parentID(of: main.id))
    }

    // MARK: - Color styles (Next flag `next-styles`)

    /// Whether colors can be saved under a name at all.
    var colorStylesEnabled: Bool { Experiments.shared.colorStylesEnabled }

    /// `next-color-picker`: whether every color row opens the app's designed
    /// picker rather than the one it shipped with (and, on a few rows, the
    /// system color panel).
    var designedColorPickerEnabled: Bool { Experiments.shared.designedColorPickerEnabled }

    /// Which color well has its picker open, by the key the well gives itself
    /// ("selection.fill", "shadow", "backdrop"). Nil means none.
    ///
    /// One field rather than a flag inside each well, for two reasons: two
    /// pickers can never be open at once, and a walk can open one from outside
    /// the dock, which the pointer cannot reach.
    var openColorWell: String?

    /// The binding a color well hands its popover.
    /// The same well opened or shut by the swatch that owns it, which is what
    /// clicking a toolbar swatch twice means.
    func toggleColorWell(_ key: String) {
        openColorWell = openColorWell == key ? nil : key
    }

    func colorWellBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { [weak self] in self?.openColorWell == key },
                set: { [weak self] shown in self?.openColorWell = shown ? key : nil })
    }

    /// Saves a color the picker is holding under a name, whatever it came from.
    ///
    /// This is the picker's own Save style, which differs from the color row's
    /// in one way: the row saves what the picked layers are painted in and
    /// points them at it, while this saves a color that may be nothing's yet,
    /// so it only puts it on the shelf. Both land in the Library the same way,
    /// and both show it, because a style you cannot see is a button that
    /// appears to do nothing.
    @discardableResult
    func saveColorStyle(hex: String, name: String? = nil, slot: ColorSlot? = nil) -> UUID? {
        saveColorStyle(paint: Paint(hex: hex), name: name, slot: slot)
    }

    /// The same, with the whole paint the picker is holding, so a gradient
    /// somebody has just aimed is kept aimed rather than saved as the one stop
    /// they happened to be editing.
    @discardableResult
    func saveColorStyle(paint: Paint, name: String? = nil, slot: ColorSlot? = nil) -> UUID? {
        guard colorStylesEnabled else { return nil }
        discardDragPreview()
        var saved: UUID?
        perform { saved = $0.addColorStyle(name: name, paint: paint,
                                           roles: slot.map { [$0.styleRole] }) }
        guard let styleID = saved else { return nil }
        showColorStyleShelf()
        pendingLibraryTileID = styleID.uuidString
        return styleID
    }

    /// The color row that is asking for a name right now, raised by its Save as
    /// Style button and lowered when the name lands, when Escape drops it, or
    /// when the selection moves on. It lives here rather than inside the row so
    /// only one field is ever open, and so a walk can open one.
    var colorStyleNaming: ColorStyleNamingRequest?

    /// Save as Style: opens the name field under that color row. The row it
    /// belongs to is the one for that slot, whatever is picked, because only
    /// one field is open at a time and the selection is what it is about.
    func beginNamingColorStyle(slot: ColorSlot) {
        guard colorStylesEnabled else { return }
        colorStyleNaming = ColorStyleNamingRequest(slot: slot)
    }

    /// Escape, or the name landing: the field closes.
    func endNamingColorStyle() {
        colorStyleNaming = nil
    }

    /// Every style in the open document, as shelf items.
    var colorStyleEntries: [LibraryEntry] {
        guard colorStylesEnabled else { return [] }
        return document?.colorStyleLibraryEntries ?? []
    }

    /// Every style in the open document, in the order the shelf lists them.
    var colorStyles: [ColorStyle] {
        guard colorStylesEnabled else { return [] }
        return document?.colorStyles ?? []
    }

    /// The styles ONE color row offers: only the ones meant for the part it
    /// paints, so a color kept for hairlines is not on the menu as something
    /// to fill a box with.
    func colorStyles(for slot: ColorSlot) -> [ColorStyle] {
        guard colorStylesEnabled else { return [] }
        return document?.colorStyles(for: slot) ?? []
    }

    /// What a saved color is offered for right now, including the answer
    /// worked out for one saved before anybody said.
    func colorStyleRoles(styleID: UUID) -> [ColorStyleRole] {
        document?.effectiveColorStyleRoles(id: styleID) ?? []
    }

    /// The Style section's "Use it for" checkboxes: which parts of a layer
    /// this saved color turns up on. Ticking nothing is refused, because a
    /// color offered nowhere is a shelf tile that cannot be used.
    func setColorStyleRoles(styleID: UUID, roles: [ColorStyleRole]) {
        guard colorStylesEnabled else { return }
        perform { $0.setColorStyleRoles(id: styleID, roles: roles) }
    }

    /// The style behind the picked Styles tile, or nil when the pick is not a
    /// style.
    var selectedColorStyle: ColorStyle? {
        guard colorStylesEnabled, let raw = selectedLibraryItemID,
              let styleID = UUID(uuidString: raw) else { return nil }
        return document?.colorStyle(id: styleID)
    }

    /// The style painting one of a layer's colors, nil when that color is the
    /// layer's own.
    func colorStyle(layerID: UUID, slot: ColorSlot) -> ColorStyle? {
        guard colorStylesEnabled,
              let styleID = document?.layer(id: layerID)?.colorStyleID(for: slot) else { return nil }
        return document?.colorStyle(id: styleID)
    }

    /// The name the Save as Style field opens on: one nobody is using yet.
    var suggestedColorStyleName: String {
        document?.freshColorStyleName() ?? PhotonzDocument.colorStyleNameBase
    }

    /// The name the field opens on for ONE row: a saved ramp is offered
    /// "Gradient" rather than "Color 4", because a shelf where half the tiles
    /// called Color are gradients is a shelf nobody reads.
    func suggestedColorStyleName(slot: ColorSlot) -> String {
        let paint = colorStyleSelection(slot: slot).savablePaint ?? Paint(hex: "#000000")
        let base = PhotonzDocument.colorStyleNameBase(for: paint)
        return document?.freshColorStyleName(base: base) ?? base
    }

    /// The layers a color row speaks for: the whole multi-selection when there
    /// is one, else the one selected layer — the same set every other
    /// whole-selection command acts on. In draw order, so the row reads the
    /// same way twice running and one undo step lands the same way every time.
    private var colorStyleTargetIDs: [UUID] {
        let picked = actionableLayerIDs
        guard !picked.isEmpty, let document else { return [] }
        return document.allLayers.map(\.id).filter { picked.contains($0) }
    }

    /// What the Effects and Shadow rows show: the picked layers that can be
    /// restyled, the look each of them is wearing right now, and whether they
    /// agree. One layer picked or twenty, this is the same reading, which is
    /// what lets one pull on Corner Radius round every button you picked.
    ///
    /// Preview-aware, so a slider mid-drag reads what is on the canvas rather
    /// than snapping back to what is on disk between frames.
    var layerStyleSelection: LayerStyleSelection {
        guard let document else { return LayerStyleSelection(members: [], selectionCount: 0) }
        return document.layerStyleSelection(layerIDs: colorStyleTargetIDs) { layer in
            self.previewedStyle(of: layer.id) ?? layer.style
        }
    }

    /// What the type rows show: the picked TEXT layers and what they are set
    /// in. One label picked or ten, this is the same reading, which is what
    /// lets three labels be made 14pt in one go instead of three.
    var textSelection: TextLayerSelection {
        guard let document else { return TextLayerSelection(members: [], selectionCount: 0) }
        return document.textSelection(layerIDs: colorStyleTargetIDs)
    }

    /// The same for the shape rows: the picked shapes, the settings they all
    /// have, and what those settings read across them.
    var shapeSelection: ShapeSelection {
        guard let document else { return ShapeSelection(members: [], selectionCount: 0) }
        return document.shapeSelection(layerIDs: colorStyleTargetIDs)
    }

    /// What the ONE Corner Radius row shows: how round each picked layer is
    /// right now, whichever way it rounds. A rectangle curves the outline it
    /// draws and everything else has its corners masked off, and this row
    /// speaks for both, so one pull can round a screenshot and the box drawn on
    /// top of it together.
    var cornerRadiusSelection: CornerRadiusSelection {
        guard let document else { return CornerRadiusSelection(members: [], selectionCount: 0) }
        return document.cornerRadiusSelection(layerIDs: colorStyleTargetIDs)
    }

    /// Live drag on that row: rounds every picked layer without recording an
    /// undo step, each of them the way it rounds.
    func previewCornerRadius(ids: [UUID], _ radius: CGFloat) {
        guard !ids.isEmpty, var doc = document else { return }
        // This row does not go through the layer-style preview, so anything a
        // previous drag left there would be read back as the current look.
        stylePreview = nil
        discardDragPreview()
        doc.setCornerRadius(layerIDs: ids, to: radius)
        submit(doc)
    }

    /// Letting go of it: ONE undo step, however many layers the pull reached,
    /// plus the corners the next rectangle you draw starts with.
    func commitCornerRadius(ids: [UUID], _ radius: CGFloat) {
        guard !ids.isEmpty, let doc = document else { return }
        stylePreview = nil
        discardDragPreview()
        perform { $0.setCornerRadius(layerIDs: ids, to: radius) }
        if ids.contains(where: { doc.layer(id: $0)?.annotation?.shape == .rectangle }) {
            annotationStyles.setCornerRadius(radius, forShape: .rectangle)
            saveAnnotationStyles()
        }
        rememberStyleDefault(of: ids)
    }

    /// Whether anything picked can be restyled at all, which is what decides
    /// whether the Effects and Shadow sections are in the panel. A locked layer
    /// is not restylable, so a selection of nothing but locked layers brings no
    /// sections rather than rows of dead sliders — the same call the Color rows
    /// make.
    var hasRestylableSelection: Bool {
        guard let document else { return false }
        return actionableLayerIDs.contains { document.layer(id: $0)?.isLocked == false }
    }

    /// The Shadow switch: turns a shadow on for every picked layer that has
    /// none, or off for all of them, in one step. On means on EVERYWHERE, so
    /// three boxes where one is shadowed read off and one click shadows the
    /// other two rather than un-shadowing the first.
    func setSelectionShadowEnabled(_ on: Bool) {
        let ids = layerStyleSelection.layerIDs
        guard !ids.isEmpty else { return }
        setLayerStyle(ids: ids) { style in
            if on {
                // A layer that already has one keeps the shadow it tuned.
                if style.shadow == nil { style.shadow = ShadowStyle() }
            } else {
                style.shadow = nil
            }
        }
    }

    /// What one color row shows: the picked layers that have a color in this
    /// slot, what they are painted, and the style painting them when they all
    /// wear one. One layer picked or twenty, this is the same reading, which is
    /// what lets the Color section be the ONE place a color lives.
    ///
    /// Not gated on saved styles: a color still has to be readable and
    /// settable with `next-styles` off. What that flag takes away is the styles
    /// button beside the color, and `ColorStyleControl` hides itself.
    func colorStyleSelection(slot: ColorSlot) -> ColorStyleSelection {
        guard let document else {
            return ColorStyleSelection(slot: slot, members: [], selectionCount: 0)
        }
        return document.colorStyleSelection(layerIDs: colorStyleTargetIDs, slot: slot)
    }

    /// The slots the selection actually has a color in. What a style can be
    /// saved from or applied to.
    var colorStyleSlots: [ColorSlot] {
        guard let document else { return [] }
        return document.colorStyleSlots(layerIDs: colorStyleTargetIDs)
    }

    /// The rows the Color section shows, in inspector order: every slot the
    /// picked layers HAVE, whether or not there is a color in it right now. A
    /// box with its fill switched off keeps its Fill row, because that row is
    /// the way back to a fill.
    var colorRowSlots: [ColorSlot] {
        guard let document else { return [] }
        return document.colorRowSlots(layerIDs: colorStyleTargetIDs)
    }

    /// What the checkbox on a color row reads: offered only where the color can
    /// be absent at all, and on only when every layer it speaks for has one.
    func colorSwitch(slot: ColorSlot) -> ColorSwitch {
        guard let document else { return ColorSwitch(slot: slot, layerIDs: [], onCount: 0) }
        return document.colorSwitch(layerIDs: colorStyleTargetIDs, slot: slot)
    }

    /// The checkbox on a color row: switches a box's inside, or a frame's
    /// surface, on or off across everything picked, in one step.
    func setColorEnabled(slot: ColorSlot, on: Bool) {
        guard document != nil else { return }
        let targets = colorSwitch(slot: slot).layerIDs
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { _ = $0.setColorEnabled(layerIDs: targets, slot: slot, on: on) }
        // Switching a box's inside off here arms the tool with no inside, so
        // the next box comes out an outline like the one just emptied. Same
        // rule as picking a colour on the row above it.
        armToolsFromSelection(slot: slot, targets: targets)
    }

    /// How many layers are picked, which is what the whole-selection Color
    /// section says out loud before anything is changed.
    var colorStyleSelectionCount: Int { colorStyleTargetIDs.count }

    /// "Save as Style" on a color row: takes the name typed in the little
    /// field, saves the color the picked layers share under it, and points
    /// every one of them at it. Nil when they do not share one.
    ///
    /// It also **shows the Library on the Styles shelf**, because a style you
    /// cannot see is a button that appears to do nothing. The layers stay
    /// selected, so the row you saved from is right there saying which style it
    /// is now wearing.
    @discardableResult
    func saveColorStyle(slot: ColorSlot, name: String? = nil) -> UUID? {
        guard colorStylesEnabled else { return nil }
        colorStyleNaming = nil
        let targets = colorStyleTargetIDs
        guard !targets.isEmpty else { return nil }
        discardDragPreview()
        var saved: UUID?
        perform { saved = $0.saveColorStyle(from: targets, slot: slot, name: name) }
        guard let styleID = saved else { return nil }
        showColorStyleShelf()
        // The saved color is one tile among the ones already kept, so the shelf
        // scrolls to it for the same reason a new component's tile does.
        pendingLibraryTileID = styleID.uuidString
        return styleID
    }

    /// Puts the Library on screen with the Styles shelf showing, which is
    /// where a saved color is renamed, recolored, or told which parts of a
    /// layer to turn up on. Saving does this, and so does a color row whose
    /// list is empty because the saved colors are all for other parts.
    func showColorStyleShelf() {
        setLibraryVisible(true)
        UserDefaults.standard.set(LibraryScope.styles.rawValue, forKey: LibraryPanel.scopeKey)
    }

    /// Points every picked layer's color at a style, which paints all of them
    /// in ONE step: pick three boxes, choose Accent once, undo once.
    func useColorStyle(slot: ColorSlot, styleID: UUID) {
        guard colorStylesEnabled else { return }
        // Only a color meant for this part. The menu already offers no other,
        // so this is the belt: a walk or a stale menu cannot put a color kept
        // for hairlines on the inside of a box.
        guard document?.colorStyles(for: slot).contains(where: { $0.id == styleID }) == true
        else { return }
        let targets = colorStyleSelection(slot: slot).layerIDs
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { _ = $0.bindColorStyle(layerIDs: targets, slot: slot, styleID: styleID) }
    }

    /// "Unlink": every picked color stays exactly as it is, it just becomes its
    /// own layer's again, in one step.
    func unlinkColorStyle(slot: ColorSlot) {
        guard colorStylesEnabled else { return }
        let targets = colorStyleSelection(slot: slot).layerIDs
        guard !targets.isEmpty else { return }
        perform(reportingLinkBreaks: false) { $0.unbindColorStyle(layerIDs: targets, slot: slot) }
    }

    /// The color well on a whole-selection row: paints every picked layer that
    /// has this kind of color the one color chosen, in ONE step. Pick three
    /// boxes, choose a blue once, undo once.
    ///
    /// Layers wearing a style in that slot are taken off it, which the row says
    /// in words before the color is picked.
    func setSelectionColor(slot: ColorSlot, hex: String) {
        let targets = colorStyleSelection(slot: slot).layerIDs
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { _ = $0.setColorHex(layerIDs: targets, slot: slot, hex: hex) }
        armToolsFromSelection(slot: slot, targets: targets)
        recordRecentColor(hex: hex)
    }

    /// Paints a slot across the selection with a whole paint — flat colour or
    /// gradient. The gradient counterpart of `setSelectionColor`, and the only
    /// way a gradient reaches the document.
    func setSelectionPaint(slot: ColorSlot, paint: Paint) {
        let targets = colorStyleSelection(slot: slot).layerIDs
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { _ = $0.setPaint(layerIDs: targets, slot: slot, paint: paint) }
        armToolsFromSelection(slot: slot, targets: targets)
        // The recents row is a row of colours, so a gradient leaves its flat
        // colour there rather than nothing.
        recordRecentColor(hex: paint.hex)
    }

    /// Painting a shape from the panel arms the tool that draws it, so the next
    /// shape of that kind comes out the colour just chosen — the same thing the
    /// toolbar swatch has always done, and the same thing Thickness, Corner
    /// Radius and the Effects sliders already do from this panel. Colour was
    /// the one field where picking in the two places meant two different
    /// things.
    ///
    /// Every kind of shape the pick reached is armed for itself, so painting a
    /// box and an arrow blue leaves both tools blue and the ellipse tool alone.
    /// A kind whose shapes end up disagreeing arms nothing rather than being
    /// guessed at. Read AFTER the change, so it is what the shapes are wearing
    /// now rather than what was aimed at them.
    private func armToolsFromSelection(slot: ColorSlot, targets: [UUID]) {
        guard let document else { return }
        let arming = document.toolArming(layerIDs: targets, slot: slot)
        if !arming.isEmpty {
            for entry in arming {
                annotationStyles.arm(entry.paint, slot: slot, forShape: entry.shape)
            }
            saveAnnotationStyles()
        }
        // A ring is styling laid over a layer rather than part of the shape, so
        // it rides along with the rest of a shape's remembered look, exactly
        // the way pulling its width in the Effects section already does.
        if slot == .border { rememberStyleDefault(of: targets) }
    }

    /// What the picked layers are painted with in a slot, when they agree.
    func selectionPaint(slot: ColorSlot) -> Paint? {
        document?.sharedPaint(layerIDs: colorStyleTargetIDs, slot: slot)
    }

    /// A colour drag in flight: the paint being pushed at the canvas frame by
    /// frame, held out of history until the drag is let go of.
    ///
    /// Deliberately NOT what `selectionPaint` reads. That reading is what the
    /// picker is opened on, and a picker reopened on its own live frames would
    /// hand the ramp's selection back to the first stop halfway through a pull.
    /// The document stays the opening colour for the whole gesture; only the
    /// canvas and the row's chip follow.
    private var paintPreview: (slot: ColorSlot, ids: [UUID], paint: Paint)?

    /// What a colour row's chip shows: the paint in flight while a drag is
    /// happening, the document's otherwise. Without it the little swatch under
    /// the picker would sit on the old colour for a whole pull and then jump on
    /// release, while the canvas beside it had been following all along.
    func previewedPaint(slot: ColorSlot) -> Paint? {
        if let preview = paintPreview, preview.slot == slot { return preview.paint }
        return selectionPaint(slot: slot)
    }

    /// One frame of a colour drag: paints the slot across everything picked and
    /// renders it, recording nothing. Same shape as `previewLayerStyle`, and
    /// for the same reason — a live tick per frame in history would make one
    /// pull a hundred undo steps and the recents row a transcript of it.
    func previewSelectionPaint(slot: ColorSlot, paint: Paint) {
        let targets = colorStyleSelection(slot: slot).layerIDs
        guard !targets.isEmpty, var doc = document else { return }
        // A drag that has moved to a different row or a different selection is
        // a new gesture: nothing of the old one carries over, and a held drag
        // sprite would be showing the old colour.
        if paintPreview?.slot != slot || paintPreview?.ids != targets {
            stylePreview = nil
            discardDragPreview()
        }
        paintPreview = (slot, targets, paint)
        _ = doc.setPaint(layerIDs: targets, slot: slot, paint: paint)
        submit(doc)
    }

    /// Puts the canvas back on the document if a colour drag is somehow still
    /// in flight — the picker was dismissed with the pointer down, so the
    /// release that would have committed never came. Without this the canvas
    /// would keep showing a colour the document does not have until the next
    /// edit. A no-op the rest of the time, which is nearly always.
    func discardPickerPreview() {
        guard paintPreview != nil || stylePreview != nil else { return }
        paintPreview = nil
        stylePreview = nil
        rerender()
    }

    /// Letting go of a colour drag: ONE undo step from the colour the slot had
    /// before the drag started to the one it ended on, however many layers it
    /// reached, and ONE entry in the recents row for the whole gesture.
    func commitSelectionPaint(slot: ColorSlot, paint: Paint) {
        paintPreview = nil
        setSelectionPaint(slot: slot, paint: paint)
    }

    /// Repaints a style and everything wearing it, as one undo step.
    func setColorStyleHex(styleID: UUID, hex: String) {
        setColorStylePaint(styleID: styleID, paint: Paint(hex: hex))
    }

    /// Repaints a style with a whole paint — this is how a saved gradient is
    /// edited — and everything wearing it follows, as one undo step.
    func setColorStylePaint(styleID: UUID, paint: Paint) {
        guard colorStylesEnabled else { return }
        discardDragPreview()
        perform { _ = $0.setColorStylePaint(styleID: styleID, paint: paint) }
        // The recents row is a row of colours, so a ramp leaves its flat colour
        // there rather than nothing.
        recordRecentColor(hex: paint.hex)
    }

    /// The Style section's Name field. One name in one place: the shelf tile
    /// and every row wearing it read the same string.
    func renameColorStyle(styleID: UUID, to name: String) {
        guard colorStylesEnabled else { return }
        perform { $0.renameColorStyle(id: styleID, to: name) }
    }

    /// Takes a style off the shelf. Nothing is repainted: every layer keeps the
    /// color it is wearing and simply owns it again.
    func deleteColorStyle(styleID: UUID) {
        guard colorStylesEnabled else { return }
        perform { $0.deleteColorStyle(id: styleID) }
        if selectedLibraryItemID == styleID.uuidString { selectedLibraryItemID = nil }
    }

    /// How many of the document's colors this style paints.
    func colorStyleUsageCount(styleID: UUID) -> Int {
        document?.colorStyleUsageCount(id: styleID) ?? 0
    }

    /// "Select what uses this": the layers wearing a style become the
    /// selection, which is how the shelf answers "where is this thing?".
    func selectLayersUsingColorStyle(styleID: UUID) {
        guard let ids = document?.layersUsingColorStyle(id: styleID), !ids.isEmpty else { return }
        selectLayers(Set(ids))
    }

    // MARK: - Component knobs and overrides (Next flag `next-components`)

    /// The knobs an original exposes, in the order it lists them.
    func componentProperties(of componentID: UUID) -> [ComponentProperty] {
        guard componentsEnabled else { return [] }
        return document?.componentProperties(of: componentID) ?? []
    }

    /// What the Add Property menu lists: the layers inside the original and the
    /// knob each one could become.
    func componentPropertyCandidates(componentID: UUID) -> [ComponentPropertyCandidate] {
        guard componentsEnabled else { return [] }
        return document?.componentPropertyCandidates(componentID: componentID) ?? []
    }

    /// Exposes one layer inside an original as a knob.
    /// A knob the author just added and has not named yet, so its name field
    /// can take the focus with its text selected. Same New Folder idiom the
    /// component's own Name field follows: a knob lands with a name that says
    /// what it does ("Wording"), and saying what it IS is one word of typing.
    var componentPropertyAwaitingName: UUID?

    @discardableResult
    func addComponentProperty(componentID: UUID, target: UUID, kind: ComponentPropertyKind) -> UUID? {
        guard componentsEnabled else { return nil }
        var added: UUID?
        perform { added = $0.addComponentProperty(componentID: componentID, target: target, kind: kind) }
        componentPropertyAwaitingName = added
        return added
    }

    func removeComponentProperty(componentID: UUID, propertyID: UUID) {
        guard componentsEnabled else { return }
        perform { $0.removeComponentProperty(componentID: componentID, propertyID: propertyID) }
    }

    func renameComponentProperty(componentID: UUID, propertyID: UUID, to name: String) {
        guard componentsEnabled else { return }
        perform { $0.renameComponentProperty(componentID: componentID, propertyID: propertyID, to: name) }
    }

    /// The shapes a choice can land on: exactly what the original holds.
    func componentVariantOptions(componentID: UUID, propertyID: UUID) -> [Layer] {
        guard componentsEnabled else { return [] }
        return document?.componentVariantOptions(componentID: componentID, propertyID: propertyID) ?? []
    }

    /// The same shapes with labels a person can tell apart, which is what the
    /// choice menu lists.
    func componentVariantOptionLabels(componentID: UUID,
                                      propertyID: UUID) -> [(id: UUID, label: String)] {
        guard componentsEnabled else { return [] }
        return document?.componentVariantOptionLabels(componentID: componentID,
                                                      propertyID: propertyID) ?? []
    }

    /// What a copy shows for a knob: its own answer, or the original's.
    func instanceValue(instance: UUID, property: UUID) -> ComponentPropertyValue? {
        document?.instanceValue(instance: instance, property: property)
    }

    /// Which knobs this copy has answered for itself, which is what puts the
    /// revert control on a row.
    func instanceOverrides(instance: UUID) -> Set<UUID> {
        document?.instanceOverrides(instance: instance) ?? []
    }

    /// Sets one knob on one copy.
    ///
    /// It is performed WITHOUT the "copies followed" pill: that pill exists to
    /// say how far an edit to an original reached, and this edit reached one
    /// copy, the one whose panel the person is typing into and looking at.
    func setInstanceOverride(instance: UUID, property: UUID, value: ComponentPropertyValue) {
        guard componentsEnabled else { return }
        perform(announcing: false) {
            $0.setInstanceOverride(instance: instance, property: property, value: value)
        }
    }

    /// Puts one knob back to following the original.
    func clearInstanceOverride(instance: UUID, property: UUID) {
        guard componentsEnabled else { return }
        perform(announcing: false) { $0.clearInstanceOverride(instance: instance, property: property) }
    }

    /// Which parts of a copy's look are its own rather than the original's,
    /// named as their controls are, in the order they sit in the dock.
    func instanceStyleOverrideLabels(instance: UUID) -> [String] {
        guard componentsEnabled else { return [] }
        return document?.instanceStyleOverrideLabels(instance: instance) ?? []
    }

    /// Whether one part of a copy's look is its own, which is what puts the way
    /// back on an Effects row.
    func isInstanceStyleOwn(instance: UUID, field: LayerStyleField) -> Bool {
        guard componentsEnabled else { return false }
        return document?.isInstanceStyleOwn(instance: instance, field: field) ?? false
    }

    /// Puts one part of a copy's look back to following the original.
    ///
    /// Like setting a knob, it is performed without the "copies followed" pill:
    /// the change lands on the one copy whose panel the person is looking at.
    func clearInstanceStyleOverride(instance: UUID, field: LayerStyleField) {
        guard componentsEnabled else { return }
        stylePreview = nil
        discardDragPreview()
        perform(announcing: false) { $0.clearInstanceStyleOverride(instance: instance, field: field) }
    }

    /// Puts a copy's whole look back to the original's.
    func clearInstanceStyleOverrides(instance: UUID) {
        guard componentsEnabled else { return }
        stylePreview = nil
        discardDragPreview()
        perform(announcing: false) { $0.clearInstanceStyleOverrides(instance: instance) }
    }

    /// Whether Layer ▸ Detach Instance would do anything: one unlocked copy is
    /// selected.
    var canDetachInstance: Bool {
        guard componentsEnabled, let document else { return false }
        return document.canDetachInstance(ids: actionableLayerIDs)
    }

    /// Layer ▸ Detach Instance (⌥⌘B): turns the selected copy into ordinary
    /// layers that no longer follow the original.
    ///
    /// It says so out loud, because nothing on screen changes when it runs: the
    /// picture the instant after is the picture the instant before, and a
    /// command that looks like it did nothing is a command people press twice.
    func detachInstance() {
        guard canDetachInstance, let id = actionableLayerIDs.first else { return }
        let name = document?.layer(id: id)?.instanceOf
            .flatMap { document?.mainComponent(componentID: $0)?.name }
        discardDragPreview()
        var detached = false
        perform(announcing: false) { detached = $0.detachInstance(id: id) }
        guard detached else { return }
        selectLayer(id, inGroup: document?.parentID(of: id))
        raiseCanvasNotice(.componentDetached(component: name))
    }

    /// Whether Layer ▸ Select Original would do anything: the selection is a
    /// copy whose original is still in the document.
    var canSelectComponentOriginal: Bool { selectedInstanceOriginal != nil }

    /// The component the selected copy follows, when there is exactly one copy
    /// selected and its original is still here.
    private var selectedInstanceOriginal: UUID? {
        guard componentsEnabled, let document, actionableLayerIDs.count == 1,
              let id = actionableLayerIDs.first,
              let componentID = document.layer(id: id)?.instanceOf,
              document.mainComponent(componentID: componentID) != nil else { return nil }
        return componentID
    }

    /// Exposes the first piece of the selected original that can take this
    /// kind of knob. The Add menu lives in the dock, which a scripted playtest
    /// cannot reach with the pointer, so a walk asks for it here.
    func exposeFirstProperty(kind: ComponentPropertyKind) {
        guard componentsEnabled, let id = actionableLayerIDs.first,
              let componentID = document?.layer(id: id)?.componentID,
              let candidate = componentPropertyCandidates(componentID: componentID)
                  .first(where: { $0.kinds.contains(kind) }) else { return }
        addComponentProperty(componentID: componentID, target: candidate.layerID, kind: kind)
    }

    /// Moves the selected copy's first choice knob on to its next option, the
    /// same edit picking the next row of that knob's menu makes. Scripted
    /// playtests only: a walk cannot open a menu inside the dock.
    func cycleInstanceChoice() {
        guard componentsEnabled, let id = actionableLayerIDs.first,
              let componentID = document?.layer(id: id)?.instanceOf,
              let property = componentProperties(of: componentID).first(where: { $0.kind == .variant })
        else { return }
        let options = componentVariantOptions(componentID: componentID, propertyID: property.id)
        guard !options.isEmpty else { return }
        let current = instanceValue(instance: id, property: property.id)?.optionValue
        let index = options.firstIndex { $0.id == current } ?? 0
        let next = options[(index + 1) % options.count]
        setInstanceOverride(instance: id, property: property.id, value: .variant(next.id))
    }

    /// Whether Layer ▸ Make Alternatives would do anything: the selection can
    /// become a set of alternatives with a knob that picks between them.
    var canMakeChoice: Bool {
        guard componentsEnabled, Experiments.shared.layerGroupsEnabled, let document else { return false }
        return document.canMakeChoice(ids: actionableLayerIDs)
    }

    /// Layer ▸ Make Alternatives: the selected shapes become a group of
    /// alternatives inside the original, and the original grows the knob every
    /// copy uses to pick between them. One undo step.
    ///
    /// It says so out loud, because settling the choice HIDES all but one of
    /// the shapes that were just selected: without a word on screen the command
    /// reads as having deleted one of them.
    func makeChoice() {
        guard canMakeChoice else { return }
        let ids = actionableLayerIDs
        discardDragPreview()
        var made: PhotonzDocument.MadeChoice?
        perform(announcing: false) { made = $0.makeChoice(ids: ids) }
        guard let made, let document else { return }
        // The new group is selected, the same way ⌘G leaves the group it made
        // selected: the next thing you do is almost always to it.
        groupContextID = document.parentID(of: made.group)
        selectedLayerID = made.group
        setSelection(nil, captureLayers: false)
        let knob = document.componentHome(of: made.group)
            .flatMap { document.componentProperty(componentID: $0, propertyID: made.property) }?.name
        raiseCanvasNotice(.componentChoiceMade(options: made.options, knob: knob ?? "the choice knob"))
    }

    /// Layer ▸ Select Original: jumps from a copy to the thing every copy
    /// follows, which is where a change to all of them is made.
    func selectComponentOriginal() {
        guard let componentID = selectedInstanceOriginal else { return }
        selectComponentOnCanvas(componentID: componentID)
    }

    // MARK: - Frames (Next flag `next-frames`)

    /// The size the next frame gets when it is dropped with a plain click, and
    /// what the New Frame dialog opens on: whatever you made last, so building
    /// a second phone screen costs one click.
    @ObservationIgnored
    @AppStorage("frames.lastSize") private var lastFrameSizeRaw = ""

    var lastFrameSize: CGSize {
        get {
            let parts = lastFrameSizeRaw.split(separator: "x").compactMap { Double($0) }
            guard parts.count == 2 else { return FramePreset.default.size }
            return FramePreset.normalized(CGSize(width: parts[0], height: parts[1]))
        }
        set {
            let size = FramePreset.normalized(newValue)
            lastFrameSizeRaw = "\(Int(size.width))x\(Int(size.height))"
        }
    }

    /// Whether the frame rows and the frame tool exist at all.
    var framesEnabled: Bool { Experiments.shared.framesEnabled }

    /// Whether Layer ▸ Frame Selection would do anything: one unlocked layer
    /// is enough, because putting a single thing on a screen of its own is a
    /// normal way to start.
    var canFrameSelection: Bool {
        guard framesEnabled, let document else { return false }
        return document.canFrameSelection(ids: actionableLayerIDs)
    }

    /// The frame Export would offer as its scope: the selected frame, or the
    /// frame whatever is selected lives in. Nil when the selection is nowhere
    /// near one.
    var selectedFrameID: UUID? {
        guard let document, let id = selectedLayerID else { return nil }
        return document.frameID(containing: id)
    }

    /// Every frame in the document, outermost first — the export scope menu
    /// and the frame label chrome both read this.
    var documentFrames: [Layer] {
        document?.frames ?? []
    }

    /// A frame drawn on the canvas, or dropped at a chosen size. One undo
    /// step, then the frame is selected with the Select tool in hand, the way
    /// every other created layer lands.
    @discardableResult
    func addFrame(at origin: CGPoint, size: CGSize, name: String? = nil) -> UUID? {
        guard document != nil else { return nil }
        let size = FramePreset.normalized(size)
        var madeID: UUID?
        perform { document in
            madeID = document.addFrame(name: name, origin: origin, size: size).id
        }
        lastFrameSize = size
        if let madeID { finishCreating(madeID) }
        return madeID
    }

    /// The frame tool's drag: a frame the size you drew, or — when the drag
    /// was really a click — one at the size you made last, dropped with its
    /// top left where you clicked.
    func addFrame(from start: CGPoint, to end: CGPoint) {
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        if rect.width < 4 || rect.height < 4 {
            addFrame(at: start, size: lastFrameSize)
        } else {
            addFrame(at: rect.origin, size: rect.size)
        }
    }

    /// Layer ▸ New Frame…: a frame at a chosen size, placed where the eye
    /// already is. The first one lands in the middle of what you are looking
    /// at; every one after that lines up to the right of the frames already on
    /// the canvas, which is how a document ends up reading as a row of screens
    /// rather than a stack of them.
    func addFrameInView(size: CGSize) {
        guard let document else { return }
        let size = FramePreset.normalized(size)
        let canvas = CGRect(origin: .zero, size: document.canvasSize)
        var visible = canvas
        if let viewport {
            visible = CGRect(x: -viewport.origin.x / viewport.zoom,
                             y: -viewport.origin.y / viewport.zoom,
                             width: viewport.viewSize.width / viewport.zoom,
                             height: viewport.viewSize.height / viewport.zoom)
                .intersection(canvas)
        }
        addFrame(at: document.placementForNewFrame(size: size, visible: visible), size: size)
    }

    /// Layer ▸ Frame Selection: puts a frame around what is selected, fitted
    /// to it exactly, in one undo step.
    func frameSelection() {
        guard canFrameSelection else { return }
        let ids = actionableLayerIDs
        discardDragPreview()
        var madeID: UUID?
        perform { document in
            madeID = document.frameSelection(ids: ids)?.id
        }
        groupContextID = madeID.flatMap { document?.parentID(of: $0) }
        selectedLayerID = madeID
        setSelection(nil, captureLayers: false)
    }

    /// The frame inspector's size menu and its typed width and height. The
    /// layers inside stay where they are: a frame's size says where it clips.
    func setFrameSize(id: UUID, size: CGSize) {
        guard document?.layer(id: id)?.isFrame == true else { return }
        discardDragPreview()
        perform { $0.setFrameSize(id: id, size: size) }
        lastFrameSize = size
    }

    /// Whether a frame hides what hangs off its edge.
    func setFrameClips(id: UUID, _ clips: Bool) {
        guard document?.layer(id: id)?.isFrame == true else { return }
        perform { $0.setFrameClips(id: id, clips) }
    }

    /// The surface a frame paints behind its contents; nil is a frame you see
    /// the canvas through.
    func setFrameBackground(id: UUID, hex: String?) {
        guard document?.layer(id: id)?.isFrame == true else { return }
        perform { $0.setFrameBackground(id: id, hex: hex) }
        if let hex { recordRecentColor(hex: hex) }
    }

    // MARK: - Where the pieces sit when something is resized

    /// The group the selected layer sits in, or nil when it sits loose on the
    /// canvas. What the Layout section asks before it offers a row about "the
    /// container", since without one there is nothing to line up against.
    var containerOfSelection: Layer? {
        guard multiSelectedLayerIDs.isEmpty, let id = selectedLayerID else { return nil }
        return document?.containingGroup(of: id)
    }

    /// What a group tells everything inside it to do when it is resized.
    func setContentPlacement(id: UUID, horizontal: HorizontalPlacement?) {
        guard document?.layer(id: id)?.isGroup == true else { return }
        perform { $0.setContentPlacement(id: id, horizontal: horizontal) }
    }

    func setContentPlacement(id: UUID, vertical: VerticalPlacement?) {
        guard document?.layer(id: id)?.isGroup == true else { return }
        perform { $0.setContentPlacement(id: id, vertical: vertical) }
    }

    /// What ONE piece does, overriding the group it sits in. Nil hands the
    /// axis back to the group.
    func setPlacement(id: UUID, horizontal: HorizontalPlacement?) {
        guard document?.layer(id: id) != nil else { return }
        perform { $0.setPlacement(id: id, horizontal: horizontal) }
    }

    func setPlacement(id: UUID, vertical: VerticalPlacement?) {
        guard document?.layer(id: id) != nil else { return }
        perform { $0.setPlacement(id: id, vertical: vertical) }
    }

    /// A canvas click that resolved through the group walk: the layer it
    /// picked and the group it picked it inside.
    func selectLayer(_ id: UUID?, inGroup context: UUID?) {
        if groupContextID != context { groupContextID = context }
        selectedLayerID = id
        if id == nil, !multiSelectedLayerIDs.isEmpty { multiSelectedLayerIDs = [] }
    }

    /// A ⇧-click on the canvas: adds the layer to the selection, or drops it
    /// when it is already in. The canvas gesture the Layers list has always
    /// had, so picking exactly two things to group is two clicks instead of a
    /// sweep that takes in whatever else was nearby.
    ///
    /// The caller has already resolved the click at the level you are on
    /// (`PhotonzDocument.extendTarget`), so this runs the same toggle a
    /// ⌘-click on a row runs, anchor and all: carry on in the list and it
    /// picks up where the canvas left off.
    func extendSelection(toLayer id: UUID) {
        clickRow(id, .toggle, in: [])
        // Any rubber band on screen described the OLD selection. It does not
        // describe this one, so it comes down rather than lying. A pixel
        // region belongs to the region tools, not to layers: that one stays.
        if selection != nil, !selectionTargetsPixels { setSelection(nil, captureLayers: false) }
    }

    /// A ⇧-sweep on the canvas: every layer the band fully contains joins what
    /// was already picked, so a selection can be built out of two or three
    /// sweeps instead of having to be right in one. Sweeping over something
    /// already picked leaves it picked, and a sweep that catches nothing new
    /// changes nothing.
    func addSweptLayersToSelection(in region: SelectionRegion) {
        guard let document else { return }
        let was = actionableLayerIDs
        let picked = BareCanvasPress.spares
            .selection(afterSweeping: document.layerIDs(fullyInside: region.bounds),
                       startingFrom: was)
        // Whatever the sweep caught, the band that is on screen came from an
        // EARLIER gesture and no longer describes anything: it comes down
        // before anything else, even when this sweep caught nothing new. A
        // pixel region stays put: it is the region tools' selection, not a
        // layer pick.
        if selection != nil, !selectionTargetsPixels { setSelection(nil, captureLayers: false) }
        guard picked != was else { return }
        if picked.count == 1 {
            selectedLayerID = picked.first // didSet clears any multi-selection
        } else {
            selectedLayerID = nil // didSet clears the multi-selection first
            multiSelectedLayerIDs = picked
            // A sweep has no anchor row, the same as any other marquee: the
            // next ⇧-click in the list starts over from the row it lands on.
            rowSelection = ListSelection(selected: picked)
        }
    }

    /// Escape, one level: leaves the group you are in with that group selected.
    /// Returns false when you are already at the top, which is when Escape
    /// means what it always meant (clear the selection).
    @discardableResult
    func exitGroupContext() -> Bool {
        guard Experiments.shared.layerGroupsEnabled, let context = groupContextID,
              document?.layer(id: context) != nil else {
            groupContextID = nil
            return false
        }
        let parent = document?.parentID(of: context)
        groupContextID = parent
        selectedLayerID = context
        return true
    }

    /// Makes `ids` the selection the way a row click would: one becomes the
    /// primary selection, several the multi-selection, none clears.
    private func selectLayers(_ ids: Set<UUID>) {
        // Whatever list the new selection lives in is where you now are, so a
        // duplicate made inside a group leaves you inside that group.
        groupContextID = ids.first.flatMap { document?.parentID(of: $0) }
        switch ids.count {
        case 0:
            selectLayer(nil)
        case 1:
            selectedLayerID = ids.first
        default:
            selectedLayerID = nil // didSet clears the multi-selection first
            multiSelectedLayerIDs = ids
            rowSelection = ListSelection(selected: ids)
        }
    }

    /// Layers the committed marquee fully contains — the rubber-band
    /// multi-selection. Derived from (selection, document), so there's no
    /// separate selection state to fall out of sync.
    var marqueeSelectedLayerIDs: [UUID] {
        guard let selection, let document else { return [] }
        return document.layerIDs(fullyInside: selection.bounds)
    }

    /// Batch delete (⌫ over a marquee that captured layers): all of them go in
    /// ONE undo step, then the marquee clears.
    func deleteLayers(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        discardDragPreview()
        let idSet = Set(ids)
        if let selected = selectedLayerID, idSet.contains(selected) { selectedLayerID = nil }
        perform { $0.removeLayers(ids: idSet) }
        setSelection(nil)
    }

    func duplicateLayer(id: UUID) {
        // Duplicating a member of the multi-selection (row context menu)
        // duplicates the whole selection, like Delete does.
        if multiSelectedLayerIDs.contains(id) {
            duplicateSelectedLayers()
            return
        }
        discardDragPreview()
        var copyID: UUID?
        perform { copyID = $0.duplicateLayer(id: id, offsetBy: CGPoint(x: 16, y: 16))?.id }
        selectedLayerID = copyID
    }

    // MARK: - Collage (16.9)

    /// The layers "Arrange in Collage…" would arrange: the multi-selection's
    /// image layers when it holds at least two, else every visible, unlocked
    /// image layer (so the command works straight from the menu with nothing
    /// selected — the locked Background never participates).
    var collageLayerIDs: [UUID] {
        guard let document else { return [] }
        let eligible = document.layers.filter {
            if case .image = $0.content { return $0.isVisible && !$0.isLocked }
            return false
        }.map(\.id)
        let selected = eligible.filter { multiSelectedLayerIDs.contains($0) }
        return selected.count >= 2 ? selected : eligible
    }

    var canArrangeCollage: Bool { collageLayerIDs.count >= 2 }

    /// "Arrange in Collage": absorbs `collageLayerIDs` into ONE new collage
    /// layer (their refs become slots in reading order, frame = the union of
    /// their frames, the source layers are removed) in one undo step, then
    /// selects it. The collage is live: resize reflows, slots swap by drag,
    /// photos drop in from history/Finder/other layers.
    func arrangeSelectionAsCollage() {
        guard let document else { return }
        let ids = Set(collageLayerIDs)
        guard ids.count >= 2 else { return }
        discardDragPreview()
        let participants = document.layers.filter { ids.contains($0.id) }
        guard let collageLayer = Collage.layer(absorbing: participants),
              let topIndex = document.layers.lastIndex(where: { ids.contains($0.id) }) else { return }
        // The collage takes the TOP participant's stacking slot (indices below
        // it shift down by the number of removed participants beneath it).
        let insertIndex = topIndex - (participants.count - 1)
        selectedLayerID = nil
        perform { doc in
            doc.removeLayers(ids: ids)
            doc.addLayer(collageLayer, at: insertIndex)
        }
        selectedLayerID = collageLayer.id
    }

    /// Creates an empty 2×2 collage layer centered on the canvas.
    func newEmptyCollageLayer() {
        guard let document else { return }
        discardDragPreview()
        let canvas = document.canvasSize
        let size = CGSize(width: (canvas.width * 0.6).rounded(), height: (canvas.height * 0.6).rounded())
        let frame = CGRect(x: ((canvas.width - size.width) / 2).rounded(),
                           y: ((canvas.height - size.height) / 2).rounded(),
                           width: size.width, height: size.height)
        let layer = Collage.layer(content: CollageContent(slots: [CollageSlot(), CollageSlot(),
                                                                  CollageSlot(), CollageSlot()]),
                                  frame: frame)
        perform { $0.addLayer(layer) }
        selectedLayerID = layer.id
    }

    /// A file dropped onto a collage cell: decode and fill that slot.
    func dropImage(at url: URL, intoCollage collageID: UUID, slot: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        fillCollageSlot(collageID: collageID, slot: slot, image: image)
    }

    /// Fills a collage slot with a new image (a history/Finder drop).
    func fillCollageSlot(collageID: UUID, slot: Int, image: CGImage) {
        let ref = store.register(image)
        perform { doc in
            doc.updateLayer(id: collageID) { layer in
                if var content = layer.collage {
                    content.fill(slot: slot, with: ref)
                    layer.content = .collage(content)
                }
            }
        }
    }

    /// Drops an existing photo layer into a collage slot: the layer's ref
    /// moves into the slot and the layer disappears — one undo step.
    func absorbLayer(id: UUID, intoCollage collageID: UUID, slot: Int) {
        guard id != collageID,
              let ref = document?.layers.first(where: { $0.id == id })?.imageRef else { return }
        discardDragPreview()
        if selectedLayerID == id { selectedLayerID = nil }
        perform { doc in
            doc.removeLayers(ids: [id])
            doc.updateLayer(id: collageID) { layer in
                if var content = layer.collage {
                    content.fill(slot: slot, with: ref)
                    layer.content = .collage(content)
                }
            }
        }
        selectedLayerID = collageID
    }

    /// Swaps two slots' photos (drag between cells).
    func swapCollageSlots(collageID: UUID, _ i: Int, _ j: Int) {
        guard i != j else { return }
        perform { doc in
            doc.updateLayer(id: collageID) { layer in
                if var content = layer.collage {
                    content.swapSlots(i, j)
                    layer.content = .collage(content)
                }
            }
        }
    }

    /// Inspector mutations, each one undo step.
    func updateCollage(layerID: UUID, _ mutate: (inout CollageContent) -> Void) {
        perform { doc in
            doc.updateLayer(id: layerID) { layer in
                if var content = layer.collage {
                    mutate(&content)
                    layer.content = .collage(content)
                }
            }
        }
    }

    // MARK: - Merge down (Photoshop ⌘E)

    /// ⌘E: merge the selected layer into the one below it — or the marquee
    /// multi-selection into one — as a single rasterized image layer.
    func mergeDown() {
        guard let document else { return }
        if multiSelectedLayerIDs.count >= 2 {
            mergeLayers(ids: document.layers.filter { multiSelectedLayerIDs.contains($0.id) }.map(\.id))
        } else if let id = selectedLayerID {
            mergeDown(id: id)
        }
    }

    /// Merge one specific layer into the layer directly below it (the panel's
    /// context menu, which acts on the clicked row, not the selection).
    func mergeDown(id: UUID) {
        guard let document, let idx = document.index(of: id), idx > 0 else { return }
        mergeLayers(ids: [document.layers[idx - 1].id, id])
    }

    /// Whether ⌘E has something to merge (menu enablement).
    var canMergeDown: Bool {
        guard let document else { return false }
        if multiSelectedLayerIDs.count >= 2 { return true }
        guard let id = selectedLayerID, let idx = document.index(of: id), idx > 0,
              !document.layers[idx].isLocked else { return false }
        return true
    }

    /// Composites the given layers (bottom-up order) into ONE image layer, in
    /// one undo step: their styles, blend modes, and transforms bake into the
    /// bitmap; the result takes the bottom participant's slot, name, and lock
    /// (so merging into the locked Background stays a background). All
    /// participants must be visible — a hidden layer would silently rasterize
    /// to nothing. Only the bottom layer may be locked (merge INTO it).
    private func mergeLayers(ids: [UUID]) {
        guard let document, ids.count >= 2 else { return }
        let idSet = Set(ids)
        let participants = document.layers.filter { idSet.contains($0.id) }
        guard participants.count >= 2, participants.allSatisfy(\.isVisible),
              let bottom = participants.first,
              participants.dropFirst().allSatisfy({ !$0.isLocked }) else { return }

        // The merged bitmap covers everything the participants can draw:
        // transformed bounds padded by each style's reach, clamped to canvas.
        var union = CGRect.null
        for layer in participants {
            var bounds = layer.frame
            if !layer.transform.isIdentity {
                let corners = layer.transformedCorners
                if let first = corners.first {
                    bounds = corners.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                        $0.union(CGRect(origin: $1, size: .zero))
                    }
                }
            }
            let pad = layer.style.previewPadding
            union = union.union(bounds.insetBy(dx: -pad, dy: -pad))
        }
        let region = Geometry.clampCrop(union, toCanvas: document.canvasSize)
        guard region.width >= 1, region.height >= 1 else { return }

        // Composite ONLY the participants (over transparency), so layers in
        // between or below don't leak into the merged bitmap.
        var temp = document
        temp.layers = participants
        guard let raster = previewRenderer.rasterize(region: region, of: temp, store: store) else { return }
        let ref = store.register(raster)
        let merged = Layer(name: bottom.name, content: .image(ref), frame: region,
                           isLocked: bottom.isLocked)
        discardDragPreview()
        perform { doc in
            guard let insertAt = doc.index(of: bottom.id) else { return }
            doc.removeLayers(ids: idSet)
            doc.addLayer(merged, at: insertAt)
        }
        selectedLayerID = merged.id
    }

    // MARK: - Rasterize (vector shape → pixels)

    /// Whether "Rasterize Layer" applies to the given layer (menu enablement).
    func canRasterizeLayer(id: UUID) -> Bool {
        document?.layer(id: id)?.isRasterizable ?? false
    }

    /// Bakes a vector shape/annotation layer into pixels in one undo step: the
    /// shape is rendered WITH all its style effects (blur, shadow, border, corner
    /// radius, opacity) and geometry (crop, transform) into a bitmap covering its
    /// padded on-canvas footprint, that bitmap is stored, and the layer's content
    /// becomes `.image` with its now-baked style reset. Looks pixel-identical;
    /// undo restores the editable vector shape. The layer keeps its slot/name/id.
    func rasterizeLayer(id: UUID) {
        guard let document, let layer = document.layer(id: id), layer.isRasterizable else { return }

        // The baked bitmap covers everything the layer can draw: its transformed
        // bounds padded by the style's reach (shadow/blur), clamped to canvas —
        // exactly how merge-down sizes its result, so nothing is clipped.
        var bounds = layer.frame
        if !layer.transform.isIdentity {
            let corners = layer.transformedCorners
            if let first = corners.first {
                bounds = corners.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                    $0.union(CGRect(origin: $1, size: .zero))
                }
            }
        }
        let pad = layer.style.previewPadding
        let region = Geometry.clampCrop(bounds.insetBy(dx: -pad, dy: -pad), toCanvas: document.canvasSize)
        guard region.width >= 1, region.height >= 1 else { return }

        // Composite ONLY this layer (over transparency) so nothing below leaks in.
        var temp = document
        var only = layer
        only.isVisible = true
        temp.layers = [only]
        guard let raster = previewRenderer.rasterize(region: region, of: temp, store: store) else { return }
        let ref = store.register(raster)
        discardDragPreview()
        perform { $0.rasterizeLayer(id: id, rasterized: ref, frame: region) }
        selectedLayerID = id
    }

    // MARK: - Restacking (Photoshop ⌘] ⌘[ ⇧⌘] ⇧⌘[)

    func bringLayerForward(id: UUID) { restack(id: id, .forward) }
    func sendLayerBackward(id: UUID) { restack(id: id, .backward) }
    func bringLayerToFront(id: UUID) { restack(id: id, .toFront) }
    func sendLayerToBack(id: UUID) { restack(id: id, .toBack) }

    /// Moves a layer in the stack (row context menu). A member of the
    /// multi-selection takes the whole selection with it; on its own, locked
    /// layers stay put and nothing can be pushed underneath the locked
    /// Background at the bottom.
    private func restack(id: UUID, _ step: PhotonzDocument.RestackStep) {
        if multiSelectedLayerIDs.contains(id) {
            restackSelectedLayers(step)
            return
        }
        guard let document else { return }
        var preview = document
        guard preview.restackLayers(ids: [id], step) else { return }
        discardDragPreview()
        perform { $0.restackLayers(ids: [id], step) }
    }

    /// Drag-reorder from the layers panel (SwiftUI `onMove` indices, visual
    /// top-down order). One undo step.
    func moveLayers(visualSources: IndexSet, visualDestination: Int) {
        discardDragPreview()
        perform { $0.moveLayers(visualSources: visualSources, visualDestination: visualDestination) }
    }

    /// The panel row thumbnail: cached per layer, re-rendered asynchronously
    /// whenever the layer changes (the hash covers content, frame, and style).
    func thumbnail(for layer: Layer) -> CGImage? {
        let hash = layer.hashValue
        if let cached = thumbnailCache[layer.id], cached.hash == hash { return cached.image }
        guard let doc = document else { return thumbnailCache[layer.id]?.image }
        if !thumbnailsInFlight.contains(hash) {
            let renderer = previewRenderer
            let store = store
            let id = layer.id
            // Defer the in-flight bookkeeping off the view-body read path.
            Task { @MainActor [weak self] in
                guard let self, !self.thumbnailsInFlight.contains(hash) else { return }
                self.thumbnailsInFlight.insert(hash)
                // One count per render actually started, so a walk can say
                // whether opening a hundred layer document costs a hundred
                // renders or the handful the panel is showing. Probe only.
                #if PHOTONZ_PLAYTEST
                ViewBuildMeter.shared.built(.layerThumbnail)
                #endif
                let image = await Task.detached(priority: .utility) {
                    renderer.thumbnail(for: id, in: doc, store: store, maxDimension: 80)
                }.value
                self.thumbnailsInFlight.remove(hash)
                if let image { self.thumbnailCache[id] = (hash, image) }
            }
        }
        return thumbnailCache[layer.id]?.image
    }

    /// The picture for every row the layers list is about to draw, gathered in
    /// one walk of the tree. Rows inside a shut group are not asked for, so a
    /// closed group still costs nothing to keep closed.
    ///
    /// The list hands each row its own image rather than letting the row ask:
    /// a row that reads the thumbnail cache becomes an observer of it, and
    /// then every thumbnail that lands redraws every row.
    func thumbnails(for rows: [LayerRowDisplay]) -> [UUID: CGImage] {
        guard let document, !rows.isEmpty else { return [:] }
        let wanted = Set(rows.map(\.id))
        var out: [UUID: CGImage] = [:]
        out.reserveCapacity(wanted.count)
        for layer in document.allLayers where wanted.contains(layer.id) {
            if let image = thumbnail(for: layer) { out[layer.id] = image }
        }
        return out
    }

    #if PHOTONZ_PLAYTEST
    /// Forget every picture the panel has made. Adopting a document does this
    /// too, so a walk can use it to measure what a big document costs to open
    /// without having to save and reopen one.
    func forgetLayerThumbnails() {
        thumbnailCache = [:]
        thumbnailsInFlight = []
    }
    #endif

    /// The Library shelf's picture of a component, sharp enough to be blown up
    /// and cropped in a tile. Same render path as the panel row thumbnail,
    /// asked for at a bigger size and cached on its own.
    func shelfThumbnail(for layer: Layer, dimension: CGFloat) -> CGImage? {
        let key = ShelfPictureKey(id: layer.id, dimension: Int(dimension))
        let hash = layer.hashValue
        if let cached = shelfThumbnails[key], cached.hash == hash { return cached.image }
        guard let doc = document else { return shelfThumbnails[key]?.image }
        if !shelfThumbnailsInFlight.contains(key) {
            let renderer = previewRenderer
            let store = store
            let id = layer.id
            Task { @MainActor [weak self] in
                guard let self, !self.shelfThumbnailsInFlight.contains(key) else { return }
                self.shelfThumbnailsInFlight.insert(key)
                let image = await Task.detached(priority: .utility) {
                    renderer.thumbnail(for: id, in: doc, store: store, maxDimension: dimension)
                }.value
                self.shelfThumbnailsInFlight.remove(key)
                if let image { self.shelfThumbnails[key] = (hash, image) }
            }
        }
        return shelfThumbnails[key]?.image
    }

    // MARK: - Promote selection

    /// ⌘J: rasterizes the marquee selection from the current composite and
    /// stacks it as a new image layer (one undo step). The new layer is
    /// selected; the marquee clears — it has done its job.
    func promoteSelectionToLayer() {
        guard let document, let selection else { return }
        let canvas = CGRect(origin: .zero, size: document.canvasSize)
        let raster: CGImage?
        let frame: CGRect
        if selectionTargetsPixels {
            // Pixel region: the promoted bitmap is clipped to the path —
            // transparent outside a wand blob or ellipse.
            frame = selection.path.boundingBoxOfPath.integral.intersection(canvas)
            raster = previewRenderer.rasterize(region: canvas, of: document, store: store)
                .flatMap { RegionOps.extracted($0, path: selection.path) }
        } else {
            frame = Geometry.pixelAligned(selection.bounds)
            raster = previewRenderer.rasterize(region: frame, of: document, store: store)
        }
        guard let raster, !frame.isNull else { return }
        let ref = store.register(raster)
        var newID: UUID?
        perform { newID = $0.promoteRegionToLayer(region: frame, rasterized: ref, name: "Promoted Layer").id }
        self.selection = nil // like Photoshop's Layer via Copy, ⌘J consumes the selection
        selectedLayerID = newID
    }

    /// One-click blur-behind: a single full-canvas rasterization becomes a
    /// blurred backdrop layer plus a sharp cutout cropped to the selection
    /// (one undo step). The focus layer ends up selected so its blur radius
    /// or crop can be adjusted immediately.
    func blurBehindSelection() {
        guard let document, let region = selection.map({ Geometry.pixelAligned($0.bounds) }),
              let raster = previewRenderer.rasterize(region: CGRect(origin: .zero, size: document.canvasSize),
                                                     of: document, store: store) else { return }
        let ref = store.register(raster)
        var focusID: UUID?
        perform { focusID = $0.blurBehind(selection: region, rasterized: ref).focus.id }
        selection = nil
        selectedLayerID = focusID
    }

    // MARK: - Clipboard

    /// ⌘C with a layer selected: the layer's model JSON (plus its bitmap for
    /// image layers — ImageRefs only mean something in this window's store)
    /// goes on the pasteboard under a Photonz-private type.
    ///
    /// With NO layer selected, ⌘C copies the marquee region — or, with no
    /// marquee either, the whole canvas — flattened from the composite. So
    /// ⌘A → ⌘C → ⌘V duplicates what you see (background included), and the
    /// PNG also pastes into other apps.
    func copySelectedLayer() {
        // A pixel region supersedes the layer (even one that's selected —
        // e.g. the fresh layer from ⌘N): ⌘C copies the region, not the layer.
        if selectionTargetsPixels, selection != nil {
            copyRegionFromComposite()
            return
        }
        if let id = selectedLayerID, let layer = document?.layer(id: id) {
            var imageData: Data?
            if case .image(let ref) = layer.content, let cg = store.image(for: ref) {
                imageData = ImageCodec.encode(cg, format: .png)
            }
            // The payload travels in CANVAS coordinates: a button copied out of
            // a screen remembers where it was on the canvas, not where it was
            // inside that screen, so pasting it lands it back over the screen.
            let travelling = document?.detachedLayer(id: id) ?? layer
            guard let payload = try? JSONEncoder().encode(LayerTransfer(layer: travelling, imageData: imageData)) else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(payload, forType: NSPasteboard.PasteboardType(LayerTransfer.pasteboardType))
            // A copied measurement also travels as its spec line, so ⌘C then
            // ⌘V in a chat or a doc pastes "- Width: 128 px (size)" instead of
            // nothing. Photonz's own paste still prefers the layer payload.
            if let document, let line = MeasureSpecList.specLine(for: layer, in: document) {
                pasteboard.setString(line, forType: .string)
            }
            return
        }
        guard let document else { return }
        let canvas = CGRect(origin: .zero, size: document.canvasSize)
        let region = selection.map { Geometry.pixelAligned($0.bounds) } ?? canvas
        guard region.width >= 1, region.height >= 1,
              let raster = previewRenderer.rasterize(region: region, of: document, store: store),
              let png = ImageCodec.encode(raster, format: .png) else { return }
        // A Photonz image-layer payload (⌘V lands it as a layer over the copied
        // spot) plus a plain PNG for interoperability.
        let layer = Layer(name: "Copied Selection",
                          content: .image(ImageRef(pixelSize: region.size)), frame: region)
        guard let payload = try? JSONEncoder().encode(LayerTransfer(layer: layer, imageData: png)) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(payload, forType: NSPasteboard.PasteboardType(LayerTransfer.pasteboardType))
        pasteboard.setData(png, forType: .png)
    }

    /// The pixel region copied from the composite, CLIPPED to its path —
    /// transparent outside a wand blob or ellipse. Pastes as a layer over the
    /// copied spot in Photonz, and as a PNG elsewhere.
    private func copyRegionFromComposite() {
        guard let document, let selection else { return }
        let canvas = CGRect(origin: .zero, size: document.canvasSize)
        let frame = selection.path.boundingBoxOfPath.integral.intersection(canvas)
        guard !frame.isNull, frame.width >= 1, frame.height >= 1,
              let composite = previewRenderer.rasterize(region: canvas, of: document, store: store),
              let clipped = RegionOps.extracted(composite, path: selection.path),
              let png = ImageCodec.encode(clipped, format: .png) else { return }
        let layer = Layer(name: "Copied Selection",
                          content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
        guard let payload = try? JSONEncoder().encode(LayerTransfer(layer: layer, imageData: png)) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(payload, forType: NSPasteboard.PasteboardType(LayerTransfer.pasteboardType))
        pasteboard.setData(png, forType: .png)
    }

    /// ⌘X: copy the selected (unlocked) layer, then remove it.
    func cutSelectedLayer() {
        guard let id = selectedLayerID, let layer = document?.layer(id: id),
              !layer.isLocked else { return }
        copySelectedLayer()
        deleteLayer(id: id)
    }

    /// ⌘A (Preview convention): marquee the whole canvas.
    func selectAll() {
        guard let document else { return }
        setSelection(SelectionRegion.rect(CGRect(origin: .zero, size: document.canvasSize)))
    }

    /// ⇧⌘A: clear the marquee.
    func deselect() {
        setSelection(nil)
    }

    /// ⇧⌘I (Photoshop): select everything OUTSIDE the current region. The
    /// result is a pixel-semantics region regardless of how the original was
    /// made — "the rest of the canvas" isn't a layer rubber-band.
    func invertSelection() {
        guard let document, let selection else { return }
        let full = SelectionRegion.rect(CGRect(origin: .zero, size: document.canvasSize))
        setSelection(full?.combining(selection, mode: .subtract), captureLayers: false)
    }

    /// File > New from Clipboard (⌘N, Preview convention): a clipboard image
    /// becomes a new document; beeps when the clipboard has none.
    func newFromClipboard() {
        if let image = NSImage(pasteboard: .general)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) {
            openCapture(image)
        } else {
            NSSound.beep()
        }
    }

    /// ⌘V: a copied Photonz layer pastes offset with a fresh identity; any
    /// system image (screenshot, copied web image) pastes as a new layer —
    /// or opens as a document when none is open.
    func paste() {
        // Pasting lands a NEW layer — the marquee belonged to the moment
        // before it; keeping stale ants over fresh content misleads
        // (Photoshop also deselects on a plain paste).
        setSelection(nil)
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(LayerTransfer.pasteboardType)),
           let transfer = try? JSONDecoder().decode(LayerTransfer.self, from: data) {
            pasteLayer(transfer)
            return
        }
        if let image = NSImage(pasteboard: pasteboard)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) {
            pasteImage(image)
        }
    }

    private func pasteLayer(_ transfer: LayerTransfer) {
        var layer = transfer.layer.duplicated(offsetBy: CGPoint(x: 16, y: 16))
        layer.name = transfer.layer.name
        if case .image = transfer.layer.content {
            guard let data = transfer.imageData, let cg = ImageCodec.decode(data) else { return }
            // The payload's ImageRef belonged to the source window's store.
            layer.content = .image(store.register(cg))
        }
        if document == nil, case .image(let ref) = layer.content,
           let cg = store.image(for: ref) {
            openCapture(cg)
            return
        }
        guard document != nil else { return }
        discardDragPreview()
        // Pasted over a screen means pasted ONTO it: the layer keeps the spot
        // it looks like it landed on and becomes part of that screen, the same
        // way a shape drawn there does.
        perform { [layer] in $0.addLayerDrawnOnFrame(layer) }
        selectedLayerID = layer.id
    }

    /// `point` is where a drag let go, in canvas coordinates; nil for ⌘V,
    /// which has no pointer and falls back to the middle of the canvas.
    ///
    /// `fileName` is the file the picture came out of, so the layer can carry
    /// its name instead of a generic one. nil for the clipboard, which has no
    /// file behind it (`PlacedImageNaming`). A name already in use here takes
    /// the next free number, so placing the same file twice reads as two rows
    /// rather than one word repeated.
    private func pasteImage(_ image: CGImage, at point: CGPoint? = nil,
                            fileName: String? = nil) {
        guard let document else {
            openCapture(image)
            return
        }
        let ref = store.register(image)
        let frame = document.placementForIncomingImage(size: ref.pixelSize, at: point)
        guard !frame.isEmpty else { return }
        // Numbered against what is already here, so dropping one file in twice
        // gives two rows you can tell apart instead of the same word twice.
        let name = PlacedImageNaming.layerName(fileName: fileName,
                                               taken: Set(document.allLayers.map(\.name)))
        let layer = Layer(name: name, content: .image(ref), frame: frame)
        discardDragPreview()
        perform { $0.addLayerDrawnOnFrame(layer) }
        selectedLayerID = layer.id
    }

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

    /// A layer's canvas-space frame, preview-aware.
    func canvasFrame(of id: UUID) -> CGRect? {
        if let frame = previewMoves[id] { return frame }
        return document?.canvasLayer(id: id)?.frame
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
            return LayerGeometrySelection.Member(id: layer.id, frame: frame,
                                                 editing: LayerGeometryEditing(layer: layer,
                                                                               in: holder))
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

    // MARK: - Frames from the canvas
    //
    // The canvas drags in CANVAS coordinates; a layer stores its frame in its
    // PARENT'S. The two are the same thing for a layer sitting loose on the
    // canvas, which is every layer in a document with no groups, so these two
    // entry points convert once and everything downstream keeps working in the
    // space it always did.

    /// A canvas-space point in the space the layer is stored in. Unchanged for
    /// a layer sitting loose on the canvas.
    private func parentPoint(_ point: CGPoint, of id: UUID) -> CGPoint {
        let origin = document?.parentOrigin(of: id) ?? .zero
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    /// Live drag update from the canvas, in canvas coordinates.
    ///
    /// A group takes the same path as everything else: the box it is being
    /// dragged to goes into `resized(to:)`, which moves it when the size did
    /// not change and scales everything inside it when it did
    /// (`docs/design/ui-building.md`). Previews always start from the document
    /// as it was before the drag — `submit` renders without touching history —
    /// so a hundred mouse-moves compose into one clean scale rather than a
    /// hundred stacked ones.
    func previewCanvasFrame(id: UUID, frame: CGRect) {
        guard let document, let parent = document.parentSpaceFrame(frame, of: id) else { return }
        previewLayerFrame(id: id, frame: parent)
    }

    /// Mouse-up from the canvas, in canvas coordinates: one undo step.
    func commitCanvasFrame(id: UUID, frame: CGRect) {
        guard let document, let parent = document.parentSpaceFrame(frame, of: id) else { return }
        commitLayerFrame(id: id, frame: parent)
    }

    /// Mouse-up on a DRAG, in canvas coordinates: the same one undo step, plus
    /// the layer joining the screen it was dropped on or leaving the one it was
    /// dragged out of.
    ///
    /// Only a drag takes this path. A resize and an arrow-key nudge come
    /// through `commitCanvasFrame` and never change what holds a layer: a nudge
    /// quietly changing hands one point at a time is a surprise nobody can see
    /// coming, and there is no pointer over a screen to say it is about to
    /// happen. See `FrameAdoption.swift`.
    func commitCanvasDrop(id: UUID, frame: CGRect) {
        guard let document, let parent = document.parentSpaceFrame(frame, of: id) else { return }
        commitLayerFrame(id: id, frame: parent, joiningScreens: true)
    }

    /// Live drag update for a whole multi-selection, in canvas coordinates:
    /// every layer the drag carries goes to its own new origin, and a group
    /// takes what is inside it along in one number changing.
    ///
    /// There is no floated sprite for a selection — a sprite carries one layer
    /// — so this re-renders the picture per mouse move, the path a text layer's
    /// drag has always taken.
    func previewCanvasOrigins(_ moves: [UUID: CGPoint]) {
        guard !moves.isEmpty, var doc = document else { return }
        // The rubber band that picked these layers described where they WERE.
        // The moment they move it stops being true, so it comes down rather
        // than lying, exactly as it does when a ⇧-click changes the selection.
        // A pixel region belongs to the region tools: that one stays.
        if selection != nil, !selectionTargetsPixels { setSelection(nil, captureLayers: false) }
        // A sprite left over from an earlier one-layer drag would float that
        // layer over a picture that has already moved it. Dropped once, not
        // once per mouse move: this runs on every point of the drag.
        if dragPreview != nil { discardDragPreview() }
        for (id, origin) in moves { doc.moveLayer(id: id, toCanvasOrigin: origin) }
        previewMoves = moves.reduce(into: [:]) { frames, move in
            frames[move.key] = doc.canvasBounds(of: move.key)
        }
        submit(doc)
    }

    /// Mouse-up on a multi-selection drag: the whole selection lands in ONE
    /// undo step, so one ⌘Z puts all of it back where it was.
    func commitCanvasOrigins(_ moves: [UUID: CGPoint], joiningScreens: Bool = false) {
        previewMoves = [:]
        guard !moves.isEmpty else { return }
        // The rubber band that picked these layers described where they WERE,
        // so it comes down the moment they move. A drag already dropped it on
        // its first live update; an arrow-key nudge has no live update at all,
        // and without this the band sits there outlining empty canvas.
        if selection != nil, !selectionTargetsPixels { setSelection(nil, captureLayers: false) }
        discardDragPreview()
        // Draw order, so a selection dropped on a screen keeps its stacking
        // inside it rather than landing in whatever order a dictionary iterated.
        let ordered = document?.allLayers.map(\.id).filter { moves[$0] != nil } ?? Array(moves.keys)
        var joined: [UUID] = []
        perform { document in
            for (id, origin) in moves { document.moveLayer(id: id, toCanvasOrigin: origin) }
            if joiningScreens { joined = document.adoptMovedLayers(ids: ordered) }
        }
        revealJoinedScreens(joined)
    }

    // MARK: ⌥-drag: leave the original, carry a copy

    /// Live ⌥-drag from the canvas: every original stays exactly where it is
    /// and a copy of each travels with the pointer.
    ///
    /// Nothing is recorded here. The whole gesture lands as ONE undo step on
    /// mouse-up (`commitCopyDrag`), which is what makes a cancelled drag, or a
    /// press that never left the click tolerance, cost nothing at all — there
    /// is no half-made copy to take back.
    ///
    /// There is no floated sprite on purpose. A sprite is one layer lifted off
    /// a picture that HIDES it, and a copy drag needs the picture whole with
    /// the original still in it, so the composite re-renders per move the way a
    /// multi-selection drag already does.
    func previewCopyDrag(_ origins: [UUID: CGPoint]) {
        guard !origins.isEmpty, var doc = document else { return }
        // The rubber band that picked these described where they WERE, and it
        // is about to stop being the truth — same rule as a multi-drag.
        if selection != nil, !selectionTargetsPixels { setSelection(nil, captureLayers: false) }
        if dragPreview != nil { discardDragPreview() }
        // The numbers, the outline and the handles follow the COPY, even though
        // the copy has no id yet and the selection is still the original. The
        // copy is the thing under the pointer and the thing that will be
        // selected the moment you let go, so X and Y reading the original's
        // resting place would be the inspector describing something nobody is
        // touching. The copy is the same size in the same parent, so the
        // original's own box is all that is needed to say where it is.
        previewMoves = origins.reduce(into: [:]) { frames, move in
            guard let size = doc.canvasBounds(of: move.key)?.size else { return }
            frames[move.key] = CGRect(origin: move.value, size: size)
        }
        doc.duplicateLayers(movingCopiesTo: origins)
        submit(doc)
    }

    /// Mouse-up on an ⌥-drag: the copies and where they landed go in as ONE
    /// undo step, so one ⌘Z leaves the document exactly as it was. The copies
    /// become the selection, so a follow-up nudge, restyle or arrange moves
    /// what you just made rather than what you made it from.
    func commitCopyDrag(_ origins: [UUID: CGPoint]) {
        previewMoves = [:]
        guard !origins.isEmpty else { return cancelCopyDrag() }
        discardDragPreview()
        var made: [UUID] = []
        var joined: [UUID] = []
        perform { document in
            made = document.duplicateLayers(movingCopiesTo: origins)
            // A copy dragged onto a screen joins it, exactly as the original
            // would have if it had been the thing that travelled.
            joined = document.adoptMovedLayers(ids: made)
        }
        guard !made.isEmpty else { return }
        revealJoinedScreens(joined)
        selectLayers(Set(made))
    }

    /// Esc, or a press that never travelled far enough to be a drag: nothing
    /// was ever recorded, so the only work is putting the real picture back.
    func cancelCopyDrag() {
        previewMoves = [:]
        discardDragPreview()
        rerender()
    }

    /// Live drag update (move or resize) in the layer's own parent space. With
    /// a CA preview active the canvas already shows the move, so this only
    /// records state; otherwise it renders the new frame without touching
    /// history.
    func previewLayerFrame(id: UUID, frame: CGRect) {
        let origin = document?.parentOrigin(of: id) ?? .zero
        previewMoves = [id: frame.offsetBy(dx: origin.x, dy: origin.y)]
        // A RESIZE (size change) of a layer whose look is sized in fixed points —
        // border/corner-radius/blur/shadow, or annotation strokes, text, callouts,
        // measures — can't be shown by scaling the drag sprite: the stroke would
        // stretch and, once the sprite's padding scales too, the anchored edge
        // would drift. Drop the sprite so the frame re-renders live each move
        // (moves keep their sprite — same-size scaling is faithful). The doc still
        // holds the pre-drag frame while a sprite is active, so a differing size
        // is exactly the resize signal.
        if dragPreview?.layerID == id, let layer = document?.layer(id: id),
           frame.size != layer.frame.size, !layer.resizeScalesUniformly {
            discardDragPreview()
        }
        guard dragPreview?.layerID != id else { return }
        guard var doc = document, doc.layer(id: id) != nil else { return }
        doc.updateLayer(id: id) { $0 = $0.resized(to: frame) }
        submit(doc)
    }

    /// Mouse-up: one undoable step from the pre-drag frame to the final one.
    /// Committing back to the original frame is a recognized no-op (History
    /// skips it), which is how an Esc-cancelled drag restores the real render.
    /// `resized(to:)` remaps annotation endpoints so resize scales the shape.
    /// A captioned arrow then re-picks its pill spot: a whole-arrow drag or
    /// nudge that parks the tail at the picture's edge would otherwise carry
    /// the label off the picture, and one dragged back into the open gets its
    /// default spot behind the tail again. Captionless layers pass through.
    func commitLayerFrame(id: UUID, frame: CGRect, joiningScreens: Bool = false) {
        previewMoves = [:]
        dragPreviewGeneration += 1 // cancels an in-flight preview session
        clearPreviewAfterNextFrame = dragPreview != nil
        var joined: [UUID] = []
        perform { document in
            let canvas = document.canvasSize
            document.updateLayer(id: id) {
                $0 = AnnotationBuilder.planningCaption($0.resized(to: frame), canvas: canvas)
            }
            // In the SAME mutation as the move, so one undo puts the layer back
            // where it was and back in what held it.
            if joiningScreens { joined = document.adoptMovedLayers(ids: [id]) }
        }
        revealJoinedScreens(joined)
    }

    /// After a drop changed what holds a layer, open the screen it went into,
    /// so the layers list shows where it landed instead of losing it in a shut
    /// row. A layer that came OUT is already at the top level and needs
    /// nothing opened.
    private func revealJoinedScreens(_ ids: [UUID]) {
        guard !ids.isEmpty, let document else { return }
        for id in ids { expandedGroupIDs.formUnion(document.ancestorIDs(of: id)) }
    }

    /// Live rotate/skew update. With a CA preview active the canvas applies
    /// the transform to the floated sprite, so this only renders when the
    /// preview pieces haven't landed yet.
    func previewLayerTransform(id: UUID, transform: LayerTransform) {
        guard dragPreview?.layerID != id else { return }
        guard var doc = document, doc.layer(id: id) != nil else { return }
        doc.updateLayer(id: id) { $0.transform = transform }
        submit(doc)
    }

    /// Mouse-up on a rotate/skew drag: one undo step. Committing the original
    /// transform is a History no-op (the Esc-cancel path).
    func commitLayerTransform(id: UUID, transform: LayerTransform) {
        dragPreviewGeneration += 1
        clearPreviewAfterNextFrame = dragPreview != nil
        perform { $0.updateLayer(id: id) { $0.transform = transform } }
    }

    /// Endpoint-drag commit from the canvas (document coords, ⇧ already
    /// applied). Rebuilds the layer's frame around the new endpoints in one
    /// undo step; committing the original endpoints is a History no-op (how
    /// an Esc-cancelled endpoint drag restores the real render).
    func commitAnnotationEndpoints(id: UUID, start: CGPoint, end: CGPoint) {
        let start = parentPoint(start, of: id)
        let end = parentPoint(end, of: id)
        previewMoves = [:]
        dragPreviewGeneration += 1
        clearPreviewAfterNextFrame = dragPreview != nil
        perform { document in
            // A moved tail can push the caption off the picture (or free the
            // room it was missing), so the pill re-picks its spot.
            let canvas = document.canvasSize
            document.updateLayer(id: id) {
                $0 = AnnotationBuilder.planningCaption(
                    AnnotationBuilder.updating($0, start: start, end: end), canvas: canvas)
            }
        }
    }

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

    private func rerender() {
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
    private func submit(_ document: PhotonzDocument) {
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

