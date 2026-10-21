import CoreGraphics
import Foundation

/// What one Border goes round: the thing the layer draws, or the box it sits
/// in.
///
/// On a LABEL the thing is its letters. Words over a screenshot want a line
/// round each letter, so they stay readable whatever is behind them, and that
/// is what a border on a label has always drawn here (and what a Stroke on a
/// text layer draws in Photoshop). But a bordered label (a plain rectangle
/// round the whole thing) is an ordinary thing to want too, and after the
/// Outline row left Appearance there was no way left to ask for one (reported
/// by the user, 2026-09-08, `OutlineRetirement.swift`).
///
/// On anything else with a silhouette of its own (a path, an oval, an arrow, a
/// line, a group, a cut-out picture) the thing is that silhouette, the way
/// Photoshop's Stroke runs round a layer's pixels (`ShapeOutline.swift`). It
/// used to be the box whatever this said, and a border added to a drawn package
/// came out as a rectangle round it: "borders are borders, not always boxes"
/// (the user, 2026-10-20).
///
/// So the choice sits on the border itself rather than on the layer: a border
/// is countable, so a layer can wear a fat pale halo round its shape AND a thin
/// dark box round its frame, as two rows with a grip between them, and each
/// row says which of the two it is. A layer that is only a box (a rectangle, a
/// screenshot, a frame) has nothing else to follow, so its rings follow the box
/// whatever this says and the panel never asks (`Layer.shapeToFollow`).
public enum BorderFollows: String, CaseIterable, Hashable, Codable, Sendable {
    /// Round the thing itself: a label's letters, baked into the words, or
    /// anything else's outline. Saved as "letters", the word it was written
    /// under before a shape could be followed, so every file opens as it was.
    case shape = "letters"
    /// Round the box the layer sits in.
    case box

    /// What the picker calls it on a layer with `kind` to follow.
    public func title(on kind: ShapeToFollow) -> String {
        switch self {
        case .shape: return kind == .letters ? "Letters" : "Shape"
        case .box: return "Box"
        }
    }

    /// One line saying what picking it does, for the control's own help.
    public func summary(on kind: ShapeToFollow) -> String {
        switch (self, kind) {
        case (.shape, .letters): return "Draws round each letter, so words stay readable over anything"
        case (.shape, _): return "Draws round the outline of what the layer draws"
        case (.box, .letters): return "Draws round the label's frame"
        case (.box, _): return "Draws round the layer's box"
        }
    }
}

extension Layer {

    /// Whether this layer has letters for a ring to follow. Only a label does.
    public var hasLetters: Bool {
        if case .text = content { return true }
        return false
    }

    /// The rings baked round this layer's LETTERS, nearest the eye first.
    ///
    /// Empty on anything that is not a label, so nothing else has to know that
    /// a border can be drawn two ways.
    public var letterBorders: [BorderEffect] {
        guard hasLetters else { return [] }
        return style.paintedBorders.filter { $0.follows == .shape }
    }

    /// The rings drawn round this layer's box or its outline, nearest the eye
    /// first: every painted border on everything except a label, and on a
    /// label the ones that were asked to follow its frame. Which of the two
    /// each one goes round is its own `follows`, read where it is drawn.
    public var ringedBorders: [BorderEffect] {
        guard hasLetters else { return style.paintedBorders }
        return style.paintedBorders.filter { $0.follows == .box }
    }
}
