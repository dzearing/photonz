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
/// is shown at, how big the card holding them is and where it goes. The pictures
/// themselves are `DocumentRenderer.iconPreview`, which draws the frame AT that
/// many pixels rather than shrinking a big picture — a smooth shrink looks fine
/// and hides the exact problem the strip exists to show.
public enum IconPreviews {

    /// The sizes interface iconography is actually shown at. Not 512: an app
    /// icon is the thing being drawn, not a size to check it at, and a 512
    /// chip would be bigger than the canvas it sits on.
    public static let interfaceSides: [CGFloat] = [16, 24, 32, 48, 64]

    /// The biggest square that is an icon rather than a screen, bar the app
    /// icon below; the smallest screen the app offers is a 390 point phone, so
    /// the two lists overlap in size and only the SHAPE tells them apart — a
    /// phone is not square.
    public static let largestIconSide: CGFloat = 512

    /// An app icon, drawn at the one size bigger than that. Only exactly this:
    /// the Square screen is 1000, and it is a screen.
    public static let appIconSide: CGFloat = 1024

    /// Whether a frame this size is an icon: square, and no bigger than an app
    /// icon. Deliberately wider than "matches one of the Icons presets" — a
    /// frame somebody typed 40 into is plainly an icon, and would be baffled to
    /// find the strip gone.
    public static func isIconSize(_ size: CGSize) -> Bool {
        guard size.width >= 1, size.width == size.height else { return false }
        return size.width <= largestIconSide || size.width == appIconSide
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
        guard side >= 1, side <= largestIconSide || side == appIconSide else { return [] }
        var sides = interfaceSides.filter { $0 <= side * 2 }
        if side <= (interfaceSides.last ?? 0), !sides.contains(side) { sides.append(side) }
        return sides.sorted()
    }

    /// The two grounds every size is drawn on. The dark one is the mock's own
    /// pair, light ink on near black; the light one is plain white unless the
    /// frame's own surface can be it (`iconPreviewGroundHex`).
    public static let lightGroundHex = "#FFFFFF"
    public static let darkGroundHex = "#0B0D14"
    public static let inkOnDarkHex = "#F2F4FF"
    /// Below this a frame's surface is too dark to call the Light ground.
    public static let lightestDarkSurface: Double = 0.6

    /// The sizes a frame of this size is shown at, or nothing for a frame that
    /// is not an icon.
    public static func sides(forFrameSize size: CGSize) -> [CGFloat] {
        isIconSize(size) ? sides(forFrameSide: size.width) : []
    }

    // MARK: The card

    /// Between two sizes on a ground.
    public static let columnGap: CGFloat = 10
    /// From a ground's edge to the first and last size.
    public static let groundInsetX: CGFloat = 8
    /// Above and below the biggest size on a ground.
    public static let groundInsetY: CGFloat = 6
    /// Between the two grounds, and from the second to the numbers.
    public static let groundGap: CGFloat = 4
    /// Inside the glass, on every side.
    public static let cardPadding: CGFloat = 10
    /// The title row, and the air under it.
    public static let titleHeight: CGFloat = 18
    public static let titleGap: CGFloat = 6
    /// The row of numbers under the grounds.
    public static let numberHeight: CGFloat = 12
    /// The word on a ground sits in the top left corner, above the smallest
    /// size. It needs this much height over that size to clear it, and it is
    /// narrower than the first column and its gap, so it can never touch the
    /// size beside it and costs the card no width at all.
    private static let wordHeight: CGFloat = 10
    /// As narrow as a ground goes: the title has to fit over it.
    public static let minimumGroundWidth: CGFloat = 64
    /// With play and the speed menu in the title row.
    public static let minimumGroundWidthWithTransport: CGFloat = 132

    /// How tall one ground is: the biggest size with air round it, and never
    /// less than the word on it and the smallest size stacked.
    public static func groundHeight(sides: [CGFloat]) -> CGFloat {
        let biggest = sides.max() ?? 0
        let smallest = sides.min() ?? 0
        return max(biggest, smallest + wordHeight) + groundInsetY * 2
    }

    /// Where each size starts along a ground, in the order given. The numbers
    /// use the same answer, so a number is always under its own two pictures.
    public static func columnLeadings(sides: [CGFloat]) -> [CGFloat] {
        var x = groundInsetX
        return sides.map { side in
            defer { x += side + columnGap }
            return x
        }
    }

    public static func groundWidth(sides: [CGFloat], hasTransport: Bool) -> CGFloat {
        let columns = sides.reduce(0, +) + CGFloat(max(sides.count - 1, 0)) * columnGap
        return max(columns + groundInsetX * 2,
                   hasTransport ? minimumGroundWidthWithTransport : minimumGroundWidth)
    }

    /// The whole card, exactly. It is sized here rather than left to SwiftUI
    /// because where it may go depends on how big it is.
    public static func cardSize(sides: [CGFloat], hasTransport: Bool) -> CGSize {
        CGSize(width: groundWidth(sides: sides, hasTransport: hasTransport) + cardPadding * 2,
               height: cardPadding * 2 + titleHeight + titleGap
                   + groundHeight(sides: sides) * 2 + groundGap * 2 + numberHeight)
    }

