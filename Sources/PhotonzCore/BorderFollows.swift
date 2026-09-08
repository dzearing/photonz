import CoreGraphics
import Foundation

/// What one Border round a LABEL goes round: the letters, or the box the words
/// sit in.
///
/// A border on type is not the same idea as a border on a box. Words over a
/// screenshot want a line round each letter, so they stay readable whatever is
/// behind them, and that is what a border on a label has always drawn here (and
/// what a Stroke on a text layer draws in Photoshop). But a bordered LABEL — a
/// plain rectangle round the whole thing — is an ordinary thing to want too,
/// and after the Outline row left Appearance there was no way left to ask for
/// one (reported by the user, 2026-09-08, `OutlineRetirement.swift`).
///
/// So the choice sits on the border itself rather than on the layer: a border
/// is countable, so a label can wear a fat pale halo on its letters AND a thin
/// dark box round its frame, as two rows with a grip between them, and each row
/// says which of the two it is.
///
/// Only a label has letters. Everything else — a picture, a shape, a frame, a
/// group — has a box and nothing else, so its rings follow the box whatever
/// this says and the panel never asks (`Layer.boxBorders`).
public enum BorderFollows: String, CaseIterable, Hashable, Codable, Sendable {
    /// Round each letter, baked into the words themselves.
    case letters
    /// Round the box the label sits in, drawn like every other layer's ring.
    case box

    /// What the picker calls it.
    public var title: String {
        switch self {
        case .letters: return "Letters"
        case .box: return "Box"
        }
    }

    /// One line saying what picking it does, for the control's own help.
    public var summary: String {
        switch self {
        case .letters: return "Draws round each letter, so words stay readable over anything"
        case .box: return "Draws round the label's frame, like a border on any other layer"
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
        return style.paintedBorders.filter { $0.follows == .letters }
    }

    /// The rings drawn round this layer's BOX, nearest the eye first. Every
    /// painted border on everything except a label, and on a label the ones
    /// that were asked to follow its frame.
    public var boxBorders: [BorderEffect] {
        guard hasLetters else { return style.paintedBorders }
        return style.paintedBorders.filter { $0.follows == .box }
    }
}
