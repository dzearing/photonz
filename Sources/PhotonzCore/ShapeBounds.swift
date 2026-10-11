import CoreGraphics
import Foundation

/// Finds the things in a screenshot that are not boxes: a round avatar, an
/// icon on its tile, a pill or a count badge, a photo, and a stack of avatars
/// overlapping one another. Size mode's other reader (`ElementBounds`) builds an
/// element from a pair of straight boundaries above and below the pointer, which
/// is exactly right for a button or a row and blind to a circle, whose top and
/// bottom are a single point each (the user, 2026-10-11: "i hover over the
/// avatar and it won't size it. or the stacked set of avatars").
///
/// So this one reads a shape by what it is NOT: the background around it. A
/// window around the pointer is grown until its rim sits on one flat colour; the
/// background is flooded in from that rim; whatever the flood cannot reach and
/// is connected to the pointer is the shape, holes and all (the letters of an
/// initials avatar, the glyph on an icon's tile). Its bounding box is the
/// outermost pixel that differs from the background, which is the outer edge a
/// spec quotes, antialiased fringe included.
///
/// Pure brightness, like the rest of the picture readers: a shape the same
/// brightness as the page behind it is invisible here.
public enum ShapeBounds {

    /// How far (0...255) a pixel may sit from the background and still BE
    /// background. Above lossless noise and a hairline's antialiased whisper,
    /// below the faintest tinted backdrop a pale avatar has.
    public static let tolerance = 9

    /// How much of a window's rim has to be one colour for that colour to be
    /// called the background. Under it the rim is still crossing the thing
    /// being read, and the window grows.
    private static let rimAgreement = 0.5

    /// How tightly (0...255) the rim has to agree for that agreement to count.
    /// A page, a card or a sidebar in a screenshot is one exact colour; a photo
    /// or a gradient is not, however slowly it changes, and a window whose rim
    /// is still crossing one has to grow rather than call it a background.
    private static let flatness = 3

    /// Whether any paint sits within `reach` px beyond either side of `b`,
    /// across the middle half of its height.
    private static func hasNeighbour(beside b: CGRect, within reach: Int, in image: Image,
                                     background: Int) -> Bool {
        let y0 = max(0, Int(b.minY + b.height / 4)), y1 = min(image.h, Int(b.maxY - b.height / 4))
        guard y0 < y1 else { return false }
        for (from, to) in [(Int(b.maxX), Int(b.maxX) + reach), (Int(b.minX) - reach, Int(b.minX))] {
            for x in max(0, from)..<min(image.w, max(from, to)) {
                for y in y0..<y1 where abs(Int(image.s[y * image.w + x]) - background) > tolerance {
                    return true
                }
            }
        }
        return false
    }

    /// The tallest shape whose stack is looked for, in image px.
    private static let maxGroupHeight = 240.0

    /// One shape under the pointer.
    public struct Reading: Equatable, Sendable {
        /// The shape's bounding box in image px, to its outer edge.
        public var bounds: CGRect
        /// Whether the pointer is on the shape's own paint (a photo, a fill, a
        /// letter cut out of it) rather than inside a hole big enough to be a
        /// thing of its own (a white button inside a filled banner).
        public var onBody: Bool
        /// The brightness the shape was separated from, 0...255.
        public var background: Int

        public init(bounds: CGRect, onBody: Bool, background: Int) {
            self.bounds = bounds
            self.onBody = onBody
            self.background = background
        }
    }

