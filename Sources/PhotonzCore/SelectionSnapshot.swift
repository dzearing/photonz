import CoreGraphics
import Foundation

/// Which layers were picked at one moment: the one you are working on, or the
/// handful a rubber band caught.
///
/// The two never both hold something — picking one layer lets go of a band's
/// catch — but they are kept apart rather than flattened to a list because
/// that is exactly how the editor holds them, and a value that has to be
/// re-derived on the way back is a value that can come back wrong.
public struct LayerPick: Equatable, Sendable {
    /// The single layer being worked on, or nil.
    public var primary: UUID?
    /// The layers a band caught (two or more), or empty.
    public var multi: Set<UUID>

    public init(primary: UUID? = nil, multi: Set<UUID> = []) {
        self.primary = primary
        self.multi = multi
    }

    /// Everything picked, however it was picked: what a menu row would act on.
    public var ids: Set<UUID> {
        multi.isEmpty ? (primary.map { [$0] } ?? []) : multi
    }

    public var isEmpty: Bool { ids.isEmpty }
}

/// What was picked, as one undoable value: the outline itself, whether it
/// means pixels or layers, and the layers that were picked with it.
///
/// A selection is editor state — it is never saved with the document — but it
/// is something a person spends time placing, so it belongs in the same undo
/// stack the picture uses (`History`). All three parts travel together because
/// they are one thing on screen: the same outline drawn by the wand erases
/// pixels, and drawn by the arrow tool picks layers, so putting back the
/// outline without putting back its meaning would hand back a marquee that
/// does something else — and putting back the band without the layers it
/// caught hands back a picture nobody is holding, so the step after every undo
/// is a re-pick (reported three times on 2026-09-08).
///
/// The pick RIDES WITH a step and is never a step of its own: `History` writes
/// whatever is picked into every step it pushes, so a command added later
/// cannot forget, and clicking a layer row never costs a press of ⌘Z.
public struct SelectionSnapshot: Equatable, Sendable {
    /// The outline, or nil for no selection.
    public var region: SelectionRegion?
    /// True when the outline was made by a region tool (rect, ellipse, wand):
    /// pixel semantics rather than the arrow tool's layer band.
    public var targetsPixels: Bool
    /// The layers that were picked while that outline was on screen.
    public var picked: LayerPick

    public init(region: SelectionRegion? = nil, targetsPixels: Bool = false,
                picked: LayerPick = LayerPick()) {
        self.region = region
        self.targetsPixels = targetsPixels
        self.picked = picked
    }
}
