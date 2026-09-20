import AppKit
import PhotonzCore

/// The space an icon has to live inside, drawn on the canvas (Next,
/// `next-icon-frames`).
///
/// The rule it follows is written down: docs/design/mocks/shared/UX-PATTERNS.md
/// D16, "A guide draws over your work, and never gets into the picture".
///
/// Chrome, not content: drawn by this view rather than by the renderer, so it
/// can never land in an export, a copied picture or an SVG, and the document
/// carries nothing at all for it — the frame's size is the whole input.
///
/// Four things make it behave:
///
/// - **Never a traced border.** The margin is a WASH filling the band between
///   the frame's edge and the live area, and the square a boxy glyph fills is
///   four hairlines that run off the edges of the frame. Neither closes a
///   rectangle, so the selection outline is the only thing on the canvas that
///   draws a hard line round the edge of something, which is how you know what
///   your next gesture will act on. The first version traced the live area as
///   a dashed rectangle, and since a new icon frame arrives selected, the very
///   first thing anybody saw was two dashed rectangles a few points apart
///   meaning completely different things (task
///   `an-icon-frame-s-guides-stop-looking-like-a-secon`, UX-PATTERNS D16 rule
///   3). The circle keeps its dashes: a circle is not a selection and never
///   reads as one.
/// - **Dashes, over the drawing.** Everything else the canvas draws on a
///   picture is solid: the grid's hairlines, a column wash, a frame's edge. A
///   dash is the one mark nobody can mistake for something they drew, which
///   matters more here than anywhere else in the app, because on a 24 pixel
///   icon a guide and a stroke are the same size on screen.
/// - **An ink of its own, over a casing.** The canvas grid is the accent sunk
///   most of the way into grey; the columns are a warm red wash. These are
///   violet, which is neither, so a person with all three switched on sees
///   three things rather than one broken one. Under the violet goes a wider
///   stroke in the opposite tone, because the first version of this drew violet
///   alone and the center lines vanished the moment a shape was drawn across
///   them — which is the one place a guide has to survive, since checking what
///   you drew against the margin is the whole feature. On a pale surface the
///   casing is invisible and costs nothing; over a drawing it is what keeps the
///   dashes readable.
/// - **Only what is on screen.** A frame scrolled out of the window contributes
///   nothing, and a frame too small on screen to have an inside — zoomed far
///   out, an icon is a speck — draws nothing rather than a smudge.
extension CanvasNSView {

    /// Below this many view points across there is no room between the margin
    /// and the frame's own edge, and the guides read as a thickening of the
    /// edge rather than as a margin.
    private static let smallestDrawableIcon: CGFloat = 24

    /// How far apart the square's hairlines and the circle have to be ON
    /// SCREEN before they read as two guides rather than as one thickened one.
    /// Below it both are left off and the frame shows the margin wash and the
    /// center lines alone, which is the same rule the frame itself already
    /// follows when it gets too small to have an inside.
    private static let smallestGuideGap: CGFloat = 3

    /// How wide the casing under the dashes is. Wide enough to show either side
    /// of a one point line, narrow enough that on a pale surface, where it is
    /// invisible anyway, it costs nothing.
    private static let casingWidth: CGFloat = 3

    func refreshIconKeylineChrome() {
        guard framesEnabled, iconKeylines, let viewport, let document,
              document.hasIconFrames, bounds.width > 0.5, bounds.height > 0.5 else {
            hideIconKeylineChrome()
            return
        }
        // One sublayer per icon frame, because the ink depends on what that
        // frame is painted: a white icon frame takes a different strength from
        // a dark one, and two icons on one canvas can be painted differently.
        var drawn: [CAShapeLayer] = []
        for frame in document.frames {
            guard frame.isVisible, let box = liveCanvasBounds(of: frame.id),
                  let guides = IconKeylines.guides(in: box) else { continue }
            let onScreen = viewRect(forDocRect: box, in: viewport)
            guard onScreen.intersects(bounds),
                  onScreen.width >= Self.smallestDrawableIcon else { continue }

            // The margin: the band between the frame's edge and the live area,
            // washed. An even-odd path with the frame outside and the live
            // area as the hole, so the guide says "not in here" by covering
            // the gutter rather than by drawing a line somebody has to work
            // out which side of it they belong on.
            let outer = pixelAlignedFill(onScreen)
            let inner = pixelAlignedFill(viewRect(forDocRect: guides.liveArea, in: viewport))
            guard inner.width >= 2, inner.height >= 2 else { continue }
            let band = CGMutablePath()
            band.addRect(outer)
            band.addRect(inner)

            let path = CGMutablePath()
            for line in guides.centerGuideLines {
                addIconKeylineLine(line, to: path, in: viewport)
            }

            // The two shapes that make a boxy glyph and a round one look the
            // same size. They are the finest thing on the frame — the square
            // sits a single document point inside the live area — so they only
            // come out once there is enough room on screen to tell them apart.
            if iconKeylineShapesFit(frameSide: box.width, onScreenWidth: onScreen.width) {
                let circle = pixelAligned(viewRect(forDocRect: guides.circleKeyline, in: viewport))
                if circle.width >= 2, circle.height >= 2 { path.addEllipse(in: circle) }
                for line in guides.squareGuideLines {
                    addIconKeylineLine(line, to: path, in: viewport)
                }
            }

            // Wash first, then casing, then ink. The casing and the ink are
            // two strokes of the same path, so the dashes line up exactly and
            // the casing reads as a halo rather than as a second guide.
            let wash = iconKeylineLayer(reusing: drawn.count)
            wash.path = band
            wash.fillRule = .evenOdd
            wash.fillColor = iconKeylineWash(on: frame)
            wash.strokeColor = nil
            wash.lineWidth = 0
            wash.lineDashPattern = nil
            wash.isHidden = false
            drawn.append(wash)

            let casing = iconKeylineLayer(reusing: drawn.count)
            casing.path = path
            casing.fillColor = nil
            casing.strokeColor = iconKeylineCasing(on: frame)
            casing.lineWidth = Self.casingWidth
            casing.lineDashPattern = Self.dashPattern
            casing.isHidden = false
            drawn.append(casing)

            let shape = iconKeylineLayer(reusing: drawn.count)
            shape.path = path
            shape.fillColor = nil
            shape.strokeColor = iconKeylineInk(on: frame)
            shape.lineWidth = 1
            shape.lineDashPattern = Self.dashPattern
            shape.isHidden = false
            drawn.append(shape)
        }
        for spare in (iconKeylineLayerGroup.sublayers ?? []).dropFirst(drawn.count) {
            (spare as? CAShapeLayer)?.path = nil
            spare.isHidden = true
        }
        iconKeylineLayerGroup.isHidden = drawn.isEmpty
    }

