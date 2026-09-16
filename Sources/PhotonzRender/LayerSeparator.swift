import CoreGraphics
import Foundation
import PhotonzCore

/// Takes a picture apart: every run of text and every box in it comes out as
/// its own layer, and the picture comes back with the space each one came from
/// filled in.
///
/// The pure decisions live in `PhotonzCore` — `TextRunSweep` says where the
/// runs are, `BoxSweep` says where the boxes are and which of them is really a
/// shape, `PatchDecision` says what goes in the hole. This is the part that has
/// to touch pixels: reading the ring around a piece, painting the fill, and
/// cutting a piece out of its background so what comes out is the WORDS, or the
/// BOX, and not a rectangle of whatever they were sitting on.
///
/// Full design: `docs/design/separate-into-layers.md`.
public enum LayerSeparator {

    /// One piece, cut out.
    public struct Piece: Sendable {
        /// What kind of thing it is, which is all the naming needs to know.
        public enum Kind: Sendable {
            case text
            case box
        }

        /// What it turned out to be made of.
        public enum Body: Sendable {
            /// Pixels, with everything that was behind them transparent.
            case picture(CGImage)
            /// A real rounded rectangle, in image pixels, that can be resized
            /// and repainted rather than stretched.
            case shape(BoxSweep.Shape)
        }

        /// Where it sat in the source picture, in image pixels, top-left
        /// origin.
        public let rect: CGRect
        public let kind: Kind
        public let body: Body
        /// The shadow this piece was sitting on in the picture, read back as a
        /// real shadow so it moves with the piece — and so the space it came
        /// from is plain page again. Nil whenever the picture did not say
        /// clearly enough what the shadow was, which leaves the piece flat
        /// rather than wearing a guess (`ShadowRead`).
        public let shadow: ShadowStyle?

        public init(rect: CGRect, kind: Kind, body: Body, shadow: ShadowStyle? = nil) {
            self.rect = rect
            self.kind = kind
            self.body = body
            self.shadow = shadow
        }

        /// The bitmap, when it is one.
        public var image: CGImage? {
            if case .picture(let image) = body { return image }
            return nil
        }
    }

    public struct Result: Sendable {
        /// The picture with every accepted piece's space filled in.
        public let background: CGImage
        /// The pieces that came out, BOTTOM-MOST FIRST: the boxes outermost
        /// first and then down the page, then the runs of text in reading
        /// order. That order is the stacking order, and it is the only one that
        /// works — a row sits ON the card it came off and a label sits ON the
        /// button, so a card laid over its own rows would hide them the instant
        /// the command finished.
        public let pieces: [Piece]
        /// How many things were found but left in the picture, because their
        /// surroundings did not justify a fill or the app could not read them
        /// confidently enough to cut them.
        public let skipped: Int
        /// How many were read perfectly well and left in the picture anyway,
        /// because one command only takes so much out of one screenshot
        /// (`SeparateBudget`). These are a different sentence from `skipped`:
        /// they are still there to be taken, and the next run takes them.
        public let crowded: Int
        /// The spaces filled in behind the pieces. They never overlap, which is
        /// what "no region is patched twice" means and what a test can check.
        public let patched: [CGRect]

        public init(background: CGImage, pieces: [Piece], skipped: Int,
                    crowded: Int = 0, patched: [CGRect] = []) {
            self.background = background
            self.pieces = pieces
            self.skipped = skipped
            self.crowded = crowded
            self.patched = patched
        }

        /// Everything still in the picture when the command finished, for
        /// either reason. The number the pill prints, and the one a test can
        /// check against what the sweep found.
        public var left: Int { skipped + crowded }

        /// The pieces arranged the way the screen was: a label that sits in a
        /// button is a child of that button, a row inside a card sits under the
        /// card, and a piece that belongs to nothing stays at the top. Indices
        /// into `pieces`, outermost first, in the same order.
        ///
        /// The rule is `LayerNesting` and it is pure: this is only where the
        /// pieces meet it, so the tree a test reads off a real capture is the
        /// same tree the app builds layers from.
        public var nested: [LayerNesting.Node] { LayerNesting.nest(pieces.map(\.rect)) }

