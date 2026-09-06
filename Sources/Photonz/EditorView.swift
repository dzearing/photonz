import AppKit
import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

/// What the window takes when a file is let go anywhere except on the picture
/// itself: the bar, the chrome around the edges, and the parts of the inspector
/// that have no drop of their own. `FileDrop` holds the reading; the inspector's
/// own sections and rows give the same answer, so the whole window agrees.
private struct WindowFileDrop: DropDelegate {
    let editorState: EditorState

    func validateDrop(info: DropInfo) -> Bool { FileDrop.carriesUsableFile(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .copy : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        FileDrop.accept(info, into: editorState)
    }
}

struct EditorView: View {
    @Environment(EditorState.self) private var editorState
    /// Capture/history live on the resident agent now; the in-editor history
    /// panel (phase-9 carousel) reads it until phase 11.4 replaces it with the
    /// global slide-down overlay.
    @Environment(AppCoordinator.self) private var coordinator
    /// The toolbar's own two pickers answer to the same "only one picker is
    /// open" rule every other colour row does, and by name — so a walk can
    /// open the one the tool is holding without a pointer.
    private var toolStyleWellKey: String { "tool.color" }
    private var toolFillWellKey: String { "tool.fill" }
    /// The bespoke HSB color picker popover (13.2).
    @State private var isFgPickerShown = false
    @State private var isBgPickerShown = false
    /// Whether the compact Tolerance chip's popover is open. Only ever used on
    /// a canvas too narrow for the wand's options to lay out along the bar.
    @State private var isWandToleranceShown = false
    @State private var isCropAspectShown = false
    /// Slider drafts so a drag doesn't snap back to the committed value mid-drag.
    @State private var strokeWidthDraft: CGFloat?
    @State private var arrowheadScaleDraft: CGFloat?
    /// Docked inspector width, set by the 1px left resize handle; persisted.
    @AppStorage("inspector.width") private var panelWidth = 264.0
    /// Anchors the active-tool accent circle so it slides between buttons.
    @Namespace private var toolbarNamespace
    /// True when the inspector was hidden BY the width auto-collapse (not by the
    /// user). Lets us restore the user's shown/hidden preference when the window
    /// grows back above the threshold, instead of clobbering it permanently.
    @State private var inspectorAutoHidden = false
    /// False until the document has first appeared, so the inspector pane doesn't
    /// slide in on open (it should just be there, or not). Armed one runloop
    /// after the first document load; user toggles / auto-collapse animate after.
    @State private var inspectorAnimationEnabled = false
    /// How many leading tools the floating toolbar currently shows; the rest sit
    /// in the "…" overflow menu. Driven by the measured-fit loop below.
    @State private var toolbarVisibleCount = ToolbarSlot.allCases.count
    /// The toolbar's measured natural width and the width available to it — the
    /// two inputs to the overflow loop. Real measurements, so no width estimate
    /// can be wrong (an earlier hand-computed version under-counted and clipped;
    /// a `ViewThatFits` version recursed to death inside `GlassEffectContainer`).
    @State private var toolbarContentWidth: CGFloat = 0
    @State private var toolbarBudget: CGFloat = 0
    /// The canvas's own width, so the bar can decide what it can afford to show
    /// beyond its tools (the zoom slider is the first thing to give way).
    @State private var canvasContentWidth: CGFloat = 0

