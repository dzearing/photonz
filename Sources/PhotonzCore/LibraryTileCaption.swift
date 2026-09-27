import CoreGraphics

/// The quiet second line under a Library card's name (`video.html`,
/// `.libtile .mt`): a few characters that say what the thing IS, where the
/// name says which one it is. A recording's length and a component's own
/// detail come from their items; the rest are here.
public enum LibraryTileCaption {
    /// A picture on the Media shelf: its size in pixels, the way the mock's
    /// image pages print "2560 × 1440".
    public static func pictureSize(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }

    /// The three kinds of style share one shelf, so each says which it is.
    public static let colorStyle = "paint"
    public static let textStyle = "type"
    public static let effectStyle = "effect"
}
