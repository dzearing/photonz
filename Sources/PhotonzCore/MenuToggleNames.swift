/// The name of every menu item in the app that is simply on or off.
///
/// A setting keeps ONE name and wears a checkmark when it is on. A name that
/// rewrites itself ("Show Grid" becoming "Hide Grid", "Snap to Grid" becoming
/// "Stop Snapping to Grid") is how an ACTION is written: it makes you read a
/// sentence to learn a state you could have seen at a glance, and it moves the
/// next item up or down under the pointer as the label changes length. Asked
/// for by the user on 2026-09-05 for every one of them, not just the grid.
///
/// The names kept are the ones that were already there, so nothing has to be
/// re-learned or re-found, and the two grid switches now read word for word the
/// same here as on the grid settings popover (`CanvasGridCopy.grid`,
/// `CanvasGridCopy.snap`). A row in a list is different: a bare "Show" on a
/// layer row says nothing, so those say what the row IS.
///
/// Kept flipping on purpose, because each pair is two different actions rather
/// than one setting: Play/Pause, Crop to Region/Finish Crop, and
/// `CaptureMenuNames.recording` (the first opens a picker, the second stops a
/// recording).
public enum MenuToggleNames {
    // MARK: View menu

    public static let grid = "Show Grid"
    public static let snapToGrid = "Snap to Grid"
    public static let layersPanel = "Show Layers"
    public static let library = "Show Library"

    // MARK: Layer menu

    /// The selected screen's own column layout. Deliberately not called a grid:
    /// that word belongs to the canvas-wide grid on the View menu, and the two
    /// are different things. Kept word for word the same as the checkbox at the
    /// top of the Columns section (`FrameColumnsCopy.show` says the same thing
    /// in lower case, because a menu row is Title Case and a checkbox is not).
    public static let showColumns = "Show Columns"

    // MARK: Capture menu, in both the editor's menu bar and the agent's

    public static let history = CaptureMenuNames.history

    // MARK: A row's own context menu

    public static let layerVisible = "Visible"
    public static let layerLocked = "Locked"

    /// Every on/off item in the app, so a test can hold them all to the same
    /// standard and a new one added without a name here shows up as a gap.
    public static let all: [String] = [
        grid, snapToGrid, layersPanel, library, showColumns, history,
        layerVisible, layerLocked,
    ]
}
