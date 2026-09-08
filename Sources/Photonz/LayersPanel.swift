import AppKit
import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

extension RowClick {
    /// The Finder's reading of a click's modifier keys: shift ranges,
    /// command toggles, anything else is a plain click. Shift wins when
    /// both are held.
    init(modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift) { self = .extend }
        else if modifiers.contains(.command) { self = .toggle }
        else { self = .plain }
    }
}

extension Color {
    /// The document model's hex form of this color (alpha dropped); nil for
    /// colors outside sRGB.
    var hexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    /// This color's alpha, for the pickers that offer an opacity slider (the
    /// model stores alpha in its own field — hex strings never carry it).
    var alphaComponent: CGFloat {
        NSColor(self).usingColorSpace(.sRGB)?.alphaComponent ?? 1
    }
}

/// What the dock has measured of itself, which is everything `DockHeightBudget`
/// needs to decide who gives up room.
///
/// A value, and held in `@State` on purpose, unlike the drag and reveal scratch
/// next to it: those remember numbers nothing draws, while these numbers decide
/// how tall the sections are, so a change to one has to reach the next pass.
/// Nothing here depends on the heights the budget hands out — a body is
/// measured INSIDE its scroller, and the layers list reports what it would be
/// rather than what it got — so there is no loop between the two.
struct DockBudgetScratch: Equatable {
    /// How tall the dock's scrolling area is, nil until it has been laid out.
    var viewportHeight: CGFloat?
    var headers: [InspectorSectionID: CGFloat] = [:]
    /// What each body would like to be. For a list section this is the
    /// scrollable part alone.
    var bodies: [InspectorSectionID: CGFloat] = [:]
    /// The part of a list section's body that does NOT scroll with the list:
    /// the layers list's count line and grab bar.
    var listExtras: [InspectorSectionID: CGFloat] = [:]
}

// MARK: - Docked inspector panel

/// The full-height, docked right-side inspector (10.5). Holds collapsible,
/// drag-reorderable sections — Layers, Annotation, Effects, Shadow. Order and
/// collapsed state persist across launches; the panel width is set by the 1px
/// `InspectorResizeHandle` on its left edge.
struct InspectorPanel: View {
    @Environment(EditorState.self) private var editorState
    @AppStorage(InspectorPanel.sectionOrderKey) private var orderRaw = ""
    @AppStorage(InspectorPanel.collapsedKey) private var collapsedRaw = ""
    /// Which one-time section moves this panel's saved order has had. See
    /// `loadOrder`.
    @AppStorage(InspectorPanel.sectionOrderVersionKey) private var orderVersion = 0
    /// What the dock remembers about its own sections between launches, named
    /// so a scripted walk that rearranges them can put them back.
    static let sectionOrderKey = "inspector.sectionOrder"
    /// One section header's row: the height `CollapsibleSection` pins its
    /// header to. A 13 pt semibold title in 8 pt of padding each side.
    static let headerRowHeight: CGFloat = 32
    /// The dock's own padding above its first section.
    static let listTopPadding: CGFloat = 6
    /// How deep the fade is at the edge of a body the dock has shortened: the
    /// cue that there is more of it past the cut.
    static let bodyEdgeFade: CGFloat = 14
    /// The hairline under each section, which the dock pays for as surely as
    /// it pays for the header.
    static let sectionDividerHeight: CGFloat = 1
    /// The sections whose body is a LIST, and so may be shortened and scroll
    /// inside itself when the dock is over-subscribed.
    ///
    /// This is the whole of the list-versus-form judgment, in one place. A list
    /// is as long as the document happens to make it — however many layers,
    /// parts, measurements or shelf tiles there are — so nobody designed its
    /// height and shortening it costs a scroll you were going to do anyway. A
    /// FORM (Text, Position & Size, Effects, Arrange) is a set of controls
    /// somebody chose: shortening it compresses nothing, it just hides controls
    /// behind a second scroller, which is the same hunt one level deeper. So
    /// forms are paid first, at full height, and the lists share what is left.
    ///
    /// Which of Appearance and Effects is the list flipped with the split
    /// (`next-shape-parts`, 2026-09-07). Appearance became a FORM — opacity,
    /// fill, outline, corner radius, four rows somebody designed — and Effects
    /// became the list, as long as whatever you added to it. Left the other way
    /// round, two shadows squeezed Appearance until its Width and Corner Radius
    /// rows were scrolled out of sight, which is the opposite of what the dock
    /// is for.
    static var scrollingSections: Set<InspectorSectionID> {
        var sections: Set<InspectorSectionID> = [.layers, .measurements, .library]
        sections.insert(Experiments.shared.shapePartsEnabled ? .effects : .color)
        return sections
    }
    /// How short a list may be squeezed before the dock stops asking: about
    /// three rows. Under that a list stops reading as a list, and a dock that
    /// scrolls a little is better than six peepholes.
    static let listFloor: CGFloat = 112
    static let sectionOrderVersionKey = "inspector.sectionOrder.version"
    static let collapsedKey = "inspector.collapsed"
    /// Effects joined the Color section instead of trailing every per-kind one.
    private static let orderVersionEffectsWithColor = 1
    /// Component rose above Position & Size, so a copy says which version it is
    /// without being scrolled to.
    private static let orderVersionComponentAboveGeometry = 2
    /// ...and then every section named after the thing you picked followed it
    /// up there, so the panel opens on what you just clicked.
    private static let orderVersionPickedAboveGeometry = 3
    /// Appearance and Effects rose to sit directly under Layers, in that order.
    /// Asked for by the user on 2026-09-07 with the split between them: what a
    /// shape IS, then what you have added to it, both within reach without
    /// scrolling, because they are the two people touch on every layer.
    private static let orderVersionLookUnderLayers = 4
    /// The sections named after the thing you have picked, in the order they
    /// sit in. One list, so the migration and the rule stay the same sentence.
    private static let pickedSections: [InspectorSectionID] =
        [.annotation, .callout, .text, .measure, .collage, .canvas]
    @State private var order: [InspectorSectionID] = InspectorSectionID.allCases
    /// The section currently in the reader's hand, and where it is being
    /// carried. See `sectionDragChanged`.
    @State private var drag = SectionDrag()
    /// The measurements and the Escape watch a reorder needs, held by
    /// reference so keeping them up to date does not redraw the dock.
    @State private var dragScratch = SectionDragScratch()
    /// The Library's scope, so the picked item's section can be titled after
    /// what it is ("Media", "Component") rather than "Library Item".
    @AppStorage(LibraryPanel.scopeKey) private var libraryScopeRaw = LibraryScope.media.rawValue
    /// Scratch measurements for the Library reveal. A reference on purpose:
    /// see the note at the geometry reader.
    @State private var reveal = DockRevealScratch()
    /// Which sections have been built, so a new one can arrive a pass after
    /// the click rather than inside it. See `PanelSectionArrival`.
    @State private var arrivals = DockArrivals()
    /// Bumped to draw the pass that mounts the sections held back above. The
    /// value means nothing; changing it is the whole point.
    @State private var arrivalPass = 0
    /// What each section costs the dock, and how tall the dock is. Together
    /// these are the whole input to `DockHeightBudget`; see `dockBudget`.
    @State private var budget = DockBudgetScratch()

