import CoreGraphics
import Foundation

/// Every BOX in a picture: a button, a card, a bar, a row — the things a person
/// would reach out and move if the screenshot were the real thing.
///
/// The rule, in one sentence: **a box is something sitting on the picture's own
/// background.** A screenshot is painted the way UI is painted, one flat colour
/// behind everything, and whatever interrupts that colour is a thing. The page
/// itself is not a thing; nor is anything the frame cut in half; nor is what
/// sits on top of a box, because that travels with the box it is on.
///
/// That rule is asked TWICE. Once of the page, which gives the cards and the
/// buttons; then again inside every box it gave, where the box's own paint
/// plays the part the page played and whatever interrupts it is a thing on the
/// box. That is how a row inside a card, or a switch on a row, gets a layer of
/// its own instead of being baked into a flat picture of the card.
///
/// It stops at two (`maxBoxDepth`). WHICH of the nested rungs in a screenshot
/// are worth becoming layers is the question this feature lives or dies on: a
/// settings pane has a rung for the window, one for the pane, one for every
/// group and one for every row, and all of them as a flat pile is a tree nobody
/// wants. Two levels, nested, is the cards and what is sitting on them — and a
/// card that closes up into one row is SHORTER in the layers list than the flat
/// list was.
///
/// Two things were tried first and measured, and both are written down here so
/// nobody spends the afternoon again:
///
/// - `ElementBounds.candidates` is the measure tool's ladder and looks like the
///   answer. Probed on a grid over the 1440x960 fixture it costs 7 ms a probe,
///   37 seconds for the picture, and returns 320 overlapping rungs — every pair
///   of agreeing horizontal boundaries, so two rows, three rows, a card, a card
///   group. It is built to answer "what is under the pointer", where being
///   generous is right; sweeping a whole picture is the opposite job.
/// - `TextRunSweep`'s own ink components already know a box when they see one
///   (`isBox`). But ink is measured against a 33 px box mean, so a box's edges
///   read several pixels inside where they really are, and only boxes with more
///   than 15% contrast are found at all. Good enough to keep a switch out of the
///   text layers, nowhere near good enough to cut one out.
///
/// Full design: `docs/design/separate-into-layers.md`.
public enum BoxSweep {

    /// A box that turned out to be a real shape rather than a picture: one flat
    /// colour, optionally one plain edge, with its corners rounded the way they
    /// were in the screenshot.
    ///
    /// Only ever filled in when the picture SAYS so. A ramp is not a flat fill,
    /// a two-tone inside is not a flat fill, and an edge that varies is not an
    /// edge — all three come back as a picture instead, because a shape that is
    /// nearly right is worse than pixels that are exactly right.
    public struct Shape: Equatable, Sendable {
        /// What the inside is painted.
        public let fill: RGBA
        /// How round each corner is, in image pixels.
        public let radii: CornerRadii
        /// How thick the edge is, in image pixels. Zero when there is none.
        public let borderWidth: CGFloat
        /// What the edge is painted, or nil when there is none.
        public let borderColor: RGBA?

        public init(fill: RGBA, radii: CornerRadii, borderWidth: CGFloat = 0,
                    borderColor: RGBA? = nil) {
            self.fill = fill
            self.radii = radii
            self.borderWidth = borderWidth
            self.borderColor = borderColor
        }
    }

    /// One box.
    public struct Box: Equatable, Sendable {
        /// Where it sits, in image pixels, top-left origin.
        public let rect: CGRect
        /// Which island in `Sweep.islands` its pixels carry, so the exact shape
        /// — rounded corners and all — can be cut rather than a rectangle of
        /// picture.
        public let island: Int32
        /// The shape it can honestly be turned into, or nil when it has to stay
        /// a picture.
        public let shape: Shape?
        /// The island of the box this one is SITTING ON, or 0 when it is
        /// sitting on the page. A row inside a card carries the card's island,
        /// which is what says where its edge has to be read from and what has
        /// to be painted into the space it leaves.
        public let parent: Int32
        /// How many boxes deep it is: 1 for a box on the page, 2 for a box on
        /// that one.
        public let depth: Int

        public init(rect: CGRect, island: Int32, shape: Shape?,
                    parent: Int32 = 0, depth: Int = 1) {
            self.rect = rect
            self.island = island
            self.shape = shape
            self.parent = parent
            self.depth = depth
        }
    }

    /// What the sweep found: the boxes, which pixel belongs to which, and which
    /// pixels are the background they are sitting on.
    public struct Sweep: Sendable {
        public let boxes: [Box]
        /// One label per pixel: the DEEPEST island it belongs to, 0 for none.
        /// A pixel of a row inside a card carries the row, not the card, so a
        /// row can be cut out on its own; `owns` is what answers the other
        /// question, whether the card has it.
        public let islands: [Int32]
        /// 1 where the pixel is part of a background rather than a thing on it.
        /// What the patch reads its ring from, so a neighbouring control can
        /// never vote on what is behind this one.
        public let backdrop: [UInt8]
        /// Which island holds each island: `ancestors[id - 1]` is the island
        /// that one is sitting on, 0 when it is sitting on the page. Empty when
        /// nothing was found inside anything, which is every picture the sweep
        /// only ever read one level of.
        public let ancestors: [Int32]
        public let width: Int
        public let height: Int

