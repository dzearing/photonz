import CoreGraphics
import Foundation
import PhotonzCore

/// Works out what a picture export will weigh, by encoding it.
///
/// There is no formula worth trusting here. A screenshot of flat panels and a
/// photograph of leaves, at the same quality and the same size, differ by an
/// order of magnitude, so the only honest number is the one the encoder
/// produces. That makes weighing expensive, and it happens while somebody is
/// dragging a slider, so this does two things about the cost:
///
/// - it is an actor, so the work is off the main actor and the sheet keeps
///   drawing while a number is being worked out;
/// - it keeps the render, because moving the quality changes the encoding and
///   not one pixel of what is being encoded. The first answer costs a render
///   plus an encode; every stop after it costs an encode.
///
/// The kept render is keyed by everything it depends on — which frame, and at
/// what scale — and assumes the document itself does not change underneath it.
/// The Export sheet is the caller, and nothing can edit a document while that
/// sheet is up. Anything else that wants a number makes its own sizer, whose
/// life is the life of the question.
public actor ExportSizer {

    private struct Render: Hashable {
        let frameID: UUID?
        let scale: CGFloat
    }

    /// A render plus everything that turns it into a file.
    private struct Encoding: Hashable {
        let render: Render
        let format: ImageCodec.Format
        let quality: Double
    }

    private let renderer: DocumentRenderer
    private let store: ImageStore
    /// The last render, and what it was of.
    ///
    /// One, not a collection. A 12 megapixel document at 2x is a 48 megapixel
    /// bitmap, about 190 MB, and keeping one per scale would hold a quarter of
    /// a gigabyte for the life of a sheet to save a render somebody makes once.
    /// Dragging the quality is the case that has to be fast, and that never
    /// changes the key at all.
    private var kept: (of: Render, picture: CGImage)?

    /// The last file made, and what it was made of.
    ///
    /// The point of keeping it is the moment after: the Export sheet asks what
    /// the picture weighs, a person reads the number and presses Export, and
    /// the answer to "write that file" is a file that was made a second ago.
    /// Without this the whole encode runs again, which on a lossless WebP of a
    /// big document is seconds of waiting for bytes we already had.
    private var encoded: (of: Encoding, data: Data)?

    public init(renderer: DocumentRenderer, store: ImageStore) {
        self.renderer = renderer
        self.store = store
    }

    /// Exactly how many bytes this document makes as `format`, at this quality
    /// and scale. Nil when there is nothing to render.
    ///
    /// Not an estimate: this is the size of the file that `exportComposite`
    /// writes for the same answers, because it is the same render and the same
    /// encoder given the same numbers.
    public func byteCount(of document: PhotonzDocument, frameID: UUID?, scale: CGFloat,
                          format: ImageCodec.Format, quality: Double) -> Int? {
        data(of: document, frameID: frameID, scale: scale, format: format, quality: quality)?.count
    }

    /// The bytes themselves, for anything that wants to write the very file the
    /// number came from — which is how a walk proves the number was true.
    public func data(of document: PhotonzDocument, frameID: UUID?, scale: CGFloat,
                     format: ImageCodec.Format, quality: Double) -> Data? {
        let key = Encoding(render: Render(frameID: frameID, scale: scale),
                           format: format, quality: quality)
        if let encoded, encoded.of == key { return encoded.data }
        guard let image = picture(of: document, frameID: frameID, scale: scale),
              let data = ImageCodec.encode(image, format: format, quality: quality) else {
            return nil
        }
        encoded = (key, data)
        return data
    }

    /// Throws away what has been kept, for a caller whose document changed.
    public func forget() {
        kept = nil
        encoded = nil
    }

    private func picture(of document: PhotonzDocument, frameID: UUID?, scale: CGFloat) -> CGImage? {
        let key = Render(frameID: frameID, scale: scale)
        if let kept, kept.of == key { return kept.picture }
        // The same scoping Export itself uses, so what gets weighed and what
        // gets saved can never be two different pictures.
        let target = document.exportTarget(frameID: frameID)
        guard let image = renderer.render(target, store: store, scale: scale) else { return nil }
        kept = (key, image)
        return image
    }
}
