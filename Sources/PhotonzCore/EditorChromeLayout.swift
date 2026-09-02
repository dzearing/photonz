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
    /// The bar's own height. Measured off the running app rather than guessed:
    /// the glass capsule around its 28pt controls comes out at 48pt.
    public static let toolBarHeight: CGFloat = 48
    /// The breathing room between the bar and whatever stacks on top of it, so
    /// the two read as two surfaces rather than one sitting on the other.
    public static let toolBarStackGap: CGFloat = 12

    /// Bottom padding for anything the canvas floats at bottom center — the
    /// Measure hint, the crop's Cancel/Crop pill — so it lands ABOVE the
    /// floating tool bar instead of behind it. The bar is drawn last and wins
    /// every overlap, so an overlay that does not clear this is simply
    /// invisible: the hint chip spent its life at 14pt, fully covered.
    public static let aboveToolBar: CGFloat = toolBarInset + toolBarHeight + toolBarStackGap

    /// Where a bottom-centre notice of `noticeSize` (the Measure mode hint,
    /// the "Copied" pill) sits in a canvas of `canvasSize`: centred, its
    /// bottom edge `aboveToolBar` off the floor. Top-left origin, like every
    /// other rect the placement code takes.
    public static func bottomNoticeFrame(canvasSize: CGSize, noticeSize: CGSize) -> CGRect {
        CGRect(x: (canvasSize.width - noticeSize.width) / 2,
               y: canvasSize.height - aboveToolBar - noticeSize.height,
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
    /// measure legend) must never park behind: the notice pill's slot, then
    /// the tool bar. The pill's slot is reserved whether or not a pill is up,
    /// so the legend never has to jump when one appears for two seconds.
    public static func bottomChrome(canvasSize: CGSize, toolBarWidth: CGFloat,
                                    noticeSize: CGSize) -> [CGRect] {
        [bottomNoticeFrame(canvasSize: canvasSize, noticeSize: noticeSize),
         toolBarFrame(canvasSize: canvasSize, toolBarWidth: toolBarWidth)]
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