    /// Whether the square and the circle have room to be themselves on screen.
    ///
    /// The square is inset from the live area by about a twenty-fourth of the
    /// frame, so on a 24 point icon at 100% that is one view point and the two
    /// dashed rectangles would land on top of each other. Zoomed in there is
    /// room, and an icon is drawn zoomed in.
    private func iconKeylineShapesFit(frameSide: CGFloat, onScreenWidth: CGFloat) -> Bool {
        guard frameSide > 0, onScreenWidth > 0 else { return false }
        let gap = IconKeylines.squareInset(forSide: frameSide) - IconKeylines.margin(forSide: frameSide)
        return gap * (onScreenWidth / frameSide) >= Self.smallestGuideGap
    }

    /// A rectangle on whole view points with its stroke centred on a device
    /// pixel, so a hairline is one crisp line rather than a two pixel smear —
    /// the same reason the grid and the column bands round.
    private func pixelAligned(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX.rounded() + 0.5, y: rect.minY.rounded() + 0.5,
               width: max(0, rect.width.rounded() - 1),
               height: max(0, rect.height.rounded() - 1))
    }

    /// A rectangle to FILL, on whole view points. No half point here: a fill
    /// wants its edges on the pixel boundary, where a stroke wants its centre
    /// on the pixel.
    private func pixelAlignedFill(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded(), minY = rect.minY.rounded()
        return CGRect(x: minX, y: minY,
                      width: max(0, rect.maxX.rounded() - minX),
                      height: max(0, rect.maxY.rounded() - minY))
    }

    /// One guide hairline, mapped onto the screen and snapped so it comes out
    /// as one crisp line. Axis aligned by construction, so the constant side
    /// lands on a pixel centre and the ends land on whole points.
    private func addIconKeylineLine(_ line: IconKeylineLine,
                                    to path: CGMutablePath,
                                    in viewport: Viewport) {
        let a = viewport.viewPoint(fromDocument: line.from)
        let b = viewport.viewPoint(fromDocument: line.to)
        if abs(a.x - b.x) <= abs(a.y - b.y) {
            let x = ((a.x + b.x) / 2).rounded() + 0.5
            path.move(to: CGPoint(x: x, y: min(a.y, b.y).rounded()))
            path.addLine(to: CGPoint(x: x, y: max(a.y, b.y).rounded()))
        } else {
            let y = ((a.y + b.y) / 2).rounded() + 0.5
            path.move(to: CGPoint(x: min(a.x, b.x).rounded(), y: y))
            path.addLine(to: CGPoint(x: max(a.x, b.x).rounded(), y: y))
        }
    }

    /// A long dash with a short gap. It is no longer what tells a guide from
    /// the selection — nothing dashed here traces a border any more, so there
    /// is nothing to confuse — but a dash still says "the app drew this, you
    /// did not", which is what it is for.
    private static let dashPattern: [NSNumber] = [5, 3]

    /// A guide layer, made once and then reused: a canvas of frames redraws on
    /// every scroll, and rebuilding layers per frame is how a scroll gets
    /// expensive. Every property that varies by role — wash, casing or ink —
    /// is set at the call site rather than here, because a reused layer may
    /// come back in a different role when the number of icon frames changes.
    private func iconKeylineLayer(reusing index: Int) -> CAShapeLayer {
        let existing = iconKeylineLayerGroup.sublayers ?? []
        if index < existing.count, let shape = existing[index] as? CAShapeLayer { return shape }
        let shape = CAShapeLayer()
        shape.fillColor = nil
        iconKeylineLayerGroup.addSublayer(shape)
        return shape
    }

    private func hideIconKeylineChrome() {
        guard !iconKeylineLayerGroup.isHidden else { return }
        for shape in iconKeylineLayerGroup.sublayers ?? [] {
            (shape as? CAShapeLayer)?.path = nil
            shape.isHidden = true
        }
        iconKeylineLayerGroup.isHidden = true
    }

    /// A violet hairline: deliberately neither the grid's cooled accent nor the
    /// columns' warm red, so all three on at once read as three things.
    ///
    /// The strength follows THE FRAME. A guide has to read against the surface
    /// it is lying on, and an icon frame paints its own: a white icon in a dark
    /// app is still white. So a dark frame takes a brighter violet, a light one
    /// a deeper one, and a frame you can see straight through is judged by the
    /// canvas behind it instead.
    private func iconKeylineInk(on frame: Layer) -> CGColor {
        let violet = surfaceIsPale(on: frame)
            ? NSColor(calibratedRed: 0.42, green: 0.26, blue: 0.85, alpha: 0.85)
            : NSColor(calibratedRed: 0.72, green: 0.60, blue: 1.0, alpha: 0.95)
        var ink = violet.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if let converted = violet.usingColorSpace(.sRGB) { ink = converted.cgColor }
        }
        return ink
    }

    /// The wash that fills the margin band. The same violet as the hairlines,
    /// sunk far enough that everything under it stays completely readable: it
    /// has to say "keep your drawing out of here" without hiding the bit of
    /// drawing that has strayed into it, which is the one thing somebody looks
    /// at the margin to check. Stronger on a dark frame than on a pale one,
    /// for the same reason the ink is.
    private func iconKeylineWash(on frame: Layer) -> CGColor {
        let violet = surfaceIsPale(on: frame)
            ? NSColor(calibratedRed: 0.42, green: 0.26, blue: 0.85, alpha: 0.13)
            : NSColor(calibratedRed: 0.72, green: 0.60, blue: 1.0, alpha: 0.18)
        var wash = violet.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if let converted = violet.usingColorSpace(.sRGB) { wash = converted.cgColor }
        }
        return wash
    }

    /// The stroke that goes UNDER the dashes, in the opposite tone: white
    /// behind a dark violet, black behind a pale one. On the frame's own
    /// surface it disappears; over anything drawn on the frame it is what stops
    /// the guide disappearing with it.
    private func iconKeylineCasing(on frame: Layer) -> CGColor {
        surfaceIsPale(on: frame)
            ? CGColor(gray: 1, alpha: 0.7)
            : CGColor(gray: 0, alpha: 0.45)
    }

    /// Whether the surface this frame's guides are lying on is a pale one. The
    /// frame's own paint when it has any, because a white frame in a dark app
    /// is still white, and the app's theme for a frame you can see through.
    private func surfaceIsPale(on frame: Layer) -> Bool {
        guard let surface = frame.group?.backgroundHex.flatMap({ RGBA(hex: $0) }),
              surface.a > 0.5 else { return !isDarkCanvasAppearance }
        return surface.relativeLuminance >= 0.5
    }

    private var isDarkCanvasAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// What the guides are drawing RIGHT NOW, read off the frames themselves,
    /// for a scripted walk to assert on.
    var playtestIconKeylineReport: String {
        guard framesEnabled else { return "frames off in Experiments" }
        guard iconKeylines else { return "icon keylines off" }
        guard let document else { return "no document" }
        let icons = document.frames.filter { IconKeylines.guides(in: $0.frame) != nil }
        guard !icons.isEmpty else { return "no icon frame in this document" }
        let names = icons.map { frame -> String in
            let guides = IconKeylines.guides(in: frame.frame)
            let live = guides?.liveArea ?? .zero
            let onScreen = liveCanvasBounds(of: frame.id).flatMap { box in
                viewport.map { port in viewRect(forDocRect: box, in: port) }
            }
            let shapes: String
            if let onScreen, iconKeylineShapesFit(frameSide: frame.frame.width,
                                                  onScreenWidth: onScreen.width) {
                let square = guides?.squareKeyline.map { Int($0.width) }
                shapes = " square \(square.map(String.init) ?? "none")"
                    + " circle \(Int(guides?.circleKeyline.width ?? 0))"
            } else {
                shapes = " shapes too close together to draw"
            }
            return "\(frame.name) \(Int(frame.frame.width))"
                + " live \(Int(live.width))×\(Int(live.height))"
                + " margin \(Int(IconKeylines.margin(forSide: frame.frame.width)))"
                + shapes
        }.joined(separator: " · ")
        return "\(names) · \(iconKeylineLayerGroup.isHidden ? "nothing drawn" : "drawn")"
    }
}
