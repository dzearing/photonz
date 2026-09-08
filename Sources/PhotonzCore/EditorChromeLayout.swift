import CoreGraphics

/// Pure, testable layout policy for the editor's *chrome* — the floating tool
/// toolbar and the docked right-side inspector — as the window is resized down.
///
/// The SwiftUI shell (`EditorView`, `LayersPanel`) owns the views; this type
/// owns the *decisions* so they can be unit-tested without a running app:
///  - the window's minimum size (the floor the layout is designed against),
///  - whether the inspector should auto-collapse at a given window width.
///
/// Toolbar overflow is measured, not estimated: the app hands `fittedToolCount`
/// the bar's real width and the room it has, and this decides how many tools
/// stay inline. The arithmetic here only sizes the STEP, so a wrong estimate
/// costs a layout pass, never a clipped bar.
///
/// Everything here is a pure function of sizes — no UIKit/AppKit/SwiftUI.
public enum EditorChromeLayout {

    // MARK: Window floor

    /// The smallest the editor window may get. Low enough that the responsive
    /// behavior (toolbar overflow, inspector auto-collapse) genuinely exercises
    /// *above* this floor — people resize to arbitrary sizes, not just the min.
    public static let minWindowWidth: CGFloat = 480
    /// The smallest window height. Leaves room for the canvas plus the floating
    /// toolbar without the two fighting for space.
    public static let minWindowHeight: CGFloat = 400

    // MARK: Floating tool bar

    /// How far the floating tool bar floats off the bottom of the canvas.
    public static let toolBarInset: CGFloat = 16
    /// The height EVERY glass group along the bottom of the canvas is drawn
    /// at: the tools, the colours, the grid chip, the zoom.
    ///
    /// Measured off the running app rather than guessed: the capsule around a
    /// 28pt control row comes out at 48pt. It is one number because the groups
    /// sit side by side and a person reads them as one row — and because each
    /// group used to take its height from whatever was inside it, which on
    /// 2026-09-07 had the tools at 48pt, the colours at 45pt and the zoom at
    /// 35pt on the same row. The zoom is the extreme case: a small slider and
    /// a borderless menu are only 15pt of content, so no amount of padding
    /// picked by hand keeps it level with a bar of buttons.
    public static let toolBarGroupHeight: CGFloat = 48

    /// The bar's own height, which is one group's height: everything that has
    /// to clear the bar measures from this.
    public static let toolBarHeight: CGFloat = toolBarGroupHeight
    /// The breathing room between the bar and whatever stacks on top of it, so
    /// the two read as two surfaces rather than one sitting on the other.
    public static let toolBarStackGap: CGFloat = 12

    /// Bottom padding for anything the canvas floats at bottom center — the
    /// Measure hint, the crop's Cancel/Crop pill — so it lands ABOVE the
    /// floating tool bar instead of behind it. The bar is drawn last and wins
    /// every overlap, so an overlay that does not clear this is simply
    /// invisible: the hint chip spent its life at 14pt, fully covered.
    public static let aboveToolBar: CGFloat = toolBarInset + toolBarHeight + toolBarStackGap

    /// The same band, with the tool settings capsule standing in between.
    ///
    /// The capsule (`ToolSettingsBar`) rides on its own row above the bar for
    /// whichever tool has something to set, so anything that used to clear
    /// only the bar has to clear the capsule too or land on top of it. Measure
    /// is one of the tools with a capsule AND the owner of the hint pill, so
    /// this is not a theoretical overlap.
    ///
    /// A height of zero is the no-capsule case and gives back exactly
    /// `aboveToolBar`, so nothing moves when the flag is off or the tool in
    /// hand has nothing to set.
    public static func aboveToolBar(toolSettingsHeight: CGFloat) -> CGFloat {
        guard toolSettingsHeight > 0 else { return aboveToolBar }
        return aboveToolBar + toolSettingsHeight + toolBarStackGap
    }

    /// Where the tool settings capsule sits: centred like the bar, one
    /// `toolBarStackGap` above it, as wide as it measures but never wider than
    /// the bar's own budget — going wider is what would push it off the edge
    /// of the picture, and the view wraps its contents instead.
    ///
    /// Nil when there is no capsule, so callers can treat "no capsule" and "no
    /// rect" as the same thing.
    public static func toolSettingsFrame(canvasSize: CGSize,
                                         width: CGFloat, height: CGFloat) -> CGRect? {
        guard width > 0, height > 0 else { return nil }
        let capped = min(width, toolBarBudget(canvasWidth: canvasSize.width))
        return CGRect(x: (canvasSize.width - capped) / 2,
                      y: canvasSize.height - toolBarInset - toolBarHeight
                        - toolBarStackGap - height,
                      width: capped, height: height)
    }

