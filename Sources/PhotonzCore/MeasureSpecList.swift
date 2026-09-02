import CoreGraphics
import Foundation

/// The Measurements panel's row model and the "Copy as spec list" text
/// (`next-measure-panel`, §6–7 of `docs/design/next-measure.md`).
///
/// Rows are a **filtered view of the layer stack** — top-most first, exactly the
/// order the panel lists — and the spec list is the deterministic, copyable text
/// form of the visible ones. The format is pinned by `MeasureSpecListTests`;
/// change it there first.
public enum MeasureSpecList {

    /// The document's measure layers in panel order: top-most first. Hidden
    /// ones stay in (the panel shows them with the eye off); text export
    /// filters to visible itself.
    public static func measureLayers(in document: PhotonzDocument) -> [Layer] {
        document.layers.reversed().filter { $0.measure != nil }
    }

    /// The automatic row name (decision D3): what the measurement is, worded by
    /// axis and role — "Width"/"Height" for sizes, "Gap" for spacing. A guide
    /// says which edges it judged and how many: "Left edges, 4 items", or
    /// "Vertical edges, 4 items" when the scan could not tell which side its
    /// elements sit on. The mock's "Left edge alignment, 4 items" was measured
    /// at 162pt in the row's font against about 149pt of room at the panel's
    /// default width: it truncated and lost the count, the one thing it was
    /// there to carry. "Alignment" is already said three times over — by the
    /// dashed swatch, by the verdict beside the name, and by the spec line's
    /// role word. The value (the verdict, for a guide) is shown beside the
    /// name, not inside it.
    public static func derivedName(for content: MeasureContent) -> String {
        if let check = content.alignment {
            let edges: String
            if let edge = content.alignedEdge {
                edges = "\(edge.word) edges"
            } else {
                edges = content.mode == .vertical ? "Vertical edges" : "Horizontal edges"
            }
            return "\(edges), \(countPhrase(check.items.count))"
        }
        switch content.role {
        case .spacing: return "Gap"
        case .size: return content.mode == .horizontal ? "Width" : "Height"
        }
    }

    /// "no items" / "1 item" / "N items".
    public static func countPhrase(_ count: Int) -> String {
        switch count {
        case 0: "no items"
        case 1: "1 item"
        default: "\(count) items"
        }
    }

    /// The name a row (and the spec list) shows: a custom name survives a
    /// rename; the builder's stock names mean "not renamed", so those derive.
    public static func displayName(for layer: Layer) -> String {
        guard let content = layer.measure else { return layer.name }
        let stock = [MeasureBuilder.defaultName, MeasureBuilder.defaultAlignmentName, ""]
        return stock.contains(layer.name) ? derivedName(for: content) : layer.name
    }

    /// The role word a spec line carries in parentheses.
    private static func roleWord(for content: MeasureContent) -> String {
        content.alignment != nil ? "alignment" : content.role.rawValue
    }

    /// Plain-text spec list: a header line `<name> · <W> × <H> px`, then one
    /// line per **visible** measurement in panel order:
    /// `- <name>: <value> (<role>)`.
    public static func render(document: PhotonzDocument, name: String) -> String {
        let header = "\(name) · \(Int(document.canvasSize.width.rounded())) × " +
            "\(Int(document.canvasSize.height.rounded())) px"
        let lines = measureLayers(in: document)
            .filter(\.isVisible)
            .compactMap { layer -> String? in
                guard let content = layer.measure else { return nil }
                let value = content.label(pixelScale: document.pixelScale)
                return "- \(displayName(for: layer)): \(value) (\(roleWord(for: content)))"
            }
        return ([header] + lines).joined(separator: "\n")
    }
}