    var body: some View {
        // The sections the selection asks for, and the ones the dock may draw
        // this pass. They are the same list except in the pass right after a
        // click that brings new sections in, when the canvas gets the frame to
        // itself and the panel follows in the next one.
        let wanted = orderedAvailableSections
        let sections = arrivals.showing(wanted)
        let _ = arrivalPass // the catch-up pass reads its own trigger
        // How tall each list section may be drawn, so that the forms under it
        // stay where they are instead of being carried off the bottom.
        let ceilings = dockCeilings(sections)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.self) { id in
                        VStack(alignment: .leading, spacing: 0) {
                            CollapsibleSection(
                                title: sectionTitle(id),
                                isCollapsed: isCollapsed(id),
                                onToggle: { toggleCollapsed(id) },
                                onReorder: { pointerY, carriedBy in
                                    sectionDragChanged(id, pointerY: pointerY,
                                                       carriedBy: carriedBy, in: sections)
                                },
                                onReorderEnd: { endSectionDrag(in: sections) },
                                accessory: sectionAccessory(id),
                                // The layers list bounds itself — it has had
                                // its own scroller and grab bar since long
                                // before the dock had a budget — so the
                                // ceiling reaches it through `LayersListView`
                                // instead of through a second scroller round
                                // the outside of the one it already has.
                                bodyCeiling: id == .layers ? nil : ceilings[id],
                                onBodyHeight: { height in
                                    guard id != .layers else { return }
                                    budget.bodies[id] = height
                                },
                                onHeaderHeight: { budget.headers[id] = $0 }
                            ) {
                                sectionContent(id, ceiling: ceilings[id])
                            }
                            // The hairline belongs to the section above it, so
                            // a section lifted off the panel takes its line
                            // with it instead of leaving one hanging in the
                            // gap it left behind.
                            Divider().opacity(drag.section == id ? 0 : 0.4)
                        }
                        // Where this section sits inside the dock: for the
                        // reveal below, and for a reorder, which reads every
                        // section's resting place the moment one is picked up.
                        // Kept OUTSIDE @State on purpose: this fires on every
                        // scroll tick, and re-drawing the whole dock to
                        // remember a number nothing draws is the jank the
                        // comment further down is about.
                        .onGeometryChange(for: CGRect.self) {
                            $0.frame(in: .named(inspectorDockSpace))
                        } action: { frame in
                            recordInspectorSection(id, title: sectionTitle(id), frame: frame)
                            // Mid-drag a section is standing somewhere it does
                            // not live, so its measurement is worth nothing:
                            // the spans a reorder reads were taken before it
                            // started.
                            if drag.section == nil { dragScratch.frames[id] = frame }
                            guard id == .library else { return }
                            reveal.libraryFrame = frame
                            if reveal.isPending { applyLibraryReveal(proxy) }
                        }
                        // A section in your hand is off the surface: it wears a
                        // card and a shadow, and it draws over its neighbours.
                        .background { sectionLift(id) }
                        .zIndex(drag.section == id ? 1 : 0)
                        // Two offsets, and the order matters. The sections
                        // moving aside SLIDE, so their offset is animated; the
                        // one in your hand must not, because an animation
                        // between the pointer and the section is lag.
                        .offset(y: sectionSlide(id, in: sections))
                        .animation(.spring(duration: 0.24), value: drag.target)
                        .offset(y: drag.section == id ? drag.carriedBy : 0)
                        // FILES ONLY. Reordering is this panel's own gesture,
                        // not a drop, so a section being carried never reaches
                        // the drop machinery and can never light up the marks
                        // that answer for a file.
                        .onDrop(of: FileDrop.types,
                                delegate: SectionFileDrop(item: id, editorState: editorState))
                    }
                }
                .padding(.vertical, InspectorPanel.listTopPadding)
                // NO implicit animation on the section SET (10.7). Animating
                // section insert/remove forces the whole .regularMaterial panel to
                // re-blur and an NSColorWell to animate in/out every frame for the
                // spring's duration — ~350ms of pegged CPU per selection that
                // crosses between an annotation and a non-annotation layer (the
                // Annotation section toggles). Showing/hiding sections instantly
                // drops that to ~20ms. Collapse (chevron) and drag-reorder keep
                // their own explicit `withAnimation`, so they still animate.
            }
            .coordinateSpace(.named(inspectorDockSpace))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                reveal.viewportHeight = $0
                budget.viewportHeight = $0
                recordInspectorViewportHeight($0)
            }
            // Where the dock sits in the window. Only a scripted walk reads
            // it, to put a pointer on a section; it is a no-op in the
            // shipping build.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                recordInspectorDockFrame($0)
                // The edge every icon on the right of the panel is measured
                // against, so a walk reads "22.5pt in from the edge" rather
                // than a window coordinate that means nothing on its own.
                recordPanelEdgeFrame($0)
            }
            .inspectorLayoutProbe(sections: sections)
            // A section the selection asked for that has not been built yet
            // gets the next pass to itself. Departures are already on screen by
            // now (they leave in the click's own pass), so this only ever fires
            // for arrivals, and a click that keeps the same sections — moving
            // the selection from one group to another — never reaches it at all.
            .onChange(of: wanted) { _, latest in
                guard arrivals.isWaiting(for: latest) else { return }
                DispatchQueue.main.async {
                    arrivals.allow(latest)
                    arrivalPass &+= 1
                }
            }
            // The app opened the Library for you: put it where you can see it.
            // On appear too, because showing the shelf opens the dock as well,
            // and then this panel is born with the request already waiting.
            .onChange(of: editorState.pendingLibraryReveal) { requestLibraryReveal(proxy) }
            .onAppear { requestLibraryReveal(proxy) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
        // The panel answering for a file let go where it has no other target:
        // the empty space under the last section, and the gaps between them.
        // Registered for FILES ONLY, so a section header or a layer row dragged
        // out here still falls through to the window exactly as it did before.
        .onDrop(of: FileDrop.types, delegate: PanelFileDrop(editorState: editorState))
        // What the panel is about to do with what you are holding. Drawn over
        // everything and hit-testing nothing, so it cannot swallow the drag it
        // is describing.
        .overlay {
            PanelDropAffordance(offer: editorState.panelDropOffer)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.12), value: editorState.panelDropOffer)
        .onAppear(perform: loadOrder)
        .onChange(of: order) { persistOrder() }
        // A panel that goes away mid-drag takes its key watch with it.
        .onDisappear(perform: stopWatchingForEscape)
        // Only a scripted walk reads these; both are no-ops in the shipping
        // build. A walk cannot drive the header's gesture — SwiftUI does not
        // answer synthesized mouse events, which is the same wall
        // `dragComponent` and `scrollPanel` hit — so it carries a section by
        // calling the very handlers the gesture calls.
        .onChange(of: drag.section) { _, id in
            recordInspectorCarrying(id.map(sectionTitle))
        }
        .inspectorSectionDragProbe(
            carry: { id, pointerY, carriedBy in
                sectionDragChanged(id, pointerY: pointerY, carriedBy: carriedBy, in: sections)
            },
            end: { endSectionDrag(in: sections) },
            cancel: cancelSectionDrag,
            sections: sections)
    }

    // MARK: Sharing out the height the dock has

    /// How tall each list section may be drawn, given what the forms in the
    /// dock cost and how tall the dock is.
    ///
    /// A section is absent from the result when it may be drawn whole, which is
    /// every case where the panel fits, so the common dock is exactly the dock
    /// it always was — no extra scrollers, no frames pinned to a measurement
    /// taken a pass ago.
    private func dockCeilings(_ sections: [InspectorSectionID]) -> [InspectorSectionID: CGFloat] {
        let groups = sections.map { id -> DockHeightBudget.Group in
            let header = budget.headers[id] ?? InspectorPanel.headerRowHeight
            let open = !isCollapsed(id)
            let body = open ? (budget.bodies[id] ?? 0) : 0
            let scrolls = open && InspectorPanel.scrollingSections.contains(id)
            // A list pays for the chrome that does not scroll with it up
            // front; a form pays for its whole body up front, because none of
            // it may be taken away.
            let paid = scrolls ? (budget.listExtras[id] ?? 0) : body
            return DockHeightBudget.Group(key: id.rawValue,
                                          fixed: header + InspectorPanel.sectionDividerHeight + paid,
                                          flexible: scrolls ? body : 0,
                                          floor: InspectorPanel.listFloor)
        }
        // The dock's own padding above the first section and below the last is
        // room no section can have.
        let room = budget.viewportHeight.map { $0 - 2 * InspectorPanel.listTopPadding }
        let heights = DockHeightBudget.flexibleHeights(groups, viewport: room)
        var ceilings: [InspectorSectionID: CGFloat] = [:]
        for id in sections {
            guard let height = heights[id.rawValue],
                  // Only when it is actually being shortened. A section given
                  // exactly its own height gains nothing from a scroller.
                  height < (budget.bodies[id] ?? 0) - PanelAreaResize.tolerance else { continue }
            ceilings[id] = height
        }
        return ceilings
    }

    // MARK: Bringing the Library into view

    /// The app has opened the Library shelf (View ▸ Show Library, or a command
    /// that fills it, like making a component). Bring it into view.
    ///
    /// A shelf already on screen must not move: pressing the same menu item
    /// twice should not make the dock jump. `DockReveal` makes that call, from
    /// the measured frame, once layout has one.
    private func requestLibraryReveal(_ proxy: ScrollViewProxy) {
        guard editorState.pendingLibraryReveal,
              Experiments.shared.libraryEnabled, editorState.isLibraryVisible else { return }
        // A collapsed shelf scrolled into view is a header and nothing else,
        // which is not "you can see it". Instantly, without the collapse
        // spring, so the reveal scrolls to a height that has stopped moving.
        expand(.library)
        reveal.isPending = true
        // The section may have appeared with this very state change, in which
        // case the measurement above lands first and this finds nothing left to
        // do. When it was already there and stationary, this is the only path.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { applyLibraryReveal(proxy) }
    }

    private func applyLibraryReveal(_ proxy: ScrollViewProxy) {
        guard reveal.isPending, let frame = reveal.libraryFrame else { return }
        let action = DockReveal.action(sectionTop: frame.minY,
                                       sectionHeight: frame.height,
                                       viewportHeight: reveal.viewportHeight)
        reveal.isPending = false
        editorState.libraryRevealHandled()
        guard action != .none else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            proxy.scrollTo(InspectorSectionID.library, anchor: action == .top ? .top : .bottom)
        }
    }

    private var selectedLayer: Layer? {
        guard let id = editorState.selectedLayerID else { return nil }
        return editorState.document?.layer(id: id)
    }

    /// Sections currently applicable: Layers always; Effects/Shadow when a layer
    /// is selected; Annotation only for annotation layers.
    private var availableSections: Set<InspectorSectionID> {
        var set: Set<InspectorSectionID> = [.layers]
        // Lining layers up (`next-align-layers`). Present only with something
        // to line up: two or more layers picked, or one layer inside a frame,
        // which has the frame to answer to. A lone layer on the canvas has
        // nothing, so the section is absent rather than a row of dead buttons.
        if Experiments.shared.alignLayersEnabled, editorState.canAlignSelection {
            set.insert(.arrange)
        }
        // Where the selected layers sit and how big they are, as numbers you
        // can type (Next, `next-geometry-fields`). Every layer kind has a
        // position, so this shows for all of them, and it speaks for the whole
        // selection: pick four buttons and one typed width reaches all four.
        // Which of the four fields accept typing is `LayerGeometryEditing`'s
        // call.
        // A live marquee brings the section up on its own, with or without a
        // layer picked: while a selection tool has the arrow keys the numbers
        // are the selection's, and a marquee swept over an empty canvas would
        // otherwise have nowhere to report its size.
        if Experiments.shared.geometryFieldsEnabled,
           editorState.hasLayerSelection || editorState.regionGeometry != nil {
            set.insert(.geometry)
        }
        // Every color the picked layers have, in ONE place. Present as soon as
        // anything with a color is picked, one layer or twenty: a color that
        // moved to a different section the moment you shift-clicked a second
        // layer was a color you had to find again for no reason.
        if Experiments.shared.shapePartsEnabled {
            // One list of the parts the picked layers paint (`next-shape-parts`),
            // in the same slot the Color section held: it IS the Color section,
            // widened to hold each colour's switch and settings beside it.
            if !editorState.layerPartRows.isEmpty { set.insert(.color) }
        } else if !editorState.colorRowSlots.isEmpty {
            set.insert(.color)
        }
        // Fade, blur, corners, border and shadow, for EVERYTHING picked. Like
        // the Color rows above, these speak for the whole selection: one pull
        // on Corner Radius rounds four buttons rather than sending you round
        // four times. Absent only when nothing picked can be restyled, which
        // is a selection of locked layers and nothing else.
        if editorState.hasRestylableSelection {
            set.insert(.effects)
            // The shadow is a PART, and with `next-shape-parts` on it is a row
            // in the parts list with the fill and the outline rather than a
            // section of its own with a switch nothing else has.
            if !Experiments.shared.shapePartsEnabled { set.insert(.shadow) }
        }
        // The picked shapes' own settings: thickness, corners, an arrow's head
        // and caption — for EVERYTHING picked, like the rows above. Present
        // whenever the picked shapes share at least one setting, so two arrows
        // keep their settings instead of losing them the moment a second one
        // is picked, and a highlight (which has nothing but a color) still
        // brings no section rather than an empty one headed with its name.
        if !AnnotationInspector.visibleRows(editorState.shapeSelection).isEmpty {
            set.insert(.annotation)
        }
        // And the picked text's own type: font, size, weight, alignment. Three
        // labels made 14pt should be one trip round the panel.
        if !editorState.textSelection.isEmpty {
            set.insert(.text)
        }
        if let layer = selectedLayer {
            // A frame's own properties: its size, its clipping, its surface
            // (Next, `next-frames`). Only a frame has any of them.
            if Experiments.shared.framesEnabled, layer.isFrame {
                set.insert(.frame)
            }
            // A main component's own section (Next, `next-components`): its
            // name, which is the one name the layers list and the shelf both
            // print. Only a main has one.
            // ...and so does a piece INSIDE a copy, which is where somebody
            // who clicked into one to change its words has just landed. The
            // section is the only thing on the panel that can tell them the
            // piece is not theirs to change and what is.
            // (A copy gets the same slot, however many are picked; that is the
            // whole-selection test below rather than this one-layer one.)
            // ...and a piece inside an ORIGINAL whose component holds more
            // than one drawing, because that is where somebody who has just
            // rounded a corner is standing when they wonder whether they now
            // have to do it twice more (`ComponentVersionMatching`).
            if Experiments.shared.componentsEnabled,
               layer.isMainComponent || editorState.selectedComponentPiece != nil
                || editorState.componentVersionApply != nil {
                set.insert(.component)
            }
            // A picked callout's own settings. Present whenever one is
            // picked, the way Color and Effects are: what a callout magnifies
            // is a property of the callout, not of the tool in your hand.
            if layer.zoomCallout != nil { set.insert(.callout) }
            if layer.measure != nil { set.insert(.measure) }
            if layer.collage != nil { set.insert(.collage) }
        }
        // Where the picked layers sit when the thing holding them is resized
        // (Next, `next-placement`) — for EVERYTHING picked, like the Color and
        // Effects rows above. Picking a second layer used to take the whole
        // section off the panel, so three buttons in a bar had to be stretched
        // one at a time; the section leaves only when nothing picked has a
        // place in anything. A picked GROUP also brings it for what it holds,
        // one group or three, which is the Contents half of the same section.
        if Experiments.shared.placementEnabled,
           editorState.placementSelection.isPresent || editorState.contentsSelection.isPresent {
            set.insert(.placement)
        }
        // The picked copies' own section, saying which original they follow and
        // holding the knobs it exposes — for EVERYTHING picked, like the Color
        // and Effects rows above. Picking a second copy used to take the whole
        // section off the panel, so five buttons had to be set one at a time;
        // the section leaves only when nothing picked is a copy at all.
        if Experiments.shared.componentsEnabled, editorState.componentKnobSelection.isPresent {
            set.insert(.component)
        }
        // The columns of the screen you are working on (Next, `next-frames`),
        // right under Frame. Present for the screen itself AND for a button on
        // it, because the columns belong to the screen either way and Layer ▸
        // Show Columns has always acted on it either way: the section used to
        // go the moment you picked something on the screen, so the same
        // feature was half there depending on what you clicked last. When the
        // screen is not the thing picked, the header says whose numbers these
        // are.
        if editorState.columnsTargetFrameID != nil {
            set.insert(.columns)
        }
        if editorState.isCanvasSelected { set.insert(.canvas) }
        // The Library shelf (step B3, `next-library`): an ordinary panel group,
        // present only once View ▸ Show Library has asked for it. With it
        // off the dock is exactly the dock someone who only redlines has today.
        if Experiments.shared.libraryEnabled, editorState.isLibraryVisible,
           editorState.document != nil {
            set.insert(.library)
            // ...and the picked tile's own section, the way a picked layer
            // brings its sections. Nothing picked, nothing shown.
            if editorState.selectedLibraryItemID != nil { set.insert(.libraryItem) }
        }
        // The Measurements group (§6, `next-measure-panel`): a filtered view of
        // the layer stack, present whenever the document holds a measurement.
        if Experiments.shared.measurePanelEnabled, editorState.measurementCount > 0 {
            set.insert(.measurements)
        }
        // The Measure tool's own properties (D15): Snap and Show are settings,
        // not modes, so they left the tool bar and live here while the tool is
        // in hand. The Mode row is a deliberate echo of the button's flyout —
        // the flyout is the fast path, this is where the live mode is readable
        // as a word rather than a glyph.
        if editorState.activeTool == .measure, MeasureToolInspector.hasAnySetting {
            set.insert(.measureTool)
        }
        // The Magic Wand's own properties (D15): tolerance is a setting, not a
        // mode, so it left the tool bar and lives here while the wand is in
        // hand.
        if editorState.activeTool == .wand, Experiments.shared.toolOptionsEnabled {
            set.insert(.wandTool)
        }
        // Crop's aspect lock, in words. The tool button's flyout is the fast
        // path; D15 asks that the live mode stay readable somewhere as a word,
        // because a glyph says what the next drag does and does not remind you
        // three minutes later.
        if editorState.activeTool == .crop, Experiments.shared.toolOptionsEnabled {
            set.insert(.cropTool)
        }
        // The Zoom Callout tool's shape, while the tool is in hand
        // (`next-callout-shape`). Same test as the wand's tolerance: it changes
        // what the drag produces, not what the pointer does, so it is a setting
        // and settings live here.
        if editorState.activeTool == .zoomCallout, CalloutToolInspector.hasAnySetting {
            set.insert(.calloutTool)
        }
        // A piece INSIDE a copy owns nothing. Its size, its colors, its type
        // and its effects all come from the original and are written back over
        // on the next redraw, so a panel full of those controls is a panel full
        // of edits that get thrown away. It answers through the copy's knobs
        // instead, and the Component section is where they are.
        if editorState.selectedComponentPiece != nil {
            set.subtract(Self.sectionsAPieceDoesNotOwn)
        }
        return set
    }

    /// What a piece inside a copy does not answer for. Everything here is a
    /// fact the original decides.
    private static let sectionsAPieceDoesNotOwn: Set<InspectorSectionID> = [
        .arrange, .geometry, .frame, .columns, .placement, .color, .effects, .shadow,
        .annotation, .callout, .text, .measure, .collage,
    ]

    private var orderedAvailableSections: [InspectorSectionID] {
        let available = availableSections
        return order.filter { available.contains($0) }
    }

    /// Header furniture for sections that carry any: the Measurements group's
    /// count badge and panel menu (§6), and the Library's scope, so a
    /// collapsed Library still says what it is set to.
    private func sectionAccessory(_ id: InspectorSectionID) -> AnyView? {
        switch id {
        case .effects where Experiments.shared.shapePartsEnabled:
            // The plus that makes Effects a list you add to. It rides the
            // HEADER rather than the foot of the list, because the dock gives a
            // section a height and scrolls the rest inside it: one shadow is
            // already enough to push a foot button out of sight, and the one
            // gesture that adds an effect may never be the thing you have to go
            // looking for.
            return AnyView(AddEffectButton())
        case .measurements:
            return AnyView(MeasurementsSectionAccessory())
        case .library:
            let scope = LibraryScope(rawValue: libraryScopeRaw) ?? .media
            return AnyView(Text(scope.title)
                .font(.caption)
                .foregroundStyle(.secondary))
        case .columns:
            // Whose columns these are, when they are not the picked thing's
            // own. Beside the title so a collapsed section says it too.
            guard !editorState.isColumnsTargetSelected,
                  let frame = editorState.columnsTargetFrame else { return nil }
            return AnyView(Text(FrameColumnsCopy.belongsTo(frame.name))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail))
        default:
            return nil
        }
    }

    /// A section's header text.
    ///
    /// Most sections are named after what they are. The ones that describe the
    /// thing you have picked are named after IT, because a header reading
    /// "Annotation" over a rectangle's settings is a word out of the code:
    /// nothing on screen is called an annotation, and the person looking at it
    /// has selected a rectangle. Reported by the user on 2026-09-03.
    private func sectionTitle(_ id: InspectorSectionID) -> String {
        if id == .libraryItem {
            return (LibraryScope(rawValue: libraryScopeRaw) ?? .media).itemTitle
        }
        // With the parts list on, this section is no longer only colours: it
        // holds every part the picked layers paint, each with its switch and
        // its own settings. Appearance is what it is.
        if id == .color, Experiments.shared.shapePartsEnabled { return "Appearance" }
        // The numbers under this header belong to the marquee while a
        // selection tool has the arrow keys, so the header says so: a person
        // reading "Position & Size" over a layer's name would take them for
        // the layer's.
        if id == .geometry, editorState.regionGeometry != nil { return "Selection" }
        guard Experiments.shared.colorStylesEnabled else { return id.title }
        switch id {
        case .annotation:
            // The picked shapes' own name: Rectangle for one, Rectangles for
            // several, Shapes for a mixture.
            return editorState.shapeSelection.title
        case .measure:
            // What is selected is a measurement, not the act of measuring.
            // (The Measure Tool section, which IS about the act, keeps its
            // name, and the Measurements list keeps its plural.)
            return "Measurement"
        default:
            return id.title
        }
    }

    @ViewBuilder
    private func sectionContent(_ id: InspectorSectionID, ceiling: CGFloat?) -> some View {
        switch id {
        case .layers:
            // The one section that bounds itself: it is handed the dock's
            // ceiling and applies it to its rows, so its count line and grab
            // bar stay put instead of scrolling away with them.
            LayersListView(dockCeiling: ceiling,
                           onMetrics: { natural, extras in
                               budget.bodies[.layers] = natural
                               budget.listExtras[.layers] = extras
                           })
        case .measurements:
            MeasurementsListView()
        case .arrange:
            ArrangeInspector()
        case .geometry:
            GeometryInspector()
        case .measureTool:
            MeasureToolInspector()
        case .wandTool:
            WandToolInspector()
        case .cropTool:
            CropToolInspector()
        case .calloutTool:
            CalloutToolInspector()
        case .frame:
            if let layer = selectedLayer, layer.isFrame {
                FrameInspector(layer: layer)
            }
        case .columns:
            // The screen picked, or the screen what you picked is on.
            if let frame = editorState.columnsTargetFrame {
                FrameColumnsInspector(layer: frame)
            }
        case .placement:
            // One layer picked or five: the same section, the same rows, each
            // one answering for all of them.
            PlacementInspector(layer: selectedLayer)
        case .component:
            if let layer = selectedLayer, layer.isMainComponent {
                ComponentInspector(layer: layer)
            } else if case let selection = editorState.componentKnobSelection, selection.isPresent {
                // One copy picked or five: the same section, the same rows,
                // each one answering for all of them.
                ComponentInstanceInspector(selection: selection)
            } else if let piece = editorState.selectedComponentPiece {
                // Clicked into a copy: the section answers for the COPY, not
                // for the piece, because the piece has nothing of its own.
                ComponentPieceInspector(piece: piece)
            } else if let plan = editorState.componentVersionApply {
                // Clicked into an ORIGINAL that has other versions. The piece
                // itself is edited by every ordinary control above; the one
                // thing this section adds is the way that edit reaches the
                // other drawings.
                ComponentVersionPieceInspector(plan: plan)
            }
        case .color:
            if Experiments.shared.shapePartsEnabled {
                PartsInspector()
            } else {
                SelectionColorInspector()
            }
        case .annotation:
            AnnotationInspector()
        case .callout:
            if let layer = selectedLayer, layer.zoomCallout != nil {
                CalloutInspector(layer: layer)
            }
        case .text:
            TextInspector()
        case .measure:
            if let layer = selectedLayer, layer.measure != nil {
                MeasureInspector(layer: layer)
            }
        case .collage:
            if let layer = selectedLayer, layer.collage != nil {
                CollageInspector(layer: layer)
            }
        case .canvas:
            if editorState.isCanvasSelected {
                CanvasInspector()
            }
        case .effects:
            // Appearance is what a shape IS and Effects is what you ADD, so
            // with the split on this section is the list rather than four
            // sliders that are always there (`next-shape-parts`).
            if Experiments.shared.shapePartsEnabled {
                EffectsListInspector()
            } else {
                EffectsInspector()
            }
        case .shadow:
            ShadowInspector()
        case .library:
            // Deliberately NOT `.equatable()`. A shelf saying it is the same
            // as any other shelf was true of the value and false of what it
            // draws: the panel's own scope and search box live in `@State` and
            // `@AppStorage`, so an always-true `==` let SwiftUI keep the tile
            // grid it built first. Switching from Media to Components moved
            // the tab, the header and the search box and left the old tiles
            // sitting under them (2026-09-03). Sparing the shelf a re-run has
            // to start from what the shelf is actually made of.
            LibraryPanel()
        case .libraryItem:
            // The picked tile's section, named and filled by the scope it came
            // from: a capture's details, or a component's.
            if editorState.selectedComponentLayer != nil {
                LibraryComponentInspector()
            } else if editorState.selectedStarterComponent != nil {
                StarterComponentInspector()
            } else if editorState.selectedColorStyle != nil {
                LibraryStyleInspector()
            } else {
                LibraryItemInspector()
            }
        }
    }

    // MARK: Persistence

    private func loadOrder() {
        // Sections added after this panel's order was last saved get spliced in
        // at their canonical position rather than dumped at the bottom, so a new
        // section lands where it was designed to sit for people who have already
        // run the app (which is everyone).
        var merged = PanelSectionOrder.merged(
            saved: orderRaw.split(separator: ",").map(String.init),
            canonical: InspectorSectionID.allCases.map(\.rawValue))
        // A section that shipped in the wrong place has to reach the people who
        // already ran the app, and every one of them has an order saved (the
        // panel writes one on first launch). So each fix is a numbered, one-time
        // move of that ONE section, leaving any arrangement they made by hand
        // around it alone.
        if orderVersion < Self.orderVersionEffectsWithColor {
            merged = PanelSectionOrder.moving(InspectorSectionID.effects.rawValue,
                                              after: InspectorSectionID.color.rawValue,
                                              in: merged)
            orderVersion = Self.orderVersionEffectsWithColor
        }
        if orderVersion < Self.orderVersionComponentAboveGeometry {
            merged = PanelSectionOrder.moving(InspectorSectionID.component.rawValue,
                                              before: InspectorSectionID.geometry.rawValue,
                                              in: merged)
            orderVersion = Self.orderVersionComponentAboveGeometry
        }
        if orderVersion < Self.orderVersionPickedAboveGeometry {
            merged = PanelSectionOrder.moving(Self.pickedSections.map(\.rawValue),
                                              before: InspectorSectionID.geometry.rawValue,
                                              in: merged)
            orderVersion = Self.orderVersionPickedAboveGeometry
        }
        // Next only: it is the split that makes Appearance short enough to sit
        // up here, so the release without the split keeps its order.
        if Experiments.shared.shapePartsEnabled, orderVersion < Self.orderVersionLookUnderLayers {
            merged = PanelSectionOrder.moving(
                [InspectorSectionID.color.rawValue, InspectorSectionID.effects.rawValue],
                after: InspectorSectionID.layers.rawValue, in: merged)
            orderVersion = Self.orderVersionLookUnderLayers
        }
        let ids = merged.compactMap { InspectorSectionID(rawValue: $0) }
        if ids != order { order = ids }
    }

    private func persistOrder() {
        orderRaw = order.map(\.rawValue).joined(separator: ",")
    }

    // MARK: Picking a section up

    /// How far the section being carried is drawn from where it rests, and how
    /// far each section it has passed has slid to open the gap.
    private func sectionSlide(_ id: InspectorSectionID,
                              in sections: [InspectorSectionID]) -> CGFloat {
        guard drag.section != nil, let index = sections.firstIndex(of: id) else { return 0 }
        return SectionReorderDrag.offset(of: index, dragging: drag.from,
                                         target: drag.target, spans: drag.spans)
    }

    /// The card a section wears while it is in your hand: a solid surface and a
    /// shadow under it, so it reads as lifted off the panel rather than drawn
    /// on it.
    @ViewBuilder
    private func sectionLift(_ id: InspectorSectionID) -> some View {
        if drag.section == id {
            RoundedRectangle(cornerRadius: 8)
                .fill(.thickMaterial)
                .shadow(color: .black.opacity(0.32), radius: 14, y: 6)
                .padding(.horizontal, 4)
        }
    }

    /// The section being carried has moved. The first call is the pick-up: it
    /// takes down where every section is standing, so the lines the drag reads
    /// against stay still while the sections themselves slide.
    ///
    /// - Parameters:
    ///   - pointerY: the pointer, measured down from the top of the dock's
    ///     visible area.
    ///   - carriedBy: how far the pointer has travelled since the pick-up,
    ///     vertically. The sideways part is dropped on purpose: a section moves
    ///     up and down its own column and cannot be pulled out of it.
    private func sectionDragChanged(_ id: InspectorSectionID, pointerY: CGFloat,
                                    carriedBy: CGFloat, in sections: [InspectorSectionID]) {
        // Escape has already put this one back. Nothing else happens until the
        // button comes up.
        guard !drag.cancelled else { return }
        if drag.section == nil {
            guard let from = sections.firstIndex(of: id) else { return }
            let spans = sections.map {
                SectionReorderDrag.Span(top: dragScratch.frames[$0]?.minY ?? 0,
                                        height: dragScratch.frames[$0]?.height ?? 0)
            }
            // A dock nothing has measured yet cannot say what the pointer is
            // passing, so it does not move at all.
            guard spans.allSatisfy({ $0.height > 0 }) else { return }
            drag.section = id
            drag.sections = sections
            drag.from = from
            drag.target = from
            drag.spans = spans
            watchForEscape()
        }
        // The dock rebuilt itself under the drag — a selection change adds and
        // removes sections. What was measured at pick-up no longer describes
        // what is on screen, so put it back rather than act on it.
        guard drag.sections == sections else {
            cancelSectionDrag()
            return
        }
        drag.carriedBy = carriedBy
        let target = SectionReorderDrag.target(dragging: drag.from, pointerY: pointerY,
                                               spans: drag.spans)
        guard target != drag.target else { return }
        drag.target = target
    }

    /// Let go. The section lands in the slot the column has been holding open
    /// for it, and everything settles in one animation.
    private func endSectionDrag(in sections: [InspectorSectionID]) {
        stopWatchingForEscape()
        let landed = drag.section != nil && !drag.cancelled && drag.sections == sections
            ? SectionReorderDrag.reordered(sections, moving: drag.from, to: drag.target)
            : sections
        withAnimation(.spring(duration: 0.28)) {
            drag = SectionDrag()
            commitSectionOrder(landed, onScreen: sections)
        }
    }

    /// Escape while carrying: the section goes back where it came from, and
    /// nothing about the column has changed.
    private func cancelSectionDrag() {
        stopWatchingForEscape()
        guard drag.section != nil else { return }
        withAnimation(.spring(duration: 0.22)) {
            drag.carriedBy = 0
            drag.target = drag.from
            drag.section = nil
        }
        // The button is still down, so the gesture keeps reporting. It is
        // ignored from here until it ends.
        drag.cancelled = true
    }

    /// Writes an on-screen reordering back into the saved order, which also
    /// holds the sections this selection has no use for. Those keep the slots
    /// they have: reordering what you can see must not shuffle what you cannot.
    private func commitSectionOrder(_ landed: [InspectorSectionID],
                                    onScreen: [InspectorSectionID]) {
        var queue = ArraySlice(landed)
        var merged: [InspectorSectionID] = []
        for id in order {
            if onScreen.contains(id), let next = queue.popFirst() { merged.append(next) }
            else { merged.append(id) }
        }
        merged.append(contentsOf: queue)
        guard merged != order else { return }
        order = merged
    }

    /// Escape puts a carried section back. A key watch rather than a key
    /// binding because the dock does not hold the keyboard during a drag —
    /// whatever had it before still does.
    private func watchForEscape() {
        guard dragScratch.escapeWatch == nil else { return }
        dragScratch.escapeWatch = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            cancelSectionDrag()
            return nil
        }
    }

    private func stopWatchingForEscape() {
        guard let watch = dragScratch.escapeWatch else { return }
        NSEvent.removeMonitor(watch)
        dragScratch.escapeWatch = nil
    }

    private func isCollapsed(_ id: InspectorSectionID) -> Bool {
        collapsedRaw.split(separator: ",").contains(Substring(id.rawValue))
    }

    private func toggleCollapsed(_ id: InspectorSectionID) {
        var set = Set(collapsedRaw.split(separator: ",").map(String.init))
        if set.contains(id.rawValue) { set.remove(id.rawValue) } else { set.insert(id.rawValue) }
        withAnimation(.spring(duration: 0.25)) {
            collapsedRaw = set.sorted().joined(separator: ",")
        }
    }

    /// Opens a section that was left collapsed, and does nothing to one that is
    /// already open. No animation: the reveal that calls this needs a height
    /// that has finished changing.
    private func expand(_ id: InspectorSectionID) {
        var set = Set(collapsedRaw.split(separator: ",").map(String.init))
        guard set.remove(id.rawValue) != nil else { return }
        collapsedRaw = set.sorted().joined(separator: ",")
    }
}

/// The dock's live measurements for the Library reveal: where the shelf sits,
/// how tall the dock is, and whether a reveal is waiting on layout. Held by
/// reference so writing it during a scroll does not redraw the dock.
/// A dock section on its way up or down the column.
private struct SectionDrag: Equatable {
    /// What is in your hand. Nil means nothing is being carried.
    var section: InspectorSectionID?
    /// The sections on screen when it was picked up, so a dock that rebuilds
    /// itself mid-drag can be noticed rather than acted on.
    var sections: [InspectorSectionID] = []
    /// Where it came from, as an index into `sections`.
    var from = 0
    /// The slot it is currently offering to land in.
    var target = 0
    /// How far the pointer has carried it, vertically only.
    var carriedBy: CGFloat = 0
    /// Where every section was standing when it was picked up.
    var spans: [SectionReorderDrag.Span] = []
    /// Escape has put it back; the rest of the gesture is ignored.
    var cancelled = false
}

/// What a reorder needs to remember that nothing draws: where the sections
/// were last measured, and the key watch that lets Escape put one back. Held
/// by reference so keeping it up to date on every scroll tick does not redraw
/// the dock.
@MainActor private final class SectionDragScratch {
    var frames: [InspectorSectionID: CGRect] = [:]
    var escapeWatch: Any?
}

@MainActor private final class DockRevealScratch {
    var libraryFrame: CGRect?
    var viewportHeight: CGFloat = 0
    var isPending = false
}

/// Which dock sections have actually been built, so a brand new one can wait a
/// beat before it is. The rule and the reason are in
/// `PanelSectionArrival`; this is only the bookkeeping the panel needs to
/// apply it.
///
/// Deliberately NOT observed state. The list has to be recorded on every body
/// pass, and re-drawing the whole dock to write down what it has just drawn
/// would cost more than the pass this exists to save. The one moment it needs
/// to force a re-draw — the pass that mounts the sections it held back — the
/// panel does with its own `@State` counter.
@MainActor private final class DockArrivals {
    private var mounted: [InspectorSectionID] = []

