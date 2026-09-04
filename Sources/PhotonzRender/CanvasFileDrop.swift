import CoreGraphics
import Foundation

/// What the canvas could do with a file being dragged over it.
///
/// A drag has to answer before the button comes up: the pointer either shows
/// the copy badge, promising something will happen, or the no-entry sign,
/// saying plainly that nothing will. Both answers come from here, so the
/// promise a pointer makes and what the drop actually does cannot drift apart.
public enum CanvasFileDrop: Equatable, Sendable {
    /// A picture, at the pixel size read from its header. It lands on the
    /// canvas as a layer, in a box the drag can draw before letting go.
    case picture(CGSize)
    /// A Photonz document. It opens in a window rather than landing on this
    /// canvas, so it is taken, but there is no landing box to draw.
    case package
    /// A text file, an archive, a folder, a picture too broken to read: there
    /// is nothing the canvas can make of it, so the drag refuses it.
    case unsupported

    /// The extension a Photonz document carries.
    public static let packageExtension = "photonz"

    /// Reads what a file on a drag is, from its name and its header only —
    /// never a full decode, because this is asked on every mouse move.
    public static func of(_ url: URL) -> CanvasFileDrop {
        if url.pathExtension.lowercased() == packageExtension { return .package }
        guard let size = ImageCodec.pixelSize(ofFileAt: url) else { return .unsupported }
        return .picture(size)
    }

    /// Whether letting go here would do anything at all. The pointer says no
    /// when this is false.
    public var isAccepted: Bool { self != .unsupported }

    /// The size of the picture, for the landing box a drag draws. Nil for
    /// everything that does not land on this canvas.
    public var pictureSize: CGSize? {
        if case .picture(let size) = self { return size }
        return nil
    }
}