        /// Just the runs of text.
        public var runs: [Piece] { pieces.filter { $0.kind == .text } }
        /// Just the boxes.
        public var boxes: [Piece] { pieces.filter { $0.kind == .box } }
    }

    /// Everything read off the picture about one box before anything is cut.
    ///
    /// The whole point of writing it down rather than acting on it straight
    /// away: a row inside a card has to be READ while the card is still whole,
    /// and the card has to be CUT once the row is out of it. One list, filled in
    /// outermost first and spent innermost first.
    private struct BoxPlan {
        let box: BoxSweep.Box
        /// The box plus whatever its shadow reaches: the space to be filled in.
        let grown: CGRect
        /// What goes in that space — the page for a card, the card's own colour
        /// for a row inside it.
        let fill: PatchFill
        let shadow: ShadowRead.Reading?
    }

    /// How much of the visible gap a run of text is grown by before anything is
    /// sampled or painted, as a fraction of it: two pixels on a 2x capture.
    ///
    /// Without it the antialiased rim of the glyphs sits just OUTSIDE the box.
    /// It would poison the ring reading — a pixel a tenth of the way into a
    /// letter is not ink by the 15% floor, but it is 25 levels off the panel
    /// colour, which is a dozen times the tolerance the flat case runs at — and
    /// it would be left behind in the picture as a faint grey ghost of the word.
    public static let haloRatio = 1.0 / 8

    /// How wide the ring around a piece is, in pixels. Wide enough for a real
    /// reading, narrow enough that it is still the background right THERE.
    public static let ringWidth = 3

    /// How far a run's ink must sit from its background before the app will
    /// claim to know which is which. Under this the cut would be a guess at
    /// what is letter and what is panel, so the run is left where it is.
    public static let minimumContrast = 0.1

    /// Every run of text in `image`, cut out, with `image` repaired behind
    /// them, and no boxes. What the first slice of this feature did, kept as
    /// its own entry point because it is the half that has nothing to do with
    /// colour.
    public static func separateText(_ image: CGImage, luma: LumaField,
                                    gap: Double = TextLineBounds.defaultGap,
                                    minElement: Double = ElementBounds.defaultMinElement)
        -> Result? {
        separate(image, luma: luma, gap: gap, minElement: minElement, boxes: false)
    }

