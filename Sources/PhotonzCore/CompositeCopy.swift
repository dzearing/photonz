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
///
/// A drawing also goes on as SVG (`next-export-svg`): the same file the Export
/// sheet writes for a web page, under the system's own SVG type, so a paste
/// into an app that takes shapes gets shapes and a paste into a chat still
/// gets the picture. Only a drawing earns it: a screenshot, a photograph or a
/// video is pixels however it is written, and copies exactly as before.
public enum CompositeCopy {

    /// One clipboard flavor, in the order they are declared.
    public enum Representation: Hashable, Sendable {
        case png
        case tiff
        /// The drawing as an SVG file (`public.svg-image`).
        case svg(String)
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
    /// consumers take the picture, the SVG beside them for apps that read
    /// shapes, the text last so only text-only fields fall through to it.
    public static func representations(specList: String?,
                                       svg: String? = nil) -> [Representation] {
        var reps: [Representation] = [.png, .tiff]
        if let svg { reps.append(.svg(svg)) }
        if let specList { reps.append(.text(specList)) }
        return reps
    }

    // MARK: - The drawing as SVG

    /// Whether a copy of `document` carries it as SVG too: true for a drawing,
    /// false for anything holding a picture somebody can see (a screenshot, a
    /// photograph, a collage) and for anything with time in it, which Export
    /// hands over as a film.
    ///
    /// `flatImages` is the reading `SVGExport` takes: a blank canvas is a
    /// picture that is all one colour, which the file writes as a rectangle,
    /// so it does not make a drawing a photograph. A shape Export has to
    /// write as a picture of itself (a blend, a halo) is still a drawing.
    public static func carriesSVG(_ document: PhotonzDocument,
                                  flatImages: [UUID: RGBA] = [:]) -> Bool {
        guard !document.hasTime else { return false }
        func holdsAPicture(_ layers: [Layer]) -> Bool {
            layers.contains { layer in
                guard layer.isVisible else { return false }
                switch layer.content {
                case .image:
                    return SVGExport.flatColor(of: layer, in: flatImages) == nil
                case .collage:
                    return true
                case .group(let group):
                    return holdsAPicture(group.children)
                default:
                    return false
                }
            }
        }
        return !holdsAPicture(document.layers)
    }

    /// Whether the copied SVG plays: exactly what the Export sheet writes for
    /// a web page, which is the one destination that keeps the motion.
    /// `motionOn` is whether this release exports motion at all.
    public static func svgAnimation(for document: PhotonzDocument,
                                    motionOn: Bool) -> SVGExport.Animation {
        motionOn && SVGHandoff.format(for: .webPage, in: document) == .animatedSVG
            ? .moving(cycleMS: document.motionCycleLengthMS) : .still
    }
}