    /// Where a bottom-centre notice of `noticeSize` (the Measure mode hint,
    /// the "Copied" pill) sits in a canvas of `canvasSize`: centred, its
    /// bottom edge clear of the bar and of the tool settings capsule when one
    /// is up. Top-left origin, like every other rect the placement code takes.
    public static func bottomNoticeFrame(canvasSize: CGSize, noticeSize: CGSize,
                                         toolSettingsHeight: CGFloat = 0) -> CGRect {
        CGRect(x: (canvasSize.width - noticeSize.width) / 2,
               y: canvasSize.height - aboveToolBar(toolSettingsHeight: toolSettingsHeight)
                 - noticeSize.height,
               width: noticeSize.width, height: noticeSize.height)
    }

    /// Where the floating tool bar sits: centred, `toolBarInset` off the
    /// floor, `toolBarHeight` tall, and as wide as it measures. A bar that has
    /// not been measured yet (`toolBarWidth` of 0), or one that somehow
    /// overflows, reserves its whole `toolBarBudget`, which is the widest it
    /// can ever be inside the canvas.
    public static func toolBarFrame(canvasSize: CGSize, toolBarWidth: CGFloat) -> CGRect {
        let budget = toolBarBudget(canvasWidth: canvasSize.width)
        let width = toolBarWidth > 0 ? min(toolBarWidth, budget) : budget
        return CGRect(x: (canvasSize.width - width) / 2,
                      y: canvasSize.height - toolBarInset - toolBarHeight,
                      width: width, height: toolBarHeight)
    }

    /// The chrome along the bottom of the canvas that a floating panel (the
    /// measure legend) must never park behind: the notice pill's slot, the
    /// tool settings capsule if one is up, then the tool bar. The pill's slot
    /// is reserved whether or not a pill is up, so the legend never has to
    /// jump when one appears for two seconds.
    public static func bottomChrome(canvasSize: CGSize, toolBarWidth: CGFloat,
                                    noticeSize: CGSize,
                                    toolSettingsSize: CGSize = .zero) -> [CGRect] {
        let capsule = toolSettingsFrame(canvasSize: canvasSize,
                                        width: toolSettingsSize.width,
                                        height: toolSettingsSize.height)
        return [bottomNoticeFrame(canvasSize: canvasSize, noticeSize: noticeSize,
                                  toolSettingsHeight: capsule?.height ?? 0)]
            + (capsule.map { [$0] } ?? [])
            + [toolBarFrame(canvasSize: canvasSize, toolBarWidth: toolBarWidth)]
    }

    // MARK: Corner chrome

    /// How far anything parked in a canvas corner floats off its two edges.
    /// One number, shared, so two things that ever stack in a corner line up.
    public static let cornerInset: CGFloat = 12

    // Nothing parks in a canvas corner any more. The panel toggle used to,
    // floating in the top-right corner whenever the panel was closed, with the
    // measure legend hanging one stack gap below it; on 2026-09-06 it moved
    // into the window's own title bar, where a Mac keeps a panel toggle. The
    // legend now takes its corner outright, so it asks `PanelPlacement` for a
    // slot with no corner chrome to clear.

    // MARK: The panel's right edge

    /// How far in from the inspector panel's own right edge anything parked on
    /// that edge is drawn: the eye and the lock on a layer row, the grip on a
    /// section header, the cross that takes an effect out of the list.
    ///
    /// ONE number, shared, because the alternative was measured on 2026-09-07
    /// and reported by the user: each row and control carried its own trailing
    /// space (6 here, 12 there, 14 somewhere else) and the icons down the right
    /// of the panel did not share a centre.
    public static let panelEdgeInset: CGFloat = 14

    /// The slot EVERY icon on that edge is drawn in, whatever glyph is in it.
    ///
    /// A shared trailing space is not enough on its own: these glyphs are
    /// different widths, so lining up their BOXES leaves what is DRAWN on
    /// different lines, and the line a person sees is the drawn one. Measured
    /// at 11pt type: the eye is 17 wide, the grip 14, the open padlock 14.5 and
    /// the closed one 10.5 — so locking a layer used to slide its padlock 2pt
    /// sideways. A fixed slot with the glyph centred in it makes all of them
    /// one column.
    ///
    /// It is the eye's own width because the eye is the widest of them: the
    /// column then lands exactly where the eyes already were, so the fix moved
    /// the grips and the padlocks and left the layers list alone.
    public static let panelEdgeIconWidth: CGFloat = 17

