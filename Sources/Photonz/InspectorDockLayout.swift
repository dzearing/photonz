// The right dock's layout rules, out of the view that draws them: the metrics every section is measured in, how the dock shares its height out between them, and the reveals that bring a thing the app just opened for you into view.

import PhotonzCore
import SwiftUI
// MARK: - The one rule

// **What you picked sits at the top, then where it sits, then what it looks
// like.** The dock is ordered so the section named after the thing you just
// clicked is the first thing under the layers list, with Position & Size under
// that, then Appearance and Effects, then everything general. The user chose
// the first half on 2026-09-13 over three other answers, one of which was the
// panel scrolling itself to the pick; the second half followed on 2026-09-15,
// when Position & Size was measured below the bottom edge at every window size
// this machine can open (1052 points of sections against a 968 point dock).
// There is no arithmetic that fits a dock over-subscribed by that much, so the
// only thing an ordering decides is which sections are above the fold, and the
// X, Y, width and height boxes had earned their place over the last rows of
// Appearance.
//
// It is one rule because it used to be three, each built on its own and each
// undoing the others: the order the sections sat in, a scroll that chased
// whatever you had just picked, and the room the Effects list kept for the
// effect you had just opened. Picking text left its settings off the bottom;
// picking a plain rectangle left the panel parked where the last pick put it,
// so the top of the panel was a headless colour row; and picking a row scrolled
// the layers list you clicked in off the top.
//
// So, in order of who does what:
//
// 1. **The ORDER puts the pick on screen.** `InspectorPanel.loadOrder` moves
//    every section named after a picked thing up under Layers, once, as a
//    numbered migration. Nothing has to move at pick time because nothing is
//    in the wrong place.
// 2. **The BUDGET keeps it on screen**, by shortening the lists rather than the
//    forms: see `ceilings(for:)` below and `DockHeightBudget`. Layers is a list
//    and gives up room; the pick's own section is a form and never does.
// 3. **A PICK NEVER SCROLLS THE DOCK.** There is no reveal on selection at all.
//    A reveal is for something the app opened for you that you could not have
//    known was there — the Library shelf, an effect's settings — and those two
//    are the whole of `InspectorDockReveal`. The one exception is the release
//    whose order has NOT been fixed: see `requestPick` at the end of this file.
//    That goes the day Next is promoted.
//
// The same rule written for a reader rather than for a compiler is in
// `docs/design/mocks/shared/UX-PATTERNS.md`, section 3, under Reveal.
//
// MARK: - ...and the rule about WHICH sections there are
//
// The rule above decides the ORDER. A second rule, in
// `PanelSectionVisibility` (PhotonzCore, pure and tested), decides which of
// the optional sections are drawn at all: **what you PICK never adds or
// removes an optional section; only what the document holds, the tool in your
// hand, and what you asked for may.** A document with no measurement in it has
// no Measurements section; make one and it arrives, and it does not then come
// and go as you click around. Anything automatic leaves out is one press
// away in the Sections row at the foot of the panel, which sits OUTSIDE this
// scroller for exactly that reason. Written for a reader in
// `docs/design/panel-sections.md`.
//
// MARK: - ...and the rule about HOW TALL they are allowed to be
//
// The two rules above decide the order and the cast. This one is the budget,
// and it is the one every section added from here on has to be read against.
//
// The user asked on 2026-09-07 for a promise: **Appearance and Effects are the
// two sections nobody should ever have to scroll to.** They are the two touched
// on every single layer, so they are the two that must always be whole on
// screen. That promise has been walked back by every feature that wanted room,
// seven times, because nobody wrote down what it COSTS.
//
// This is what it costs. The smallest window the app supports is 1200 by 720,
// which gives the dock **621 points**, less `listTopPadding` top and bottom, so
// **609 points to share**. Out of that:
//
//     the layers list at its floor         163pt   (112 body + header + count line)
//   + the section named after your pick    109-311pt
//   + Appearance                           195-669pt
//   + Effects                               68-391pt
//   ------------------------------------------------
//     must come to 609 or less.
//
// Measured across 3,334 recorded dock states, from 185 walks run on
// 2026-09-16, it never does, and Appearance or Effects was below the fold in
// 15% of them overall. At a 621pt dock that is **44%** of states; at the 781pt
// dock a taller window gives, **50%**; and even at the 969pt dock of the
// largest window this display can open, **12%**. Four worked examples at
// 1200 by 720:
//
//   | picked      | Layers | pick | Appearance | Effects | wants | over by |
//   | ---         | ---    | ---  | ---        | ---     | ---   | ---     |
//   | a piece of text | 163 | 198 |  231       |  68     |  747  |  126    |
//   | an arrow        | 163 |   - |  447       |  68     |  765  |  144    |
//   | a component copy| 163 | 311 |  195       |  68     | 1102  |  481    |
//   | a measurement   | 163 | 109 |  489       |  68     |  702  |   81    |
//
// Two things fall straight out of that table and neither was known before it
// was measured:
//
// 1. **Appearance is the biggest thing in the dock, not a small form.** It is a
//    LIST of the parts a thing is made of, and every switched-on part unfolds
//    all of its settings at once (`PartsInspector`, `ShapePartSettings`). An
//    arrow is 447pt of it and a measurement 489pt; the tallest recorded is
//    **669pt, which is more than the whole 621pt dock**. `scrollingSections`
//    below still calls it a form, so the budget may never shorten it.
// 2. **No ordering fixes this.** Ordering only decides which section is the one
//    left below the fold. It has now been re-ordered six times (the migrations
//    in `InspectorPanel`) and the total has not moved.
//
// So: **a section may not be added, and an existing one may not be allowed to
// grow, without saying which line of that table it spends from.** If the answer
// is "from Appearance's", it is not an answer.
//
// How the promise gets KEPT is an open question with the user as of
// 2026-09-16: see the task `appearance-is-below-the-fold-again-because-the-p`
// and its decision card. Until it is answered this comment is the measurement,
// not the fix.
/// The numbers every section in the dock is measured in.
enum DockMetrics {
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
    /// How short a list may be squeezed before the dock stops asking: about
    /// three rows. Under that a list stops reading as a list, and a dock that
    /// scrolls a little is better than six peepholes.
    static let listFloor: CGFloat = 112

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
    /// This is also half of why rule 1 above can stand without a scroll: the
    /// only thing between the top of the dock and the section named after what
    /// you picked is Layers, and Layers is on this list, so it is the one that
    /// gives way.
    ///
    /// Which of Appearance and Effects is the list flipped with the split
    /// (`next-shape-parts`, 2026-09-07). Appearance became a FORM — opacity,
    /// fill, outline, corner radius, four rows somebody designed — and Effects
    /// became the list, as long as whatever you added to it. Left the other way
    /// round, two shadows squeezed Appearance until its Width and Corner Radius
    /// rows were scrolled out of sight, which is the opposite of what the dock
    /// is for.
    @MainActor static var scrollingSections: Set<InspectorSectionID> {
        var sections: Set<InspectorSectionID> = [.layers, .measurements, .library]
        sections.insert(Experiments.shared.shapePartsEnabled ? .effects : .color)
        return sections
    }
}

