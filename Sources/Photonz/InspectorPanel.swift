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

// MARK: - Docked inspector panel

/// The full-height, docked right-side inspector (10.5). Holds collapsible,
/// drag-reorderable sections — Layers, Annotation, Effects, Shadow. Order and
/// collapsed state persist across launches; the panel width is set by the 1px
/// `InspectorResizeHandle` on its left edge.
struct InspectorPanel: View {
    @Environment(EditorState.self) private var editorState
    @StoredSetting(InspectorPanel.sectionOrderKey) private var orderRaw = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which one-time section moves this panel's saved order has had. See
    /// `loadOrder`.
    @StoredSetting(InspectorPanel.sectionOrderVersionKey) private var orderVersion = 0
    /// What the dock remembers about its own sections between launches, named
    /// so a scripted walk that rearranges them can put them back.
    static let sectionOrderKey = "inspector.sectionOrder"
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
    /// ...and then the section named after the thing you picked rose above
    /// THEM, so it is the first thing under the layers list. This is the order
    /// half of the one dock rule in `InspectorDockLayout.swift`: the user chose
    /// it on 2026-09-13 over a panel that scrolled itself to each pick, and it
    /// is why there is no longer any reveal on selection at all.
    private static let orderVersionPickedUnderLayers = 5
    /// ...and then Position & Size, with Arrange and Component beside it, rose
    /// above Appearance and Effects, so the plainest fact about a layer — where
    /// it is and how big it is — no longer sits below the bottom edge.
    ///
    /// Measured on 2026-09-15: a piece of text picked in a three layer document
    /// asked the dock for 1052 points against the 688 a laptop window gives and
    /// the 968 the largest window on this display gives, so the X, Y, width and
    /// height boxes were off the bottom at EVERY window size. The dock is over
    /// by a factor rather than by a few points — the forms alone come to 551
    /// and every list is already drawn at its floor — so nothing the budget can
    /// do reaches this. The only question a dock that big answers is which
    /// sections are above the fold, and this is the answer: what you picked,
    /// then where it sits, then what it looks like. It is the order the
    /// Component move (2) was already written for.
    ///
    /// The cost, and it is a real one: Appearance drops by the height of
    /// Position & Size, so with an arrow or a measurement picked — the two
    /// whose Appearance runs to 382 and 525 points — its last rows are below
    /// the fold on a laptop window where they used to be on screen.
    private static let orderVersionSizeAboveLook = 6
    /// ...and Motion came back up to sit directly under Effects, where it has
    /// said it belongs since the day it shipped.
    ///
    /// It is read the same way the Effects list is read — a header with a plus,
    /// rows with a switch and a name and a summary, settings that unfold — and
    /// learning one is meant to teach you the other. Move 4 lifted Appearance
    /// and Effects up under Layers and left Motion where it was declared, which
    /// put ELEVEN sections between them: pick a screen and Frame, Columns and
    /// Layout all sat in the gap, so animating an icon meant scrolling past
    /// every screen setting in the panel.
    private static let orderVersionMotionUnderEffects = 7

    /// Reframe sits directly above Motion (Next, `next-punch-in-and-hold`).
    /// They are the same move at two altitudes: Reframe is the whole camera
    /// move in two buttons, Motion is the two properties it is made of. The
    /// short way round comes first, and the parts are under it for anybody who
    /// wants to tune the timing.
    private static let orderVersionReframeAboveMotion = 8
    /// Animating, the list of what is keyed, above Reframe and Motion: those
    /// are two ways of making a move, and this is what is moving
    /// (`PropertyKeysInspector`).
    private static let orderVersionKeysAboveReframe = 9
    /// The sections named after the thing you have picked, in the order they
    /// sit in. One list, so the migration and the rule stay the same sentence.
    private static let pickedSections: [InspectorSectionID] =
        [.annotation, .callout, .lens, .text, .measure, .collage, .canvas]
    /// Where the picked thing SITS: its place on the canvas, what it is placed
    /// against, and what it is a copy of. They travel together because they
    /// answer one question at three scales, and because splitting them would
    /// put Arrange below Effects on a multiple selection while the boxes it
    /// aligns stayed above.
    private static let placeSections: [InspectorSectionID] = [.arrange, .component, .geometry]

    /// Every one-time move the dock's saved order has had, in the order they
    /// were written. The ones marked for the split belong to the release that
    /// has it: a move that is skipped is not counted as done, so turning the
    /// release on later still runs it.
    @MainActor private static func orderMigrations() -> [PanelSectionOrder.Migration] {
        let split = Experiments.shared.shapePartsEnabled
        return [
            .init(version: orderVersionEffectsWithColor,
                  sections: [InspectorSectionID.effects.rawValue],
                  .after, InspectorSectionID.color.rawValue),
            .init(version: orderVersionComponentAboveGeometry,
                  sections: [InspectorSectionID.component.rawValue],
                  .before, InspectorSectionID.geometry.rawValue),
            .init(version: orderVersionPickedAboveGeometry,
                  sections: pickedSections.map(\.rawValue),
                  .before, InspectorSectionID.geometry.rawValue),
            // Next only: it is the split that makes Appearance short enough to
            // sit up here, so the release without the split keeps its order.
            .init(version: orderVersionLookUnderLayers,
                  sections: [InspectorSectionID.color.rawValue,
                             InspectorSectionID.effects.rawValue],
                  .after, InspectorSectionID.layers.rawValue, isEnabled: split),
            // What you picked sits at the top: above Appearance and Effects,
            // which the move before this one had just put under Layers.
            .init(version: orderVersionPickedUnderLayers,
                  sections: pickedSections.map(\.rawValue),
                  .after, InspectorSectionID.layers.rawValue, isEnabled: split),
            // ...and where it sits comes before what it looks like.
            .init(version: orderVersionSizeAboveLook,
                  sections: placeSections.map(\.rawValue),
                  .before, InspectorSectionID.color.rawValue, isEnabled: split),
            // ...and Motion follows Effects up, because the two are one idea
            // read twice: what the layer paints, then what about it changes.
            .init(version: orderVersionMotionUnderEffects,
                  sections: [InspectorSectionID.motion.rawValue],
                  .after, InspectorSectionID.effects.rawValue, isEnabled: split),
            // ...with Reframe above it: the whole move first, its two
            // properties under it.
            .init(version: orderVersionReframeAboveMotion,
                  sections: [InspectorSectionID.reframe.rawValue],
                  .before, InspectorSectionID.motion.rawValue),
            // ...and what is keyed above both.
            .init(version: orderVersionKeysAboveReframe,
                  sections: [InspectorSectionID.keys.rawValue],
                  .before, InspectorSectionID.reframe.rawValue),
        ]
    }
    @State private var order: [InspectorSectionID] = InspectorSectionID.allCases
    /// The section currently in the reader's hand, and where it is being
    /// carried. See `sectionDragChanged`.
    @State private var drag = SectionDrag()
    /// The measurements and the Escape watch a reorder needs, held by
    /// reference so keeping them up to date does not redraw the dock.
    @State private var dragScratch = SectionDragScratch()
    /// The Library's scope, so the picked item's section can be titled after
    /// what it is ("Media", "Component") rather than "Library Item".
    @StoredSetting(LibraryPanel.scopeKey) private var libraryScopeRaw = LibraryScope.media.rawValue
    /// ...and a video's own, watched so the header follows it too.
    @StoredSetting(EditorState.videoLibraryScopeKey) private var videoLibraryScopeRaw = LibraryScope.media.rawValue

    /// The Library's pivot for the open document (`EditorState.libraryPivot`),
    /// read through the two settings above so a change to either redraws.
    private var libraryScope: LibraryScope {
        let hasTime = editorState.documentHasTime
        return LibraryScope.resolved(LibraryScope(rawValue: hasTime ? videoLibraryScopeRaw : libraryScopeRaw) ?? .media,
                                     hasTime: hasTime, brushes: editorState.libraryOffersBrushes)
    }
    /// Scratch measurements for the Library reveal. A reference on purpose:
    /// see the note at the geometry reader.
    @State private var reveal = DockRevealScratch()
    /// Which sections are folded. Each section reads its own fold, so a click
    /// on a header redraws that section and not this panel. See `toggleCollapsed`
    /// for the one way a fold still reaches the panel.
    @State private var folds = PanelSectionFoldStore()
    /// Goes up when a fold changes how much height the dock's lists get, which
    /// is the one thing about a fold this panel has to draw.
    @State private var foldBudgetPass = 0
    /// Bumped when the divider under the Layers pane writes where it was
    /// left, so the panel reads the new height (`listsPaneStored`).
    @State private var listsPaneStoredPass = 0
    /// The height the Layers pane and the sections under it share, nil until
    /// laid out.
    @State private var listsColumnHeight: CGFloat?
    /// The pane's own measurements, for its reorder, by reference for the
    /// reason `reveal` is.
    @State private var listsReveal: DockRevealScratch = {
        let scratch = DockRevealScratch()
        scratch.revealsHeaderOnly = true
        return scratch
    }()
    /// The Library's own pane at the foot of the panel (`PanelShelfPane`):
    /// its measurements, the height it holds until its divider is moved, and
    /// the pass the divider bumps when it writes where it was left.
    @State private var shelfReveal: DockRevealScratch = {
        let scratch = DockRevealScratch()
        scratch.revealsHeaderOnly = true
        return scratch
    }()
    @State private var shelfHold: PanelShelfPane.Hold?
    @State private var shelfStoredPass = 0
    // WHAT A PICK ACTUALLY COSTS, measured 2026-09-16 by taking one piece out
    // at a time and running the same walk again. Written down because three
    // tasks in a row have gone looking for the cost in the machinery below it
    // and it is not there.
    //
    // A blank 900x700 canvas with a rectangle and an arrow on it, picking one
    // and then the other, twenty times, probe build, longest single run loop
    // pass per pick (median of 38):
    //
    //   dock hidden altogether (`hideInspector`)                    9.8ms
    //   dock shown, every section's body replaced by a blank       13.4ms
    //   ...with the layers list put back, forms still blank        19.4ms
    //   ...everything back: the app as it ships                    30.2ms
    //
    // So a pick is roughly 10ms of canvas and selection, 4ms of dock shell,
    // 6ms of the layers list drawing itself again, and 10ms of the forms in
    // the sections (read on: it is not the ARRIVING form, it is all of them).
    // Taking a piece out of this file moved none of
    // it: the per-section chrome (the tutorial anchor, the frame reader, the
    // lift, the offsets, the drop target) is free, the `.regularMaterial` is
    // free, and the height budget below is free — its writes are no-ops once a
    // section's height has been seen once, which after the first pick is
    // always. The arrival pass EARNS its keep: turning it off put the longest
    // pass up from 29.7 to 33.3ms, because then all of it lands in one go.
    //
    // ...AND THE ARRIVING FORM IS NOT IT EITHER, measured 2026-09-17 with
    // `Scripts/playtest/perf/pick-cost-walk.json`, which picks back and forth
    // between two IDENTICAL arrows and then between a box and an arrow. If a
    // section arriving were the cost, the first phase would be cheap:
    //
    //   one arrow, then the other: same sections, same rows       33.4 / 35.1ms
    //   the box, then an arrow:    same sections, different rows  25.9 / 39.0ms
    //
    // A pick that changes NOTHING about the panel's shape still costs two
    // frames. Bringing new rows in is worth about 4ms of the 39; the other 35
    // is what a pick costs whatever it lands on. So the sentence to carry
    // forward is not "an arriving section is expensive", it is "the panel
    // redraws its whole form on every pick".
    //
    // The form is all of it: with `PartsInspector`'s body replaced by a blank,
    // the arrow pick is 16.3ms and the box pick 18.5ms, which is the canvas,
    // the selection, the layers list and this shell together.
    //
    // It is not the number of controls PRESENT. Ten more sliders in Appearance,
    // wrapped so their value never changes between picks, cost nothing at all
    // (34.6 against 35.8). What costs is the controls that UPDATE: taking out
    // the three segmented picture pickers an arrow shows is worth 7ms, the five
    // sliders 4ms, the number boxes beside them 3ms. Nothing is a villain;
    // every control that has to be handed a new value asks for about a
    // millisecond, and an arrow's Appearance hands out twenty.
    //
    // Which says where a fix has to come from: rows that SKIP when what they
    // show has not changed. That landed on 2026-09-17 (`PanelReach.swift`).
    // Every slider and picture picker in Appearance is now handed the NAME of
    // what it edits rather than the layers that happened to be picked when it
    // was drawn, and it looks those layers up at the moment somebody uses it,
    // so a row the panel leaves alone behaves exactly like one it rebuilt.
    // Then `.equatable()` on each of them compares only what a person can see.
    // Same walk, same locked machine, median of 12 picks, three runs each way:
    //
    //   one arrow, then the other      33.2 to 34.0ms  ->  24.3 to 25.6ms
    //   blanking PartsInspector, same session and protocol      16.0 to 19.1ms
    //
    // So Appearance costs about 6ms of a pick now rather than about 15, and
    // what is left of a pick is mostly NOT the panel's form: the canvas, the
    // selection, the layers list and this shell are two thirds of it now. So
    // "the panel redraws its whole form on every pick", true above, has stopped
    // being where the cost is, and the next person chasing a pick should start
    // with that floor rather than with Appearance.
    //
    // MEASURE IT LIKE THIS or the number is fiction. Build the probe once
    // (`Scripts/playtest.sh <walk>`), then take every reading with
    // `--no-build`. The reading that first went into this note was taken
    // against a probe still carrying the previous experiment, and it claimed
    // five milliseconds this change never won.
    //
    // The colour rows followed on 2026-09-17 and were the last of it
    // (`ColorTarget.Source`). They were the piece that could not be fixed from
    // outside: the well, the styles menu and the row itself each read the
    // selection in their OWN bodies, so nothing the row above them did could
    // leave them alone. Each is handed its reading now and compares what it
    // DRAWS, and the layers it paints are looked up at the moment somebody
    // paints. Interleaved against the same build with the change stashed, six
    // runs of the same walk in one session: 24.1 to 25.8ms without, 23.3 to
    // 23.4 with. The number to trust is not the stopwatch, though, it is the
    // count: `color-row-leaves-alone-walk` builds ZERO colour rows on a click
    // between two alike arrows, and three on a click that really changes the
    // panel.
    //
    // What is left inside Appearance: the arrow's Caption block, about 1ms, and
    // the rest spread across the row chrome with no villain in it. The Caption
    // block is a different job from the rows above -- its field is bound to one
    // arrow's WORDS, so two arrows really are two different fields -- and the
    // floor underneath it all, measured on 2026-09-17 by blanking
    // `PartsInspector` in the same session, is 23.1 to 24.6ms. Which is to say
    // Appearance has stopped being where a pick costs anything.
    // `Scripts/playtest/pick-leaves-settings-alone-walk.json` is the guard that
    // the skipping stayed honest: it picks the second of two arrows that read
    // exactly alike, which is the case where a control really was skipped, and
    // then uses that control and checks which arrow moved.
    /// Which sections have been built, so a new one can arrive a pass after
    /// the click rather than inside it. See `PanelSectionArrival`.
    @State private var arrivals = DockArrivals()
    /// Bumped to draw the pass that mounts the sections held back above. The
    /// value means nothing; changing it is the whole point.
    @State private var arrivalPass = 0
    /// Which sections wait unbuilt below the fold (`PanelBodyReach`). Held by
    /// reference, like `arrivals`: it is written on every pass and read on
    /// every scroll tick. Each section reads whether it waits from its own
    /// cell, so building one redraws that section and not the dock.
    @State private var bodies = DockBodyReach()
    /// Which sections have left the screen and wait a pass to be pulled down
    /// (`PanelSectionDeparture`). By reference, like `arrivals`.
    @State private var departures = DockDepartures()
    /// Bumped to draw the pass that pulls the lingering sections down.
    @State private var departurePass = 0
    /// What each section costs the dock, and how tall the dock is. Together
    /// these are the whole input to `DockHeightBudget`; see `dockBudget`.
    @State private var budget = DockBudgetScratch()
    /// What the section list needs to know about where the playhead is, as
    /// the watcher last handed it over. Nil until it has, and worked out on
    /// the spot until then.
    @State private var watchedTimeFacts: PanelTimeFacts?