        public init(boxes: [Box], islands: [Int32], backdrop: [UInt8],
                    ancestors: [Int32] = [], width: Int, height: Int) {
            self.boxes = boxes
            self.islands = islands
            self.backdrop = backdrop
            self.ancestors = ancestors
            self.width = width
            self.height = height
        }

        public static let empty = Sweep(boxes: [], islands: [], backdrop: [],
                                        width: 0, height: 0)

        /// Whether the pixel belongs to that island ITSELF. A pixel of a row
        /// inside a card is the row's, not the card's. Outside the picture is
        /// no.
        public func isIsland(_ x: Int, _ y: Int, _ id: Int32) -> Bool {
            guard width > 0, x >= 0, y >= 0, x < width, y < height,
                  islands.count == width * height else { return false }
            return islands[y * width + x] == id
        }

        /// Whether the pixel is that island's or anything sitting on it, however
        /// deep. This is what cutting a card out asks: the space a row came from
        /// is still part of the card, and what goes back into it is the card's
        /// own colour rather than a hole.
        public func owns(_ x: Int, _ y: Int, _ id: Int32) -> Bool {
            guard width > 0, x >= 0, y >= 0, x < width, y < height,
                  islands.count == width * height else { return false }
            var here = islands[y * width + x]
            // Every child is numbered after its parent, so walking up strictly
            // decreases and this cannot loop however the ancestry was built.
            while here != 0 {
                if here == id { return true }
                let slot = Int(here) - 1
                guard slot >= 0, slot < ancestors.count else { return false }
                let up = ancestors[slot]
                guard up < here else { return false }
                here = up
            }
            return false
        }

        /// Whether the pixel is background. Outside the picture is no.
        public func isBackdrop(_ x: Int, _ y: Int) -> Bool {
            guard width > 0, x >= 0, y >= 0, x < width, y < height,
                  backdrop.count == width * height else { return false }
            return backdrop[y * width + x] == 1
        }

        /// Whether the pixel is what `box` is SITTING ON: the page for a box on
        /// the page, the holder's own paint for a box on a box.
        ///
        /// Everything that reads round a box goes through this — the ring the
        /// patch is decided from, the shadow, the edge read to better than a
        /// pixel — so a row inside a card is measured against the card and
        /// never against a page it cannot see.
        public func isSurround(_ x: Int, _ y: Int, of box: Box) -> Bool {
            box.parent == 0 ? isBackdrop(x, y) : isIsland(x, y, box.parent)
        }
    }

    // MARK: - The numbers

    /// How far apart two neighbouring pixels may be, per channel out of 255,
    /// and still be the same patch of colour. Three, which is under what an eye
    /// can see on a flat panel and well over the dither a renderer leaves —
    /// while the step across an antialiased edge is tens of levels, so a box
    /// never leaks into the page it sits on.
    public static let colorTolerance = 3

    /// How much of a box's own bounding box its pixels must fill. A rounded
    /// rectangle fills 88% at its most generous rounding (a pill) and 100% when
    /// square; a letter of the alphabet fills half that, which is what this is
    /// really keeping out — a word the sweep could not read is still in the
    /// picture and must not come back as a box.
    public static let minFill = 0.75

    /// How much of the picture a box may cover before it stops being a thing IN
    /// the picture and starts being the picture. Past this the sweep looks
    /// inside it instead.
    public static let maxAreaFraction = 0.6

    /// How much of the picture's own border one colour must hold before it can
    /// be called the background. Under this there is no page to read anything
    /// against — a photograph, a collage — and nothing is claimed at all.
    public static let minBorderShare = 0.5

    /// How many times the sweep will step inside something that filled the
    /// picture. A screenshot of a window inside a window inside a window is not
    /// a thing that happens, and each step costs another pass.
    public static let maxDescents = 3

    /// How many boxes one sweep will return.
    public static let defaultLimit = 200

    /// How many boxes deep the sweep looks: a box on the page, and the boxes on
    /// THAT one. Two.
    ///
    /// The line has to go somewhere, and this is where the answers stop being
    /// things a person points at. On a settings pane, one level is the cards and
    /// the buttons; two is the rows, switches and fields sitting on them, which
    /// is the whole point of looking inside at all. Three is the knob inside the
    /// switch and the chevron inside the row — parts of a control rather than
    /// controls, and a layers list that offers them is a list you scroll past.
    ///
    /// Nothing is lost by stopping: the knob still comes out, INSIDE its switch,
    /// because a box is cut whole and everything sitting on it travels with it.
    public static let maxBoxDepth = 2

    /// How far a colour may sit from the middle of its neighbours and still be
    /// called one flat colour, per channel out of 255. The same tightness the
    /// patch uses to call a ring flat, so what the app calls a solid fill and
    /// what it calls a solid background agree.
    public static let uniformTolerance = 2.0 / 255