    /// The shape under `point`, or nil when the pointer is on open background,
    /// on something bigger than `maxRadius` reaches, or on something smaller
    /// than `minElement` either way.
    public static func shape(at point: CGPoint, in luma: LumaField,
                             minElement: Double = ElementBounds.defaultMinElement,
                             maxRadius: Double = ElementBounds.defaultMaxRadius) -> Reading? {
        guard !luma.isEmpty, maxRadius > 0 else { return nil }
        let px = Int(point.x.rounded(.down)), py = Int(point.y.rounded(.down))
        guard px >= 0, py >= 0, px < luma.width, py < luma.height else { return nil }
        // A shape is a thing the size of an avatar, an icon or a photo in a
        // card. Anything bigger is a panel, and the pair reader measures
        // panels; tracing one on every mouse move would only cost time.
        let limit = min(max(8, Int(maxRadius.rounded())), max(8, Int((largest * minElement).rounded())))
        return luma.samples.withUnsafeBufferPointer { s -> Reading? in
            let image = Image(s: s, w: luma.width, h: luma.height)
            // Which colour is the background? Try each colour that surrounds
            // the pointer, nearest first. When the pointer's own pixel is one
            // of them (a white letter cut out of a purple avatar, a white glyph
            // on a blue tile on a white page) that one is the background and
            // the pointer is in a hole of the thing painted on it: a mark in
            // the page's own colour is part of what it is cut out of.
            let own = Int(s[py * luma.width + px])
            let t0 = DispatchTime.now().uptimeNanoseconds
            let (around, nearestEdge) = surroundings(of: px, py, in: image, reach: limit)
            // On a broad flat fill (inside a card, a big button) there is no
            // shape to find that the pair reader does not already measure.
            if isFlat(at: px, py, in: image), nearestEdge >= Int((flatFill * minElement).rounded()) {
                return nil
            }
            // The pointer's own colour also surrounds it when it is on a
            // shape's flat fill and the walks crossed a label painted on it;
            // that is no hole, so the other colours get their turn.
            if let background = around.first(where: { abs($0 - own) <= tolerance }),
               let ring = cutOut(at: px, py, in: image, background: background,
                                 minElement: minElement, limit: limit) {
                return ring
            }
            for background in around where abs(background - own) > tolerance {
                if let reading = body(at: px, py, in: image, background: background,
                                      minElement: minElement, limit: limit) {
                    return reading
                }
            }
            return nil
        }
    }

    /// The overlapping or tightly spaced row `reading` is one of (an avatar
    /// stack, a facepile, a run of chips), or nil when it stands alone. Its
    /// members are about as tall as it is and sit within `link` px of one
    /// another, so a name beside an avatar (shorter, further off) never joins.
    public static func group(of reading: Reading, in luma: LumaField, link: Double? = nil) -> CGRect? {
        guard !luma.isEmpty else { return nil }
        let b = reading.bounds
        let h = Double(b.height)
        // Stacks are of small things; a tall shape is a card, and reading a
        // strip sixteen cards wide to find its siblings would cost a hover.
        guard h >= 2, h <= maxGroupHeight else { return nil }
        let linkPx = link ?? max(4, 0.2 * h)
        return luma.samples.withUnsafeBufferPointer { s -> CGRect? in
            let image = Image(s: s, w: luma.width, h: luma.height)
            // A stack member has a neighbour within `link` of one side, about
            // half way down; most things do not, and are spared the strip read.
            guard hasNeighbour(beside: b, within: Int(linkPx.rounded(.up)) + 1, in: image,
                               background: reading.background) else { return nil }
            let reach = min(Int((8 * h).rounded()), 480)
            let window = image.clamp(x0: Int(b.minX) - reach, y0: Int(b.minY) - Int(h / 2),
                                     x1: Int(b.maxX) + reach, y1: Int(b.maxY) + Int(h / 2) + 1)
            let parts = pieces(of: window, image: image, background: reading.background)
                .filter { !$0.clipped }
            var members = parts.filter { $0.rect.intersects(b.insetBy(dx: 1, dy: 1)) }
            guard !members.isEmpty else { return nil }
            var rest = parts.filter { part in !members.contains { $0.id == part.id } }
            var span = members.reduce(b) { $0.union($1.rect) }
            var grew = true
            while grew {
                grew = false
                for (i, part) in rest.enumerated().reversed() {
                    let r = part.rect
                    let ph = Double(r.height)
                    let overlap = Double(min(r.maxY, b.maxY) - max(r.minY, b.minY))
                    guard ph >= 0.6 * h, ph <= 1.6 * h, overlap >= 0.6 * min(ph, h),
                          Double(r.width) >= 0.3 * ph else { continue }
                    let gap = Double(max(r.minX - span.maxX, span.minX - r.maxX))
                    guard gap <= linkPx else { continue }
                    members.append(part)
                    span = span.union(r)
                    rest.remove(at: i)
                    grew = true
                }
            }
            // The shape itself may count once only (a crescent's own piece).
            let others = members.filter { !b.insetBy(dx: -2, dy: -2).contains($0.rect) }
            guard !others.isEmpty else { return nil }
            return span
        }
    }

