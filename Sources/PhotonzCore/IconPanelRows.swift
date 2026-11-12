import CoreGraphics
import Foundation

/// Which panel rows a pick in an icon has any use for.
///
/// The page layout rows (Arrangement, Hug and Fixed, Padding, how a layer
/// follows its screen when the screen is resized, and a screen's columns) are
/// for designing screens. In an icon, drawn on a 24 unit grid with keylines,
/// none of them change the icon, and they pushed its own rows (Motion among
/// them) down the panel. So the panel leaves them out when everything picked
/// is drawn in an icon: on a picture made as an icon, or inside an icon frame.
extension PhotonzDocument {

    /// Whether every one of these layers is drawn in an icon, by the rule the
    /// keylines, the snapping and the previews already follow
    /// (`iconFrameID(containing:)`): inside an icon frame (the frame itself
    /// included), or on a canvas made as an icon outside any other frame.
    ///
    /// False with nothing picked, and false when one picked layer is outside
    /// any icon: that one still has a page to be laid out on.
    public func isAllDrawnInAnIcon(_ ids: [UUID]) -> Bool {
        !ids.isEmpty && ids.allSatisfy { iconFrameID(containing: $0) != nil }
    }
}
