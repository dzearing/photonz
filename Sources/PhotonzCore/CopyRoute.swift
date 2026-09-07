import Foundation

/// What a copy puts on the clipboard.
///
/// Two commands share this list. Plain copy (⌘C) takes the layer you picked;
/// copy merged (⇧⌘C) takes every layer flattened together. A marquee crops
/// either of them.
public enum CopyPlan: Equatable, Sendable {
    /// Nothing to copy: no document is open.
    case nothing
    /// The whole picked layer, as a layer — it pastes back as a layer, keeps
    /// its own model, and carries its bitmap.
    case layer(UUID)
    /// The picked layer's pixels inside the marquee, and nothing from the
    /// layers around it.
    case layerRegion(UUID)
    /// Every layer flattened together inside the marquee, or the whole canvas
    /// when nothing is marqueed. Pastes back over the spot it came from.
    case mergedRegion
    /// The flattened picture of the whole canvas: the hand-off copy, which
    /// also carries the spec list when the document has measurements.
    case mergedImage
}

/// Which copy each key means.
///
/// The rule in one line: **copy takes what you picked, and a marquee crops
/// it**. Picking a layer and drawing a marquee used to make the marquee win,
/// so copy handed back every layer flattened together and the layer you were
/// working on was nowhere in it. The flattened copy is still one keystroke
/// away, it just needs the shift key, which is where Photoshop keeps it.
public enum CopyRoute {
    /// ⌘C.
    ///
    /// `picked` is the layer that is selected, or nil when none is.
    /// `pixelRegion` is true only for a marquee that means pixels — a rubber
    /// band thrown round a few layers is a way of picking layers, not a hole
    /// cut in the picture, so it never crops a copy.
    public static func copy(picked: UUID?, pixelRegion: Bool, hasDocument: Bool) -> CopyPlan {
        guard hasDocument else { return .nothing }
        guard let picked else { return .mergedRegion }
        return pixelRegion ? .layerRegion(picked) : .layer(picked)
    }

    /// ⇧⌘C: everything flattened together, cropped to the marquee when there
    /// is one and the whole picture when there is not.
    public static func copyMerged(pixelRegion: Bool, hasDocument: Bool) -> CopyPlan {
        guard hasDocument else { return .nothing }
        return pixelRegion ? .mergedRegion : .mergedImage
    }
}
