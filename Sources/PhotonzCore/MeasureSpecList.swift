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
        if let check = content.alignment, let edges = content.alignmentEdgesPhrase {
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

    /// One measurement's spec line: `- <name>: <value> (<role>)`. Nil for a
    /// layer that is not a measurement.
    public static func specLine(for layer: Layer, in document: PhotonzDocument) -> String? {
        guard let content = layer.measure else { return nil }
        let value = content.label(pixelScale: document.pixelScale)
        return "- \(displayName(for: layer)): \(value) (\(roleWord(for: content)))"
    }

    /// The header's size, in the unit the lines use. A 2x capture used to
    /// head its list with the canvas in device pixels (1440 × 960) above rows
    /// in logical pixels (124), two units in one list with no scale stated.
    /// The header now follows the rows: logical size plus "@2x" unless every
    /// listed measurement reads device pixels, in which case the device size.
    public static func headerSize(document: PhotonzDocument) -> String {
        let listed = measureLayers(in: document).filter(\.isVisible).compactMap(\.measure)
        let scale = document.pixelScale > 0 ? document.pixelScale : 1
        let devicePixels = !listed.isEmpty && listed.allSatisfy { $0.unit == .pixels }
        let divisor: CGFloat = devicePixels ? 1 : scale
        let w = Int((document.canvasSize.width / divisor).rounded())
        let h = Int((document.canvasSize.height / divisor).rounded())
        let suffix = (!devicePixels && scale != 1) ? " @\(Self.scaleText(scale))" : ""
        return "\(w) × \(h) px\(suffix)"
    }

    /// "2x", "1.5x".
    private static func scaleText(_ scale: CGFloat) -> String {
        scale == scale.rounded() ? "\(Int(scale))x" : "\(scale)x"
    }

    /// Plain-text spec list: a header line `<name> · <W> × <H> px[ @2x]`
    /// (`headerSize`), then one line per **visible** measurement in panel
    /// order: `- <name>: <value> (<role>)`.
    public static func render(document: PhotonzDocument, name: String) -> String {
        let header = "\(name) · \(headerSize(document: document))"
        let lines = measureLayers(in: document)
            .filter(\.isVisible)
            .compactMap { specLine(for: $0, in: document) }
        return ([header] + lines).joined(separator: "\n")
    }

    /// Copy Measurement: the spec lines of the SELECTED measurements only, in
    /// panel order, with no header (they are lines to paste into a thread, not
    /// a document). An explicit pick outranks the eye, so a hidden measurement
    /// still copies. Ids that are not measurements contribute nothing; an
    /// empty selection renders "".
    public static func render(document: PhotonzDocument, ids: Set<UUID>) -> String {
        measureLayers(in: document)
            .filter { ids.contains($0.id) }
            .compactMap { specLine(for: $0, in: document) }
            .joined(separator: "\n")
    }
}