    /// The sections the dock may draw this pass, and a note of them for the
    /// next one. Safe to call more than once per pass: the answer does not
    /// change until `allow` opens the gate.
    func showing(_ target: [InspectorSectionID]) -> [InspectorSectionID] {
        let raw = PanelSectionArrival.showing(target: target.map(\.rawValue),
                                              mounted: mounted.map(\.rawValue))
        let sections = raw.compactMap(InspectorSectionID.init(rawValue:))
        mounted = sections
        return sections
    }

    /// True when `target` asks for a section that has not been built, so the
    /// panel owes it one more pass.
    func isWaiting(for target: [InspectorSectionID]) -> Bool {
        PanelSectionArrival.isWaiting(target: target.map(\.rawValue),
                                      mounted: mounted.map(\.rawValue))
    }

    /// Let everything the selection asked for be built on the next pass.
    func allow(_ target: [InspectorSectionID]) { mounted = target }
}

/// The dock's scrolling area as a coordinate space, so a section can say where
/// it sits relative to what is on screen rather than to the window.
private let inspectorDockSpace = "inspector.dock"

/// The sections of the inspector, in their default order. `rawValue` persists.
enum InspectorSectionID: String, CaseIterable {
    case layers
    case measureTool
    case wandTool
    case cropTool
    // The Zoom Callout tool's own setting (`next-callout-shape`): whether the
    // next callout comes out a box or a circle. It sits with the other
    // tool-in-hand sections, and the picked-callout section below carries the
    // same choice for one that is already on the canvas.
    case calloutTool
    case measurements
    // Above Position & Size, because the two answer the same question at
    // different scales: where do these sit, and where does this one sit.
    case arrange
    // WHAT you have picked, before anything about where it sits: an original
    // component's name and its versions, and a copy's Version row and knobs.
    // Above Position & Size on purpose (2026-09-06). It used to sit under
    // Layout, which is the tallest section in the dock, and that put the
    // Version row — the biggest single fact about a copy — below the bottom of
    // the panel on a laptop window: you had to scroll to find out which
    // version you were looking at. Identity first, then where it is, then what
    // it looks like.
    case component
    // The sections named after the thing you have picked: Rectangle, Text,
    // Measurement, Zoom Callout, Collage, Canvas. They sit here, straight
    // under what the document holds and above everything general, because the
    // panel should answer "what did I just click" before it explains position,
    // colour and effects — the same rule Component follows just above.
    //
    // They used to trail Colour and Effects, which on a laptop window put them
    // below the bottom of the panel: on a marked-up screenshot even the header
    // was off screen, so there was no hint the settings existed at all (chosen
    // by the user on 2026-09-06, "Put what you picked first"). The cost is
    // that Colour, Effects and the X Y W H boxes each shift down by the height
    // of one section.
    case annotation
    // A picked zoom callout's own two settings, beside the shapes' own: how
    // much it magnifies and whether it is a box or a circle. Its ring is the
    // layer's border, so the ring's color stays in Color and its thickness
    // stays in Effects, like every other layer's.
    case callout
    case text
    case measure
    case collage
    case canvas
    case geometry
    case frame
    // The column layout a selected screen is designed to (Next, `next-frames`).
    // Directly under Frame, because Frame says how big the screen is and this
    // says what it is laid out on. Its own section rather than three more rows
    // inside Frame, so the app's two grid-ish things each have their own place
    // with their own words: Columns on a screen, Grid on the canvas.
    case columns
    // Where the pieces sit when something is resized (Next, `next-placement`).
    // Under Frame, because Frame says how big the box is and this says what
    // happens to what is in it when that box changes.
    case placement
    // Every color the picked layers wear, and one place to set them all at
    // once. Under the per-kind sections, because those say what the thing IS
    // and this says what it looks like, and it sits in the SAME place whether
    // one layer is picked or twenty: adding to the selection widens what a row
    // answers for and never moves the row.
    //
    // With the Appearance/Effects split on (`next-shape-parts`) these two rise
    // to sit directly under Layers, in this order, which the user asked for on
    // 2026-09-07: they are the two sections touched on every single layer, so
    // they are the two that must never need scrolling to. That is a one-time
    // move of a saved order rather than a change here, so the release without
    // the split keeps the arrangement it has always had.
    case color
    // Fade, corners, blur and border: the look of the thing, right beside the
    // colors it is painted, because they are the same question. This is the
    // section people reach for most and it used to sit under Shadow and every
    // per-kind section, which in a normal window put Corner Radius below the
    // bottom of the panel (reported 2026-09-03).
    case effects
    // Shadow stays at the bottom. It is part of the same look family as Color
    // and Effects, but it is a switch you set once rather than a slider you
    // pull, and it is the tallest section in the panel: putting it above the
    // picked thing's own settings would push THOSE off the bottom instead.
    case shadow
    // The shelf sits under the property sections, where the mock puts it: it is
    // where you go to fetch something, not what the thing you have selected is.
    case library
    case libraryItem

    var title: String {
        switch self {
        case .layers: "Layers"
        case .measureTool: "Measure Tool"
        case .wandTool: "Magic Wand"
        case .cropTool: "Crop Tool"
        case .calloutTool: "Zoom Callout Tool"
        case .measurements: "Measurements"
        case .arrange: "Arrange"
        case .geometry: "Position & Size"
        case .frame: "Frame"
        case .columns: FrameColumnsCopy.section
        case .placement: "Layout"
        case .component: "Component"
        case .color: "Color"
        case .annotation: "Annotation"
        case .callout: "Zoom Callout"
        case .text: "Text"
        case .measure: "Measure"
        case .collage: "Collage"
        case .canvas: "Canvas"
        case .effects: "Effects"
        case .shadow: "Shadow"
        case .library: "Library"
        // Replaced at draw time by the scope's own noun; this is the fallback.
        case .libraryItem: "Library Item"
        }
    }
}

/// The panel itself answering for a file let go anywhere it has no other drop
/// target: the empty space under the last section, and the gaps between the
/// sections.
///
/// There is no `validateDrop`, on purpose. Answering false there takes the
/// delegate out of the drag altogether, and then the panel could never say it
/// was about to REFUSE something — the refusal would live in the pointer and
/// nowhere else, which is the thing this surface was fixed for.
private struct PanelFileDrop: DropDelegate {
    let editorState: EditorState

    /// Who is speaking, for the one-voice rule in `offerPanelDrop`.
    private var owner: AnyHashable { "inspector-panel" }

    func dropEntered(info: DropInfo) { offerFile(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: offerFile(info))
    }

    func dropExited(info: DropInfo) { editorState.endPanelDrop(from: owner) }

    func performDrop(info: DropInfo) -> Bool {
        let landing = editorState.incomingDropOnTop
        editorState.endPanelDrop(from: owner)
        return FileDrop.accept(info, into: editorState, landingAt: landing)
    }

    @discardableResult
    private func offerFile(_ info: DropInfo) -> DropOperation {
        guard FileDrop.isAboutAFile(info) else { return .forbidden }
        guard FileDrop.carriesUsableFile(info) else {
            editorState.offerPanelDrop(.refuses, from: owner)
            return .forbidden
        }
        editorState.offerPanelDrop(.accepts(editorState.incomingDropOnTop), from: owner)
        return .copy
    }
}

/// What the panel draws while something is in the air over it, so the only
/// sign of what is about to happen is not the shape of the pointer.
///
/// Two answers, told apart at a glance rather than by reading: a solid accent
/// edge with a faint wash means the panel will take this, and a dashed red
/// edge means it will not. The precise slot the picture will take is drawn by
/// the layers list itself, in the same drop line a dragged row already gets.
private struct PanelDropAffordance: View {
    let offer: EditorState.PanelDropOffer?

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10) }

    @ViewBuilder
    var body: some View {
        switch offer {
        case .accepts:
            shape
                .fill(Color.accentColor.opacity(0.07))
                .overlay { shape.strokeBorder(Color.accentColor, lineWidth: 2) }
                .padding(3)
        case .refuses:
            shape
                .strokeBorder(Color.red.opacity(0.55),
                              style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .padding(3)
        case nil:
            EmptyView()
        }
    }
}

/// Takes a picture let go on a dock section the way the rest of the window
/// does.
///
/// A section answers for files because nothing behind it can: SwiftUI gives the
/// drag to the innermost target under the pointer and stops there, so a section
/// that answered for nothing made the top half of the panel refuse a picture
/// the bottom half was happily taking.
///
/// FILES ONLY, and that is the whole point of it. Reordering sections used to
/// come through here as well, riding on a system drag that carried the
/// section's name as text — which every drop target in the panel then read as
/// a payload it could not use, and answered with the red dashes that mean a
/// file would be refused. A reorder is now the panel's own gesture
/// (`reorderGesture`) and never reaches the drop machinery at all.
private struct SectionFileDrop: DropDelegate {
    let item: InspectorSectionID
    let editorState: EditorState

    func dropEntered(info: DropInfo) { offerFile(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: offerFile(info))
    }

    func dropExited(info: DropInfo) { editorState.endPanelDrop(from: item) }

    func performDrop(info: DropInfo) -> Bool {
        let landing = editorState.incomingDropOnTop
        editorState.endPanelDrop(from: item)
        return FileDrop.accept(info, into: editorState, landingAt: landing)
    }

    /// Tells the panel what it is about to do with the file in the air, and
    /// answers the pointer the same thing. A section is not a place in the
    /// stack, so a picture let go here lands on top — which is what the line
    /// at the top of the layers list is drawing while this is showing.
    @discardableResult
    private func offerFile(_ info: DropInfo) -> DropOperation {
        guard FileDrop.isAboutAFile(info) else { return .forbidden }
        guard FileDrop.carriesUsableFile(info) else {
            editorState.offerPanelDrop(.refuses, from: item)
            return .forbidden
        }
        editorState.offerPanelDrop(.accepts(editorState.incomingDropOnTop), from: item)
        return .copy
    }
}

/// Measured height of a layers-panel row, so a drop can tell the top of a row
/// from its middle, and so the list can work out how tall it wants to be
/// without measuring rows it never built. Every row is the same shape, so one
/// value serves them all.
private struct LayerRowHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 38
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Measured height of the Canvas row at the foot of the list. It is separate
/// from `LayerRowHeightKey` because the Canvas row is the ONE row that is
/// always built, so it is the one measurement the list can always rely on.
private struct LayerCanvasRowHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 38
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Where a dragged row would land, and what the drop line under the pointer is
/// promising. Three zones per row: the top strip puts the layers in front of
/// this one, the bottom strip behind it, and the middle of a group row puts
/// them inside it. An OPEN group has no bottom strip, because the slot under
/// its row already belongs to its own topmost child.
///
/// A drop is one document mutation, so a drag is one undo step, and every
/// layer keeps its place on the canvas.
private struct LayerRowDropDelegate: DropDelegate {
    let row: LayerPanelRow
    let rowHeight: CGFloat
    let editorState: EditorState

    /// The row the list is holding, if any. It lives on the editor rather than
    /// in the list so that a drag which ends without reporting itself — escape,
    /// let go over the picture, let go outside the window — is still put down,
    /// by the same watch that settles the panel's own mark. See
    /// `LayerRowInHand`.
    private var dragging: UUID? { editorState.layerRowInHand }

    /// What the drag is carrying: the whole selection when the row you picked
    /// up is part of it (the way Delete and Duplicate already work), else just
    /// that row.
    private var carried: Set<UUID> {
        guard let dragging else { return [] }
        return PhotonzDocument.rowsCarried(byDragging: dragging,
                                           selection: editorState.actionableLayerIDs)
    }

    private func proposal(_ info: DropInfo) -> LayerDrop? {
        editorState.dropProposal(carrying: carried, over: row,
                                 pointerY: info.location.y, rowHeight: rowHeight)
    }

    /// Whether THIS drag is a row being carried up or down the list, rather
    /// than a file arriving from outside it.
    ///
    /// It asks what is in the air and not just whether a row was picked up,
    /// because a row can be picked up and then let go somewhere that never
    /// reports it — over the canvas, outside the window, cancelled with escape
    /// — and the list is still holding it afterwards. A picture dragged in next
    /// would then be read as that row coming back: no accept mark, and a drop
    /// that reordered layers instead of adding the picture. What you are
    /// holding decides, and a file is always answered as a file.
    private func carriesARow(_ info: DropInfo) -> Bool {
        dragging != nil && !FileDrop.isAboutAFile(info)
    }

    func dropEntered(info: DropInfo) {
        guard carriesARow(info) else {
            offerFile(info)
            return
        }
        editorState.sayLayerRowLanding(proposal(info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Nothing was picked up in the list, so this is a file coming in from
        // outside. A row answers for one because nothing behind it can, and it
        // answers the way the rest of the window does: a picture is taken, and
        // anything else shows the no-entry sign.
        guard carriesARow(info) else { return DropProposal(operation: offerFile(info)) }
        let proposed = proposal(info)
        // Said on every frame even when it has not changed, because each answer
        // is also what pushes the put-it-down deadline out: a pointer resting
        // still over one row must not be read as a drag that ended.
        editorState.sayLayerRowLanding(proposed)
        return DropProposal(operation: proposed == nil ? .forbidden : .move)
    }

    func dropExited(info: DropInfo) {
        guard carriesARow(info) else {
            editorState.endPanelDrop(from: row.id)
            return
        }
        // The row is still in the hand — the drag is only off THIS row — so
        // this takes the line away and nothing more.
        if editorState.layerRowLanding?.targetID == row.id { editorState.sayLayerRowLanding(nil) }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard carriesARow(info) else {
            let landing = fileLanding(info)
            editorState.endPanelDrop(from: row.id)
            return FileDrop.accept(info, into: editorState, landingAt: landing)
        }
        defer { editorState.letGoOfLayerRow() }
        guard let drop = proposal(info) else { return false }
        editorState.dropRows(ids: carried, drop)
        return true
    }

    /// Where the picture in the air lands if it is let go on this row now: the
    /// slot the pointer is pointing at, read the same three ways a row drag is,
    /// falling back to the top of the stack for a row that cannot take it.
    private func fileLanding(_ info: DropInfo) -> LayerDrop? {
        editorState.incomingDropProposal(over: row, pointerY: info.location.y, rowHeight: rowHeight)
            ?? editorState.incomingDropOnTop
    }

    /// Tells the panel what it is about to do with the file in the air, and
    /// answers the pointer the same thing.
    ///
    /// A row takes plain text as well as files, because that is how a row being
    /// reordered travels — so this is also where every OTHER thing the app
    /// carries around lands: a colour off a swatch, a saved colour off the
    /// Library shelf, words dragged out of a field. None of them is a file, and
    /// the panel says nothing at all about them. The pointer still shows the
    /// no-entry sign, because a colour does not belong on a layer row either.
    @discardableResult
    private func offerFile(_ info: DropInfo) -> DropOperation {
        guard FileDrop.isAboutAFile(info) else { return .forbidden }
        guard FileDrop.carriesUsableFile(info) else {
            editorState.offerPanelDrop(.refuses, from: row.id)
            return .forbidden
        }
        editorState.offerPanelDrop(.accepts(fileLanding(info)), from: row.id)
        return .copy
    }
}

/// A titled section with a chevron (tap to collapse) and a drag affordance on
/// its header (drag to reorder). Elegant/modern: clean header, smooth collapse.
private struct CollapsibleSection<Content: View>: View {
    let title: String
    let isCollapsed: Bool
    let onToggle: () -> Void
    /// The header being dragged up or down the dock: where the pointer is in
    /// the dock's visible area, and how far it has carried this section.
    let onReorder: (CGFloat, CGFloat) -> Void
    /// The header let go.
    let onReorderEnd: () -> Void
    /// Optional header furniture between the title and the drag grip — the
    /// Measurements section puts its count badge and panel menu here.
    var accessory: AnyView?
    /// The height this body is allowed, past which it scrolls inside itself so
    /// the sections under it stay where they are. Nil is the normal case: the
    /// body is drawn whole, because the dock has room for all of it. See
    /// `DockHeightBudget`.
    var bodyCeiling: CGFloat?
    /// Told how tall the body would like to be, whether or not it got it. This
    /// is what the dock budgets from, and it is measured INSIDE the scroller,
    /// so it is the content's own height rather than the height it was given —
    /// the two being different is the whole point.
    var onBodyHeight: ((CGFloat) -> Void)?
    /// ...and how tall the header is, since a header whose words wrap is
    /// taller than the row it is pinned to.
    var onHeaderHeight: ((CGFloat) -> Void)?
    @ViewBuilder var content: () -> Content
    /// Whether this header's press has travelled far enough to have picked the
    /// section up. See `headerGesture`.
    @State private var isCarrying = false
    /// Which way a shortened body has more to show. Starts as "more below",
    /// which is what being shortened means, so the cue is right on the first
    /// frame rather than one scroll later.
    @State private var overflow = EdgeOverflow(above: false, below: true)

    /// Which edges of a shortened body have more content past them.
    private struct EdgeOverflow: Equatable {
        let above: Bool
        let below: Bool
    }

    /// Solid over the body, fading out at whichever edge has more past it.
    private var edgeFade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0), .black],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: overflow.above ? InspectorPanel.bodyEdgeFade : 0)
            Rectangle()
            LinearGradient(colors: [.black, .black.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: overflow.below ? InspectorPanel.bodyEdgeFade : 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    onHeaderHeight?($0)
                }
            if !isCollapsed {
                boundedBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// The body, inside its own scroller when the dock has had to shorten it.
    ///
    /// Whole and unwrapped the rest of the time, which is every case where the
    /// panel fits: a section that would be drawn at exactly its own height
    /// gains nothing from a scroller and loses a frame of lag every time its
    /// content changes, because the height it is given is measured one pass
    /// behind the content it is given for.
    @ViewBuilder private var boundedBody: some View {
        let measured = content()
            .padding(.bottom, 6)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                onBodyHeight?($0)
            }
        if let bodyCeiling {
            ScrollView(.vertical) { measured }
                .frame(height: bodyCeiling)
                .scrollBounceBehavior(.basedOnSize)
                // Which way there is more to see, so the edge that says so is
                // only drawn where it is true.
                .onScrollGeometryChange(for: EdgeOverflow.self) { geometry in
                    EdgeOverflow(
                        above: geometry.contentOffset.y > 1,
                        below: geometry.contentOffset.y + geometry.containerSize.height
                            < geometry.contentSize.height - 1)
                } action: { _, edges in
                    overflow = edges
                }
                // A body the dock has shortened is cut off mid-control, and
                // macOS hides its scrollers until you scroll, so the first
                // build of this clipped a sentence in half and gave no hint
                // why: it read as a rendering fault rather than as something
                // that scrolls. The edge fades out instead, which is the
                // ordinary way of saying there is more this way, and it is
                // only ever on a body that really is shorter than its content.
                .mask { edgeFade }
                .animation(.easeOut(duration: 0.12), value: overflow)
        } else {
            measured
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: PanelSectionLook.Section.chevronSize,
                              weight: PanelSectionLook.Section.chevronWeight))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            Text(title)
                .font(PanelSectionLook.Section.titleFont)
            Spacer(minLength: 8)
            if let accessory { accessory }
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .panelEdgeIcon("section grip", of: title)
        }
        // Leading and trailing separately: the title stays exactly where it
        // was, and the grip joins the column the eyes make down the edge.
        .padding(.leading, 12)
        .panelEdgePadding()
        .padding(.vertical, 8)
        // A floor, not a fixed height: a header whose words grow still grows.
        .frame(minHeight: InspectorPanel.headerRowHeight)
        .contentShape(Rectangle())
        .gesture(headerGesture)
        .panelHelp("Drag to reorder • click to collapse")
        // Named for a scripted walk, so one can collapse a section, or pick it
        // up, by the words on it.
        .playtestControl("\(title) section", detail: "a dock section header")
    }

    /// Click to collapse, drag to reorder — ONE gesture, which is the only way
    /// the two can be told apart without arbitration: a press that never
    /// travels is a click, and a press that travels 4pt has picked the section
    /// up and stays a carry until it is let go.
    ///
    /// Reordering is a plain drag of the panel's own, NOT a system drag. A
    /// system drag hands the pointer a picture of the title and nothing else,
    /// lets the section be pulled sideways out of the column, and — because
    /// what it is carrying looks like a payload to every drop target it crosses
    /// — makes the panel flash the marks that answer for a dropped file,
    /// including the red dashes that mean a file would be refused.
    private var headerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(inspectorDockSpace))
            .onChanged { value in
                guard isCarrying || abs(value.translation.height) > 4 else { return }
                isCarrying = true
                onReorder(value.location.y, value.translation.height)
            }
            .onEnded { _ in
                guard isCarrying else {
                    withAnimation(.spring(duration: 0.25)) { onToggle() }
                    return
                }
                isCarrying = false
                onReorderEnd()
            }
    }
}

/// The 1px resize handle on the panel's left edge. Drag to set the panel width;
/// the value persists via the caller's `@AppStorage` binding.
struct InspectorResizeHandle: View {
    @Binding var width: Double
    @State private var dragStartWidth: Double?

    static let minWidth: Double = 220
    static let maxWidth: Double = 480

    var body: some View {
        Divider()
            .frame(width: 1)
            .overlay {
                // A wide, invisible strip makes the 1px line easy to grab — a
                // hairline is nearly impossible to hit, so give it a 14pt target
                // (extends 7pt each side of the divider).
                Color.clear
                    .frame(width: 14)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                let base = dragStartWidth ?? width
                                if dragStartWidth == nil { dragStartWidth = width }
                                // Dragging left (negative dx) widens the right panel.
                                width = min(Self.maxWidth, max(Self.minWidth, base - value.translation.width))
                            }
                            .onEnded { _ in dragStartWidth = nil }
                    )
            }
            // The 14pt grab strip spills past the 1pt divider; let it receive
            // hits in that overhang instead of being clipped to 1pt.
            .frame(width: 1)
            .zIndex(1)
    }
}

