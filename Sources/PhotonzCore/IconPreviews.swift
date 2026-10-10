import CoreGraphics
import Foundation

/// Seeing an icon at the size it will really be used (`next-icon-previews`).
///
/// An icon is the only thing in this app that is drawn at one size and looked
/// at at another. A hairline that reads beautifully on a 512 point canvas is
/// gone at 16, and finding that out after export means drawing it again. So
/// while an icon frame is what you are working in, the same drawing is shown
/// small beside you, at the sizes it will really be used.
///
/// This is the pure half: which frames count as icons, which sizes one of them
/// is shown at, and how big the chip under each preview is. The pictures
/// themselves are `DocumentRenderer.iconPreview`, which draws the frame AT that
/// many pixels rather than shrinking a big picture — a smooth shrink looks fine
/// and hides the exact problem the strip exists to show.
public enum IconPreviews {

    /// The sizes interface iconography is actually shown at. Not 512: an app
    /// icon is the thing being drawn, not a size to check it at, and a 512
    /// chip would be bigger than the canvas it sits on.
    public static let interfaceSides: [CGFloat] = [16, 24, 32, 48, 64]

    /// The biggest square that is an icon rather than a screen. 512 is the app
    /// icon, which is the largest size anybody draws one at; the smallest
    /// screen the app offers is a 390 point phone, so the two lists overlap in
    /// size and only the SHAPE tells them apart — a phone is not square.
    public static let largestIconSide: CGFloat = 512

    /// The margin around a preview on its chip, on every side. One number, so
    /// five chips of five sizes read as one row of squares.
    public static let chipMargin: CGFloat = 5

    /// Whether a frame this size is an icon: square, and no bigger than an app
    /// icon. Deliberately wider than "matches one of the Icons presets" — a
    /// frame somebody typed 40 into is plainly an icon, and would be baffled to
    /// find the strip gone.
    public static func isIconSize(_ size: CGSize) -> Bool {
        guard size.width >= 1, size.width == size.height else { return false }
        return size.width <= largestIconSide
    }

    /// The sizes one frame is shown at, smallest first.
    ///
    /// Every interface size up to twice the frame's own side, plus that side
    /// itself. So a 24 point glyph is shown at 16, 24, 32 and 48, which is the
    /// strip the icon mock draws under one (icon-draw-wt.html, step 11): a 24
    /// grid glyph is used at 32 and 48 too, and that is where a designer checks
    /// it before it joins a set. Bigger is honest here because each picture is
    /// drawn AT its size from the shapes, never a small picture blown up.
    /// Twice is where it stops: a 16 shown at 64 is a different icon.
    public static func sides(forFrameSide side: CGFloat) -> [CGFloat] {
        guard side >= 1, side <= largestIconSide else { return [] }
        var sides = interfaceSides.filter { $0 <= side * 2 }
        if side <= (interfaceSides.last ?? 0), !sides.contains(side) { sides.append(side) }
        return sides.sorted()
    }

    /// The one size shown on a dark chip, or nil when there is a single chip.
    ///
    /// The mock puts 32 on dark under a 24 point glyph, so it is checked on
    /// both grounds. That is the chip before the biggest: the biggest stays
    /// light, which is where detail is read, and the one beside it shows the
    /// glyph against the dark.
    public static func darkSide(among sides: [CGFloat]) -> CGFloat? {
        let sorted = sides.sorted()
        guard sorted.count >= 2 else { return nil }
        return sorted[sorted.count - 2]
    }

    /// The dark chip's ground, and the ink a one colour dark glyph is drawn in
    /// on it: the mock's own pair, light on near black.
    public static let darkChipHex = "#0B0D14"
    public static let inkOnDarkHex = "#F2F4FF"

    /// The sizes a frame of this size is shown at, or nothing for a frame that
    /// is not an icon.
    public static func sides(forFrameSize size: CGSize) -> [CGFloat] {
        isIconSize(size) ? sides(forFrameSide: size.width) : []
    }

    /// The square a preview sits on: the icon plus one even margin. The chip
    /// is what makes a white glyph visible at all, since a frame that paints no
    /// surface renders as nothing on glass.
    public static func chipSide(for side: CGFloat) -> CGFloat {
        side + chipMargin * 2
    }
}