    var body: some View {
        #if PHOTONZ_PLAYTEST
        let _ = ViewBuildMeter.shared.built(.inspectorPanel)
        #endif
        // The sections the selection asks for, and the ones the dock may draw
        // this pass. They are the same list except in the pass right after a
        // click that brings new sections in, when the canvas gets the frame to
        // itself and the panel follows in the next one.
        // A section an edit marked to catch up next pass brings arrives
        // then (`readingALatePass`).
        let wanted = readingALatePass { orderedAvailableSections }
        // Sliding in with Edit mode, the dock waits its turn (`EditModeArrival`).
        let sections = arrivals.showing(wanted) {
            !editorState.editArrival.panelMayFill || editorState.secondsUntilTheSlideLands > 0
        }
        let _ = arrivalPass // the catch-up pass reads its own trigger
        // Sections this pass leaves out stay built, unseen, for one more pass
        // when the pick has not moved: a cut clicked on the clip in hand
        // shows its own sections in the click's frame and pulls the clip's
        // down in the next (`PanelSectionDeparture`).
        let _ = departurePass
        let lingering = departures.draw(sections, pick: editorState.selectedLayerID,
                                        lingers: holdsBodiesOutOfSight)
        let _ = departures.releaseNextPass { departurePass &+= 1 }
        // Layers in a pane on top, the pick and the Library under it (Next,
        // `next-lists-pane`): one part each, and with the pane off the lower
        // part is every section, exactly the dock it always was. `pick` is
        // the part under the divider.
        let split = paneSplit(sections)
        let lingerSplit = paneSplit(lingering)
        // Nothing under the divider (nothing picked): Layers fills the panel.
        // Read off what the selection ASKS for, so the pass a click's sections
        // are held back does not draw the pane full for a frame.
        let pickIsEmpty = paneSplit(wanted).pick.isEmpty
        let belowIsEmpty = pickIsEmpty && split.shelf.isEmpty
        let listsHeight = listsPaneHeight(for: split.lists, belowIsEmpty: belowIsEmpty)
        // The Library in its own pane at the foot (`PanelShelfPane`), and
        // with nothing picked Layers takes whatever the shelf leaves.
        let showsListsGrip = !split.lists.isEmpty && !pickIsEmpty
        let shelfHeight = shelfPaneHeight(split, pickIsEmpty: pickIsEmpty, paneHeight: listsHeight,
                                          showsListsGrip: showsListsGrip)
        let paneHeight = pickIsEmpty && !split.lists.isEmpty && !split.shelf.isEmpty
            ? listsColumnHeight.map { max(listsPaneFloor(split.lists), $0 - shelfHeight) } ?? listsHeight
            : listsHeight
        let listsCeilings = split.lists.isEmpty
            ? [:] : listsLayout(paneHeight).ceilings(for: split.lists)
        let shelfCeilings = split.shelf.isEmpty
            ? [:] : listsLayout(shelfHeight).ceilings(for: split.shelf)
        // How tall each list section may be drawn, so that the forms under it
        // stay where they are instead of being carried off the bottom. Each
        // part shares out its own height.
        let ceilings = departures.ceilings(
            pickLayout(split.lists, paneHeight: paneHeight,
                       shelfHeight: split.shelf.isEmpty ? 0 : shelfHeight + (showsListsGrip ? ListsPaneGrip.thickness : 0))
                .ceilings(for: split.pick)
                .merging(listsCeilings) { pick, _ in pick }
                .merging(shelfCeilings) { pick, _ in pick })
        let _ = (reveal.drawnCeilings = ceilings)
        // Folds are NOT read here for the rows: each section reads its own
        // from `PanelSectionFoldStore`, so a fold redraws one section. This
        // panel was once handed the folds through its stored setting, and
        // rebuilt every section on every click, 20 to 70ms a fold with a clip
        // picked (`section-fold-motion-walk`, 2026-10-04). Before that it read
        // the setting inside the rows' closures and SwiftUI never saw a fold
        // change at all (the user, 2026-10-02: "collapsed panels that can't
        // be expanded", `every-section-header-opens-walk`). What it does read
        // is when a fold moved the height budget, and when somebody outside
        // the panel changed the folds.
        let _ = foldBudgetPass
        let _ = folds.syncs
        let _ = (folds.onFoldFromAnotherWindow = { checkFoldBudget() })
        // Before `drawnSections` moves on: a section new to the dock is placed
        // by where the one above it ended LAST pass.
        let _ = bodies.draw(split.pick, after: reveal, holding: holdsBodiesOutOfSight)
        let _ = (reveal.drawnSections = split.pick)
        let _ = (listsReveal.drawnSections = split.lists)
        let _ = (listsReveal.drawnCeilings = listsCeilings)
        let _ = (listsReveal.drawnPaneHeight = paneHeight)
        let _ = (shelfReveal.drawnSections = split.shelf)
        let _ = (shelfReveal.drawnPaneHeight = split.shelf.isEmpty ? nil : shelfHeight)
        #if PHOTONZ_PLAYTEST
        let _ = ViewBuildMeter.shared.note(
            "[\(sections.map(\.rawValue).joined(separator: ","))] arrival \(arrivalPass) "
            + "viewport \(Int(budget.viewportHeight ?? -1)) "
            + "headers \(budget.headers.map { "\($0.key.rawValue)=\(Int($0.value))" }.sorted().joined(separator: ",")) "
            + "bodies \(budget.bodies.map { "\($0.key.rawValue)=\(Int($0.value))" }.sorted().joined(separator: ","))")
        #endif
        // The dock, and under it the one row that says which sections it is
        // showing. The row sits OUTSIDE the scroller on purpose: it is the way
        // back to anything automatic has left out, and a way back you have to
        // scroll to find is not a way back.
        VStack(spacing: 0) {
          VStack(spacing: 0) {
            if !split.lists.isEmpty {
                listsPane(split.lists, lingering: lingerSplit.lists, ceilings: ceilings)
                    .frame(height: paneHeight)
                // The divider: drag it down to give Layers more of the
                // panel, up to give the sections under it more. It runs from
                // the pane's first header to the last row its lists have, so
                // no blank band can be dragged open under them. Nothing under
                // it, no divider: Layers is the whole panel then, or Layers
                // and the Library, with the Library's divider between them.
                if showsListsGrip {
                    let floor = listsPaneFloor(split.lists)
                    let most = max(PanelListsPane.gripCeiling(column: listsColumnHeight,
                                                              listsNeed: sectionsNeed(split.lists),
                                                              floor: floor), paneHeight)
                    ListsPaneGrip(height: paneHeight,
                                  contentHeight: most,
                                  floor: floor,
                                  maxAllowedHeight: most,
                                  stored: listsPaneStored)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(split.pick + lingerSplit.pick, id: \.self) { id in
                            dockSection(id, in: split.pick, isLingering: lingerSplit.pick.contains(id),
                                        ceilings: ceilings, scratch: reveal, proxy: proxy)
                        }
                        // A video with nothing picked: the timeline has taken
                        // the list's place, so the dock says where to click
                        // rather than standing empty.
                        // Not while the sections are only held back a pass.
                        // Next leaves it empty: an empty state is empty or one
                        // short label, never an errand
                        // (`next-notices-say-what-happened`).
                        if wanted.isEmpty, !showsLayersList,
                           !Experiments.shared.noticesSayWhatHappenedEnabled {
                            Text("Pick a clip on the timeline")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 24)
                                .panelReadout("panel empty: pick a clip on the timeline")
                        }
                    }
                    .padding(.vertical, DockMetrics.listTopPadding)
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
                // A list a section opens over itself (Animate a property),
                // drawn over the scroller so the scroller never cuts it off.
                .panelPopoverHost()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    reveal.viewportHeight = $0
                    // With the pane of lists under it, this part's height is
                    // the column less the pane, known in the same pass
                    // (`pickLayout`). Writing it here as well redrew the
                    // whole panel a second time on every fold that moved the
                    // pane, after a first pass that had shared the part out
                    // at its old height.
                    if listsReveal.drawnSections.isEmpty { budget.viewportHeight = $0 }
                    recordInspectorViewportHeight($0)
                }
                // Where the dock sits in the window. Only a scripted walk reads
                // it, to put a pointer on a section; it is a no-op in the
                // shipping build.
                // ...and where it sits in the panel, the band its sections
                // are seen in under the Layers pane.
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(inspectorPanelSpace)) } action: {
                    recordInspectorBelowBand($0.minY...$0.maxY)
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    recordInspectorDockFrame($0)
                    // The edge every icon on the right of the panel is measured
                    // against, so a walk reads "22.5pt in from the edge" rather
                    // than a window coordinate that means nothing on its own.
                    recordPanelEdgeFrame($0)
                }
                .inspectorLayoutProbe(sections: split.lists + split.pick + split.shelf)
                // A section the selection asked for that has not been built yet
                // gets a later pass to itself, one section per pass, top down.
                // Departures are already on screen by now (they leave in the
                // click's own pass), so this only ever fires for arrivals, and a
                // click that keeps the same sections — moving the selection from
                // one group to another — never reaches it at all.
                .onChange(of: wanted) { catchUp() }
                // A dock that slid in with Edit mode built nothing in its first
                // pass, and starts filling when its turn comes.
                .onAppear { catchUp() }
                .onChange(of: editorState.editArrival) { catchUp() }
                .onChange(of: arrivalPass) { catchUp() }
                // The app opened the Library for you: put it where you can see it.
                // On appear too, because showing the shelf opens the dock as well,
                // and then this panel is born with the request already waiting.
                // With the lists in their own pane, the shelf is there and
                // the pane brings it into view instead.
                // With the Library in its own pane at the foot, that pane
                // brings it into view instead.
                .onChange(of: editorState.pendingLibraryReveal) {
                    if !listsPaneIsOn { revealer(proxy).requestLibrary() }
                }
                .onAppear { if !listsPaneIsOn { revealer(proxy).requestLibrary() } }
                // ⌘R asked for the speeds of the piece in hand: the Time
                // section open and on screen, so its Speed list can drop open
                // from it (`EditorState+SpeedKey`). On appear too, for a panel
                // the key has just brought out.
                .onChange(of: editorState.pendingClipSpeedChoices) { _, asked in
                    if asked { showTimeSection(proxy) }
                }
                // Ask asked, or its change landed: the Agent group open and on screen.
                .onChange(of: editorState.ask.revealPass) { showAgentSection(proxy) }
                // ...and for a panel the ask itself just brought out, or a
                // video's panel arriving with Edit (`AskReveal`).
                .onAppear { if editorState.ask.isRevealPending { showAgentSection(proxy) } }
                // A chart just landed and asks for its numbers: its Chart
                // section open and at the top of the view (`EditorState+Charts`).
                .onChange(of: editorState.chartDataRequest) { showChartSection(proxy) }
                .onAppear { if editorState.pendingClipSpeedChoices { showTimeSection(proxy) } }
                // You opened an effect, or added one: put the settings that just
                // appeared where you can see them. This is the LAST reveal the dock
                // has, and picking something is deliberately not one of them — the
                // order puts what you picked under the layers list, so there is
                // nothing to scroll to. See `InspectorDockLayout.swift`.
                .onChange(of: editorState.effectToReveal) { _, id in
                    guard let id else { return }
                    let delay = InspectorDockReveal.effectRevealDelay
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        revealer(proxy).applyEffect(id)
                    }
                }
                // ...and the same for a sound's effect added from its plus.
                // Looked at three times, a beat apart: an EQ or a compressor
                // arrives with sliders under it, and a section measured
                // before they have settled to their height (slow on a cold
                // launch) is scrolled short by them. A later look does
                // nothing when an earlier one was right.
                .onChange(of: editorState.soundEffectsAdded) {
                    let delay = InspectorDockReveal.effectRevealDelay
                    for wait in [delay, delay * 2, delay * 4] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                            revealer(proxy).applySection(.soundEffects)
                        }
                    }
                }
                // ...and, in the release whose order still leaves a pick's own
                // section below Appearance and Effects, the pick itself. Both
                // stores, because a plain click and a shift click are the same act
                // as far as the panel is concerned. A no-op in Next.
                .onChange(of: editorState.selectedLayerID) { revealer(proxy).requestPick() }
                .onChange(of: editorState.multiSelectedLayerIDs) { revealer(proxy).requestPick() }
            }
            // The Library, in a pane of its own under everything the pick
            // brings, with a divider over it (`PanelShelfPane`). Nothing the
            // pick does above it moves a tile under the pointer.
            if !split.shelf.isEmpty {
                let floor = listsPaneFloor(split.shelf)
                let column = shelfColumn(split, pickIsEmpty: pickIsEmpty, paneHeight: paneHeight,
                                         showsListsGrip: showsListsGrip)
                let most = max(PanelShelfPane.maxAllowedHeight(column: column, floor: floor), shelfHeight)
                ShelfPaneGrip(height: shelfHeight,
                              contentHeight: most,
                              floor: floor,
                              maxAllowedHeight: most,
                              chosen: shelfChosen(split, column: column),
                              roomLeft: column.flatMap { c in
                                  shelfAboveNeeds(split, pickIsEmpty: pickIsEmpty).map { c - $0 }
                              },
                              stored: shelfStored,
                              onCarry: { shelfReveal.heldWhilePointerInside = nil })
                shelfPane(split.shelf, ceilings: ceilings)
                    .frame(height: shelfHeight)
            }
          }
          // The height the pick and the lists share, which the pane is
          // measured against so the pick always keeps room of its own.
          // Always less the grip's hairline: the column is only read while
          // there is a pane, and this closure keeps the `split` of the pass
          // it was made in, so asking it whether there is a pane read "no"
          // on a recording whose Library came in later, and the pick's part
          // came out a point short of its sections (2026-10-18).
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
              let column = height - ListsPaneGrip.thickness
              if listsColumnHeight != column { listsColumnHeight = column }
          }
          .coordinateSpace(.named(inspectorPanelSpace))
          .onChange(of: split.lists, initial: true) { _, lists in
              if lists.isEmpty { recordInspectorListsPane([], band: nil) }
          }
          .onChange(of: split.shelf, initial: true) { _, shelf in
              if shelf.isEmpty { recordInspectorShelfPane(nil) }
          }
          // The shelf's starting height, held once it is measured.
          .onChange(of: PanelShelfPane.hold(shelfHold,
                                            column: shelfColumn(split, pickIsEmpty: pickIsEmpty,
                                                                paneHeight: paneHeight,
                                                                showsListsGrip: showsListsGrip),
                                            fit: split.shelf.isEmpty ? nil
                                                : layout.leastHeight(of: split.shelf, asIfFull: true)),
                    initial: true) { _, hold in
              if hold != shelfHold { shelfHold = hold }
          }
          // A tile picked holds the shelf still for a double click
          // (`EditorState.shelfHoldsStill`); once that has passed, it
          // settles to whatever the pick left it.
          .onChange(of: editorState.selectedLibraryItemID) {
              DispatchQueue.main.asyncAfter(deadline: .now() + EditorState.shelfHoldSeconds + 0.02) {
                  settleShelfPane()
              }
          }
          // Nothing picked: Layers fills the panel, so a Layers left folded
          // opens rather than leaving a header over an empty panel.
          .onChange(of: belowIsEmpty && split.lists.contains(.layers), initial: true) { _, alone in
              if alone, isCollapsed(.layers) { expand(.layers) }
          }
          // A cut picked holds Transitions open, without writing it down, and
          // letting the cut go puts it back the way the person left it: with
          // no cut there is nothing to put a tile on (the user, 2026-10-30).
          .onChange(of: editorState.isACutPicked, initial: true) { _, picked in
              withAnimation(foldMotion) {
                  refold { folds.hold(.transitions, open: picked) }
              }
          }
            if Experiments.shared.panelSectionsEnabled, editorState.document != nil {
                PanelSectionsFooter(offered: offeredOptionalSections,
                                    situation: editorState.panelSectionSituation)
            }
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
        // Which sections the playhead's place brings in, handed over only
        // when that changes (`PanelTimeFacts`).
        .background { PanelTimeFactsWatcher { watchedTimeFacts = $0 } }
        .onAppear(perform: loadOrder)
        .onChange(of: order) { persistOrder() }
        // A panel that goes away mid-drag takes its key watch with it, and
        // lets go of the fold store's way back to it: that closure holds this
        // panel, the panel's state holds the store, and a closed window's
        // editor stayed alive through the pair (2026-10-23, memory task).
        .onDisappear {
            stopWatchingForEscape()
            folds.onFoldFromAnotherWindow = nil
        }
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
                sectionDragChanged(id, pointerY: pointerY, carriedBy: carriedBy,
                                   in: split.lists.contains(id) ? split.lists
                                       : split.shelf.contains(id) ? split.shelf : split.pick)
            },
            end: { endSectionDrag(in: drag.section.map(split.lists.contains) == true ? split.lists
                                  : drag.section.map(split.shelf.contains) == true ? split.shelf : split.pick) },
            cancel: cancelSectionDrag,
            sections: split.lists + split.pick + split.shelf)
    }

    // MARK: The pane of lists on top of the pick

    /// Whether the panel splits into Layers in a pane on top and the pick
    /// under it (Next, `next-lists-pane`).
    private var listsPaneIsOn: Bool { Experiments.shared.listsPaneEnabled }

    /// The sections drawn in each part. With the pane off, all of them are
    /// the pick's and there is no pane.
    private func paneSplit(_ sections: [InspectorSectionID])
        -> (pick: [InspectorSectionID], lists: [InspectorSectionID], shelf: [InspectorSectionID]) {
        guard listsPaneIsOn else { return (sections, [], []) }
        let split = PanelListsPane.split(sections.map(\.rawValue))
        return (split.below.compactMap(InspectorSectionID.init(rawValue:)),
                split.lists.compactMap(InspectorSectionID.init(rawValue:)),
                split.shelf.compactMap(InspectorSectionID.init(rawValue:)))
    }

    /// The least the pane is drawn: its first header, so the lists are never
    /// out of reach however short the window.
    private func listsPaneFloor(_ lists: [InspectorSectionID]) -> CGFloat {
        let header = lists.first.flatMap { budget.headers[$0] } ?? DockMetrics.headerRowHeight
        return header + DockMetrics.sectionDividerHeight + 2 * DockMetrics.listTopPadding
    }

    /// The settings key the divider's height is kept under for this window's
    /// kind of document (`PanelListsPane.heightKey(forKind:)`).
    static func listsPaneHeightKey(forKind kind: String) -> String {
        PanelListsPane.heightKey(forKind: kind)
    }

    /// Every key the divider has ever been kept under, for a walk to forget.
    static var listsPaneHeightKeys: [String] {
        WindowModes.all.map { listsPaneHeightKey(forKind: $0.id) } + ["inspector.listsPaneHeight"]
            + WindowModes.all.map { PanelShelfPane.heightKey(forKind: $0.id) }
    }

    /// Where the divider was left for this kind of document, written as the
    /// divider is dragged and nought when it never was (or was double
    /// clicked back).
    private var listsPaneStored: Binding<Double> {
        let key = Self.listsPaneHeightKey(forKind: editorState.windowMode.id)
        let _ = listsPaneStoredPass
        return Binding(
            get: { UserDefaults.standard.double(forKey: key) },
            set: { value in
                UserDefaults.standard.set(value, forKey: key)
                listsPaneStoredPass &+= 1
            })
    }

    /// How tall the Layers pane is drawn: where the divider was left, or less
    /// when its lists need less, or the whole panel with nothing under it
    /// (`PanelListsPane.height`).
    private func listsPaneHeight(for lists: [InspectorSectionID], belowIsEmpty: Bool) -> CGFloat {
        guard !lists.isEmpty else { return 0 }
        let stored = listsPaneStored.wrappedValue
        return PanelListsPane.height(
            chosen: PanelListsPane.chosenHeight(stored: stored > 0 ? CGFloat(stored) : nil,
                                                column: listsColumnHeight),
            column: listsColumnHeight,
            listsNeed: sectionsNeed(lists),
            belowIsEmpty: belowIsEmpty,
            floor: listsPaneFloor(lists))
    }

    /// A run of sections drawn whole, from what each measured itself at:
    /// nil until every open one has been.
    private func sectionsNeed(_ sections: [InspectorSectionID]) -> CGFloat? {
        var parts: [(header: CGFloat?, body: CGFloat?)] = []
        for id in sections {
            if isCollapsed(id) {
                parts.append((budget.headers[id], nil))
                continue
            }
            guard let body = budget.bodies[id] else { return nil }
            // A list that sizes itself reports its rows and chrome, not the
            // padding every body is drawn with under it.
            let padding = Self.boundsItself(id) ? DockMetrics.bodyBottomPadding : 0
            parts.append((budget.headers[id], body + (budget.listExtras[id] ?? 0) + padding))
        }
        return PanelListsPane.contentHeight(parts, padding: DockMetrics.listTopPadding,
                                            divider: DockMetrics.sectionDividerHeight)
    }

    /// The height arithmetic for the part under the divider: the column less
    /// the pane, worked out in the same pass the pane is, so a fold that
    /// moves the pane shares the part out at its new height rather than the
    /// one it was last measured at.
    /// `shelfHeight` is the Library's pane at the foot and its divider,
    /// nought with no shelf.
    private func pickLayout(_ lists: [InspectorSectionID], paneHeight: CGFloat,
                            shelfHeight: CGFloat = 0) -> InspectorDockLayout {
        guard !lists.isEmpty || shelfHeight > 0, let column = listsColumnHeight else { return layout }
        var pick = budget
        pick.viewportHeight = column - (lists.isEmpty ? 0 : paneHeight) - shelfHeight
        return InspectorDockLayout(budget: pick, collapsed: isCollapsed)
    }

    /// The height arithmetic for the pane, which shares out its own height
    /// between its lists exactly as the dock above shares out its own.
    private func listsLayout(_ paneHeight: CGFloat) -> InspectorDockLayout {
        var pane = budget
        pane.viewportHeight = paneHeight
        return InspectorDockLayout(budget: pane, collapsed: isCollapsed)
    }

    /// The pane of lists on top: its own scroller, so picking a row in a list
    /// never moves the list, whatever the pick brings into the part below.
    private func listsPane(_ lists: [InspectorSectionID], lingering: [InspectorSectionID],
                           ceilings: [InspectorSectionID: CGFloat]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lists + lingering, id: \.self) { id in
                        dockSection(id, in: lists, isLingering: lingering.contains(id),
                                    ceilings: ceilings, scratch: listsReveal, proxy: proxy,
                                    inListsPane: true)
                    }
                }
                .padding(.vertical, DockMetrics.listTopPadding)
            }
            .coordinateSpace(.named(inspectorDockSpace))
            .panelPopoverHost()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                listsReveal.viewportHeight = $0
            }
            // Where the pane sits in the panel, for a walk reading what is
            // in view in it.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(inspectorPanelSpace)) } action: {
                listsReveal.paneBand = $0.minY...$0.maxY
                recordInspectorListsPane(listsReveal.drawnSections, band: listsReveal.paneBand)
            }
            .onChange(of: lists, initial: true) { _, lists in
                recordInspectorListsPane(lists, band: listsReveal.paneBand)
            }
        }
    }

    // MARK: The Library's pane at the foot

    /// The height the pick and the Library's pane share: the column less the
    /// Layers pane over them, and less a second divider when both show. With
    /// nothing picked it is Layers and the Library that share the column.
    private func shelfColumn(_ split: (pick: [InspectorSectionID], lists: [InspectorSectionID],
                                       shelf: [InspectorSectionID]),
                             pickIsEmpty: Bool, paneHeight: CGFloat, showsListsGrip: Bool) -> CGFloat? {
        guard let column = listsColumnHeight else { return nil }
        let pane = split.lists.isEmpty || pickIsEmpty ? 0 : paneHeight
        return column - pane - (showsListsGrip ? ListsPaneGrip.thickness : 0)
    }

    /// What sits above the shelf drawn whole: the pick's sections, or Layers
    /// with nothing picked.
    private func shelfAboveNeeds(_ split: (pick: [InspectorSectionID], lists: [InspectorSectionID],
                                           shelf: [InspectorSectionID]),
                                 pickIsEmpty: Bool) -> CGFloat? {
        pickIsEmpty ? (split.lists.isEmpty ? 0 : sectionsNeed(split.lists)) : sectionsNeed(split.pick)
    }

    /// Where the Library's divider was left for this kind of document,
    /// nought when it never was (or was double clicked back).
    private var shelfStored: Binding<Double> {
        let key = PanelShelfPane.heightKey(forKind: editorState.windowMode.id)
        let _ = shelfStoredPass
        return Binding(
            get: { UserDefaults.standard.double(forKey: key) },
            set: { value in
                UserDefaults.standard.set(value, forKey: key)
                shelfStoredPass &+= 1
            })
    }

    /// The height chosen for the shelf: the divider's, the held one, or its
    /// starting share (`PanelShelfPane.height`).
    private func shelfChosen(_ split: (pick: [InspectorSectionID], lists: [InspectorSectionID],
                                       shelf: [InspectorSectionID]),
                             column: CGFloat?) -> CGFloat {
        let stored = shelfStored.wrappedValue
        return PanelShelfPane.height(stored: stored > 0 ? CGFloat(stored) : nil,
                                     held: shelfHold, column: column,
                                     floor: listsPaneFloor(split.shelf),
                                     fit: layout.leastHeight(of: split.shelf, asIfFull: true))
    }

    /// How tall the Library's pane is drawn: the height chosen, grown into
    /// any room the pick leaves, and held where it is while the pointer is in
    /// it or a tile has just been picked, so a click there never moves it.
    private func shelfPaneHeight(_ split: (pick: [InspectorSectionID], lists: [InspectorSectionID],
                                           shelf: [InspectorSectionID]),
                                 pickIsEmpty: Bool, paneHeight: CGFloat, showsListsGrip: Bool) -> CGFloat {
        guard !split.shelf.isEmpty else {
            shelfReveal.unheldPaneHeight = nil
            return 0
        }
        let column = shelfColumn(split, pickIsEmpty: pickIsEmpty, paneHeight: paneHeight,
                                 showsListsGrip: showsListsGrip)
        let floor = listsPaneFloor(split.shelf)
        let drawn = PanelShelfPane.drawnHeight(
            chosen: shelfChosen(split, column: column),
            column: column,
            aboveNeeds: shelfAboveNeeds(split, pickIsEmpty: pickIsEmpty),
            foldedHeight: split.shelf.allSatisfy(isCollapsed) ? floor : nil)
        // Never drawn, held or not, shorter than the shelf needs to show its
        // first row of tiles whole, until the divider is moved: a colour saved
        // onto an empty Styles shelf gets its whole tile, name and all.
        let least = shelfStored.wrappedValue > 0 ? nil : layout.leastHeight(of: split.shelf)
        let unheld = PanelShelfPane.atLeastTheShelf(drawn, least: least, column: column)
        shelfReveal.unheldPaneHeight = unheld
        let held = shelfReveal.heldWhilePointerInside
            ?? (editorState.shelfHoldsStill ? shelfReveal.drawnPaneHeight : nil)
        guard let held else { return unheld }
        return PanelShelfPane.atLeastTheShelf(min(max(held, floor), column ?? held),
                                              least: least, column: column)
    }

    /// The pointer came into the Library's pane or left it. Coming in holds
    /// the pane at the height it is drawn; leaving lets it settle.
    private func pointerInShelfPane(_ inside: Bool) {
        if inside {
            shelfReveal.heldWhilePointerInside = shelfReveal.drawnPaneHeight
            return
        }
        guard shelfReveal.heldWhilePointerInside != nil else { return }
        shelfReveal.heldWhilePointerInside = nil
        settleShelfPane()
    }

    /// Lets the Library's pane go to the height the pick leaves it, on the
    /// fold's curve, when nothing is holding it and that height is new.
    private func settleShelfPane() {
        guard shelfReveal.heldWhilePointerInside == nil, !editorState.shelfHoldsStill,
              let unheld = shelfReveal.unheldPaneHeight, let drawn = shelfReveal.drawnPaneHeight,
              abs(unheld - drawn) > 0.5 else { return }
        withAnimation(foldMotion) { foldBudgetPass += 1 }
    }

    /// The Library's pane: its own scroller, so nothing the pick does above
    /// it moves a tile, and a click on a tile lands on the same tile twice.
    private func shelfPane(_ shelf: [InspectorSectionID],
                           ceilings: [InspectorSectionID: CGFloat]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(shelf, id: \.self) { id in
                        dockSection(id, in: shelf, isLingering: false,
                                    ceilings: ceilings, scratch: shelfReveal, proxy: proxy,
                                    inListsPane: true)
                    }
                }
                .padding(.vertical, DockMetrics.listTopPadding)
            }
            .coordinateSpace(.named(inspectorDockSpace))
            .panelPopoverHost()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                shelfReveal.viewportHeight = $0
            }
            .playtestHover("library pane", perform: pointerInShelfPane)
            // Where the pane sits in the panel, for a walk reading what is
            // in view in it.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(inspectorPanelSpace)) } action: {
                shelfReveal.paneBand = $0.minY...$0.maxY
                recordInspectorShelfPane(shelfReveal.paneBand)
            }
            // The app opened the Library for you: it is in this pane, so
            // this pane opens it and brings its header into view.
            .onChange(of: editorState.pendingLibraryReveal) {
                revealer(proxy, scratch: shelfReveal).requestLibrary()
            }
            .onAppear { revealer(proxy, scratch: shelfReveal).requestLibrary() }
        }
    }

    /// One section of the dock, header, body and the hairline under it, in
    /// whichever part of the panel it is drawn: the pick's scroller, or the
    /// pane of lists at the bottom (`PanelListsPane`). `column` is the part's
    /// own sections, which is all a reorder can carry it past.
    @ViewBuilder
    private func dockSection(_ id: InspectorSectionID, in sections: [InspectorSectionID],
                             isLingering: Bool, ceilings: [InspectorSectionID: CGFloat],
                             scratch: DockRevealScratch, proxy: ScrollViewProxy,
                             inListsPane: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CollapsibleSection(
                title: sectionTitle(id),
                fold: folds.cell(id),
                onToggle: { toggleCollapsed(id) },
                onReorder: { pointerY, carriedBy in
                    sectionDragChanged(id, pointerY: pointerY,
                                       carriedBy: carriedBy, in: sections)
                },
                onReorderEnd: { endSectionDrag(in: sections) },
                accessory: sectionAccessory(id),
                chip: sectionChip(id),
                // Two sections bound themselves — the layers
                // list and the Library shelf both had their
                // own scroller and grab bar since long before
                // the dock had a budget — so the ceiling
                // reaches them through `LayersListView` and
                // `LibraryPanel` instead of through a second
                // scroller round the outside of the one they
                // already have. A shelf inside two scrollers
                // had the outer one cutting the inner one's
                // window, and what it cut was the caption
                // under a tile, which is the tile's name.
                bodyCeiling: Self.boundsItself(id) ? nil : ceilings[id],
                mayBeShortened: !Self.boundsItself(id) && DockMetrics.scrollingSections.contains(id),
                onBodyHeight: { height in
                    guard !Self.boundsItself(id) else { return }
                    record(bodyHeight: height, for: id)
                },
                onHeaderHeight: { record(headerHeight: $0, for: id) },
                onBodyFrame: { scratch.bodyFrames[id] = $0 }
            ) {
                if bodies.cell(id).isHeld {
                    // Nothing built yet, at the height it
                    // was last drawn, so the dock under it
                    // and the scroller's length stay put.
                    Color.clear.frame(height: budget.bodies[id] ?? Self.unmeasuredBody)
                } else {
                    sectionContent(id, ceiling: ceilings[id], inListsPane: inListsPane)
                }
            }
            // The hairline belongs to the section above it, so
            // a section lifted off the panel takes its line
            // with it instead of leaving one hanging in the
            // gap it left behind.
            Divider().opacity(drag.section == id ? 0 : 0.4)
        }
        // A lingering section takes no room and shows
        // nothing; it is only waiting to be pulled down.
        .frame(height: isLingering ? 0 : nil, alignment: .top)
        .opacity(isLingering ? 0 : 1)
        // Named for a tutorial off the section's id, never off
        // its heading, so renaming a section cannot break a
        // guide that points at it (`TutorialAnchorRegistry`).
        .tutorialAnchor(.panelSection(id.rawValue))
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
            guard !isLingering else { return }
            scratch.sectionFrames[id] = frame
            if !inListsPane, bodies.comesNear(id, top: frame.minY, viewport: scratch.viewportHeight) {
                buildBodies()
            }
            // Mid-drag a section is standing somewhere it does
            // not live, so its measurement is worth nothing:
            // the spans a reorder reads were taken before it
            // started.
            if drag.section == nil { dragScratch.frames[id] = frame }
            guard id == .library else { return }
            scratch.libraryFrame = frame
            if scratch.isPending { revealer(proxy, scratch: scratch).applyLibrary() }
        }
        // Each part measures its sections against its own scroller, for its
        // reveal and its reorder. A walk reads every section against the
        // whole panel, so "in view" means inside the part it is drawn in.
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(inspectorPanelSpace))
        } action: { frame in
            guard !isLingering else { return }
            recordInspectorSection(id, title: sectionTitle(id), frame: frame)
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

    /// One more waiting section, a pass from now; the pass it makes asks for
    /// the next, until nothing is waiting.
    private func catchUp() {
        guard editorState.editArrival.panelMayFill,
              !arrivals.isCatchingUp, arrivals.isWaiting(for: orderedAvailableSections) else { return }
        arrivals.isCatchingUp = true
        // Built behind a recording playing in View, a section would cost the
        // player a frame, and built while Edit slides in (a pick handed back)
        // it would cost the slide one: wait for either (`EditModeArrival`).
        let behindPlayback = editorState.isWatching && editorState.isDocumentPlaying
        let wait = behindPlayback ? EditorState.buildBehindViewDelay : editorState.secondsUntilTheSlideLands
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            arrivals.isCatchingUp = false
            if wait > 0 { catchUp(); return }
            let latest = orderedAvailableSections
            guard arrivals.isWaiting(for: latest) else { return }
            arrivals.allowNext(latest)
            arrivalPass &+= 1
            // ...and asks for the next one itself, a turn of the run loop
            // later, rather than trusting `.onChange(of: arrivalPass)` alone.
            // About one pick in ten SwiftUI drew the new pass and never ran
            // that action, so the chain stopped part way down: a recording's
            // clip got its picture sections and none of its Audio ones, for
            // good. Traced on 2026-10-04 (every-section-header-opens-walk):
            // the pass went 2 to 3, the dock redrew six times over the next
            // three seconds, and no catch-up was ever asked for. When the
            // action does run, `isCatchingUp` makes this second ask a no-op.
            DispatchQueue.main.async { catchUp() }
        }
    }

    /// Whether sections that arrive below the fold wait to be built
    /// (`PanelBodyReach`). Only on a video, whose dock is the long one, and
    /// never while a guide is running: a guide points at controls, and one
    /// that is not built yet is nothing to point at. A scripted walk that
    /// looks for a control in a section still waiting turns it off for the
    /// rest of the walk (`PanelBuildsEverything`).
    private var holdsBodiesOutOfSight: Bool {
        PanelBuildsEverything.dockMayWait && editorState.documentHasTime
    }

    /// The height a waiting section stands at before it has ever been drawn.
    private static let unmeasuredBody: CGFloat = 160

    /// Builds the waiting sections that have come within reach, the highest
    /// first, one per pass, so a long scroll down a clip's dock never pays for
    /// two sections in one frame.
    private func buildBodies() {
        guard !bodies.isBuilding else { return }
        bodies.isBuilding = true
        Task { @MainActor in
            await NextRunLoopPass.start()
            bodies.isBuilding = false
            guard bodies.buildNext() else { return }
            if bodies.hasMoreNear { buildBodies() }
        }
    }

    // MARK: Sharing out the height the dock has, and revealing

    /// What a section has just measured itself to be, kept only while the dock
    /// is actually drawing that section.
    ///
    /// The guard is a real cost, not tidiness. A section on its way out of the
    /// dock measures itself one last time as it goes, at zero, and that write
    /// used to land in `budget` — which is @State, so it redrew every section
    /// still on screen and re-laid out the window, for a number nothing would
    /// ever read again. It was one of the FOUR passes over the dock that one
    /// click on a layer row cost: on a two row document, picking Background
    /// drew the dock at [layers], then again at [layers] for nothing but
    /// "canvas is 0 tall now", then at [layers, geometry], then once more with
    /// geometry's real height (`layer-pick-latency-walk`, 2026-09-14).
    ///
    /// Nothing reads a departed section's entry — `DockHeightBudget` only ever
    /// looks up the sections it was handed — so a stale one costs nothing and
    /// is simply left where it is.
    private func record(bodyHeight: CGFloat, for id: InspectorSectionID) {
        guard availableSections.contains(id) else { return }
        guard budget.bodies[id] != bodyHeight else { return }
        budget.bodies[id] = bodyHeight
    }

    /// Whether this section applies the dock's ceiling to its own list rather
    /// than being wrapped in a scroller from the outside.
    ///
    /// Two do, and for the same reason: each already has a scroller and a grab
    /// bar of its own, so a second one round the outside would cut the first
    /// one's window — and the part that goes is the bottom of the list, which
    /// is the grab bar, and for a shelf the caption under a tile.
    static func boundsItself(_ id: InspectorSectionID) -> Bool {
        id == .layers || id == .library
    }

    /// The same, for the header row, which measures itself on the way out too.
    private func record(headerHeight: CGFloat, for id: InspectorSectionID) {
        guard availableSections.contains(id) else { return }
        guard budget.headers[id] != headerHeight else { return }
        budget.headers[id] = headerHeight
    }

    /// The dock's height arithmetic, which lives in `InspectorDockLayout.swift`
    /// along with the one rule the whole panel follows. Rebuilt each pass from
    /// what the dock has measured of itself; it holds no state of its own.
    private var layout: InspectorDockLayout {
        InspectorDockLayout(budget: budget, collapsed: isCollapsed)
    }

    /// The two things the app still brings into view for you: the Library shelf
    /// and an effect whose settings have just appeared. A PICK is not one of
    /// them — the order puts what you picked on screen, so nothing has to move.
    private func revealer(_ proxy: ScrollViewProxy,
                          scratch: DockRevealScratch? = nil) -> InspectorDockReveal {
        InspectorDockReveal(scratch: scratch ?? reveal, editorState: editorState,
                            proxy: proxy, expand: expand,
                            pickedSection: { pickedSection })
    }

    /// The section named after what is picked, or nil when what is picked has
    /// none of its own. Read ONLY by the release that still scrolls to a pick;
    /// Next's order puts it under the layers list instead.
    ///
    /// The Canvas section is deliberately not one of them. Clicking empty space
    /// is how you put something down, not how you ask about the canvas.
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
        // Position & Size is NOT here any more, and its absence is the feature.
        // Where a layer sits and how big it is was a section sitting open at
        // the top of this panel for every layer, forever, costing the dock 130
        // of the 1052 points it was asking a 968 point panel for (measured
        // 2026-09-15). Moving something is what the pointer is for, and an
        // exact number is wanted rarely and precisely, so the same fields now
        // open on a command over the thing they are about: Layer ▸ Position
        // and Size…, or a right click on the layer's own row
        // (`ExactPlacement`, `ExactPlacementPopover`). The `.geometry` case
        // stays in the enum so that saved orders and the one-time moves that
        // mention it keep reading cleanly; nothing puts it on screen.
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
        // What the picked layer has been told to change over time (Next,
        // `next-motion`). ONE layer, unlike Effects above it, which speaks for
        // everything picked: a motion carries the layer's own numbers in its
        // From and To, so one row standing for five layers would have to hold
        // five different pairs of values and could only ever show one of them.
        // ...and with more than one picked it STAYS, holding one line that says
        // why it has nothing to show. Vanishing was the confusing part: the
        // section directly above it speaks for everything picked, so the second
        // click looked like it had broken something (2026-09-16 design review).
        // In a document with time only a motion that loops earns the section:
        // everything that plays once is a keyed value, shown in Animating.
        if editorState.motionLayer != nil || editorState.motionNeedsOneLayer,
           !editorState.documentHasTime || !editorState.motionRows.isEmpty {
            set.insert(.motion)
        }
        // How loud the picked layer plays (Next, `next-sound-on-the-timeline`).
        // Present only when what is picked actually makes a sound: a clip that
        // still has its recording's sound on it, or a piece of sound. A level
        // row on a rectangle would be a control for nothing.
        if Experiments.shared.soundOnTheTimelineEnabled, editorState.soundLayerInHand != nil {
            set.insert(.sound)
            set.insert(.fades)
            set.insert(.gain)
            set.insert(.soundEffects)
        }
        // Having the app write the captions (Next, `next-captions-from-the-sound`).
        // Present for the whole document rather than for what is picked: unlike
        // every other section here, this is where you go to MAKE something, so
        // gating it on a caption being selected would mean it only appeared
        // once you no longer needed it.
        if Experiments.shared.captionsFromTheSoundEnabled, editorState.documentHasTime,
           editorState.documentHasAudio || editorState.hasCaptions {
            set.insert(.captions)
        }
        // What is on the CUT in hand (Next, `next-transitions-at-a-cut`).
        // Present only where there is a cut to be on: a clip somebody has split
        // at least once. A recording nobody has cut has no join, and a section
        // about a join that is not there would be a section about nothing.
        let timeFacts = watchedTimeFacts ?? PanelTimeFacts(editorState)
        if timeFacts.showsCut {
            set.insert(.editPoint)
            set.insert(.transition)
        }
        // The zoom in hand on a recording's Zoom lane (`EditorState+Zoom`).
        if editorState.canWorkWithZooms, editorState.zoomInHand != nil {
            set.insert(.zoom)
        }
        // The transitions to drag onto a cut (`video-transitions.html`,
        // `#gEffects`): wherever the timeline holds a recording, picked or not,
        // because it is where you go to FIND a transition, before any cut is
        // in hand.
        if editorState.showsTransitionsGroup { set.insert(.transitions) }
        // How fast the piece in hand plays (Next, `next-speed-a-stretch`).
        // Present wherever there is a piece to retime at all, which is a clip
        // with time under it: unlike Transition it does NOT need the clip to
        // have been cut, because an uncut recording is one piece and one piece
        // can be sped up.
        // ...and the same section is where a TITLE says when it is on screen
        // (Next, `next-a-title-has-an-in-and-an-out`). One section rather than
        // two, because "when is this on screen" and "how fast does this play"
        // are one question asked of two kinds of layer, and a second section
        // called Time would be a second place to look for it.
        if timeFacts.canRetime || editorState.placedLayerInHand != nil {
            set.insert(.speed)
        }
        // No Reframe section: a punch-in is the clip's own Scale and Position,
        // keyed, so it reads in Animating like any other move, and the move
        // itself is a right-click preset on the clip and the canvas
        // (`timelineClipMenuRows`). The id stays for orders saved with it.
        // What is keyed on the picked layer, in a document with time
        // (`PropertyKeysInspector`). One layer, like Motion: a key is that
        // layer's own value at a moment.
        // Several things picked on the timeline: how many, and of what kinds
        // (`EditorState+TrackRange`).
        if editorState.keyLayer != nil || editorState.timelinePickSummary != nil { set.insert(.keys) }
        // How the picked layers are turned in space, and the camera when the
        // frame itself is picked (Next, `next-turn-in-depth`).
        // With the transform bar on, the 3D values live on the bar beside the
        // layer and the section is withdrawn (`video-animate.html`; Reset 3D
        // Rotation, Bring Nearer and Send Further stay in the Layer menu).
        if editorState.showsSpaceSection, !Experiments.shared.transformBarEnabled {
            set.insert(.space3D)
        }
        if editorState.showsCameraSection { set.insert(.camera) }
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
        // A picked Captions layer is one layer with its own type: the Text
        // section speaks for every caption in it, and the box is placed by the
        // pointer, not by a layout (the user, 2026-09-25).
        if selectedLayer?.isCaptionsLayer == true {
            set.insert(.text)
        }
        // How the picked text's words come in, on a video (`TextReveal.swift`).
        // Not for words on a curve, which come in whole: a reveal lays its
        // pieces out in a box (`TextOnPath.swift`).
        if let revealing = editorState.textRevealLayer, revealing.text?.onPath == nil {
            set.insert(.reveal)
        }
        // A picked title's few knobs, and the part of it in hand
        // (`TitleRestyle.swift`).
        if editorState.titleRecipeInHand != nil { set.insert(.title) }
        if editorState.chartInHand != nil { set.insert(.chart) }
        if editorState.titlePartInHand != nil { set.insert(.titlePart) }
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
            // ...except in a release where the Lens tool is in hand, where a
            // callout IS the Lens set to Magnify and says so in the Lens
            // section below. One section, not two (`LensKind`).
            if layer.zoomCallout != nil, !Experiments.shared.lensEnabled { set.insert(.callout) }
            // A picked lens's own settings, on the same terms: what it does to
            // the picture underneath is a property of the lens, not of the tool
            // in your hand.
            if Experiments.shared.lensEnabled, layer.lensKind != nil { set.insert(.lens) }
            // With the parts split on, everything that said how a measurement
            // LOOKS is in Appearance, so this section is here only for what it
            // is called and the numbers it can tell you about itself. Where
            // there is neither, there is no section (`MeasureInspector`).
            if layer.measure != nil, MeasureInspector.hasAnyRow { set.insert(.measure) }
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
        // Ask's Agent group (`next-ask`): there once this window has asked,
        // the way the Library is there once it was asked for.
        if Experiments.shared.askEnabled, editorState.ask.hasAsked, editorState.document != nil {
            set.insert(.agent)
        }
        if Experiments.shared.libraryEnabled, editorState.libraryMayShow,
           editorState.document != nil {
            set.insert(.library)
            // ...and the picked tile's own section, the way a picked layer
            // brings its sections. Nothing picked, nothing shown.
            // It follows the pick a frame behind (`panelLibraryItemID`).
            if editorState.panelLibraryItemID != nil { set.insert(.libraryItem) }
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
        // The bucket's own settings (D15), the same test as the wand's: they
        // change what the click fills, not what the pointer does.
        if editorState.activeTool == .fill, Experiments.shared.toolOptionsEnabled {
            set.insert(.fillTool)
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
        if editorState.activeTool == .zoomCallout, !Experiments.shared.lensEnabled,
           CalloutToolInspector.hasAnySetting {
            set.insert(.calloutTool)
        }
        // The Lens tool's own settings, while the tool is in hand
        // (`next-lens`). Same test again: what the drag PRODUCES.
        if editorState.activeTool == .lens, Experiments.shared.lensEnabled {
            set.insert(.lensTool)
        }
        // The brush in hand, while the Brush is: the tile picked in the
        // Library or the chooser drives it (`brush-library.html`).
        if editorState.activeTool == .brush, Experiments.shared.brushEnabled {
            set.insert(.brushTool)
        }
        // A piece INSIDE a copy owns nothing. Its size, its colors, its type
        // and its effects all come from the original and are written back over
        // on the next redraw, so a panel full of those controls is a panel full
        // of edits that get thrown away. It answers through the copy's knobs
        // instead, and the Component section is where they are.
        if editorState.selectedComponentPiece != nil {
            set.subtract(Self.sectionsAPieceDoesNotOwn)
        }
        // A CUT picked is the one thing in hand, the way a transition picked
        // in Premiere fills Effect Controls: the panel speaks for the cut and
        // nothing else, so its two sections are at the top rather than under
        // everything the clip either side has (`video-transition-wt.html`).
        // With the mock's headings the two are one group, Properties, as
        // both transitions mocks draw `#gProps` (`cutFillsProperties`).
        if editorState.selectedEditPoint != nil || editorState.selectedClipCutIndex != nil,
           set.contains(.editPoint) {
            if Experiments.shared.dockHeadersEnabled {
                set.formIntersection([.layers, .transitions, .library])
                set.insert(.keys)
            } else {
                set.formIntersection([.layers, .editPoint, .transition, .transitions, .library])
            }
        }
        // ...and so is a zoom: the panel speaks for the zoom in hand.
        if set.contains(.zoom) {
            set.formIntersection([.layers, .zoom, .library])
        }
        // ...and so is a track picked on its header (`EditorState+Tracks`):
        // the panel says a track is picked rather than talking about the
        // whole document as though nothing were.
        if editorState.documentHasTime, !editorState.tracksInHand.isEmpty {
            set.formIntersection([.layers, .library])
            set.insert(.track)
        }
        if selectedLayer?.isCaptionsLayer == true { set.remove(.placement) }
        return set
    }

    /// What a piece inside a copy does not answer for. Everything here is a
    /// fact the original decides.
    /// A cut is the thing picked and the dock draws the mock's headings: then
    /// Properties speaks for the cut (`video-transitions.html`, `#gProps`),
    /// its chip saying Transition or Edit point, its three dots the cut's own
    /// menu, and Edit point and Transition the two sections inside it
    /// (`CutPropertiesInspector`) rather than two groups of their own.
    private var cutFillsProperties: Bool {
        guard Experiments.shared.dockHeadersEnabled,
              editorState.selectedEditPoint != nil || editorState.selectedClipCutIndex != nil
        else { return false }
        return (watchedTimeFacts ?? PanelTimeFacts(editorState)).showsCut
    }

    private static let sectionsAPieceDoesNotOwn: Set<InspectorSectionID> = [
        .arrange, .geometry, .frame, .columns, .placement, .color, .effects, .shadow,
        .annotation, .callout, .lens, .text, .reveal, .measure, .collage, .motion,
    ]

    private var orderedAvailableSections: [InspectorSectionID] {
        let available = availableSections
        let inOrder = withoutLayersUnderATimeline(withTheToolInHand(timeOrdered(order).filter { available.contains($0) }))
        // ...and then the panel's own rule about which of the OPTIONAL sections
        // are worth showing at all (Next, `next-panel-sections`). The test
        // above says a section applies to what is picked; this one says the
        // document is actually doing the job that section is for, which is a
        // fact about the document rather than about the selection — so nothing
        // here can make the panel rearrange itself as you click around. See
        // `PanelSectionVisibility`.
        guard Experiments.shared.panelSectionsEnabled else { return inOrder }
        let situation = editorState.panelSectionSituation
        let choices = editorState.panelChoices
        return inOrder.filter {
            PanelSectionVisibility.isShown($0.rawValue,
                                           choices: choices,
                                           in: situation)
        }
    }

    /// A tool's settings only while that tool is in hand, directly above the
    /// pick's own sections (`PanelToolSettings`, Next). The conditions that
    /// add a tool section already ask for its tool; this is the one rule over
    /// them, so a saved order cannot bury the section under the pick and no
    /// tool's section can outlive the tool.
    private func withTheToolInHand(_ sections: [InspectorSectionID]) -> [InspectorSectionID] {
        guard Experiments.shared.toolSettingsEnabled else { return sections }
        return PanelToolSettings.arrange(sections.map(\.rawValue), toolInHand: editorState.activeTool)
            .compactMap(InspectorSectionID.init(rawValue:))
    }

    /// Where the timeline is on screen, it is the layer list, so the panel
    /// leaves its own out and opens on the picked clip
    /// (`TimelineIsTheLayerList`, `video.html`'s "NO LAYERS GROUP"). Folding
    /// the timeline away brings the list straight back.
    private func withoutLayersUnderATimeline(_ sections: [InspectorSectionID]) -> [InspectorSectionID] {
        TimelineIsTheLayerList.sections(sections.map(\.rawValue),
                                        isOn: Experiments.shared.timelineIsTheLayerListEnabled,
                                        documentHasTime: editorState.documentHasTime,
                                        isTimelineOpen: editorState.motionStripPhase == .open)
            .compactMap(InspectorSectionID.init(rawValue:))
    }

    private var showsLayersList: Bool {
        TimelineIsTheLayerList.showsLayersList(isOn: Experiments.shared.timelineIsTheLayerListEnabled,
                                               documentHasTime: editorState.documentHasTime,
                                               isTimelineOpen: editorState.motionStripPhase == .open)
    }

    /// In a document with time, the saved order with what the picked layer is
    /// FOR moved up under Layers (`TimePanelOrder`, rule 5 in
    /// `InspectorDockLayout.swift`). Applied as it is drawn rather than written
    /// back, so the saved order stays the person's own and a document without
    /// time never sees it.
    private func timeOrdered(_ order: [InspectorSectionID]) -> [InspectorSectionID] {
        // Several things picked on the timeline: what they are leads, the
        // way the clip line leads for one (`EditorState+TrackRange`).
        if editorState.documentHasTime, editorState.timelinePickSummary != nil || cutFillsProperties {
            return [.keys] + order.filter { $0 != .keys }
        }
        guard let role = timeRole else { return order }
        return TimePanelOrder.arrange(order.map(\.rawValue), for: role)
            .compactMap(InspectorSectionID.init(rawValue:))
    }

    /// What the picked layer is for, in a document with time.
    private var timeRole: TimePanelOrder.Role? {
        guard editorState.documentHasTime,
              let layer = selectedLayer ?? editorState.soundLayerInHand else { return nil }
        return TimePanelOrder.role(of: layer)
    }

    /// The optional sections this release actually builds, in the order the
    /// Sections list shows them. A section behind a flag that is off is not
    /// offered, because a switch for something the app cannot show is a switch
    /// that does nothing.
    ///
    /// The Library's own picked-tile section is never a row of its own: it is
    /// part of the shelf and takes the shelf's answer (`PanelSectionVisibility`).
    private var offeredOptionalSections: [InspectorSectionID] {
        let flags = Experiments.shared
        return PanelSectionVisibility.optionalSections
            .compactMap(InspectorSectionID.init(rawValue:))
            .filter { id in
                switch id {
                case .library: flags.libraryEnabled
                case .libraryItem: false
                case .measurements: flags.measurePanelEnabled
                case .motion: flags.motionEnabled
                case .placement: flags.placementEnabled
                case .columns: flags.framesEnabled
                case .arrange: flags.alignLayersEnabled
                case .component: flags.componentsEnabled
                // The Shadow section only exists in the release without the
                // Appearance/Effects split; with the split on it is a row in
                // the parts list and there is nothing here to switch.
                case .shadow: !flags.shapePartsEnabled
                default: true
                }
            }
    }

    /// A section's header furniture and, where the section needs explaining,
    /// the question mark that explains it. The panel says labels and tools,
    /// never sentences (the user, 2026-09-25): what a section cannot show by
    /// itself lives behind that mark, not under its rows.
    private func sectionAccessory(_ id: InspectorSectionID) -> AnyView? {
        let furniture = sectionFurniture(id)
        // The cut's two sections carry their own marks inside Properties; the
        // keying one on its header would be about something not picked.
        if id == .keys, cutFillsProperties { return furniture }
        guard let help = Self.sectionHelp(id) else { return furniture }
        // With the mock's headings the group's own buttons end the row (the
        // Properties menu is the last thing on it), so the mark goes first.
        let helpFirst = Experiments.shared.dockHeadersEnabled
        return AnyView(HStack(spacing: 6) {
            if helpFirst { SectionHelpMark(section: id.title, text: help) }
            if let furniture { furniture }
            if !helpFirst { SectionHelpMark(section: id.title, text: help) }
        })
    }

    /// What a section's question mark says. Only for a section whose way of
    /// working cannot be seen in its rows.
    static func sectionHelp(_ id: InspectorSectionID) -> String? {
        switch id {
        case .fades: SoundFadesInspector.headerHelp
        case .keys: PropertyKeysInspector.sectionHelp
        case .space3D: Space3DInspector.sectionHelp
        case .camera: CameraInspector.sectionHelp
        case .reveal: TextRevealInspector.sectionHelp
        case .chart: ChartInspector.sectionHelp
        case .title: TitleRestyleInspector.sectionHelp
        case .titlePart: TitlePartInspector.sectionHelp
        case .editPoint: EditPointInspector.sectionHelp
        case .transition: TransitionInspector.sectionHelp
        case .transitions: TransitionsGroup.sectionHelp
        case .agent: AskCopy.helpLine
        default: nil
        }
    }

    /// The mock's `.cnt` beside a section's title, with its headings on
    /// (`next-dock-headers`): what Properties has picked, the Library's scope,
    /// how many effects and measurements there are. Nil without them, where
    /// the same facts ride `sectionFurniture` as they always have.
    private func sectionChip(_ id: InspectorSectionID) -> DockHeaderChip.Content? {
        guard Experiments.shared.dockHeadersEnabled else { return nil }
        let text: String?
        switch id {
        case .layers:
            // Every layer the list could show, the total the find field
            // counts against (`component-configure-wt.html`, `#layerCount`).
            text = LayersPanelHeader.countChip(layerCount: editorState.searchableLayerCount)
            return text.map { .init(text: $0, field: "Layers Count") }
        case .keys where cutFillsProperties:
            text = DockGroupHeader.cutChip(carriesTransition: editorState.cutInHand?.cut.transition != nil)
            return text.map { .init(text: $0, field: "Properties Kind") }
        case .keys:
            text = editorState.timelinePickSummary != nil ? nil : DockGroupHeader.chip(editorState.keyLayerKind)
            return text.map { .init(text: $0, field: "Properties Kind") }
        case .library:
            text = libraryScope.title
            return text.map { .init(text: $0, field: "Library Scope") }
        case .effects where Experiments.shared.shapePartsEnabled:
            text = DockGroupHeader.countChip(editorState.layerEffectRows.count)
            return text.map { .init(text: $0, field: "Effects Count") }
        case .measurements:
            text = DockGroupHeader.countChip(editorState.measurementCount)
            return text.map { .init(text: $0, field: "Measurements Count") }
        case .agent:
            return editorState.ask.chip.map { .init(text: $0, field: "Agent State") }
        case .soundEffects:
            text = DockGroupHeader.countChip(editorState.soundLevelInHand.effectRows.count)
            return text.map { .init(text: $0, field: "Audio Effects Count") }
        default:
            return nil
        }
    }

    /// Header furniture for sections that carry any: the Measurements group's
    /// count badge and panel menu (§6), and the Library's scope, so a
    /// collapsed Library still says what it is set to.
    private func sectionFurniture(_ id: InspectorSectionID) -> AnyView? {
        switch id {
        case .layers where Experiments.shared.dockHeadersEnabled:
            // The mock's Make Component button and panel menu
            // (`component-configure-wt.html`, `#gLayersH`).
            return AnyView(LayersHeaderControls())
        case .effects where Experiments.shared.shapePartsEnabled:
            // The plus that makes Effects a list you add to. It rides the
            // HEADER rather than the foot of the list, because the dock gives a
            // section a height and scrolls the rest inside it: one shadow is
            // already enough to push a foot button out of sight, and the one
            // gesture that adds an effect may never be the thing you have to go
            // looking for.
            return AnyView(AddEffectButton())
        case .motion:
            // The plus that makes Motion a list you add to, and beside it the
            // play button, because "does it look right" is a question you ask
            // after every single change and it may never be the thing you have
            // to go looking for.
            return AnyView(HStack(spacing: 6) {
                MotionPreviewButton()
                AddMotionButton()
            })
        case .component:
            // The variants mock's `Component  ◆ linked` (`ui-variants.html`,
            // `#gProps`): an instance says it still follows its main in one
            // word on the header, where a collapsed section still says it.
            guard selectedLayer?.isMainComponent != true else { return nil }
            let selection = editorState.componentKnobSelection
            guard selection.isPresent, !selection.hasDifferentComponents,
                  let componentID = selection.componentID,
                  let main = editorState.document?.mainComponent(componentID: componentID)
            else { return nil }
            return AnyView(ComponentLinkedBadge(mainName: main.name))
        case .measurements:
            return AnyView(MeasurementsSectionAccessory(
                showsCount: !Experiments.shared.dockHeadersEnabled))
        case .soundEffects:
            // The mock's `#gEffects` plus and its `#efxMenu`.
            return AnyView(AddSoundEffectButton())
        case .transitions:
            // The mock's `.dgrp-h` plus (`#efxMenu`): the two verbs that act
            // on the picked tile across the whole timeline.
            return AnyView(TransitionsGroupMenu())
        case .editPoint, .transition, .sound, .track:
            // The mock's `.sec-h .mut`: where the cut is, what is on it, and
            // which file the picked sound came from.
            let note = switch id {
            case .editPoint: EditPointInspector.headerNote(editorState)
            case .transition: TransitionInspector.headerNote(editorState)
            case .track: TrackInspector.headerNote(editorState)
            default: SoundInspector.headerNote(editorState)
            }
            guard let note else { return nil }
            let noteText = Text(note)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(VideoKit.Palette.faint)
                .lineLimit(1)
                .truncationMode(.middle)
                .panelReadout(note)
                .playtestField("\(id.title) header")
            return AnyView(noteText)
        // The mock's `.sec-h .mut` note ("drag the diamonds on the lane") is
        // the Fades question mark now: the user asked on 2026-09-25 for no
        // sentences in the panel, the explanation behind a mark in the header.
        case .keys where cutFillsProperties:
            // The mock's panel menu on the cut (`video-transitions.html`,
            // `#propMenu`): Copy, Paste and Reset to Default Length.
            return AnyView(TransitionPanelMenu())
        case .keys:
            // With the mock's headings the kind is the chip and the header
            // ends in the pane's menu, as `video.html` draws `#gProps`.
            if Experiments.shared.dockHeadersEnabled { return AnyView(PropertiesPanelMenu()) }
            return AnyView(PropertyKeysSectionAccessory())
        case .library:
            let scope = libraryScope
            let chipped = Experiments.shared.dockHeadersEnabled
            return AnyView(HStack(spacing: 6) {
                if !chipped {
                    Text(scope.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // The mock's `.dgrp-h` plus: the ways something gets onto the
                // shelf (`video.html`, #libMenu).
                if editorState.canImportMedia { LibraryAddMenu() }
            })
        case .arrange:
            // What these buttons line up AGAINST, when it is not the selection
            // itself. That is the one thing about this section you cannot work
            // out by looking at it, and beside the heading it costs no line of
            // panel and is still said when the section is collapsed. It used to
            // be a sentence underneath (UX-PATTERNS §4, "How much a section may
            // say", 2026-09-14).
            guard let reference = editorState.arrangeReferenceName else { return nil }
            return AnyView(Text("in \(reference)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail))
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
            // A title tile is named after its kind: a picked lower third is a
            // Name Card, not a Component.
            if let preset = editorState.titlePresetInPanel { return preset.kind.name }
            // A catalog tile is named after its kind too: a Background, a
            // Picture, a Component.
            if libraryScope == .catalog {
                if editorState.catalogBackgroundInPanel != nil { return VideoCatalogCategory.backgrounds.singular }
                if editorState.selectedComponentLayer != nil || editorState.selectedStarterComponent != nil {
                    return VideoCatalogCategory.components.singular
                }
                return VideoCatalogCategory.logos.singular
            }
            return libraryScope.itemTitle
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
        // A video clip's sound sections say they are its audio, so Fades on
        // a video is never read as the picture fading (`TimePanelOrder`).
        if let role = timeRole, TimePanelOrder.trails(role).contains(id.rawValue) {
            return TimePanelOrder.title(id.rawValue, shown: id.title, for: role)
        }
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
    private func sectionContent(_ id: InspectorSectionID, ceiling: CGFloat?,
                                inListsPane: Bool = false) -> some View {
        switch id {
        case .layers:
            // The one section that bounds itself: it is handed the dock's
            // ceiling and applies it to its rows, so its count line and grab
            // bar stay put instead of scrolling away with them.
            LayersListView(dockCeiling: ceiling,
                           inListsPane: inListsPane,
                           onMetrics: { natural, extras in
                               budget.bodies[.layers] = natural
                               budget.listExtras[.layers] = extras
                           })
        case .measurements:
            MeasurementsListView()
        case .arrange:
            ArrangeInspector()
        case .geometry:
            // Unreachable: the dock never offers this section any more (see
            // `availableSections`). The same view is what the Position and Size
            // popover shows, and the case stays here because the enum still
            // carries `.geometry` for every order somebody has saved.
            GeometryInspector()
        case .measureTool:
            MeasureToolInspector()
        case .wandTool:
            WandToolInspector()
        case .fillTool:
            FillToolInspector()
        case .cropTool:
            CropToolInspector()
        case .calloutTool:
            CalloutToolInspector()
        case .lensTool:
            LensToolInspector()
        case .brushTool:
            BrushToolInspector()
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
        case .lens:
            if let layer = selectedLayer, layer.lensKind != nil {
                LensInspector(layer: layer)
            }
        case .text:
            if selectedLayer?.isCaptionsLayer == true {
                CaptionsTextInspector()
            } else {
                TextInspector()
            }
        case .reveal:
            TextRevealInspector()
        case .chart:
            ChartInspector()
        case .title:
            TitleRestyleInspector()
        case .titlePart:
            TitlePartInspector()
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
        case .motion:
            MotionListInspector()
        case .keys:
            if cutFillsProperties {
                CutPropertiesInspector()
            } else {
                PropertyKeysInspector()
            }
        case .space3D:
            Space3DInspector()
        case .camera:
            CameraInspector()
        case .reframe:
            // Never offered (see `availableSections`); kept for saved orders.
            EmptyView()
        case .editPoint:
            EditPointInspector()
        case .transition:
            TransitionInspector()
        case .zoom:
            ZoomInspector()
        case .track:
            TrackInspector()
        case .transitions:
            TransitionsGroup()
        case .speed:
            SpeedInspector()
        case .sound:
            SoundInspector()
        case .fades:
            SoundFadesInspector()
        case .gain:
            SoundGainInspector()
        case .soundEffects:
            SoundEffectsInspector()
        case .captions:
            CaptionsInspector()
        case .shadow:
            ShadowInspector()
        case .agent:
            AgentPanel()
        case .library:
            // Deliberately NOT `.equatable()`. A shelf saying it is the same
            // as any other shelf was true of the value and false of what it
            // draws: the panel's own scope and search box live in `@State` and
            // `@AppStorage`, so an always-true `==` let SwiftUI keep the tile
            // grid it built first. Switching from Media to Components moved
            // the tab, the header and the search box and left the old tiles
            // sitting under them (2026-09-03). Sparing the shelf a re-run has
            // to start from what the shelf is actually made of.
            // The shelf reports the two halves of what it costs the dock — the
            // tile grid, which the dock may take from, and the picker, search
            // box and grab bar around it, which it may not — and takes the
            // ceiling back the same way the layers list does.
            LibraryPanel(dockCeiling: ceiling,
                         inListsPane: inListsPane,
                         onMetrics: { natural, extras, floor in
                             record(bodyHeight: natural, for: .library)
                             if budget.listExtras[.library] != extras {
                                 budget.listExtras[.library] = extras
                             }
                             if budget.shelfFloor != floor { budget.shelfFloor = floor }
                         })
        case .libraryItem:
            // The picked tile's section, named and filled by the scope it came
            // from: a capture's details, or a component's.
            if let preset = editorState.titlePresetInPanel {
                LibraryTitlePresetInspector(preset: preset)
            } else if let look = editorState.catalogBackgroundInPanel {
                LibraryBackgroundInspector(look: look)
            } else if editorState.selectedComponentLayer != nil {
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
        // move of those sections, leaving any arrangement they made by hand
        // around them alone. The list of moves, and what each one is for, is
        // `orderMigrations` above; `PanelSectionOrder.upgrade` runs the ones
        // this saved order has not had, in order, and says where it ended up.
        let upgraded = PanelSectionOrder.upgrade(merged, from: orderVersion,
                                                 through: Self.orderMigrations())
        merged = upgraded.order
        if orderVersion != upgraded.version { orderVersion = upgraded.version }
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
        // Only the part of the panel the section was picked up in makes way.
        guard drag.section != nil, drag.sections == sections,
              let index = sections.firstIndex(of: id) else { return 0 }
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
        folds.isFolded(id)
    }

    /// The curve a section opens and shuts on, and nothing with Reduce Motion
    /// on: the section is simply open or shut. The section grows or shrinks
    /// and everything under it slides with it, on this one curve.
    private var foldMotion: Animation? {
        reduceMotion ? nil : .spring(duration: 0.25)
    }

    /// A click on a header. The section redraws itself; this panel redraws
    /// only when the fold changed what the dock's lists may be given, so a
    /// shut form hands its room to the layers list on the same curve.
    ///
    /// Opening a folded section takes its room from the sections above it,
    /// folding the nearest first, and leaves the ones under it as they were
    /// (`PanelOpenRoom`, the user 2026-10-24). Those folds land in the
    /// passes after the click, on the same curve: in the click's own pass
    /// they held a frame (17.5ms opening a recording's Transitions, which
    /// folded two, `section-fold-motion-walk`).
    private func toggleCollapsed(_ id: InspectorSectionID) {
        #if PHOTONZ_PLAYTEST
        let started = ContinuousClock.now
        #endif
        let making = isCollapsed(id) ? roomToOpen(id) : []
        #if PHOTONZ_PLAYTEST
        if isCollapsed(id) { notePanelOpenRoomCost(ContinuousClock.now - started) }
        #endif
        withAnimation(foldMotion) {
            refold { folds.toggle(id) }
        }
        foldOnePerPass(making)
    }

    /// Folds these, the first a pass from now and each of the rest a pass
    /// after the one before, all on the fold's curve. Two in one pass held
    /// a frame too (16.1 to 17.6ms, a recording's Time and Captions).
    private func foldOnePerPass(_ sections: [InspectorSectionID]) {
        guard let first = sections.first else { return }
        DispatchQueue.main.async {
            withAnimation(foldMotion) {
                refold { folds.fold([first]) }
            }
            foldOnePerPass(Array(sections.dropFirst()))
        }
    }

    /// The sections to fold so `id`, folded now, opens whole with everything
    /// on screen under it still on screen (`PanelOpenRoom`). Only what is on
    /// screen counts: the Layers pane, the Library's pane, and the picked
    /// thing's sections whose headers are in view. Empty when there is room,
    /// when folding cannot make enough, or before the panel has measured
    /// what it needs.
    private func roomToOpen(_ id: InspectorSectionID) -> [InspectorSectionID] {
        // Why a plan was not made, for a walk to read; nothing in the shipping build.
        func skip(_ why: String) -> [InspectorSectionID] {
            #if PHOTONZ_PLAYTEST
            recordPanelOpenRoom("\(id.rawValue): not worked out, \(why)")
            #endif
            return []
        }
        guard let column = listsColumnHeight else { return skip("the panel is not measured yet") }
        let lists = listsReveal.drawnSections
        let pick = reveal.drawnSections
        let shelf = shelfReveal.drawnSections
        guard lists.contains(id) || pick.contains(id) || shelf.contains(id) else {
            return skip("it is not drawn")
        }
        let padding = 2 * DockMetrics.listTopPadding
        let divider = DockMetrics.sectionDividerHeight
        let showsListsGrip = !lists.isEmpty && !pick.isEmpty
        // The whole stack the three parts share, less the dividers between
        // them and the padding each part draws above and below its sections.
        var room = column + ListsPaneGrip.thickness - padding
        if showsListsGrip { room -= ListsPaneGrip.thickness }
        if !lists.isEmpty { room -= padding }
        if !shelf.isEmpty { room -= ListsPaneGrip.thickness + padding }

        var entries: [PanelOpenRoom.Entry] = []
        func add(_ section: InspectorSectionID, open: CGFloat?) -> Bool {
            guard let header = budget.headers[section], let open else { return false }
            entries.append(PanelOpenRoom.Entry(
                key: section.rawValue, folded: header + divider, open: max(open, header + divider),
                isOpen: !isCollapsed(section),
                isPromised: DockMetrics.promisedSections.contains(section)))
            return true
        }
        let full = InspectorDockLayout(budget: budget, collapsed: { _ in false })

        // The Layers pane: drawn at the height its divider chose, or less
        // when its lists need less, never squeezed by the pick. With nothing
        // picked it is the whole column and its lists give way like any list.
        let paneChosen = min(PanelListsPane.chosenHeight(stored: listsPaneStored.wrappedValue > 0
                                                              ? CGFloat(listsPaneStored.wrappedValue) : nil,
                                                          column: column),
                             PanelListsPane.maxAllowedHeight(column: column, floor: listsPaneFloor(lists)))
        for section in lists {
            guard let whole = full.openHeight(of: section, whole: true) else {
                return skip("\(section.rawValue) is not measured")
            }
            let padded = whole + (Self.boundsItself(section) ? DockMetrics.bodyBottomPadding : 0)
            let open = pick.isEmpty ? full.openHeight(of: section, whole: section == id)
                : min(padded, paneChosen - padding)
            guard add(section, open: open) else { return skip("\(section.rawValue) is not measured") }
        }

        // The pick's sections in view. One under the opened section keeps
        // its header on screen, and its body may slide under the fold like
        // anything in a scroller: holding a recording's audio sections whole
        // at the foot folded Appearance to reopen Effects (2026-10-24).
        let viewport = reveal.viewportHeight
        let opening = pick.firstIndex(of: id)
        for (index, section) in pick.enumerated() {
            let frame = reveal.sectionFrames[section]
            let headerInView = frame.map { $0.minY < viewport - 4 && $0.maxY > 4 } ?? false
            guard section == id || headerInView else { continue }
            let after = opening.map { index > $0 } ?? false
            let open = after
                ? budget.headers[section].map { $0 + divider }
                : full.openHeight(of: section, whole: section == id)
            guard add(section, open: open) else { return skip("\(section.rawValue) is not measured") }
        }

        // The Library's pane: the height chosen for it open, its header shut.
        // Its share is of the room under the Layers pane, so a plan that
        // folds Layers makes it taller: it is worked out again for that.
        let listKeys = Set(lists.map(\.rawValue))
        func planned(foldingLists folded: Set<String>) -> PanelOpenRoom.Plan? {
            var all = entries
            let pane = padding + all.filter { listKeys.contains($0.key) }.reduce(CGFloat(0)) { sum, entry in
                sum + (entry.key == id.rawValue ? entry.open : folded.contains(entry.key) ? entry.folded : entry.now)
            }
            for section in shelf {
                let split = (pick: pick, lists: lists, shelf: shelf)
                let shelfAt = shelfColumn(split, pickIsEmpty: pick.isEmpty,
                                          paneHeight: pick.isEmpty ? 0 : pane,
                                          showsListsGrip: showsListsGrip)
                // As `shelfPaneHeight` draws it unheld, less the room it only
                // grows into when the pick leaves some.
                let least = shelfStored.wrappedValue > 0 ? nil : full.leastHeight(of: shelf)
                let height = PanelShelfPane.atLeastTheShelf(shelfChosen(split, column: shelfAt),
                                                            least: least, column: shelfAt)
                guard let header = budget.headers[section] else { return nil }
                all.append(PanelOpenRoom.Entry(key: section.rawValue, folded: header + divider,
                                               open: max(height - padding, header + divider),
                                               isOpen: !isCollapsed(section)))
            }
            guard let index = all.firstIndex(where: { $0.key == id.rawValue }) else { return nil }
            #if PHOTONZ_PLAYTEST
            defer { entriesSaid = all }
            #endif
            return PanelOpenRoom.plan(all, opening: index, room: room)
        }
        #if PHOTONZ_PLAYTEST
        var entriesSaid: [PanelOpenRoom.Entry] = []
        #endif
        guard var plan = planned(foldingLists: []) else { return [] }
        let listsFolded = listKeys.intersection(plan.folds)
        if !listsFolded.isEmpty {
            guard let again = planned(foldingLists: listsFolded) else { return [] }
            plan = again
        }
        #if PHOTONZ_PLAYTEST
        recordPanelOpenRoom("\(id.rawValue): room \(Int(room)), "
            + entriesSaid.map { "\($0.key) \(Int($0.isOpen || $0.key == id.rawValue ? $0.open : $0.folded))" }
                .joined(separator: " ")
            + (plan.fits ? (plan.folds.isEmpty ? ", fits" : ", folds \(plan.folds.joined(separator: ","))")
                : ", cannot fit, folds nothing"))
        #endif
        return plan.folds.compactMap(InspectorSectionID.init(rawValue:))
    }

    /// The Agent group opened if it was folded and scrolled on screen if it
    /// was not, without moving one that is already in view.
    ///
    /// Looked at a few times, a beat apart: a panel the ask has just brought
    /// out, or one sliding in with Edit, builds its sections over several
    /// passes, and a look before the Agent group exists scrolls to nothing. A
    /// later look does nothing once the group is on screen.
    private func showAgentSection(_ proxy: ScrollViewProxy) {
        expand(.agent)
        for wait in Self.agentRevealLooks {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                guard editorState.ask.isRevealPending || wait == Self.agentRevealLooks.first else { return }
                expand(.agent)
                guard let frame = reveal.sectionFrames[.agent] else {
                    proxy.scrollTo(InspectorSectionID.agent, anchor: .top)
                    return
                }
                let inView = frame.minY >= 0 && frame.maxY <= reveal.viewportHeight
                guard !inView else {
                    editorState.ask.isRevealPending = false
                    return
                }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    proxy.scrollTo(InspectorSectionID.agent, anchor: .top)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (Self.agentRevealLooks.last ?? 0) + 0.1) {
            editorState.ask.isRevealPending = false
        }
    }

    /// When the Agent reveal looks, after the ask: the first for a panel
    /// already up, the later ones for a panel still arriving.
    private static let agentRevealLooks: [Double] = [0.08, 0.3, 0.7, 1.2]

    /// The Chart section opened and put at the top of the view, so its
    /// table is on screen whole rather than under the fold.
    private func showChartSection(_ proxy: ScrollViewProxy) {
        expand(.chart)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let frame = reveal.sectionFrames[.chart], frame.minY >= 0, frame.maxY <= reveal.viewportHeight {
                return
            }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                proxy.scrollTo(InspectorSectionID.chart, anchor: .top)
            }
        }
    }

    /// The Time section opened if it was folded and scrolled on screen if it
    /// was not, without moving one that is already in view.
    private func showTimeSection(_ proxy: ScrollViewProxy) {
        expand(.speed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let frame = reveal.sectionFrames[.speed] else {
                proxy.scrollTo(InspectorSectionID.speed, anchor: .top)
                return
            }
            let inView = frame.minY >= 0 && frame.maxY <= reveal.viewportHeight
            guard !inView else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                proxy.scrollTo(InspectorSectionID.speed, anchor: frame.minY < 0 ? .top : .bottom)
            }
        }
    }

    /// Opens a section that was left collapsed, and does nothing to one that is
    /// already open. No animation: the reveal that calls this needs a height
    /// that has finished changing.
    private func expand(_ id: InspectorSectionID) {
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            refold { folds.open(id) }
        }
    }

    /// Changes the folds, and tells this panel only if an open section would
    /// now be handed a different height than the one it was drawn with. A
    /// folded section's own height does not count: its body is out of sight,
    /// and handing it a new one rebuilt the whole of Appearance for nothing
    /// (60 to 80ms a fold, 2026-10-04).
    private func refold(_ change: () -> Void) {
        change()
        checkFoldBudget()
    }

    private func checkFoldBudget() {
        let sections = reveal.drawnSections
        let lists = listsReveal.drawnSections
        let shelf = shelfReveal.drawnSections
        let height = listsPaneHeight(for: lists, belowIsEmpty: sections.isEmpty && shelf.isEmpty)
        // A fold above the Library's pane, or of the shelf itself, can change
        // how tall the pane is drawn (it grows into the room the pick leaves).
        var shelfTakes: CGFloat = 0
        if !shelf.isEmpty {
            let showsListsGrip = !lists.isEmpty && !sections.isEmpty
            let shelfNow = shelfPaneHeight((pick: sections, lists: lists, shelf: shelf),
                                           pickIsEmpty: sections.isEmpty, paneHeight: height,
                                           showsListsGrip: showsListsGrip)
            if let drawnShelf = shelfReveal.drawnPaneHeight, abs(shelfNow - drawnShelf) > 0.5 {
                foldBudgetPass += 1
                return
            }
            shelfTakes = shelfNow + (showsListsGrip ? ListsPaneGrip.thickness : 0)
        }
        let now = pickLayout(lists, paneHeight: height, shelfHeight: shelfTakes).ceilings(for: sections)
        let drawn = reveal.drawnCeilings
        if sections.contains(where: { !isCollapsed($0) && now[$0] != drawn[$0] }) {
            foldBudgetPass += 1
            return
        }
        // A section folded above that moves the pane, or a list folded in
        // it: the lists still open in it may be handed a different share.
        guard !lists.isEmpty else { return }
        let listsNow = listsLayout(height).ceilings(for: lists)
        if height != listsReveal.drawnPaneHeight
            || lists.contains(where: { !isCollapsed($0) && listsNow[$0] != listsReveal.drawnCeilings[$0] }) {
            foldBudgetPass += 1
        }
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

/// Which dock sections wait unbuilt below the fold, over `PanelBodyReach`.
///
/// Deliberately NOT observed, for the reason `DockArrivals` is not: it is
/// written on every body pass and read on every scroll tick. What a section
/// draws comes from its own `DockBodyCell`, the way its fold does.
@MainActor private final class DockBodyReach {
    private var reach = PanelBodyReach()
    private var cells: [InspectorSectionID: DockBodyCell] = [:]
    /// Waiting sections that have come within reach and are owed a build.
    private var near: Set<String> = []
    /// A build pass is on its way, so a second one is not asked for.
    var isBuilding = false

    /// Notes this pass's sections, deciding the new ones from where the
    /// sections drawn last pass ended. With `holding` off, nothing waits.
    func draw(_ sections: [InspectorSectionID], after reveal: DockRevealScratch, holding: Bool) {
        guard holding else {
            reach.draw(sections.map(\.rawValue), bottoms: [:], viewport: nil)
            reach.buildAll()
            near.removeAll()
            PanelBuildsEverything.shared.somethingWaits = false
            settle(sections)
            return
        }
        var bottoms: [String: CGFloat] = [:]
        for id in reveal.drawnSections {
            if let frame = reveal.sectionFrames[id] { bottoms[id.rawValue] = frame.maxY }
        }
        let viewport: CGFloat? = reveal.viewportHeight > 0 ? reveal.viewportHeight : nil
        reach.draw(sections.map(\.rawValue), bottoms: bottoms, viewport: viewport)
        // The sections that measure their own room, and Effects, whose open
        // pane the dock scrolls to the moment it is added, are always built.
        for id in sections where !Self.mayWait(id) { reach.build(id.rawValue) }
        near.formIntersection(reach.held)
        PanelBuildsEverything.shared.somethingWaits = !reach.held.isEmpty
        settle(sections)
    }

    /// The cell a section reads whether it waits from.
    func cell(_ id: InspectorSectionID) -> DockBodyCell {
        if let cell = cells[id] { return cell }
        let cell = DockBodyCell()
        cells[id] = cell
        return cell
    }

    /// Hands each section its answer, writing only the cells that change: a
    /// section arriving is told before anything has drawn it.
    private func settle(_ sections: some Sequence<InspectorSectionID>) {
        for id in sections {
            let held = reach.isHeld(id.rawValue)
            let cell = cell(id)
            if cell.isHeld != held { cell.isHeld = held }
        }
    }

    private static func mayWait(_ id: InspectorSectionID) -> Bool {
        !InspectorPanel.boundsItself(id) && id != .effects
    }

    /// True when `id` is waiting and has just come within reach.
    func comesNear(_ id: InspectorSectionID, top: CGFloat, viewport: CGFloat) -> Bool {
        guard reach.comesNear(id.rawValue, top: top, viewport: viewport) else { return false }
        near.insert(id.rawValue)
        return true
    }

    /// Builds the highest section owed one. False when none is.
    func buildNext() -> Bool {
        guard let next = reach.nextToBuild(among: near) else { return false }
        reach.build(next)
        near.remove(next)
        PanelBuildsEverything.shared.somethingWaits = !reach.held.isEmpty
        if let id = InspectorSectionID(rawValue: next) { settle([id]) }
        return true
    }

    var hasMoreNear: Bool { reach.nextToBuild(among: near) != nil }
}

/// Which dock sections have left the screen and are still built, over
/// `PanelSectionDeparture`, and the pass that pulls them down.
@MainActor private final class DockDepartures {
    private var state = PanelSectionDeparture()
    /// The height each section was last allowed, so a lingering one is drawn
    /// exactly as it was and nothing in it is laid out afresh.
    private var lastCeilings: [InspectorSectionID: CGFloat] = [:]
    private var isReleasing = false

    /// The sections lingering this pass, after the ones shown.
    func draw(_ sections: [InspectorSectionID], pick: UUID?, lingers: Bool) -> [InspectorSectionID] {
        state.draw(sections.map(\.rawValue), pick: pick?.uuidString, lingers: lingers)
            .compactMap(InspectorSectionID.init(rawValue:))
    }

    /// `ceilings` for the sections shown, and the last ceiling of each one
    /// lingering.
    func ceilings(_ ceilings: [InspectorSectionID: CGFloat]) -> [InspectorSectionID: CGFloat] {
        var all = lastCeilings.filter { state.lingering.contains($0.key.rawValue) }
        all.merge(ceilings) { _, shown in shown }
        lastCeilings = all
        return all
    }

    /// Asks once for the pass after this one's commit, which lets every
    /// lingering section go and redraws the dock without them.
    func releaseNextPass(_ redraw: @escaping @MainActor () -> Void) {
        guard state.isHolding, !isReleasing else { return }
        isReleasing = true
        Task { @MainActor in
            await NextRunLoopPass.start()
            isReleasing = false
            guard state.isHolding else { return }
            state.release()
            redraw()
        }
    }
}

/// Whether one dock section waits unbuilt, read by that section alone.
@MainActor @Observable private final class DockBodyCell {
    var isHeld = false
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
    private var state = DockArrival()
    private var hasStarted = false

    /// The sections the dock may draw this pass, and a note of them for the
    /// next one. Safe to call more than once per pass: the answer does not
    /// change until `allow` opens the gate. The first pass of a dock sliding
    /// in with Edit mode builds nothing (`DockArrival`).
    func showing(_ target: [InspectorSectionID],
                 slidingIn: () -> Bool) -> [InspectorSectionID] {
        if !hasStarted {
            hasStarted = true
            if slidingIn() { state = DockArrival(slidingIn: true) }
        }
        return state.showing(target.map(\.rawValue)).compactMap(InspectorSectionID.init(rawValue:))
    }

    /// True when `target` asks for a section that has not been built, so the
    /// panel owes it one more pass.
    func isWaiting(for target: [InspectorSectionID]) -> Bool {
        state.isWaiting(for: target.map(\.rawValue))
    }

    /// A catch-up pass is on its way, so a second one is not asked for.
    var isCatchingUp = false

    /// Let the next section the selection asked for be built on the next pass.
    func allowNext(_ target: [InspectorSectionID]) {
        state.allowNext(target.map(\.rawValue))
    }
}

/// The question mark on a section header: rest on it and it says how the
/// section works, click it and the same words stay up. The one place a section
/// may explain itself, so its rows stay labels and tools.
struct SectionHelpMark: View {
    let section: String
    let text: String
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(section)")
        .panelHelp(text)
        .playtestControl("\(section) help", detail: section)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 220, alignment: .leading)
                .padding(10)
        }
    }
}

/// The panel takes nothing from whoever draws it: everything it shows it reads
/// for itself, and it redraws when that changes. So a pass of the editor
/// around it is never a reason to draw it again. Without this, every pass of
/// the editor made a new panel and SwiftUI could not tell it was the same one:
/// in the first 100ms of the slide into Edit on a long captioned recording
/// the panel's body ran five times, and two of those were only the editor
/// around it passing again (2026-09-30).
extension InspectorPanel: Equatable {
    nonisolated static func == (lhs: InspectorPanel, rhs: InspectorPanel) -> Bool { true }
}

/// The two things the panel's list of sections turns on that depend on where
/// the playhead is: whether it stands on a cut of the clip in hand, which
/// brings in Edit Point and Transition, and whether it is over a piece that
/// can be retimed, which brings in Time.
///
/// Read by the panel straight off the editor, they tied the whole panel to
/// the playhead: every step of it and every frame of playback built every
/// section again, about 3ms of each far jump
/// (`first-long-jump-when-zoomed-in-walk`). They flip only when the playhead
/// crosses into or out of one, so a watcher reads them and hands them over
/// when they do (`PanelTimeFactsWatcher`).
struct PanelTimeFacts: Equatable {
    var showsCut = false
    var canRetime = false

    @MainActor init(_ editorState: EditorState) {
        showsCut = editorState.canWorkWithClipTransitions && editorState.cutInHand != nil
        canRetime = editorState.canRetimeAClip
    }
}

/// Reads `PanelTimeFacts` on every step of the playhead, which costs next to
/// nothing, and tells the panel only when they change.
private struct PanelTimeFactsWatcher: View {
    @Environment(EditorState.self) private var editorState
    let onChange: (PanelTimeFacts) -> Void

    var body: some View {
        Color.clear
            .onChange(of: PanelTimeFacts(editorState), initial: true) { _, now in onChange(now) }
            .accessibilityHidden(true)
    }
}


/// The divider under the Layers pane (`PanelListsPane`): drag it down to give
/// Layers more of the panel, up to give the sections under it more, double
/// click it to put it back. A visible grabber on a hairline, the resize
/// cursor on it, so it reads as something to drag (the user, 2026-10-18: "i
/// can't drag the pane up and down"; it was a bare hairline until then).
private struct ListsPaneGrip: View {
    /// What the divider takes from the column; the grab strip spills past it.
    static let thickness: CGFloat = 9
    static let grabHeight: CGFloat = 13

    let height: CGFloat
    let contentHeight: CGFloat
    let floor: CGFloat
    let maxAllowedHeight: CGFloat
    let stored: Binding<Double>

    @State private var dragStartHeight: CGFloat?
    @State private var isHovering = false

    private var isShown: Bool {
        PanelAreaResize.isResizable(contentHeight: contentHeight, minHeight: floor,
                                    maxAllowedHeight: maxAllowedHeight)
    }

    var body: some View {
        ZStack {
            Divider().opacity(0.6)
            Capsule()
                .fill(.tertiary)
                .frame(width: 32, height: 4)
                .opacity(isShown ? (isHovering || dragStartHeight != nil ? 1 : 0.7) : 0)
        }
        .frame(height: Self.thickness)
        .frame(maxWidth: .infinity)
        .overlay {
            if isShown {
                Color.clear
                    .frame(height: Self.grabHeight)
                    .contentShape(Rectangle())
                    .playtestHover { inside in
                        guard inside != isHovering else { return }
                        isHovering = inside
                        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .onDisappear {
                        if isHovering { isHovering = false; NSCursor.pop() }
                    }
                    // GLOBAL space: the line moves with the drag, so a
                    // local translation would be measured against itself.
                    // Down grows the pane.
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { carry($0.translation.height) }
                        .onEnded { _ in end() })
                    .simultaneousGesture(TapGesture(count: 2).onEnded { stored.wrappedValue = 0 })
                    .panelHelp("Drag to resize Layers. Double click to reset.")
                    // The height in the words, so a walk can claim the divider
                    // came back where it was left.
                    .playtestControl("Layers divider", detail: "Layers \(Int(height.rounded())) pt tall")
            }
        }
        .zIndex(1)
        .panelAreaHandleProbe(
            PanelAreaHandleReading(area: "Lists", isShown: isShown, height: height,
                                   contentHeight: contentHeight, minHeight: floor,
                                   maxAllowedHeight: maxAllowedHeight, roomLeft: nil),
            carry: carry, end: end)
    }

    /// The pane has been pulled `grow` points taller than it was when the
    /// pointer took hold, one for one, between its floor and its lists.
    private func carry(_ grow: CGFloat) {
        let base = dragStartHeight ?? height
        if dragStartHeight == nil { dragStartHeight = height }
        stored.wrappedValue = Double(PanelAreaResize.storedCeiling(base: base, translation: grow,
                                                                   contentHeight: contentHeight,
                                                                   minHeight: floor,
                                                                   maxAllowedHeight: maxAllowedHeight))
    }

    private func end() {
        dragStartHeight = nil
    }
}

/// The divider over the Library's pane at the foot of the panel
/// (`PanelShelfPane`): drag it up to give the Library more of the panel, down
/// to give the pick more, double click it to put it back. Drawn the way the
/// Layers divider is, so the two read as the same kind of thing.
private struct ShelfPaneGrip: View {
    let height: CGFloat
    let contentHeight: CGFloat
    let floor: CGFloat
    let maxAllowedHeight: CGFloat
    /// The height chosen for the pane, and the room the pick leaves empty: a
    /// pane drawn taller than chosen has grown into that room, and pulling it
    /// down there gives the pick nothing (`PanelShelfPane.gripChoice`).
    let chosen: CGFloat
    let roomLeft: CGFloat?
    let stored: Binding<Double>
    /// Called on every move of the divider, so the pane follows it even with
    /// the pointer inside the pane.
    let onCarry: () -> Void

    @State private var dragStartHeight: CGFloat?
    @State private var dragStartChosen: CGFloat?
    @State private var isHovering = false

    private var isShown: Bool {
        PanelAreaResize.isResizable(contentHeight: contentHeight, minHeight: floor,
                                    maxAllowedHeight: maxAllowedHeight)
    }

    var body: some View {
        ZStack {
            Divider().opacity(0.6)
            Capsule()
                .fill(.tertiary)
                .frame(width: 32, height: 4)
                .opacity(isShown ? (isHovering || dragStartHeight != nil ? 1 : 0.7) : 0)
        }
        .frame(height: ListsPaneGrip.thickness)
        .frame(maxWidth: .infinity)
        .overlay {
            if isShown {
                Color.clear
                    .frame(height: ListsPaneGrip.grabHeight)
                    .contentShape(Rectangle())
                    .playtestHover { inside in
                        guard inside != isHovering else { return }
                        isHovering = inside
                        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .onDisappear {
                        if isHovering { isHovering = false; NSCursor.pop() }
                    }
                    // GLOBAL space, for the reason the Layers divider gives.
                    // Up grows the pane.
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { carry(-$0.translation.height) }
                        .onEnded { _ in end() })
                    .simultaneousGesture(TapGesture(count: 2).onEnded { stored.wrappedValue = 0 })
                    .panelHelp("Drag to resize the Library. Double click to reset.")
                    .playtestControl("Library divider", detail: "Library \(Int(height.rounded())) pt tall")
            }
        }
        .zIndex(1)
        .panelAreaHandleProbe(
            PanelAreaHandleReading(area: "Library", isShown: isShown, height: height,
                                   contentHeight: contentHeight, minHeight: floor,
                                   maxAllowedHeight: maxAllowedHeight, roomLeft: roomLeft),
            carry: carry, end: end)
    }

    /// The pane has been pulled `grow` points taller than it was when the
    /// pointer took hold, one for one, between its floor and its most.
    private func carry(_ grow: CGFloat) {
        let base = dragStartHeight ?? height
        if dragStartHeight == nil { dragStartHeight = height }
        let startChosen = dragStartChosen ?? chosen
        if dragStartChosen == nil { dragStartChosen = chosen }
        onCarry()
        let dragged = PanelAreaResize.storedCeiling(base: base, translation: grow,
                                                    contentHeight: contentHeight,
                                                    minHeight: floor,
                                                    maxAllowedHeight: maxAllowedHeight)
        stored.wrappedValue = Double(PanelShelfPane.gripChoice(dragged: dragged, startChosen: startChosen,
                                                               roomLeft: roomLeft))
    }

    private func end() {
        dragStartHeight = nil
        dragStartChosen = nil
    }
}
