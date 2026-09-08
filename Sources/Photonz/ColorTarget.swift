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
        /// Set when the colour belongs to ONE ENTRY in the Effects list — this
        /// border's colour, the second shadow's — rather than to one of the
        /// layer's own slots. It is a place in the list, which is exactly how
        /// the row above it is addressed too.
        var effectIndex: Int?
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

    /// The Color row under ONE effect. Nil for an effect that paints no colour
    /// at all, which brings no such row rather than a blank one.
    ///
    /// This is what makes an effect's colour an ordinary colour: from here on
    /// it goes down the same well, the same saved-colours menu and the same
    /// naming field a Fill or an Outline does (reported by the user on
    /// 2026-09-07 — a border's colour was the one colour in the app that could
    /// not take a saved name).
    init?(effect row: LayerEffectRow) {
        guard let slot = row.kind.colorSlot else { return nil }
        // Every picked layer, not the row's own reach: the document already
        // skips the ones with nothing at that place in their list, and passing
        // the whole selection is what lets the row say "applies to 1 of the 2
        // selected layers" honestly.
        parts = [Part(slot: slot, layerIDs: nil, effectIndex: row.index)]
    }

    /// The colour this row leads with: the one its name field, its saved
    /// colours menu and its picker are keyed on. Every slot a row holds shares
    /// a style role today (a stroke and a ring are both ink), so the menu the
    /// lead opens is the menu all of them would.
    var lead: ColorSlot { parts[0].slot }

    /// Where in the Effects list this row's colour lives, when it is an
    /// effect's. Nil for every row that paints one of the layer's own slots.
    var effectIndex: Int? { parts.count == 1 ? parts[0].effectIndex : nil }

    /// True when this row stands for two kinds of line at once.
    var isSplit: Bool { parts.count > 1 }

    /// What the one open picker answers to, and what a scripted walk opens.
    /// Two borders on one shape are two rows, so the place in the list is part
    /// of the key or the second one would open the first one's picker.
    var key: String {
        guard let effectIndex else { return "selection.\(lead.rawValue)" }
        return "selection.effect.\(effectIndex).\(lead.rawValue)"
    }

    /// Whether the picker offers an alpha slider. A shadow carries an Opacity
    /// of its own in its settings, so a second see-through control in the
    /// picker would be two answers to one question.
    var supportsOpacity: Bool { lead != .shadow }

    /// Whether the picker offers a gradient. Only when EVERY colour the row
    /// paints can hold one: a ring round a picture takes a flat colour, so a
    /// row speaking for a ring and a stroke offers no ramp rather than one that
    /// half lands.
    var acceptsGradient: Bool { parts.allSatisfy(\.slot.acceptsGradient) }
}