    /// How far in from a box's edge the fill is read, so the antialiasing down
    /// its rounded sides never votes on what colour it is.
    public static let edgeMargin = 3

    /// How far a pixel in the band BETWEEN the clean fill and the box's edge
    /// may sit from the fill and still be that fill, part way through an
    /// antialiased blend. Loose, because that is exactly what those pixels are;
    /// its job is only to catch a box whose inside is not one paint at all.
    public static let blendTolerance = 0.1

    /// The thickest plain edge that will be read as an edge rather than as part
    /// of the picture. Four image pixels is a two point border on a 2x capture,
    /// which is already heavier than anything real UI draws.
    public static let maxBorderWidth = 4

    /// How far an edge's colour must sit from the fill's before it is an edge
    /// at all rather than the same paint read twice.
    public static let minBorderContrast = 4.0 / 255

    /// How far the box's own paint must sit from what is behind it before the
    /// app will claim to know where its edge is to better than a pixel. Under
    /// this, reading how much paint a pixel got is reading noise, so no shape
    /// is offered and the box comes out as the picture it already is.
    public static let minCoverageContrast = 6.0 / 255

    /// How wide a band outside a box is read to find out what is behind it.
    public static let ringWidth = 3

    /// How far in from a box's own outline is still the box's own edge rather
    /// than something sitting on it: two pixels, which is the blend a renderer
    /// leaves plus one for the rounding to land in. Only the sweep INSIDE a box
    /// uses it, and only to keep that box's own rim from being read as a thing
    /// on it.
    public static let bodyMargin = 2

    /// The roundest corner that will be read as a corner, in image pixels —
    /// 32 points on a 2x capture, past which nothing in real UI is rounded and
    /// the search would only cost time on a big card.
    public static let maxCornerRadius = 64

    /// How much of a box's bounding box must agree with the rounded rectangle
    /// read off it before that rectangle is believed. Below this the thing is
    /// some other shape — an oval, a blob, a chart — and it stays a picture.
    public static let minShapeAgreement = 0.97

    // MARK: - The sweep

    /// Every box in `field`.
    ///
    /// `reserved` are rects already spoken for by something else — the runs of
    /// text the same command is taking out — so nothing is ever separated
    /// twice. `minElement` is the smallest thing worth offering, in image
    /// pixels.
    public static func sweep(in field: PixelField,
                             avoiding reserved: [CGRect] = [],
                             minElement: Double = ElementBounds.defaultMinElement,
                             limit: Int = defaultLimit) -> Sweep {
        guard !field.isEmpty, limit > 0 else { return .empty }
        let w = field.width, h = field.height
        let regions = labelRegions(field.samples, w, h)
        guard let page = pageRegion(regions, w, h) else { return .empty }

        var backdrop = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) where regions[i] == page { backdrop[i] = 1 }

        var islands: [Int32] = []
        var found: [Island] = []
        for _ in 0...maxDescents {
            (islands, found) = self.islands(notIn: backdrop, width: w, height: h)
            let oversized = found.filter {
                Double($0.area) >= maxAreaFraction * Double(w * h)
            }
            guard !oversized.isEmpty else { break }
            // Something the size of the picture IS the picture. Whatever it is
            // mostly painted becomes background too, and the next pass reads
            // what sits on that.
            var grew = false
            for island in oversized {
                guard let inner = dominantRegion(of: island, in: regions, islands: islands,
                                                 width: w) else { continue }
                for i in 0..<(w * h) where regions[i] == inner && backdrop[i] == 0 {
                    backdrop[i] = 1
                    grew = true
                }
            }
            guard grew else { break }
        }

        let minSide = Int(minElement.rounded())
        var boxes: [Box] = []
        /// Which island each island is sitting on: `ancestors[id - 1]`.
        var ancestors = [Int32](repeating: 0, count: found.count)
        for island in found.sorted(by: { $0.area > $1.area }) {
            let bw = island.x1 - island.x0 + 1, bh = island.y1 - island.y0 + 1
            guard bw >= minSide, bh >= minSide,
                  Double(island.area) <= maxAreaFraction * Double(w * h),
                  Double(island.area) >= minFill * Double(bw * bh)
            else { continue }
            let rect = CGRect(x: island.x0, y: island.y0, width: bw, height: bh)
            // A box may HOLD something already spoken for — a card holds the
            // labels the same command just took out of it, and the hole each
            // one left has already been filled. What it may not do is be one,
            // or clip one, because then the same pixels would come out twice.
            guard !reserved.contains(where: { $0.intersects(rect) && !rect.contains($0) }),
                  !boxes.contains(where: { $0.rect.intersects(rect) })
            else { continue }
            let id = island.id
            boxes.append(Box(rect: rect, island: id,
                             shape: readShape(rect, field: field,
                                              owns: { x, y in islands[y * w + x] == id },
                                              surround: { x, y in backdrop[y * w + x] == 1 })))
            if boxes.count == limit { break }
        }

