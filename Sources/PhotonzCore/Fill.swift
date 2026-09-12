import CoreGraphics
import Foundation

/// The paint-bucket's per-content fill dispatch: what "fill this layer with a
/// color" means for each layer type. Pure — the app supplies a pre-registered
/// solid bitmap ref for image layers (bitmaps live outside the model).
public enum Fill {

    /// `layer` filled with `colorHex`, or nil when this content can't take a
    /// fill (zoom callouts sample the backdrop; image layers refuse without a
    /// `solidRef`). The frame never moves:
    /// - image → content becomes the solid ref (crop cleared)
    /// - rectangle/ellipse → interior `fillColorHex` (stroke untouched)
    /// - line/arrow/highlight → stroke color
    /// - text → color; measure → outline + readout (not the chip fill)
    /// - collage → backdrop color
    public static func filled(_ layer: Layer, colorHex: String, solidRef: ImageRef?) -> Layer? {
        var filled = layer
        switch layer.content {
        case .image:
            guard let solidRef else { return nil }
            filled.content = .image(solidRef)
            filled.crop = nil
        case .annotation(var annotation):
            switch annotation.shape {
            case .rectangle, .ellipse:
                annotation.fillColorHex = colorHex
            case .line, .arrow, .highlight:
                // The WHOLE thing, head and all. The bucket means "make this
                // that colour", which is a different gesture from the Line row
                // in Appearance: that one sets the line and leaves the head
                // where it was, and this one is somebody pointing at the shape.
                // The label keeps its own colours, exactly as a measurement's
                // chip does.
                annotation.colorHex = colorHex
                annotation.headColorHex = colorHex
            }
            filled.content = .annotation(annotation)
        case .text(var text):
            text.colorHex = colorHex
            filled.content = .text(text)
        case .measure(var measure):
            // A measure's "color" is its ink: the caliper, the ring round its
            // chip, and the readout. The bucket means "make this thing this
            // colour", which is a different gesture from the Caliper row in
            // Appearance: that one sets the caliper and leaves the chip's ring
            // where it was. The chip's FILL is left alone either way, the same
            // as an arrow's label pill.
            measure.strokeColorHex = colorHex
            measure.chipBorderColorHex = colorHex
            measure.textColorHex = colorHex
            filled.content = .measure(measure)
        case .collage(var collage):
            collage.backdropColorHex = colorHex
            filled.content = .collage(collage)
        // Neither of these has paint of its own: both draw the picture
        // underneath, so there is nothing for a bucket to fill.
        case .zoomCallout, .lens:
            return nil
        // A group has no paint of its own; filling one would mean deciding for
        // every layer inside it, which the bucket does not get to do.
        case .group:
            return nil
        }
        return filled
    }
}