/// The grab bar under a bounded list area (the layers rows, the Library
/// tiles): drag it to set how tall that area may get before it scrolls on its
/// own, so the sections below it stay in view. One idiom, so every resizable
/// area in the dock feels the same.
///
/// It is drawn only while there is something to resize. The area is as tall as
/// its content or the ceiling this bar sets, whichever is smaller, so under a
/// list shorter than the floor every ceiling draws the same picture — and a bar
/// that turns the pointer into a resize cursor and then moves nothing is worse
/// than no bar at all. `PanelAreaResize` in PhotonzCore owns that rule and the
/// arithmetic under it.
struct PanelAreaResizeHandle: View {
    /// The persisted ceiling, owned by the caller's `@AppStorage`.
    @Binding var maxHeight: Double
    /// What a walk calls this area: "Layers", "Library".
    let area: String
    /// How tall the area would be with nothing capping it. Dragging is bounded
    /// by this, so every point of the drag moves the area under the pointer.
    let contentHeight: CGFloat
    let minHeight: CGFloat
    let maxAllowedHeight: CGFloat
    let help: String

    @State private var dragStartHeight: Double?
    /// Whether the pointer is on the bar, so the resize cursor is pushed and
    /// popped exactly once each.
    @State private var isHovering = false

    /// How tall the area is right now: its content, capped.
    private var height: CGFloat {
        PanelAreaResize.height(contentHeight: contentHeight, ceiling: CGFloat(maxHeight))
    }

    /// Whether there is a bar at all. Under content shorter than the floor
    /// there is nothing a ceiling could change, so nothing is drawn and the
    /// pointer stays as it was.
    private var isShown: Bool {
        PanelAreaResize.isResizable(contentHeight: contentHeight,
                                    minHeight: minHeight,
                                    maxAllowedHeight: maxAllowedHeight)
    }

    var body: some View {
        Group {
            if isShown {
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 32, height: 4)
                    .frame(maxWidth: .infinity)
                    .frame(height: 12)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        guard inside != isHovering else { return }
                        isHovering = inside
                        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    // The bar can now go away under the pointer, when the last
                    // rows that made it worth having are deleted. Without this
                    // the resize cursor it pushed would stay on screen with
                    // nothing under it to resize.
                    .onDisappear {
                        if isHovering { isHovering = false; NSCursor.pop() }
                    }
                    .gesture(
                        // GLOBAL space: the handle moves as the area resizes, so a
                        // local-space translation would be measured against the moving
                        // handle and jiggle.
                        DragGesture(coordinateSpace: .global)
                            .onChanged { carry($0.translation.height) }
                            .onEnded { _ in end() }
                    )
                    .panelHelp(help)
            } else {
                // The bar's room, kept, so a list does not shift the sections
                // under it by twelve points as it crosses the threshold.
                Color.clear.frame(height: 12)
            }
        }
        .panelAreaHandleProbe(
            PanelAreaHandleReading(area: area, isShown: isShown, height: height,
                                   contentHeight: contentHeight, minHeight: minHeight,
                                   maxAllowedHeight: maxAllowedHeight),
            carry: carry, end: end)
    }

    /// The pointer has travelled `translation` points down from where it took
    /// hold. Bases off the area's ACTUAL height rather than the stored ceiling
    /// — which can sit above short content — so the bar tracks the cursor one
    /// for one instead of needing a big pull to catch up.
    private func carry(_ translation: CGFloat) {
        let base = dragStartHeight ?? Double(height)
        if dragStartHeight == nil { dragStartHeight = Double(height) }
        maxHeight = Double(PanelAreaResize.storedCeiling(base: CGFloat(base),
                                                        translation: translation,
                                                        contentHeight: contentHeight,
                                                        minHeight: minHeight,
                                                        maxAllowedHeight: maxAllowedHeight))
    }

    private func end() { dragStartHeight = nil }
}

// MARK: - Layers section

/// The layer list: thumbnails, visibility, lock, rename (double-click),
/// drag-reorder, and selection. Lives inside the docked inspector's Layers
/// section.
struct LayersListView: View {
    @Environment(EditorState.self) private var editorState
    @State private var renamingLayerID: UUID?
    @State private var renameText = ""
    @State private var rowHeight: CGFloat = 38
    /// The row at the top of the visible area. Only the rows around it get a
    /// picture made for them, so opening a document with a hundred layers
    /// costs the same handful of renders as opening one with ten.
    @State private var firstVisibleRow = 0
    @FocusState private var renameFieldFocused: Bool

    /// The layer area's max height (user-resizable, persisted). Beyond this the
    /// list scrolls INTERNALLY so a tall stack doesn't shove the Effects/Shadow
    /// sections off the bottom of the inspector — you keep the other palettes in
    /// view and scroll layers on their own.
    ///
    /// The area is sized to every row a twist could reveal rather than to the
    /// rows on screen, so opening a group scrolls inside this height instead
    /// of changing it. Before that, twisting a four layer group open in a two
    /// layer document made the area 80 points taller and carried the Layout
    /// controls off the bottom of the panel.
    ///
    /// Five rows at rest. It was eight, which in a document with any real number
    /// of layers spent a third of the panel on a list you were not looking at
    /// and pushed the look of the thing off the bottom. Drag the grabber under
    /// the list to give it back as much room as you want; that sticks.
    @AppStorage(LayersListView.heightKey) private var maxHeight = 200.0
    /// Measured height of the Canvas row, the one row that is always built.
    @State private var canvasRowHeight: CGFloat = 38
    /// What the count line and the grab bar under the list come to.
    @State private var listExtrasHeight: CGFloat = 0

    /// A second ceiling, from the dock rather than from the grab bar: what the
    /// panel can spare once every form section has been paid for. The stored
    /// ceiling is what this list ASKED for; this is what the panel HAS, and the
    /// list is drawn at the smaller of the two. See `DockHeightBudget`.
    var dockCeiling: CGFloat?
    /// Told what this list would be at full length, and what the count line and
    /// the grab bar under it cost, so the dock can budget for both separately:
    /// the list scrolls and they do not.
    var onMetrics: ((_ listNatural: CGFloat, _ extras: CGFloat) -> Void)?

    /// How tall the layers area may get, remembered across launches.
    static let heightKey = "inspector.layersHeight"
    static let minHeight: CGFloat = 120
    static let maxAllowedHeight: CGFloat = 600

    /// A LazyVStack of rows (NOT a `List`: a List has no natural height and its
    /// fixed-height hack clipped the top rows), inside a bounded ScrollView so it
    /// scrolls independently, plus a drag handle to resize it. Reordering uses the
    /// same drag/drop the inspector sections use.
    ///
    /// Lazy, so a hundred-layer document builds the five rows the panel shows
    /// and makes the rest as you scroll to them. That is why the area's height
    /// is WORKED OUT (`LayerListMetrics`) rather than measured: a lazy stack
    /// reports no height for a row it never built, and feeding that back into
    /// this frame is a loop that shrinks itself — a smaller frame builds fewer
    /// rows, which reports a smaller height, which shrinks the frame again.
    var body: some View {
        let displays = editorState.layerRows
        // The area is sized to every row a twist COULD reveal, not to the rows
        // showing right now, so opening a group scrolls inside the list rather
        // than growing it and pushing the controls under it off the panel.
        let reserved = LayerListMetrics.naturalHeight(
            rowCount: editorState.layerListReservedRowCount(visibleRowCount: displays.count),
            rowHeight: rowHeight,
            canvasRowHeight: canvasRowHeight)
        // The height the list is actually given, which is also the height of
        // the window of rows worth drawing pictures for. Two ceilings, and the
        // lower one wins: what the reader dragged the grab bar to, and what the
        // dock has room for after the form sections are paid.
        let ceiling = min(maxHeight, dockCeiling ?? .greatestFiniteMagnitude)
        let viewport = PanelAreaResize.height(contentHeight: reserved, ceiling: ceiling)
        // What the grab bar may reach. Never past what the dock can spare, so
        // the bar is never a control that cannot act: every point of it still
        // moves the list, and when the dock has nothing at all to give, the bar
        // is not drawn rather than sitting there refusing to move. The room is
        // still there to be had — collapsing a section you are not using is
        // what frees it.
        let grabRange = min(reserved, dockCeiling ?? .greatestFiniteMagnitude)
        // ...and what the list would be if the dock were NOT pressing on it:
        // its rows, capped by the ceiling the reader set with that bar. This is
        // what the dock budgets from, so it reserves room for the list the
        // reader asked for rather than for rows the grab bar already ruled out.
        let unpressed = PanelAreaResize.height(contentHeight: reserved, ceiling: maxHeight)
        return VStack(spacing: 0) {
            ScrollView(.vertical) {
                rows(displays, viewport: viewport)
            }
            .frame(height: viewport)
            .scrollBounceBehavior(.basedOnSize)
            // Which row is at the top, watched as a ROW rather than as an
            // offset: the action then fires once per row you scroll past
            // instead of once per frame, which is what keeps this cheap.
            .onScrollGeometryChange(for: Int.self) { geometry in
                LayerListMetrics.firstVisibleRow(
                    scrollOffset: geometry.contentOffset.y + geometry.contentInsets.top,
                    rowHeight: rowHeight)
            } action: { _, row in
                firstVisibleRow = row
            }

            // What the list costs BESIDES the rows. These do not scroll with
            // the list — a grab bar that scrolled away would be a grab bar you
            // could not reach — so the dock has to budget for them separately.
            VStack(spacing: 0) {
                multiSelectionCount
                resizeHandle(reserved: grabRange)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { extras in
                listExtrasHeight = extras
                onMetrics?(unpressed, extras)
            }
        }
        .onAppear { onMetrics?(unpressed, listExtrasHeight) }
        .onChange(of: unpressed) { _, latest in onMetrics?(latest, listExtrasHeight) }
        // The Rename command asks for a row's field. Only rows this list shows
        // answer, so the Measurements list next door does not open a second
        // field on the same layer.
        .onChange(of: editorState.layerAwaitingRename) { _, id in
            guard let id, editorState.panelRows.contains(where: { $0.id == id }),
                  let layer = editorState.document?.layer(id: id) else { return }
            editorState.layerAwaitingRename = nil
            beginRename(id: layer.id, name: layer.name)
        }
    }

    /// The inspector shows no per-layer sections for a multi-selection, so
    /// this one line is what says the panel and the canvas agree: "3 layers
    /// selected". Absent for zero or one.
    private var multiSelectionCount: some View {
        let count = editorState.multiSelectedLayerIDs.count
        return Group {
            if count >= 2 {
                Text("\(count) layers selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.leading, EditorChromeLayout.panelEdgeInset)
                    .panelEdgePadding()
                    .padding(.top, 4)
            }
        }
    }

    /// The list, built from ONE read of the document: `editorState.layerRows`
    /// walks the tree once and hands back what each row draws, and the
    /// thumbnails come in one pass beside it. Each row is then an `.equatable()`
    /// view over plain values, so a click that moves the selection redraws the
    /// two rows whose highlight changed and leaves the rest alone. Before this,
    /// every row re-ran its body on every click and looked its own layer up by
    /// searching the whole tree, which cost the list the square of its length
    /// (measured 2026-09-04: about 0.14ms of main thread per row per click).
    ///
    /// Lazy: `LazyVStack` builds a row the first time it comes into view and
    /// keeps it after that, so opening a hundred-layer document costs the five
    /// rows the panel is showing, not a hundred context menus, drop delegates
    /// and gesture recognisers nobody is looking at.
    private func rows(_ displays: [LayerRowDisplay], viewport: CGFloat) -> some View {
        // The twist column appears only once there is something to twist open,
        // so a document with no groups is the list it always was.
        let showsTwist = Experiments.shared.layersListShowsGroups && displays.contains { $0.row.isGroup }
        let componentsEnabled = Experiments.shared.componentsEnabled
        // Both component menu items also need the row to be the selected one,
        // so folding that in here keeps every OTHER row's value unchanged when
        // these flip.
        let canMakeComponent = componentsEnabled && editorState.canMakeComponent
        let canDetachInstance = componentsEnabled && editorState.canDetachInstance
        // Pictures for the rows you can see and a few off each edge, NOT for
        // the ninety behind them: every one is a real render, so asking for
        // all of them is most of the cost of opening a big document and none
        // of the benefit. Rows outside the window draw their placeholder until
        // they come near, and the cache keeps every picture once it lands, so
        // scrolling back over ground you have covered asks for nothing.
        let window = LayerListMetrics.thumbnailWindow(rowCount: displays.count,
                                                      rowHeight: rowHeight,
                                                      firstVisibleRow: firstVisibleRow,
                                                      viewportHeight: viewport)
        let thumbnails = editorState.thumbnails(for: Array(displays[window]))
        // One drop line for two kinds of drag: a row being reordered inside
        // the list, and a picture arriving from outside it. They never happen
        // at once, and drawing them the same way is the point — the promise a
        // file gets is the promise the list already made to its own rows.
        // The row being carried and where it would land are the editor's, not
        // this view's: a drag that ends without reporting itself must still be
        // put down, and only something outside the list can notice that.
        let target = editorState.layerRowLanding ?? editorState.panelDropLanding
        return LazyVStack(spacing: LayerListMetrics.spacing) {
            ForEach(displays) { display in
                LayersRow(display: display,
                          thumbnail: thumbnails[display.id],
                          showsTwist: showsTwist,
                          componentsEnabled: componentsEnabled,
                          offersMakeComponent: canMakeComponent && display.isSelected,
                          offersDetachInstance: canDetachInstance && display.isSelected,
                          drop: target?.targetID == display.id ? target : nil,
                          draftName: renamingLayerID == display.id ? renameText : nil,
                          rowHeight: rowHeight,
                          editorState: editorState,
                          renameText: $renameText,
                          renameFieldFocused: $renameFieldFocused,
                          beginRename: beginRename(id:name:),
                          commitRename: commitRename(id:),
                          cancelRename: cancelRename)
                    .equatable()
            }
            // The Canvas pseudo-layer: pinned at the very bottom (beneath the
            // Background it frames). Not a real layer — no eye/lock/delete/
            // reorder; selecting it puts resize handles on the canvas boundary.
            canvasRow
        }
        .padding(.horizontal, EditorChromeLayout.panelListGutter)
        .padding(.bottom, LayerListMetrics.bottomPadding)
        .onPreferenceChange(LayerRowHeightKey.self) { rowHeight = max(1, $0) }
        .onPreferenceChange(LayerCanvasRowHeightKey.self) { canvasRowHeight = max(1, $0) }
        // Rows slide/fade on add, delete, duplicate, reorder, and on a group
        // opening or closing. Keyed on the SHAPE of the list only: a selection
        // change is not a layout change and never was animated here.
        .animation(.spring(duration: 0.25), value: displays.map(\.row))
    }

    /// A grabber under the list: drag it to resize the layer area. It is there
    /// only while the list is taller than the area's floor, since below that
    /// the list is already showing everything it has and no drag could change
    /// the picture.
    ///
    /// `reserved` is the room the area keeps, which counts the rows a shut
    /// group is hiding: the same number the area is drawn at, so the bar and
    /// the frame under it can never disagree about how far a drag may go.
    private func resizeHandle(reserved: CGFloat) -> some View {
        PanelAreaResizeHandle(maxHeight: $maxHeight,
                              area: "Layers",
                              contentHeight: reserved,
                              minHeight: Self.minHeight,
                              maxAllowedHeight: Self.maxAllowedHeight,
                              help: "Drag to resize the layers area")
    }

    private var canvasRow: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .foregroundStyle(.tertiary)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 40, height: 30)
            Text("Canvas")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let size = editorState.document?.canvasSize {
                Text(verbatim: "\(Int(size.width)) × \(Int(size.height))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.leading, 6)
        .panelEdgeRowPadding()
        .padding(.vertical, 4)
        .background {
            if editorState.isCanvasSelected {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.25))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editorState.selectCanvas() }
        .panelHelp("Select to resize the canvas by its edges")
        // Measured on its own because it is not shaped like a layer row and
        // the list's height arithmetic counts it separately. In a short list
        // it is on screen, so the measurement is live exactly when hugging
        // depends on it; in a long one the list is capped anyway and the
        // default carries.
        .background(GeometryReader { proxy in
            Color.clear.preference(key: LayerCanvasRowHeightKey.self, value: proxy.size.height)
        })
    }

    private func beginRename(id: UUID, name: String) {
        renameText = name
        renamingLayerID = id
        renameFieldFocused = true
    }

    private func commitRename(id: UUID) {
        guard renamingLayerID == id else { return }
        renamingLayerID = nil
        editorState.renameLayer(id: id, to: renameText)
    }

    /// Escape: the row keeps the name it had and nothing reaches history, the
    /// same thing Escape does to a frame's name on the canvas.
    private func cancelRename() {
        renamingLayerID = nil
    }
}

/// One row of the layers list, as a view that can tell when nothing about it
/// changed.
///
/// Everything the row draws arrives as a plain value and NOTHING in `body`
/// reads the editor state. The actions do, but they run on a click, long after
/// the row was drawn, so they never make the row an observer. That is what lets
/// `.equatable()` mean something: a click that moves the selection changes the
/// value of the two rows whose highlight changed, and every other row in the
/// list is skipped whole.
///
/// Keep it that way. Reaching for `editorState.something` inside `body` here
/// quietly puts every row back on the list of things a click has to redraw.
/// The mark on a row whose layer the container around it has cut off, and on a
/// shut group that is hiding one.
///
/// A container set to cut off what does not fit makes anything past its edge
/// disappear completely: the canvas stops drawing it, clicks go through where
/// it used to be, and until now the layers list showed a row that looked like
/// every other row. Somebody who dragged a label a little too far had lost it,
/// with undo as the only way back.
///
/// Scissors because that is the same word the switch uses ("Clip contents"),
/// and warm because a state to notice should not shout like an error.
///
/// It is also the way back. The mark used to name the box and then leave you
/// with three moves to choose between — drag the layer, turn off Clip contents,
/// or type a new number into the inspector — which is a lot of work to undo one
/// drag that went too far. Now the mark does whatever its own sentence tells
/// you to do: on a layer that has been cut off, one press slides it back over
/// the edge it left by; on a shut group speaking for what it is hiding, one
/// press opens the group so the marked rows are on screen.
///
/// At rest it stays a bare glyph, because most of the time it is telling you
/// something rather than asking to be pressed. The capsule under it arrives on
/// hover, which is the moment, and the only moment, somebody needs telling
/// that this one can be pressed.
private struct OutOfViewMark: View {
    let outOfView: RowOutOfView
    /// This row's layer, for the sentence about what it is hiding.
    let name: String
    /// Where a walk finds this control: the list, the row, and what it says.
    let place: (String) -> String
    /// What one press does, which is whatever the tip has just promised.
    let press: () -> Void

    @State private var hovering = false

    var body: some View {
        Group {
            if isPressable {
                Button(action: press) { glyph }
                    .buttonStyle(.plain)
                    .onHover { hovering = $0 }
                    .playtestControl("Out of view", detail: place(state))
            } else {
                // Nothing one press could put right, so nothing that looks
                // pressable. The tip still says what happened and what would
                // fix it; a button that did the wrong thing quietly would be
                // worse than no button at all.
                glyph.playtestTarget("Out of view", kind: .row, detail: place(state))
            }
        }
        .panelHelp(explanation)
    }

    /// Whether pressing this would do anything: a layer that can come back, a
    /// container that can be made big enough for it, or a shut group with rows
    /// to show.
    private var isPressable: Bool {
        outOfView.container == nil ? outOfView.hiddenInside > 0
                                   : outOfView.canReturn || outOfView.growsContainer != nil
    }

    private var glyph: some View {
        Image(systemName: "scissors")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background {
                if hovering { Capsule().fill(Color.orange.opacity(0.18)) }
            }
            .contentShape(Capsule())
    }

    /// The word a walk matches on, so a step can say which of the two things
    /// this mark can mean it is pressing.
    private var state: String {
        outOfView.container.map { "cut off by \($0)" } ?? "hiding \(outOfView.hiddenInside)"
    }

    private var explanation: String {
        var lines: [String] = []
        if let container = outOfView.container {
            if outOfView.canReturn {
                lines.append(
                    "Out of view: this sits outside \(container), which is set to cut off what "
                    + "does not fit. Click to bring it back in, or turn off Clip contents on "
                    + "\(container) to show everything.")
            } else if let change = outOfView.growsContainer {
                // A layer whose container decides where it sits cannot be moved
                // back, so the press changes the container instead. It says
                // which number and what it becomes BEFORE it is pressed,
                // because that number is one somebody typed on purpose.
                lines.append(
                    "Out of view: \(container) is not big enough for everything in it and is set "
                    + "to cut off what does not fit. Click to make \(container) \(change) so "
                    + "everything fits, or turn off Clip contents on it.")
            } else {
                lines.append(
                    "Out of view: \(container) is not big enough for everything in it and is set "
                    + "to cut off what does not fit. Make \(container) bigger in the Layout "
                    + "section, or turn off Clip contents on it.")
            }
        }
        if outOfView.hiddenInside > 0 {
            lines.append(outOfView.hiddenInside == 1
                         ? "1 layer inside \(name) is out of view. Click to open \(name) and find it."
                         : "\(outOfView.hiddenInside) layers inside \(name) are out of view. "
                           + "Click to open \(name) and find them.")
        }
        return lines.joined(separator: " ")
    }
}

private struct LayersRow: View, Equatable {
    let display: LayerRowDisplay
    /// The picture beside the name. Compared by identity: the cache hands back
    /// the very same image until the layer itself changes.
    let thumbnail: CGImage?
    /// Whether the list draws a twist column at all — it appears only once the
    /// document HOLDS a group, so a screenshot with a few annotations on it
    /// reads exactly as it always has.
    let showsTwist: Bool
    let componentsEnabled: Bool
    /// The two component menu items, already decided by the list.
    let offersMakeComponent: Bool
    let offersDetachInstance: Bool
    /// Where a drag hovering over THIS row would land, nil when none is.
    let drop: LayerDrop?
    /// The draft name while this row is being renamed, nil the rest of the
    /// time. It is here so the row being typed into redraws on every keystroke
    /// and no other row does.
    let draftName: String?
    let rowHeight: CGFloat

