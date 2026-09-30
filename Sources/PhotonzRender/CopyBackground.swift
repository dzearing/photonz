import CoreGraphics
import Foundation
import PhotonzCore

public extension FlatBitmap {

    /// The flat colour of the one bitmap that could be a canvas: the bottom
    /// layer anyone can see, keyed by the id of the bitmap it draws, or empty
    /// where that layer is not a flat picture.
    ///
    /// `SVGExport.backdrop` only ever looks at that layer, so this is all a
    /// copy needs to recognise a blank canvas. `colors(in:store:)` reads every
    /// picture in the document, which Export can afford and Copy, pressed all
    /// day, should not.
    static func canvasColor(in document: PhotonzDocument, store: ImageStore) -> [UUID: RGBA] {
        guard let bottom = document.layers.first(where: \.isVisible),
              case .image(let ref) = bottom.content, bottom.crop == nil,
              let bitmap = store.image(for: ref),
              let colour = color(of: bitmap) else { return [:] }
        return [ref.id: colour]
    }
}

public extension PhotonzDocument {

    /// This document as a copy set to `background` puts it on the clipboard.
    ///
    /// The same answer Export gives (`drawn(with:flatImages:)`): with the
    /// canvas left out, a drawing made on a blank canvas lands on nothing, and
    /// a screenshot, a photograph or a drawing with no canvas under it comes
    /// back exactly as it went in.
    func copied(with background: SVGExport.Background, store: ImageStore) -> PhotonzDocument {
        guard background == .drop else { return self }
        return drawn(with: .drop, flatImages: FlatBitmap.canvasColor(in: self, store: store))
    }
}
