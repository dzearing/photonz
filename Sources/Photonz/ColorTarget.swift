import Foundation
import PhotonzCore

/// The colours ONE row of the inspector paints.
///
/// Nearly every row paints one: the Fill row is the fill of everything picked.
/// The Outline row paints TWO the moment a rectangle and a screenshot are
/// picked together, because a shape strokes its own path and a picture wears a
/// ring its styling draws. Nothing a person does differs between them, so it is
/// one row, one switch, one colour well and one Width — and this is the value
/// that lets one row stand for both without either colour landing on a layer it
/// has no business on.
///
/// Two kinds of reach, and the difference matters:
///
/// - **A slot on its own** means every picked layer that has that kind of
///   colour, worked out fresh each time the row is read. That is what a row
///   named after a slot has always meant, and it is what the Color section and
///   the toolbar rows still pass.
/// - **A slot with layers named** means exactly those. The parts list works out
///   who is in each colour when it builds the row, because a highlight has a
///   stroke colour too and it is the WASH the highlight is made of rather than
///   a line round anything. A row that reached by slot alone repainted it.
struct ColorTarget: Hashable {

    /// One colour the row paints, and who takes it.
    struct Part: Hashable {
        let slot: ColorSlot
        /// Nil for "every picked layer that has this kind of colour".
        let layerIDs: [UUID]?
    }

    /// At least one, in the order the row shows them.
    let parts: [Part]

    /// A row that paints one kind of colour across whatever is picked.
    init(_ slot: ColorSlot) {
        parts = [Part(slot: slot, layerIDs: nil)]
    }

    /// A row the parts list built, which already knows who wears what. Nil for
    /// a row with no colour at all — the shadow, whose colour is not one of the
    /// layer's slots and which brings its own well.
    init?(_ colors: [PartColor]) {
        guard !colors.isEmpty else { return nil }
        parts = colors.map { Part(slot: $0.slot, layerIDs: $0.layerIDs) }
    }

    /// The colour this row leads with: the one its name field, its saved
    /// colours menu and its picker are keyed on. Every slot a row holds shares
    /// a style role today (a stroke and a ring are both ink), so the menu the
    /// lead opens is the menu all of them would.
    var lead: ColorSlot { parts[0].slot }

    /// True when this row stands for two kinds of line at once.
    var isSplit: Bool { parts.count > 1 }

    /// Whether the picker offers a gradient. Only when EVERY colour the row
    /// paints can hold one: a ring round a picture takes a flat colour, so a
    /// row speaking for a ring and a stroke offers no ramp rather than one that
    /// half lands.
    var acceptsGradient: Bool { parts.allSatisfy(\.slot.acceptsGradient) }
}