    // Not compared. These are the ways back out to the app and they point at
    // the same state for as long as the list is on screen, so a row still
    // holding last draw's copy behaves exactly like one holding this draw's.
    let editorState: EditorState
    @Binding var renameText: String
    @FocusState.Binding var renameFieldFocused: Bool
    let beginRename: (UUID, String) -> Void
    let commitRename: (UUID) -> Void
    let cancelRename: () -> Void

    nonisolated static func == (a: LayersRow, b: LayersRow) -> Bool {
        a.display == b.display
            && a.thumbnail === b.thumbnail
            && a.showsTwist == b.showsTwist
            && a.componentsEnabled == b.componentsEnabled
            && a.offersMakeComponent == b.offersMakeComponent
            && a.offersDetachInstance == b.offersDetachInstance
            && a.drop == b.drop
            && a.draftName == b.draftName
            && a.rowHeight == b.rowHeight
    }

    private var id: UUID { display.id }
    private var panelRow: LayerPanelRow { display.row }

    /// What a scripted walk sees this row as. The out-of-view mark is part of
    /// it, because a walk that cannot read the mark cannot prove it appeared.
    private var rowDetail: String {
        var parts = [panelRow.isGroup
                     ? (panelRow.isExpanded ? "group, open" : "group, shut")
                     : "layer"]
        if let outOfView = display.outOfView {
            parts.append(outOfView.container.map { "out of view, cut off by \($0)" }
                         ?? "hiding \(outOfView.hiddenInside) out of view")
        }
        // The same words the row prints under its name, so a walk can check
        // which version a row is showing instead of squinting at a picture.
        if componentsEnabled, let version = display.versionName {
            parts.append("showing the \(version) version")
        }
        return parts.joined(separator: ", ")
    }
    private var indent: CGFloat { CGFloat(display.row.depth) * 14 }

    /// One closure for picking this row up, so a scripted walk and a pointer
    /// start the very same drag.
    private var pickUp: @MainActor () -> NSItemProvider {
        {
            editorState.pickUpLayerRow(id)
            return NSItemProvider(object: id.uuidString as NSString)
        }
    }

    var body: some View {
        // Probe-only, and the whole point of it: a walk counts these to prove
        // the list built the rows on screen and not the ninety behind them.
        #if PHOTONZ_PLAYTEST
        let _ = ViewBuildMeter.shared.built(.layersRow)
        #endif
        content
            .onDrag(pickUp)
            .onDrop(of: [.text] + FileDrop.types, delegate: LayerRowDropDelegate(
                row: panelRow, rowHeight: rowHeight, editorState: editorState))
            .playtestTarget(display.name, kind: .row,
                            detail: rowDetail,
                            payload: pickUp)
    }

    private var content: some View {
        HStack(spacing: 8) {
            if showsTwist { twistControl }
            thumbnailView
            nameBlock
            // The mark that says the box this layer lives in has cut it off,
            // so a layer dragged too far is never lost with nothing anywhere
            // saying where it went.
            if let outOfView = display.outOfView {
                OutOfViewMark(outOfView: outOfView, name: display.name,
                              place: place, press: { pressOutOfViewMark(outOfView) })
            }
            Spacer(minLength: 4)
            // A shut group says how much it is hiding, so the row is not a
            // dead end you have to open to understand.
            if panelRow.isGroup, !panelRow.isExpanded, showsTwist {
                Text("\(panelRow.childCount)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .panelHelp(panelRow.childCount == 1 ? "1 layer inside" : "\(panelRow.childCount) layers inside")
            }
            Button {
                editorState.toggleLayerLock(id: id)
            } label: {
                Image(systemName: display.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 11))
                    .foregroundStyle(display.isLocked ? .primary : .tertiary)
            }
            .panelHelp(display.isLocked ? "Unlock Layer" : "Lock Layer")
            .playtestControl("Lock", detail: place(display.isLocked ? "locked" : "unlocked"))
            // The slot is what keeps the padlock still: shut and open are two
            // drawings of different widths, and without it locking a layer
            // slid the icon 2pt sideways.
            .panelEdgeIcon("lock", of: display.name)
            Button {
                editorState.toggleLayerVisibility(id: id)
            } label: {
                Image(systemName: display.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(display.isVisible ? .primary : .tertiary)
            }
            .panelHelp(display.isVisible ? "Hide Layer" : "Show Layer")
            .playtestControl("Visibility", detail: place(display.isVisible ? "shown" : "hidden"))
            .panelEdgeIcon("eye", of: display.name)
        }
        .buttonStyle(.borderless)
        .padding(.leading, 6)
        .panelEdgeRowPadding()
        .padding(.vertical, 4)
        .padding(.leading, indent)
        .background {
            if display.isSelected {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.25))
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: LayerRowHeightKey.self, value: proxy.size.height)
        })
        .overlay(alignment: .top) { dropLine(.above(id)) }
        .overlay(alignment: .bottom) { dropLine(.below(id)) }
        .overlay {
            // Dropping INSIDE outlines the group itself, so the promise is
            // "this one swallows what you are carrying", never a line that
            // could be read as "next to it".
            if drop == .inside(id) {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        // One tap gesture reads the modifiers itself: shift ranges from the
        // anchor row, command toggles the row, plain selects it. The
        // thumbnail's own command gesture (Select Pixels) sits above this.
        .onTapGesture {
            editorState.clickRow(id, RowClick(modifiers: NSEvent.modifierFlags),
                                 in: editorState.panelRows.map(\.id))
        }
        .contextMenu { menu }
    }

    /// What the row SAYS it is: the name, with the component mark beside it,
    /// and under it the version this drawing is when its component holds more
    /// than one.
    ///
    /// The version sits UNDER the name because side by side the two do not
    /// both fit. At the dock's own width a "Save button" with a "Disabled"
    /// chip after it left the name about 30pt, and the row read as a single
    /// ellipsis: two rows called nothing (2026-09-07). Stacked, the name has
    /// the whole width and so does the version, and the row is no taller for
    /// it, since both lines together are shorter than the thumbnail beside
    /// them and the thumbnail is what sets the row's height.
    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if draftName != nil {
                    TextField("Layer name", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .focused($renameFieldFocused)
                        .onSubmit { commitRename(id) }
                        // The field does not just close on Return, it hands the
                        // keyboard to the picture. Closing alone leaves the
                        // keyboard on the window, where a tool letter does nothing
                        // at all — a quieter version of the same trap.
                        .nameFieldKeys(commit: { commitRename(id) }, revert: cancelRename)
                        .onChange(of: renameFieldFocused) { _, focused in
                            if !focused { commitRename(id) }
                        }
                } else {
                    Text(display.name)
                        .font(.callout)
                        .lineLimit(1)
                        .foregroundStyle(display.isVisible ? .primary : .tertiary)
                        .onTapGesture(count: 2) { beginRename(id, display.name) }
                }
                // The mark that says this group is a component. It sits with the
                // name rather than out at the edge, because it is part of what the
                // row IS, not one more thing you can do to it. Filled is the
                // original, outlined is a copy that follows it.
                if componentsEnabled, display.isMainComponent || display.isComponentInstance {
                    ComponentMark(isInstance: display.isComponentInstance)
                }
            }
            // Every version of a component carries the component's name, so
            // without this line a button with a Disabled version is two rows
            // both called Button and there is no telling which one you are
            // about to edit.
            if componentsEnabled, let version = display.versionName {
                Text(version)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .panelHelp("This is the \(version) version of \(display.name)")
            }
        }
    }

    /// The twist-open control, in a fixed slot so every row's thumbnail lines
    /// up whether or not the row is a group.
    @ViewBuilder
    private var twistControl: some View {
        if panelRow.isGroup {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(panelRow.isExpanded ? 90 : 0))
                .frame(width: 12, height: 12)
                .contentShape(Rectangle())
                // High priority so the twist wins over the row's own tap: a
                // click on the chevron opens the group, it does not also
                // reselect the row under the pointer.
                .highPriorityGesture(TapGesture().onEnded {
                    withAnimation(.spring(duration: 0.2)) {
                        editorState.toggleGroupExpanded(id: id)
                    }
                })
                .panelHelp(panelRow.isExpanded ? "Hide what is inside" : "Show what is inside")
                // The only way a walk has of opening a group: every row inside
                // a shut one is unbuilt, so nothing below it can be named until
                // this has been pressed.
                .playtestControl("Twist", detail: place(panelRow.isExpanded ? "open" : "shut"))
        } else {
            Color.clear.frame(width: 12, height: 12)
        }
    }

    /// Where a control on this row lives, in the words a walk names it by: the
    /// list, this row, and what the control is saying right now.
    ///
    /// The NAME of an eye stays "Visibility" whichever way it is pointing, so a
    /// walk can press the same thing twice; the part that changes under it goes
    /// here, the way a picker segment says "already on Fixed". It is also what
    /// a press step's `in` matches, so `in: "Label"` reaches this row's eye and
    /// no other row's.
    private func place(_ state: String) -> String {
        "Layers, \(display.name), \(state)"
    }

    /// The mark keeps its own promise. A layer the box around it swallowed
    /// comes back; a shut group that is speaking for something it is hiding
    /// opens, so the row wearing the real mark is on screen to be pressed in
    /// turn. Two presses at the very worst, from a mark somebody noticed
    /// without going looking.
    private func pressOutOfViewMark(_ outOfView: RowOutOfView) {
        if outOfView.container != nil {
            // The layer's own move first, always: moving one layer is a smaller
            // change than resizing the box around it, and only where the layer
            // has no position of its own does the container grow instead.
            if outOfView.canReturn {
                editorState.bringLayerIntoView(id: id)
            } else {
                editorState.makeRoomForLayer(id: id)
            }
        } else {
            withAnimation(.spring(duration: 0.2)) { editorState.toggleGroupExpanded(id: id) }
        }
    }

    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(1)
            }
        }
        .frame(width: 40, height: 30)
        .contentShape(Rectangle())
        // ⌘-click on the THUMBNAIL loads the layer's opaque pixels as a
        // selection (Photoshop's load-transparency lives on the thumbnail
        // too); on the rest of the row command-click toggles the row instead.
        .highPriorityGesture(
            TapGesture().modifiers(.command).onEnded { editorState.selectLayerPixels(id: id) }
        )
        .panelHelp("Command-click to select the layer's pixels")
    }

    /// The line that says a drop will land beside a row rather than inside it.
    /// It starts at that row's indent, which is how it names the list the
    /// layers are about to join: a line at the far left means back out on the
    /// canvas.
    @ViewBuilder
    private func dropLine(_ wanted: LayerDrop) -> some View {
        if drop == wanted {
            Capsule()
                .fill(Color.accentColor)
                .frame(height: 2)
                .padding(.leading, indent + 6)
                .padding(.trailing, 6)
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Duplicate") { editorState.duplicateLayer(id: id) }
            .keyboardShortcut("d", modifiers: .command)
        Button("Select Pixels") { editorState.selectLayerPixels(id: id) }
        Button("Merge Down") { editorState.mergeDown(id: id) }
            .keyboardShortcut("e", modifiers: .command)
        if display.isRasterizable {
            Button(RasterizePrompt.menuItem) { editorState.rasterizeLayer(id: id) }
        }
        Divider()
        Button("Bring to Front") { editorState.bringLayerToFront(id: id) }
            .keyboardShortcut("]", modifiers: [.command, .shift])
        Button("Bring Forward") { editorState.bringLayerForward(id: id) }
            .keyboardShortcut("]", modifiers: .command)
        Button("Send Backward") { editorState.sendLayerBackward(id: id) }
            .keyboardShortcut("[", modifiers: .command)
        Button("Send to Back") { editorState.sendLayerToBack(id: id) }
            .keyboardShortcut("[", modifiers: [.command, .shift])
        // Only on a row that IS out of view, which is the only row where it
        // would do anything. Same move as the mark on the row, named, for
        // anybody who goes to the menu before they go to a small orange glyph.
        if display.outOfView?.canReturn == true {
            Divider()
            Button("Bring into View") { editorState.bringLayerIntoView(id: id) }
        } else if let container = display.outOfView?.container,
                  display.outOfView?.growsContainer != nil {
            // The same move as the mark on the row, named, for anybody who goes
            // to the menu before they go to a small orange glyph. It names the
            // container because that is the thing that changes.
            Divider()
            Button("Make \(container) Fit") { editorState.makeRoomForLayer(id: id) }
        }
        Divider()
        Button("Rename") { beginRename(id, display.name) }
        if offersMakeComponent {
            Button("Make Component") { editorState.makeComponent() }
                .keyboardShortcut("k", modifiers: [.command, .option])
        }
        if offersDetachInstance {
            Button("Detach Instance") { editorState.detachInstance() }
                .keyboardShortcut("b", modifiers: [.command, .option])
        }
        // Only on an original, and only when it would work: a row that means
        // nothing on the layer you right-clicked is a row people hunt the
        // reason for.
        if display.isMainComponent, editorState.canAddComponentVersion {
            Button("Add Version") { editorState.addComponentVersion() }
        }
        // Only on a piece of an original that has other versions, and it names
        // them, so the row answers "what would this touch" before it is
        // pressed. Same rule as the Layer menu.
        if let title = editorState.applyToOtherComponentVersionsTitle {
            Button(title) { editorState.applyToOtherComponentVersions() }
                .disabled(!editorState.canApplyToOtherComponentVersions)
        }
        // Settings, not actions: the row says what it IS and wears a checkmark,
        // so the menu reads the same whichever state the layer is in and the
        // Delete below it never shifts under the pointer (MenuToggleNames).
        Toggle(MenuToggleNames.layerVisible, isOn: Binding(
            get: { display.isVisible },
            set: { _ in editorState.toggleLayerVisibility(id: id) }))
        Toggle(MenuToggleNames.layerLocked, isOn: Binding(
            get: { display.isLocked },
            set: { _ in editorState.toggleLayerLock(id: id) }))
        Divider()
        // Dimmed on a locked layer, with the Locked toggle right above it: the
        // way out of the greyed row is the line you just read.
        Button("Delete", role: .destructive) { editorState.deleteLayer(id: id) }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(display.isLocked)
    }
}

// MARK: - Measure tool properties (D15)

/// The Measure tool's own properties, shown while the tool is in hand.
///
/// These used to ride in the tool bar as a Snap menu and a Show menu next to
/// four mode chips, six controls that grew a fixed strip the moment you picked
/// the tool up. D15 draws the line: a mode changes what a click DOES and can
/// live in the tool button, and everything else is a setting that belongs with
/// the tool's properties. Snap changes where a point lands, Show changes what
/// the canvas draws, and both read better as words in a panel than as menus in
/// a strip.
///
/// Mode is here too, on purpose. The button's flyout is the fast path, but a
/// glyph cannot tell you three minutes later that you are still in Gap, so the
/// live mode stays readable as a word for anyone with the inspector open.
struct MeasureToolInspector: View {
    @Environment(EditorState.self) private var editorState

    /// Whether any of the tool's settings exist in this release, so the panel
    /// can leave the section out entirely rather than show an empty box.
    static var hasAnySetting: Bool {
        Experiments.shared.measureModesEnabled || Experiments.shared.measureCenterSnapEnabled
            || Experiments.shared.measureRolesEnabled
    }