    /// The gutter a list inside the panel keeps around its rows, so a selected
    /// row's highlight stops short of the panel's edges instead of running into
    /// them. The layers list and the measurements list share it.
    public static let panelListGutter: CGFloat = 8

    /// How far the column's centre line is in from the panel's right edge.
    /// This is the number a ruler on a screenshot measures.
    public static let panelEdgeCenterInset: CGFloat = panelEdgeInset + panelEdgeIconWidth / 2

    /// Where that line falls in a panel of this width. A distance from the
    /// panel's own edge, so resizing the panel carries the whole column with it.
    public static func panelEdgeCenterX(panelWidth: CGFloat) -> CGFloat {
        panelWidth - panelEdgeCenterInset
    }

    /// The trailing space a row needs when it is drawn inside a list that is
    /// already inset by `gutter`, so it reaches the same line as a control
    /// drawn straight onto the panel.
    ///
    /// Clamped at zero: a list inset further than the edge itself cannot reach
    /// the line, which is why `panelListGutter` is the smaller of the two.
    public static func panelEdgeInset(insideGutter gutter: CGFloat) -> CGFloat {
        max(0, panelEdgeInset - gutter)
    }

    // MARK: Tool bar fit

    /// One tool slot's share of the bar: a 28pt control plus the 14pt gap that
    /// follows it. Measured off the running app, not guessed.
    public static let toolBarSlotWidth: CGFloat = 42

    /// The widest a single slot gets: the selection group button wears a mode
    /// glyph and a chooser, so it runs about half again as wide as a plain tool.
    /// Growing the bar counts every slot at this width, so putting a tool back
    /// can never push the bar past the edge it just pulled back from.
    public static let toolBarWidestSlotWidth: CGFloat = 68

    /// The width the floating bar may use inside a canvas of this width: the
    /// canvas less one `toolBarInset` at each end, so both rounded ends of the
    /// capsule stay inside the picture.
    public static func toolBarBudget(canvasWidth: CGFloat) -> CGFloat {
        max(0, canvasWidth - 2 * toolBarInset)
    }

    /// How many leading tools the bar should show, given how wide it currently
    /// measures and how much room it has. The rest collapse into the overflow
    /// menu.
    ///
    /// This has to cross the whole gap in ONE step. The previous version moved
    /// by a single tool per layout pass and relied on the new measurement being
    /// fed back for the next pass; SwiftUI stops feeding a measurement back into
    /// the state that caused it after a couple of passes, so on a 435pt canvas
    /// the bar got two tools narrower and then simply stopped, 900pt of bar in a
    /// 435pt picture. Sizing the step from the actual overflow converges before
    /// the feedback runs out.
    ///
    /// Growing back stays deliberately conservative: it only happens when there
    /// is at least a full slot of slack, so the count cannot flip between two
    /// values every frame.
    public static func fittedToolCount(current: Int, maximum: Int,
                                       contentWidth: CGFloat,
                                       budget: CGFloat) -> Int {
        guard budget > 0, contentWidth > 0 else { return current }
        if contentWidth > budget {
            let over = contentWidth - budget
            let drop = max(1, Int((over / toolBarSlotWidth).rounded(.up)))
            return max(0, current - drop)
        }
        let slack = budget - contentWidth
        guard current < maximum, slack >= toolBarWidestSlotWidth else { return current }
        return min(maximum, current + Int(slack / toolBarWidestSlotWidth))
    }

    /// The narrowest canvas that still gets the zoom slider in the tool bar.
    ///
    /// The slider is 110pt of a bar that also has to hold the tools, and it is
    /// the one control in the bar with full keyboard and trackpad equivalents
    /// (⌘0, ⌘1, pinch, and the percentage menu that stays). So on a cramped
    /// canvas it is what gives way first, and the tools keep the room.
    public static let zoomSliderMinCanvasWidth: CGFloat = 620

    /// Whether the tool bar's zoom capsule shows its slider at this canvas width.
    public static func showsZoomSlider(canvasWidth: CGFloat) -> Bool {
        canvasWidth >= zoomSliderMinCanvasWidth
    }

