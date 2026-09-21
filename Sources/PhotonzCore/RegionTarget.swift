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

    /// The layer a region op is ABOUT, sliceable or not: the one a refusal has
    /// to name, and the only candidate `id` will consider.
    ///
    /// One picked layer is the whole answer, wherever the marquee happens to
    /// be. SEVERAL picked layers are not: the band has to say which, and it
    /// does that by being over exactly one of them. Over two it says nothing,
    /// and over none it says nothing either.
    public static func subject(picked: UUID?, multi: Set<UUID>, region: CGRect,
                               in document: PhotonzDocument) -> UUID? {
        if let picked, document.layer(id: picked) != nil { return picked }
        let over = document.layers.filter { multi.contains($0.id) && $0.frame.intersects(region) }
        return over.count == 1 ? over[0].id : nil
    }

    /// The layer a region op bakes into, or nil when there is nothing it can
    /// honestly act on.
    ///
    /// `picked` is the selected layer and `multi` the rest of a several-row
    /// pick; `hit` is the layer under the pointer for the gestures that have
    /// one (the bucket), and nil for the keyboard. `region` is the marquee's
    /// bounds, used to pick one picked layer out of several and to find a
    /// Background the marquee actually reaches.
    ///
    /// A several-row pick used to read here as NO pick at all, so the op fell
    /// past both the rows and the pointer and landed on the locked Background,
    /// which filled itself with the background colour. Over a white canvas
    /// that is a change nobody can see and nobody asked for: ⌫ over a picture
    /// you had picked did nothing visible and said nothing either
    /// (`turn-two-shapes-into-pictures-walk`, 2026-09-20). So the Background
    /// now answers only when the pick is genuinely empty.
    public static func id(picked: UUID?, multi: Set<UUID> = [], hit: UUID?, region: CGRect,
                          in document: PhotonzDocument) -> UUID? {
        if let subject = subject(picked: picked, multi: multi, region: region, in: document),
           let layer = document.layer(id: subject) {
            return canSlice(layer) ? subject : nil
        }
        // Something IS picked and the band could not choose between them:
        // a hole in a layer nobody chose is worse than nothing happening. A
        // pick naming layers this document does not have is no pick at all.
        let isPicked = { (id: UUID) in document.layer(id: id) != nil }
        guard !(picked.map(isPicked) ?? false), !multi.contains(where: isPicked) else { return nil }
        if let hit, let layer = document.layer(id: hit), canSlice(layer) { return hit }
        return document.layers.first {
            $0.isLocked && canSlice($0) && $0.frame.intersects(region)
        }?.id
    }
}