    /// Every run of text and every box in `image`, cut out, with `image`
    /// repaired behind them. Nil when the picture cannot be read at all.
    ///
    /// `luma` is the brightness field for this exact image — the one already
    /// cached beside its edge map, so a screenshot that has been measured pays
    /// nothing to be separated.
    ///
    /// The order is not an accident. The text comes out FIRST and its holes are
    /// filled before a single box is looked at, so a button whose label has
    /// just been lifted off it is one flat colour by the time it is read — and
    /// comes out as a real blue rounded rectangle you can resize, rather than
    /// as a picture of a button with words baked into it.
    public static func separate(_ image: CGImage, luma: LumaField,
                                gap: Double = TextLineBounds.defaultGap,
                                minElement: Double = ElementBounds.defaultMinElement,
                                boxes: Bool = true) -> Result? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, luma.width == w, luma.height == h else { return nil }
        guard var pixels = read(image) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)

        var runs: [Piece] = []
        var boxPieces: [Piece] = []
        var patched: [CGRect] = []
        var skipped = 0
        var crowded = 0

        // MARK: The runs of text
        let sweep = TextRunSweep.sweep(in: luma, gap: gap, minElement: minElement)
        // A whole screen is not a settings pane: a dense web page offers
        // hundreds of runs, and a layers list with hundreds of rows in it is a
        // wall rather than a list. The biggest ones come out, the rest stay in
        // the picture and are counted, and the next run takes them.
        let chosen = SeparateBudget.choose(sweep.runs, limit: SeparateBudget.maxTextRuns)
        // Plus whatever the sweep itself had to stop short of, which is still
        // sitting in the picture and still has to be counted.
        crowded += chosen.crowdedOut + sweep.beyondLimit
        // Everything the text sweep found, taken or not. A word left in the
        // picture must not come back round as a box, so the box pass is told
        // about the ones that stayed as well as the ones that came out.
        let spokenFor = sweep.runs
        let halo = max(1, Int((haloRatio * gap).rounded()))
        var fills: [(rect: CGRect, fill: PatchFill)] = []
        // Every reading comes off the ORIGINAL pixels: a run is cut and its
        // ring is sampled before a single hole is filled, so one patch can
        // never become another run's idea of what the background was.
        for run in chosen.kept.map({ sweep.runs[$0] }) {
            let box = run.insetBy(dx: CGFloat(-halo), dy: CGFloat(-halo))
                .integral.intersection(bounds)
            guard !box.isNull, box.width >= 1, box.height >= 1 else { skipped += 1; continue }
            guard let ring = ring(around: box, in: pixels, width: w, height: h,
                                  keeping: { !sweep.ink.isInk($0, $1) }),
                  let fill = PatchDecision.decide(ring) else { skipped += 1; continue }
            guard let cut = cut(box, from: pixels, width: w, over: fill) else {
                skipped += 1
                continue
            }
            runs.append(Piece(rect: box, kind: .text, body: .picture(cut)))
            fills.append((box, fill))
        }
        for (rect, fill) in fills {
            paint(fill, into: &pixels, width: w, rect: rect)
            patched.append(rect)
        }

        // MARK: The boxes
        if boxes {
            let field = PixelField(width: w, height: h, samples: pixels)
            let found = BoxSweep.sweep(in: field, avoiding: spokenFor, minElement: minElement)
            // Same ceiling, its own much smaller number: a box is a container,
            // and thirty groups to open is already more than a list wants.
            //
            // Spent OUTERMOST FIRST. A screenshot with more cards in it than the
            // ceiling allows should come apart into cards, not into eight cards
            // and the switches off the ninth, so every level takes what is left
            // after the one above it — and a box sitting on a card that did not
            // come out is not offered at all.
            var keptIndexes: [Int] = []
            var keptIslands: Set<Int32> = []
            let deepest = found.boxes.map(\.depth).max() ?? 1
            for depth in 1...max(1, deepest) {
                let level = found.boxes.enumerated().filter { $0.element.depth == depth }
                let offered = level.filter {
                    $0.element.parent == 0 || keptIslands.contains($0.element.parent)
                }
                crowded += level.count - offered.count
                let room = SeparateBudget.maxBoxes - keptIndexes.count
                guard room > 0 else { crowded += offered.count; continue }
                let choice = SeparateBudget.choose(offered.map(\.element.rect), limit: room)
                crowded += choice.crowdedOut
                for index in choice.kept {
                    keptIndexes.append(offered[index].offset)
                    keptIslands.insert(offered[index].element.island)
                }
            }
            let takeable = keptIndexes.sorted()

            // Pass one, OUTERMOST FIRST: everything a box needs read off the
            // picture before a single pixel of it is cut or painted. Reading it
            // all up front is what lets a row be cut out of its card and the
            // card still come out whole — the row's own colour is known before
            // the card is asked what it looks like without it.
            var plans: [BoxPlan] = []
            var planned: Set<Int32> = []
            for box in takeable.map({ found.boxes[$0] }) {
                // A box sitting on a box that is staying in the picture stays
                // too. Taking the switch off a card that never came out would
                // leave a hole in the screenshot with nothing to fill it.
                guard box.parent == 0 || planned.contains(box.parent) else {
                    skipped += 1
                    continue
                }
                // A card usually sits on a soft shadow, and a shadow is the one
                // thing around a box that neither agrees with itself nor ramps
                // evenly — so without reading it, every shadowed card in every
                // screenshot stays in the picture. Read as a real shadow it
                // comes off WITH the card, and the space underneath is plain
                // page again rather than a grey halo of a card that has moved.
                let surround: (Int, Int) -> Bool = { found.isSurround($0, $1, of: box) }
                let shadow = ShadowRead.read(box.rect, in: field, isBackdrop: surround)
                let out = shadow.map { max(1, Int($0.reach.rounded(.up))) } ?? 1
                let close = box.rect.insetBy(dx: CGFloat(-out), dy: CGFloat(-out))
                    .integral.intersection(bounds)
                guard !close.isNull else { skipped += 1; continue }
                // A box's own edge is not always something the sweep can tell
                // from the page: on a dark panel a field's edge sits eight
                // levels off the panel with an antialiased step between, which
                // is under `BoxSweep.colorTolerance` all the way across, so the
                // two chain into ONE patch of colour and the edge counts as
                // background. The box's island then stops inside its own edge
                // and the band read just outside it is that edge — one row of a
                // colour that is not the page, which refuses the reading and
                // leaves the box in the picture.
                //
                // So when the band right against the box will not agree, step
                // off it and read again a little further out, up to the
                // thickest edge the app will believe in. Nothing is loosened by
                // this: the reading still has to be one flat colour or one even
                // ramp, and every pixel in the band still has to be background.
                // The only thing that changes is WHICH background pixels are
                // asked, and stepping over a neighbour is not a risk because a
                // neighbour is an island and was never in the band to begin
                // with.
                //
                // A box sitting on ANOTHER BOX never steps. The mistake being
                // undone here is a page-level one — a box's edge chaining into
                // the page's own patch of colour — and inside a box the
                // surround is not a patch of colour at all, it is the parent's
                // own pixels. Stepping there would step over the one thing that
                // keeps a knob inside its switch: something that nearly fills
                // its holder has no clean ring of the holder to be read
                // against, and that is how the app knows it is a part rather
                // than a thing.
                //
                // Whatever it steps over comes out WITH the box, because that
                // is what it just decided the band is: the box grows to take
                // it, so the repair covers it and the ring stays anchored to
                // the rect that is about to be painted. Without that the box
                // leaves a ghost of its own edge behind — the four fields on
                // the inspector crop came out and left a hairline rectangle
                // where each of them had been.
                let steps = box.parent == 0 ? BoxSweep.maxBorderWidth : 0
                var reading: (grown: CGRect, fill: PatchFill)?
                var last = CGRect.null
                for step in 0...steps {
                    let trying = close.insetBy(dx: CGFloat(-step), dy: CGFloat(-step))
                        .integral.intersection(bounds)
                    // Against the picture's own edge the box stops growing, and
                    // asking the same band again would only fail again.
                    guard !trying.isNull, trying != last else { break }
                    last = trying
                    guard let ring = ring(around: trying, in: pixels, width: w, height: h,
                                          keeping: surround),
                          let fill = PatchDecision.decide(ring) else { continue }
                    reading = (trying, fill)
                    break
                }
                guard let (grown, fill) = reading else { skipped += 1; continue }
                guard !patched.contains(where: { $0.intersects(grown) && !grown.contains($0) }),
                      // Overlapping another box is still refused; HOLDING one,
                      // or being held by one, is the whole point of this pass.
                      !plans.contains(where: { $0.grown.intersects(grown)
                          && !grown.contains($0.grown) && !$0.grown.contains(grown) }),
                      shadow == nil || onlySurround(grown, outside: box.rect, is: surround)
                else { skipped += 1; continue }
                planned.insert(box.island)
                plans.append(BoxPlan(box: box, grown: grown, fill: fill, shadow: shadow))
            }

            // Pass two, INNERMOST FIRST: cut. A box is cut with the space each
            // of its own children came from painted in that box's colour, so a
            // card comes out whole rather than with a switch-shaped hole in it,
            // and the switch is not in the picture twice.
            var bodies: [Int32: Piece.Body] = [:]
            for depth in stride(from: plans.map(\.box.depth).max() ?? 0, through: 1, by: -1) {
                for plan in plans where plan.box.depth == depth {
                    let box = plan.box
                    if let shape = box.shape {
                        bodies[box.island] = .shape(shape)
                        continue
                    }
                    let holes = plans
                        .filter { $0.box.parent == box.island && bodies[$0.box.island] != nil }
                        .map { (rect: $0.grown, fill: $0.fill) }
                    // What was under the box's own antialiased rim. With a
                    // shadow that is the page ALREADY DARKENED by the shadow,
                    // not the bare page: read against the bare page a card's
                    // edge comes out too faint and dissolves into whatever it
                    // is dragged onto.
                    let under = background(plan.fill, over: plan.grown, shadow: plan.shadow,
                                           box: box.rect)
                    guard let cut = cutBox(box, from: pixels, width: w, height: h,
                                           islands: found, under: under, holes: holes)
                    else { continue }
                    bodies[box.island] = .picture(cut)
                }
            }

            // Pass three, outermost first again: who actually came out. A box
            // whose holder could not be cut stays in the picture with it.
            var taken: Set<Int32> = []
            var boxFills: [(rect: CGRect, fill: PatchFill)] = []
            for plan in plans {
                guard let body = bodies[plan.box.island],
                      plan.box.parent == 0 || taken.contains(plan.box.parent)
                else { skipped += 1; continue }
                taken.insert(plan.box.island)
                boxPieces.append(Piece(rect: plan.box.rect, kind: .box, body: body,
                                       shadow: plan.shadow?.style))
                // Only what was sitting on the PAGE leaves a space in it. A row
                // came out of its card, and the card's own space is painted over
                // the lot of it in one go.
                if plan.box.depth == 1 { boxFills.append((plan.grown, plan.fill)) }
            }
            for (rect, fill) in boxFills {
                paint(fill, into: &pixels, width: w, rect: rect)
                // A box swallows the holes its own labels left: those pixels
                // are painted once, by the box, not twice.
                patched.removeAll { rect.contains($0) }
                patched.append(rect)
            }
        }

        guard !patched.isEmpty else {
            return Result(background: image, pieces: [], skipped: skipped, crowded: crowded)
        }
        guard let background = makeImage(pixels, width: w, height: h) else { return nil }
        return Result(background: background, pieces: boxPieces + runs, skipped: skipped,
                      crowded: crowded, patched: patched)
    }

    // MARK: - The ring

    /// The background just outside `box`: a band `ringWidth` wide on all four
    /// sides, keeping only the pixels `keeping` allows — the ones the text
    /// sweep did not call ink, or the ones the box sweep called background — so
    /// a button's border or a neighbouring word never votes on what is behind
    /// this one.
    static func ring(around box: CGRect, in pixels: [UInt8], width w: Int, height h: Int,
                     keeping allowed: (Int, Int) -> Bool) -> PatchRing? {
        let x0 = Int(box.minX), y0 = Int(box.minY)
        let bw = Int(box.width), bh = Int(box.height)
        guard bw > 0, bh > 0 else { return nil }
        var samples: [PatchRing.Sample] = []
        samples.reserveCapacity(2 * (bw + bh) * ringWidth)

        func take(_ x: Int, _ y: Int) {
            guard x >= 0, y >= 0, x < w, y < h, allowed(x, y) else { return }
            let i = (y * w + x) * 4
            let a = Double(pixels[i + 3]) / 255
            // Premultiplied on the way in, so a translucent pixel has to be
            // divided back out before it can be compared with an opaque one.
            let scale = a > 0 ? 1 / a : 0
            samples.append(PatchRing.Sample(
                u: (Double(x - x0) + 0.5) / Double(bw),
                v: (Double(y - y0) + 0.5) / Double(bh),
                color: RGBA(r: Double(pixels[i]) / 255 * scale,
                            g: Double(pixels[i + 1]) / 255 * scale,
                            b: Double(pixels[i + 2]) / 255 * scale,
                            a: a)))
        }
        for band in 1...ringWidth {
            for x in (x0 - band)...(x0 + bw - 1 + band) {
                take(x, y0 - band)
                take(x, y0 + bh - 1 + band)
            }
            for y in y0...(y0 + bh - 1) {
                take(x0 - band, y)
                take(x0 + bw - 1 + band, y)
            }
        }
        return samples.isEmpty ? nil : PatchRing(samples: samples)
    }

    // MARK: - Cutting the letters out

    /// `box`'s pixels with the background unmixed back out of them: full alpha
    /// inside a stroke, partial on an antialiased rim, nothing on the panel.
    ///
    /// There is no OCR here, so this is an unmix rather than a trace. Every
    /// pixel is read as `alpha` of some ink over the background that is about to
    /// be painted under it, `alpha` comes from how far the pixel sits from that
    /// background against how far the run's own ink does, and the ink colour is
    /// divided back out — so two-tone or syntax-coloured words keep their own
    /// colours instead of being repainted one flat tone.
    ///
    /// Nil when the run's ink barely differs from its background: the app does
    /// not know which is which, so it does not claim to.
    static func cut(_ box: CGRect, from pixels: [UInt8], width w: Int,
                    over fill: PatchFill) -> CGImage? {
        let x0 = Int(box.minX), y0 = Int(box.minY)
        let bw = Int(box.width), bh = Int(box.height)
        guard bw > 0, bh > 0 else { return nil }

        // How far each pixel sits from what will be behind it, and how far the
        // run's ink does — the brightest tenth of those distances, so one
        // stray pixel cannot set the scale and a thin stroke still reaches it.
        var distance = [Double](repeating: 0, count: bw * bh)
        var background = [RGBA](repeating: RGBA(r: 0, g: 0, b: 0, a: 0), count: bw * bh)
        for y in 0..<bh {
            for x in 0..<bw {
                let pixel = color(pixels, w, x0 + x, y0 + y)
                let under = fill.color(u: (Double(x) + 0.5) / Double(bw),
                                       v: (Double(y) + 0.5) / Double(bh))
                background[y * bw + x] = under
                distance[y * bw + x] = apart(pixel, under)
            }
        }
        // The top fiftieth rather than the very top: a stroke's interior is
        // hundreds of pixels, so this lands inside one, while a single stray
        // saturated pixel cannot set the scale for the whole run.
        let ranked = distance.sorted()
        let contrast = ranked[Int(Double(ranked.count - 1) * 0.98)]
        guard contrast >= minimumContrast else { return nil }

        var out = [UInt8](repeating: 0, count: bw * bh * 4)
        for y in 0..<bh {
            for x in 0..<bw {
                let index = y * bw + x
                let alpha = min(distance[index] / contrast, 1)
                guard alpha > 0.004 else { continue }
                write(unmix(color(pixels, w, x0 + x, y0 + y), over: background[index],
                            alpha: alpha),
                      alpha: alpha, into: &out, at: index)
            }
        }
        return makeImage(out, width: bw, height: bh)
    }

    // MARK: - Cutting a box out

    /// A box's pixels, keeping EXACTLY the pixels that are the box — rounded
    /// corners and all — and nothing of the page it was sitting on.
    ///
    /// A box is not unmixed the way a run of text is. The sweep already said
    /// which pixels are the box, so there is nothing to guess about the inside:
    /// it comes out whole, switch knobs and dividers and all. Only the rim the
    /// renderer antialiased is worked out, and each of those pixels is measured
    /// against the paint right beside it, so a card that is barely lighter than
    /// its page keeps its edge instead of dissolving into it.
    ///
    /// `holes` are the spaces the boxes sitting ON this one have just been cut
    /// out of, each with the colour this box is painted there. They are filled
    /// in rather than read, so a card whose switch has come out comes out itself
    /// as a whole card — no switch baked into it, and no switch-shaped hole.
    static func cutBox(_ box: BoxSweep.Box, from pixels: [UInt8], width w: Int, height h: Int,
                       islands: BoxSweep.Sweep, under: (Int, Int) -> RGBA,
                       holes: [(rect: CGRect, fill: PatchFill)] = []) -> CGImage? {
        let x0 = Int(box.rect.minX), y0 = Int(box.rect.minY)
        let bw = Int(box.rect.width), bh = Int(box.rect.height)
        guard bw > 0, bh > 0 else { return nil }
        // `owns` rather than `isIsland`: the pixels of a row inside this card
        // are labelled the row's, and they are still the card's space.
        func mine(_ x: Int, _ y: Int) -> Bool { islands.owns(x0 + x, y0 + y, box.island) }
        func rim(_ x: Int, _ y: Int) -> Bool {
            mine(x, y) && (!mine(x - 1, y) || !mine(x + 1, y)
                || !mine(x, y - 1) || !mine(x, y + 1))
        }
        /// This box's own colour where a child was, or nil where there was none.
        func patch(_ px: Int, _ py: Int) -> RGBA? {
            let point = CGPoint(x: Double(px) + 0.5, y: Double(py) + 0.5)
            guard let hole = holes.first(where: { $0.rect.contains(point) }) else { return nil }
            return hole.fill.color(u: (point.x - hole.rect.minX) / hole.rect.width,
                                   v: (point.y - hole.rect.minY) / hole.rect.height)
        }

        var out = [UInt8](repeating: 0, count: bw * bh * 4)
        var drawn = 0
        for y in 0..<bh {
            for x in 0..<bw where mine(x, y) {
                let index = y * bw + x
                let pixel = patch(x0 + x, y0 + y) ?? color(pixels, w, x0 + x, y0 + y)
                let under = under(x0 + x, y0 + y)
                var alpha = 1.0
                if rim(x, y) {
                    // The paint beside it, which is what a fully covered pixel
                    // of this edge looks like.
                    var beside = 0.0
                    for dy in -1...1 {
                        for dx in -1...1 where mine(x + dx, y + dy) && !rim(x + dx, y + dy) {
                            beside = max(beside, apart(color(pixels, w, x0 + x + dx,
                                                             y0 + y + dy), under))
                        }
                    }
                    if beside > 0 { alpha = min(apart(pixel, under) / beside, 1) }
                }
                guard alpha > 0.004 else { continue }
                write(unmix(pixel, over: under, alpha: alpha), alpha: alpha,
                      into: &out, at: index)
                drawn += 1
            }
        }
        guard drawn > 0 else { return nil }
        return makeImage(out, width: bw, height: bh)
    }

    // MARK: - What was behind a box

    /// Whether everything the repair will paint over, outside the box itself,
    /// is what the box was sitting on — the page for a card, the card's own
    /// paint for a row inside it.
    ///
    /// Asked only of a box with a shadow, because that is the one whose repair
    /// reaches: a shadow's reach can be seventeen pixels, and painting that
    /// over a control sitting eight pixels below the card would erase it. A box
    /// whose repair would reach anything else is left in the picture instead.
    static func onlySurround(_ grown: CGRect, outside box: CGRect,
                             is surround: (Int, Int) -> Bool) -> Bool {
        for y in Int(grown.minY)..<Int(grown.maxY) {
            for x in Int(grown.minX)..<Int(grown.maxX) {
                guard !box.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) else { continue }
                guard surround(x, y) else { return false }
            }
        }
        return true
    }

    /// What the picture looked like under a box, pixel by pixel, in IMAGE
    /// coordinates: the fill that is about to be painted into the space, plus
    /// whatever the box's own shadow was darkening.
    static func background(_ fill: PatchFill, over grown: CGRect,
                           shadow: ShadowRead.Reading?, box: CGRect) -> (Int, Int) -> RGBA {
        if let shadow { return { x, y in shadow.background(at: x, y: y, of: box) } }
        return { x, y in
            fill.color(u: (Double(x) + 0.5 - Double(grown.minX)) / Double(grown.width),
                       v: (Double(y) + 0.5 - Double(grown.minY)) / Double(grown.height))
        }
    }

    // MARK: - Reading and writing one pixel

    /// One pixel of a premultiplied buffer, with the alpha divided back out.
    private static func color(_ pixels: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> RGBA {
        let i = (y * w + x) * 4
        let a = Double(pixels[i + 3]) / 255
        let scale = a > 0 ? 1 / a : 0
        return RGBA(r: Double(pixels[i]) / 255 * scale, g: Double(pixels[i + 1]) / 255 * scale,
                    b: Double(pixels[i + 2]) / 255 * scale, a: a)
    }

    /// The largest single-channel difference between two colours.
    private static func apart(_ a: RGBA, _ b: RGBA) -> Double {
        max(max(abs(a.r - b.r), abs(a.g - b.g)), max(abs(a.b - b.b), abs(a.a - b.a)))
    }

    /// The paint that, laid at `alpha` over `background`, gives this pixel.
    private static func unmix(_ pixel: RGBA, over background: RGBA, alpha: Double) -> RGBA {
        func ink(_ value: Double, _ behind: Double) -> Double {
            min(max((value - (1 - alpha) * behind) / alpha, 0), 1)
        }
        return RGBA(r: ink(pixel.r, background.r), g: ink(pixel.g, background.g),
                    b: ink(pixel.b, background.b), a: 1)
    }

    /// One pixel into a premultiplied buffer, matching the context it is drawn
    /// into.
    private static func write(_ color: RGBA, alpha: Double, into out: inout [UInt8],
                              at index: Int) {
        let o = index * 4
        out[o] = UInt8((color.r * alpha * 255).rounded())
        out[o + 1] = UInt8((color.g * alpha * 255).rounded())
        out[o + 2] = UInt8((color.b * alpha * 255).rounded())
        out[o + 3] = UInt8((alpha * 255).rounded())
    }

    // MARK: - Painting the repair

    static func paint(_ fill: PatchFill, into pixels: inout [UInt8], width w: Int,
                      rect: CGRect) {
        let x0 = Int(rect.minX), y0 = Int(rect.minY)
        let bw = Int(rect.width), bh = Int(rect.height)
        guard bw > 0, bh > 0 else { return }
        for y in 0..<bh {
            for x in 0..<bw {
                let color = fill.color(u: (Double(x) + 0.5) / Double(bw),
                                       v: (Double(y) + 0.5) / Double(bh))
                let a = min(max(color.a, 0), 1)
                let i = ((y0 + y) * w + x0 + x) * 4
                func byte(_ value: Double) -> UInt8 {
                    UInt8((min(max(value, 0), 1) * a * 255).rounded())
                }
                pixels[i] = byte(color.r)
                pixels[i + 1] = byte(color.g)
                pixels[i + 2] = byte(color.b)
                pixels[i + 3] = UInt8((a * 255).rounded())
            }
        }
    }

    // MARK: - Bitmaps

    /// `image` as premultiplied sRGB bytes, row-major, top-left origin.
    static func read(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: w, height: h,
                                          bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drew ? pixels : nil
    }

    /// Bytes back into a bitmap. The context owns its own storage and the rows
    /// are copied in one at a time against ITS stride, so nothing depends on
    /// the buffer outliving the call or on Core Graphics choosing the row
    /// padding we happened to assume.
    static func makeImage(_ pixels: [UInt8], width w: Int, height h: Int) -> CGImage? {
        guard w > 0, h > 0, pixels.count == w * h * 4,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        let stride = context.bytesPerRow
        pixels.withUnsafeBytes { source in
            guard let base = source.baseAddress else { return }
            for y in 0..<h {
                memcpy(data.advanced(by: y * stride), base.advanced(by: y * w * 4), w * 4)
            }
        }
        return context.makeImage()
    }
}