        // And now the same question inside every box that was taken: what is
        // sitting on THIS one? A card holds rows, a row holds a switch, and
        // until this loop existed every one of them came out baked into one
        // flat picture of the card.
        var frontier = boxes
        var depth = 2
        while depth <= maxBoxDepth, !frontier.isEmpty, boxes.count < limit {
            var deeper: [Box] = []
            for parent in frontier {
                for kid in children(of: parent, in: regions, islands: &islands,
                                    ancestors: &ancestors, field: field,
                                    minSide: minSide, reserved: reserved,
                                    taken: boxes + deeper) {
                    let id = kid.island, holder = parent.island
                    deeper.append(Box(
                        rect: kid.rect, island: id,
                        shape: readShape(kid.rect, field: field,
                                         owns: { x, y in islands[y * w + x] == id },
                                         surround: { x, y in islands[y * w + x] == holder }),
                        parent: holder, depth: depth))
                    if boxes.count + deeper.count == limit { break }
                }
                if boxes.count + deeper.count == limit { break }
            }
            boxes += deeper
            frontier = deeper
            depth += 1
        }

        // Outermost first, then down the page: that is the stacking order, and
        // a row laid over the card it came off would hide it otherwise.
        let ordered = boxes.sorted {
            ($0.depth, $0.rect.minY, $0.rect.minX) < ($1.depth, $1.rect.minY, $1.rect.minX)
        }
        return Sweep(boxes: ordered, islands: islands, backdrop: backdrop,
                     ancestors: ancestors, width: w, height: h)
    }

    /// What is sitting on `parent`: the whole sweep's question asked again, one
    /// box in.
    ///
    /// The parent's own paint plays the part the page plays outside it —
    /// whatever interrupts that colour is a thing ON the parent — so this is
    /// the same rule with the page already known: the colour region most of the
    /// parent is painted.
    ///
    /// Every pixel a child claims is RELABELLED from the parent to the child,
    /// so the child can be cut out exactly. The parent gets them back through
    /// `Sweep.owns`, which is what lets the space a row came from be filled with
    /// the card's own colour rather than left as a hole.
    static func children(of parent: Box, in regions: [Int32], islands: inout [Int32],
                         ancestors: inout [Int32], field: PixelField, minSide: Int,
                         reserved: [CGRect],
                         taken: [Box]) -> [(rect: CGRect, island: Int32)] {
        // A box the sweep could read as ONE FLAT COLOUR has nothing on it, by
        // the definition of flat: that reading is what says every pixel three
        // clear of its edge is the same paint. So there is nothing to look for,
        // and on a screen full of buttons this is most of the boxes.
        guard parent.shape == nil else { return [] }
        let w = field.width, h = field.height
        let x0 = Int(parent.rect.minX), y0 = Int(parent.rect.minY)
        let bw = Int(parent.rect.width), bh = Int(parent.rect.height)
        guard bw >= minSide + 2 * bodyMargin, bh >= minSide + 2 * bodyMargin,
              x0 >= 0, y0 >= 0, x0 + bw <= w, y0 + bh <= h else { return [] }

        // What the parent itself is painted. Counted on a coarse grid rather
        // than pixel by pixel: the paint a box is mostly painted holds most of
        // it, and one vote in nine settles that just as well as all nine while
        // a card's worth of dictionary work is the single biggest cost here.
        var votes: [Int32: Int] = [:]
        for y in stride(from: y0, to: y0 + bh, by: 3) {
            for x in stride(from: x0, to: x0 + bw, by: 3) where islands[y * w + x] == parent.island {
                votes[regions[y * w + x], default: 0] += 1
            }
        }
        guard let body = votes.max(by: { $0.value < $1.value })?.key else { return [] }

        // The parent's pixels with the band at its own outline taken off, which
        // is where its antialiasing lives. Without that, a header painted edge
        // to edge joins the rim running all the way round the card and the pair
        // reads as one piece the size of the card — so nothing is found at all.
        //
        // How far each pixel is from the nearest one that is not the parent's,
        // in two sweeps rather than one erosion per pixel of margin.
        let cap = UInt8(bodyMargin + 1)
        var depth = [UInt8](repeating: 0, count: bw * bh)
        for y in 0..<bh {
            for x in 0..<bw {
                let i = y * bw + x
                guard islands[(y0 + y) * w + x0 + x] == parent.island else { continue }
                depth[i] = x == 0 || y == 0
                    ? 1 : min(cap, min(depth[i - 1], depth[i - bw]) &+ 1)
            }
        }
        // Everything of the parent's that is not the parent's own paint, as
        // connected pieces. Read in a frame one pixel bigger all round, so that
        // nothing counts as cut off by an edge: a row really can run the whole
        // width of the card it is in, and the card is not a picture frame.
        let pw = bw + 2, ph = bh + 2
        var inside = [UInt8](repeating: 1, count: pw * ph)
        var any = false
        for y in stride(from: bh - 1, through: 0, by: -1) {
            for x in stride(from: bw - 1, through: 0, by: -1) {
                let i = y * bw + x
                guard depth[i] > 0 else { continue }
                let back: UInt8 = x == bw - 1 || y == bh - 1
                    ? 1 : min(cap, min(depth[i + 1], depth[i + bw]) &+ 1)
                let here = min(depth[i], back)
                depth[i] = here
                guard here > UInt8(bodyMargin),
                      regions[(y0 + y) * w + x0 + x] != body else { continue }
                inside[(y + 1) * pw + (x + 1)] = 0
                any = true
            }
        }
        guard any else { return [] }
        let (labels, pieces) = self.islands(notIn: inside, width: pw, height: ph)

        var out: [(rect: CGRect, island: Int32)] = []
        for piece in pieces.sorted(by: { $0.area > $1.area }) {
            let cw = piece.x1 - piece.x0 + 1, ch = piece.y1 - piece.y0 + 1
            guard cw >= minSide, ch >= minSide,
                  Double(piece.area) <= maxAreaFraction * Double(bw * bh),
                  Double(piece.area) >= minFill * Double(cw * ch)
            else { continue }
            let rect = CGRect(x: x0 + piece.x0 - 1, y: y0 + piece.y0 - 1,
                              width: cw, height: ch)
            // Same two rules as outside: never a run of text the command is
            // already taking, and never on top of a box already found. Holding
            // one is fine — that is what a row does to its label.
            guard !reserved.contains(where: { $0.intersects(rect) && !rect.contains($0) }),
                  !taken.contains(where: { $0.rect.intersects(rect) && !$0.rect.contains(rect) }),
                  !out.contains(where: { $0.rect.intersects(rect) })
            else { continue }
            let id = Int32(ancestors.count + 1)
            ancestors.append(parent.island)
            for y in piece.y0...piece.y1 {
                for x in piece.x0...piece.x1 where labels[y * pw + x] == piece.id {
                    islands[(y0 + y - 1) * w + x0 + x - 1] = id
                }
            }
            out.append((rect, id))
        }
        return out.sorted { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }
    }

    // MARK: - Patches of one colour

    /// Every pixel's colour region: neighbouring pixels within `colorTolerance`
    /// of each other are the same region. One pass with union-find, so a whole
    /// picture costs about what reading it did.
    ///
    /// Chaining down a slow ramp is deliberate: a page with a gentle gradient on
    /// it is still one page, and treating it as one is what lets the things
    /// sitting on it be found.
    static func labelRegions(_ px: [UInt8], _ w: Int, _ h: Int) -> [Int32] {
        let count = w * h
        var parent = [Int32](repeating: 0, count: count)
        let tol = Int32(colorTolerance)
        px.withUnsafeBufferPointer { source in
            parent.withUnsafeMutableBufferPointer { p in
                for i in 0..<count { p[i] = Int32(i) }
                func find(_ start: Int32) -> Int32 {
                    var i = start
                    while p[Int(i)] != i {
                        p[Int(i)] = p[Int(p[Int(i)])]
                        i = p[Int(i)]
                    }
                    return i
                }
                func union(_ a: Int32, _ b: Int32) {
                    let ra = find(a), rb = find(b)
                    if ra != rb { p[Int(max(ra, rb))] = min(ra, rb) }
                }
                func same(_ i: Int, _ j: Int) -> Bool {
                    let a = i * 4, b = j * 4
                    for channel in 0..<4 {
                        let d = Int32(source[a + channel]) - Int32(source[b + channel])
                        if d > tol || d < -tol { return false }
                    }
                    return true
                }
                for y in 0..<h {
                    let base = y * w
                    for x in 0..<w {
                        let i = base + x
                        if x > 0, same(i, i - 1) { union(Int32(i), Int32(i - 1)) }
                        if y > 0, same(i, i - w) { union(Int32(i), Int32(i - w)) }
                    }
                }
                for i in 0..<count { p[i] = find(Int32(i)) }
            }
        }
        return parent
    }

    /// The picture's own background: the colour region holding most of the
    /// picture's outer border. Nil when no one region holds enough of it, which
    /// is what a photograph looks like from here.
    static func pageRegion(_ regions: [Int32], _ w: Int, _ h: Int) -> Int32? {
        var votes: [Int32: Int] = [:]
        var total = 0
        func vote(_ x: Int, _ y: Int) {
            votes[regions[y * w + x], default: 0] += 1
            total += 1
        }
        for x in 0..<w { vote(x, 0); vote(x, h - 1) }
        for y in 1..<max(1, h - 1) { vote(0, y); vote(w - 1, y) }
        guard total > 0, let best = votes.max(by: { $0.value < $1.value }) else { return nil }
        return Double(best.value) >= minBorderShare * Double(total) ? best.key : nil
    }

    // MARK: - The things sitting on it

    struct Island {
        var id: Int32
        var x0 = Int.max, y0 = Int.max, x1 = -1, y1 = -1
        var area = 0
    }

    /// Labels are the island's number plus nothing: 0 means no island, so a
    /// caller never has to carry a sentinel of its own.

    /// Everything that interrupts the background, as connected pieces. A piece
    /// touching the edge of the picture is dropped: the frame cut it off, so
    /// its real shape is not in the picture and the app does not guess it.
    static func islands(notIn backdrop: [UInt8], width w: Int,
                        height h: Int) -> ([Int32], [Island]) {
        let count = w * h
        var parent = [Int32](repeating: 0, count: count)
        backdrop.withUnsafeBufferPointer { back in
            parent.withUnsafeMutableBufferPointer { p in
                for i in 0..<count { p[i] = back[i] == 1 ? -1 : Int32(i) }
                func find(_ start: Int32) -> Int32 {
                    var i = start
                    while p[Int(i)] != i {
                        p[Int(i)] = p[Int(p[Int(i)])]
                        i = p[Int(i)]
                    }
                    return i
                }
                func union(_ a: Int32, _ b: Int32) {
                    let ra = find(a), rb = find(b)
                    if ra != rb { p[Int(max(ra, rb))] = min(ra, rb) }
                }
                for y in 0..<h {
                    let base = y * w
                    for x in 0..<w where p[base + x] != -1 {
                        let i = base + x
                        if x > 0, p[i - 1] != -1 { union(Int32(i), Int32(i - 1)) }
                        if y > 0, p[i - w] != -1 { union(Int32(i), Int32(i - w)) }
                    }
                }
                for i in 0..<count where p[i] != -1 { p[i] = find(Int32(i)) }
            }
        }
        // Roots into dense numbers, so the per-pixel work is an array index
        // rather than a hash: a 12 megapixel capture goes through this loop
        // twelve million times and a dictionary there costs seconds.
        var dense = [Int32](repeating: 0, count: count)
        var found: [Island] = []
        var clipped: [Bool] = []
        var labels = [Int32](repeating: 0, count: count)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let root = parent[i]
                guard root != -1 else { continue }
                var id = dense[Int(root)]
                if id == 0 {
                    found.append(Island(id: Int32(found.count + 1), x0: x, y0: y, x1: x, y1: y))
                    clipped.append(false)
                    id = Int32(found.count)
                    dense[Int(root)] = id
                }
                let slot = Int(id) - 1
                found[slot].x0 = min(found[slot].x0, x)
                found[slot].x1 = max(found[slot].x1, x)
                found[slot].y0 = min(found[slot].y0, y)
                found[slot].y1 = max(found[slot].y1, y)
                found[slot].area += 1
                labels[i] = id
                if x == 0 || y == 0 || x == w - 1 || y == h - 1 { clipped[slot] = true }
            }
        }
        // Anything the frame cut in half is dropped: its real shape is not in
        // the picture, so the app does not guess it.
        for i in 0..<count where labels[i] != 0 && clipped[Int(labels[i]) - 1] {
            labels[i] = 0
        }
        return (labels, found.filter { !clipped[Int($0.id) - 1] })
    }

    /// The colour region most of an island is painted, which is what becomes
    /// background when the island turned out to BE the picture.
    static func dominantRegion(of island: Island, in regions: [Int32],
                               islands: [Int32], width w: Int) -> Int32? {
        var votes: [Int32: Int] = [:]
        for y in island.y0...island.y1 {
            for x in island.x0...island.x1 where islands[y * w + x] == island.id {
                votes[regions[y * w + x], default: 0] += 1
            }
        }
        return votes.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Is it really a shape?

    /// The rounded rectangle a box can honestly be turned into, or nil.
    ///
    /// `owns` says which pixels are the box's; `surround` says which are what it
    /// is SITTING ON — the page for a box on the page, the card's own paint for
    /// a row inside a card. A row read against a page it cannot see would have
    /// no reading at all.
    static func readShape(_ rect: CGRect, field: PixelField,
                          owns: (Int, Int) -> Bool,
                          surround: (Int, Int) -> Bool) -> Shape? {
        let w = field.width, h = field.height
        let x0 = Int(rect.minX), y0 = Int(rect.minY)
        let bw = Int(rect.width), bh = Int(rect.height)
        func isIsland(_ x: Int, _ y: Int) -> Bool {
            let px = x0 + x, py = y0 + y
            guard px >= 0, py >= 0, px < w, py < h else { return false }
            return owns(px, py)
        }

        // What is behind the box, and how far the box's own paint sits from it.
        // Both are needed to read the box's shape to better than a pixel: a
        // pixel its edge only clips is still a pixel of the box, so a mask of
        // "any paint at all" is a rounded corner half a dozen pixels too square.
        // Reading how MUCH paint each pixel got puts the edge back where the
        // renderer drew it.
        var behind: [RGBA] = []
        for y in (-ringWidth)..<(bh + ringWidth) {
            for x in (-ringWidth)..<(bw + ringWidth) {
                guard x < 0 || y < 0 || x >= bw || y >= bh else { continue }
                let px = x0 + x, py = y0 + y
                guard px >= 0, py >= 0, px < w, py < h, surround(px, py) else { continue }
                behind.append(field.color(px, py))
            }
        }
        guard behind.count >= 8, let page = middle(behind) else { return nil }

        // The box's own pixels, read once. Every pass below is a scan over
        // this rather than another trip through the picture.
        var paint = [RGBA](repeating: page, count: bw * bh)
        for y in 0..<bh {
            for x in 0..<bw { paint[y * bw + x] = field.color(x0 + x, y0 + y) }
        }

        // How much of each pixel the box actually covers. Everything well
        // inside it is covered outright; only the pixels its edge passes
        // through have to be worked out, and each of those is measured against
        // the paint right beside it rather than against one reading for the
        // whole box — otherwise a white field inside a grey edge reads as
        // uncovered, because white is nearer the page than grey is.
        var island = [Bool](repeating: false, count: bw * bh)
        var reach = [Double](repeating: 0, count: bw * bh)
        for y in 0..<bh {
            for x in 0..<bw where isIsland(x, y) {
                island[y * bw + x] = true
                reach[y * bw + x] = distance(paint[y * bw + x], page)
            }
        }
        guard reach.contains(where: { $0 >= minCoverageContrast }) else { return nil }
        func rim(_ x: Int, _ y: Int) -> Bool {
            guard island[y * bw + x] else { return false }
            return !isIsland(x - 1, y) || !isIsland(x + 1, y)
                || !isIsland(x, y - 1) || !isIsland(x, y + 1)
        }
        var covered = [Bool](repeating: false, count: bw * bh)
        for y in 0..<bh {
            for x in 0..<bw {
                let i = y * bw + x
                guard island[i] else { continue }
                guard rim(x, y) else { covered[i] = true; continue }
                var beside = 0.0
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < bw, ny < bh,
                              island[ny * bw + nx], !rim(nx, ny) else { continue }
                        beside = max(beside, reach[ny * bw + nx])
                    }
                }
                // Nothing beside it to measure against: keep the pixel, since
                // dropping it would shave the box for no reason.
                covered[i] = beside < minCoverageContrast || reach[i] >= 0.5 * beside
            }
        }
        func isCovered(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < bw, y < bh else { return false }
            return covered[y * bw + x]
        }

        // 1. How round each corner is.
        let radii = cornerRadii(bw: bw, bh: bh, covered: isCovered)

        // How deep inside the rounded rectangle each pixel sits, and whether it
        // is on one of the straight runs rather than round a corner. Worked out
        // once: every reading below is a scan over these two rather than a
        // fresh pass of arithmetic, which on a card-sized box is the difference
        // between ten million square roots and three hundred thousand.
        var depth = [Double](repeating: 0, count: bw * bh)
        var straight = [Bool](repeating: false, count: bw * bh)
        let hw = Double(bw) / 2, hh = Double(bh) / 2
        for y in 0..<bh {
            for x in 0..<bw {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                depth[y * bw + x] = distance(px, py, bw, bh, radii)
                let dx = px - hw, dy = py - hh
                let corner = dx < 0 ? (dy < 0 ? radii.topLeft : radii.bottomLeft)
                                    : (dy < 0 ? radii.topRight : radii.bottomRight)
                let r = min(Double(corner), min(hw, hh))
                straight[y * bw + x] = abs(dx) <= hw - r || abs(dy) <= hh - r
            }
        }

        // 2. Does the box actually have that shape? Every pixel of its box has
        // to agree with the rounded rectangle read off it, or the thing is some
        // other shape — an oval, a blob, a chart — and it stays a picture.
        var agree = 0
        for y in 0..<bh {
            for x in 0..<bw where (depth[y * bw + x] < 0) == isCovered(x, y) { agree += 1 }
        }
        guard Double(agree) >= minShapeAgreement * Double(bw * bh) else { return nil }

        // 3. One flat colour inside, with the antialiasing down its sides kept
        // out of the reading — and, if that fails, one flat colour inside one
        // plain edge.
        //
        // The bands are tight on purpose. Read loosely, a box with a two pixel
        // edge answers "one pixel" first, because a band that starts deep
        // enough to clear the edge's own antialiasing also clears the edge.

        /// The one colour a band of the box is painted, or nil when it is not
        /// one colour. Streamed as a running spread per channel rather than
        /// collected and sorted: a card-sized box offers three hundred thousand
        /// samples and this is asked five times over.
        func flat(from: Double, to: Double, straightOnly: Bool) -> RGBA? {
            var low = [Double](repeating: .infinity, count: 4)
            var high = [Double](repeating: -.infinity, count: 4)
            var seen = 0
            for i in 0..<(bw * bh) {
                let d = depth[i]
                guard d > from, d <= to, !straightOnly || straight[i] else { continue }
                let c = paint[i]
                let channels = [c.r, c.g, c.b, c.a]
                for k in 0..<4 {
                    low[k] = min(low[k], channels[k])
                    high[k] = max(high[k], channels[k])
                    if high[k] - low[k] > 2 * uniformTolerance { return nil }
                }
                seen += 1
            }
            guard seen >= 8 else { return nil }
            return RGBA(r: (low[0] + high[0]) / 2, g: (low[1] + high[1]) / 2,
                        b: (low[2] + high[2]) / 2, a: (low[3] + high[3]) / 2)
        }
        /// Whether every pixel of a band is the same paint as `fill`, allowing
        /// for a blend.
        func matches(_ fill: RGBA, from: Double, to: Double, straightOnly: Bool) -> Bool {
            for i in 0..<(bw * bh) {
                let d = depth[i]
                guard d > from, d <= to, !straightOnly || straight[i] else { continue }
                if distance(paint[i], fill) > blendTolerance { return false }
            }
            return true
        }

        for border in 0...maxBorderWidth {
            let edge = Double(border)
            guard let fill = flat(from: -.infinity, to: -edge - Double(edgeMargin),
                                  straightOnly: false)
            else { continue }
            // Everything between that clean reading and the inside of the edge
            // has to be the same paint, part way through a blend — otherwise
            // something else is hiding in the ring. It is what makes a two
            // pixel edge answer two: with the band stopping short of the
            // edge's second pixel, that pixel is never asked about and one
            // pixel of edge fits just as well.
            guard matches(fill, from: -edge - Double(edgeMargin), to: -edge - 0.5,
                          straightOnly: true)
            else { continue }
            guard border > 0 else { return Shape(fill: fill, radii: radii) }
            guard let ink = flat(from: -edge + 0.25, to: -0.25, straightOnly: true),
                  distance(ink, fill) > minBorderContrast
            else { continue }
            return Shape(fill: fill, radii: radii, borderWidth: CGFloat(border),
                         borderColor: ink)
        }
        return nil
    }

    /// The per-channel middle of a set of colours.
    private static func middle(_ colors: [RGBA]) -> RGBA? {
        guard !colors.isEmpty else { return nil }
        func mid(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
        return RGBA(r: mid(colors.map(\.r)), g: mid(colors.map(\.g)),
                    b: mid(colors.map(\.b)), a: mid(colors.map(\.a)))
    }

    /// The rounding at each of a box's four corners, read off which pixels
    /// belong to it.
    ///
    /// Read straight off the outline instead — the row at which the box's edge
    /// reaches the side of its bounding box — and a rounded corner reads about
    /// half its real radius, because a pixel the arc only clips is still a
    /// pixel of the box and near a corner those reach a long way diagonally.
    /// So every rounding is tried and the one that disagrees with the fewest
    /// pixels wins. `covered` is the box read to better than a pixel: true
    /// where the box's paint covers half the pixel or more.
    static func cornerRadii(bw: Int, bh: Int,
                            covered: (Int, Int) -> Bool) -> CornerRadii {
        let cap = min(min(bw, bh) / 2, maxCornerRadius)
        func radius(xFlipped: Bool, yFlipped: Bool) -> CGFloat {
            guard cap > 0 else { return 0 }
            let span = min(cap + 2, min(bw, bh))
            var best = 0, fewest = Int.max
            for r in 0...cap {
                let radii = CornerRadii(CGFloat(r))
                var wrong = 0
                for step in 0..<span {
                    let y = yFlipped ? bh - 1 - step : step
                    for offset in 0..<span {
                        let x = xFlipped ? bw - 1 - offset : offset
                        let d = distance(Double(x) + 0.5, Double(y) + 0.5, bw, bh, radii)
                        if (d < 0) != covered(x, y) { wrong += 1 }
                    }
                }
                if wrong < fewest { fewest = wrong; best = r }
            }
            return CGFloat(best)
        }
        return CornerRadii(topLeft: radius(xFlipped: false, yFlipped: false),
                           topRight: radius(xFlipped: true, yFlipped: false),
                           bottomRight: radius(xFlipped: true, yFlipped: true),
                           bottomLeft: radius(xFlipped: false, yFlipped: true))
    }

    private static func distance(_ a: RGBA, _ b: RGBA) -> Double {
        max(max(abs(a.r - b.r), abs(a.g - b.g)), max(abs(a.b - b.b), abs(a.a - b.a)))
    }

    /// How far a point sits inside a rounded rectangle of this size: negative
    /// inside, positive outside, in pixels. The corner nearest the point sets
    /// the rounding, so a card with only its top two corners rounded reads the
    /// same way a button with all four does.
    static func distance(_ px: Double, _ py: Double, _ bw: Int, _ bh: Int,
                         _ radii: CornerRadii) -> Double {
        let hw = Double(bw) / 2, hh = Double(bh) / 2
        let dx = px - hw, dy = py - hh
        let corner = dx < 0 ? (dy < 0 ? radii.topLeft : radii.bottomLeft)
                            : (dy < 0 ? radii.topRight : radii.bottomRight)
        let r = min(Double(corner), min(hw, hh))
        let qx = abs(dx) - (hw - r), qy = abs(dy) - (hh - r)
        let outside = sqrt(max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0))
        return outside + min(max(qx, qy), 0) - r
    }
}
