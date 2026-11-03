import CoreGraphics
import PhotonzCore
import Testing

@Suite("Crop geometry")
struct CropTests {
    let canvas = CGSize(width: 400, height: 400)

    // MARK: Aspect ratios

    @Test func aspectRatios() {
        let fourThree: CGFloat = 4.0 / 3.0
        let sixteenNine: CGFloat = 16.0 / 9.0
        #expect(CropAspect.free.ratio == nil)
        #expect(CropAspect.square.ratio == 1)
        #expect(CropAspect.fourThree.ratio == fourThree)
        #expect(CropAspect.sixteenNine.ratio == sixteenNine)
    }

    @Test func aspectLabels() {
        #expect(CropAspect.free.label == "Free")
        #expect(CropAspect.square.label == "1:1")
        #expect(CropAspect.fourThree.label == "4:3")
        #expect(CropAspect.sixteenNine.label == "16:9")
    }

    /// D15: the crop tool button wears the live aspect's glyph, so every aspect
    /// needs one and Free keeps the tool's own crop glyph.
    @Test func aspectSymbols() {
        #expect(CropAspect.free.symbol == "crop")
        #expect(CropAspect.square.symbol == "square")
        #expect(CropAspect.fourThree.symbol == "rectangle.ratio.4.to.3")
        #expect(CropAspect.sixteenNine.symbol == "rectangle.ratio.16.to.9")
    }

    @Test func everyAspectCarriesAHelpLineNamingItself() {
        for aspect in CropAspect.allCases {
            #expect(!aspect.help.isEmpty)
            #expect(aspect.help.contains(aspect.label))
        }
    }

    @Test func freeIsTheDefaultAndComesFirst() {
        #expect(CropAspect.allCases.first == .free)
    }

    // MARK: Fitting a rect to an aspect