// MARK: - What the dock has measured of itself

/// What the dock has measured of itself, which is everything
/// `InspectorDockLayout` needs to decide who gives up room.
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

// MARK: - Sharing out the height the dock has

/// Rule 2 of the dock rule above: given what the dock has measured of itself,
/// how tall each list section may be drawn.
///
/// A value with no view in it, so the arithmetic can be read — and argued with —
/// without reading a thousand lines of SwiftUI around it.
@MainActor struct InspectorDockLayout {
    let budget: DockBudgetScratch
    /// Which sections the reader has shut. A shut section costs its header and
    /// nothing else.
    let collapsed: (InspectorSectionID) -> Bool

    /// The dock's own padding above the first section and below the last is
    /// room no section can have.
    var room: CGFloat? {
        budget.viewportHeight.map { $0 - 2 * DockMetrics.listTopPadding }
    }

    /// How tall each list section may be drawn, given what the forms in the
    /// dock cost and how tall the dock is.
    ///
    /// A section is absent from the result when it may be drawn whole, which is
    /// every case where the panel fits, so the common dock is exactly the dock
    /// it always was — no extra scrollers, no frames pinned to a measurement
    /// taken a pass ago.
    func ceilings(for sections: [InspectorSectionID]) -> [InspectorSectionID: CGFloat] {
        let room = room
        let groups = sections.map { id -> DockHeightBudget.Group in
            let header = budget.headers[id] ?? DockMetrics.headerRowHeight
            let open = !collapsed(id)
            let body = open ? (budget.bodies[id] ?? 0) : 0
            let scrolls = open && DockMetrics.scrollingSections.contains(id)
            // A list pays for the chrome that does not scroll with it up
            // front; a form pays for its whole body up front, because none of
            // it may be taken away.
            let paid = scrolls ? (budget.listExtras[id] ?? 0) : body
            return DockHeightBudget.Group(key: id.rawValue,
                                          fixed: header + DockMetrics.sectionDividerHeight + paid,
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
                                                + DockMetrics.bodyBottomPadding,
                                            peek: DockMetrics.bodyPeek,
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
    /// you just opened OR JUST ADDED, so adding a second effect to a short
    /// window makes room for the new one rather than for the one above it.
    private func squeezeFloor(for id: InspectorSectionID, room: CGFloat?) -> CGFloat {
        // The Library shelf is a grid of TILES, and a tile is a picture with its
        // name under it. Cut one across the middle and it does not read as a
        // list with more in it, the way a cut list of rows does: it reads as a
        // row of pictures nobody has named, and the name was the whole of what
        // the tile said. So the shelf's floor is one whole row, never part of
        // one — plus the same sliver of the next row every other shortened body
        // in the dock keeps, so a cut shelf says there is more under it instead
        // of ending on clean glass and reading as the whole list.
        //
        // 100 points against the 112 every other list gets, which is still
        // LESS, so this cannot starve anything: it only stops the shelf being
        // handed a number that has no honest way to spend it. A shelf that fits
        // in one row never spends the sliver, because the budget never draws a
        // list taller than its own content.
        if id == .library { return LibraryShelfLayout.squeezeFloor(peek: DockMetrics.bodyPeek) }
        guard let panes = budget.listPanes[id], !panes.isEmpty else {
            return DockMetrics.listFloor
        }
        return DockHeightBudget.paneListFloor(
            panes,
            focus: budget.listFocus[id],
            spacing: EffectsListInspector.paneSpacing,
            topInset: EffectsListInspector.listInset,
            bottomInset: EffectsListInspector.listInset + DockMetrics.bodyBottomPadding,
            peek: DockMetrics.bodyPeek,
            base: DockMetrics.listFloor,
            viewport: room)
    }
}

// MARK: - What the dock has measured of the things it might reveal

/// The frames a reveal reads, kept by reference on purpose: they are written on
/// every scroll tick, and re-drawing the whole dock to write down where it has
/// just drawn something is the jank this exists to avoid.
@MainActor final class DockRevealScratch {
    var libraryFrame: CGRect?
    var viewportHeight: CGFloat = 0
    var isPending = false
    /// How many picks the dock has seen. Only the release that still scrolls to
    /// a pick reads it: a reveal waits a beat for the section it is about to
    /// scroll to to finish being laid out, and this is how the wait knows it is
    /// still the newest one.
    var pickPass = 0
    /// Where each effect in the Effects list is sitting, by
    /// `LayerEffectRow.id`, in the dock's visible area. Written on every scroll
    /// tick and read only when an effect has just been opened or added.
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

// MARK: - Bringing into view the things the app opened for you

/// Rule 3 of the dock rule above, and the whole of what is left of revealing:
/// the Library shelf the app has just filled, and the effect whose settings
/// have just appeared because you opened or added it.
///
/// **In Next, a pick is not in here.** Selection used to scroll the dock, and
/// that is the mechanism the user replaced with an order on 2026-09-13. It
/// survives below for the release that has NOT had the order fix, because
/// without either one a piece of text in a laptop window has its settings
/// below the bottom edge and nothing says they exist. It goes the day Next is
/// promoted.
@MainActor struct InspectorDockReveal {
    let scratch: DockRevealScratch
    let editorState: EditorState
    let proxy: ScrollViewProxy
    /// Opening a section the reveal is about to scroll to, since scrolling to
    /// a shut header shows a title and nothing else.
    let expand: (InspectorSectionID) -> Void
    /// The section named after what is picked, or nil when what is picked owns
    /// none. Only the release below uses it.
    let pickedSection: () -> InspectorSectionID?

    /// How long to wait before scrolling to an effect that has just been opened
    /// or added: a shade longer than the fold's own spring, so the pane is
    /// measured at the height it has settled at rather than partway through
    /// growing into it.
    static let effectRevealDelay = 0.24

    // MARK: The Library shelf

    /// The app has opened the Library shelf (View ▸ Show Library, or a command
    /// that fills it, like making a component). Bring it into view.
    ///
    /// A shelf already on screen must not move: pressing the same menu item
    /// twice should not make the dock jump. `DockReveal` makes that call, from
    /// the measured frame, once layout has one.
    func requestLibrary() {
        guard editorState.pendingLibraryReveal,
              Experiments.shared.libraryEnabled, editorState.isLibraryVisible else { return }
        // A collapsed shelf scrolled into view is a header and nothing else,
        // which is not "you can see it". Instantly, without the collapse
        // spring, so the reveal scrolls to a height that has stopped moving.
        expand(.library)
        scratch.isPending = true
        // The section may have appeared with this very state change, in which
        // case the measurement above lands first and this finds nothing left to
        // do. When it was already there and stationary, this is the only path.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { applyLibrary() }
    }

    func applyLibrary() {
        guard scratch.isPending, let frame = scratch.libraryFrame else { return }
        let action = DockReveal.action(sectionTop: frame.minY,
                                       sectionHeight: frame.height,
                                       viewportHeight: scratch.viewportHeight)
        scratch.isPending = false
        editorState.libraryRevealHandled()
        guard action != .none else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            proxy.scrollTo(InspectorSectionID.library, anchor: action == .top ? .top : .bottom)
        }
    }

    // MARK: An effect you opened or added

    /// An effect's settings have just appeared. Bring the whole pane on screen,
    /// and only if it is not already there.
    ///
    /// The pane is measured in the dock's visible area rather than in the
    /// Effects list, because the list can be inside a scroller of its own when
    /// the panel is over-subscribed: an effect can be perfectly placed in its
    /// list and still be somewhere nobody can see. One `scrollTo` covers both,
    /// since the pane is identified in the list SwiftUI is scrolling either
    /// way.
    func applyEffect(_ id: String) {
        // A second chevron pressed while this one was waiting: that press has
        // its own wait running, and it is measured from ITS fold rather than
        // from this one, so this turn is simply given up.
        guard editorState.effectToReveal == id else { return }
        editorState.effectRevealHandled()
        guard let frame = scratch.effectFrames[id],
              let here = scratch.room(for: .effects) else { return }
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
        let dock = DockReveal.action(sectionTop: scratch.sectionFrames[.effects]?.minY ?? 0,
                                     sectionHeight: scratch.sectionFrames[.effects]?.height ?? 0,
                                     viewportHeight: scratch.viewportHeight)
        let shift = scratch.shift(of: .effects, doing: dock)
        guard let room = scratch.room(for: .effects, shiftedBy: shift) else { return }
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

    // MARK: A pick, in the release without the order

    /// How long to wait after a pick before scrolling to the section it brought
    /// up. A section that has just appeared is built a pass after the click
    /// (see `PanelSectionArrival`) and the lists above it settle to their new
    /// heights in the pass after that, so a reveal measured any sooner is
    /// measuring a dock that is still moving.
    static let pickRevealDelay = 0.24

    /// You clicked a layer, in the list or on the canvas, and this is the
    /// release whose panel still keeps the pick's own section below Appearance
    /// and Effects. Bring it into view.
    ///
    /// Only the pick's OWN section: the dock is routinely taller than the panel
    /// there too, so something is always off screen, and the one thing that
    /// must not be is what you just clicked.
    ///
    /// Next does none of this. Its order puts the section under the layers
    /// list, so there is nothing to scroll to, and the cost this carries — the
    /// layers list you clicked in going off the top to show a section near the
    /// bottom — is exactly what the order was chosen to stop paying.
    func requestPick() {
        guard !Experiments.shared.shapePartsEnabled else { return }
        scratch.pickPass &+= 1
        let mine = scratch.pickPass
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pickRevealDelay) {
            guard scratch.pickPass == mine else { return }
            applyPick()
        }
    }

    private func applyPick() {
        // The Library shelf asked first and is mid-flight; two scrollers
        // fighting over the same dock is worse than either one losing.
        guard !scratch.isPending else { return }
        guard let id = pickedSection(), let frame = scratch.sectionFrames[id] else { return }
        let action = DockReveal.action(sectionTop: frame.minY,
                                       sectionHeight: frame.height,
                                       viewportHeight: scratch.viewportHeight)
        // Already all there: picking a second piece of text while its section
        // is under your eyes must not make the dock twitch.
        guard action != .none else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            proxy.scrollTo(id, anchor: action == .top ? .top : .bottom)
        }
    }
}
