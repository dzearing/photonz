import CoreGraphics
import Foundation
import PhotonzCore

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
    /// A sound file, or a recording. What either does depends on whether the
    /// document underneath runs in time, which this cannot see: `MediaDrop`
    /// answers that, and the drag says the answer out loud rather than drawing
    /// a box, because neither of these has a box to draw.
    case media(MediaDrop.Kind)
    /// A text file, an archive, a folder, a picture too broken to read: there
    /// is nothing the canvas can make of it, so the drag refuses it.
    case unsupported

    /// The extension a Photonz document carries.
    public static let packageExtension = "photonz"

    /// Reads what a file on a drag is, from its name and its header only —
    /// never a full decode, because this is asked on every mouse move.
    public static func of(_ url: URL, takingMedia: Bool = false) -> CanvasFileDrop {
        if url.pathExtension.lowercased() == packageExtension { return .package }
        // Asked BEFORE the header read, because ImageIO happily reads the
        // poster frame out of some movie containers and a recording that came
        // back as a still picture would land as one.
        if takingMedia, let media = MediaFiles.kind(of: url) { return .media(media) }
        guard let size = ImageCodec.pixelSize(ofFileAt: url) else { return .unsupported }
        return .picture(size)
    }

    /// The sound or the recording this is, where it is one.
    public var media: MediaDrop.Kind? {
        if case .media(let kind) = self { return kind }
        return nil
    }

    /// Whether the canvas could do anything with a file of this KIND. The
    /// pointer says no when this is false.
    ///
    /// A picture and a package are settled here. A sound or a recording is not:
    /// what happens to either depends on the document underneath, so the final
    /// yes or no for `.media` comes from `MediaDrop.answer`, and this only says
    /// the file is worth asking about.
    public var isAccepted: Bool { self != .unsupported }

    /// The size of the picture, for the landing box a drag draws. Nil for
    /// everything that does not land on this canvas.
    public var pictureSize: CGSize? {
        if case .picture(let size) = self { return size }
        return nil
    }
}
