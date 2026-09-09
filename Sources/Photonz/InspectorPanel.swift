// The docked right hand panel itself: which sections it shows, how it shares out its height between them, and how it scrolls to the one you just picked.

import AppKit
import PhotonzCore
import SwiftUI

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
    /// The panes a list section is made of, for the lists that are stacks of
    /// small panes rather than stacks of rows. Only Effects reports these, and
    /// they decide its floor: see `DockHeightBudget.paneListFloor`.
    var listPanes: [InspectorSectionID: [DockHeightBudget.Block]] = [:]
    /// Which of those panes you just opened, by its place in the list. That is
    /// the one the floor pays to draw whole; nil means nobody has said, and the
    /// first open pane stands in.
    var listFocus: [InspectorSectionID: Int] = [:]
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
    /// The breathing room under every section body, inside the part the dock
    /// may shorten. A floor has to pay for it too, or a body drawn at exactly
    /// its floor is six points short of its own content and fades an edge that
    /// has nothing past it.
    static let bodyBottomPadding: CGFloat = 6
    /// How much of the NEXT thing a shortened body keeps on screen. Deeper than
    /// the fade, so what shows through it is a heading somebody can read the
    /// top of rather than a smudge, and it is the difference between a cut that
    /// says "there is more" and one that says "that is all".
    static let bodyPeek: CGFloat = bodyEdgeFade + 8
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
                                onHeaderHeight: { budget.headers[id] = $0 },
                                onBodyFrame: { reveal.bodyFrames[id] = $0 }
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
                            reveal.sectionFrames[id] = frame
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
            // You opened an effect: put the settings that just appeared where
            // you can see them.
            .onChange(of: editorState.effectToReveal) { _, id in
                guard let id else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.effectRevealDelay) {
                    applyEffectReveal(proxy, for: id)
                }
            }
            // You picked something: put the section named after it where you
            // can see it. Both stores, because a plain click and a shift click
            // are the same act as far as the panel is concerned.
            .onChange(of: editorState.selectedLayerID) { requestPickedReveal(proxy) }
            .onChange(of: editorState.multiSelectedLayerIDs) { requestPickedReveal(proxy) }
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
        // The dock's own padding above the first section and below the last is
        // room no section can have.
        let room = budget.viewportHeight.map { $0 - 2 * InspectorPanel.listTopPadding }
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
                                          floor: squeezeFloor(for: id, room: room))
        }
        let heights = DockHeightBudget.flexibleHeights(groups, viewport: room)
        var ceilings: [InspectorSectionID: CGFloat] = [:]
        for id in sections {
            let natural = budget.bodies[id] ?? 0
            defer {
                // What the budget did to this section, in numbers a scripted
                // walk can read back: "Effects was drawn 129 tall and its open
                // Border needs 129" is a claim, and a capture is not.
                if heights[id.rawValue] != nil {
                    recordInspectorListRoom(id, natural: natural,
                                            drawn: ceilings[id] ?? natural,
                                            panes: budget.listPanes[id] ?? [],
                                            focus: budget.listFocus[id],
                                            spacing: EffectsListInspector.paneSpacing,
                                            topInset: EffectsListInspector.listInset,
                                            bottomInset: EffectsListInspector.listInset
                                                + InspectorPanel.bodyBottomPadding,
                                            peek: InspectorPanel.bodyPeek,
                                            room: room)
                }
            }
            guard let height = heights[id.rawValue],
                  // Only when it is actually being shortened. A section given
                  // exactly its own height gains nothing from a scroller.
                  height < natural - PanelAreaResize.tolerance else { continue }
            ceilings[id] = height
        }
        return ceilings
    }

    /// How short a list section may be squeezed.
    ///
    /// Three rows for a list of rows, which is the ordinary case: layers,
    /// measurements, the Library shelf. A list of PANES asks for more, because
    /// a pane cut across the middle shows half a slider rather than most of a
    /// row — see `DockHeightBudget.paneListFloor`, and the Border the user was
    /// handed sliced in two on 2026-09-08. Which pane it pays for is the one
    /// you just opened, so opening the second of two effects in a short window
    /// makes room for the second rather than for the first.
    private func squeezeFloor(for id: InspectorSectionID, room: CGFloat?) -> CGFloat {
        guard let panes = budget.listPanes[id], !panes.isEmpty else {
            return InspectorPanel.listFloor
        }
        return DockHeightBudget.paneListFloor(
            panes,
            focus: budget.listFocus[id],
            spacing: EffectsListInspector.paneSpacing,
            topInset: EffectsListInspector.listInset,
            bottomInset: EffectsListInspector.listInset + InspectorPanel.bodyBottomPadding,
            peek: InspectorPanel.bodyPeek,
            base: InspectorPanel.listFloor,
            viewport: room)
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

    // MARK: Bringing an opened effect into view

    /// How long to wait before scrolling to an effect that has just been
    /// opened: a shade longer than the fold's own spring, so the pane is
    /// measured at the height it has settled at rather than partway through
    /// growing into it.
    private static let effectRevealDelay = 0.24

    /// An effect's settings have just appeared. Bring the whole pane on screen,
    /// and only if it is not already there.
    ///
    /// The pane is measured in the dock's visible area rather than in the
    /// Effects list, because the list can be inside a scroller of its own when
    /// the panel is over-subscribed: an effect can be perfectly placed in its
    /// list and still be somewhere nobody can see. One `scrollTo` covers both,
    /// since the pane is identified in the list SwiftUI is scrolling either
    /// way.
    private func applyEffectReveal(_ proxy: ScrollViewProxy, for id: String) {
        // A second chevron pressed while this one was waiting: that press has
        // its own wait running, and it is measured from ITS fold rather than
        // from this one, so this turn is simply given up.
        guard editorState.effectToReveal == id else { return }
        editorState.effectRevealHandled()
        guard let frame = reveal.effectFrames[id],
              let here = reveal.room(for: .effects) else { return }
        // Where it stands now. Already all there and nothing moves: pressing a
        // chevron on an effect you can see must never make the panel jump.
        guard DockReveal.action(sectionTop: frame.minY - here.top,
                                sectionHeight: frame.height,
                                viewportHeight: here.height) != .none else {
            recordEffectReveal(id, frame: frame, room: here.height, action: .none)
            return
        }
        // Something has to move, so the dock takes its turn first: an Effects
        // list hanging past the bottom of the panel is room the effect could
        // have had, and gaining it is why the list has to be asked second,
        // against the room it will have rather than the room it has.
        let dock = DockReveal.action(sectionTop: reveal.sectionFrames[.effects]?.minY ?? 0,
                                     sectionHeight: reveal.sectionFrames[.effects]?.height ?? 0,
                                     viewportHeight: reveal.viewportHeight)
        let shift = reveal.shift(of: .effects, doing: dock)
        guard let room = reveal.room(for: .effects, shiftedBy: shift) else { return }
        let action = DockReveal.action(sectionTop: frame.minY + shift - room.top,
                                       sectionHeight: frame.height,
                                       viewportHeight: room.height)
        recordEffectReveal(id, frame: frame, room: room.height, action: action)
        withAnimation(.easeInOut(duration: 0.24)) {
            if dock != .none {
                proxy.scrollTo(InspectorSectionID.effects, anchor: dock == .top ? .top : .bottom)
            }
            if action != .none {
                proxy.scrollTo(id, anchor: action == .top ? .top : .bottom)
            }
        }
    }

    // MARK: Bringing what you just picked into view

    /// How long to wait after a pick before scrolling to the section it brought
    /// up. A section that has just appeared is built a pass after the click
    /// (see `PanelSectionArrival`) and the lists above it settle to their new
    /// heights in the pass after that, so a reveal measured any sooner is
    /// measuring a dock that is still moving.
    private static let pickRevealDelay = 0.24

    /// You clicked a layer — in the list or on the canvas. Bring the section
    /// named after it into view, so the settings for the thing you just picked
    /// are the ones you can see.
    ///
    /// Only the pick's OWN section: the dock is routinely taller than the panel
    /// (a marked-up screenshot runs about 1100pt in a 690pt panel), so
    /// something is always off screen, and the one thing that must not be is
    /// what you just clicked. Everything general — Appearance, Effects,
    /// Position & Size — keeps whatever place the reader left it in.
    private func requestPickedReveal(_ proxy: ScrollViewProxy) {
        reveal.pickPass &+= 1
        let pass = reveal.pickPass
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pickRevealDelay) {
            guard reveal.pickPass == pass else { return }
            applyPickedReveal(proxy)
        }
    }

    private func applyPickedReveal(_ proxy: ScrollViewProxy) {
        // The Library shelf asked first and is mid-flight; two scrollers
        // fighting over the same dock is worse than either one losing.
        guard !reveal.isPending else { return }
        guard let id = pickedSection, let frame = reveal.sectionFrames[id] else { return }
        let action = DockReveal.action(sectionTop: frame.minY,
                                       sectionHeight: frame.height,
                                       viewportHeight: reveal.viewportHeight)
        recordPickedReveal(sectionTitle(id), frame: frame,
                           viewport: reveal.viewportHeight, action: action)
        // Already all there: picking a second piece of text while its section
        // is under your eyes must not make the dock twitch.
        guard action != .none else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            proxy.scrollTo(id, anchor: action == .top ? .top : .bottom)
        }
    }

    /// The section named after what is picked, or nil when what is picked has
    /// none of its own.
    ///
    /// A plain rectangle is the nil case and it is the ordinary one: since the
    /// parts list landed, everything a rectangle owns is a row inside
    /// Appearance, which sits high in the dock and needs no help. Only the
    /// kinds that still carry a section of their own — a piece of text, a
    /// measurement, a zoom callout, an arrow's head and caption, a collage —
    /// are worth moving the dock for.
    ///
    /// The Canvas section is deliberately NOT one of them. Clicking empty space
    /// is how you put something down, not how you ask about the canvas, and a
    /// dock that jumped every time you deselected would be jumping most of the
    /// time.
    private var pickedSection: InspectorSectionID? {
        let available = availableSections
        return Self.pickedSections.first { $0 != .canvas && available.contains($0) }
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
            //
            // Present for ANYTHING unlocked, not just for things with a colour.
            // Opacity leads this section and it is the one thing every layer
            // has, so gating the section on there being a paintable part took
            // the opacity away from everything that paints nothing of its own:
            // a copy of a component, and an unlocked picture. A faded copy then
            // had no Opacity row to carry the way back to the original's
            // opacity, and a screenshot could not be faded at all. (A plain
            // group is fine either way: picking one reaches the shapes inside
            // it, and those have colours.)
            if editorState.hasRestylableSelection { set.insert(.color) }
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
                EffectsListInspector(onPanes: {
                                         budget.listPanes[.effects] = $0
                                         budget.listFocus[.effects] = $1
                                     },
                                     onPaneFrame: { reveal.effectFrames[$0] = $1 })
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
            } else if editorState.selectedTextStyle != nil {
                LibraryTextStyleInspector()
            } else if editorState.selectedEffectStyle != nil {
                LibraryEffectStyleInspector()
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
    /// How many picks the dock has seen. A reveal waits a beat for the section
    /// it is about to scroll to to finish being laid out, and this is how the
    /// wait knows it is still the newest one: click three rows quickly and only
    /// the third moves the dock.
    var pickPass = 0
    /// Where each effect in the Effects list is sitting, by
    /// `LayerEffectRow.id`, in the dock's visible area. Written on every scroll
    /// tick and read only when an effect has just been opened.
    var effectFrames: [String: CGRect] = [:]
    /// Where each section's body is drawn, in the same coordinates.
    var bodyFrames: [InspectorSectionID: CGRect] = [:]
    /// ...and each whole section, header and all, which is what the dock's own
    /// scroller moves.
    var sectionFrames: [InspectorSectionID: CGRect] = [:]

    /// The band of the dock a thing inside `section` can be seen in: what the
    /// section is drawing, less whatever of that has scrolled off the dock.
    ///
    /// The two are different whenever the dock is over-subscribed, and that
    /// difference is the whole reason this exists: an effect can have 255pt of
    /// settings and 153pt of list to show them in, and a reveal that measured
    /// itself against the dock would scroll the effect's heading off the top
    /// to line its foot up with a bottom edge nobody can see.
    func room(for section: InspectorSectionID, shiftedBy shift: CGFloat = 0)
        -> (top: CGFloat, height: CGFloat)? {
        guard viewportHeight > 0 else { return nil }
        guard let body = bodyFrames[section] else { return (0, viewportHeight) }
        let top = max(body.minY + shift, 0)
        let bottom = min(body.maxY + shift, viewportHeight)
        guard bottom > top else { return nil }
        return (top, bottom - top)
    }

    /// How far the dock would carry `section` if it scrolled to it: the number
    /// the reveal needs to work out what room the section will have AFTER the
    /// dock has moved, rather than the room it has now.
    func shift(of section: InspectorSectionID, doing action: DockReveal.Action) -> CGFloat {
        guard let frame = sectionFrames[section] else { return 0 }
        return switch action {
        case .none: 0
        case .top: -frame.minY
        case .bottom: viewportHeight - frame.maxY
        }
    }
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
