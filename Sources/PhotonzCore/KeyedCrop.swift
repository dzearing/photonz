import CoreGraphics
import Foundation

// A keyed crop (task `keyframe-anything-and-see-and-shape-the-keys-on`).
//
// Premiere's Crop effect, said in this app's model: four edges, Left, Top,
// Right and Bottom, each a percent of the picture cut away from that side and
// each keyed on its own. What is kept stays exactly where it was drawn, so a
// crop animating in is a wipe, not a squash.
//
// It is the Crop tool's own two numbers moved together: the frame shrinks to
// the part kept, and the layer's `crop` (in the picture's own pixels) shrinks
// by the same share, so the kept pixels land on the same spot of the canvas
// (`Layer.cropContent`). Measured from the layer as it was DRAWN, which is
// what makes the four edges independent of each other and of the order the
// motions are applied in: a crop is innermost (`MotionProperty.nestingOrder`),
// so nothing has moved the layer before it runs.

extension Layer {

    /// True where one of the four crop edges is keyed on a picture that can be
    /// cropped at all.
    public var hasKeyedCrop: Bool {
        supportsContentCrop && (motions ?? []).contains { $0.property.isCrop && $0.isOn }
    }

    /// This layer with `edge` cut in to `percent` of the picture as drawn
    /// (`authored`). The edge opposite never moves, and at least a point of
    /// picture is always left, however far two opposite edges are pulled.
    func croppedByKey(_ edge: MotionProperty, percent: Double, authored: Layer) -> Layer {
        guard edge.isCrop, supportsContentCrop, case let .image(ref) = authored.content else { return self }
        let box = authored.frame.standardized
        let pixels = authored.crop ?? CGRect(origin: .zero, size: ref.pixelSize)
        guard box.width > 0, box.height > 0, pixels.width > 0, pixels.height > 0 else { return self }
        let share = CGFloat(min(max(percent, 0), 100) / 100)
        let least: CGFloat = 1

        var frame = self.frame.standardized
        var cut = self.crop ?? pixels
        // How many of the picture's pixels one point of the box holds, which a
        // crop never changes: it takes the same share off both.
        let across = pixels.width / box.width
        let down = pixels.height / box.height

        switch edge {
        case .cropLeft:
            let minX = min(box.minX + box.width * share, frame.maxX - least)
            let pixelMinX = pixels.minX + (minX - box.minX) * across
            cut.size.width = cut.maxX - pixelMinX
            cut.origin.x = pixelMinX
            frame.size.width = frame.maxX - minX
            frame.origin.x = minX
        case .cropRight:
            let maxX = max(box.maxX - box.width * share, frame.minX + least)
            cut.size.width = pixels.minX + (maxX - box.minX) * across - cut.minX
            frame.size.width = maxX - frame.minX
        case .cropTop:
            let minY = min(box.minY + box.height * share, frame.maxY - least)
            let pixelMinY = pixels.minY + (minY - box.minY) * down
            cut.size.height = cut.maxY - pixelMinY
            cut.origin.y = pixelMinY
            frame.size.height = frame.maxY - minY
            frame.origin.y = minY
        case .cropBottom:
            let maxY = max(box.maxY - box.height * share, frame.minY + least)
            cut.size.height = pixels.minY + (maxY - box.minY) * down - cut.minY
            frame.size.height = maxY - frame.minY
        default:
            return self
        }
        var out = self
        out.frame = frame
        out.crop = cut
        return out
    }
}