    // MARK: Where the card goes

    /// Where the card sits and how much of it there is.
    public struct Placement: Equatable, Sendable {
        public let sides: [CGFloat]
        public let anchor: PanelAnchor
        public let frame: CGRect

        public init(sides: [CGFloat], anchor: PanelAnchor, frame: CGRect) {
            self.sides = sides
            self.anchor = anchor
            self.frame = frame
        }
    }

    /// The corners it may take, best first. Top left is where the mock puts it.
    private static let corners: [PanelAnchor] = [.topLeading, .topTrailing,
                                                 .bottomLeading, .bottomTrailing]

    /// The first place the card can sit without covering the icon, or nil when
    /// there is none. All rects are in the canvas view's own space.
    ///
    /// An icon is fitted to the view when its frame is made, which leaves far
    /// less than a card's width beside it, so "the corner it is least in"
    /// (UX-PATTERNS, furniture rule 3) is not enough on its own. In order:
    ///
    ///  1. the whole card in a corner clear of the whole frame;
    ///  2. the whole card clear of what is drawn, lying on the empty artboard;
    ///  3. the card without its biggest sizes, one at a time, clear of what is
    ///     drawn. The small sizes stay because they are the ones a hairline
    ///     dies at;
    ///  4. nothing. Zoomed right in, every corner has the drawing in it, and
    ///     the card goes rather than cover it.
    ///
    /// `ink` is what must stay visible: the drawing, and whatever is picked
    /// with its handles (the frame itself, when that is what is picked).
    /// `chrome` is never lain on at any price: a card behind the tool bar is
    /// a card nobody can see.
    public static func placement(sides: [CGFloat], hasTransport: Bool, in bounds: CGSize,
                                 inset: CGFloat, icon: CGRect, ink: [CGRect],
                                 chrome: [CGRect]) -> Placement? {
        func clear(_ sides: [CGFloat], of obstacles: [CGRect]) -> Placement? {
            let size = cardSize(sides: sides, hasTransport: hasTransport)
            for anchor in corners {
                let frame = PanelPlacement.frame(for: anchor, size: size, in: bounds, inset: inset)
                guard frame.minX >= 0, frame.minY >= 0,
                      frame.maxX <= bounds.width, frame.maxY <= bounds.height else { continue }
                if !(obstacles + chrome).contains(where: { $0.intersects(frame) }) {
                    return Placement(sides: sides, anchor: anchor, frame: frame)
                }
            }
            return nil
        }
        let ordered = sides.sorted()
        guard !ordered.isEmpty else { return nil }
        if let whole = clear(ordered, of: [icon]) { return whole }
        for count in stride(from: ordered.count, to: 0, by: -1) {
            if let placed = clear(Array(ordered.prefix(count)), of: ink) { return placed }
        }
        return nil
    }
}

extension PhotonzDocument {

    /// Whether this layer is a frame the size an icon is drawn at.
    public func isIconFrame(id: UUID) -> Bool {
        guard let layer = layer(id: id), layer.isFrame else { return false }
        return IconPreviews.isIconSize(layer.frame.size)
    }

    /// The colour of the Light ground: the frame's own surface when that is
    /// one flat, opaque, light colour on a frame drawn at full strength, and
    /// plain white otherwise. The picture still carries that surface, exactly
    /// as Export writes it, so ground and picture are one colour and the glyph
    /// sits straight on the ground rather than on a white square inside a
    /// grey one. A dark, gradient or faded surface stays what it is, a square
    /// in the picture: the ground says Light on it, so it has to be light.
    public func iconPreviewGroundHex(id: UUID) -> String {
        guard let frame = layer(id: id), frame.isFrame, frame.style.opacity >= 1,
              let surface = frame.group?.background, surface.kind == .solid,
              let colour = RGBA(hex: surface.hex), colour.a >= 1,
              colour.relativeLuminance >= IconPreviews.lightestDarkSurface
        else { return IconPreviews.lightGroundHex }
        return surface.hex
    }

    /// What is drawn in an icon frame and can be seen, as canvas-space boxes
    /// cut to the frame: the thing the previews card must never cover. The
    /// frame clips, so whatever spills past its edge is not on screen.
    public func iconPreviewInk(id: UUID) -> [CGRect] {
        guard let frame = layer(id: id), frame.isFrame, let box = canvasBounds(of: id),
              let children = frame.group?.children else { return [] }
        return children.filter(\.isVisible).compactMap { child in
            guard let drawn = canvasContentBounds(of: child.id) else { return nil }
            let visible = drawn.intersection(box)
            return visible.isNull || visible.isEmpty ? nil : visible
        }
    }

    /// The frame on its own, as one preview draws it.
    ///
    /// Exactly what Export takes (`frameDocument(id:)`) on the Light ground, so
    /// a line too thin to survive is exactly as faint as in the exported file.
    /// On the Dark ground the frame's own surface is left out: that white is
    /// the artboard rather than the icon, and left in it would cover the dark
    /// the ground exists to show the glyph against.
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
