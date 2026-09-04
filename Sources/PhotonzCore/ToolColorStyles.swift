import Foundation

/// Handing the saved colour a tool is holding to the shape it just drew.
///
/// What a tool holds is a preference: it survives launches and it does not
/// belong to any one document, the same way thickness and corner radius do
/// not. A saved colour, on the other hand, lives INSIDE a document. So the
/// tool remembers two things side by side — the name, and the flat paint that
/// name stood for — and the document has the last word every time a shape is
/// drawn.
///
/// That is what keeps the promise honest in the three places it could break:
/// a document that has never heard of the name simply gets the paint; a name
/// that has been repainted since gives the shape what it is NOW rather than a
/// stale copy; and a name that has since been told it is only for outlines is
/// not quietly poured into a box.
public extension PhotonzDocument {

    /// A freshly drawn shape wearing whatever saved colours its tool is
    /// holding. Anything the tool holds no name for is left exactly as the
    /// tool's own remembered paint drew it.
    func wearingArmedColorStyles(_ layer: Layer, styles: AnnotationStyles) -> Layer {
        guard let shape = layer.annotation?.shape else { return layer }
        var worn = layer
        for slot in worn.colorSlots {
            guard let id = styles.colorStyleID(forShape: shape, slot: slot),
                  let style = colorStyle(id: id),
                  // Only where this saved colour is still offered, so a colour
                  // since reserved for outlines does not turn up inside a box.
                  colorStyles(for: slot).contains(where: { $0.id == id }),
                  // ...and only where there is already a colour to replace: a
                  // name must never switch on an inside the tool draws without.
                  worn.paint(for: slot) != nil
            else { continue }
            worn.setPaint(style.paint(for: slot), for: slot)
            worn.bindColorStyle(id, for: slot)
        }
        return worn
    }
}
