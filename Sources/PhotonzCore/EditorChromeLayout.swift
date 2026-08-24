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