    /// What a box drawn around something is ABOUT: the bounding box of
    /// everything wholly inside it, or nil when nothing is.
    ///
    /// The background is read off the box's own rim. Anything the box cuts
    /// through is left out, along with whatever sits within `link` px of it,
    /// since a word the box cuts in half is still one word and its first two
    /// letters are not what anybody drew a box around. `slack` lets a box
    /// drawn a little tight still find the edge just outside it.
    public static func content(in box: CGRect, luma: LumaField, slack: Double = 8,
                               link: Double = 8, minElement: Double = 4) -> CGRect? {
        guard !luma.isEmpty else { return nil }
        let r = box.standardized.insetBy(dx: CGFloat(-slack), dy: CGFloat(-slack))
        return luma.samples.withUnsafeBufferPointer { s -> CGRect? in
            let image = Image(s: s, w: luma.width, h: luma.height)
            let window = image.clamp(x0: Int(r.minX.rounded(.down)), y0: Int(r.minY.rounded(.down)),
                                     x1: Int(r.maxX.rounded(.up)), y1: Int(r.maxY.rounded(.up)))
            guard window.w >= 3, window.h >= 3,
                  let background = rimBackground(of: window, image: image) else { return nil }
            let parts = pieces(of: window, image: image, background: background)
                .filter { $0.count >= 4 }
            guard !parts.isEmpty else { return nil }
            // Clusters: parts within `link` of each other belong together.
            var root = Array(0..<parts.count)
            func find(_ i: Int) -> Int {
                var i = i
                while root[i] != i { root[i] = root[root[i]]; i = root[i] }
                return i
            }
            // A sweep from left to right: a screenful of text is thousands of
            // letters, and every pair of them is too many to compare.
            let l = CGFloat(link)
            let order = parts.indices.sorted { parts[$0].rect.minX < parts[$1].rect.minX }
            for (k, i) in order.enumerated() {
                let grown = parts[i].rect.insetBy(dx: -l, dy: -l)
                for j in order[(k + 1)...] {
                    guard parts[j].rect.minX <= grown.maxX else { break }
                    if grown.intersects(parts[j].rect) { root[find(i)] = find(j) }
                }
            }
            // A part the box cuts is out, and so is anything small within
            // `link` of it: a word the box cuts in half is one word. Something
            // big inside the box (an avatar between two the box cuts) is what
            // the box was drawn around, whatever it touches.
            var cut = Set<Int>()
            for (i, part) in parts.enumerated() where part.clipped { cut.insert(find(i)) }
            let regionArea = Double(window.w * window.h)
            let kept = parts.indices.filter { i in
                guard !parts[i].clipped else { return false }
                guard cut.contains(find(i)) else { return true }
                return Double(parts[i].rect.width * parts[i].rect.height) >= 0.2 * regionArea
            }
            guard let first = kept.first else { return nil }
            var span = parts[first].rect
            for i in kept.dropFirst() { span = span.union(parts[i].rect) }
            guard Double(span.width) >= minElement, Double(span.height) >= minElement else { return nil }
            if kept.count == 1 {
                let piece = trace(from: parts[first].seed, in: image, background: background,
                                  bound: window)
                return piece.clipped ? span : completedCircle(piece)
            }
            return span
        }
    }

    // MARK: Reading the piece under the pointer

    /// The piece of not-background (eight way) the pointer is on, against
    /// `background`, as long as it closes inside `limit` and steps off the
    /// background crisply. Only the piece itself is visited, so a hover costs
    /// what the thing under it is big, not what the window is.
    private static func body(at px: Int, _ py: Int, in image: Image, background: Int,
                             minElement: Double, limit: Int) -> Reading? {
        // One trace out to the full reach: it only ever visits the piece
        // itself, so a bigger bound costs nothing unless the piece is big, and
        // a piece that runs past it is a panel, not a shape.
        let bound = image.clamp(x0: px - limit, y0: py - limit, x1: px + limit + 1, y1: py + limit + 1)
        let piece = trace(from: (py - bound.y0) * bound.w + (px - bound.x0), in: image,
                          background: background, bound: bound)
        guard !piece.clipped else { return nil }
        // A real shape steps off its background; a patch of a smooth photo
        // that sits near the background's colour fades out of it.
        guard isCrisp(piece, in: image, background: background) else { return nil }
        let rect = completedCircle(piece)
        guard Double(rect.width) >= minElement, Double(rect.height) >= minElement else { return nil }
        return Reading(bounds: rect, onBody: true, background: background)
    }

