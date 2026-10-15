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

    // MARK: - Copy SVG

    /// What Copy SVG copies when asked about `layerID`: the frame it is, or
    /// the frame it lives in, on its own, else the whole drawing. The same
    /// scope the Export sheet opens on for the same pick, so the code you
    /// paste and the file you export are one file.
    public static func svgCopyTarget(in document: PhotonzDocument,
                                     around layerID: UUID?) -> PhotonzDocument {
        document.exportTarget(frameID: layerID.flatMap { document.frameID(containing: $0) })
    }

    /// The name the "Copied" notice gives what Copy SVG copied: the frame's,
    /// or nothing for the whole drawing.
    public static func svgCopyName(in document: PhotonzDocument, around layerID: UUID?) -> String {
        guard let frame = layerID.flatMap({ document.frameID(containing: $0) }) else { return "" }
        return document.layer(id: frame)?.name ?? ""
    }

    /// Copy SVG's clipboard: the code as plain text and nothing else, so a
    /// code editor, a plain text box and Safari all paste the code. Copy and
    /// Copy Merged keep the text slot for the spec list (`representations`).
    public static func svgCodeRepresentations(_ svg: String) -> [Representation] {
        [.text(svg)]
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
