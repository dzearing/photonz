import CoreGraphics
import Foundation

/// A logo or a photo off the Library shelf, let go on the timeline
/// (`video-title-wt.html`, steps 6 to 8: the Gfx track holds the art).
///
/// A still is laid OVER the picture the way a title is, never edited into it:
/// it lands on the track under the pointer when that track is free for the
/// whole of it, and on a new track of its own just above otherwise
/// (`titleLanding`). So letting go of a logo never covers or cuts a clip.
public enum PictureClip {
    /// How long a still runs when it lands: five seconds, Premiere's default
    /// still length, so a Premiere editor's logo is as long as they expect.
    public static let lengthMS = 5_000
}

extension PhotonzDocument {

    /// Puts a picture the document holds on the timeline where `landing`
    /// says, sized to fit the frame and centred in it. Reuses the ref, so a
    /// second placement is a second layer and never a second bitmap.
    ///
    /// Nil, and nothing changed, where the landing is refused.
    @discardableResult
    public mutating func landPicture(_ image: ImageRef, named name: String,
                                     at landing: ClipLanding) -> UUID? {
        let start = max(0, landing.startMS)
        var layer = Layer(name: name, content: .image(image),
                          frame: placementForIncomingImage(size: image.pixelSize, at: nil))
        layer.time = LayerTime(inMS: start, outMS: start + max(LayerTime.shortestMS, landing.lengthMS))
        return land(layer, at: landing)
    }
}
