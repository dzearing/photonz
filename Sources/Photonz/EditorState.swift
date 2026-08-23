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
    var isImporterPresented = false
    var isResizeDialogPresented = false
    var isCanvasSizeDialogPresented = false
    /// Live inspector visibility. The view drives this from BOTH the user's
    /// show/hide and the width-based auto-collapse, so it is transient — the
    /// persisted *preference* that survives relaunch (and feeds window sizing)
    /// is `inspectorPreferredVisible`, written only on an explicit toggle.
    var isLayersPanelVisible = EditorState.inspectorPreferredVisibleDefault
    var isExportDialogPresented = false

    /// The user's persisted show/hide preference for the docked inspector.
    /// Distinct from `isLayersPanelVisible`: auto-collapse never touches this,
    /// so `sizeWindowToImage()` can reserve the pane's width for a fresh window
    /// even before layout has decided whether the pane is currently shown.
    var inspectorPreferredVisible = EditorState.inspectorPreferredVisibleDefault {
        didSet { UserDefaults.standard.set(inspectorPreferredVisible, forKey: Self.inspectorVisibleKey) }
    }

    // MARK: Persisted inspector state (shared with EditorView's @AppStorage)

    static let inspectorVisibleKey = "inspector.visible"
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
    func setInspectorVisible(_ visible: Bool) {
        isLayersPanelVisible = visible
        inspectorPreferredVisible = visible
    }

    /// Canvas camera. Nil until a document is open. All zoom/pan flows through
    /// `Viewport` (PhotonzCore) so the math stays tested.
    private(set) var viewport: Viewport?
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
    /// The layer targeted by click-to-select / drag-to-move. Nil = none.
    /// Any change to the primary selection dissolves a marquee multi-selection —
    /// the two never coexist.
    private(set) var selectedLayerID: UUID? {
        didSet {
            if oldValue != selectedLayerID { multiSelectedLayerIDs = [] }
            // Selecting anything (or explicitly deselecting) drops the Canvas
            // pseudo-selection; selectCanvas() re-raises the flag afterwards.
            isCanvasSelected = false
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
    private(set) var multiSelectedLayerIDs: Set<UUID> = []
    /// Frame override while a move drag is in flight — rendered as a preview,
    /// committed to history only on mouse-up.
    private var previewMove: (id: UUID, frame: CGRect)?
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
    func addImageLayerOrOpen(at url: URL) {
        if url.pathExtension.lowercased() == "photonz" || document == nil {
            openImage(at: url)
            return
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        pasteImage(image)
    }

    /// Opens a CGImage (from a file or a screen capture) as a fresh document.
    /// `pixelScale` carries the capture's backing scale (2 for a Retina
    /// screenshot) so zoom and measures read in points.
    func openCapture(_ image: CGImage, pixelScale: CGFloat = 1) {
        let ref = store.register(image)
        installDocument(.withBaseImage(ref, pixelScale: pixelScale), url: nil)
    }

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
            // A file opened from the capture folder can round-trip back to history.
            if url.deletingLastPathComponent().standardizedFileURL == capture.store.directory.standardizedFileURL {
                sourceCaptureURL = url
            }
        case .clipboard:
            newFromClipboard()
            untitledName = Self.nextUntitledName()
        case .fresh:
            untitledName = Self.nextUntitledName() // empty editor; onboarding card guides next step
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
        viewport = .fit(documentSize: document.canvasSize, in: canvasViewSize)
        selection = nil
        selectedLayerID = nil
        activeTool = .select
        previewMove = nil
        dragPreview = nil
        editingTextLayerID = nil
        editingCaptionLayerID = nil
        stylePreview = nil
        thumbnailCache = [:]
        dragPreviewGeneration += 1
        rerender()
        // Size the window to the image (100% when it fits, reduced only when a
        // maxed window can't). The `.fit` above is the fallback for when there
        // is no host window yet — the real sizing runs once one is available.
        needsOpenSizing = true
        sizeWindowToImageIfReady()
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
    func exportComposite(format: ImageCodec.Format, scale: CGFloat, quality: Double = 0.9) {
        guard let document,
              let image = previewRenderer.render(document, store: store, scale: scale),
              let data = ImageCodec.encode(image, format: format, quality: quality) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        let base = documentURL?.deletingPathExtension().lastPathComponent ?? "Photonz Export"
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
    func copyCompositeToClipboard() {
        guard let document,
              let image = previewRenderer.render(document, store: store) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = ImageCodec.encode(image, format: .png) {
            pasteboard.setData(png, forType: .png)
        }
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        if let tiff = nsImage.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
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
        guard activeTool != tool else { return }
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
        perform { $0.addLayer(layer) }
        finishCreating(layer.id)
        guard shape == .arrow, Experiments.shared.arrowCaptionsEnabled else { return nil }
        return layer
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
    /// Newlines collapse to spaces — the pill is a single line.
    func commitCaptionEdit(layerID: UUID, string: String) {
        editingCaptionLayerID = nil
        let text = string.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let layer = document?.layer(id: layerID),
              let annotation = layer.annotation else {
            rerender()
            return
        }
        let newCaption: String? = text.isEmpty ? nil : text
        guard annotation.caption != newCaption else {
            rerender() // un-suppress the pill
            return
        }
        perform { document in
            guard let current = document.layer(id: layerID) else { return }
            let restyled = AnnotationBuilder.restyled(current, caption: .some(newCaption))
            document.updateLayer(id: layerID) {
                $0.content = restyled.content
                $0.frame = restyled.frame
            }
        }
    }

    /// Caption entry abandoned (Esc): the arrow keeps whatever caption it had.
    func cancelCaptionEdit() {
        editingCaptionLayerID = nil
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
    private func finishCreating(_ layerID: UUID) {
        setTool(.select)
        selectedLayerID = layerID
    }

    /// Completed source-box drag from the zoom tool. One undo step adds the
    /// callout (placement picked by Geometry), then the editor returns to select
    /// with it selected.
    func addZoomCallout(from start: CGPoint, to end: CGPoint) {
        guard let document,
              let layer = ZoomCalloutBuilder.layer(from: start, to: end,
                                                   canvas: document.canvasSize) else { return }
        perform { $0.addLayer(layer) }
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
                             avoiding extra: [CGRect] = []) {
        var probe = content
        probe.start = start
        probe.end = end
        let plan = MeasureLabelPlanner.plan(for: probe, canvas: document?.canvasSize,
                                            avoiding: placedReadoutRects() + extra)
        content.labelPlacement = plan.placement
        content.labelNudge = plan.nudge
    }

    /// Completed 3-click caliper placement: add the dimension layer with the
    /// active style, then auto-revert to Select and select the new caliper so its
    /// handles are immediately grabbable — matches other apps (the old sticky
    /// measure tool felt inconsistent).
    func addMeasure(from start: CGPoint, to end: CGPoint, mode: MeasureMode, headOffset: CGFloat) {
        var content = measureStyle
        content.mode = mode
        content.headOffset = headOffset
        planReadout(&content, from: start, to: end)
        var layer = MeasureBuilder.layer(content: content, from: start, to: end)
        // Inherit the last caliper's non-destructive effects (a drop shadow added
        // in Effects carries to the next measure), like annotations do per shape.
        layer.style = measureStyles.layerStyle
        perform { $0.addLayer(layer) }
        recordRecentColor(hex: content.strokeColorHex)
        measureHintDismissed = true
        finishCreating(layer.id)
    }

    /// Size mode's click: the element under the pointer becomes a width caliper
    /// and a height caliper in ONE undo step, both the same caliper every other
    /// mode produces. Two layers rather than a combined badge on purpose — a
    /// mode that invented its own callout would be the only one with a look of
    /// its own, and each caliper stays individually movable and deletable.
    /// The heads point outward, away from the element, so neither sits on it.
    func addElementSize(_ rect: CGRect) {
        guard rect.width > 0, rect.height > 0, let canvas = document?.canvasSize else { return }
        let widthFeet = (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY))
        let heightFeet = (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
        var width = measureStyle
        width.mode = .horizontal
        width.headOffset = MeasureBuilder.clearingHeadOffset(content: width, from: widthFeet.0,
                                                             to: widthFeet.1, canvas: canvas)
        var height = measureStyle
        height.mode = .vertical
        height.headOffset = MeasureBuilder.clearingHeadOffset(content: height, from: heightFeet.0,
                                                              to: heightFeet.1, canvas: canvas)
        planReadout(&width, from: widthFeet.0, to: widthFeet.1)
        var widthLayer = MeasureBuilder.layer(content: width, from: widthFeet.0, to: widthFeet.1)
        // The height readout also dodges the width readout that just landed —
        // they meet at the element's corner, so they are the likeliest pair in
        // the whole app to stack.
        planReadout(&height, from: heightFeet.0, to: heightFeet.1,
                    avoiding: [MeasureBuilder.readoutRect(of: widthLayer)].compactMap { $0 })
        var heightLayer = MeasureBuilder.layer(content: height, from: heightFeet.0, to: heightFeet.1)
        widthLayer.style = measureStyles.layerStyle
        heightLayer.style = measureStyles.layerStyle
        perform {
            $0.addLayer(widthLayer)
            $0.addLayer(heightLayer)
        }
        recordRecentColor(hex: width.strokeColorHex)
        measureHintDismissed = true
        finishCreating(widthLayer.id)
    }

    /// The style the canvas should preview the active Measure mode in. Gap mode
    /// previews in the Spacing ink it will actually commit, so what you see
    /// under the pointer is what lands.
    var measureStyleForActiveMode: MeasureContent {
        guard measureToolMode == .gap, Experiments.shared.measureRolesEnabled else {
            return measureStyle
        }
        return measureStyles.content(for: .spacing)
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
        planReadout(&content, from: gap.start, to: gap.end)
        var layer = MeasureBuilder.layer(content: content, from: gap.start, to: gap.end)
        layer.style = measureStyles.layerStyle
        perform { $0.addLayer(layer) }
        recordRecentColor(hex: content.strokeColorHex)
        measureHintDismissed = true
        finishCreating(layer.id)
    }

    /// What the Measure tool does when you click (Next): the two-point caliper,
    /// the size of the element under the pointer, the gap under the pointer, or
    /// an alignment guide. Always visible in the tool options, session chrome,
    /// never persisted. Distance is the default and the only mode that draws
    /// nothing on the canvas until you act.
    var measureToolMode: MeasureToolMode {
        get { Experiments.shared.measureModesEnabled ? storedMeasureToolMode : .distance }
        set {
            guard newValue != storedMeasureToolMode else { return }
            storedMeasureToolMode = newValue
            measureCandidateLevel = 0
        }
    }
    private var storedMeasureToolMode: MeasureToolMode = .distance

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
        let items = AlignmentScan.items(axis: axis, position: position, span: span,
                                        in: snappingEdgeMap)
        var content = measureStyle
        content.mode = axis
        content.headOffset = 0
        content.alignment = AlignmentCheck(items: items,
                                           tolerance: Experiments.shared.measureAlignTolerance)
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
        measureHintDismissed = true
        finishCreating(layer.id)
    }

    /// Once the first caliper lands in this document, the measure hint chip is
    /// gone for good — deleting every measurement doesn't bring it back.
    /// Session-scoped on purpose: hint state is chrome and never persists into
    /// the document.
    private var measureHintDismissed = false

    /// Whether the Measure tool's first-run hint chip shows: the Measure tool is
    /// active and no measurement has ever landed in this document. It tells you
    /// what a click does in the mode you are in, which is the one thing a mode
    /// switcher costs you.
    var showsMeasureHint: Bool {
        guard activeTool == .measure, !measureHintDismissed,
              let document else { return false }
        return !document.layers.contains { $0.measure != nil }
    }

    /// That chip's line, for the current mode.
    var measureHintText: String { measureToolMode.hint }

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

    /// Which corner the legend takes. It is a key TO the measurements, so
    /// parking it on top of one makes the same mistake a callout covering its
    /// subject makes (UX-PATTERNS D14): it walks to the first free corner.
    var measureLegendCorner: CanvasCorner {
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
        return CornerPlacement.firstClear(size: Self.measureLegendSize(rows: rows),
                                          in: viewport.viewSize,
                                          inset: Self.measureLegendInset,
                                          avoiding: occupied)
    }

    /// A generous reservation for the legend's glass panel. It is chrome laid
    /// out by SwiftUI, so its exact size is not knowable here; over-reserving
    /// only makes it step aside a little sooner than strictly needed.
    static func measureLegendSize(rows: Int) -> CGSize {
        CGSize(width: 140, height: CGFloat(max(rows, 1)) * 21 + 16)
    }
    /// Matches the legend's own `.padding(10)`.
    static let measureLegendInset: CGFloat = 10

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

    /// Copy as spec list (§7): the pinned plain-text form of the visible
    /// measurements goes on the clipboard.
    func copyMeasureSpecList() {
        guard let document else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(MeasureSpecList.render(document: document, name: specListName),
                             forType: .string)
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
        if let frame = doc.layer(id: layer.id)?.frame { previewMove = (layer.id, frame) }
        submit(doc)
    }

    /// Slider release: commit the label size in one undo step.
    func commitMeasureLabelScale(_ scale: CGFloat) {
        measureLabelPreview = nil
        previewMove = nil
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
    func previewMeasureEndpoints(id: UUID, start: CGPoint, end: CGPoint, headOffset: CGFloat) {
        guard var doc = document, doc.layer(id: id)?.measure != nil else { return }
        doc.updateLayer(id: id) {
            $0 = MeasureBuilder.updating($0, start: start, end: end, headOffset: headOffset)
        }
        if let frame = doc.layer(id: id)?.frame { previewMove = (id, frame) }
        submit(doc)
    }

    /// Mouse-up on a caliper handle: one undoable step. Committing the original
    /// values is a History no-op (the Esc-cancel path).
    func commitMeasureEndpoints(id: UUID, start: CGPoint, end: CGPoint, headOffset: CGFloat) {
        previewMove = nil
        let others = placedReadoutRects(excluding: id)
        let canvas = document?.canvasSize
        perform {
            $0.updateLayer(id: id) {
                $0 = MeasureBuilder.updating($0, start: start, end: end, headOffset: headOffset)
                // The measurement moved, so where its readout can sit changed.
                $0 = MeasureBuilder.replanningLabel($0, canvas: canvas, avoiding: others)
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

    /// A swatch pick restyles the selected annotation (one undo step) when
    /// there is one; either way it becomes the default for new annotations.
    func setAnnotationColor(_ hex: String) {
        // Per-tool color (17.12): a shape's color is its OWN, not the shared
        // paint-bucket foreground — picking here never touches the FG swatch.
        if let layer = selectedAnnotationLayer, let shape = layer.annotation?.shape {
            discardDragPreview() // a click-select's held sprite shows the old style
            perform { $0.updateLayer(id: layer.id) { $0 = AnnotationBuilder.restyled($0, colorHex: hex) } }
            annotationStyles.setColorHex(hex, forShape: shape)
        } else {
            annotationStyles.setColorHex(hex, for: activeTool)
        }
        saveAnnotationStyles()
        recordRecentColor(hex: hex)
    }

    /// The interior fill the current selection/tool draws with (rectangle /
    /// ellipse); nil = no fill.
    var activeToolFillHex: String? {
        if let layer = selectedAnnotationLayer { return layer.annotation?.fillColorHex }
        return annotationStyles.fillColorHex(for: activeTool)
    }

    /// A fill pick for the selected box (one undo step) or, with none selected,
    /// the active tool's new-shape default. nil = no fill (outline only).
    func setAnnotationFillColor(_ hex: String?) {
        if let layer = selectedAnnotationLayer, let shape = layer.annotation?.shape {
            discardDragPreview()
            perform { $0.updateLayer(id: layer.id) { $0 = AnnotationBuilder.restyled($0, fillColorHex: .some(hex)) } }
            annotationStyles.setFillColorHex(hex, forShape: shape)
        } else {
            annotationStyles.setFillColorHex(hex, for: activeTool)
        }
        saveAnnotationStyles()
        if let hex { recordRecentColor(hex: hex) }
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
        guard var doc = document, let shape = doc.layer(id: layerID)?.annotation?.shape else { return }
        if let strokeWidth, shape != .highlight { annotationStyles.setStrokeWidth(strokeWidth, forShape: shape) }
        if let arrowheadScale { annotationStyles.setArrowheadScale(arrowheadScale, forShape: shape) }
        discardDragPreview()
        doc.updateLayer(id: layerID) {
            $0 = AnnotationBuilder.restyled($0, strokeWidth: strokeWidth, arrowheadScale: arrowheadScale,
                                            cornerRadius: cornerRadius)
        }
        submit(doc)
    }

    /// Inspector slider release: one undo step + persist the shape default.
    func commitAnnotationRestyle(layerID: UUID, strokeWidth: CGFloat? = nil, arrowheadScale: CGFloat? = nil,
                                 cornerRadius: CGFloat? = nil) {
        guard let shape = document?.layer(id: layerID)?.annotation?.shape else { return }
        discardDragPreview()
        perform { $0.updateLayer(id: layerID) {
            $0 = AnnotationBuilder.restyled($0, strokeWidth: strokeWidth, arrowheadScale: arrowheadScale,
                                            cornerRadius: cornerRadius)
        } }
        if let strokeWidth, shape != .highlight { annotationStyles.setStrokeWidth(strokeWidth, forShape: shape) }
        if let arrowheadScale { annotationStyles.setArrowheadScale(arrowheadScale, forShape: shape) }
        if let cornerRadius { annotationStyles.setCornerRadius(cornerRadius, forShape: shape) }
        saveAnnotationStyles()
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

    /// The selected zoom-callout layer when the select tool is active — the
    /// style popover becomes the callout inspector for it.
    var selectedZoomCalloutLayer: Layer? {
        guard activeTool == .select, let id = selectedLayerID,
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

    func setCalloutBorderColor(_ hex: String) {
        guard let layer = selectedZoomCalloutLayer else { return }
        perform { $0.updateLayer(id: layer.id) { $0.style.borderColorHex = hex } }
        recordRecentColor(hex: hex)
    }

    func setCalloutBorderWidth(_ width: CGFloat) {
        guard let layer = selectedZoomCalloutLayer else { return }
        perform { $0.updateLayer(id: layer.id) { $0.style.borderWidth = width } }
    }

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
    /// color, callout border color, and LayerStyle border/shadow. Malformed hex
    /// is ignored by `RecentColors.record`.
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
        guard let layer = document?.layer(id: layerID),
              case .text = layer.content else { return }
        restyleSelectedText(layer, fontName: fontName, fontSize: fontSize,
                            weight: weight, colorHex: colorHex)
        if let fontName { textStyles.fontName = fontName }
        if let fontSize { textStyles.fontSize = fontSize }
        if let weight { textStyles.weight = weight }
        if let colorHex { textStyles.colorHex = colorHex }
        saveTextStyles()
        if let colorHex { recordRecentColor(hex: colorHex) }
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
        let content = textStyles.content(string: string)
        if let layerID {
            if isEmpty {
                perform { $0.removeLayer(id: layerID) }
            } else {
                let size = TextRasterizer.naturalSize(content, maxWidth: maxWidth,
                                                      minWidth: TextRasterizer.minimumTextWidth)
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
            let size = TextRasterizer.naturalSize(content, maxWidth: maxWidth,
                                                  minWidth: TextRasterizer.minimumTextWidth)
            let layer = TextBuilder.layer(content: content, at: origin, naturalSize: size)
            perform { $0.addLayer(layer) }
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
    private var stylePreview: (id: UUID, style: LayerStyle)?
    /// Thumbnail cache keyed by layer id; `hash` invalidates on any layer edit.
    private var thumbnailCache: [UUID: (hash: Int, image: CGImage)] = [:]
    private var thumbnailsInFlight: Set<Int> = []

    /// Layers in panel order (visual index 0 = topmost).
    var panelLayers: [Layer] {
        (document?.layers ?? []).reversed()
    }

    /// The selected layer's style, preview-aware so inspector sliders don't
    /// snap back mid-drag.
    func previewedStyle(of id: UUID) -> LayerStyle? {
        if let stylePreview, stylePreview.id == id { return stylePreview.style }
        return document?.layer(id: id)?.style
    }

    /// Live inspector-slider update: renders the new style without touching
    /// history. The first preview of a gesture drops any held drag sprite
    /// (it shows the old style).
    func previewLayerStyle(id: UUID, _ mutate: (inout LayerStyle) -> Void) {
        guard var style = previewedStyle(of: id) else { return }
        if stylePreview?.id != id { discardDragPreview() }
        mutate(&style)
        stylePreview = (id, style)
        guard var doc = document else { return }
        doc.updateLayer(id: id) { $0.style = style }
        submit(doc)
    }

    /// Slider release: one undo step from the pre-gesture style to the last
    /// previewed one (a no-change release is a History no-op).
    func commitLayerStyle(id: UUID) {
        guard let preview = stylePreview, preview.id == id else { return }
        stylePreview = nil
        perform { $0.updateLayer(id: id) { $0.style = preview.style } }
        captureStyleDefault(layerID: id)
    }

    /// One-shot style edit (steppers, toggles): a single undo step, no preview.
    func setLayerStyle(id: UUID, _ mutate: @escaping (inout LayerStyle) -> Void) {
        stylePreview = nil
        discardDragPreview()
        perform { $0.updateLayer(id: id) { mutate(&$0.style) } }
        captureStyleDefault(layerID: id)
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

    // MARK: - Restacking (Photoshop ⌘] ⌘[ ⌘⇧] ⌘⇧[)

    func bringLayerForward(id: UUID) { restack(id: id) { idx, count, _ in min(idx + 1, count - 1) } }
    func sendLayerBackward(id: UUID) { restack(id: id) { idx, _, floor in max(idx - 1, floor) } }
    func bringLayerToFront(id: UUID) { restack(id: id) { _, count, _ in count - 1 } }
    func sendLayerToBack(id: UUID) { restack(id: id) { _, _, floor in floor } }

    /// Moves a layer in the stack. Locked layers stay put, and nothing can be
    /// pushed underneath the locked Background at the bottom.
    private func restack(id: UUID, _ target: (Int, Int, Int) -> Int) {
        guard let document, let idx = document.index(of: id),
              !document.layers[idx].isLocked else { return }
        let floor = document.layers.prefix(while: \.isLocked).count
        let to = target(idx, document.layers.count, floor)
        guard to != idx else { return }
        discardDragPreview()
        perform { $0.moveLayer(id: id, to: to) }
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
                let image = await Task.detached(priority: .utility) {
                    renderer.thumbnail(for: id, in: doc, store: store, maxDimension: 80)
                }.value
                self.thumbnailsInFlight.remove(hash)
                if let image { self.thumbnailCache[id] = (hash, image) }
            }
        }
        return thumbnailCache[layer.id]?.image
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
            guard let payload = try? JSONEncoder().encode(LayerTransfer(layer: layer, imageData: imageData)) else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(payload, forType: NSPasteboard.PasteboardType(LayerTransfer.pasteboardType))
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
        perform { [layer] in $0.addLayer(layer) }
        selectedLayerID = layer.id
    }

    private func pasteImage(_ image: CGImage) {
        guard let document else {
            openCapture(image)
            return
        }
        let ref = store.register(image)
        let frame = PastePlacement.frame(forImageOf: ref.pixelSize, canvas: document.canvasSize)
        guard !frame.isEmpty else { return }
        let layer = Layer(name: "Pasted Image", content: .image(ref), frame: frame)
        discardDragPreview()
        perform { $0.addLayer(layer) }
        selectedLayerID = layer.id
    }

    // MARK: - Layer selection & move

    /// The selected layer's frame (preview-aware), for the canvas outline.
    var selectedLayerFrame: CGRect? {
        guard let id = selectedLayerID else { return nil }
        if let previewMove, previewMove.id == id { return previewMove.frame }
        return document?.layer(id: id)?.frame
    }

    func selectLayer(_ id: UUID?) {
        selectedLayerID = id
        // Explicit deselection dissolves the multi-selection even when the
        // primary was already nil (didSet only fires on change).
        if id == nil { multiSelectedLayerIDs = [] }
    }

    /// Selects the Canvas pseudo-layer (panel row click): boundary handles
    /// appear on canvas and the Canvas inspector section opens.
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
        let padding = layer.style.previewPadding
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

    /// Live drag update (move or resize). With a CA preview active the canvas
    /// already shows the move, so this only records state; otherwise it
    /// renders the new frame without touching history.
    func previewLayerFrame(id: UUID, frame: CGRect) {
        previewMove = (id, frame)
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
    func commitLayerFrame(id: UUID, frame: CGRect) {
        previewMove = nil
        dragPreviewGeneration += 1 // cancels an in-flight preview session
        clearPreviewAfterNextFrame = dragPreview != nil
        perform { $0.updateLayer(id: id) { $0 = $0.resized(to: frame) } }
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
        previewMove = nil
        dragPreviewGeneration += 1
        clearPreviewAfterNextFrame = dragPreview != nil
        perform { $0.updateLayer(id: id) { $0 = AnnotationBuilder.updating($0, start: start, end: end) } }
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

    func perform(_ mutate: (inout PhotonzDocument) -> Void) {
        history?.perform(mutate)
        rerender()
    }

    func undo() {
        discardDragPreview() // undone edits may invalidate a held sprite
        stylePreview = nil
        history?.undo()
        rerender()
    }

    func redo() {
        discardDragPreview()
        stylePreview = nil
        history?.redo()
        rerender()
    }

    private func rerender() {
        guard let document = history?.current else {
            renderedImage = nil
            viewport = nil
            selection = nil
            cropRect = nil
            selectedLayerID = nil
            previewMove = nil
            dragPreview = nil
            editingTextLayerID = nil
            editingCaptionLayerID = nil
            stylePreview = nil
            thumbnailCache = [:]
            return
        }
        // Thumbnails for layers that no longer exist are dead weight.
        if thumbnailCache.count != document.layers.count {
            let ids = Set(document.layers.map(\.id))
            thumbnailCache = thumbnailCache.filter { ids.contains($0.key) }
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

    /// Hands a document (committed or move-preview) to the render scheduler.
    private func submit(_ document: PhotonzDocument) {
        // The measure Show filter shapes the INTERACTIVE render only; export
        // paths rasterize the document directly and never pass through here.
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