    /// How long the zoom percentage waits, after a click, to see whether a
    /// second one is coming — which is how double clicking it can mean "back
    /// to a hundred percent" while a single click still opens the stop menu.
    ///
    /// The wait is unavoidable: a menu opens on the press and then owns every
    /// event until it closes, so the second click of a double click would land
    /// inside the menu rather than on the number. The only way to tell the two
    /// apart is to let the first click sit for a moment.
    ///
    /// So the number is capped. The system's own interval is half a second by
    /// default, and half a second of nothing after clicking reads as a control
    /// that did not work; a quarter of a second reads as the menu opening.
    /// Someone who has set a FASTER double click gets their own shorter wait,
    /// since waiting longer than their machine would ever call a double click
    /// buys nothing.
    public static let zoomReadoutDoubleClickCap: CGFloat = 0.25

    public static func zoomReadoutDoubleClickWindow(systemInterval: Double) -> Double {
        max(0, min(systemInterval, Double(zoomReadoutDoubleClickCap)))
    }

    /// The narrowest canvas on which the active tool's options still lay
    /// themselves out along the tool bar.
    ///
    /// The Magic Wand's Tolerance label, slider and readout are 176pt of bar,
    /// and unlike a tool they are not something the overflow loop can shed: on
    /// a 435pt canvas the bar had already dropped every tool it has and still
    /// measured 473pt against a 403pt budget, so 35pt of capsule hung off each
    /// end of the picture and clicks near either edge landed on a control that
    /// was only half drawn.
    ///
    /// Below this width the options collapse to one small chip that shows the
    /// live value and opens the full control. Squeezing the slider instead was
    /// measured and rejected: the only variant that fit left a 44pt track for a
    /// 0 to 128 range, roughly three tolerance steps per point, with 6pt to
    /// spare. The chip costs 69pt and brings the bar to 366pt, leaving 37pt —
    /// deliberately less than one `toolBarWidestSlotWidth`, so freeing the room
    /// cannot tempt the fit loop into putting a tool back and starting the
    /// overflow over again.
    ///
    /// The threshold is set so the budget at it covers that whole 473pt bar.
    public static let toolOptionsMinCanvasWidth: CGFloat = 520

    /// Whether the active tool's options lay out in full at this canvas width.
    public static func showsFullToolOptions(canvasWidth: CGFloat) -> Bool {
        canvasWidth >= toolOptionsMinCanvasWidth
    }

    /// The narrowest canvas that still gets the grid's own chip in the tool
    /// bar — the glass capsule that appears beside the zoom while the grid is
    /// showing, reads its spacing, and opens every grid setting.
    ///
    /// It shares the zoom slider's threshold on purpose. Both are the same kind
    /// of thing: chrome for how the canvas is being LOOKED at, with a full
    /// keyboard and menu equivalent behind it (⌘0 and ⌘1 for the zoom, the View
    /// menu's Show Grid and Grid Settings for the grid). So they are the first
    /// two things the bar sheds, and they go together rather than one at a
    /// time. Below this width the grid is still switched on and tuned from the
    /// View menu, which is where a person on a 500pt canvas is reaching anyway.
    ///
    /// The arithmetic: at the threshold the budget has to cover the widest the
    /// bar ever gets with no tools inline — 473pt, measured — plus the chip,
    /// which is under 115pt with its glyph, its spacing and its chevron. The
    /// chip's number carries two spacings when the zoom has coarsened the grid
    /// ("4 → 32 pt"), and 56pt of fixed, monospaced digits is what that costs:
    /// at the 620pt threshold the budget is 588 and the bar with the chip on it
    /// is 587.
    public static let gridChipMinCanvasWidth: CGFloat = zoomSliderMinCanvasWidth

    /// Whether the grid has anything at all in the tool bar at this canvas
    /// width. With the grid off that is one icon; see `gridChipParts`.
    public static func showsGridChip(canvasWidth: CGFloat) -> Bool {
        canvasWidth >= gridChipMinCanvasWidth
    }

    /// One of the things the grid's capsule in the tool bar can carry.
    public enum GridChipPart: String, Sendable, CaseIterable {
        /// The grid's own icon. A DOOR, not a switch: it opens the settings,
        /// where the switch that draws the grid is the first row. Always there
        /// when the capsule is there at all.
        case settings
        /// The button reading the cell the grid works to, with the sizes
        /// behind it.
        case cell
        /// The gear that takes the canvas over to place the zero point and pin
        /// guides. It brings its own divider with it.
        case adjust
    }