    var body: some View {
        @Bindable var editorState = editorState
        GeometryReader { geo in
            let inspectorShown = editorState.document != nil
                && editorState.isLayersPanelVisible
                && !inspectorAutoHidden
            // Width the canvas (and thus the floating toolbar) actually gets.
            let canvasWidth = geo.size.width - (inspectorShown ? panelWidth + 1 : 0)
            HStack(spacing: 0) {
                canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Canvas surround adapts to the system appearance (Preview-
                    // style): near-black in dark mode, light gray in light mode.
                    .background(Color(nsColor: .underPageBackgroundColor))
                    // The toolbar is an OVERLAY, not a ZStack sibling: an overlay
                    // does not contribute to the canvas's minimum width, so a wide
                    // toolbar can never push the inspector off the window edge (the
                    // original bug). It stays bottom-centered and clips to the
                    // canvas rather than overhanging the panel.
                    .overlay(alignment: .bottom) {
                        // The bar and, on its own row above it, the settings
                        // for the tool in hand (`next-tool-settings`). Two
                        // surfaces, never one: tool settings used to live
                        // INSIDE the bar and grew it by 150 to 200pt the moment
                        // you picked up Measure, which is exactly what this
                        // stack exists to avoid.
                        VStack(spacing: EditorChromeLayout.toolBarStackGap) {
                            // The `if` is the "takes no room" rule: an empty
                            // capsule still counts as a stack child, and the
                            // 12pt gap above it would push the bar up off its
                            // own inset for a tool with nothing to set.
                            if !ToolSettingsCapsule.settings(
                                for: editorState.activeTool).isEmpty {
                                GlassEffectContainer {
                                    ToolSettingsCapsule()
                                }
                                .background(GeometryReader { proxy in
                                    Color.clear.preference(key: ToolSettingsSizeKey.self,
                                                           value: proxy.size)
                                })
                            }
                            GlassEffectContainer {
                                toolbar
                            }
                            // Measure the BAR, inside the insets. Measuring
                            // outside them counted the 32pt of inset twice (the
                            // budget already subtracts it) and cost the bar a
                            // tool it had room for. The capsule is measured
                            // separately and deliberately OUTSIDE this
                            // container: feeding its width to the overflow loop
                            // would shed tools the bar has room for.
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: ToolbarContentWidthKey.self,
                                                       value: proxy.size.width)
                            })
                            // The bar keeps exactly the animation behaviour it
                            // had: the stack's spring is for the capsule coming
                            // and going, and letting it reach the bar would
                            // start sliding the accent circle, which is a
                            // change to the bar nobody asked for.
                            .animation(nil, value: editorState.activeTool)
                        }
                        .padding(.horizontal, EditorChromeLayout.toolBarInset)
                        // The one inset the bar floats at, shared with whatever
                        // stacks above it (EditorChromeLayout.aboveToolBar).
                        .padding(.bottom, EditorChromeLayout.toolBarInset)
                        .animation(.spring(duration: 0.22),
                                   value: editorState.activeTool)
                    }
                    // The way back to a closed panel, top-trailing. ONLY while
                    // the panel is closed: open, the same button lives in the
                    // panel's own top-right corner, because a button floating
                    // beside the panel reads as an unrelated blob in the middle
                    // of the picture (reported 2026-09-05). Closed there is no
                    // panel to put it in and this corner is the way back,
                    // including after the shell auto-collapsed the panel on a
                    // narrow window.
                    .overlay(alignment: .topTrailing) {
                        if editorState.document != nil, !inspectorShown {
                            inspectorToggle(isShown: false)
                                // The one corner inset, shared with the measure
                                // legend, which parks under this button when it
                                // takes the top-right corner
                                // (EditorChromeLayout.inspectorToggleFrame).
                                .padding(EditorChromeLayout.cornerInset)
                                .transition(.opacity)
                        }
                    }
                    .clipped()  // keep a transient over-wide toolbar off the panel
                    // What the capsule takes, so every other bottom overlay
                    // (the Measure hint, the crop pill, the legend) clears one
                    // more row when it is up. Zero when it is not.
                    .onPreferenceChange(ToolSettingsSizeKey.self) { size in
                        editorState.toolSettingsSize = size
                    }
                    .onPreferenceChange(ToolbarContentWidthKey.self) { width in
                        toolbarContentWidth = width
                        // The legend parks clear of the bar, so it needs the
                        // bar's real width, not a guess.
                        editorState.toolBarWidth = width
                        reconcileToolbarCount()
                    }
                // The docked inspector. The 1px resize handle is the panel's own
                // LEADING EDGE (grouped here, not a separate sibling), so the two
                // slide in together as one surface — the border used to pop in
                // instantly while the panel slid. It runs the full window height.
                if inspectorShown {
                    HStack(spacing: 0) {
                        InspectorResizeHandle(width: $panelWidth)
                            // Only the 1px border runs edge-to-edge under the
                            // title bar; the panel's SCROLL content stays inset so
                            // its top row isn't clipped / unreachable.
                            .ignoresSafeArea(.container, edges: .vertical)
                        InspectorPanel()
                            .frame(width: panelWidth)
                    }
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing))
                }
            }
            // Animate show/hide only AFTER the first appearance: on open the pane
            // should just be there (or not), instantly — animating it in slows
            // the window's entrance. Later user toggles / auto-collapse animate.
            .animation(inspectorAnimationEnabled ? .spring(duration: 0.3) : nil,
                       value: inspectorShown)
            // Auto-collapse the inspector below the width threshold, and restore
            // the user's preference when the window grows back. Runs on the
            // initial size too, so opening small starts collapsed.
            .onChange(of: geo.size.width, initial: true) { _, width in
                updateInspectorAutoCollapse(width: width)
            }
            // Arm the show/hide animation one runloop after the document first
            // loads (the same pass that inserts the pane at its opening state),
            // so that first insertion is instant but every change thereafter
            // springs.
            .onChange(of: editorState.document != nil, initial: true) { _, hasDoc in
                guard hasDoc, !inspectorAnimationEnabled else { return }
                DispatchQueue.main.async { inspectorAnimationEnabled = true }
            }
            // Keep the toolbar's fit budget current as the window / panel changes.
            .onChange(of: canvasWidth, initial: true) { _, width in
                canvasContentWidth = width
                toolbarBudget = EditorChromeLayout.toolBarBudget(canvasWidth: width)
                reconcileToolbarCount()
                // Widening past the threshold takes the compact Tolerance chip
                // away, and its popover with it. Clear the flag too, or the
                // popover springs open by itself the next time the window comes
                // back down.
                if EditorChromeLayout.showsFullToolOptions(canvasWidth: width) {
                    isWandToleranceShown = false
                }
                if EditorChromeLayout.showsFullCropOptions(canvasWidth: width) {
                    isCropAspectShown = false
                }
            }
            // Same for putting the wand down while the chip's popover is open.
            .onChange(of: editorState.activeTool) { _, tool in
                if tool != .wand { isWandToleranceShown = false }
                if tool != .crop { isCropAspectShown = false }
            }
        }
        // Fill the window even in the empty state — the HStack otherwise hugs
        // the toolbar's width and the background paints as a visible column
        // against the window's own background.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $editorState.isImporterPresented,
                      allowedContentTypes: [.image, EditorState.photonzType]) { result in
            if case .success(let url) = result {
                let scoped = url.startAccessingSecurityScopedResource()
                editorState.openImage(at: url)
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
        }
        // Drop an image (history overlay thumbnail, Finder file, …) anywhere in
        // the window that is not the picture itself: into an open document it
        // becomes a new layer; otherwise it opens as a document.
        .onDrop(of: FileDrop.types, delegate: WindowFileDrop(editorState: editorState))
        // Finder double-click / `open` with a document (image or .photonz).
        .onOpenURL { editorState.openImage(at: $0) }
        .sheet(isPresented: $editorState.isResizeDialogPresented) {
            if let document = editorState.document {
                ResizeDialog(originalSize: document.canvasSize)
            }
        }
        .sheet(isPresented: $editorState.isCanvasSizeDialogPresented) {
            if let document = editorState.document {
                CanvasSizeDialog(originalSize: document.canvasSize)
            }
        }
        .sheet(isPresented: $editorState.isExportDialogPresented) {
            ExportDialog()
        }
        .sheet(isPresented: $editorState.isBlankCanvasDialogPresented) {
            // Where the canvas lands is the editor's call (empty window fills
            // itself, a busy one opens a new window), so both routes into this
            // sheet behave the same.
            NewCanvasDialog(onCreate: { editorState.createBlankCanvas(size: $0) },
                            opensNewWindow: BlankCanvas.destination(
                                windowHasDocument: editorState.document != nil) == .newWindow)
        }
        .sheet(isPresented: $editorState.isNewFrameDialogPresented) {
            NewFrameDialog()
        }
    }

    @ViewBuilder
    private var canvas: some View {
        if editorState.document != nil {
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
                       selectedLayerID: editorState.selectedLayerID,
                       selectedLayerFrame: editorState.selectedLayerFrame,
                       groupContext: editorState.groupContextID,
                       multiSelectedLayerIDs: editorState.multiSelectedLayerIDs,
                       dragPreview: editorState.dragPreview,
                       tool: editorState.activeTool,
                       captionCloseRequest: editorState.captionCloseRequest,
                       annotationContent: editorState.activeAnnotationContent,
                       calloutShape: editorState.calloutToolShape,
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
                       onSelectionChange: { editorState.setSelection($0, captureLayers: $1, inside: $2) },
                       onWandAt: { editorState.wandSelect(at: $0, mode: $1) },
                       onDeleteRegion: { editorState.deleteRegion() },
                       onRegionMoveBegin: { editorState.beginRegionMove(copy: $0) },
                       onRegionMoveCommit: { editorState.commitRegionMove(delta: $0) },
                       onRegionMoveCancel: { editorState.cancelRegionMove() },
                       onCropRectChange: { editorState.setCropRect($0) },
                       onCropCommit: { editorState.commitCrop() },
                       onSelectLayer: { editorState.selectLayer($0) },
                       onSelectLayerInGroup: { editorState.selectLayer($0, inGroup: $1) },
                       onExtendSelection: { editorState.extendSelection(toLayer: $0) },
                       onAddSweptLayers: { editorState.addSweptLayersToSelection(in: $0, inside: $1) },
                       onRenameLayer: { editorState.renameLayer(id: $0, to: $1) },
                       onRenameComponent: { editorState.renameComponent(componentID: $0, to: $1) },
                       onExitGroup: { editorState.exitGroupContext() },
                       onClickedNothing: { editorState.clearLibraryPick() },
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
                       onMeasureCommit: { editorState.addMeasure(from: $0, to: $1, mode: $2, headOffset: $3) },
                       onMeasureEndpointPreview: { editorState.previewMeasureEndpoints(id: $0, start: $1, end: $2, headOffset: $3, readout: $4) },
                       onMeasureEndpointCommit: { editorState.commitMeasureEndpoints(id: $0, start: $1, end: $2, headOffset: $3, readout: $4) },
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
                       onDropComponent: { componentID, point in
                           editorState.placeComponent(componentID: componentID, at: point)
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
                       gridOriginAdjust: editorState.gridOriginAdjustment?.origin,
                       onGridOriginChange: { editorState.moveGridOrigin(to: $0) },
                       onGridOriginCommit: { editorState.commitGridOriginPlacement() },
                       onGridOriginCancel: { editorState.cancelGridOriginPlacement() },
                       onCanvasResize: { size, anchor in
                           editorState.setCanvasSize(to: size, anchor: anchor)
                       },
                       onFillAt: { point, hit, useBackground in
                           editorState.fillLayer(at: point, hit: hit, useBackground: useBackground)
                       },
                       onFillSelected: { editorState.fillSelectedLayer(useBackground: $0) },
                       onClearBackground: { editorState.clearBackgroundLayer() },
                       onWindowChange: { editorState.canvasDidMoveToWindow($0) })
                .overlay(alignment: .bottom) {
                    // One slot: the "Copied" notice and the Measure mode hint
                    // never stack. The notice wins while it is up.
                    if let notice = editorState.copyConfirmation {
                        canvasNoticeChip(title: notice.title, detail: notice.detail)
                    } else if editorState.showsMeasureHint {
                        measureHintChip
                    }
                }
                .overlay(alignment: .bottom) {
                    if Experiments.shared.toolOptionsEnabled,
                       editorState.activeTool == .crop, editorState.cropRect != nil {
                        cropActionBar
                    }
                }
                .overlay(alignment: Self.alignment(for: editorState.measureLegendAnchor)) {
                    let entries = editorState.measureLegendEntries
                    if !entries.isEmpty { measureLegend(entries) }
                }
                .animation(.easeInOut(duration: 0.2), value: editorState.showsMeasureHint)
                .animation(.easeInOut(duration: 0.2), value: editorState.measureModeHint)
                .animation(.easeInOut(duration: 0.2), value: editorState.copyConfirmation)
                .animation(.easeInOut(duration: 0.2), value: editorState.activeTool)
                .animation(.easeInOut(duration: 0.2), value: editorState.measureLegendEntries)
                .animation(.easeInOut(duration: 0.25), value: editorState.measureLegendAnchor)
        } else {
            emptyState
        }
    }

    /// The mock's glass legend (§5, `next-measure-roles`): while the Measure
    /// tool is active, the measurement kinds present in the document, each
    /// swatched in its canvas ink (Alignment as a dashed line). Chrome only —
    /// it can never appear in an export.
    private func measureLegend(_ entries: [EditorState.MeasureLegendEntry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    legendSwatch(color: Color(hex: entry.colorHex), dashed: entry.isDashed)
                    Text(entry.label)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
        // The slot's inset on every side, except the top, which the placement
        // sets: in the top-right corner the legend hangs one stack gap under
        // the inspector toggle instead of sitting on it.
        .padding(.top, editorState.measureLegendTopInset)
        .padding([.leading, .trailing, .bottom], EditorState.measureLegendInset)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    /// The slot the legend picked, as a SwiftUI overlay alignment.
    private static func alignment(for anchor: PanelAnchor) -> Alignment {
        switch anchor {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    /// A short line of the entry's ink: solid for a role, dashed for Alignment.
    private func legendSwatch(color: Color, dashed: Bool) -> some View {
        HStack(spacing: 2) {
            if dashed {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().fill(color).frame(width: 4, height: 3)
                }
            } else {
                Capsule().fill(color).frame(width: 16, height: 3)
            }
        }
        .frame(width: 16, alignment: .leading)
    }

    /// The Measure tool's hint: a small glass pill saying what a click does in
    /// the current mode. In Next it is a toast that names the mode you just
    /// landed on and fades on its own (`MeasureModeHint`); in Current it is the
    /// first-run line that lives until the document's first measurement lands.
    private var measureHintChip: some View {
        canvasNoticeChip(title: editorState.measureHintTitle, detail: editorState.measureHintText)
    }

    /// The canvas-bottom glass pill every transient notice uses (the Measure
    /// mode hint, the "Copied" confirmation): an optional lead in its own
    /// weight, then one line. Never takes input, and fades with its owner.
    private func canvasNoticeChip(title: String?, detail: String) -> some View {
        HStack(spacing: 8) {
            if let title {
                Text(title).fontWeight(.semibold)
            }
            Text(detail)
        }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            // Above the tool bar, not behind it: it used to sit 14pt off the
            // bottom, inside the bar's own band, so the one line telling you
            // what a click does was covered by the bar you had just used. And
            // above the tool settings capsule when one is up, which for Measure
            // — the tool that owns this hint — it always is.
            .padding(.bottom, EditorChromeLayout.aboveToolBar(
                toolSettingsHeight: editorState.toolSettingsSize.height))
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var emptyState: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop a photo or screenshot here")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            GlassEffectContainer {
                VStack(alignment: .leading, spacing: 2) {
                    onboardingRow("folder", "Open a file", "⌘O") {
                        editorState.isImporterPresented = true
                    }
                    onboardingRow("rectangle.dashed", "Capture a rectangle", "⇧⌘4") {
                        coordinator.capture.beginRectCapture()
                    }
                    onboardingRow("doc.on.clipboard", "Paste an image", "⌘V") {
                        editorState.paste()
                    }
                    // Last on purpose: capture-and-redline is the daily use, so
                    // starting from nothing joins the card without moving the
                    // rows already under the pointer.
                    if Experiments.shared.blankCanvasEnabled {
                        onboardingRow("rectangle.badge.plus", "Blank canvas", "") {
                            editorState.isBlankCanvasDialogPresented = true
                        }
                    }
                }
                .padding(8)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
        }
    }

    /// One actionable hint in the onboarding card: icon, label, shortcut.
    private func onboardingRow(_ symbol: String, _ title: String, _ shortcut: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                Text(title)
                    .font(.callout)
                Spacer(minLength: 24)
                // An action with no key of its own leaves the column empty
                // rather than inventing a shortcut to fill it.
                if !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.callout.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 260)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderless)
    }

    /// Three glass bars: tools, fill colors, zoom — grouped in one
    /// GlassEffectContainer so the capsules morph together. Shows
    /// `toolbarVisibleCount` leading tools inline (the full bar when that's all
    /// of them, so there is zero regression at large sizes); the rest collapse
    /// into the "…" overflow menu. The count is driven by `reconcileToolbarCount`
    /// from real measured widths, so nothing clips at the window edge. On a
    /// canvas too cramped even for that, the zoom slider steps aside as well —
    /// see `EditorChromeLayout.showsZoomSlider`.
    private var toolbar: some View {
        HStack(spacing: 10) {
            // Placing the grid's zero point takes the bar over: the whole
            // adjustment is in one place, and there is no tool to reach for
            // while the canvas belongs to the two markers.
            if editorState.isPlacingGridOrigin {
                gridOriginBar
            } else {
                if toolbarVisibleCount >= toolbarSlots.count {
                    toolsBar
                } else {
                    compactToolsBar(visibleCount: toolbarVisibleCount)
                }
                sideCapsules
            }
        }
    }

    /// The bar that replaces the tools while the grid's zero point is being
    /// placed: where it is now, how fine the grid may get, and the two ways out.
    ///
    /// The readout is not decoration. The whole point of the mode is landing
    /// zero on something exact — the left edge of a screenshot's content, say —
    /// and you cannot check by eye that the markers came to rest on 24, 16.
    @ViewBuilder private var gridOriginBar: some View {
        let cell = editorState.gridOriginAdjustment?.minimumCell ?? CanvasGridSettings.noMinimumCell
        let origin = editorState.gridOriginAdjustment?.origin ?? .zero
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Grid starts at")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(CanvasGridOriginLabel.text(origin))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            .frame(minWidth: 92, alignment: .leading)
            Divider().frame(height: 24)
            gridMinimumCellSlider(cell)
            Divider().frame(height: 24)
            Button("Cancel") { editorState.cancelGridOriginPlacement() }
                .help("Put the grid back where it was (\u{238B})")
                .playtestControl("Cancel", detail: "Grid origin bar")
            Button("Done") { editorState.commitGridOriginPlacement() }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .help("Keep this zero point (\u{23CE})")
                .playtestControl("Done", detail: "Grid origin bar")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .contentShape(.capsule)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// The smallest cell the grid may draw. One to sixty four covers every UI
    /// grid anyone works to; the setting itself allows more, which is what a
    /// typed number is for.
    private func gridMinimumCellSlider(_ cell: CGFloat) -> some View {
        let value = Binding(get: { Double(cell) },
                            set: { editorState.setGridMinimumCell(CGFloat($0.rounded())) })
        return HStack(spacing: 8) {
            Text("Smallest cell")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Slider(value: value, in: 1...64, step: 1)
                .frame(width: 130)
            Text(verbatim: "\(Int(cell.rounded())) pt")
                .font(.system(size: 11).monospacedDigit())
                .frame(width: 38, alignment: .leading)
        }
    }


    /// Move the visible tool count to the largest set that fits `toolbarBudget`.
    /// Called whenever the measured content width or the available budget
    /// changes. The policy (and the reason it steps by many tools at once) lives
    /// in `EditorChromeLayout.fittedToolCount`, where it is unit-tested.
    private func reconcileToolbarCount() {
        guard toolbarBudget > 0, toolbarContentWidth > 0 else { return }
        let fitted = EditorChromeLayout.fittedToolCount(
            current: toolbarVisibleCount,
            maximum: toolbarSlots.count,
            contentWidth: toolbarContentWidth,
            budget: toolbarBudget)
        if fitted != toolbarVisibleCount { toolbarVisibleCount = fitted }
    }

    /// The grid's own chip: a glass capsule beside the zoom that appears the
    /// instant the grid does, reads the spacing it is drawing, and opens every
    /// grid setting.
    ///
    /// It exists because turning the grid on used to change the picture and
    /// nothing else, leaving the numbers behind a click on the Canvas row of
    /// the layers list that nobody makes. Now the settings appear beside the
    /// lines they shape, at the moment they arrive — no tip to dismiss, and
    /// nothing to know in advance.
    ///
    /// It is only there while the grid is showing (a door into settings for a
    /// grid that is off is a door into an empty room, and this bar has no width
    /// to spare) and only on a canvas roomy enough to hold it, which is the
    /// same width the zoom slider needs. On anything narrower the View menu's
    /// Show Grid and Grid Settings are still the whole feature.
    @ViewBuilder private var gridChip: some View {
        @Bindable var state = editorState
        if Experiments.shared.canvasGridEnabled, editorState.canvasGrid.isVisible,
           editorState.document != nil,
           EditorChromeLayout.showsGridChip(canvasWidth: canvasContentWidth) {
            Button {
                editorState.isGridSettingsPresented.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "grid")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    // The live spacing, in the same weight the bar's other
                    // pressable values wear. Monospaced digits so typing 4 into
                    // 128 cannot resize the chip underneath the popover you are
                    // typing in.
                    Text(editorState.canvasGrid.spacingText)
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundStyle(Color.primary)
                        .frame(width: 38, alignment: .trailing)
                        .background(Color.clear)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
                .frame(height: 28)
                .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .contentShape(.capsule)
            .help("Grid settings: spacing, bold lines, where it starts")
            .playtestControl("Grid settings", detail: "Tool bar, \(editorState.canvasGrid.spacingText)")
            .popover(isPresented: $state.isGridSettingsPresented, arrowEdge: .top) {
                CanvasGridSettingsPopover()
            }
        }
    }

    /// The color + zoom capsules, always present at the trailing end.
    ///
    /// The mock's "7 measurements" pill used to sit here too. It was a whole
    /// glass capsule of running text, permanently parked in the scarcest strip
    /// in the app, to report a number the Measurements panel already shows
    /// beside the list it is counting. Horizontal space in this bar is the
    /// thing D15 exists to protect, so the count went back to the panel and the
    /// bar kept its width.
    private var sideCapsules: some View {
        HStack(spacing: 10) {
            colorBar
            // Grid beside zoom: both are chrome for how the canvas is being
            // looked at, and both are the first things the bar sheds when the
            // picture gets narrow.
            gridChip
            zoomBar
        }
    }

    private var toolsBar: some View {
        HStack(spacing: 14) {
            if Experiments.shared.toolGroupsEnabled {
                groupedToolRow
            } else {
                flatToolRow
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        // The bar absorbs clicks on the whole capsule it draws, not just
        // on the controls: the glass has a 10pt rim above and below the
        // 28pt control row, and without this a click that lands on the
        // rim falls through to the picture behind the bar — with Measure
        // active, aiming slightly high at a tool started a measurement on
        // the image instead of picking the tool.
        .contentShape(.capsule)
        // One spring drives every toolbar transition: the accent circle
        // sliding between tools, conditional segments, and the capsule resize.
        .animation(.spring(duration: 0.3), value: editorState.activeTool)
        // NO toolbar animation on selectedLayerID (10.7). Selecting an
        // annotation/callout shows the style swatch, which resizes this glass
        // capsule; animating that reflow re-renders the glass every frame for
        // the spring's duration — ~350ms of pegged CPU per selection that
        // crosses an annotation boundary, on top of the inspector's own cost.
        // Making the swatch appear instantly on selection drops it to ~25ms.
        // (The accent circle still slides on TOOL change via `value: activeTool`
        // above, and the swatch still animates in when you pick the arrow tool.)
    }

    /// The bar as families (`ToolBarLayout.families`), a hairline between
    /// each: pick, cut and measure the picture; draw on it; paint it. Every
    /// slot is the same widget the compact bar uses, so the two never drift.
    @ViewBuilder private var groupedToolRow: some View {
        ForEach(Array(ToolBarLayout.bar(withFrame: Experiments.shared.framesEnabled)
            .families.enumerated()), id: \.offset) { index, family in
            if index > 0 {
                Divider().frame(height: 20)
            }
            ForEach(family, id: \.self) { entry in
                slotButton(ToolbarSlot(entry))
            }
            // With the tool-options flag off, Resize is still a button and it
            // stays beside Crop, the family it belongs to.
            if index == 0, !Experiments.shared.toolOptionsEnabled {
                resizeButton
            }
        }
        contextualToolOptions
    }

    /// One button per tool in the order the bar has always had. What Current
    /// ships, and what Next shows with its tool-groups flag off.
    @ViewBuilder private var flatToolRow: some View {
            toolButton(.select, "cursorarrow", "Select")
            regionSelectButtons
            if editorState.activeTool == .wand, !Experiments.shared.toolOptionsEnabled {
                wandOptions
                    .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
            }
            toolButton(.arrow, "arrow.up.right", "Arrow")
            toolButton(.line, "line.diagonal", "Line")
            toolButton(.rectangle, "rectangle", "Rectangle")
            toolButton(.ellipse, "circle", "Ellipse")
            toolButton(.highlight, "highlighter", "Highlight")
            toolButton(.text, "character.cursor.ibeam", "Text")
            Divider().frame(height: 20)
            cropToolButton
            if editorState.activeTool == .crop, !Experiments.shared.toolOptionsEnabled {
                cropOptions
                    .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
            }
            resizeButton
            toolButton(.zoomCallout, "plus.magnifyingglass", "Zoom Callout")
            // I, not M: M is the Photoshop marquee (rect/ellipse select), and
            // Photoshop itself files the Ruler under I.
            measureToolButton
            toolButton(.fill, help: "Fill") {
                PaintBucketIcon().frame(width: 22, height: 21)
            }
    }

    /// The compact tool row used when the full set won't fit: the leading tools
    /// that fit, then a chevron overflow menu holding the rest, then the
    /// contextual options for the active tool (which stay reachable). The active
    /// tool is always kept out of the overflow so its options make sense.
    private func compactToolsBar(visibleCount: Int) -> some View {
        let all = toolbarSlots
        let active = activeSlot
        let visible = all.enumerated().filter { index, slot in
            index < visibleCount || slot == active
        }.map(\.element)
        let overflow = all.filter { !visible.contains($0) }
        return HStack(spacing: 14) {
            ForEach(visible, id: \.self) { slotButton($0) }
            if !overflow.isEmpty {
                overflowMenu(overflow)
            }
            contextualToolOptions
        }
        .background { overflowShortcuts(overflow) }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .contentShape(.capsule)
        .animation(.spring(duration: 0.3), value: editorState.activeTool)
    }

    /// The trailing "…" menu that lists the tools that didn't fit. Picking one
    /// activates it (and, since the active tool is never overflowed, it then
    /// pops back into the visible row).
    private func overflowMenu(_ slots: [ToolbarSlot]) -> some View {
        Menu {
            ForEach(slots, id: \.self) { slot in
                Button {
                    activateSlot(slot)
                } label: {
                    Label(slot.title, systemImage: slot.menuSymbol)
                }
                // The row prints the same letter the button's tooltip does, so
                // the collapsed bar still TEACHES the keyboard instead of
                // hiding it. Nothing here fires: a SwiftUI Menu cannot carry a
                // shortcut for a closed menu, which is what the stand-ins below
                // are for.
                .keyboardShortcut(slot.keyEquivalent.map { KeyboardShortcut($0, modifiers: []) })
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
        }
        .menuStyle(.button)
        .buttonStyle(.tool())
        .menuIndicator(.hidden)
        .fixedSize()
        .toolTip("More tools")
    }

    /// Contextual options for the active tool (wand tolerance, crop aspects). In
    /// the compact bar they sit at the trailing edge; the full bar keeps them
    /// inline. (The color/style swatch lives in the adaptive color capsule now.)
    @ViewBuilder private var contextualToolOptions: some View {
        if !Experiments.shared.toolOptionsEnabled {
            if editorState.activeTool == .wand {
                wandOptions
            }
            if editorState.activeTool == .crop {
                cropOptions
            }
        }
    }

    /// Resize Image at the foot of the Crop flyout. Not a mode and not a tool:
    /// it is the other way to change the picture's bounds, so it rides with
    /// Crop rather than spending a slot of its own. The chord is printed for
    /// teaching; the Image menu is what fires it.
    private var resizeMenuRow: some View {
        Button {
            editorState.isResizeDialogPresented = true
        } label: {
            Label("Resize Image…", systemImage: "arrow.down.right.and.arrow.up.left.rectangle")
        }
        .keyboardShortcut("i", modifiers: [.command, .option])
        .disabled(editorState.document == nil)
    }

    /// The image-resize button (not a `Tool`, so it isn't part of `setTool`).
    private var resizeButton: some View {
        Button {
            editorState.isResizeDialogPresented = true
        } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left.rectangle")
                .font(.system(size: 15, weight: .medium))
        }
        .buttonStyle(.tool())
        .disabled(editorState.document == nil)
        .toolTip("Resize Image", key: "⌥⌘I")
    }

    /// The canvas's sidebar toggle (top-trailing): the way back to a closed
    /// inspector, including when the panel has auto-collapsed on a narrow
    /// window — tapping it forces the inspector open. While the panel is open
    /// its own corner carries the button instead (`InspectorPanel`).
    private func inspectorToggle(isShown: Bool) -> some View {
        Button {
            if isShown {
                editorState.setInspectorVisible(false)
                inspectorAutoHidden = false
            } else {
                editorState.setInspectorVisible(true)
                inspectorAutoHidden = false // user override beats auto-collapse
            }
        } label: {
            Image(systemName: isShown ? "sidebar.trailing" : "sidebar.leading")
                .font(.system(size: 14, weight: .medium))
        }
        // Same language as the tool bar: the hover fill is the capsule itself
        // lighting up, since the button is exactly the glass it sits on.
        .buttonStyle(.tool(diameter: EditorChromeLayout.inspectorToggleSize))
        .glassEffect(.regular, in: .capsule)
        .toolTip(isShown ? "Hide Inspector" : "Show Inspector", key: "⌥⌘L")
        // Named for a scripted walk. A `click` step goes to the canvas view
        // and falls straight through an overlay button, so a walk that wants
        // the way back into a closed dock has to press this by name.
        .playtestControl(isShown ? "Hide Inspector" : "Show Inspector",
                         detail: "the canvas corner's way back to the dock")
    }

    /// Auto-collapse the inspector below the width threshold, and restore the
    /// user's preference when the window grows back above it.
    private func updateInspectorAutoCollapse(width: CGFloat) {
        if EditorChromeLayout.shouldAutoCollapseInspector(windowWidth: width) {
            // Too narrow: hide, remembering that WE hid it (not the user).
            if editorState.isLayersPanelVisible {
                editorState.isLayersPanelVisible = false
                inspectorAutoHidden = true
            }
        } else if inspectorAutoHidden {
            // Roomy again: restore what the user had before we auto-hid it.
            editorState.isLayersPanelVisible = true
            inspectorAutoHidden = false
        }
    }

    // MARK: Toolbar overflow model

    /// The fixed tool-row slots, in bar order. Drives overflow: the leading
    /// slots that fit stay inline; the rest collapse into the chevron menu.
    private enum ToolbarSlot: String, CaseIterable {
        case select, marquee, arrow, line, rectangle, ellipse, highlight, text
        case crop, resize, zoomCallout, measure, fill
        /// The frame tool (Next, `next-frames`): the screen you build on.
        case frame
        /// Line, Rectangle and Ellipse as one family. Only in the grouped bar.
        case shapes

        /// The slot for one entry of `ToolBarLayout`.
        init(_ entry: ToolBarLayout.Entry) {
            switch entry {
            case .group(.selection): self = .marquee
            case .group(.shapes): self = .shapes
            case .tool(let tool): self = ToolbarSlot.allCases.first { $0.tool == tool } ?? .select
            }
        }

        /// The family this slot stands for, nil for a lone tool.
        var group: ToolGroup? {
            switch self {
            case .marquee: .selection
            case .shapes: .shapes
            default: nil
            }
        }

        /// Menu title when the slot is overflowed.
        var title: String {
            switch self {
            case .select: "Select"
            case .marquee: "Selection"
            case .shapes: "Shapes"
            case .arrow: "Arrow"
            case .line: "Line"
            case .rectangle: "Rectangle"
            case .ellipse: "Ellipse"
            case .highlight: "Highlight"
            case .text: "Text"
            case .crop: "Crop"
            case .resize: "Resize Image"
            case .zoomCallout: "Zoom Callout"
            case .measure: "Measure"
            case .fill: "Fill"
            case .frame: "Frame"
            }
        }

        /// SF Symbol for the overflow-menu row.
        var menuSymbol: String {
            switch self {
            case .select: "cursorarrow"
            case .marquee: "rectangle.dashed"
            case .shapes: "square.on.circle"
            case .arrow: "arrow.up.right"
            case .line: "line.diagonal"
            case .rectangle: "rectangle"
            case .ellipse: "circle"
            case .highlight: "highlighter"
            case .text: "character.cursor.ibeam"
            case .crop: "crop"
            case .resize: "arrow.down.right.and.arrow.up.left.rectangle"
            case .zoomCallout: "plus.magnifyingglass"
            case .measure: "ruler"
            case .fill: "drop"
            case .frame: "macwindow"
            }
        }

        /// The letter this slot answers to, for the overflow menu row. The
        /// marquee slot borrows M from the group it stands for; Resize is a
        /// ⌥⌘I menu command and keeps its hint in the menu bar where chords
        /// belong, so it prints nothing here.
        var shortcutKey: Character? {
            switch self {
            case .marquee: "m"
            // Each shape keeps its own letter, so the family prints none.
            case .shapes, .resize: nil
            default: tool?.shortcutKey
            }
        }

        var keyEquivalent: KeyEquivalent? { shortcutKey.map { KeyEquivalent($0) } }

        /// The `Tool` this slot activates, if any (resize opens a dialog; the
        /// marquee slot resolves to the remembered variant, so both are nil).
        var tool: Tool? {
            switch self {
            case .select: .select
            case .arrow: .arrow
            case .line: .line
            case .rectangle: .rectangle
            case .ellipse: .ellipse
            case .highlight: .highlight
            case .text: .text
            case .crop: .crop
            case .zoomCallout: .zoomCallout
            case .measure: .measure
            case .fill: .fill
            case .frame: .frame
            case .marquee, .shapes, .resize: nil
            }
        }
    }

    /// The slots the bar shows, in order. Families (`ToolBarLayout`) with the
    /// tool-groups flag on; otherwise one button per tool in the old order,
    /// which is what Current ships. Resize stays a button beside Crop only
    /// while the Crop flyout (tool-options flag) is not there to hold it.
    private var toolbarSlots: [ToolbarSlot] {
        let frames = Experiments.shared.framesEnabled
        guard Experiments.shared.toolGroupsEnabled else {
            return ToolbarSlot.allCases.filter { $0 != .shapes && ($0 != .frame || frames) }
        }
        var slots = ToolBarLayout.bar(withFrame: frames).entries.map(ToolbarSlot.init)
        if !Experiments.shared.toolOptionsEnabled, let crop = slots.firstIndex(of: .crop) {
            slots.insert(.resize, at: crop + 1)
        }
        return slots
    }

    /// The slot matching the active tool (all region selectors fold to
    /// `.marquee`), so the compact bar keeps the active tool out of the overflow.
    private var activeSlot: ToolbarSlot? {
        let tool = editorState.activeTool
        let slots = toolbarSlots
        if let group = ToolGroup.containing(tool), let slot = slots.first(where: { $0.group == group }) {
            return slot
        }
        return slots.first { $0.tool == tool }
    }

    /// Inline button for a slot in the compact bar — same widgets the full bar
    /// uses, so the two stay visually identical for the tools that show.
    @ViewBuilder private func slotButton(_ slot: ToolbarSlot) -> some View {
        switch slot {
        case .select: toolButton(.select, "cursorarrow", "Select")
        case .marquee:
            if Experiments.shared.toolGroupsEnabled {
                groupButton(.selection,
                            hint: "⇧ adds to the selection, ⌥ subtracts, ⇧⌥ intersects.")
            } else {
                selectionGroupButton
            }
        case .shapes: groupButton(.shapes)
        case .arrow: toolButton(.arrow, "arrow.up.right", "Arrow")
        case .line: toolButton(.line, "line.diagonal", "Line")
        case .rectangle: toolButton(.rectangle, "rectangle", "Rectangle")
        case .ellipse: toolButton(.ellipse, "circle", "Ellipse")
        case .highlight: toolButton(.highlight, "highlighter", "Highlight")
        case .text: toolButton(.text, "character.cursor.ibeam", "Text")
        case .crop: cropToolButton
        case .resize: resizeButton
        case .zoomCallout: toolButton(.zoomCallout, "plus.magnifyingglass", "Zoom Callout")
        case .frame: toolButton(.frame, "macwindow", "Frame")
        case .measure: measureToolButton
        case .fill:
            toolButton(.fill, help: "Fill") {
                PaintBucketIcon().frame(width: 22, height: 21)
            }
        }
    }

    /// Keeps every tool's letter alive at every window width.
    ///
    /// A tool that slid into the chevron stops being rendered, and its
    /// `.keyboardShortcut` goes with it, so at narrow widths the letter would
    /// have nothing left to fire on. A `Menu` cannot carry the shortcut for
    /// its own rows either (the same limitation the selection group works
    /// around below), so the overflowed slots get invisible stand-ins. Only
    /// the OVERFLOWED ones, so a letter is never registered twice.
    private func overflowShortcuts(_ slots: [ToolbarSlot]) -> some View {
        ZStack {
            ForEach(slots, id: \.self) { slot in
                if let key = slot.keyEquivalent {
                    Button("") { activateSlot(slot) }
                        .keyboardShortcut(key, modifiers: [])
                }
                // A family slot stands for several tools, so it carries the
                // whole family's vocabulary, not just its own letter.
                if let group = slot.group {
                    ToolGroupShortcuts(
                        group: group,
                        activate: { editorState.setTool($0) },
                        pickRemembered: { editorState.setTool(editorState.lastTool(in: group)) },
                        cycle: { cycleGroup(group) })
                }
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Activate a slot picked from the overflow menu.
    private func activateSlot(_ slot: ToolbarSlot) {
        switch slot {
        case .resize: editorState.isResizeDialogPresented = true
        default:
            if let group = slot.group {
                editorState.setTool(editorState.lastTool(in: group))
            } else if let tool = slot.tool {
                editorState.setTool(tool)
            }
        }
    }

    /// One family of tools as one slot: the button wears the member used
    /// last, and the family's keys live behind it.
    private func groupButton(_ group: ToolGroup, hint: String? = nil) -> some View {
        ToolGroupButton(
            group: group,
            remembered: editorState.lastTool(in: group),
            isActive: ToolGroup.containing(editorState.activeTool) == group,
            namespace: toolbarNamespace,
            hint: hint,
            activate: { editorState.setTool($0) },
            pickRemembered: { editorState.setTool(editorState.lastTool(in: group)) },
            cycle: { cycleGroup(group) })
    }

    /// Shift plus a family letter: the member after the one the family's
    /// button stands for. Read live, never from a rendered snapshot.
    private func cycleGroup(_ group: ToolGroup) {
        editorState.setTool(group.next(after: editorState.lastTool(in: group)))
    }

    /// The single color capsule, adaptive to the active tool (17.12): a drawing
    /// tool (line/arrow/shape/highlight/text) shows ONE swatch — that tool's own
    /// color, opening its style popover — because a stroke has a single color.
    /// Select / fill / everything else shows the Photoshop-style FG/BG paint pair
    /// (the bucket + ⌫/⌥⌫ colors), so there's exactly one color control on
    /// screen and it means the right thing for the tool in hand.
    private var colorBar: some View {
        Group {
            if activeToolUsesFillAndBorder {
                shapeFillBorderPair
            } else if usesToolColor {
                styleButton
            } else {
                fillColorPair
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .contentShape(.capsule)
    }

    /// Rectangle/ellipse have TWO tones — an interior fill and a border — so the
    /// capsule shows a fill/border pair for them (17.13).
    private var activeToolUsesFillAndBorder: Bool {
        editorState.activeTool == .rectangle || editorState.activeTool == .ellipse
    }

    /// Whether the active tool draws in a single color (so the capsule shows that
    /// tool's swatch instead of the FG/BG paint pair). Excludes the fill/border
    /// shapes, which get their own pair.
    private var usesToolColor: Bool {
        (editorState.activeTool.createsAnnotationByDrag || editorState.activeTool == .text)
            && !activeToolUsesFillAndBorder
    }

    /// Fill (top-left) OVER border (bottom-right), Photoshop-style — the fill is
    /// primary because you reach for a box to fill an area. The fill swatch picks
    /// the interior color (or clears it for an outline); the border swatch opens
    /// the style popover (border color + width + corner radius).
    private var shapeFillBorderPair: some View {
        HStack(spacing: 6) {
            ZStack {
                shapeBorderSwatch
                    .frame(width: 29, height: 29, alignment: .bottomTrailing)
                shapeFillSwatch
                    .frame(width: 29, height: 29, alignment: .topLeading)
            }
        }
    }

    private var shapeFillSwatch: some View {
        Button { editorState.openColorWell = toolFillWellKey } label: {
            shapeSwatchLabel(paint: editorState.activeToolFillPaint)
        }
        .help(editorState.toolColorStyle(slot: .fill).map { "Fill color — using \($0.name)" }
              ?? "Fill color — the shape's interior. Uncheck Fill for an outline.")
        .popover(isPresented: editorState.colorWellBinding(toolFillWellKey), arrowEdge: .top) {
            let off = editorState.activeToolFillPaint == nil
            VStack(alignment: .leading, spacing: 14) {
                toolColorStyleRow(slot: .fill)
                // A checkbox enables the fill; the picker stays visible but
                // disabled (dimmed) when it's off, so it's clear what it controls.
                Toggle("Fill", isOn: Binding(
                    get: { !off },
                    set: { on in
                        // Switched on from nothing, the interior starts where
                        // the shape's own colour is — gradient and all, so a
                        // box armed with a ramp fills with the same ramp.
                        editorState.setAnnotationFillPaint(
                            on ? (editorState.activeToolFillPaint ?? activeToolPaint) : nil)
                    }))
                    .font(.callout)
                ColorPickerContent(editorState: editorState,
                                   paint: editorState.activeToolFillPaint ?? activeToolPaint,
                                   name: "Fill",
                                   slot: .fill,
                                   supportsOpacity: true,
                                   // The tool can be armed with a gradient, so
                                   // the type row is here for the same reason
                                   // it is on a selected shape's Fill row.
                                   supportsGradient: ColorSlot.fill.acceptsGradient,
                                   embedded: true) { editorState.setAnnotationFillPaint($0) }
                    .disabled(off)
                    .opacity(off ? 0.4 : 1)
            }
            .padding(16)
        }
    }

    private var shapeBorderSwatch: some View {
        Button { editorState.toggleColorWell(toolStyleWellKey) } label: {
            // Show the "none" slash when the box has no border.
            shapeSwatchLabel(paint: editedStrokeWidth > 0 ? activeToolPaint : nil)
        }
        .help(editorState.toolColorStyle(slot: .stroke).map { "Border color — using \($0.name)" }
              ?? "Border color, width, and corner radius")
        .popover(isPresented: editorState.colorWellBinding(toolStyleWellKey), arrowEdge: .top) {
            stylePopover
        }
    }

    /// What the swatch above is HOLDING, when it is holding a saved colour
    /// rather than just a colour: the palette mark and the name, and the way
    /// back out.
    ///
    /// The swatch alone cannot say this. Two shapes can be the same blue with
    /// only one of them following Accent, and the difference is the whole point
    /// of saving a colour, so the popover the swatch opens is where the name
    /// goes. The same mark and the same word Unlink the inspector's colour rows
    /// use, so the two places read as one idea.
    ///
    /// Picking a colour in the picker below lets go of the name, which is what
    /// picking a plain colour has always meant — and the row SAYS so the moment
    /// it happens, in the place the name was, because that is the one spot the
    /// eye is already on. It cannot be the canvas pill the other broken links
    /// use: the picker that caused it is open over the canvas and covers it.
    ///
    /// The way back is beside the sentence, because undo cannot do this one.
    /// What a tool holds is a preference rather than part of the picture, so a
    /// pull of the picker you did not mean was never in the history to step
    /// back over.
    @ViewBuilder private func toolColorStyleRow(slot: ColorSlot) -> some View {
        if let style = editorState.toolColorStyle(slot: slot) {
            HStack(spacing: 6) {
                Image(systemName: "swatchpalette")
                    .foregroundStyle(.secondary)
                Text("Using \(style.name)")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button("Unlink") { editorState.releaseToolColorStyle(slot: slot) }
                    .buttonStyle(.link)
                    .font(.callout)
            }
            .help("New shapes follow the saved color \(style.name). "
                  + "Picking a color below lets go of it.")
        } else if let letGo = editorState.letGoNotice(slot: slot) {
            HStack(spacing: 6) {
                Image(systemName: "swatchpalette")
                    .foregroundStyle(.secondary)
                Text(letGo.line)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if editorState.canRearmToolColorStyle(letGo) {
                    Button("Put it back") { editorState.rearmToolColorStyle(letGo) }
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
            .help("New shapes are this colour on their own now. "
                  + "Put it back to follow \(letGo.name) again.")
            .transition(.opacity)
        }
    }

    /// A rounded-rect swatch; a nil paint shows the white-with-red-slash
    /// "none". It draws the PAINT rather than the one flat colour it stands
    /// for, because this little square is the only thing that says the tool in
    /// your hand is armed with a gradient before you draw with it.
    private func shapeSwatchLabel(paint: Paint?) -> some View {
        PaintFill(paint: paint ?? Paint(hex: "#FFFFFF"))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(width: 18, height: 18)
            .overlay {
                if paint == nil {
                    Path { p in
                        p.move(to: CGPoint(x: 2, y: 16))
                        p.addLine(to: CGPoint(x: 16, y: 2))
                    }
                    .stroke(Color.red, lineWidth: 1.5)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.background, lineWidth: 1.5))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.25), lineWidth: 1))
    }

    /// The Photoshop-style fill pair: foreground swatch top-left OVERLAPPING
    /// the background swatch bottom-right, swap arrows beside them (X). Each
    /// swatch opens the app's HSB/eyedropper picker.
    private var fillColorPair: some View {
        HStack(spacing: 6) {
            // Corner-aligned frames (not .offset, which is visual-only and
            // would leave the layout box as just the top swatch, hanging the
            // pair low-right of the capsule's center).
            ZStack {
                fillSwatch(hex: editorState.backgroundFillHex, isForeground: false)
                    .frame(width: 29, height: 29, alignment: .bottomTrailing)
                fillSwatch(hex: editorState.foregroundFillHex, isForeground: true)
                    .frame(width: 29, height: 29, alignment: .topLeading)
            }
            Button {
                editorState.swapFillColors()
            } label: {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            .keyboardShortcut("x", modifiers: [])
            .toolTip("Swap Fill Colors", key: "X")
        }
    }

    private func fillSwatch(hex: String, isForeground: Bool) -> some View {
        Button {
            if isForeground { isFgPickerShown = true } else { isBgPickerShown = true }
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: hex))
                .frame(width: 18, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.background, lineWidth: 1.5))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.primary.opacity(0.25), lineWidth: 1))
        }
        .help(isForeground
              ? "Foreground fill: bucket and ⌥⌫ fill with this"
              : "Background fill: new canvas space and ⌫-cleared backgrounds use this")
        .popover(isPresented: isForeground ? $isFgPickerShown : $isBgPickerShown,
                 arrowEdge: .top) {
            ColorPickerContent(editorState: editorState,
                                hex: hex,
                                name: isForeground ? "Foreground fill" : "Background fill",
                                slot: .fill,
                                onClose: { if isForeground { isFgPickerShown = false } else { isBgPickerShown = false } }) { newHex in
                if isForeground { editorState.foregroundFillHex = newHex }
                else { editorState.backgroundFillHex = newHex }
                editorState.recordRecentColor(hex: newHex)
            }
        }
    }

    private static let zoomStops: [Double] = [0.25, 0.5, 1, 2, 4, 8]

    /// Zoom: a log-scale slider plus a % readout that opens a stop menu.
    private var zoomBar: some View {
        HStack(spacing: 8) {
            // Zoom is shown in POINT terms (displayZoom), so 100% matches the
            // on-screen size even for Retina (pixelScale 2) screenshots.
            // On a cramped canvas the slider steps aside so the tools keep the
            // room: the percentage menu below still has every stop, Fit and
            // Actual Size, and ⌘0 / ⌘1 / pinch are untouched.
            if EditorChromeLayout.showsZoomSlider(canvasWidth: canvasContentWidth) {
                Slider(value: Binding(
                    get: { Double(log2(editorState.displayZoom)) },
                    set: { editorState.setDisplayZoom(CGFloat(pow(2, $0))) }),
                    in: -5...5)
                    .controlSize(.small)
                    .frame(width: 110)
                    .help("Zoom")
            }
            Menu {
                ForEach(Self.zoomStops, id: \.self) { stop in
                    Button(stop.formatted(.percent.precision(.fractionLength(0)))) {
                        editorState.setDisplayZoom(CGFloat(stop))
                    }
                }
                Divider()
                Button("Fit") { editorState.zoomToFit() }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Actual Size") { editorState.zoomToActualSize() }
                    .keyboardShortcut("1", modifiers: .command)
            } label: {
                Text(Double(editorState.displayZoom).formatted(.percent.precision(.fractionLength(0))))
                    .font(.callout.monospacedDigit())
                    .frame(width: 46)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Choose a zoom level")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .contentShape(.capsule)
        .disabled(editorState.document == nil)
    }

    /// Wand tolerance: how far a color may drift (0–255 Euclidean RGBA) and
    /// still join the flood. Applies to the next wand click.
    ///
    /// Laid out along the bar when the picture is wide enough to hold it, and
    /// otherwise collapsed to a chip that shows the live value and opens the
    /// same control in a popover — see `EditorChromeLayout.showsFullToolOptions`
    /// for why (176pt of bar that the overflow loop cannot shed, which pushed
    /// both ends of the capsule outside a 435pt picture).
    @ViewBuilder private var wandOptions: some View {
        if EditorChromeLayout.showsFullToolOptions(canvasWidth: canvasContentWidth) {
            wandToleranceControl
                .help("Wand tolerance: how similar a color must be to join the selection")
        } else {
            compactWandOptions
        }
    }

    /// The label, slider and readout, at their natural size. Used inline on a
    /// roomy canvas and inside the chip's popover on a cramped one, so the
    /// control itself never changes — only where it is drawn.
    private var wandToleranceControl: some View {
        HStack(spacing: 6) {
            Text("Tolerance")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            Slider(value: Binding(get: { editorState.wandTolerance },
                                  set: { editorState.wandTolerance = $0.rounded() }),
                   in: 0...128)
                .controlSize(.small)
                .frame(width: 80)
            Text("\(Int(editorState.wandTolerance))")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 22, alignment: .trailing)
        }
    }

    /// The cramped-canvas form: "Tol" plus the live number, opening the full
    /// slider in a popover.
    ///
    /// It wears a chevron because without one the pair reads as a readout
    /// rather than something to click — and a chevron is the affordance this
    /// bar already uses for a value you press to change it (the zoom
    /// percentage, the selection group's tool list). The number sits in a
    /// fixed-width frame so dragging the slider from 8 to 128 cannot change the
    /// chip's width and reflow the bar underneath the popover you are dragging
    /// in.
    private var compactWandOptions: some View {
        Button {
            isWandToleranceShown = true
        } label: {
            HStack(spacing: 4) {
                Text("Tol")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int(editorState.wandTolerance))")
                    // Weight and color match the crop chip's ratio beside it:
                    // both are live values you press, not dimmed captions. The
                    // clear background is load-bearing — a bare Text in a
                    // borderless button's label is drawn as an NSButton title,
                    // which ignores foregroundStyle and comes out gray; giving
                    // it a background puts it back on SwiftUI's own drawing
                    // path, where the color sticks. Monospaced digits carry the
                    // same advance width at every weight, so medium costs no
                    // width and the 22pt frame still holds three digits.
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(Color.primary)
                    .frame(width: 22, alignment: .trailing)
                    .background(Color.clear)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
            .frame(height: 28)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .help("Wand tolerance: how similar a color must be to join the selection")
        .popover(isPresented: $isWandToleranceShown, arrowEdge: .top) {
            wandToleranceControl
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
    }

    /// The Measure tool's button, which owns its own modes (D15). Distance,
    /// Size, Gap and (when its flag is on) Alignment used to sit beside it as
    /// four labelled chips plus a Snap menu and a Show menu, six controls that
    /// grew the bar the moment you picked the tool up. Now the button wears the
    /// live mode's glyph, press-and-hold lists the modes, I cycles them, and
    /// Snap and Show have moved to the Measure Tool section of the inspector,
    /// where settings belong.
    private var measureToolButton: some View {
        @Bindable var state = editorState
        let modes = Experiments.shared.measureModesEnabled
            ? MeasureToolMode.available(alignmentEnabled: Experiments.shared.measureAlignEnabled)
            : [.distance]
        return ToolModeButton(
            toolTitle: "Measure",
            key: Tool.measure.keyEquivalent,
            isActive: editorState.activeTool == .measure,
            modes: modes.map {
                ToolMode(mode: $0, title: $0.title, symbol: $0.symbol,
                         help: $0.help(landsOnRelease:
                                        Experiments.shared.measureDistanceLandsOnRelease))
            },
            selection: $state.measureToolMode,
            namespace: toolbarNamespace,
            activate: { editorState.setTool(.measure) },
            pressedKey: {
                // Read the tool live: I picks Measure up, and once it is in hand
                // the same key walks the modes.
                guard editorState.activeTool == .measure,
                      Experiments.shared.measureModesEnabled else {
                    editorState.setTool(.measure)
                    return
                }
                editorState.measureToolMode = editorState.measureToolMode
                    .cycled(alignmentEnabled: Experiments.shared.measureAlignEnabled)
            })
    }

    /// The Crop tool's button, which owns its aspect locks (D15). Free, 1:1,
    /// 4:3 and 16:9 used to sit beside it as four chips (plus a checkmark and a
    /// cross), 207pt of bar that appeared the moment you picked the tool up.
    /// The lock is a mode by D15's test — it changes what a drag does — so the
    /// button wears its glyph and press-and-hold lists the four.
    ///
    /// Unlike Measure, C does NOT cycle: switching lock refits the rect, so a
    /// second press of the tool's key would silently reshape a crop you just
    /// dragged. Picking a lock stays a deliberate choice.
    ///
    /// With the flag off this is the plain crop button and the chips are back
    /// in the bar, which is what Current ships.
    @ViewBuilder private var cropToolButton: some View {
        if Experiments.shared.toolOptionsEnabled {
            ToolModeButton(
                toolTitle: "Crop",
                key: Tool.crop.keyEquivalent,
                isActive: editorState.activeTool == .crop,
                modes: CropAspect.allCases.map {
                    ToolMode(mode: $0, title: $0.label, symbol: $0.symbol, help: $0.help)
                },
                selection: Binding(get: { editorState.cropAspect },
                                   set: { editorState.setCropAspect($0) }),
                namespace: toolbarNamespace,
                activate: { editorState.setTool(.crop) },
                keyCycles: false,
                footer: Experiments.shared.toolGroupsEnabled ? AnyView(resizeMenuRow) : nil,
                pressedKey: { editorState.setTool(.crop) })
        } else {
            toolButton(.crop, "crop", "Crop")
        }
    }

    /// Crop's two actions while a crop is live. A mode belongs in the tool
    /// button and a setting in the inspector (D15), but Apply and Cancel are
    /// neither: they are the actions that END a modal state, so they sit on the
    /// canvas the state has taken over, floating just clear of the tool bar,
    /// and they leave with the crop. Words, not glyphs — a checkmark at the far
    /// end of an 1100pt bar was never the thing a first-timer reached for.
    private var cropActionBar: some View {
        HStack(spacing: 10) {
            Button("Cancel") { editorState.cancelCrop() }
                .help("Cancel the crop (⎋)")
            Button("Crop") { editorState.commitCrop() }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .help("Apply the crop (⏎)")
        }
        .controlSize(.large)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        // Clear of the floating tool bar, and of the tool settings capsule
        // when one is up, so they read as a stack rather than one covering
        // the other.
        .padding(.bottom, EditorChromeLayout.aboveToolBar(
            toolSettingsHeight: editorState.toolSettingsSize.height))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// Aspect locks plus apply/cancel, shown while the crop tool is active.
    ///
    /// Laid out along the bar when the picture is wide enough to hold them, and
    /// otherwise collapsed so the four locks become one chip — see
    /// `EditorChromeLayout.showsFullCropOptions` for why (231pt of bar that the
    /// overflow loop cannot shed, which left 51pt of capsule hanging off each
    /// end of a 435pt picture, with clicks near either edge landing on controls
    /// that were only half drawn).
    ///
    /// Apply and cancel stay in the bar at both widths. They are the two things
    /// you reach for to finish a crop, and the compacted bar has room for them.
    @ViewBuilder private var cropOptions: some View {
        if EditorChromeLayout.showsFullCropOptions(canvasWidth: canvasContentWidth) {
            HStack(spacing: 6) {
                cropAspectLocks
                cropCommitButtons
            }
        } else {
            compactCropOptions
        }
    }

    /// The four locks as chips, at their natural size. Used inline on a roomy
    /// canvas and inside the chip's popover on a cramped one, so the control
    /// itself never changes — only where it is drawn.
    private var cropAspectLocks: some View {
        ForEach(CropAspect.allCases, id: \.self) { aspect in
            let isActive = editorState.cropAspect == aspect
            Button {
                editorState.setCropAspect(aspect)
                // A lock is a one-shot choice, unlike the wand's slider, so the
                // popover gets out of the way the moment you make it.
                isCropAspectShown = false
            } label: {
                Text(aspect.label)
                    .font(.caption.weight(.medium))
                    .fixedSize()
                    .foregroundStyle(isActive ? Color.white : Color.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        if isActive {
                            Capsule().fill(Color.accentColor)
                        }
                    }
            }
            .help("Lock aspect to \(aspect.label)")
        }
    }

    /// Apply and cancel, the pair that ends the crop.
    private var cropCommitButtons: some View {
        Group {
            Button {
                editorState.commitCrop()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .keyboardShortcut(.return, modifiers: [])
            .help("Apply Crop (⏎)")
            Button {
                editorState.cancelCrop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .help("Cancel Crop (⎋)")
        }
    }

    /// The cramped-canvas form: the live lock plus a chevron, opening the same
    /// four locks in a popover, then apply and cancel as before.
    ///
    /// The chevron is the affordance this bar already uses for a value you
    /// press to change it (the zoom percentage, the wand's Tolerance chip). A
    /// menu would have been the closer match to the zoom capsule, but a
    /// borderless menu sizes itself to its own title and ignores a fixed-width
    /// label, so the bar shifted 8pt every time the lock changed; the chip pins
    /// the label in a fixed frame, so switching from Free to 16:9 cannot reflow
    /// the bar. No glyph beside the label, for the same reason the four chips
    /// had to go: it costs 18pt, and 18pt is the difference between the bar
    /// fitting inside the picture and not.
    private var compactCropOptions: some View {
        HStack(spacing: 6) {
            Button {
                isCropAspectShown = true
            } label: {
                HStack(spacing: 4) {
                    Text(editorState.cropAspect.label)
                        .font(.caption.weight(.medium))
                        // Primary, not the borderless button's tint: this is a
                        // live value you can press, the same as the zoom
                        // percentage beside it, not a dimmed caption. The clear
                        // background is load-bearing: a bare Text in a
                        // borderless button's label is drawn as an NSButton
                        // title, which ignores foregroundStyle and comes out
                        // gray; giving it a background puts it back on
                        // SwiftUI's own drawing path, where the color sticks.
                        .foregroundStyle(Color.primary)
                        .frame(width: 30, alignment: .leading)
                        .background(Color.clear)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
                .frame(height: 28)
                .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .fixedSize()
            .help("Crop aspect: \(editorState.cropAspect.label). Click to lock the crop to a ratio.")
            .popover(isPresented: $isCropAspectShown, arrowEdge: .top) {
                HStack(spacing: 6) { cropAspectLocks }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            cropCommitButtons
        }
    }

    /// The annotation the popover is editing when one is selected (select
    /// tool); otherwise the popover sets defaults for the active tool.
    private var selectedAnnotation: AnnotationContent? {
        editorState.selectedAnnotationLayer?.annotation
    }

    /// The selected text layer's content when the popover should edit it
    /// (13.1), else nil. Routes the font/color controls to that layer.
    private var selectedTextContent: TextContent? {
        if case .text(let content)? = editorState.selectedTextLayer?.content { return content }
        return nil
    }

    /// Whether the popover shows the text controls: the text tool is active, or
    /// a placed text element is selected.
    private var showsTextControls: Bool {
        editorState.activeTool == .text || selectedTextContent != nil
    }

    /// The color the popover currently represents: the selected annotation's,
    /// the selected/edited text's, or what the active tool draws.
    ///
    /// A zoom callout is never one of them. This popover belongs to the TOOL
    /// in your hand, and the only tools that open it drop the layer selection
    /// when they are picked up, so a callout could not be showing here even
    /// when the code said it could. Its ring is the layer's own border and
    /// lives in the Color and Effects sections with every other layer's.
    private var activeToolColorHex: String {
        if let selected = selectedAnnotation {
            return selected.colorHex
        }
        if let text = selectedTextContent {
            return text.colorHex
        }
        if editorState.activeTool == .text {
            return editorState.textStyles.colorHex
        }
        return editorState.annotationStyles.colorHex(for: editorState.activeTool) ?? "#FF3B30" // non-annotation fallback
    }

    /// The same colour, gradient and all: what the tool in your hand is armed
    /// with, or what the selected object is painted with. A text block's ink is
    /// laid down glyph by glyph by a different path, so it comes back flat here
    /// and never sees the type row.
    private var activeToolPaint: Paint {
        if selectedTextContent != nil || editorState.activeTool == .text {
            return Paint(hex: activeToolColorHex)
        }
        if let selected = selectedAnnotation { return selected.paint }
        return editorState.annotationStyles.paint(for: editorState.activeTool)
            ?? Paint(hex: activeToolColorHex)
    }

    /// Whether the swatch the toolbar opens can be armed with a gradient: a
    /// ramp has to be something the slot can hold, or four tiles that quietly
    /// do nothing are worse than no tiles.
    private var toolColorAcceptsGradient: Bool { toolColorSlot.acceptsGradient }

    /// Which of a layer's colours the toolbar's single swatch stands for.
    private var toolColorSlot: ColorSlot { showsTextControls ? .text : .stroke }

    /// Stroke width applies to stroke shapes only — highlight is a fill.
    private var showsStrokeWidthRow: Bool {
        if let selected = selectedAnnotation {
            return selected.shape != .highlight
        }
        return editorState.activeTool.usesStrokeWidth
    }

    /// Rectangle/ellipse can have NO border (width 0, fill only); a line/arrow
    /// can't (it would vanish), so the toggle is box-only.
    private var showsBorderToggle: Bool {
        let shape = selectedAnnotation?.shape ?? editorState.activeTool.annotationShape
        return shape == .rectangle || shape == .ellipse
    }

    private var editedStrokeWidth: CGFloat {
        selectedAnnotation?.strokeWidth
            ?? editorState.annotationStyles.strokeWidth(for: editorState.activeTool)
    }

    /// The arrowhead-size row applies to arrows only.
    private var showsArrowheadRow: Bool {
        if let selected = selectedAnnotation { return selected.shape == .arrow }
        return editorState.activeTool == .arrow
    }

    private var editedArrowheadScale: CGFloat {
        selectedAnnotation?.arrowheadScale ?? editorState.annotationStyles.arrowheadScale(for: editorState.activeTool)
    }

    /// Swatch showing the active tool's color; opens the style popover.
    ///
    /// When the tool is holding a SAVED colour the palette mark appears BESIDE
    /// the swatch, because two identical greens where only one follows Accent
    /// look exactly alike and the shape is drawn long before you would think to
    /// open the popover. Beside rather than on top: a mark laid over a 16pt
    /// circle covers the one thing the circle is there to show, and at that size
    /// it read as a smudge rather than as a mark. The name itself is one click
    /// away, inside.
    private var styleButton: some View {
        let heldStyle = editorState.toolColorStyle(slot: toolColorSlot)
        return Button {
            editorState.toggleColorWell(toolStyleWellKey)
        } label: {
            HStack(spacing: 3) {
                PaintFill(paint: activeToolPaint)
                    .clipShape(Circle())
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                if heldStyle != nil {
                    Image(systemName: "swatchpalette")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: heldStyle == nil ? 28 : 42, height: 28)
        }
        .toolTip(heldStyle.map { "Using \($0.name)" }
                 ?? (editorState.activeTool == .text ? "Text Style" : "Annotation Style"),
                 key: "S")
        .keyboardShortcut("s", modifiers: [])
        .popover(isPresented: editorState.colorWellBinding(toolStyleWellKey), arrowEdge: .top) {
            stylePopover
        }
    }

    private var stylePopover: some View {
        let borderOff = showsBorderToggle && editedStrokeWidth <= 0
        return VStack(alignment: .leading, spacing: 14) {
            // For boxes, a "Border" CHECKBOX enables/disables the border. The
            // color + width below stay VISIBLE but disabled (dimmed) when it's
            // off, so it's obvious what the checkbox controls.
            if showsBorderToggle {
                Toggle("Border", isOn: Binding(
                    get: { editedStrokeWidth > 0 },
                    set: { on in
                        editorState.setAnnotationStrokeWidth(on ? AnnotationContent.defaultStrokeWidth : 0)
                    }))
                    .font(.callout)
            }
            VStack(alignment: .leading, spacing: 14) {
                toolColorStyleRow(slot: toolColorSlot)
                // One consistent color control everywhere: the same picker
                // this row opens is the one every other color row opens.
                ColorPickerContent(editorState: editorState,
                                   paint: activeToolPaint,
                                   name: showsTextControls ? "Text" : "Color",
                                   slot: toolColorSlot,
                                   supportsOpacity: true,
                                   supportsGradient: toolColorAcceptsGradient,
                                   embedded: true) { applyPaint($0) }
                if showsTextControls {
                    fontPicker
                } else if showsStrokeWidthRow {
                    strokeWidthSlider
                }
                if showsArrowheadRow {
                    arrowheadSizeSlider
                }
            }
            .disabled(borderOff)
            .opacity(borderOff ? 0.4 : 1)
        }
        .padding(16)
        .buttonStyle(.plain)
        // The system popover chrome is already glass on macOS 26. Drawing our
        // own glass rect inside a cleared presentation background left a light
        // halo (the popover bezel) around the inner rect — let the system
        // material carry the surface instead.
    }

    // A callout's Magnification and Shape used to sit here, under a popover a
    // picked callout can never open. They are the Zoom Callout section in the
    // dock now (`CalloutInspector`), beside the Color and Effects rows that
    // paint its ring.

    /// Font family / size / weight menus. Drives the new-text defaults for the
    /// text tool, or the selected text element's face/size/weight (13.1) — the
    /// pickers reflect that element so the panel edits what's on screen.
    private var fontPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Font", selection: Binding(
                get: { selectedTextContent?.fontName ?? editorState.textStyles.fontName },
                set: { editorState.setTextFont($0) })) {
                ForEach(fontMenuFamilies, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            HStack(spacing: 10) {
                Picker("Size", selection: Binding(
                    get: { selectedTextContent?.fontSize ?? editorState.textStyles.fontSize },
                    set: { editorState.setTextFontSize($0) })) {
                    ForEach(fontMenuSizes, id: \.self) { size in
                        Text("\(Int(size)) pt").tag(size)
                    }
                }
                Picker("Weight", selection: Binding(
                    get: { selectedTextContent?.weight ?? editorState.textStyles.weight },
                    set: { editorState.setTextWeight($0) })) {
                    ForEach(TextWeight.allCases, id: \.self) { weight in
                        Text(weight.rawValue.capitalized).tag(weight)
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 220)
    }

    /// Font families for the picker, including the selected element's family if
    /// it isn't one of the curated defaults (so its current value stays valid).
    private var fontMenuFamilies: [String] {
        guard let name = selectedTextContent?.fontName, !TextStyles.fonts.contains(name) else {
            return TextStyles.fonts
        }
        return TextStyles.fonts + [name]
    }

    /// Sizes for the picker, including the selected element's size if it isn't a
    /// preset (so a custom size from a re-measure still selects correctly).
    private var fontMenuSizes: [CGFloat] {
        guard let size = selectedTextContent?.fontSize, !TextStyles.fontSizes.contains(size) else {
            return TextStyles.fontSizes
        }
        return (TextStyles.fontSizes + [size]).sorted()
    }

    /// Where a pick from the toolbar's one colour row lands: the
    /// active/selected text, or the active annotation. Every path records the
    /// shared recents list (13.2). A shape takes the whole paint, so a gradient
    /// arms the tool; a text block's ink takes the flat colour it can draw,
    /// which is why it was not offered the type row in the first place.
    private func applyPaint(_ paint: Paint) {
        if showsTextControls {
            editorState.setTextColor(paint.hex)
        } else {
            editorState.setAnnotationPaint(paint)
        }
    }

    /// Stroke width slider with a live numeric readout. Drag previews without
    /// recording undo; release commits one step.
    private var strokeWidthSlider: some View {
        let value = strokeWidthDraft ?? editedStrokeWidth
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label("Width", systemImage: "lineweight").labelStyle(.titleOnly)
                Spacer()
                Text("\(Int(value.rounded())) pt").monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            Slider(value: Binding(
                get: { strokeWidthDraft ?? editedStrokeWidth },
                set: { v in
                    strokeWidthDraft = v
                    editorState.previewAnnotationRestyle(strokeWidth: v.rounded())
                }
            ), in: AnnotationStyles.strokeWidthRange, onEditingChanged: { editing in
                if !editing {
                    editorState.setAnnotationStrokeWidth(
                        (strokeWidthDraft ?? editedStrokeWidth).rounded())
                    strokeWidthDraft = nil
                }
            })
        }
        .frame(width: 220)
    }

    /// Arrowhead size slider (multiplier) with a small/large triangle on each end.
    private var arrowheadSizeSlider: some View {
        let value = arrowheadScaleDraft ?? editedArrowheadScale
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label("Arrowhead", systemImage: "arrowshape.right.fill").labelStyle(.titleOnly)
                Spacer()
                Text("×\(String(format: "%.1f", value))").monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            HStack(spacing: 8) {
                Image(systemName: "arrowtriangle.right.fill").font(.system(size: 8)).foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { arrowheadScaleDraft ?? editedArrowheadScale },
                    set: { v in
                        arrowheadScaleDraft = v
                        editorState.previewAnnotationRestyle(arrowheadScale: v)
                    }
                ), in: AnnotationStyles.arrowheadScaleRange, onEditingChanged: { editing in
                    if !editing {
                        editorState.setAnnotationArrowheadScale(arrowheadScaleDraft ?? editedArrowheadScale)
                        arrowheadScaleDraft = nil
                    }
                })
                Image(systemName: "arrowtriangle.right.fill").font(.system(size: 15)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 220)
    }

    private func toolButton(_ tool: Tool, _ symbol: String, _ help: String) -> some View {
        toolButton(tool, help: help) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
        }
    }

    /// The key is never passed in: it comes from `Tool.shortcutKey`, so the
    /// letter this button fires on and the letter its tooltip prints are the
    /// same fact read twice. Hand-written literals here are how the redline
    /// surface ended up teaching P for the Arrow while the Pen owns P
    /// everywhere else.
    private func toolButton(_ tool: Tool, help: String,
                            modifiers: EventModifiers = [],
                            @ViewBuilder icon: () -> some View) -> some View {
        let isActive = editorState.activeTool == tool
        let shiftHint = modifiers.contains(.shift) ? "⇧" : ""
        let keyLabel = tool.shortcutHint.map { "\(shiftHint)\($0)" }
        let keyHint = keyLabel.map { " (\($0))" } ?? ""
        let key = tool.keyEquivalent
        return Button {
            editorState.setTool(tool)
        } label: {
            icon()
        }
        // The shared icon-button language: hover fill, pressed shrink, and the
        // accent circle while this is the tool in hand.
        .buttonStyle(.tool(isActive: isActive, in: toolbarNamespace))
        // Tools are sticky (17.12), so no double-click-to-lock is needed.
        .toolTip(help, key: keyLabel, fallback: "\(help)\(keyHint)")
        .accessibilityLabel(help)
        .keyboardShortcut(key.map { KeyboardShortcut($0, modifiers: modifiers) })
    }

    /// The three region-selection tools share ONE toolbar slot (Photoshop-style):
    /// rectangle select, ellipse select, and the magic wand. The button shows
    /// (and a click activates) the last-used one, the chevron menu switches it,
    /// M picks the remembered one, ⇧M cycles, W jumps to the wand. Keeps the bar
    /// uncrowded and puts the wand where it belongs — with the other selectors.
    private var regionSelectButtons: some View {
        selectionGroupButton
    }

    /// The tools in the shared selection slot, in cycle order.
    private static let selectionGroupTools: [Tool] = [.rectSelect, .ellipseSelect, .wand]

    private func selectionToolSymbol(_ tool: Tool) -> String {
        switch tool {
        case .ellipseSelect: "circle.dashed"
        case .wand: "wand.and.rays"
        default: "rectangle.dashed"
        }
    }

    private var selectionGroupButton: some View {
        let remembered = lastSelectionTool
        let isActive = editorState.activeTool.isRegionSelectionTool
        return Menu {
            Picker("Selection", selection: Binding(get: { lastSelectionTool },
                                                   set: { activateSelectionTool($0) })) {
                Label("Rectangle Select", systemImage: "rectangle.dashed").tag(Tool.rectSelect)
                Label("Ellipse Select", systemImage: "circle.dashed").tag(Tool.ellipseSelect)
                Label("Magic Wand", systemImage: "wand.and.rays").tag(Tool.wand)
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: selectionToolSymbol(remembered))
                .font(.system(size: 15, weight: .medium))
        } primaryAction: {
            activateSelectionTool(remembered)
        }
        .menuIndicator(.visible)
        .menuStyle(.button)
        .buttonStyle(.tool(isActive: isActive, in: toolbarNamespace))
        .fixedSize()
        .toolTip(remembered.barTitle, key: remembered == .wand ? "W" : "M",
                 fallback: "Selection: Rectangle / Ellipse / Magic Wand (M, ⇧M cycles, W wand). ⇧ add, ⌥ subtract, ⇧⌥ intersect.")
        // The shortcuts live on invisible stand-ins (Menu can't carry them):
        // M = the remembered selector, ⇧M = cycle, W = jump to the wand.
        .background {
            Group {
                Button("") { activateSelectionTool(lastSelectionTool) }
                    .keyboardShortcut("m", modifiers: [])
                Button("") { activateSelectionTool(cycledSelectionTool) }
                    .keyboardShortcut("m", modifiers: .shift)
                Button("") { activateSelectionTool(.wand) }
                    .keyboardShortcut("w", modifiers: [])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    /// The next tool when cycling the selection slot with ⇧M.
    private var cycledSelectionTool: Tool {
        let tools = Self.selectionGroupTools
        let idx = tools.firstIndex(of: lastSelectionTool) ?? 0
        return tools[(idx + 1) % tools.count]
    }

    /// The selection tool the grouped slot remembers (persisted by
    /// `EditorState`, which records every tool pick).
    private var lastSelectionTool: Tool {
        editorState.lastTool(in: .selection)
    }

    private func activateSelectionTool(_ tool: Tool) {
        editorState.setTool(tool)
    }

    /// Inert buttons for tools that land in later tasks/phases.
    private func placeholderButton(_ symbol: String, _ help: String) -> some View {
        Button {} label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
        }
        .buttonStyle(.tool())
        .disabled(true)
        .toolTip(help)
    }
}

/// The floating toolbar's measured natural width, read by the overflow loop in
/// `EditorView` to decide how many tools fit before the "…" menu takes over.
private struct ToolbarContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The tool settings capsule's measured size, read by every bottom overlay that
/// has to stack clear of it. `.zero` when there is no capsule, so nothing moves
/// for a tool with nothing to set.
private struct ToolSettingsSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width),
                       height: max(value.height, next.height))
    }
}

extension Color {
    /// Color from the document model's hex strings, via the tested RGBA parser.
    init(hex: String) {
        let rgba = RGBA(hex: hex) ?? RGBA(r: 1, g: 0, b: 0)
        self.init(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }
}

/// A Photoshop-style paint-bucket glyph (SF Symbols has no bucket): a tilted
/// bucket — elliptical rim, tapered body, small back handle loop — pouring
/// left, with a filled drop at the lip. Designed in a 20-unit box (numbers
/// visually tuned against a rendered preview); draws in the inherited
/// foreground style to match the SF tool icons.
struct PaintBucketIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height) / 20
            let dx = (proxy.size.width - 20 * s) / 2   // center the design box
            let tilt = -CGFloat.pi / 4.4
            let rotate = CGAffineTransform(translationX: dx + 11.6 * s, y: 9.6 * s)
                .rotated(by: tilt)

            let rim = Path(ellipseIn: CGRect(x: -4.4 * s, y: -5.4 * s,
                                             width: 8.8 * s, height: 3.0 * s))
                .applying(rotate)

            let bucket: Path = {
                var p = Path()
                p.move(to: CGPoint(x: -4.4 * s, y: -3.9 * s))
                p.addLine(to: CGPoint(x: -3.1 * s, y: 4.2 * s))
                p.addQuadCurve(to: CGPoint(x: 3.1 * s, y: 4.2 * s),
                               control: CGPoint(x: 0, y: 5.8 * s))
                p.addLine(to: CGPoint(x: 4.4 * s, y: -3.9 * s))
                return p
            }().applying(rotate)

            let handle: Path = {
                var p = Path()
                p.addArc(center: CGPoint(x: 3.4 * s, y: -5.6 * s), radius: 2.4 * s,
                         startAngle: .radians(.pi * 1.05), endAngle: .radians(.pi * 1.95),
                         clockwise: false)
                return p
            }().applying(rotate)

            // Filled drop just off the pouring lip (which lands at ≈(5.1, 9.3)).
            let dTip = CGPoint(x: dx + 3.9 * s, y: 11.0 * s)
            let dropR = 1.7 * s
            let dCenter = CGPoint(x: dTip.x, y: dTip.y + dropR * 1.4)
            let drop: Path = {
                var p = Path()
                p.move(to: dTip)
                p.addQuadCurve(to: CGPoint(x: dCenter.x - dropR, y: dCenter.y),
                               control: CGPoint(x: dCenter.x - dropR, y: dTip.y + dropR * 0.35))
                p.addArc(center: dCenter, radius: dropR,
                         startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
                p.addQuadCurve(to: dTip,
                               control: CGPoint(x: dCenter.x + dropR, y: dTip.y + dropR * 0.35))
                p.closeSubpath()
                return p
            }()

            ZStack {
                bucket.stroke(style: StrokeStyle(lineWidth: 1.15 * s, lineCap: .round, lineJoin: .round))
                rim.stroke(style: StrokeStyle(lineWidth: 1.15 * s, lineCap: .round, lineJoin: .round))
                handle.stroke(style: StrokeStyle(lineWidth: 1.0 * s, lineCap: .round))
                drop.fill()
            }
        }
    }
}

extension Tool {
    /// `Tool.shortcutKey` in SwiftUI's currency. The letter itself is a
    /// product decision and lives in PhotonzCore, where a test holds it still;
    /// this is only the type conversion.
    var keyEquivalent: KeyEquivalent? { shortcutKey.map { KeyEquivalent($0) } }
}
