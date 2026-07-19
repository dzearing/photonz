import CoreGraphics

/// Pure, testable layout policy for the editor's *chrome* — the floating tool
/// toolbar and the docked right-side inspector — as the window is resized down.
///
/// The SwiftUI shell (`EditorView`, `LayersPanel`) owns the views; this type
/// owns the *decisions* so they can be unit-tested without a running app:
///  - the window's minimum size (the floor the layout is designed against),
///  - whether the inspector should auto-collapse at a given window width.
///
/// (Toolbar overflow itself is done with SwiftUI's `ViewThatFits`, which MEASURES
/// each variant, so there is no width arithmetic here to get wrong — an earlier
/// hand-computed count under-counted the real widths and still clipped.)
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

    // MARK: Inspector auto-collapse

    /// Below this window width the docked inspector hides itself so the canvas
    /// and toolbar stay usable (Finder/Photos-style). At or above it, the panel
    /// follows the user's own show/hide preference. Chosen so that when the
    /// panel *is* shown there is always enough width left for the (possibly
    /// overflowed) toolbar to sit in the canvas without clipping.
    public static let inspectorAutoCollapseWidth: CGFloat = 680

    /// Whether the docked inspector should auto-collapse at this window width.
    public static func shouldAutoCollapseInspector(windowWidth: CGFloat) -> Bool {
        windowWidth < inspectorAutoCollapseWidth
    }
}
