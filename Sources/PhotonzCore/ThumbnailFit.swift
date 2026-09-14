import CoreGraphics

/// How to draw a capture inside a thumbnail tile: which part of the bitmap to
/// show, and how big to show it.
///
/// Two rules, both of them about the size to draw at:
///
/// 1. **A ratio cap.** A picture far wider than it is tall (or far taller than
///    it is wide) is CROPPED to the cap rather than running on as a sliver.
///    Wide crops from the LEADING edge and tall crops from the TOP, because the
///    start of a screenshot — the window title, the app's own logo, the first
///    controls on a bar — is the part a person recognises it by.
/// 2. **Never bigger than life.** A picture smaller than the tile is drawn at
///    its own size, centred, instead of being blown up into a soft mess.
///
/// "Its own size" is measured in POINTS, never in pixels: a Retina capture of a
/// 60x30 point region is a 120x60 bitmap, and drawing that at 120x60 points is
/// already a 2x upscale of what the person actually saw. `pixelScale` carries
/// the capture's backing scale (see `DisplayScale`), and everything the tile
/// draws is in points.
public struct ThumbnailFit: Equatable, Sendable {
    /// Which edge of the picture the ratio cap cut off, if any.
    public enum CroppedEdge: Equatable, Sendable {
        case trailing
        case bottom
    }

    /// The part of the bitmap to show, in whole image PIXELS, top-left origin —
    /// ready to hand straight to `CGImage.cropping(to:)`.
    public let cropPixels: CGRect
    /// The size to draw that part at, in POINTS.
    public let drawnSize: CGSize
    /// The edge the ratio cap cut off, so a tile can quietly say it is cropped.
    public let croppedEdge: CroppedEdge?

    public init(cropPixels: CGRect, drawnSize: CGSize, croppedEdge: CroppedEdge?) {
        self.cropPixels = cropPixels
        self.drawnSize = drawnSize
        self.croppedEdge = croppedEdge
    }

    public var isCropped: Bool { croppedEdge != nil }
    /// True when the whole bitmap is shown, so the caller can skip the crop.
    public var showsWholeImage: Bool { croppedEdge == nil }

    /// The widest (and, flipped, the tallest) a tile is allowed to get. The
    /// reporter's own words were "say 2.5:1 or 3:1"; 2.5 keeps the history strip
    /// legible when several wide captures sit in a row.
    public static let defaultMaxAspect: CGFloat = 2.5

    /// Works out what a tile should draw.
    ///
    /// - Parameters:
    ///   - pixelSize: the bitmap's size in pixels.
    ///   - pixelScale: the capture's backing scale (1, 2 or 3). Bad values are 1.
    ///   - available: the space the tile has, in points. Either side may be
    ///     `.infinity` for "as much as it wants" — the history strip is a fixed
    ///     height and a free width.
    ///   - maxAspect: the ratio cap, long side over short side.
    public static func fit(pixelSize: CGSize,
                           pixelScale: CGFloat,
                           available: CGSize,
                           maxAspect: CGFloat = defaultMaxAspect) -> ThumbnailFit {
        guard pixelSize.width >= 1, pixelSize.height >= 1,
              pixelSize.width.isFinite, pixelSize.height.isFinite,
              maxAspect.isFinite, maxAspect >= 1 else {
            return ThumbnailFit(cropPixels: .zero, drawnSize: .zero, croppedEdge: nil)
        }
        let scale = (pixelScale.isFinite && pixelScale > 0) ? pixelScale : 1

        // 1. Cap the ratio by cropping, in pixels, anchored at the top-left.
        var crop = CGRect(origin: .zero, size: pixelSize)
        var edge: CroppedEdge? = nil
        let aspect = pixelSize.width / pixelSize.height
        if aspect > maxAspect {
            crop.size.width = (pixelSize.height * maxAspect).rounded()
            edge = .trailing
        } else if aspect < 1 / maxAspect {
            crop.size.height = (pixelSize.width * maxAspect).rounded()
            edge = .bottom
        }

        // 2. Scale that down to fit, never up: the picture's own point size is
        //    the ceiling.
        let natural = CGSize(width: crop.width / scale, height: crop.height / scale)
        let fitWidth = available.width.isFinite ? available.width / natural.width : .infinity
        let fitHeight = available.height.isFinite ? available.height / natural.height : .infinity
        let k = min(1, fitWidth, fitHeight)
        let drawn = CGSize(width: natural.width * k, height: natural.height * k)

        return ThumbnailFit(cropPixels: crop, drawnSize: drawn, croppedEdge: edge)
    }
}
