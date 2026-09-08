import CoreGraphics
import Foundation

/// The marquee as one undoable value: the outline itself, plus whether it
/// means pixels or layers.
///
/// A selection is editor state — it is never saved with the document — but it
/// is something a person spends time placing, so it belongs in the same undo
/// stack the picture uses (`History`). Both halves travel together because
/// they are one thing on screen: the same outline drawn by the wand erases
/// pixels, and drawn by the arrow tool picks layers, so putting back the
/// outline without putting back its meaning would hand back a marquee that
/// does something else.
public struct SelectionSnapshot: Equatable, Sendable {
    /// The outline, or nil for no selection.
    public var region: SelectionRegion?
    /// True when the outline was made by a region tool (rect, ellipse, wand):
    /// pixel semantics rather than the arrow tool's layer band.
    public var targetsPixels: Bool

    public init(region: SelectionRegion? = nil, targetsPixels: Bool = false) {
        self.region = region
        self.targetsPixels = targetsPixels
    }
}