    /// The pointer is on the background's own colour. When that is a small
    /// hole in something (a letter cut out of an initials avatar, a glyph
    /// knocked out of an icon's tile), the something is what is meant; a big
    /// stretch of background is not a shape, and is left to the box reader.
    private static func cutOut(at px: Int, _ py: Int, in image: Image, background: Int,
                               minElement: Double, limit: Int) -> Reading? {
        let reach = min(limit, Int((4 * minElement).rounded()))
        let bound = image.clamp(x0: px - reach, y0: py - reach, x1: px + reach + 1, y1: py + reach + 1)
        let holeLimit = Int((2 * minElement) * (2 * minElement))
        guard let hole = traceHole(at: px, py, in: image, background: background, bound: bound,
                                   limit: holeLimit) else { return nil }
        // Whatever rings the hole: the first paint on each side of it.
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
            var x = px, y = py
            while x >= bound.x0, y >= bound.y0, x < bound.x0 + bound.w, y < bound.y0 + bound.h,
                  abs(Int(image.s[y * image.w + x]) - background) <= tolerance {
                x += dx
                y += dy
            }
            guard x >= 0, y >= 0, x < image.w, y < image.h,
                  let ring = body(at: x, y, in: image, background: background,
                                  minElement: minElement, limit: limit),
                  ring.bounds.insetBy(dx: -1, dy: -1).contains(hole) else { continue }
            return ring
        }
        return nil
    }

    /// The pixels a piece of not-background covers, read row by row and
    /// column by column, which is all its edge tests need.
    private struct Trace {
        var rect: CGRect
        /// The open sides of the bound it runs on past: 0 left, 1 top, 2
        /// right, 3 bottom.
        var clippedSides: Set<Int>
        var clipped: Bool { !clippedSides.isEmpty }
        /// Per row of `rect`, the leftmost and rightmost pixel (image x).
        var rowMin: [Int], rowMax: [Int]
        /// Per column of `rect`, the topmost and bottommost pixel (image y).
        var colMin: [Int], colMax: [Int]
    }

    /// The eight-way piece of not-background holding window pixel `seed`.
    private static func trace(from seed: Int, in image: Image, background: Int,
                              bound: Window) -> Trace {
        let w = bound.w, h = bound.h
        var seen = [UInt8](repeating: 0, count: w * h)
        var rowMin = [Int](repeating: Int.max, count: h), rowMax = [Int](repeating: -1, count: h)
        var colMin = [Int](repeating: Int.max, count: w), colMax = [Int](repeating: -1, count: w)
        var clippedSides = Set<Int>()
        // Scanline fill: each popped seed is widened into the whole run of
        // not-background it sits in, and only the rows above and below that run
        // are searched for more, so a pixel is looked at a handful of times
        // rather than once per neighbour.
        var stack: [Int32] = [Int32(seed)]
        seen.withUnsafeMutableBufferPointer { seen in
        rowMin.withUnsafeMutableBufferPointer { rowMin in
        rowMax.withUnsafeMutableBufferPointer { rowMax in
        colMin.withUnsafeMutableBufferPointer { colMin in
        colMax.withUnsafeMutableBufferPointer { colMax in
            @inline(__always) func paint(_ x: Int, _ y: Int) -> Bool {
                abs(Int(image.s[(bound.y0 + y) * image.w + bound.x0 + x]) - background) > tolerance
            }
            while let top = stack.popLast() {
                let i = Int(top)
                let y = i / w
                var l = i % w, r = l
                guard seen[i] == 0 else { continue }
                while l > 0, seen[y * w + l - 1] == 0, paint(l - 1, y) { l -= 1 }
                while r < w - 1, seen[y * w + r + 1] == 0, paint(r + 1, y) { r += 1 }
                for x in l...r {
                    seen[y * w + x] = 1
                    if y < colMin[x] { colMin[x] = y }
                    if y > colMax[x] { colMax[x] = y }
                }
                if l < rowMin[y] { rowMin[y] = l }
                if r > rowMax[y] { rowMax[y] = r }
                if l == 0, bound.x0 > 0 { clippedSides.insert(0) }
                if r == w - 1, bound.x0 + w < image.w { clippedSides.insert(2) }
                if y == 0, bound.y0 > 0 { clippedSides.insert(1) }
                if y == h - 1, bound.y0 + h < image.h { clippedSides.insert(3) }
                // Past the bound it is too big to be a shape, and nothing
                // more about it is wanted.
                if !clippedSides.isEmpty {
                    stack.removeAll()
                    break
                }
                // Eight-way: the runs above and below may start one pixel
                // diagonally past either end.
                for ny in [y - 1, y + 1] where ny >= 0 && ny < h {
                    var x = max(0, l - 1)
                    let end = min(w - 1, r + 1)
                    while x <= end {
                        if seen[ny * w + x] == 0, paint(x, ny) {
                            stack.append(Int32(ny * w + x))
                            // One seed per run: skip to the run's end.
                            while x <= end, paint(x, ny) { x += 1 }
                        } else {
                            x += 1
                        }
                    }
                }
            }
        }}}}}
        let rows = rowMin.indices.filter { rowMax[$0] >= 0 }
        let cols = colMin.indices.filter { colMax[$0] >= 0 }
        guard let top = rows.first, let bottom = rows.last,
              let left = cols.first, let right = cols.last else {
            return Trace(rect: .zero, clippedSides: clippedSides, rowMin: [], rowMax: [], colMin: [], colMax: [])
        }
        return Trace(rect: CGRect(x: bound.x0 + left, y: bound.y0 + top,
                                  width: right - left + 1, height: bottom - top + 1),
                     clippedSides: clippedSides,
                     rowMin: rowMin[top...bottom].map { $0 == Int.max ? $0 : $0 + bound.x0 },
                     rowMax: rowMax[top...bottom].map { $0 < 0 ? $0 : $0 + bound.x0 },
                     colMin: colMin[left...right].map { $0 == Int.max ? $0 : $0 + bound.y0 },
                     colMax: colMax[left...right].map { $0 < 0 ? $0 : $0 + bound.y0 })
    }

    /// The four-way patch of background colour holding (px, py), if it closes
    /// inside `bound` within `limit` pixels.
    private static func traceHole(at px: Int, _ py: Int, in image: Image, background: Int,
                                  bound: Window, limit: Int) -> CGRect? {
        let w = bound.w
        var seen = [UInt8](repeating: 0, count: w * bound.h)
        let seed = (py - bound.y0) * w + (px - bound.x0)
        var stack: [Int32] = [Int32(seed)]
        seen[seed] = 1
        var count = 0
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        while let top = stack.popLast() {
            let i = Int(top)
            let x = i % w, y = i / w
            count += 1
            guard count <= limit, x > 0, y > 0, x < w - 1, y < bound.h - 1 else { return nil }
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            @inline(__always) func visit(_ j: Int) {
                guard seen[j] == 0 else { return }
                seen[j] = 1
                if abs(Int(image.s[bound.imageIndex(j)]) - background) <= tolerance {
                    stack.append(Int32(j))
                }
            }
            visit(i - 1)
            visit(i + 1)
            visit(i - w)
            visit(i + w)
        }
        return CGRect(x: bound.x0 + minX, y: bound.y0 + minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Whether a piece steps off the background at its edge: one pixel in
    /// from its outermost pixel on each row and column, most of it reads
    /// clearly apart from the background.
    private static func isCrisp(_ piece: Trace, in image: Image, background: Int) -> Bool {
        var tried = 0, crisp = 0
        func check(_ x: Int, _ y: Int) {
            guard x >= 0, y >= 0, x < image.w, y < image.h else { return }
            tried += 1
            if abs(Int(image.s[y * image.w + x]) - background) >= 2 * tolerance { crisp += 1 }
        }
        let x0 = Int(piece.rect.minX), y0 = Int(piece.rect.minY)
        for (k, lo) in piece.rowMin.enumerated() where lo != Int.max {
            check(lo + 1, y0 + k)
            check(piece.rowMax[k] - 1, y0 + k)
        }
        for (k, lo) in piece.colMin.enumerated() where lo != Int.max {
            check(x0 + k, lo + 1)
            check(x0 + k, piece.colMax[k] - 1)
        }
        return tried > 0 && Double(crisp) >= 0.6 * Double(tried)
    }

    // MARK: Pixels

    private struct Image {
        let s: UnsafeBufferPointer<UInt8>
        let w: Int
        let h: Int

        func clamp(x0: Int, y0: Int, x1: Int, y1: Int) -> Window {
            let a = max(0, min(x0, w - 1)), b = max(0, min(y0, h - 1))
            let c = max(a + 1, min(x1, w)), d = max(b + 1, min(y1, h))
            return Window(x0: a, y0: b, w: c - a, h: d - b, imageW: w, imageH: h)
        }
    }

    /// A rectangle of the image being read. Index `i` is window-local.
    private struct Window {
        let x0: Int, y0: Int, w: Int, h: Int
        let imageW: Int, imageH: Int

        /// Whether a window-local pixel sits on a side of the window that is
        /// not also the image's own edge: touching it means the thing runs on
        /// past what the window can see.
        func onOpenSide(_ x: Int, _ y: Int) -> Bool {
            (x == 0 && x0 > 0) || (y == 0 && y0 > 0)
                || (x == w - 1 && x0 + w < imageW) || (y == h - 1 && y0 + h < imageH)
        }

        func imageIndex(_ i: Int) -> Int { (y0 + i / w) * imageW + x0 + i % w }
    }

    /// The largest shape a hover traces, in `minElement`s from the pointer
    /// to its far side: 160 points either way on a 2x capture.
    private static let largest = 8.0

    /// How far, in `minElement`s, the nearest edge has to be from a pointer
    /// on flat paint for that paint to be a broad fill rather than a shape.
    private static let flatFill = 3.0

    /// Whether the pointer's pixel and its eight neighbours are one colour.
    private static func isFlat(at px: Int, _ py: Int, in image: Image) -> Bool {
        let v = Int(image.s[py * image.w + px])
        for y in max(0, py - 1)...min(image.h - 1, py + 1) {
            for x in max(0, px - 1)...min(image.w - 1, px + 1)
            where abs(Int(image.s[y * image.w + x]) - v) > 1 {
                return false
            }
        }
        return true
    }

    /// How many pixels in a row, each within a level of the last, make a walk
    /// call a stretch flat.
    private static let flatRun = 6

    /// The flat colours that surround the pointer, nearest first: eight walks
    /// outward, each noting every flat stretch it reaches across an edge. A
    /// colour most walks reach is all round the pointer (the card an avatar
    /// sits on, then the page the card sits on); one only a walk or two reach
    /// is a patch inside the thing (its hair, its shirt) or beside it.
    /// Also says how far the nearest edge is along the four straight walks.
    private static func surroundings(of px: Int, _ py: Int, in image: Image,
                                     reach: Int) -> (colours: [Int], nearestEdge: Int) {
        var walks: [[(value: Int, distance: Int)]] = []
        var nearestEdge = Int.max
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
            var found: [(value: Int, distance: Int)] = []
            var prev = Int(image.s[py * image.w + px])
            var crossed = false, run = 0, start = prev
            for step in 1...reach {
                let x = px + dx * step, y = py + dy * step
                guard x >= 0, y >= 0, x < image.w, y < image.h else { break }
                let v = Int(image.s[y * image.w + x])
                if abs(v - prev) > tolerance {
                    crossed = true
                    if dx == 0 || dy == 0 { nearestEdge = min(nearestEdge, step) }
                }
                if run > 0 && abs(v - start) <= 1 {
                    run += 1
                } else {
                    run = 1
                    start = v
                }
                prev = v
                if crossed, run >= flatRun {
                    found.append((start, step))
                    crossed = false
                    if found.count >= maxStretches { break }
                }
            }
            if !found.isEmpty { walks.append(found) }
        }
        guard !walks.isEmpty else { return ([], nearestEdge) }
        let needed = max(3, Int((0.6 * Double(walks.count)).rounded(.up)))
        var colours: [(value: Int, reach: Double)] = []
        for walk in walks {
            for stretch in walk where !colours.contains(where: { abs($0.value - stretch.value) <= flatness }) {
                var hits = 0, distance = 0
                for other in walks {
                    if let match = other.first(where: { abs($0.value - stretch.value) <= flatness }) {
                        hits += 1
                        distance += match.distance
                    }
                }
                if hits >= needed { colours.append((stretch.value, Double(distance) / Double(hits))) }
            }
        }
        return (colours.sorted { $0.reach < $1.reach }.map(\.value), nearestEdge)
    }

    /// How many flat stretches one walk notes before it stops.
    private static let maxStretches = 6

    /// The commonest brightness on the window's rim, if enough of the rim
    /// agrees on it to call it the background.
    private static func rimBackground(of window: Window, image: Image) -> Int? {
        var histogram = [Int](repeating: 0, count: 256)
        var total = 0
        func vote(_ x: Int, _ y: Int) {
            histogram[Int(image.s[(window.y0 + y) * image.w + window.x0 + x])] += 1
            total += 1
        }
        for x in 0..<window.w {
            vote(x, 0)
            if window.h > 1 { vote(x, window.h - 1) }
        }
        if window.h > 2 {
            for y in 1..<(window.h - 1) {
                vote(0, y)
                if window.w > 1 { vote(window.w - 1, y) }
            }
        }
        guard total > 0 else { return nil }
        // The value with the most rim within `flatness` of it.
        var prefix = [Int](repeating: 0, count: 257)
        for v in 0..<256 { prefix[v + 1] = prefix[v] + histogram[v] }
        var best = 0, votes = -1
        for v in 0..<256 {
            let n = prefix[min(255, v + flatness) + 1] - prefix[max(0, v - flatness)]
            if n > votes || (n == votes && histogram[v] > histogram[best]) {
                best = v
                votes = n
            }
        }
        guard Double(votes) >= rimAgreement * Double(total) else { return nil }
        return best
    }

    /// One connected piece of a window.
    private struct Part {
        var id: Int
        /// One of its pixels, window-local.
        var seed: Int
        var rect: CGRect
        var count: Int
        /// Runs on past an open side of the window.
        var clipped: Bool
    }

    /// Every piece of not-background in the window, after the background is
    /// flooded in from the rim (four way, so a shape's diagonal antialiasing
    /// is a wall and the inside of a ring is not background). A piece is
    /// eight-way connected, holes and all.
    ///
    /// Both floods are scanline fills over one byte per pixel, so a box drawn
    /// round a whole screen is a few passes over it, not a stack entry per
    /// pixel per neighbour.
    private static func pieces(of window: Window, image: Image, background: Int) -> [Part] {
        let w = window.w, h = window.h
        var mask = [UInt8](repeating: 0, count: w * h)
        var stack: [Int32] = []
        var parts: [Part] = []
        mask.withUnsafeMutableBufferPointer { mask in
            @inline(__always) func isBackground(_ x: Int, _ y: Int) -> Bool {
                abs(Int(image.s[(window.y0 + y) * image.w + window.x0 + x]) - background) <= tolerance
            }
            // One scanline flood. `outside` floods background (mark 1, four
            // way); otherwise it floods whatever the background left (mark 2,
            // eight way).
            func fill(from seed: Int, outside: Bool) -> Part {
                let mark: UInt8 = outside ? 1 : 2
                @inline(__always) func admits(_ x: Int, _ y: Int) -> Bool {
                    mask[y * w + x] == 0 && (!outside || isBackground(x, y))
                }
                var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1, count = 0
                var clipped = false
                mask[seed] = mark
                stack.append(Int32(seed))
                while let top = stack.popLast() {
                    let i = Int(top)
                    let y = i / w
                    var l = i % w, r = l
                    while l > 0, admits(l - 1, y) { l -= 1; mask[y * w + l] = mark }
                    while r < w - 1, admits(r + 1, y) { r += 1; mask[y * w + r] = mark }
                    count += r - l + 1
                    minX = min(minX, l); maxX = max(maxX, r)
                    minY = min(minY, y); maxY = max(maxY, y)
                    if window.onOpenSide(l, y) || window.onOpenSide(r, y) { clipped = true }
                    let lo = outside ? l : max(0, l - 1), hi = outside ? r : min(w - 1, r + 1)
                    for ny in [y - 1, y + 1] where ny >= 0 && ny < h {
                        var x = lo
                        while x <= hi {
                            guard admits(x, ny) else { x += 1; continue }
                            mask[ny * w + x] = mark
                            stack.append(Int32(ny * w + x))
                            x += 1
                            while x <= hi, admits(x, ny) { x += 1 }
                        }
                    }
                }
                let rect = CGRect(x: window.x0 + minX, y: window.y0 + minY,
                                  width: maxX - minX + 1, height: maxY - minY + 1)
                return Part(id: parts.count, seed: seed, rect: rect, count: count, clipped: clipped)
            }
            for x in 0..<w {
                for y in [0, h - 1] where mask[y * w + x] == 0 && isBackground(x, y) {
                    _ = fill(from: y * w + x, outside: true)
                }
            }
            for y in 0..<h {
                for x in [0, w - 1] where mask[y * w + x] == 0 && isBackground(x, y) {
                    _ = fill(from: y * w + x, outside: true)
                }
            }
            for i in 0..<(w * h) where mask[i] == 0 {
                parts.append(fill(from: i, outside: false))
            }
        }
        return parts
    }

    // MARK: A circle with a piece hidden

    /// The whole circle a crescent is the visible part of, or the piece's own
    /// box when it is not one.
    ///
    /// In an avatar stack every avatar but one is cut by the ring of the one
    /// in front, and a spec quotes the avatar's size, not the sliver that
    /// shows. When a piece is narrower than it is tall and the side it shows
    /// whole follows a circle as tall as the piece, it is that circle (and the
    /// same turned on its side for a vertical stack).
    private static func completedCircle(_ piece: Trace) -> CGRect {
        let r = piece.rect
        let wide = Int(r.width), tall = Int(r.height)
        guard abs(wide - tall) > 2, min(wide, tall) >= 6 else { return r }
        let horizontal = wide < tall
        let diameter = Double(horizontal ? tall : wide)
        let span = Double(horizontal ? wide : tall)
        let origin = horizontal ? Int(r.minX) : Int(r.minY)
        // Leading and trailing extent along each scan line, from the piece's
        // own start.
        let lead = (horizontal ? piece.rowMin : piece.colMin).map { $0 == Int.max ? -1 : $0 - origin }
        let trail = (horizontal ? piece.rowMax : piece.colMax).map { $0 < 0 ? -1 : $0 - origin }
        let radius = diameter / 2
        func follows(_ edge: [Int], fromLead: Bool) -> Bool {
            var tried = 0, fits = 0
            for (line, at) in edge.enumerated() where at >= 0 {
                let offset = Double(line) + 0.5 - radius
                guard abs(offset) <= 0.8 * radius else { continue }
                let chord = (radius * radius - offset * offset).squareRoot()
                // A lead edge is the circle's near side; a trail edge is its
                // far side, on a circle that starts `diameter` before the
                // piece ends.
                let expected = fromLead ? radius - chord : span - radius + chord
                let measured = fromLead ? Double(at) : Double(at) + 1
                tried += 1
                if abs(measured - expected) <= 1.5 { fits += 1 }
            }
            return tried >= 4 && Double(fits) >= 0.85 * Double(tried)
        }
        let d = CGFloat(diameter)
        if follows(lead, fromLead: true) {
            return horizontal ? CGRect(x: r.minX, y: r.minY, width: d, height: r.height)
                : CGRect(x: r.minX, y: r.minY, width: r.width, height: d)
        }
        if follows(trail, fromLead: false) {
            return horizontal ? CGRect(x: r.maxX - d, y: r.minY, width: d, height: r.height)
                : CGRect(x: r.minX, y: r.maxY - d, width: r.width, height: d)
        }
        return r
    }
}

