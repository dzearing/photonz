import CoreGraphics
import Foundation

public extension PhotonzDocument {

    /// This document as an export set to `background` would draw it.
    ///
    /// The SVG writer can leave the canvas out by simply not writing a
    /// rectangle. A picture has no such move: it is rendered, and every layer
    /// that is visible lands in the pixels. So a PNG with nothing behind the
    /// drawing is this document with the canvas hidden — the layer stays where
    /// it is, so nothing else shifts, and what comes out is the drawing over
    /// transparency.
    ///
    /// `flatImages` says which of the document's bitmaps are one flat colour,
    /// by bitmap id (`FlatBitmap.colors` in PhotonzRender reads them). Without
    /// that there is nothing to recognise a canvas by, so the document comes
    /// back exactly as it went in — which is also what a screenshot,
    /// a photograph or a drawing with no canvas under it gets.
    ///
    /// A frame's surface is not a layer, so it is taken off the frame, which
    /// stays with everything in it.
    func drawn(with background: SVGExport.Background,
               flatImages: [UUID: RGBA]) -> PhotonzDocument {
        let gone = SVGExport.leftOut(of: self, flatImages: flatImages, background: background)
        guard gone.layerID != nil || !gone.surfaces.isEmpty else { return self }
        var copy = self
        if let canvas = gone.layerID {
            copy.updateLayer(id: canvas) { $0.isVisible = false }
        }
        for frame in gone.surfaces {
            copy.updateLayer(id: frame) { layer in
                guard var group = layer.group else { return }
                group.background = nil
                layer.content = .group(group)
            }
        }
        return copy
    }
}
