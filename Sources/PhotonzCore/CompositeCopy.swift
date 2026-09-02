import Foundation

/// What Copy Image puts on the clipboard (`next-measure-panel`, §7 of
/// `docs/design/next-measure.md`).
///
/// Handing a redline to someone used to take two copies: Copy Image for the
/// picture, then Copy as Spec List for the words. One copy now carries both:
/// the flattened picture as PNG and TIFF, and, when the document has at least
/// one visible measurement, the spec list as plain text beside them. An app
/// that understands images takes the picture; a text-only field takes the
/// list. Nothing to learn, and a document without measurements copies exactly
/// what it always did.
public enum CompositeCopy {

    /// One clipboard flavor, in the order they are declared.
    public enum Representation: Hashable, Sendable {
        case png
        case tiff
        case text(String)
    }

    /// The spec list that rides beside the picture, or nil when the document
    /// has no visible measurement: a header-only list says nothing the picture
    /// does not, and would turn a plain-text paste into a stray line.
    public static func specListText(document: PhotonzDocument, name: String) -> String? {
        guard visibleMeasurementCount(in: document) > 0 else { return nil }
        return MeasureSpecList.render(document: document, name: name)
    }

    /// How many measurements the list carries (the notice's number).
    public static func visibleMeasurementCount(in document: PhotonzDocument) -> Int {
        MeasureSpecList.measureLayers(in: document).filter(\.isVisible).count
    }

    /// The flavors in declaration order: the image types first so image-aware
    /// consumers take the picture, the text last so only text-only fields
    /// fall through to it.
    public static func representations(specList: String?) -> [Representation] {
        var reps: [Representation] = [.png, .tiff]
        if let specList { reps.append(.text(specList)) }
        return reps
    }
}