extension PhotonzDocument {

    /// Whether this layer is a frame the size an icon is drawn at.
    public func isIconFrame(id: UUID) -> Bool {
        guard let layer = layer(id: id), layer.isFrame else { return false }
        return IconPreviews.isIconSize(layer.frame.size)
    }

    /// The colour a light chip is painted, when it can be the frame's own
    /// surface: one flat opaque colour on a frame drawn at full strength. The
    /// picture still carries that surface, exactly as Export writes it, so the
    /// chip and the picture are one colour and the glyph sits straight on the
    /// chip the way icon-draw-wt.html draws it, rather than on a white square
    /// inside a grey one. Nil for a clear frame, a gradient, or a faded one,
    /// which sit on the plain chip.
    public func iconPreviewGroundHex(id: UUID) -> String? {
        guard let frame = layer(id: id), frame.isFrame, frame.style.opacity >= 1,
              let surface = frame.group?.background, surface.kind == .solid,
              let colour = RGBA(hex: surface.hex), colour.a >= 1 else { return nil }
        return surface.hex
    }

    /// The frame on its own, as one preview chip draws it.
    ///
    /// Exactly what Export takes (`frameDocument(id:)`) on a light chip, so a
    /// line too thin to survive is exactly as faint as in the exported file.
    /// On the dark chip the frame's own surface is left out: that white is the
    /// artboard rather than the icon, and left in it would cover the dark
    /// ground the chip exists to show the glyph against.
    public func iconPreviewDocument(id: UUID, onDarkGround: Bool) -> PhotonzDocument? {
        guard var scoped = frameDocument(id: id) else { return nil }
        guard onDarkGround else { return scoped }
        scoped.updateLayer(id: id) { frame in
            guard var group = frame.group else { return }
            group.background = nil
            frame.content = .group(group)
        }
        return scoped
    }

    /// The icon frame a layer is being drawn inside, if any.
    ///
    /// Itself when the frame is what is selected, and the frame above it when
    /// what is selected is the shape you are drawing — which is what it is for
    /// nearly the whole time anybody is drawing an icon.
    public func iconFrameID(containing id: UUID) -> UUID? {
        guard let frameID = frameID(containing: id), isIconFrame(id: frameID) else { return nil }
        return frameID
    }

    /// The icon the previews strip is showing, from the three things that can
    /// say so: what is PICKED, failing that the frame the POINTER is resting
    /// in, and failing that the last icon either of them named.
    ///
    /// The first two are the rule the Width row already runs on
    /// (`iconFrameSize(picked:pointerIn:)`), so the number in the row and the
    /// pictures beside it are always about one icon. What is picked comes
    /// first and answers even when the answer is "no icon": picking a shape on
    /// a screen puts the strip away, wherever the hand has wandered.
    ///
    /// The third is the strip's own, and it is the whole point of it. Clicking
    /// an empty part of the canvas, or pressing Escape, is the ordinary way to
    /// stand back and look at what you have drawn, and it is exactly the
    /// moment the previews are worth most. Nothing is picked and the pointer
    /// is over no frame at all, so without a memory the row vanished at the
    /// one moment it was wanted. It keeps the last icon instead.
    ///
    /// Staying is bounded by being CHECKED rather than by expiring: an icon
    /// that has been deleted, or a `remembered` that was never an icon frame,
    /// is dropped here, so the strip can never go on showing an icon that is
    /// not in the document.
    public func iconPreviewFrameID(picked: UUID?, pointerIn hovered: UUID?,
                                   remembered: UUID?) -> UUID? {
        if let id = picked ?? hovered { return iconFrameID(containing: id) }
        guard let remembered, isIconFrame(id: remembered) else { return nil }
        return remembered
    }

    /// The icon frame a canvas point is inside, if any.
    ///
    /// The same question `frameID(under:)` answers, narrowed to the frames that
    /// are icons, so a screen and bare canvas both come back nil: neither has
    /// anything to say about the weight of a line.
    public func iconFrameID(under point: CGPoint) -> UUID? {
        guard let id = frameID(under: point), isIconFrame(id: id) else { return nil }
        return id
    }
}