    var body: some View {
        @Bindable var state = editorState
        VStack(alignment: .leading, spacing: 8) {
            if Experiments.shared.measureModesEnabled {
                field("Mode") {
                    Picker("Mode", selection: $state.measureToolMode) {
                        ForEach(MeasureToolMode.available(
                            alignmentEnabled: Experiments.shared.measureAlignEnabled), id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden().controlSize(.small)
                    .panelHelp("What a click does. The Measure button holds the same list, "
                          + "and I cycles it. In Size, [ and ] pick a smaller or larger element.")
                    // The keys the mode answers to, taught here because this
                    // line stays: the canvas hint fades in two seconds and
                    // used to be the only place the [ and ] keys were written.
                    if let tip = editorState.measureToolMode.keyTip {
                        Text(tip)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if Experiments.shared.measureCenterSnapEnabled {
                field("Snap") {
                    Picker("Snap", selection: $state.measureSnapsToCenters) {
                        Text("Edges").tag(false)
                        Text("Edges and centers").tag(true)
                    }
                    .labelsHidden().controlSize(.small)
                    .panelHelp("What measure points magnetize to. Hold Command to drag free.")
                }
            }
            if Experiments.shared.measureRolesEnabled {
                field("Show") {
                    Picker("Show", selection: Binding(
                        get: { editorState.measureShowFilter },
                        set: { editorState.setMeasureShowFilter($0) })) {
                        ForEach(EditorState.MeasureShowFilter.allCases, id: \.self) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .labelsHidden().controlSize(.small)
                    .panelHelp("Which measurements the canvas shows. A view filter only: exports "
                          + "always include every visible measurement.")
                }
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }

    @ViewBuilder private func field<Content: View>(_ label: String,
                                                   @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .playtestField(label)
    }
}

// MARK: - Magic Wand tool properties (D15)

/// The Magic Wand's own properties, shown while the tool is in hand.
///
/// Tolerance used to ride in the tool bar as a labelled slider, 152pt that
/// appeared the moment you picked the wand up. It is a setting by D15's test —
/// it changes what the result looks like, not what the pointer does — so it
/// belongs with the tool's properties, and it reads better here with room for
/// the number and a line saying what it means.
struct WandToolInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        @Bindable var state = editorState
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tolerance").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(editorState.wandTolerance))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { editorState.wandTolerance },
                                  set: { editorState.wandTolerance = $0.rounded() }),
                   in: 0...128)
                .controlSize(.small)
            Text("How far a color may drift and still join the selection.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }
}

// MARK: - Crop tool properties (D15)

/// The Crop tool's own properties, shown while the tool is in hand: the aspect
/// lock as a word.
///
/// The four locks used to be four chips in the tool bar. They are modes, so
/// they moved into the crop button's flyout; this is the same choice spelled
/// out, for anyone with the inspector open. Picking here reshapes the pending
/// crop rect exactly as the flyout does.
struct CropToolInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Aspect").font(.caption).foregroundStyle(.secondary)
            Picker("Aspect", selection: Binding(get: { editorState.cropAspect },
                                                set: { editorState.setCropAspect($0) })) {
                ForEach(CropAspect.allCases, id: \.self) { aspect in
                    Text(aspect.label).tag(aspect)
                }
            }
            .labelsHidden().controlSize(.small)
            .panelHelp("What shape the crop keeps. The Crop button holds the same list.")
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }
}

// MARK: - Zoom Callout tool properties (D15)

/// The Zoom Callout tool's own properties, shown while the tool is in hand:
/// whether the next callout is a box or a circle, and how much it magnifies.
///
/// Both used to be reachable only after the fact, in a picked callout's own
/// section, so getting a round 4× callout meant drawing a 2× rectangle and then
/// going to fix it twice. They are settings by D15's test — they change what
/// the drag produces, not what the pointer does — so they belong with the
/// tool's properties, and the tool keeps whatever you last chose.
///
/// Same order as the capsule above the tool bar, because they are the same two
/// settings: whichever place you learn them in, the other reads the same.
struct CalloutToolInspector: View {
    @Environment(EditorState.self) private var editorState

    /// Either half can be off on its own, so each row asks for itself.
    static var hasAnySetting: Bool {
        Experiments.shared.calloutShapeEnabled || Experiments.shared.calloutMagnificationEnabled
    }

    var body: some View {
        @Bindable var state = editorState
        VStack(alignment: .leading, spacing: 10) {
            if Experiments.shared.calloutShapeEnabled {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shape").font(.caption).foregroundStyle(.secondary)
                    Picker("Shape", selection: $state.calloutToolShape) {
                        ForEach(ZoomCalloutShape.allCases, id: \.self) { shape in
                            Text(shape.title).tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .panelHelp("What the next callout is drawn in. The box you drag out previews "
                          + "in the same shape, and a callout already on the canvas is "
                          + "switched in its own section.")
                }
            }
            if Experiments.shared.calloutMagnificationEnabled {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Magnification").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(ZoomCalloutBuilder
                            .magnificationLabel(editorState.calloutToolMagnification))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    // The tool's number is not a document edit, so unlike the
                    // picked callout's slider there is nothing to preview and
                    // nothing to undo: it just moves.
                    Slider(value: Binding(get: { state.calloutToolMagnification },
                                          set: { state.calloutToolMagnification = $0 }),
                           in: ZoomCalloutBuilder.magnificationRange)
                        .controlSize(.small)
                        .panelHelp("How much bigger the next callout draws the region it points at. "
                              + "A callout already on the canvas is resized by the slider in "
                              + "its own section.")
                }
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }
}

// MARK: - Measurements section (§6, `next-measure-panel`)

/// The Measurements group's header furniture: the count badge and the panel
/// menu (Show All / Hide All / Copy as Spec List / Clear Measurements). Each
/// menu action is one undo step; Clear has no confirmation — undo is the
/// safety net.
struct MeasurementsSectionAccessory: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        HStack(spacing: 6) {
            Text("\(editorState.measurementCount)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(.quaternary))
            // The same commands as the menu bar's Measure menu, in its order
            // and under its names (§6's mirror rule), so nothing learned here
            // is wrong there. Each is off when it would change nothing.
            let count = editorState.measurementCount
            let visibleCount = editorState.visibleMeasurementCount
            Menu {
                Button("Show All Measurements") { editorState.setAllMeasurementsVisible(true) }
                    .disabled(visibleCount == count)
                Button("Hide All Measurements") { editorState.setAllMeasurementsVisible(false) }
                    .disabled(visibleCount == 0)
                Divider()
                Button("Copy as Spec List") { editorState.copyMeasureSpecList() }
                    .disabled(visibleCount == 0)
                Divider()
                Button("Clear Measurements", role: .destructive) {
                    editorState.clearAllMeasurements()
                }
                .disabled(count == 0)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .panelHelp("Show, hide, copy, or clear every measurement")
        }
    }
}

/// The Measurements rows (§6): a filtered view of the layer stack, top-most
/// first. Selection is the shared layer selection, the eye is the layer's
/// visibility, delete is layer delete — the group holds no state of its own.
struct MeasurementsListView: View {
    @Environment(EditorState.self) private var editorState
    @State private var renamingLayerID: UUID?
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 2) {
            ForEach(editorState.measurePanelLayers, id: \.id) { layer in
                row(layer)
            }
            // How many of the rows are in the selection, once it is more than
            // one: the number Copy Measurements will copy.
            let count = editorState.selectedMeasureLayerIDs.count
            if count >= 2 {
                Text("\(count) measurements selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.leading, 6)
                    .panelEdgeRowPadding()
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelListGutter)
        // The Rename command asks for a row's field; only measurement rows this
        // list shows answer it.
        .onChange(of: editorState.layerAwaitingRename) { _, id in
            guard let id, let layer = editorState.measurePanelLayers.first(where: { $0.id == id })
            else { return }
            editorState.layerAwaitingRename = nil
            beginRename(layer)
        }
    }

    private var pixelScale: CGFloat { editorState.document?.pixelScale ?? 1 }

    private func row(_ layer: Layer) -> some View {
        let isSelected = editorState.isLayerSelected(layer.id)
        let content = layer.measure
        return HStack(spacing: 8) {
            swatch(content)
            if renamingLayerID == layer.id {
                TextField("Measurement name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename(layer) }
                    .nameFieldKeys(commit: { commitRename(layer) }, revert: cancelRename)
                    .onChange(of: renameFieldFocused) { _, focused in
                        if !focused { commitRename(layer) }
                    }
            } else {
                // Rows name themselves (decision D3): axis + role wording until
                // the user renames one, then the custom name sticks.
                Text(MeasureSpecList.displayName(for: layer))
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(layer.isVisible ? .primary : .tertiary)
                    .onTapGesture(count: 2) { beginRename(layer) }
            }
            Spacer(minLength: 4)
            if let content {
                Text(content.label(pixelScale: pixelScale))
                    .font(.callout)
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(layer.isVisible ? .secondary : .tertiary)
            }
            Button {
                editorState.toggleLayerVisibility(id: layer.id)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(layer.isVisible ? .primary : .tertiary)
            }
            .panelHelp(layer.isVisible ? "Hide Measurement" : "Show Measurement")
            .panelEdgeIcon("eye", of: MeasureSpecList.displayName(for: layer))
        }
        .buttonStyle(.borderless)
        .padding(.leading, 6)
        .panelEdgeRowPadding()
        .padding(.vertical, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.25))
            }
        }
        .contentShape(Rectangle())
        // Shift ranges from the anchor row, command toggles, plain selects:
        // the same reading as the Layers rows, over this list's order.
        .onTapGesture {
            editorState.clickRow(layer.id, RowClick(modifiers: NSEvent.modifierFlags),
                                 in: editorState.measurePanelLayers.map(\.id))
        }
        .contextMenu {
            Button("Copy Measurement") { editorState.copyMeasurement(id: layer.id) }
            Divider()
            Button("Rename") { beginRename(layer) }
            Toggle(MenuToggleNames.layerVisible, isOn: Binding(
                get: { layer.isVisible },
                set: { _ in editorState.toggleLayerVisibility(id: layer.id) }))
            Divider()
            Button("Delete", role: .destructive) { editorState.deleteLayer(id: layer.id) }
        }
        // The name a walk uses for this row, so its menu can be opened and
        // photographed. Without it the measurement rows were the one list in
        // the panel nothing could reach by name.
        .playtestTarget(MeasureSpecList.displayName(for: layer), kind: .row,
                        detail: "measurement, \(layer.isVisible ? "shown" : "hidden")")
    }

    /// The row's role swatch: the measurement's own ink, so it matches the
    /// canvas even after a recolor. Alignment guides ring it dashed, like the
    /// legend.
    @ViewBuilder private func swatch(_ content: MeasureContent?) -> some View {
        let color = Color(hex: content?.strokeColorHex ?? MeasureContent.defaultStrokeColorHex)
        if content?.alignment != nil {
            Circle()
                .strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .frame(width: 10, height: 10)
        } else {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
        }
    }

    private func beginRename(_ layer: Layer) {
        renameText = MeasureSpecList.displayName(for: layer)
        renamingLayerID = layer.id
        renameFieldFocused = true
    }

    private func commitRename(_ layer: Layer) {
        guard renamingLayerID == layer.id else { return }
        renamingLayerID = nil
        editorState.renameLayer(id: layer.id, to: renameText)
    }

    /// Escape: the row keeps the name it had and nothing reaches history, the
    /// same thing Escape does to a frame's name on the canvas.
    private func cancelRename() {
        renamingLayerID = nil
    }
}

// MARK: - Effects & shadow inspectors

/// Non-destructive effects for EVERYTHING picked: opacity, blur, corner
/// radius, border. One pull rounds four buttons, and one undo puts all four
/// back. Where the picked layers differ the readout says Mixed rather than
/// printing one of their numbers as if it spoke for the rest.
struct EffectsInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let selection = editorState.layerStyleSelection
        let ids = selection.layerIDs
        VStack(alignment: .leading, spacing: 8) {
            LayerStyleSlider(layerIDs: ids, label: "Opacity",
                             reading: selection.reading { $0.opacity }, range: 0...1,
                             format: { "\(Int(($0 * 100).rounded()))%" },
                             field: .opacity) { style, v in
                style.opacity = v
            }
            LayerStyleSlider(layerIDs: ids, label: "Blur",
                             reading: selection.number { $0.blurRadius }, range: 0...50,
                             format: points, field: .blur) { style, v in
                style.blurRadius = CGFloat(v)
            }
            // ONE Corner Radius, for every way of rounding. A rectangle curves
            // the outline it draws; a screenshot or a frame has its corners
            // masked off. Both used to have a slider of their own, both called
            // Corner Radius, sitting in different sections of the same panel.
            CornerRadiusRow(selection: editorState.cornerRadiusSelection)
            // The width only. The color a border is painted is a color like any
            // other, so it lives in the Color section with the rest rather than
            // in a swatch of its own down here — and the moment this slider
            // leaves zero, the Border row is up there waiting.
            //
            // Offered only to layers with no line of their own. A shape strokes
            // its own outline, and at the same width the two rings are the same
            // pixels, so a rectangle used to carry two sliders for one ring with
            // the border quietly covering the stroke. A shape's width is the
            // Thickness row in its own section now; see `OutlineWidth.swift`.
            // With `next-shape-parts` on, this ring is the Outline part and its
            // width sits with its own switch and colour up in Appearance.
            let borders = Experiments.shared.shapePartsEnabled
                ? LayerStyleSelection(members: [], selectionCount: selection.selectionCount)
                : selection.borders
            if !borders.isEmpty {
                LayerStyleSlider(layerIDs: borders.layerIDs, label: "Border",
                                 reading: borders.number { $0.borderWidth }, range: 0...20,
                                 format: points, field: .border) { style, v in
                    style.borderWidth = CGFloat(v)
                }
                .panelHelp("The color of the border is in the Color section above")
                // Said under the row it is about, the way the Color rows say
                // it, so it cannot be read as speaking for the whole section:
                // Opacity and Blur still reach every picked layer.
                if let reach = borderReachNote(selection, borders) {
                    Text(reach)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // "A slider here changes every one of them" is a promise Border
            // cannot keep when a shape is picked with something that can take
            // one, so in that case the caption claims only the rest.
            SelectionStyleNotes(notes: [selection.note],
                                caption: selectionCaption(
                                    selection.count,
                                    borders.count == selection.count || borders.isEmpty
                                        ? "A slider here" : "Every other slider here"))
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }

    /// What the Border row says out loud when a shape is picked alongside
    /// something that can take one. Nothing when the row is not there at all:
    /// a lone rectangle is not missing a Border, it has its Thickness.
    private func borderReachNote(_ selection: LayerStyleSelection,
                                 _ borders: LayerStyleSelection) -> String? {
        guard !borders.isEmpty, borders.count < selection.count else { return nil }
        let shapes = selection.count - borders.count
        let verb = shapes == 1 ? "draws its own outline" : "draw their own outline"
        return "Border applies to \(borders.count) of the \(selection.count) selected layers. "
            + "The other \(shapes == 1 ? "one" : "\(shapes)") \(verb): use Thickness."
    }
}

/// The picked layers' shadow: a switch plus, when one is on, blur (softness),
/// size (spread), distance (offset), direction (angle), opacity, and color
/// (10.6) — all of them over the whole selection.
struct ShadowInspector: View {
    @Environment(EditorState.self) private var editorState
    /// Whether the section draws its own on/off switch. The parts list
    /// (`next-shape-parts`) puts that switch up on the Shadow row with every
    /// other part's, and borrows only the rows below it.
    var showsSwitch = true
    /// Same for the colour, which sits on the row in the parts list.
    var showsColor = true
    /// Whether this is a section of its own, with a section's padding. Inside
    /// the parts list the list supplies the margins, so the shadow's rows sit
    /// in the same column as every part above them.
    var inset = true
    /// Which of the layer's shadows these rows are for, nearest the eye first.
    /// A layer can throw more than one since the Appearance list became a list
    /// you add to; the Shadow section of the old panel only ever means the
    /// first one.
    var index = 0

    var body: some View {
        // The layers that have a shadow to talk about. A label whose halo its
        // surface draws for it is not one of them: a switch reading "on" there
        // would be describing a shadow nobody can see, so off is the truth and
        // switching it on gives that label a real shadow.
        let selection = editorState.layerStyleSelection
        let shadows = selection.shadows(at: index)
        let ids = shadows.layerIDs
        VStack(alignment: .leading, spacing: 8) {
            let isMixed = selection.shadowIsMixed
            // The way back for a copy that has picked its own shadow, when
            // there is one. Worked out up here because with the switch up on
            // the parts row this line has nothing else on it, and an empty
            // line still takes its spacing: it pushed Blur further from the
            // Shadow row than Width sits from Outline.
            let revert: UUID? = soleLayerID(selection.layerIDs).flatMap {
                editorState.isInstanceStyleOwn(instance: $0, field: .shadow) ? $0 : nil
            }
            if showsSwitch || revert != nil {
                HStack(spacing: 6) {
                    if showsSwitch {
                        // The caption is the switch's own, and it is out here
                        // rather than inside the Toggle so that the one step
                        // quieter below lands on the switch alone: a caption
                        // dimmed with it would fade into the notes around it.
                        Text("Enable Shadow").font(.caption).foregroundStyle(.secondary)
                        Toggle("", isOn: Binding(
                            // A switch has on and off and nothing else, so while
                            // the picked layers disagree it shows neither: the
                            // first press resolves to ON for all of them, the way
                            // a mixed checkbox has always behaved here, and it
                            // never returns to Mixed, because Mixed is a report
                            // about the selection rather than a state anyone sets.
                            get: { isMixed ? false : selection.hasShadowEverywhere },
                            set: { editorState.setSelectionShadowEnabled(isMixed ? true : $0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .accessibilityLabel("Enable Shadow")
                        // Off is a true answer — none of them have one — so a
                        // disagreeing selection may not wear it at full strength.
                        .opacity(isMixed ? MixedLook.controlOpacity : 1)
                        .panelHelp(shadowSwitchHelp(selection, isMixed: isMixed))
                        .playtestControl("Enable Shadow",
                                         detail: isMixed ? "Shadow, mixed"
                                             : (selection.hasShadowEverywhere ? "Shadow, on" : "Shadow, off"))
                        // The word goes beside the switch, since there is no room
                        // for it inside one, and after it rather than between it
                        // and its caption so that nothing moves on a selection
                        // that agrees.
                        if isMixed { MixedWord() }
                    }
                    // A shadow is ONE part of the look: its softness, size,
                    // distance, direction, opacity and colour are six controls for
                    // the one thing a person means by "the shadow", so there is one
                    // way back rather than six identical arrows.
                    if let revert {
                        InstanceStyleRevert(layerID: revert, field: .shadow)
                    }
                    Spacer(minLength: 0)
                }
            }
            // Said BEFORE the rows, not after them, because a switch reading
            // off above six rows full of numbers is a contradiction until you
            // know only some of the picked layers have a shadow. Said first,
            // it is the sentence that makes the rows make sense.
            //
            // Only where the switch it describes is actually here. Borrowed by
            // the Effects list, these rows are settings hanging under a row
            // whose tick lives up on that row and reaches ONLY the layers that
            // hold the effect, so this sentence printed a second count under
            // the row's own and then promised something untrue: "the switch
            // gives the rest one too" (found on the probe, 2026-09-08). The
            // list's row says its reach itself.
            if showsSwitch, let reach = shadowReachNote(selection, shadows) {
                Text(reach)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !shadows.isEmpty {
                let at = index
                HStack(spacing: 8) {
                    // Called Softness in the Effects list, where a row called
                    // Blur can be sitting right above it: two controls with one
                    // word between them is exactly what the user reported on
                    // 2026-09-07. The rule down the side of these settings
                    // already says whose they are; the name says what it does.
                    // Current, where there is no Blur row to collide with, is
                    // untouched.
                    LayerStyleSlider(layerIDs: ids,
                                     label: Experiments.shared.shapePartsEnabled
                                         ? "Softness" : "Blur",
                                     reading: shadows.number { $0.shadow(at: at)?.radius ?? 0 },
                                     range: 0...40, format: points) { style, v in
                        style.updateShadow(at: at) { $0.radius = CGFloat(v) }
                    }
                    if showsColor { ShadowColorWell(index: at) }
                }
                LayerStyleSlider(layerIDs: ids, label: "Size",
                                 reading: shadows.number { $0.shadow(at: at)?.spread ?? 0 },
                                 range: 0...80, format: points) { style, v in
                    style.updateShadow(at: at) { $0.spread = CGFloat(v) }
                }
                LayerStyleSlider(layerIDs: ids, label: "Distance",
                                 reading: shadows.number { $0.shadow(at: at)?.distance ?? 0 },
                                 range: 0...40, format: points) { style, v in
                    // Each layer keeps the way its own shadow points; only how
                    // far it is thrown is set from here.
                    style.updateShadow(at: at) { $0.setDistance(CGFloat(v)) }
                }
                LayerStyleSlider(layerIDs: ids, label: "Direction",
                                 reading: shadows.number { $0.shadow(at: at)?.directionDegrees ?? 90 },
                                 range: 0...360,
                                 format: { "\(Int($0.rounded()))°" }) { style, v in
                    style.updateShadow(at: at) { $0.setDirectionDegrees(CGFloat(v)) }
                }
                LayerStyleSlider(layerIDs: ids, label: "Opacity",
                                 reading: shadows.reading { $0.shadow(at: at)?.opacity ?? 0 },
                                 range: 0...1,
                                 format: { "\(Int(($0 * 100).rounded()))%" }) { style, v in
                    style.updateShadow(at: at) { $0.opacity = v }
                }
                SelectionStyleNotes(notes: [showsColor ? shadowColorNote(shadows, at: at) : nil],
                                    caption: nil)
            }
        }
        .padding(.horizontal, inset ? 14 : 0)
        .padding(.vertical, inset ? 8 : 0)
    }

    /// How many of the picked layers this section is talking to, in words,
    /// and what the switch does with the rest.
    private func shadowReachNote(_ selection: LayerStyleSelection,
                                 _ shadows: LayerStyleSelection) -> String? {
        let picked = selection.count
        let shadowed = shadows.count
        guard picked > 1 else { return nil }
        if shadowed == 0 {
            return "\(picked) layers. Switching this on shadows every one of them, in one step."
        }
        if shadowed == picked {
            return "\(picked) layers. A slider here changes every one of them, in one step."
        }
        let verb = shadowed == 1 ? "has" : "have"
        return "\(shadowed) of the \(picked) selected layers \(verb) a shadow. "
            + "The rows below change those; the switch gives the rest one too."
    }

    private func shadowSwitchHelp(_ selection: LayerStyleSelection,
                                  isMixed: Bool) -> String {
        // While they disagree the switch has no state to turn off, so the tip
        // says what the press it CAN take would do.
        if isMixed { return "Gives all \(selection.count) of them a shadow" }
        return selection.count > 1
            ? "Turns the shadow on or off for all \(selection.count) of them"
            : "Turns the shadow on or off"
    }

    private func shadowColorNote(_ shadows: LayerStyleSelection, at index: Int) -> String? {
        guard shadows.reading({ $0.shadow(at: index)?.colorHex ?? "#000000" }).isMixed else { return nil }
        return "Shadow colors differ. Picking one paints them all."
    }
}

/// What the shadow is painted, over every picked layer that has one.
///
/// Its own view because it sits in two places: beside Blur in the Shadow
/// section, and on the Shadow row of the parts list, where every other part
/// keeps its colour.
struct ShadowColorWell: View {
    @Environment(EditorState.self) private var editorState
    /// Which shadow in the layer's list this well paints.
    var index = 0

    var body: some View {
        let at = index
        let shadows = editorState.layerStyleSelection.shadows(at: at)
        let ids = shadows.layerIDs
        let reading = shadows.reading { $0.shadow(at: at)?.colorHex ?? "#000000" }
        // The same picker every other color row opens. A shadow keeps its own
        // Opacity slider in its settings, so the picker is not offered a second
        // one that would fight with it.
        ColorWellButton(hex: reading.value ?? "#000000",
                        name: "Shadow",
                        supportsOpacity: false,
                        // The same preview-and-commit path the Blur and Size
                        // sliders take, so a shadow recolours under the drag
                        // and lands in one step.
                        onPreview: { hex in
            editorState.previewLayerStyle(ids: ids) { $0.updateShadow(at: at) { $0.colorHex = hex } }
        }) { hex in
            editorState.previewLayerStyle(ids: ids) { $0.updateShadow(at: at) { $0.colorHex = hex } }
            editorState.commitLayerStyle(ids: ids)
            editorState.recordRecentColor(hex: hex)
        }
        .disabled(ids.isEmpty)
    }
}

/// How a style row writes a length. One place, so Blur and Size and Distance
/// cannot drift apart.
func points(_ value: Double) -> String { "\(Int(value.rounded())) pt" }

/// The revert arrow belongs to ONE layer's override of its component, so it is
/// offered only when the section is speaking for one layer. Over a selection
/// there is no single copy for it to answer for.
func soleLayerID(_ ids: [UUID]) -> UUID? { ids.count == 1 ? ids.first : nil }

/// What a style section says out loud before anything is dragged, and after:
/// how many layers it is talking to, and anything it is quietly skipping.
private func selectionCaption(_ count: Int, _ lead: String = "A slider here") -> String? {
    guard count > 1 else { return nil }
    return "\(count) layers. \(lead) changes every one of them, in one step."
}

/// The small print under a style section: what it skips, where the picked
/// layers differ, and how many it speaks for. Said only when there is
/// something to say — over one layer every row means what it always meant, and
/// a sentence explaining that is a sentence in the way.
struct SelectionStyleNotes: View {
    let notes: [String?]
    let caption: String?

    var body: some View {
        let lines = (notes + [caption]).compactMap { $0 }
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A labeled style slider wired to EditorState's preview/commit gesture
/// pattern, over every layer the row speaks for: dragging previews without
/// recording undo; release commits ONE step, however many layers it reached.
struct LayerStyleSlider: View {
    @Environment(EditorState.self) private var editorState
    /// The layers one pull on this slider changes.
    let layerIDs: [UUID]
    let label: String
    /// What the layers say: one number when they agree, Mixed when they do not.
    let reading: StyleReading<Double>
    let range: ClosedRange<Double>
    /// How the number is written when they agree.
    let format: (Double) -> String
    /// The part of the look this slider sets, when it is one a copy of a
    /// component can own. It puts the way back on the row itself, which is
    /// where the person who just dragged it is looking.
    var field: LayerStyleField? = nil
    let apply: (inout LayerStyle, Double) -> Void

    /// Where the knob sits. Over layers that differ this is the first picked
    /// layer's number, and it is a starting point rather than a claim: the
    /// readout beside it says Mixed.
    private var knob: Double {
        min(max(reading.value ?? range.lowerBound, range.lowerBound), range.upperBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                if let field, let only = soleLayerID(layerIDs) {
                    InstanceStyleRevert(layerID: only, field: field)
                }
                Spacer()
                Text(reading.isMixed ? LayerStyleSelection.mixedText : format(knob))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(MixedLook.style(reading.isMixed, otherwise: .secondary))
            }
            Slider(value: Binding(
                get: { knob },
                set: { v in editorState.previewLayerStyle(ids: layerIDs) { apply(&$0, v) } }),
                   in: range) { editing in
                if !editing { editorState.commitLayerStyle(ids: layerIDs) }
            }
            .controlSize(.small)
            .disabled(layerIDs.isEmpty)
            // Named so a walk can move it: a press lands in the middle of the
            // track, which is what putting the knob there by hand does. Without
            // this, everything in Effects could be photographed and never used.
            .playtestControl("Slider", detail: label)
        }
        // The row lends its word to whatever sits on it, so the revert arrow on
        // a Blur row reads as Blur's and not as the Border row's.
        .playtestField(label)
    }
}

// MARK: - Annotation inspector

/// The picked shapes' own settings: thickness, an arrow's caption and its
/// head — over the WHOLE selection.
///
/// Colors are not here: they live in the Color section, which is where they
/// live whatever is picked, so shift-clicking a second layer widens what a row
/// speaks for instead of moving it. These rows now work the same way. Pick two
/// arrows and Thickness is still there, speaking for both; pick an arrow and a
/// box and only the setting they share is offered, because a Head Size slider
/// over a rectangle is a control that does nothing.
///
/// Corners are not here either, for the same reason colors are not: rounding
/// is one row under Effects that speaks for everything picked, shapes and
/// screenshots alike.
///
/// Sliders preview live and commit one undo step on release, however many
/// shapes they reached.
struct AnnotationInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let selection = editorState.shapeSelection
        let ids = selection.layerIDs
        let rows = Self.visibleRows(selection)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.self) { row in
                    self.row(row, selection: selection, ids: ids)
                }
                // The label pills a hand has dragged, put back where the app
                // places them. Offered only while there is one to put back.
                if !selection.pinnedCaptionIDs.isEmpty,
                   Experiments.shared.arrowCaptionsEnabled {
                    let pinned = selection.pinnedCaptionIDs
                    Button(pinned.count > 1 ? "Reset label positions" : "Reset label position") {
                        editorState.resetCaptionPlacement(ids: pinned)
                    }
                    .font(.caption)
                    .controlSize(.small)
                    .panelHelp(pinned.count > 1
                          ? "Put all \(pinned.count) labels back where the app places them"
                          : "Put the label back where the app places it")
                }
                SelectionStyleNotes(notes: [selection.note],
                                    caption: selectionCaption(selection.count))
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 8)
        }
    }

    /// The rows this section actually shows, which is also what decides whether
    /// the section is there at all: a rectangle whose only setting was its
    /// Thickness brings no section once that width has moved into the Outline
    /// part, rather than an empty heading with its name on it.
    static func visibleRows(_ selection: ShapeSelection) -> [ShapeSettingRow] {
        selection.rows.filter { row in
            // Captions are a Next feature; without it an arrow is a plain
            // arrow and neither the field nor its size row belongs here.
            guard Experiments.shared.arrowCaptionsEnabled
                    || (row != .caption && row != .labelSize) else { return false }
            // Where the outline is a part that switches off — a box, an
            // ellipse — its width is that part's own setting and is called
            // Width there (`next-shape-parts`). Where the line IS the shape
            // the part has no switch and so no drawer, and the thickness
            // stays right here, in reach the moment the arrow is picked.
            return !(Experiments.shared.shapePartsEnabled && row == .thickness
                     && selection.widthIsAnOutlineSetting)
        }
    }

    @ViewBuilder
    private func row(_ row: ShapeSettingRow, selection: ShapeSelection, ids: [UUID]) -> some View {
        switch row {
        case .thickness:
            // The ONE width of the line round a shape. It reads whichever ring
            // is actually on screen, so a box drawn before the Effects Border
            // slider stopped reaching shapes still shows its width here, and a
            // pull moves that ring onto the stroke where it belongs.
            ShapeSlider(layerIDs: ids, label: "Thickness",
                        reading: selection.outlineWidth,
                        range: AnnotationStyles.strokeWidthRange,
                        format: { "\(Int($0.rounded())) pt" },
                        preview: { editorState.previewOutlineWidth(ids: $0, $1) },
                        commit: { editorState.commitOutlineWidth(ids: $0, $1) })
                .panelHelp(Experiments.shared.shapePartsEnabled
                      ? "How thick the line is. Its color is the Color row, in Appearance above"
                      : "How thick the line round the shape is. Its color is Outline, in the Color section above")
        case .caption:
            // ONE arrow only. A single field over three arrows could only give
            // all three the same words, and a caption is what the arrow says,
            // not how it looks.
            if let only = selection.members.first, selection.count == 1 {
                ArrowCaptionField(layerID: only.id)
            }
        case .labelSize:
            ShapeSlider(layerIDs: ids, label: "Label size",
                        reading: selection.number { $0.captionFontSize },
                        range: MeasureContent.labelSizeRangePx,
                        format: { "\(Int($0.rounded())) px" },
                        preview: { editorState.previewCaptionFontSize(ids: $0, $1) },
                        commit: { editorState.commitCaptionFontSize(ids: $0, $1) })
        case .labelCorners:
            ShapeSlider(layerIDs: ids, label: "Label corners",
                        reading: selection.number { $0.captionRoundness },
                        range: AnnotationContent.captionRoundnessRange,
                        format: { roundnessWord($0) },
                        round: { $0 },
                        preview: { editorState.previewCaptionRoundness(ids: $0, $1) },
                        commit: { editorState.commitCaptionRoundness(ids: $0, $1) })
                .panelHelp("How round the label's corners are, from a square box through a badge to a full pill")
        case .headStyle:
            // The one row in this section that is a picture rather than a
            // number, so it carries its own caption instead of a slider's.
            let ending = selection.reading { $0.arrowheadStyle }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Ending").font(.caption).foregroundStyle(.secondary)
                    // A glyph says what the ending IS while you are looking at
                    // the row; the word is what you remember it by afterwards.
                    if ending.isMixed {
                        MixedWord()
                    } else if let word = ArrowheadStylePicker.word(ending.value, isMixed: false) {
                        Text(word).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                ArrowheadStylePicker(selection: ending.value, isMixed: ending.isMixed) {
                    editorState.setArrowheadStyle(ids: ids, $0)
                }
            }
            .playtestField("Ending")
        case .headSize:
            ShapeSlider(layerIDs: ids, label: "Head Size",
                        reading: selection.number { $0.arrowheadScale },
                        range: AnnotationStyles.arrowheadScaleRange,
                        format: { "×\(String(format: "%.1f", $0))" },
                        round: { $0 },
                        preview: { editorState.previewAnnotationRestyle(ids: $0, arrowheadScale: $1) },
                        commit: { editorState.commitAnnotationRestyle(ids: $0, arrowheadScale: $1) })
        }
    }

    /// What the corner row says it is on. The two ends are shapes with names,
    /// because "Square" and "Pill" are what the user is actually after; the
    /// middle is how far it has travelled between them.
    private func roundnessWord(_ value: CGFloat) -> String {
        switch value {
        case ..<0.02: "Square"
        case 0.98...: "Pill"
        default: "\(Int((value * 100).rounded()))%"
        }
    }
}

/// The ONE Corner Radius row, under Effects, speaking for everything picked.
///
/// Rounding means two different things underneath: a rectangle curves the
/// outline it draws, so the curve follows its border, while a screenshot, a
/// frame or a group has its corners masked off. The panel used to carry a
/// slider for each, one in the shape's own section and one here, both labelled
/// Corner Radius, with nothing to say which was which. They also disagreed in
/// the worst way: the mask chopped the corners clean off a rectangle's
/// outline. So there is one row, it reads whichever number is rounding each
/// picked layer, and a pull writes back to whichever one rounds it properly.
///
/// Dragging previews without recording undo; release commits ONE step,
/// however many layers it reached.
struct CornerRadiusRow: View {
    @Environment(EditorState.self) private var editorState
    let selection: CornerRadiusSelection

    /// Where the knob is while the hand is on it, so it moves smoothly even
    /// though what it sends is whole points.
    @State private var draft: Double?

    private var range: ClosedRange<Double> { 0...selection.limit }

    private var knob: Double {
        min(max(draft ?? selection.reading.value ?? 0, range.lowerBound), range.upperBound)
    }

    /// Mixed only until the drag starts: once it has, they all wear the number
    /// under the knob.
    private var showsMixed: Bool { draft == nil && selection.reading.isMixed }

    var body: some View {
        let ids = selection.layerIDs
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Corner Radius").font(.caption).foregroundStyle(.secondary)
                if let only = selection.soleStyleRoundedID {
                    InstanceStyleRevert(layerID: only, field: .cornerRadius)
                }
                Spacer()
                Text(showsMixed ? LayerStyleSelection.mixedText : points(knob))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(MixedLook.style(showsMixed, otherwise: .secondary))
            }
            Slider(value: Binding(
                get: { knob },
                set: { v in
                    draft = v
                    editorState.previewCornerRadius(ids: ids, CGFloat(v.rounded()))
                }), in: range) { editing in
                if !editing {
                    editorState.commitCornerRadius(ids: ids, CGFloat((draft ?? knob).rounded()))
                    draft = nil
                }
            }
            .controlSize(.small)
            .disabled(ids.isEmpty)
            .playtestControl("Slider", detail: "Corner Radius")
        }
        .playtestField("Corner Radius")
    }
}

/// A shape-settings slider over every picked shape: dragging previews without
/// recording undo; release commits ONE step, however many shapes it reached.
///
/// While the shapes differ the readout says Mixed and the knob sits at the
/// first picked shape's number, so the position is a starting point rather
/// than a claim. The moment the knob moves they agree, and it says so.
struct ShapeSlider: View {
    let layerIDs: [UUID]
    let label: String
    let reading: StyleReading<CGFloat>
    let range: ClosedRange<CGFloat>
    let format: (CGFloat) -> String
    /// How this row rounds the number it sends. Thicknesses and radii are
    /// whole points; an arrowhead multiplier is not.
    var round: (CGFloat) -> CGFloat = { $0.rounded() }
    let preview: ([UUID], CGFloat) -> Void
    let commit: ([UUID], CGFloat) -> Void

    /// Where the knob is while the hand is on it, so it moves smoothly even
    /// though what it sends is rounded.
    @State private var draft: CGFloat?

    private var knob: CGFloat {
        min(max(draft ?? reading.value ?? range.lowerBound, range.lowerBound), range.upperBound)
    }

    /// Mixed only until the drag starts: once it has, they all wear the number
    /// under the knob.
    private var showsMixed: Bool { draft == nil && reading.isMixed }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(showsMixed ? LayerStyleSelection.mixedText : format(knob))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(MixedLook.style(showsMixed, otherwise: .secondary))
            }
            Slider(value: Binding(
                get: { knob },
                set: { v in
                    draft = v
                    preview(layerIDs, round(v))
                }), in: range) { editing in
                if !editing {
                    commit(layerIDs, round(draft ?? knob))
                    draft = nil
                }
            }
            .controlSize(.small)
            .disabled(layerIDs.isEmpty)
            .playtestControl("Slider", detail: label)
        }
        .playtestField(label)
    }
}

