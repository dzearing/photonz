import Foundation

/// Handing the saved text style the text tool is holding to the block just
/// typed. The colour half of the same idea is `ToolColorStyles.swift`, and this
/// works exactly the way that one does, for the same reason.
///
/// What a tool holds is a preference: it survives launches and belongs to no
/// one document, the way the font and the size do not. A saved style, on the
/// other hand, lives INSIDE a document. So the tool remembers two things side
/// by side — the name, and the type that name stood for — and the document has
/// the last word every time a block is typed.
///
/// That keeps the promise honest in the two places it could break: a document
/// that has never heard of the name simply types in the tool's own type, and a
/// name that has been re-set since gives the block what it is NOW rather than a
/// stale copy of what it was.
public extension PhotonzDocument {

    /// What the next block of text is actually set in, when the tool is holding
    /// a name this document knows. Nil when it is holding nothing, or holding a
    /// name that came from some other document.
    func armedTextTreatment(_ styles: TextStyles) -> TextTreatment? {
        guard let id = styles.styleID else { return nil }
        return textStyle(id: id)?.treatment
    }

    /// A freshly typed block wearing the style its tool is holding: set in it,
    /// and pointing at it, so an edit to the style re-sets this block too.
    /// Anything else — a shape, or text from a tool holding nothing — comes
    /// back exactly as it went in.
    func wearingArmedTextStyle(_ layer: Layer, styles: TextStyles) -> Layer {
        guard layer.textTreatment != nil, let id = styles.styleID,
              let treatment = textStyle(id: id)?.treatment else { return layer }
        var worn = layer
        worn.setTextTreatment(treatment)
        worn.textStyleID = id
        // A text style keeps a colour of its own, so a colour style on the same
        // words would be a second name claiming one colour. The same rule
        // `bindTextStyle` follows when a style is put on by hand.
        worn.unbindColorStyle(for: .text)
        return worn
    }
}
