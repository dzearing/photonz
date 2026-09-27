import CoreGraphics

/// One panel row, the way the mocks draw every one of them (`inspector.css`
/// `.irow`): a short label, small and faint, in a fixed left column, and the
/// control beside it starting on the same line as every other row's control.
///
/// Until 2026-09-27 the panel spoke two ways at once in a video document: the
/// video sections (Time, Sound, Captions) used this row while the older ones
/// (Appearance, Effects, Layout, Text) put a bigger label over a full width
/// control, so one panel looked like two. These are the numbers both halves
/// now share.
public enum PanelRowLayout {
    /// The label column (`--rl-w`, 76px).
    public static let labelColumn: CGFloat = 76
    /// Between the label column and the control (`--s3`).
    public static let labelGap: CGFloat = 12
    /// The label's type size (`.irow>.rl`, 10.5px). Its colour is the faint
    /// tone, which lives with the app's palette.
    public static let labelSize: CGFloat = 10.5

    /// Where every row's control begins, measured from the row's own start.
    public static var controlLeading: CGFloat { labelColumn + labelGap }

    /// What is left for the control in a row this wide.
    public static func controlWidth(rowWidth: CGFloat) -> CGFloat {
        max(0, rowWidth - controlLeading)
    }

    /// Whether a control that needs `controlMinimum` fits beside its label in
    /// a row this wide. When it does not, the row puts the control on its own
    /// line under the label rather than cutting it: a narrowed dock, or a
    /// setting stepped in under the effect it belongs to.
    public static func sitsBeside(controlMinimum: CGFloat, rowWidth: CGFloat) -> Bool {
        controlMinimum <= controlWidth(rowWidth: rowWidth)
    }
}