/// One arrow's caption. Its own view because it holds a draft and the keyboard:
/// typing edits the draft, and Return, Escape or clicking away all land or drop
/// it exactly once.
private struct ArrowCaptionField: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    @State private var captionDraft: String = ""
    @FocusState private var captionFocused: Bool
    /// True from the moment the field takes focus until its draft has been
    /// committed or dropped, so a field that disappears mid-edit (the arrow was
    /// deselected by a canvas click) still lands what was typed.
    @State private var captionEditing = false

    private var annotation: AnnotationContent? {
        editorState.document?.layer(id: layerID)?.annotation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Caption").font(.caption).foregroundStyle(.secondary)
            // As many lines as the caption has: a single line field showed a
            // two line label as its first line alone and landed that back on
            // the arrow the moment the field lost focus, quietly throwing the
            // second line away.
            TextField("Add a caption", text: $captionDraft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .focused($captionFocused)
                // The canvas field's keys, so the two fields for one label
                // agree: Return drops a line, Command and Return lands the
                // caption, Esc drops the draft and shows the arrow's caption
                // again. Both closing keys hand the keyboard to the picture.
                // Clearing `captionEditing` first is what stops the focus loss
                // that follows from landing the same words a second time.
                .onKeyPress(phases: .down) { press in
                    let key: ArrowCaptionEntry.Key
                    switch press.key {
                    case .return, KeyEquivalent("\u{3}"):
                        key = .return(command: press.modifiers.contains(.command))
                    case .escape: key = .escape
                    default: return .ignored
                    }
                    switch ArrowCaptionEntry.action(for: key) {
                    case .type: return .ignored
                    case .commit:
                        captionEditing = false
                        editorState.setAnnotationCaption(layerID: layerID, captionDraft)
                    case .cancel:
                        captionDraft = annotation?.caption ?? ""
                        captionEditing = false
                    }
                    KeyboardHandback.toCanvas()
                    return .handled
                }
                // Like every Mac text field, clicking away commits what you
                // typed (one undo step; none if unchanged). Not when the canvas
                // has just opened its own editor on this arrow: that editor
                // owns the draft now.
                .onChange(of: captionFocused) { _, focused in
                    if focused {
                        captionEditing = true
                    } else if captionEditing {
                        captionEditing = false
                        commitInspectorCaption()
                    }
                }
                .onDisappear {
                    if captionEditing {
                        captionEditing = false
                        commitInspectorCaption()
                    }
                }
        }
        // Track the model (initially, after undo, on layer switch); typing
        // edits only the draft until Return commits.
        .onChange(of: annotation?.caption ?? "", initial: true) { _, new in
            captionDraft = new
        }
        // The canvas opening its own editor on this arrow closes the
        // inspector's draft (one draft at a time): the field falls back to the
        // caption the canvas editor starts from. In practice the click that
        // opens the canvas editor takes focus first, so a pending draft has
        // already landed by then (verified on the probe app); this is the
        // fallback.
        .onChange(of: editorState.editingCaptionLayerID) { _, editing in
            if editing == layerID {
                captionEditing = false
                captionDraft = annotation?.caption ?? ""
            }
        }
    }

    /// The field landing its draft (Return or focus loss). Skipped while the
    /// canvas editor is open on the same arrow: the two fields share one draft
    /// and the canvas holds it.
    private func commitInspectorCaption() {
        guard editorState.editingCaptionLayerID != layerID else { return }
        editorState.setAnnotationCaption(layerID: layerID, captionDraft)
    }
}

/// The picked text layers' type (13.1): font face, size, weight and alignment,
/// over the WHOLE selection.
///
/// Pick three labels and one size reaches all three, in one undo step. Where
/// they differ the menu says Mixed and choosing anything makes them agree. The
/// ink is in the Color section with every other color; this is the type itself.
private extension TextAlign {
    /// The picture on this row's segment. `text.align*` is the system's own
    /// family for it, and a screen reader and a scripted walk both name the
    /// segment from the symbol, so these stay the standard ones.
    var symbolName: String {
        switch self {
        case .left: "text.alignleft"
        case .center: "text.aligncenter"
        case .right: "text.alignright"
        }
    }
}

private extension TextVerticalAlign {
    /// The same idea down the box.
    var symbolName: String {
        switch self {
        case .top: "align.vertical.top"
        case .middle: "align.vertical.center"
        case .bottom: "align.vertical.bottom"
        }
    }

    /// That picture, carrying the PLACE's name.
    ///
    /// A segment named itself out of the picture on it, and the three
    /// `align.vertical.*` symbols carry no description at all, so this row
    /// read out as nothing: a screen reader announced three anonymous buttons
    /// and a scripted walk skipped straight past them. (The Across row is fine
    /// by luck — the system happens to describe `text.align*` as "align left"
    /// and so on.) Built through `NSImage` the description is ours, so Top,
    /// Middle and Bottom each answer to their own word. The same way
    /// `ArrowheadStyle.glyph` names the endings; a SwiftUI
    /// `.accessibilityLabel` on the Image does not reach the segment.
    ///
    /// 11pt medium is the size `Image(systemName:)` already draws at inside a
    /// small segmented picker, so the pictures do not move: rendered both
    /// ways, light and dark, the row comes out pixel for pixel the same.
    var glyph: Image {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) else {
            return Image(systemName: symbolName)
        }
        let sized = image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)) ?? image
        sized.accessibilityDescription = title
        return Image(nsImage: sized)
    }
}

struct TextInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let selection = editorState.textSelection
        let ids = selection.layerIDs
        if !selection.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SelectionMenu(label: "Font",
                              reading: selection.reading { $0.fontName },
                              options: fontFamilies(selection),
                              title: { $0 },
                              help: help("font", selection.count),
                              pinnedWidth: Self.fontMenuWidth) {
                    editorState.setTextStyle(ids: ids, fontName: $0)
                }
                HStack(alignment: .top, spacing: 8) {
                    SelectionMenu(label: "Size",
                                  reading: selection.number { $0.fontSize },
                                  options: sizes(selection),
                                  // Padded out to three digits, so every size
                                  // takes the same room and the box holds one
                                  // width whatever the list picked up. The
                                  // padding is invisible; `spoken` is the same
                                  // words without it, for the sentence a
                                  // hover says.
                                  title: { TextStyles.sizeTitle($0) },
                                  spoken: { TextStyles.sizeWords($0) },
                                  help: help("size", selection.count)) {
                        editorState.setTextStyle(ids: ids, fontSize: $0)
                    }
                    SelectionMenu(label: "Weight",
                                  reading: selection.reading { $0.weight },
                                  options: TextWeight.allCases,
                                  title: { $0.rawValue.capitalized },
                                  help: help("weight", selection.count)) {
                        editorState.setTextStyle(ids: ids, weight: $0)
                    }
                }
                // Where the words sit inside their own boxes. Only tells while
                // a box is bigger than its words, which is what a box told to
                // stretch is (Next, `next-placement`).
                if Experiments.shared.placementEnabled { alignRow(selection, ids: ids) }
                SelectionStyleNotes(notes: [selection.note,
                                            Experiments.shared.placementEnabled
                                                ? selection.downTheBoxNote : nil],
                                    caption: selectionCaption(selection.count, "A change here"))
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 8)
        }
    }

    // The pictures on the two alignment rows. They live beside the row that
    // draws them, and both rows build their pictures AND their tooltips by
    // walking `allCases`, so a name can never end up under the wrong picture.

    /// Align: where the words sit across their box and down it.
    ///
    /// Two segmented controls rather than menus, because this is the one thing
    /// in the section that is read as a picture, and because every tool that
    /// has it draws it exactly this way. Layers that differ leave both controls
    /// showing nothing picked, which is the Mac's own way of saying Mixed on a
    /// row of buttons.
    private func alignRow(_ selection: TextLayerSelection, ids: [UUID]) -> some View {
        let across = selection.reading { $0.usedAlignment }
        let down = selection.reading { $0.usedVerticalAlignment }
        return HStack(alignment: .top, spacing: 8) {
            captioned("Across", isMixed: across.isMixed) {
                Picker("Words across the box", selection: Binding<TextAlign?>(
                    get: { across.isMixed ? nil : across.value },
                    set: { if let v = $0 { editorState.setTextAlignment(ids: ids, v) } })) {
                    ForEach(TextAlign.allCases, id: \.self) { align in
                        Image(systemName: align.symbolName).tag(TextAlign?.some(align))
                    }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small)
                // Left, Center, Right, one on each picture, from the same
                // `allCases` that built them.
                .segmentToolTips(TextAlign.allCases.map(\.title),
                                 fallback: across.isMixed
                                 ? "The picked layers sit their words differently across the box. Choosing one sets all of them."
                                 : "Where the words sit across the box")
            }
            captioned("Down", isMixed: down.isMixed) {
                Picker("Words down the box", selection: Binding<TextVerticalAlign?>(
                    get: { down.isMixed ? nil : down.value },
                    set: { if let v = $0 { editorState.setTextAlignment(ids: ids, v) } })) {
                    ForEach(TextVerticalAlign.allCases, id: \.self) { align in
                        align.glyph.tag(TextVerticalAlign?.some(align))
                    }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small)
                .segmentToolTips(TextVerticalAlign.allCases.map(\.title),
                                 fallback: down.isMixed
                                 ? "The picked layers sit their words differently down the box. Choosing one sets all of them."
                                 : "Where the words sit down the box")
            }
        }
    }

    /// A control with its name in a small caption above it, the way the rest of
    /// this dock labels things. Both alignment controls show nothing picked
    /// when the layers differ, so without a caption a blank row of buttons
    /// cannot say which of the two is the one that differs.
    ///
    /// And the caption is where the word Mixed goes, because a row of picture
    /// buttons has nowhere else to put it: lighting no segment says the layers
    /// differ and says a value was never set in exactly the same way, and those
    /// are different answers.
    ///
    /// It sits right after the row's own word rather than out at the trailing
    /// edge, where a slider's readout sits. Across and Down are two columns on
    /// one line, and a trailing Mixed lands hard against the next column's
    /// caption: the first build of this read "Across      Mixed  Down", which
    /// says nothing about which of the two differs. Beside its own word it can
    /// only mean one of them.
    @ViewBuilder private func captioned<Content: View>(_ label: String,
                                                       isMixed: Bool = false,
                                                       @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                if isMixed { MixedWord() }
                Spacer(minLength: 0)
            }
            content()
        }
        .playtestField(label)
    }

    /// What a menu says it is. Over a selection it says how far it reaches, so
    /// a menu reading Mixed also says what it is mixed about.
    private func help(_ part: String, _ count: Int) -> String {
        count > 1 ? "The \(part) of all \(count) selected layers" : "The \(part) of this text"
    }

    /// Curated families plus any the picked labels are already set in, so a
    /// label in an off-list font does not lose it just by being picked.
    private func fontFamilies(_ selection: TextLayerSelection) -> [String] {
        TextStyles.fontOptions(picked: selection.fontNames)
    }

    /// The width the Font menu holds, whatever is in its list.
    ///
    /// The curated families are in the list in every state it can be in, so the
    /// width they need is the narrowest the menu could ever be — and a pop-up
    /// never accepts a width wider than its content, so this is also the widest
    /// constant available. Every curated family therefore lands exactly where
    /// it does today, and only a longer name brought in by an opened document
    /// is shortened rather than shoving the row sideways.
    private static var fontMenuWidth: CGFloat {
        MenuMetrics.width(ofOptions: TextStyles.fonts)
    }

    /// Preset sizes plus any the picked labels already wear.
    private func sizes(_ selection: TextLayerSelection) -> [CGFloat] {
        let extra = selection.fontSizes.filter { !TextStyles.fontSizes.contains($0) }
        return extra.isEmpty ? TextStyles.fontSizes : (TextStyles.fontSizes + extra).sorted()
    }
}

