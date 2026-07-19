import AppKit
import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @Environment(EditorState.self) private var editorState
    /// Capture/history live on the resident agent now; the in-editor history
    /// panel (phase-9 carousel) reads it until phase 11.4 replaces it with the
    /// global slide-down overlay.
    @Environment(AppCoordinator.self) private var coordinator
    @State private var isStylePopoverPresented = false
    /// The bespoke HSB color picker popover (13.2).
    @State private var isFgPickerShown = false
    @State private var isBgPickerShown = false
    @State private var isShapeFillPickerShown = false
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
    /// How many leading tools the floating toolbar currently shows; the rest sit
    /// in the "…" overflow menu. Driven by the measured-fit loop below.
    @State private var toolbarVisibleCount = ToolbarSlot.allCases.count
    /// The toolbar's measured natural width and the width available to it — the
    /// two inputs to the overflow loop. Real measurements, so no width estimate
    /// can be wrong (an earlier hand-computed version under-counted and clipped;
    /// a `ViewThatFits` version recursed to death inside `GlassEffectContainer`).
    @State private var toolbarContentWidth: CGFloat = 0
    @State private var toolbarBudget: CGFloat = 0

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
                        GlassEffectContainer {
                            toolbar
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ToolbarContentWidthKey.self,
                                                   value: proxy.size.width)
                        })
                    }
                    // Sidebar toggle, top-trailing — the in-window affordance to
                    // collapse/reveal the inspector (Xcode/Finder-style), and the
                    // way back when the panel has auto-collapsed on a narrow window.
                    .overlay(alignment: .topTrailing) {
                        if editorState.document != nil {
                            inspectorToggle(isShown: inspectorShown)
                                .padding(12)
                        }
                    }
                    .clipped()  // keep a transient over-wide toolbar off the panel
                    .onPreferenceChange(ToolbarContentWidthKey.self) { width in
                        toolbarContentWidth = width
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
            .animation(.spring(duration: 0.3), value: inspectorShown)
            // Auto-collapse the inspector below the width threshold, and restore
            // the user's preference when the window grows back. Runs on the
            // initial size too, so opening small starts collapsed.
            .onChange(of: geo.size.width, initial: true) { _, width in
                updateInspectorAutoCollapse(width: width)
            }
            // Keep the toolbar's fit budget current as the window / panel changes.
            .onChange(of: canvasWidth, initial: true) { _, width in
                toolbarBudget = max(0, width - 32)  // 16 inset each side
                reconcileToolbarCount()
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
        // Drop an image (history overlay thumbnail, Finder file, …): into an
        // open document it becomes a new layer; otherwise it opens as a document.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            editorState.addImageLayerOrOpen(at: url)
            return true
        }
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
    }

    @ViewBuilder
    private var canvas: some View {
        if editorState.document != nil {
            CanvasView(image: editorState.renderedImage,
                       viewport: editorState.viewport,
                       document: editorState.document,
                       selection: editorState.selection,
                       selectionTargetsPixels: editorState.selectionTargetsPixels,
                       cropRect: editorState.cropRect,
                       cropAspect: editorState.cropAspect,
                       cropBounds: editorState.cropBounds,
                       selectedLayerID: editorState.selectedLayerID,
                       selectedLayerFrame: editorState.selectedLayerFrame,
                       multiSelectedLayerIDs: editorState.multiSelectedLayerIDs,
                       dragPreview: editorState.dragPreview,
                       tool: editorState.activeTool,
                       annotationContent: editorState.activeAnnotationContent,
                       textContent: editorState.activeTextContent,
                       measureContent: editorState.measureStyle,
                       edgeMap: editorState.snappingEdgeMap,
                       onViewSizeChange: { editorState.canvasViewSizeChanged($0) },
                       onViewportChange: { editorState.setViewport($0) },
                       onSelectionChange: { editorState.setSelection($0, captureLayers: $1) },
                       onWandAt: { editorState.wandSelect(at: $0, mode: $1) },
                       onDeleteRegion: { editorState.deleteRegion() },
                       onRegionMoveBegin: { editorState.beginRegionMove(copy: $0) },
                       onRegionMoveCommit: { editorState.commitRegionMove(delta: $0) },
                       onRegionMoveCancel: { editorState.cancelRegionMove() },
                       onCropRectChange: { editorState.setCropRect($0) },
                       onCropCommit: { editorState.commitCrop() },
                       onSelectLayer: { editorState.selectLayer($0) },
                       onDragBegin: { editorState.beginLayerDrag(id: $0) },
                       onFramePreview: { editorState.previewLayerFrame(id: $0, frame: $1) },
                       onFrameCommit: { editorState.commitLayerFrame(id: $0, frame: $1) },
                       onTransformPreview: { editorState.previewLayerTransform(id: $0, transform: $1) },
                       onTransformCommit: { editorState.commitLayerTransform(id: $0, transform: $1) },
                       onAnnotationCommit: { editorState.addAnnotation(from: $0, to: $1) },
                       onAnnotationEndpointsCommit: { editorState.commitAnnotationEndpoints(id: $0, start: $1, end: $2) },
                       onZoomCalloutCommit: { editorState.addZoomCallout(from: $0, to: $1) },
                       onMeasureCommit: { editorState.addMeasure(from: $0, to: $1, mode: $2) },
                       onMeasureEndpointPreview: { editorState.previewMeasureEndpoints(id: $0, start: $1, end: $2) },
                       onMeasureEndpointCommit: { editorState.commitMeasureEndpoints(id: $0, start: $1, end: $2) },
                       onToolChange: { editorState.setTool($0) },
                       onTextEditBegin: { editorState.beginTextEdit(layerID: $0) },
                       onTextCommit: { editorState.commitTextEdit(layerID: $0, origin: $1, string: $2, maxWidth: $3) },
                       onTextCancel: { editorState.cancelTextEdit() },
                       onDeleteLayer: { editorState.deleteLayer(id: $0) },
                       onDeleteLayers: { editorState.deleteLayers(ids: $0) },
                       onDropImageURL: { editorState.addImageLayerOrOpen(at: $0) },
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
                       onCanvasResize: { size, anchor in
                           editorState.setCanvasSize(to: size, anchor: anchor)
                       },
                       onFillAt: { point, hit, useBackground in
                           editorState.fillLayer(at: point, hit: hit, useBackground: useBackground)
                       },
                       onFillSelected: { editorState.fillSelectedLayer(useBackground: $0) },
                       onClearBackground: { editorState.clearBackgroundLayer() })
        } else {
            emptyState
        }
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
                Text(shortcut)
                    .font(.callout.monospaced())
                    .foregroundStyle(.tertiary)
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
    /// from real measured widths, so nothing clips at the window edge.
    private var toolbar: some View {
        HStack(spacing: 10) {
            if toolbarVisibleCount >= ToolbarSlot.allCases.count {
                toolsBar
            } else {
                compactToolsBar(visibleCount: toolbarVisibleCount)
            }
            sideCapsules
        }
    }

    /// Grow or shrink the visible tool count by one step toward the largest set
    /// that fits `toolbarBudget`. Called whenever the measured content width or
    /// the available budget changes; converges over a couple of frames without
    /// oscillating (it only grows when one more tool would still fit).
    private func reconcileToolbarCount() {
        guard toolbarBudget > 0, toolbarContentWidth > 0 else { return }
        let maxCount = ToolbarSlot.allCases.count
        if toolbarContentWidth > toolbarBudget {
            if toolbarVisibleCount > 0 { toolbarVisibleCount -= 1 }
        } else if toolbarVisibleCount < maxCount,
                  toolbarContentWidth + 48 <= toolbarBudget {
            // 48 ≈ one tool + gap (worst case, the wider marquee slot). Only grow
            // when the extra tool is sure to still fit, so it can't ping-pong.
            toolbarVisibleCount += 1
        }
    }

    /// The color + zoom capsules, always present at the trailing end.
    private var sideCapsules: some View {
        HStack(spacing: 10) {
            colorBar
            zoomBar
        }
    }

    private var toolsBar: some View {
        HStack(spacing: 14) {
            toolButton(.select, "cursorarrow", "Select", "v")
            regionSelectButtons
            if editorState.activeTool == .wand {
                wandOptions
                    .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
            }
            toolButton(.arrow, "arrow.up.right", "Arrow", "a")
            toolButton(.line, "line.diagonal", "Line", "l")
            toolButton(.rectangle, "rectangle", "Rectangle", "r")
            toolButton(.ellipse, "circle", "Ellipse", "o")
            toolButton(.highlight, "highlighter", "Highlight", "h")
            toolButton(.text, "character.cursor.ibeam", "Text", "t")
            Divider().frame(height: 20)
            toolButton(.crop, "crop", "Crop", "c")
            if editorState.activeTool == .crop {
                cropOptions
                    .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
            }
            resizeButton
            toolButton(.zoomCallout, "plus.magnifyingglass", "Zoom Callout", "z")
            // I, not M: M is the Photoshop marquee (rect/ellipse select), and
            // Photoshop itself files the Ruler under I.
            toolButton(.measure, "ruler", "Measure", "i")
            toolButton(.fill, help: "Fill", key: "g") {
                PaintBucketIcon().frame(width: 22, height: 21)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
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

    /// The compact tool row used when the full set won't fit: the leading tools
    /// that fit, then a chevron overflow menu holding the rest, then the
    /// contextual options for the active tool (which stay reachable). The active
    /// tool is always kept out of the overflow so its options make sense.
    private func compactToolsBar(visibleCount: Int) -> some View {
        let all = ToolbarSlot.allCases
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
        .buttonStyle(.borderless)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
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
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More tools")
    }

    /// Contextual options for the active tool (wand tolerance, crop aspects). In
    /// the compact bar they sit at the trailing edge; the full bar keeps them
    /// inline. (The color/style swatch lives in the adaptive color capsule now.)
    @ViewBuilder private var contextualToolOptions: some View {
        if editorState.activeTool == .wand {
            wandOptions
        }
        if editorState.activeTool == .crop {
            cropOptions
        }
    }

    /// The image-resize button (not a `Tool`, so it isn't part of `setTool`).
    private var resizeButton: some View {
        Button {
            editorState.isResizeDialogPresented = true
        } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left.rectangle")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .disabled(editorState.document == nil)
        .help("Resize Image (⌥⌘I)")
    }

    /// The in-window sidebar toggle (top-trailing): collapse or reveal the
    /// docked inspector. Also the way back when the panel has auto-collapsed on
    /// a narrow window — tapping it forces the inspector open.
    private func inspectorToggle(isShown: Bool) -> some View {
        Button {
            if isShown {
                editorState.isLayersPanelVisible = false
                inspectorAutoHidden = false
            } else {
                editorState.isLayersPanelVisible = true
                inspectorAutoHidden = false // user override beats auto-collapse
            }
        } label: {
            Image(systemName: isShown ? "sidebar.trailing" : "sidebar.leading")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.borderless)
        .glassEffect(.regular, in: .capsule)
        .help(isShown ? "Hide Inspector (⌥⌘L)" : "Show Inspector (⌥⌘L)")
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

        /// Menu title when the slot is overflowed.
        var title: String {
            switch self {
            case .select: "Select"
            case .marquee: "Selection"
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
            }
        }

        /// SF Symbol for the overflow-menu row.
        var menuSymbol: String {
            switch self {
            case .select: "cursorarrow"
            case .marquee: "rectangle.dashed"
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
            }
        }

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
            case .marquee, .resize: nil
            }
        }
    }

    /// The slot matching the active tool (all region selectors fold to
    /// `.marquee`), so the compact bar keeps the active tool out of the overflow.
    private var activeSlot: ToolbarSlot? {
        let tool = editorState.activeTool
        if tool.isRegionSelectionTool { return .marquee }
        return ToolbarSlot.allCases.first { $0.tool == tool }
    }

    /// Inline button for a slot in the compact bar — same widgets the full bar
    /// uses, so the two stay visually identical for the tools that show.
    @ViewBuilder private func slotButton(_ slot: ToolbarSlot) -> some View {
        switch slot {
        case .select: toolButton(.select, "cursorarrow", "Select", "v")
        case .marquee: selectionGroupButton
        case .arrow: toolButton(.arrow, "arrow.up.right", "Arrow", "a")
        case .line: toolButton(.line, "line.diagonal", "Line", "l")
        case .rectangle: toolButton(.rectangle, "rectangle", "Rectangle", "r")
        case .ellipse: toolButton(.ellipse, "circle", "Ellipse", "o")
        case .highlight: toolButton(.highlight, "highlighter", "Highlight", "h")
        case .text: toolButton(.text, "character.cursor.ibeam", "Text", "t")
        case .crop: toolButton(.crop, "crop", "Crop", "c")
        case .resize: resizeButton
        case .zoomCallout: toolButton(.zoomCallout, "plus.magnifyingglass", "Zoom Callout", "z")
        case .measure: toolButton(.measure, "ruler", "Measure", "i")
        case .fill:
            toolButton(.fill, help: "Fill", key: "g") {
                PaintBucketIcon().frame(width: 22, height: 21)
            }
        }
    }

    /// Activate a slot picked from the overflow menu.
    private func activateSlot(_ slot: ToolbarSlot) {
        switch slot {
        case .marquee: activateSelectionTool(lastSelectionTool)
        case .resize: editorState.isResizeDialogPresented = true
        default: if let tool = slot.tool { editorState.setTool(tool) }
        }
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
        Button { isShapeFillPickerShown = true } label: {
            shapeSwatchLabel(hex: editorState.activeToolFillHex)
        }
        .help("Fill color — the shape's interior. Uncheck Fill for an outline.")
        .popover(isPresented: $isShapeFillPickerShown, arrowEdge: .top) {
            let off = editorState.activeToolFillHex == nil
            VStack(alignment: .leading, spacing: 14) {
                // A checkbox enables the fill; the picker stays visible but
                // disabled (dimmed) when it's off, so it's clear what it controls.
                Toggle("Fill", isOn: Binding(
                    get: { !off },
                    set: { on in
                        editorState.setAnnotationFillColor(on ? (editorState.activeToolFillHex ?? activeToolColorHex) : nil)
                    }))
                    .font(.callout)
                ColorPickerPopover(initialHex: editorState.activeToolFillHex ?? activeToolColorHex,
                                   recents: editorState.recentColors.colors,
                                   embedded: true) { editorState.setAnnotationFillColor($0) }
                    .disabled(off)
                    .opacity(off ? 0.4 : 1)
            }
            .padding(16)
        }
    }

    private var shapeBorderSwatch: some View {
        Button { isStylePopoverPresented.toggle() } label: {
            // Show the "none" slash when the box has no border.
            shapeSwatchLabel(hex: editedStrokeWidth > 0 ? activeToolColorHex : nil)
        }
        .help("Border color, width, and corner radius")
        .popover(isPresented: $isStylePopoverPresented, arrowEdge: .top) {
            stylePopover
        }
    }

    /// A rounded-rect swatch; a nil hex shows the white-with-red-slash "none".
    private func shapeSwatchLabel(hex: String?) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(hex.map { Color(hex: $0) } ?? Color.white)
            .frame(width: 18, height: 18)
            .overlay {
                if hex == nil {
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
            .help("Swap Fill Colors (X)")
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
            ColorPickerPopover(initialHex: hex, recents: editorState.recentColors.colors) { newHex in
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
            Slider(value: Binding(
                get: { Double(log2(editorState.displayZoom)) },
                set: { editorState.setDisplayZoom(CGFloat(pow(2, $0))) }),
                in: -5...5)
                .controlSize(.small)
                .frame(width: 110)
                .help("Zoom")
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
        .disabled(editorState.document == nil)
    }

    /// Aspect locks plus commit/cancel, shown while the crop tool is active.
    /// Wand tolerance: how far a color may drift (0–255 Euclidean RGBA) and
    /// still join the flood. Applies to the next wand click.
    private var wandOptions: some View {
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
        .help("Wand tolerance: how similar a color must be to join the selection")
    }

    private var cropOptions: some View {
        HStack(spacing: 6) {
            ForEach(CropAspect.allCases, id: \.self) { aspect in
                let isActive = editorState.cropAspect == aspect
                Button {
                    editorState.setCropAspect(aspect)
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

    /// The color the popover currently represents: the selected annotation's
    /// or callout's, the selected/edited text's, or what the active tool draws.
    private var activeToolColorHex: String {
        if let callout = editorState.selectedZoomCalloutLayer {
            return callout.style.borderColorHex
        }
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

    /// Stroke width applies to stroke shapes only — highlight is a fill.
    private var showsStrokeWidthRow: Bool {
        if editorState.selectedZoomCalloutLayer != nil {
            return true
        }
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
        editorState.selectedZoomCalloutLayer?.style.borderWidth
            ?? selectedAnnotation?.strokeWidth
            ?? editorState.annotationStyles.strokeWidth(for: editorState.activeTool)
    }

    /// The arrowhead-size row applies to arrows only.
    private var showsArrowheadRow: Bool {
        if editorState.selectedZoomCalloutLayer != nil { return false }
        if let selected = selectedAnnotation { return selected.shape == .arrow }
        return editorState.activeTool == .arrow
    }

    private var editedArrowheadScale: CGFloat {
        selectedAnnotation?.arrowheadScale ?? editorState.annotationStyles.arrowheadScale(for: editorState.activeTool)
    }

    /// Swatch showing the active tool's color; opens the style popover.
    private var styleButton: some View {
        Button {
            isStylePopoverPresented.toggle()
        } label: {
            Circle()
                .fill(Color(hex: activeToolColorHex))
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
                .frame(width: 28, height: 28)
        }
        .help(editorState.activeTool == .text ? "Text Style (S)" : "Annotation Style (S)")
        .keyboardShortcut("s", modifiers: [])
        .popover(isPresented: $isStylePopoverPresented, arrowEdge: .top) {
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
                // One consistent color control everywhere (swatches + recents +
                // HSB + hex + eyedropper).
                ColorPickerPopover(initialHex: activeToolColorHex,
                                   recents: editorState.recentColors.colors,
                                   embedded: true) { applyColor($0) }
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
            if editorState.selectedZoomCalloutLayer != nil {
                calloutInspector
            }
        }
        .padding(16)
        .buttonStyle(.plain)
        // The system popover chrome is already glass on macOS 26. Drawing our
        // own glass rect inside a cleared presentation background left a light
        // halo (the popover bezel) around the inner rect — let the system
        // material carry the surface instead.
    }

    /// Magnification + shape controls for the selected zoom callout. Color and
    /// width reuse the shared swatch/dot rows above.
    private var calloutInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(editorState.selectedCalloutMagnification ?? 2) },
                    set: { editorState.previewCalloutMagnification(CGFloat($0)) }),
                       in: 1.25...6) { editing in
                    if !editing { editorState.commitCalloutMagnification() }
                }
                Text(Double(editorState.selectedCalloutMagnification ?? 2)
                    .formatted(.number.precision(.fractionLength(1))) + "×")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            HStack(spacing: 6) {
                calloutShapeButton(.rectangle, "rectangle", "Rectangular callout")
                calloutShapeButton(.circle, "circle", "Circular callout")
            }
        }
        .frame(width: 220)
    }

    private func calloutShapeButton(_ shape: ZoomCalloutShape, _ symbol: String,
                                    _ help: String) -> some View {
        let isActive = editorState.selectedZoomCalloutLayer?.zoomCallout?.shape == shape
        return Button {
            editorState.setCalloutShape(shape)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .frame(width: 28, height: 24)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 6).fill(Color.accentColor)
                    }
                }
        }
        .help(help)
    }

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

    /// Routes a committed color pick to the bucket the popover is editing:
    /// the selected callout's border, the active/selected text, or the active
    /// annotation. Every path records the shared recents list (13.2).
    private func applyColor(_ hex: String) {
        if editorState.selectedZoomCalloutLayer != nil {
            editorState.setCalloutBorderColor(hex)
        } else if showsTextControls {
            editorState.setTextColor(hex)
        } else {
            editorState.setAnnotationColor(hex)
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
                    // Annotations preview live; callouts commit on release only
                    // (no preview path, so live updates would spam undo).
                    if editorState.selectedZoomCalloutLayer == nil {
                        editorState.previewAnnotationRestyle(strokeWidth: v.rounded())
                    }
                }
            ), in: AnnotationStyles.strokeWidthRange, onEditingChanged: { editing in
                if !editing {
                    let final = (strokeWidthDraft ?? editedStrokeWidth).rounded()
                    if editorState.selectedZoomCalloutLayer != nil {
                        editorState.setCalloutBorderWidth(final)
                    } else {
                        editorState.setAnnotationStrokeWidth(final)
                    }
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

    private func toolButton(_ tool: Tool, _ symbol: String, _ help: String,
                            _ key: KeyEquivalent) -> some View {
        toolButton(tool, help: help, key: key) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
        }
    }

    private func toolButton(_ tool: Tool, help: String, key: KeyEquivalent?,
                            modifiers: EventModifiers = [],
                            @ViewBuilder icon: () -> some View) -> some View {
        let isActive = editorState.activeTool == tool
        let shiftHint = modifiers.contains(.shift) ? "⇧" : ""
        let keyHint = key.map { " (\(shiftHint)\(String(describing: $0.character).uppercased()))" } ?? ""
        return Button {
            editorState.setTool(tool)
        } label: {
            icon()
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background {
                    if isActive {
                        Circle().fill(Color.accentColor)
                            .matchedGeometryEffect(id: "activeTool", in: toolbarNamespace)
                    }
                }
        }
        // Tools are sticky (17.12), so no double-click-to-lock is needed.
        .help("\(help)\(keyHint)")
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
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background {
                    if isActive {
                        Circle().fill(Color.accentColor)
                            .matchedGeometryEffect(id: "activeTool", in: toolbarNamespace)
                    }
                }
        } primaryAction: {
            activateSelectionTool(remembered)
        }
        .menuIndicator(.visible)
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .help("Selection: Rectangle / Ellipse / Magic Wand (M, ⇧M cycles, W wand). ⇧ add, ⌥ subtract, ⇧⌥ intersect.")
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

    /// The selection tool the grouped slot remembers (persisted).
    private var lastSelectionTool: Tool {
        let raw = UserDefaults.standard.string(forKey: "tool.marquee.last") ?? ""
        let tool = Tool(rawValue: raw)
        return tool?.isRegionSelectionTool == true ? (tool ?? .rectSelect) : .rectSelect
    }

    private func activateSelectionTool(_ tool: Tool) {
        UserDefaults.standard.set(tool.rawValue, forKey: "tool.marquee.last")
        editorState.setTool(tool)
    }

    /// Inert buttons for tools that land in later tasks/phases.
    private func placeholderButton(_ symbol: String, _ help: String) -> some View {
        Button {} label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .disabled(true)
        .help(help)
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
