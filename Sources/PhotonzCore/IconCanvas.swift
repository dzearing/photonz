import CoreGraphics
import Foundation

/// A picture made as an icon (`madeAsIcon`): its CANVAS answers every question
/// an icon frame answers, so somebody who started from File, New, Image, Icon
/// gets the keylines, the snapping, the weight and the previews without making
/// a frame they never heard of.
///
/// The context still follows where you are working, which is the rule
/// `DocumentHasNoKindTests` pins: a frame laid on the canvas speaks for itself,
/// a screen stays a screen, and the canvas speaks only where no frame does.
///
/// A real frame was the other way to do it and is the wrong one: it would sit
/// in the layers list as a thing nobody made, and everything drawn would land
/// inside it.
extension PhotonzDocument {

    /// What stands for the canvas wherever an icon is named by id: the strip's
    /// memory, the pointer's report, the frame a shape is being drawn in. It
    /// names no layer, so `layer(id:)` is nil for it: ask `iconBox(of:)`,
    /// `iconSize(of:)` and `iconContents(of:)` instead.
    public static let iconCanvasID = UUID(uuid: (0x1C, 0x0A, 0xCA, 0x4F, 0, 0, 0x40, 0, 0x80, 0,
                                                 0, 0, 0, 0, 0, 1))

    /// The canvas, as the space an icon is drawn in.
    private var canvasBox: CGRect { CGRect(origin: .zero, size: canvasSize) }

    /// An icon frame that is the whole picture, which is how Ask lands an icon
    /// and how one is set up by hand.
    private var iconFrameFillingCanvas: Layer? {
        layers.first { $0.isFrame && $0.frame == canvasBox && IconPreviews.isIconSize($0.frame.size) }
    }

    /// Whether the canvas itself is the icon. Not at a size no icon is drawn
    /// at, the rule a frame's size already follows, so a picture cut to a
    /// banner stops being one. Not under a frame filling it either: that frame
    /// is the icon then, and answers for itself.
    public var isIconCanvas: Bool {
        madeAsIcon && IconPreviews.isIconSize(canvasSize) && iconFrameFillingCanvas == nil
    }

    /// Whether this picture's window starts in Icon: it is an icon from edge to
    /// edge, by its canvas or by a frame filling it.
    public var opensAsIcon: Bool {
        isIconCanvas || iconFrameFillingCanvas != nil
    }

    /// How long one unit is on a picture that is an icon at the Icon row's
    /// size, by its canvas or by the frame Ask lands filling it, or nil on any
    /// other picture. Such a picture is 24 units across at 512 points: a person
    /// handing the file over expects a 24 by 24 icon. App Icon keeps its own
    /// 1024 numbers, and so does an icon frame somewhere on a bigger picture.
    public var pictureIconUnit: CGFloat? {
        guard canvasSize.width == IconUnits.pictureSide, opensAsIcon else { return nil }
        return IconUnits.pictureSide / IconKeylines.artboardSide
    }

    /// How many canvas points one unit of this icon is. One, except on a
    /// picture that has 24 units across (`pictureIconUnit`).
    public func iconUnit(of id: UUID) -> CGFloat {
        guard let unit = pictureIconUnit else { return 1 }
        return id == Self.iconCanvasID || id == iconFrameFillingCanvas?.id ? unit : 1
    }

    /// The same, for an icon known by its box.
    public func iconUnit(ofBox box: CGRect) -> CGFloat {
        box == canvasBox ? pictureIconUnit ?? 1 : 1
    }

    /// The box of an icon in canvas coordinates, the canvas included.
    public func iconBox(of id: UUID) -> CGRect? {
        guard isIconFrame(id: id) else { return nil }
        return id == Self.iconCanvasID ? canvasBox : canvasFrame(of: id)
    }

    /// The size an icon is drawn at, the canvas included.
    public func iconSize(of id: UUID) -> CGSize? {
        guard isIconFrame(id: id) else { return nil }
        return id == Self.iconCanvasID ? canvasSize : layer(id: id)?.frame.size
    }

    /// What is drawn in an icon. On a canvas that leaves out the frames, which
    /// speak for themselves, and the Background.
    public func iconContents(of id: UUID) -> [Layer] {
        id == Self.iconCanvasID ? iconCanvasDrawing.filter { !$0.isFrame } : layer(id: id)?.children ?? []
    }

    /// Everything on the canvas but the locked picture it started as, which is
    /// to the canvas what a frame's surface is to a frame.
    var iconCanvasDrawing: [Layer] {
        layers.filter { !($0.isLocked && $0.imageRef != nil) }
    }

    /// What the previews card must not cover on a canvas.
    var iconCanvasInk: [CGRect] {
        guard isIconCanvas else { return [] }
        return iconCanvasDrawing.filter(\.isVisible).compactMap { layer in
            guard let drawn = canvasContentBounds(of: layer.id) else { return nil }
            let visible = drawn.intersection(canvasBox)
            return visible.isNull || visible.isEmpty ? nil : visible
        }
    }

    /// The canvas as one preview draws it: the picture on the Light ground, and
    /// the drawing alone on the Dark one, for the reason a frame's surface is
    /// left out there (`iconPreviewDocument(id:onDarkGround:)`).
    func iconCanvasPreviewDocument(onDarkGround: Bool) -> PhotonzDocument? {
        guard isIconCanvas else { return nil }
        var scoped = self
        if onDarkGround { scoped.layers = iconCanvasDrawing }
        return scoped
    }

    /// What a preview's picture is cached against: everything that can change
    /// how this icon looks.
    public func iconPreviewHash(id: UUID) -> Int {
        id == Self.iconCanvasID ? layers.hashValue : layer(id: id)?.hashValue ?? 0
    }

    /// Whether anything in this icon moves.
    public func iconHasMotion(id: UUID) -> Bool {
        id == Self.iconCanvasID ? layers.contains(where: \.hasMotionInside)
                                : layer(id: id)?.hasMotionInside ?? false
    }

    /// The document with this icon at a moment of its loop. Only the frame is
    /// worked out for a frame; a canvas is the whole picture.
    public func movedIcon(id: UUID, toMotionTimeMS ms: Int) -> PhotonzDocument {
        id == Self.iconCanvasID ? moved(toMotionTimeMS: ms) : moved(layerID: id, toMotionTimeMS: ms)
    }
}