    @Test func fittedFreeReturnsTheRectUnchanged() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 100)
        #expect(Crop.fitted(rect, to: .free) == rect)
    }

    @Test func fittedSquareCentersInsideALandscapeRect() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        #expect(Crop.fitted(rect, to: .square) == CGRect(x: 50, y: 0, width: 100, height: 100))
    }

    @Test func fittedSixteenNineCentersInsideATallRect() {
        let rect = CGRect(x: 0, y: 0, width: 1600, height: 1200)
        #expect(Crop.fitted(rect, to: .sixteenNine) == CGRect(x: 0, y: 150, width: 1600, height: 900))
    }

    // MARK: Free resize

    @Test func freeResizeClampsToCanvas() {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .bottomRight, to: CGPoint(x: 500, y: 500),
                                 aspect: .free, canvas: canvas)
        #expect(result == CGRect(x: 100, y: 100, width: 300, height: 300))
    }

    @Test func freeResizeNeverInverts() {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .bottomRight, to: CGPoint(x: 0, y: 0),
                                 aspect: .free, canvas: canvas)
        #expect(result.origin == CGPoint(x: 100, y: 100))
        #expect(result.width >= 1 && result.height >= 1)
    }

    // MARK: Ratio-locked corner resize

    @Test func ratioCornerFollowsTheDominantAxis() {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .bottomRight, to: CGPoint(x: 250, y: 220),
                                 aspect: .square, canvas: canvas)
        #expect(result == CGRect(x: 100, y: 100, width: 150, height: 150))
    }

    @Test func ratioCornerAnchorsTheOppositeCorner() {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .topLeft, to: CGPoint(x: 50, y: 80),
                                 aspect: .square, canvas: canvas)
        #expect(result == CGRect(x: 50, y: 50, width: 150, height: 150))
    }

    @Test func ratioCornerClampsToCanvasKeepingTheRatio() {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .bottomRight, to: CGPoint(x: 900, y: 900),
                                 aspect: .square, canvas: canvas)
        #expect(result == CGRect(x: 100, y: 100, width: 300, height: 300))
    }

    @Test func ratioCornerClampWhenOneAxisHitsTheEdgeFirst() {
        // Anchor at (100, 300): 300pt available right, 300 up — but a 16:9 box
        // dragged far right is limited by height: h ≤ 300 → w ≤ 533… no, w ≤ 300.
        let rect = CGRect(x: 100, y: 200, width: 160, height: 90)
        let result = Crop.resize(rect, dragging: .bottomRight, to: CGPoint(x: 900, y: 900),
                                 aspect: .sixteenNine, canvas: canvas)
        // availX = 300, availY = 200 → w = min(300, 200 * 16/9 ≈ 355.6) = 300
        #expect(result.origin == CGPoint(x: 100, y: 200))
        #expect(result.width == 300)
        #expect(abs(result.height - 300 * 9 / 16) < 0.001)
    }

    // MARK: Ratio-locked edge resize

    @Test func ratioEdgeScalesTheCrossAxisAroundItsCenter() {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .right, to: CGPoint(x: 260, y: 150),
                                 aspect: .square, canvas: canvas)
        #expect(result == CGRect(x: 100, y: 70, width: 160, height: 160))
    }

    @Test func ratioEdgeClampsWhenTheCrossAxisHitsTheCanvas() {
        // midY = 60 → centered height can grow to 2 × min(60, 340) = 120.
        let rect = CGRect(x: 100, y: 10, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .right, to: CGPoint(x: 350, y: 60),
                                 aspect: .square, canvas: canvas)
        #expect(result == CGRect(x: 100, y: 0, width: 120, height: 120))
    }

    @Test func ratioTopEdgeScalesWidthAroundItsCenter() {
        let rect = CGRect(x: 150, y: 150, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .top, to: CGPoint(x: 0, y: 100),
                                 aspect: .square, canvas: canvas)
        #expect(result == CGRect(x: 125, y: 100, width: 150, height: 150))
    }

    // MARK: Moving

    @Test func moveClampsInsideTheCanvas() {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 100)
        #expect(Crop.moved(rect, by: CGPoint(x: 50, y: -30), in: canvas)
                == CGRect(x: 150, y: 70, width: 100, height: 100))
        #expect(Crop.moved(rect, by: CGPoint(x: 1000, y: -1000), in: canvas)
                == CGRect(x: 300, y: 0, width: 100, height: 100))
    }

    // MARK: Drag-to-define a fresh rect

    @Test func dragRectStandardizesAndClampsFreeDrags() {
        let rect = Crop.dragRect(anchor: CGPoint(x: 200, y: 200), current: CGPoint(x: -50, y: 100),
                                 aspect: .free, canvas: canvas)
        #expect(rect == CGRect(x: 0, y: 100, width: 200, height: 100))
    }

    @Test func emptyDragYieldsNil() {
        let p = CGPoint(x: 200, y: 200)
        #expect(Crop.dragRect(anchor: p, current: p, aspect: .free, canvas: canvas) == nil)
        #expect(Crop.dragRect(anchor: p, current: p, aspect: .square, canvas: canvas) == nil)
    }

    @Test func ratioDragFollowsTheDominantAxisInTheDragDirection() {
        let rect = Crop.dragRect(anchor: CGPoint(x: 200, y: 200), current: CGPoint(x: 100, y: 140),
                                 aspect: .square, canvas: canvas)
        #expect(rect == CGRect(x: 100, y: 100, width: 100, height: 100))
    }

    @Test func ratioDragClampsToTheCanvasCorner() {
        let rect = Crop.dragRect(anchor: CGPoint(x: 350, y: 350), current: CGPoint(x: 600, y: 600),
                                 aspect: .square, canvas: canvas)
        #expect(rect == CGRect(x: 350, y: 350, width: 50, height: 50))
    }

    // MARK: Rect bounds (per-layer crop confines drags to the layer frame)

    @Test func resizeClampsToRectBounds() {
        let bounds = CGRect(x: 100, y: 100, width: 200, height: 200)
        let rect = CGRect(x: 120, y: 120, width: 100, height: 100)
        let result = Crop.resize(rect, dragging: .bottomRight, to: CGPoint(x: 900, y: 900),
                                 aspect: .free, bounds: bounds)
        #expect(result == CGRect(x: 120, y: 120, width: 180, height: 180))
    }

    @Test func ratioResizeClampsToRectBounds() {
        let bounds = CGRect(x: 100, y: 100, width: 300, height: 200)
        let rect = CGRect(x: 150, y: 150, width: 50, height: 50)
        let result = Crop.resize(rect, dragging: .bottomRight, to: CGPoint(x: 900, y: 900),
                                 aspect: .square, bounds: bounds)
        // availY = 300 - 150 = 150 limits the square.
        #expect(result == CGRect(x: 150, y: 150, width: 150, height: 150))
    }

    @Test func moveClampsInsideRectBounds() {
        let bounds = CGRect(x: 100, y: 100, width: 200, height: 200)
        let rect = CGRect(x: 150, y: 150, width: 100, height: 100)
        #expect(Crop.moved(rect, by: CGPoint(x: -500, y: 500), in: bounds)
                == CGRect(x: 100, y: 200, width: 100, height: 100))
    }

    @Test func dragRectClampsToRectBounds() {
        let bounds = CGRect(x: 100, y: 100, width: 200, height: 200)
        let rect = Crop.dragRect(anchor: CGPoint(x: 150, y: 150), current: CGPoint(x: 600, y: 250),
                                 aspect: .free, bounds: bounds)
        #expect(rect == CGRect(x: 150, y: 150, width: 150, height: 100))
    }

    // MARK: Per-layer content crop

    @Test func imageLayersSupportContentCrop() {
        let image = Layer(name: "L", content: .image(ImageRef(pixelSize: CGSize(width: 100, height: 100))),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let note = Layer(name: "A", content: .annotation(AnnotationContent(shape: .rectangle)),
                         frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(image.supportsContentCrop)
        #expect(!note.supportsContentCrop)
    }

    @Test func cropContentShrinksTheFrameAndMapsToContentCoords() {
        // Content 200×200 shown 1:1 at (100, 100).
        var layer = Layer(name: "L", content: .image(ImageRef(pixelSize: CGSize(width: 200, height: 200))),
                          frame: CGRect(x: 100, y: 100, width: 200, height: 200))
        layer.cropContent(to: CGRect(x: 150, y: 150, width: 100, height: 100))
        #expect(layer.frame == CGRect(x: 150, y: 150, width: 100, height: 100))
        #expect(layer.crop == CGRect(x: 50, y: 50, width: 100, height: 100))
    }

    @Test func cropContentAccountsForFrameScale() {
        // Content 400×400 displayed in a 200×200 frame (2× downscale).
        var layer = Layer(name: "L", content: .image(ImageRef(pixelSize: CGSize(width: 400, height: 400))),
                          frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        layer.cropContent(to: CGRect(x: 50, y: 0, width: 100, height: 100))
        #expect(layer.frame == CGRect(x: 50, y: 0, width: 100, height: 100))
        #expect(layer.crop == CGRect(x: 100, y: 0, width: 200, height: 200))
    }

    @Test func cropContentComposesWithAnExistingCrop() {
        // Already cropped to the content's right half (100,0,100,200), shown
        // in a 100×200 frame at the origin.
        var layer = Layer(name: "L", content: .image(ImageRef(pixelSize: CGSize(width: 200, height: 200))),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 200),
                          crop: CGRect(x: 100, y: 0, width: 100, height: 200))
        layer.cropContent(to: CGRect(x: 50, y: 100, width: 50, height: 100))
        #expect(layer.frame == CGRect(x: 50, y: 100, width: 50, height: 100))
        #expect(layer.crop == CGRect(x: 150, y: 100, width: 50, height: 100))
    }

    @Test func cropContentClampsToTheFrame() {
        var layer = Layer(name: "L", content: .image(ImageRef(pixelSize: CGSize(width: 100, height: 100))),
                          frame: CGRect(x: 100, y: 100, width: 100, height: 100))
        layer.cropContent(to: CGRect(x: 0, y: 0, width: 150, height: 150))
        #expect(layer.frame == CGRect(x: 100, y: 100, width: 50, height: 50))
        #expect(layer.crop == CGRect(x: 0, y: 0, width: 50, height: 50))
    }

    @Test func cropContentIgnoresNonImageLayersAndEmptyRects() {
        var note = Layer(name: "A", content: .annotation(AnnotationContent(shape: .rectangle)),
                         frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        note.cropContent(to: CGRect(x: 10, y: 10, width: 50, height: 50))
        #expect(note.crop == nil)
        #expect(note.frame == CGRect(x: 0, y: 0, width: 100, height: 100))

        var image = Layer(name: "L", content: .image(ImageRef(pixelSize: CGSize(width: 100, height: 100))),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        image.cropContent(to: CGRect(x: 500, y: 500, width: 50, height: 50))
        #expect(image.crop == nil, "a rect outside the frame changes nothing")
    }

    // MARK: Rule-of-thirds grid

    @Test func thirdsLinesDivideTheRectInThree() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 90)
        let lines = Crop.thirdsLines(in: rect)
        #expect(lines.count == 4)
        #expect(lines.contains { $0.from == CGPoint(x: 100, y: 0) && $0.to == CGPoint(x: 100, y: 90) })
        #expect(lines.contains { $0.from == CGPoint(x: 200, y: 0) && $0.to == CGPoint(x: 200, y: 90) })
        #expect(lines.contains { $0.from == CGPoint(x: 0, y: 30) && $0.to == CGPoint(x: 300, y: 30) })
        #expect(lines.contains { $0.from == CGPoint(x: 0, y: 60) && $0.to == CGPoint(x: 300, y: 60) })
    }
}

/// The Crop tool draws the box you want, the way a marquee is drawn
/// (`with-the-crop-tool-dragging-across-the-picture-d`, the user 2026-11-03):
/// a press anywhere that is not a handle draws, inside the current box or
/// outside it, and Space is what moves.
@Suite("Crop drawing")
struct CropDrawingTests {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
    let full = CGRect(x: 0, y: 0, width: 400, height: 300)

    // MARK: What a press does

    @Test func aPressInsideTheBoxDrawsRatherThanMoves() {
        let press = Crop.press(at: CGPoint(x: 200, y: 150), cropRect: full, zoom: 1, spaceHeld: false)
        #expect(press == .draw)
    }

    @Test func aPressOutsideTheBoxDraws() {
        let box = CGRect(x: 100, y: 100, width: 100, height: 100)
        #expect(Crop.press(at: CGPoint(x: 20, y: 20), cropRect: box, zoom: 1, spaceHeld: false) == .draw)
        #expect(Crop.press(at: CGPoint(x: 20, y: 20), cropRect: nil, zoom: 1, spaceHeld: false) == .draw)
    }

    @Test func aPressOnAHandleStillResizes() {
        let box = CGRect(x: 100, y: 100, width: 100, height: 100)
        #expect(Crop.press(at: CGPoint(x: 100, y: 100), cropRect: box, zoom: 1, spaceHeld: false)
                == .resize(.topLeft))
        #expect(Crop.press(at: CGPoint(x: 200, y: 150), cropRect: box, zoom: 1, spaceHeld: false)
                == .resize(.right))
    }

    @Test func withSpaceHeldEveryPressMovesTheBox() {
        let box = CGRect(x: 100, y: 100, width: 100, height: 100)
        #expect(Crop.press(at: CGPoint(x: 150, y: 150), cropRect: box, zoom: 1, spaceHeld: true) == .move)
        // On a handle too: the open hand is what the pointer shows, so the
        // handle under it is not what the press takes.
        #expect(Crop.press(at: CGPoint(x: 100, y: 100), cropRect: box, zoom: 1, spaceHeld: true) == .move)
        #expect(Crop.press(at: CGPoint(x: 20, y: 20), cropRect: box, zoom: 1, spaceHeld: true) == .move)
        // With no box there is nothing to move, so the press draws one.
        #expect(Crop.press(at: CGPoint(x: 20, y: 20), cropRect: nil, zoom: 1, spaceHeld: true) == .draw)
    }

    @Test func theCueSaysWhatThePressDoes() {
        let box = CGRect(x: 100, y: 100, width: 100, height: 100)
        #expect(CanvasPointer.cropCue(at: CGPoint(x: 150, y: 150), cropRect: box, zoom: 1) == nil)
        #expect(CanvasPointer.cropCue(at: CGPoint(x: 100, y: 100), cropRect: box, zoom: 1)
                == .resize(.topLeft))
        #expect(CanvasPointer.cropCue(at: CGPoint(x: 150, y: 150), cropRect: box, zoom: 1,
                                      spaceHeld: true) == .grab)
        #expect(CanvasPointer.cropCue(at: CGPoint(x: 100, y: 100), cropRect: box, zoom: 1,
                                      spaceHeld: true) == .grab)
    }

    // MARK: The box a drag draws

    @Test func aPlainDrawRunsFromThePressToThePointer() {
        let rect = Crop.drawnRect(anchor: CGPoint(x: 50, y: 40), current: CGPoint(x: 250, y: 140),
                                  aspect: .free, fromCenter: false, square: false, bounds: bounds)
        #expect(rect == CGRect(x: 50, y: 40, width: 200, height: 100))
    }

    @Test func aDrawBackwardsStandardizes() {
        let rect = Crop.drawnRect(anchor: CGPoint(x: 250, y: 140), current: CGPoint(x: 50, y: 40),
                                  aspect: .free, fromCenter: false, square: false, bounds: bounds)
        #expect(rect == CGRect(x: 50, y: 40, width: 200, height: 100))
    }

    @Test func aDrawStaysOnThePicture() {
        let rect = Crop.drawnRect(anchor: CGPoint(x: 300, y: 200), current: CGPoint(x: 900, y: 900),
                                  aspect: .free, fromCenter: false, square: false, bounds: bounds)
        #expect(rect == CGRect(x: 300, y: 200, width: 100, height: 100))
    }

    @Test func shiftKeepsASquareOnAFreeCrop() {
        let rect = Crop.drawnRect(anchor: CGPoint(x: 50, y: 40), current: CGPoint(x: 250, y: 100),
                                  aspect: .free, fromCenter: false, square: true, bounds: bounds)
        #expect(rect == CGRect(x: 50, y: 40, width: 200, height: 200))
    }

    @Test func shiftKeepsTheLockedAspectRatherThanASquare() {
        let rect = Crop.drawnRect(anchor: CGPoint(x: 0, y: 0), current: CGPoint(x: 160, y: 10),
                                  aspect: .sixteenNine, fromCenter: false, square: true, bounds: bounds)
        #expect(rect == CGRect(x: 0, y: 0, width: 160, height: 90))
    }

    @Test func optionDrawsOutFromTheCentre() {
        let rect = Crop.drawnRect(anchor: CGPoint(x: 200, y: 150), current: CGPoint(x: 260, y: 190),
                                  aspect: .free, fromCenter: true, square: false, bounds: bounds)
        #expect(rect == CGRect(x: 140, y: 110, width: 120, height: 80))
    }

    @Test func optionFromTheCentreStopsAtTheNearestEdge() {
        // 50 from the left edge, so the box can be at most 100 wide.
        let rect = Crop.drawnRect(anchor: CGPoint(x: 50, y: 150), current: CGPoint(x: 300, y: 170),
                                  aspect: .free, fromCenter: true, square: false, bounds: bounds)
        #expect(rect == CGRect(x: 0, y: 130, width: 100, height: 40))
    }

    @Test func optionAndShiftDrawASquareFromTheCentre() {
        let rect = Crop.drawnRect(anchor: CGPoint(x: 200, y: 150), current: CGPoint(x: 230, y: 200),
                                  aspect: .free, fromCenter: true, square: true, bounds: bounds)
        #expect(rect == CGRect(x: 150, y: 100, width: 100, height: 100))
    }

    @Test func optionFromTheCentreKeepsALockedAspectInsideThePicture() {
        // 16:9 from the middle, pulled far: as wide as the picture allows.
        let rect = Crop.drawnRect(anchor: CGPoint(x: 200, y: 150), current: CGPoint(x: 900, y: 150),
                                  aspect: .sixteenNine, fromCenter: true, square: false, bounds: bounds)
        let r = try! #require(rect)
        #expect(abs(r.width / r.height - 16.0 / 9.0) < 0.0001)
        #expect(bounds.contains(r))
        #expect(abs(r.midX - 200) < 0.0001 && abs(r.midY - 150) < 0.0001)
        #expect(abs(r.width - 400) < 0.0001)
    }

    @Test func anEmptyDrawIsNoBox() {
        let p = CGPoint(x: 100, y: 100)
        #expect(Crop.drawnRect(anchor: p, current: p, aspect: .free, fromCenter: false,
                               square: false, bounds: bounds) == nil)
        #expect(Crop.drawnRect(anchor: p, current: p, aspect: .free, fromCenter: true,
                               square: false, bounds: bounds) == nil)
    }

    // MARK: Space while drawing

    @Test func spaceWhileDrawingSlidesTheBoxAndItsAnchorTogether() {
        let rect = CGRect(x: 50, y: 50, width: 100, height: 80)
        let slid = Crop.slidDraw(anchor: CGPoint(x: 50, y: 50), rect: rect,
                                 by: CGPoint(x: 30, y: 20), in: bounds)
        #expect(slid.rect == CGRect(x: 80, y: 70, width: 100, height: 80))
        #expect(slid.anchor == CGPoint(x: 80, y: 70))
    }

    @Test func spaceWhileDrawingStopsAtThePictureEdge() {
        let rect = CGRect(x: 250, y: 50, width: 100, height: 80)
        let slid = Crop.slidDraw(anchor: CGPoint(x: 350, y: 130), rect: rect,
                                 by: CGPoint(x: 200, y: 0), in: bounds)
        #expect(slid.rect == CGRect(x: 300, y: 50, width: 100, height: 80))
        // Only as far as the box went: the anchor keeps its corner of it.
        #expect(slid.anchor == CGPoint(x: 400, y: 130))
    }
}

@Suite("Crop press, the rule Current keeps")
struct CropPressCurrentTests {
    @Test func withoutDrawingInsideAPressInsideMovesAndOutsideDraws() {
        let box = CGRect(x: 100, y: 100, width: 100, height: 100)
        #expect(Crop.press(at: CGPoint(x: 150, y: 150), cropRect: box, zoom: 1, spaceHeld: false,
                           drawsInside: false) == .move)
        #expect(Crop.press(at: CGPoint(x: 20, y: 20), cropRect: box, zoom: 1, spaceHeld: false,
                           drawsInside: false) == .draw)
        #expect(Crop.press(at: CGPoint(x: 100, y: 100), cropRect: box, zoom: 1, spaceHeld: false,
                           drawsInside: false) == .resize(.topLeft))
    }

    @Test func theFlagIsOnInNextAndNowhereElse() {
        let flag = FeatureCatalog.cropDrawsABoxFlag
        #expect(FeatureCatalog.defaultSettings(for: .next).isEnabled(flag))
        #expect(FeatureCatalog.flags(for: .next).contains { $0.name == flag })
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == flag })
        #expect(!FeatureCatalog.defaultSettings(for: .current).isEnabled(flag))
    }
}
