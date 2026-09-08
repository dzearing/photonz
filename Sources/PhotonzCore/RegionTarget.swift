import CoreGraphics
import Foundation

/// Which layer a region works on.
///
/// The rule in one line: **a region says WHERE, and the layer you picked says
/// WHAT.** Drawing a marquee chooses a piece of the picture; it never chooses
/// a different layer for you. So ⌫, ⌥⌫, the paint bucket, a drag of the
/// region's pixels and ⌘C all come through here and all land on the same
/// layer, which is what makes the family agree.
///
/// The two answers that are NOT the picked layer both need a pick to be
/// missing:
///
/// - the layer under the pointer, for the bucket, which is clicked AT
///   something and has nothing else to go on;
/// - the locked Background, for ⌫ with no pointer at all, since clearing to
///   the background colour is what that layer is for (Photoshop).
///
/// A picked layer that cannot be sliced takes the op NOWHERE else. Cutting a
/// hole in the picture under a rectangle you had picked is a change to a layer
/// nobody chose, and silence is better than that.
public enum RegionTarget {
    /// Whether a region op could bake into this layer: only an untransformed,
    /// uncropped image layer can be sliced, since the op writes into its
    /// bitmap and the document-to-bitmap mapping goes through the layer's
    /// frame. A shape or a piece of text would have to be turned into pixels
    /// first, which is a different decision and never a side effect of ⌫.
    public static func canSlice(_ layer: Layer) -> Bool {
        layer.imageRef != nil && layer.crop == nil && layer.transform.isIdentity
    }

    /// The layer a region op bakes into, or nil when there is nothing it can
    /// honestly act on.
    ///
    /// `picked` is the selected layer; `hit` is the layer under the pointer
    /// for the gestures that have one (the bucket), and nil for the keyboard.
    /// `region` is the marquee's bounds, used only to find a Background the
    /// marquee actually reaches.
    public static func id(picked: UUID?, hit: UUID?, region: CGRect,
                          in document: PhotonzDocument) -> UUID? {
        if let picked, let layer = document.layer(id: picked) {
            return canSlice(layer) ? picked : nil
        }
        if let hit, let layer = document.layer(id: hit), canSlice(layer) { return hit }
        return document.layers.first {
            $0.isLocked && canSlice($0) && $0.frame.intersects(region)
        }?.id
    }
}