/// A menu that speaks for the whole selection: the one thing they all say, or
/// the word Mixed. Choosing anything makes them agree — which is exactly what
/// the word is there to offer, so it is a real entry in the menu rather than a
/// blank box.
private struct SelectionMenu<Value: Hashable & Sendable>: View {
    let label: String
    let reading: StyleReading<Value>
    let options: [Value]
    let title: (Value) -> String
    /// The same value in the words a SENTENCE wants, when the words in the box
    /// are not those: the Size menu pads its numbers out with blank so every
    /// size takes the same room, and a hover must not read that blank back.
    /// Nil wherever the box already says exactly what it means.
    var spoken: ((Value) -> String)?
    /// What this menu is, in words, for anyone who hovers it. The caption above
    /// the menu says the same thing without being asked. When the box is too
    /// narrow for what it is showing, the full value is said here first.
    let help: String
    /// A width to hold, whatever ends up in the list. Nil for a menu whose list
    /// never changes, which is every menu but Font: those are already still.
    var pinnedWidth: CGFloat?
    let choose: (Value) -> Void

    /// The words the box is showing, when it is showing a value at all.
    private var shownTitle: String? {
        reading.isMixed ? nil : reading.value.map(title)
    }

    /// The same value as a sentence would say it, which is what a hover reads.
    private var saidTitle: String? {
        reading.isMixed ? nil : reading.value.map(spoken ?? title)
    }

    /// Whether the box had to shorten them.
    private var isClipped: Bool {
        guard let pinnedWidth, let shownTitle else { return false }
        return !MenuMetrics.fits(shownTitle, in: pinnedWidth)
    }

    var body: some View {
        // The caption sits above the menu, the way every other labelled
        // control in this dock reads (Effects sliders, Measure fields). A menu
        // showing Mixed is only useful if the row beside it says WHAT is
        // mixed, and with three menus in a row the shape of the word is not
        // enough: "Regular" and "Mixed" both look like a weight.
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Picker(label, selection: Binding<Value?>(
                get: { reading.isMixed ? nil : reading.value },
                set: { if let value = $0 { choose(value) } })) {
                if reading.isMixed {
                    // A closed pop-up button draws its own title, and
                    // `.foregroundStyle` on the Picker does not reach it (tried
                    // in the probe and photographed: the word stayed white).
                    // Styling the Text on the row does reach it, which is the
                    // only way this menu can say Mixed at the same strength the
                    // field and the slider beside it do.
                    Text(LayerStyleSelection.mixedText)
                        .foregroundStyle(MixedLook.style)
                        .tag(Value?.none)
                }
                ForEach(options, id: \.self) { option in
                    Text(title(option)).tag(Value?.some(option))
                }
            }
            .pickerStyle(.menu).labelsHidden().controlSize(.small)
            // Held to one width, so a name the list picked up from an opened
            // document cannot stretch the row. A pop-up takes a width smaller
            // than its content and shortens the closed title with an ellipsis,
            // which is what should happen to a name too long for the box; the
            // open menu still spells every name out in full.
            .frame(width: pinnedWidth)
            .accessibilityLabel(label)
        }
        // The caption names the row, and the row names the menu for a walk.
        // A menu wears its own value — "24 pt" one moment, "48 pt" the next —
        // so a walk that named it by its words would stop working the first
        // time it used it.
        .playtestField(label)
        // `panelHelp`, not `.help`, so the sentence a shortened name puts in
        // front is something a walk can read back. It is the same text either
        // way; the probe simply keeps a copy of it.
        .panelHelp(MenuTip.text(about: help, showing: saidTitle, isClipped: isClipped))
    }
}

/// Docked per-layer measure inspector (16.3): unit, label toggle, color, and the
/// document's pixel scale (so the points readout is correct on a Retina capture).
struct MeasureInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer
    @State private var nameDraft = ""
    /// Which layer `nameDraft` was typed for. Selecting another measurement
    /// while the field has focus drops focus AFTER `layer` has changed, and
    /// the draft must not land on the new selection.
    @State private var draftLayerID: UUID?
    @FocusState private var nameFocused: Bool
    /// Whether the read-only numbers at the foot of the section are unfolded.
    /// Remembered across selections and across launches, like the parts list's
    /// open row: someone checking coordinates all afternoon should not have to
    /// open the fold again on every measurement they click.
    @AppStorage(MeasureInspector.detailsOpenKey) private var isDetailsOpen = false
    static let detailsOpenKey = "inspector.measureDetailsOpen"

    private var content: MeasureContent? {
        editorState.document?.layer(id: layer.id)?.measure
    }

    /// The name the Measurements row shows: derived until renamed, then the
    /// custom name. The Name field edits exactly this.
    private var displayName: String {
        MeasureSpecList.displayName(for: editorState.document?.layer(id: layer.id) ?? layer)
    }

    var body: some View {
        if let c = content {
            VStack(alignment: .leading, spacing: 6) {
                // The same rename the Measurements row offers on double-click
                // (decision D3), reachable from Properties too. It commits
                // through the same call, so it is one undo step either way.
                if Experiments.shared.measurePanelEnabled {
                    row("Name") {
                        TextField("Measurement name", text: $nameDraft)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .focused($nameFocused)
                            .onSubmit { commitName() }
                            .nameFieldKeys(commit: { commitName() },
                                           revert: { nameDraft = displayName })
                            .onChange(of: nameFocused) { _, focused in
                                if !focused { commitName() }
                            }
                            .panelHelp("What this measurement is called in the Measurements "
                                  + "list and the copied spec list")
                    }
                    .id(layer.id)
                    .onAppear {
                        nameDraft = displayName
                        draftLayerID = layer.id
                    }
                    .onChange(of: displayName) { _, name in
                        if !nameFocused { nameDraft = name }
                    }
                }
                // The mock's Role control (§5, `next-measure-roles`): Size vs
                // Spacing, each with its own remembered color set. Alignment
                // guides are their own kind, so they don't offer it.
                if Experiments.shared.measureRolesEnabled, c.alignment == nil {
                    row("Role") {
                        Picker("Role", selection: Binding(
                            get: { c.role },
                            set: { editorState.setMeasureRole($0) })) {
                            Text("Size").tag(MeasureRole.size)
                            Text("Spacing").tag(MeasureRole.spacing)
                        }
                        .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                        .panelHelp("What this measurement calls out. Switching applies that "
                              + "role's remembered colors, and new measurements start "
                              + "with the last-used role.")
                    }
                }
                row("Unit") {
                    Picker("Unit", selection: Binding(
                        get: { c.unit },
                        set: { editorState.setMeasureUnit($0) })) {
                        // "Logical" = on-screen/design size (points); "Actual" =
                        // raw bitmap pixels (2× on a Retina screenshot).
                        Text("Logical").tag(MeasureUnit.points)
                        Text("Actual").tag(MeasureUnit.pixels)
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                    .panelHelp("Both read out in px. Logical is the on-screen size (like CSS px, the "
                          + "default); Actual is raw device pixels, 2× larger on a Retina screenshot.")
                }
                row("Thickness") {
                    Picker("Thickness", selection: Binding(
                        get: { c.strokeWidth },
                        set: { editorState.setMeasureThickness($0) })) {
                        Text("1 px").tag(CGFloat(1))
                        Text("2 px").tag(CGFloat(2))
                        Text("3 px").tag(CGFloat(3))
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                }
                row("Label size") {
                    // During a drag the committed doc hasn't changed, so read the
                    // live preview value (else the thumb snaps back / resets).
                    let liveScale = editorState.measureLabelPreview?.scale ?? c.labelScale
                    let px = liveScale * MeasureContent.labelFontSize
                    let lo = Double(MeasureContent.labelSizeRangePx.lowerBound)
                    let hi = Double(MeasureContent.labelSizeRangePx.upperBound)
                    HStack(spacing: 6) {
                        Slider(value: Binding(
                            get: { Double(px) },
                            set: { editorState.previewMeasureLabelScale(CGFloat($0) / MeasureContent.labelFontSize) }),
                               in: lo...hi,
                               onEditingChanged: { editing in
                                   if !editing {
                                       editorState.commitMeasureLabelScale(
                                           editorState.measureLabelPreview?.scale ?? c.labelScale)
                                   }
                               })
                            .controlSize(.small)
                        Text("\(Int(px.rounded())) px")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                // Three swatches, no extra sliders: Stroke = caliper ink + the
                // chip's border, Chip = the pill's fill (its picker carries the
                // opacity slider, so "no chip" is just alpha 0), Text = readout.
                // Whole-object transparency lives in Effects, where every layer's
                // does.
                swatchRow("Stroke", hex: c.strokeColorHex) {
                    editorState.setMeasureStrokeColor($0, commit: true)
                }
                // The chip's opacity IS its alpha, so the picker's opacity
                // slider writes it: "no chip" is alpha 0 rather than a separate
                // switch.
                swatchRow("Chip", hex: chipHex(c), supportsOpacity: true) { picked in
                    let rgba = RGBA(hex: picked)
                    editorState.setMeasureChipColor(rgba?.hexString ?? picked,
                                                    opacity: rgba?.a ?? 1, commit: true)
                }
                swatchRow("Text", hex: c.textColorHex) {
                    editorState.setMeasureTextColor($0, commit: true)
                }
                if Experiments.shared.measurePanelEnabled {
                    detailsSection(c)
                }
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 8)
        }
    }

    /// Commits the Name field the way the row's double-click rename does: a
    /// trimmed, non-empty name that differs from what the row already shows.
    /// Clearing the field just puts the current name back.
    private func commitName() {
        guard draftLayerID == layer.id else { return }
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != displayName else {
            nameDraft = displayName
            return
        }
        editorState.renameLayer(id: layer.id, to: trimmed)
    }

    /// The foot of the section: the one action that belongs beside a picked
    /// measurement, and a fold holding every number it can tell you about
    /// itself.
    ///
    /// The numbers used to sit open, and between them and the spec-line preview
    /// they were half the section's height — which is how the section came to
    /// be 470pt tall against a 344pt slot and could not be made to fit by any
    /// ordering of the dock. None of them is a setting: Distance restates the
    /// number already drawn on the canvas, Units restates the Unit row three
    /// rows above, and the spec line restates both. So they fold, the way a
    /// part's settings fold in the parts list, and the fold is remembered
    /// across launches: open it once and it stays open.
    @ViewBuilder private func detailsSection(_ c: MeasureContent) -> some View {
        Divider().opacity(0.4)
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.14)) { isDetailsOpen.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(isDetailsOpen ? 90 : 0))
                    Text("Details").font(.caption)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .panelHelp("Where this measurement's feet sit, how far apart they are, and the "
                  + "exact line Copy Measurement puts on the clipboard")
            .playtestControl("Details", detail: isDetailsOpen ? "open" : "closed")
            Spacer(minLength: 0)
            Button("Copy Measurement") { editorState.copyMeasurement(id: layer.id) }
                .controlSize(.small)
                .panelHelp("Copies this one measurement's spec line as text, ready to paste into a thread")
        }
        .playtestField("Details")
        if isDetailsOpen {
            VStack(alignment: .leading, spacing: 4) {
                geometryGrid(c)
                // The exact line that lands on the clipboard, so the button
                // needs no explaining. Selectable, like the readouts above it.
                if let line = specLine {
                    Text(line)
                        .font(.caption2).monospaced().foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.tail)
                        .textSelection(.enabled)
                }
            }
            .transition(.opacity)
        }
    }

    /// The mock's read-only From / To / Distance / Units grid (§6): the feet in
    /// document coordinates and the span, straight from `caliperGeometry()` —
    /// no new model state. A guide (§9) reads Length instead of Distance, and
    /// adds the edge it settled on and how many things it checked.
    @ViewBuilder private func geometryGrid(_ c: MeasureContent) -> some View {
        let frame = editorState.document?.layer(id: layer.id)?.frame ?? layer.frame
        let g = c.caliperGeometry()
        let scale = editorState.document?.pixelScale ?? 1
        VStack(alignment: .leading, spacing: 4) {
            readoutRow("From", point(g.footA, in: frame, scale: scale))
            readoutRow("To", point(g.footB, in: frame, scale: scale))
            readoutRow(c.alignment == nil ? "Distance" : "Length",
                       String(format: "%.\(max(0, c.decimals))f %@",
                              c.displayDistance(pixelScale: scale), c.unit.suffix))
            if let check = c.alignment {
                readoutRow("Edge", edgeReadout(c, check, in: frame, scale: scale))
                readoutRow("Items", itemsReadout(check))
            }
            readoutRow("Units", c.unit == .points ? "Logical px" : "Actual px")
        }
    }

    /// Which edge the guide settled on and where it is, in the measure's unit:
    /// "Left, x 312 px", or just "x 312 px" when the scan could not tell the
    /// side. The position is the reference line, which is where the guide
    /// itself sits once committed.
    private func edgeReadout(_ c: MeasureContent, _ check: AlignmentCheck,
                             in frame: CGRect, scale: CGFloat) -> String {
        guard let verdict = check.verdict else { return "no edges" }
        let position: String
        switch c.mode {
        case .vertical:
            let x = c.displayValue(frame.minX + verdict.reference, pixelScale: scale)
            position = "x \(Int(x.rounded())) \(c.unit.suffix)"
        case .horizontal:
            let y = c.displayValue(frame.minY + verdict.reference, pixelScale: scale)
            position = "y \(Int(y.rounded())) \(c.unit.suffix)"
        }
        guard let edge = c.alignedEdge else { return position }
        return "\(edge.word), \(position)"
    }

    /// How many elements the guide checked, and how many are off: "4 items" /
    /// "4 items, 1 off". A check whose items are raw edge runs (no pixels were
    /// read, or an older guide) says "not counted" rather than a wrong number.
    private func itemsReadout(_ check: AlignmentCheck) -> String {
        let count = check.itemsAreElements
            ? MeasureSpecList.countPhrase(check.items.count) : "not counted"
        guard let verdict = check.verdict, !verdict.isAligned else { return count }
        return "\(count), 1 off"
    }

    /// A document coordinate in the measure's unit, "x, y".
    private func point(_ p: CGPoint, in frame: CGRect, scale: CGFloat) -> String {
        guard let c = content else { return "" }
        let x = c.displayValue(frame.minX + p.x, pixelScale: scale)
        let y = c.displayValue(frame.minY + p.y, pixelScale: scale)
        return "\(Int(x.rounded())), \(Int(y.rounded()))"
    }

    /// One read-only line of the grid: caption left, value right, selectable so
    /// a number can be copied straight out of the inspector.
    @ViewBuilder private func readoutRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
                .frame(width: Self.labelWidth, alignment: .leading)
            Text(value)
                .font(.caption)
                .monospacedDigit()
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    /// The spec line Copy Measurement puts on the clipboard, live from the
    /// document so a recolor, rename or unit change updates it in place.
    private var specLine: String? {
        guard let document = editorState.document,
              let current = document.layer(id: layer.id) else { return nil }
        return MeasureSpecList.specLine(for: current, in: document)
    }

    /// One setting, on one line: its name on the left, its control on the
    /// right, the way the colour rows below already read.
    ///
    /// These used to stack the caption on its own line ABOVE a full-width
    /// control, which is the Effects panel's shape. It is the wrong shape here:
    /// every control in this section — two segments, three segments, a short
    /// slider — is about half the column wide, so the caption line bought
    /// nothing and cost a line of height each time, and the section ended up
    /// speaking two row languages, stacked at the top and inline at the bottom.
    /// One language, five lines shorter.
    @ViewBuilder private func row<Content: View>(_ label: String,
                                                 @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
                .frame(width: Self.labelWidth, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .playtestField(label)
    }

    /// Wide enough for "Thickness" and "Label size", the two longest names in
    /// the section, so every control in it starts at the same left edge.
    private static let labelWidth: CGFloat = 62

    /// One color row: caption on the left, swatch next to it, so the three
    /// swatches line up in a column.
    /// The chip's color and its opacity as one string, because to the picker
    /// they are one color.
    private func chipHex(_ measure: MeasureContent) -> String {
        var rgba = RGBA(hex: measure.chipColorHex) ?? RGBA(r: 1, g: 1, b: 1)
        rgba.a = measure.chipOpacity
        return rgba.hexStringWithAlpha
    }

    @ViewBuilder private func swatchRow(_ label: String, hex: String,
                                        supportsOpacity: Bool = false,
                                        set: @escaping (String) -> Void) -> some View {
        row(label) {
            ColorWellButton(hex: hex, name: label, supportsOpacity: supportsOpacity, onCommit: set)
        }
    }
}

// MARK: - Canvas inspector (the Canvas pseudo-layer)

struct CanvasInspector: View {
    @Environment(EditorState.self) private var editorState
    @State private var width: Double = 0
    @State private var height: Double = 0

    private var canvasSize: CGSize { editorState.document?.canvasSize ?? .zero }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                dimensionField("W", $width)
                dimensionField("H", $height)
                Spacer()
                Button("Canvas Size…") { editorState.isCanvasSizeDialogPresented = true }
                    .controlSize(.small)
                    .panelHelp("Numeric resize with a content-anchor picker")
            }
            Text("Drag the canvas edges to add or trim space; content stays put on the side you didn't move. Fields grow to the right/bottom.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            newSpaceRow
            if Experiments.shared.canvasGridEnabled {
                Divider().padding(.vertical, 2)
                gridSection
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
        .onAppear { syncFields() }
        .onChange(of: canvasSize) { syncFields() }
    }

    /// Which colour the space a canvas grows into arrives in.
    ///
    /// It is the background fill, the same colour ⌫ clears a locked background
    /// to, and its only other home on screen is the paint bucket's swatches.
    /// Adding space is the one place that colour lands on the picture without
    /// anyone typing a shortcut, so it belongs beside the sentence that
    /// explains how to add it: what happens next is stated where the doing is,
    /// and it can be changed there rather than by picking up a tool you did not
    /// want. The canvas paints the same colour into the proposed space while an
    /// edge is being dragged, so this row and the picture agree.
    @ViewBuilder private var newSpaceRow: some View {
        HStack(spacing: 8) {
            Text("New space").font(.caption).foregroundStyle(.secondary)
            ColorWellButton(hex: editorState.backgroundFillHex, name: "Background fill",
                            wellKey: "canvas.background") { editorState.backgroundFillHex = $0 }
            Spacer()
        }
        .padding(.top, 2)
    }

    // MARK: The grid you build against (Next, `next-canvas-grid`)

    /// The grid's numbers, on the Canvas, because that is what the grid
    /// belongs to. They are ALSO on the chip in the tool bar and on View ▸
    /// Grid Settings, because "click the Canvas row first" is not how anyone
    /// looks for them — see `CanvasGridControls`, which is the one copy of
    /// these controls that all three places draw.
    ///
    /// Nothing here is saved in the document: it is a view preference the app
    /// remembers between launches, and every window shows the same one.
    @ViewBuilder private var gridSection: some View {
        // The panel column is narrower than the popover, so the labels get
        // less of it and the controls keep their room.
        CanvasGridControls(labelWidth: 78)
    }

    private func syncFields() {
        width = Double(canvasSize.width)
        height = Double(canvasSize.height)
    }

    private func dimensionField(_ label: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: value,
                      format: .number.precision(.fractionLength(0)).grouping(.never))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
                .onSubmit { applyDimensions() }
                // The same two finishing keys the layer's own numbers answer:
                // a canvas size typed and finished with lets go of the keyboard
                // so the next letter picks a tool.
                .numberFieldKeys(
                    commit: { applyDimensions() },
                    revert: { syncFields() },
                    step: { direction, coarse in
                        let stepped = LayerGeometry.stepped(value.wrappedValue,
                                                            direction: direction, coarse: coarse)
                        value.wrappedValue = max(1, Double(stepped))
                        applyDimensions()
                    })
        }
    }

    private func applyDimensions() {
        let size = CGSize(width: max(1, width.rounded()), height: max(1, height.rounded()))
        guard size != canvasSize else { return }
        editorState.setCanvasSize(to: size, anchor: .topLeft)
    }
}

// MARK: - Collage inspector (16.9)

struct CollageInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer

    private var content: CollageContent? {
        editorState.document?.layer(id: layer.id)?.collage
    }

    var body: some View {
        if let c = content {
            VStack(alignment: .leading, spacing: 8) {
                field("Layout") {
                    Picker("Layout", selection: Binding(
                        get: { c.template },
                        set: { value in editorState.updateCollage(layerID: layer.id) { $0.template = value } })) {
                        ForEach(CollageTemplate.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                }
                field("Photos") {
                    Stepper("\(c.slots.count) slots", value: Binding(
                        get: { c.slots.count },
                        set: { value in editorState.updateCollage(layerID: layer.id) { $0.setSlotCount(value) } }),
                        in: 1...12)
                        .font(.caption).controlSize(.small)
                }
                field("Spacing") {
                    Stepper("\(Int(c.gutter)) px", value: Binding(
                        get: { Int(c.gutter) },
                        set: { value in editorState.updateCollage(layerID: layer.id) { $0.gutter = CGFloat(value) } }),
                        in: 0...200, step: 4)
                        .font(.caption).controlSize(.small)
                }
                HStack {
                    Toggle("Backdrop", isOn: Binding(
                        get: { c.backdropColorHex != nil },
                        set: { on in
                            editorState.updateCollage(layerID: layer.id) {
                                $0.backdropColorHex = on ? "#FFFFFF" : nil
                            }
                        }))
                        .font(.caption).controlSize(.small)
                    Spacer()
                    if let hex = c.backdropColorHex {
                        ColorWellButton(hex: hex, name: "Backdrop") { newHex in
                            editorState.updateCollage(layerID: layer.id) { $0.backdropColorHex = newHex }
                            editorState.recordRecentColor(hex: newHex)
                        }
                    }
                }
                Text("Drop photos from the history or Finder into a cell; drag a photo layer onto a cell to absorb it; drag between cells to swap.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private func field<Content: View>(_ label: String,
                                                   @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .playtestField(label)
    }
}