    /// What the grid's capsule carries right now.
    ///
    /// The rule is the one thing the whole capsule turns on: **a grid that is
    /// not drawn takes one icon of the bar and no more.** The cell and the gear
    /// only ever act on lines that are on the picture, so with the grid off
    /// they are two controls asking for room on the scarcest strip in the app
    /// to do nothing. They come back the moment the grid does.
    ///
    /// The icon stays either way, because with the grid off it is the only
    /// thing left saying the grid exists, and pressing it is how you get to the
    /// switch.
    public static func gridChipParts(canvasWidth: CGFloat,
                                     isGridVisible: Bool) -> [GridChipPart] {
        guard showsGridChip(canvasWidth: canvasWidth) else { return [] }
        return isGridVisible ? [.settings, .cell, .adjust] : [.settings]
    }

    /// What the grid's settings come out of on a canvas this wide.
    public enum GridSettingsAnchor: String, Sendable, Equatable, CaseIterable {
        /// The grid's own icon in the tool bar, which is where the settings
        /// belong: they point at the thing that opened them.
        case gridChip
        /// The floating tool bar itself. On a canvas too narrow for the grid to
        /// have a chip there is no icon to point at, so the settings rise out
        /// of the bar as a whole instead.
        case toolBar
    }

    /// Where the grid's settings open from, whichever door was used.
    ///
    /// They used to open from the chip and from nowhere else, so on a canvas
    /// that had shed the chip the View menu's Grid Settings row raised a flag
    /// that no surface in the app was reading: the row did nothing, and the
    /// flag stayed up, so widening the window later could present the settings
    /// unbidden. Below the threshold they come out of the bar itself now — the
    /// same popover, the same controls, out of the same strip of the window,
    /// just without an icon under the arrow.
    ///
    /// One width, one answer: the app builds the settings once, at the anchor
    /// this names, so the two can never both be up on the one flag.
    public static func gridSettingsAnchor(canvasWidth: CGFloat) -> GridSettingsAnchor {
        showsGridChip(canvasWidth: canvasWidth) ? .gridChip : .toolBar
    }

    /// The narrowest canvas on which the CROP tool's options still lay
    /// themselves out along the tool bar.
    ///
    /// Crop needs its own threshold because its options are the widest in the
    /// bar: four aspect chips plus a tick and a cross are 231pt, against the
    /// wand's 176pt. Measured at a 435pt canvas with the bar already pulled
    /// back to zero inline tools, the crop bar is 505pt against a 403pt
    /// budget — 51pt of capsule off each end of the picture, where a click
    /// near either edge lands on a control that is only half drawn.
    ///
    /// 505pt does not fit at the wand's 520 threshold either (the budget there
    /// is 488), which is why this is a separate number and not a shared one.
    /// The threshold is set so the budget at it covers the whole 505pt bar
    /// with a little to spare, and so the slack it leaves stays under one
    /// `toolBarWidestSlotWidth` — otherwise the fit loop would put a tool back,
    /// push the bar out again, and flip forever.
    ///
    /// Below this width the four locks collapse to one chip showing the live
    /// lock, which opens the same four in a popover. The tick and the cross
    /// stay in the bar: at 392pt the compacted bar has 11pt to spare with them
    /// still there, and they are the two things you reach for to finish a crop.
    public static let cropOptionsMinCanvasWidth: CGFloat = 545

    /// Whether the crop tool's aspect locks lay out in full at this canvas width.
    public static func showsFullCropOptions(canvasWidth: CGFloat) -> Bool {
        canvasWidth >= cropOptionsMinCanvasWidth
    }

    // MARK: Inspector auto-collapse

    /// Below this window width the docked inspector hides itself so the canvas
    /// and toolbar stay usable (Finder/Photos-style). At or above it, the panel
    /// follows the user's own show/hide preference.
    ///
    /// This is NOT what keeps the tool bar inside the canvas. It used to claim
    /// that, and a hit-test sweep of the running app disproved it: at a 700pt
    /// window the panel stays, the canvas is 435pt, and the bar has to fit
    /// itself. `fittedToolCount` and `showsZoomSlider` do that job.
    public static let inspectorAutoCollapseWidth: CGFloat = 680

    /// Whether the docked inspector should auto-collapse at this window width.
    public static func shouldAutoCollapseInspector(windowWidth: CGFloat) -> Bool {
        windowWidth < inspectorAutoCollapseWidth
    }
}
