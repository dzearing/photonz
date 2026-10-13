import CoreGraphics
import Foundation

/// Finds a button, a pill or a card in a screenshot by where its fill ENDS,
/// whatever glows round it (the user, 2026-10-13: "the size tool's edge
/// detection is great for text but hoooooorible for just objects ... it will
/// NOT measure the width /height of the button").
///
/// Size mode's other picture readers each miss one of these. The pair reader
/// (`ElementBounds`) needs two straight edges that agree, and a pill's ends
/// are round. The shape reader (`ShapeBounds`) needs the thing to step
/// crisply off its background all the way round and to fit in 160 points,
/// and a purple pill with a purple glow under it does neither. Both read
/// brightness only, so a red button as bright as its grey page is invisible
/// to them.
///
/// This one grows a region out from the pointer, always taking the pixel
/// that looks most like what it already has, and notes the region's box at
/// every step. A thing with a real edge makes that box STAND STILL: once the
/// fill is in, the next thing to take is the glow or the page, which looks
/// clearly different, so a long stretch of the growth adds nothing to the
/// box. A glow or a shadow never does that, because it fades. So a stretch
/// where the box holds still is an object, and each of its sides is placed
/// where that side held still longest: half way through an antialiased edge,
/// and inside the glow, never out where it fades.
///
/// The growth runs two ways and both answers are offered: by likeness to the
/// colour under the pointer (a gradient pill is all one purple next to a near
/// black glow; a white card is all white next to its grey shadow), and by
/// difference from the background round it (the pill from one of the white
/// letters on it; the ring of a bordered button from the page colour inside
/// it). Colour counts as well as brightness (`LumaField.opponent`).
public enum ObjectBounds {

    /// How far (0...255) a pixel may sit from the background and still BE
    /// background, as `ShapeBounds.tolerance`.
    public static let tolerance = 9

    /// How far from the pointer a hover reads, in `minElement`s: 1600 points
    /// either way, past the far side of any button, banner or card on a
    /// screen. The window costs nothing it does not visit: a growth only
    /// touches the region it takes in and its rim.
    static let reach = 160.0

    /// The most pixels one hover's growths take in between them before they
    /// give up, which is what keeps a hover inside a frame. Measured on the
    /// user's own 3456 x 2234 capture, release build, 2026-10-13: about 27 ns
    /// a pixel, so the slowest hover there (open page, a line of body text, a
    /// big panel) took 11 to 19 ms all readers together, and the download
    /// pill 4.4 ms. A million pixels is a 700 x 350 point card at 2x; past
    /// that the pair reader, which reads panels, has the say.
    static let hoverBudget = 1_000_000

    /// The same for a box, which reads from five points and may be drawn
    /// round the whole screen: 30 ms for a box round all of that capture.
    static let boxBudget = 2_400_000

    // MARK: Hover

    /// The objects under `point`, innermost first: every stretch of a growth
    /// from the pointer whose box held still. Empty on open background.
    public static func objects(at point: CGPoint, in field: LumaField,
                               minElement: Double = ElementBounds.defaultMinElement) -> [CGRect] {
        reading(at: point, in: field, minElement: minElement).objects
    }

    /// What a hover reads: the objects under the pointer, innermost first, and
    /// the brightness (0...255) of the background they were read against.
    public struct Reading: Equatable, Sendable {
        public var objects: [CGRect]
        public var background: Int

        public static let none = Reading(objects: [], background: 0)
    }

    public static func reading(at point: CGPoint, in field: LumaField,
                               minElement: Double = ElementBounds.defaultMinElement) -> Reading {
        guard !field.isEmpty, minElement > 0 else { return .none }
        let px = Int(point.x.rounded(.down)), py = Int(point.y.rounded(.down))
        guard px >= 0, py >= 0, px < field.width, py < field.height else { return .none }
        let r = max(16, Int((reach * minElement).rounded()))
        return Pixels.with(field) { image in
            let window = image.clamp(x0: px - r, y0: py - r, x1: px + r + 1, y1: py + r + 1)
            var budget = hoverBudget
            return read(at: px, py, in: image, window: window, minElement: minElement, budget: &budget)
        }
    }

    // MARK: A box

    /// The biggest object wholly inside `box` (`slack` px to spare), or nil.
    /// Read from five points spread over the box, so a box whose middle falls
    /// between two things still finds them.
    public static func content(in box: CGRect, field: LumaField, slack: Double = 8,
                               minElement: Double = 4) -> CGRect? {
        guard !field.isEmpty, minElement > 0 else { return nil }
        let r = box.standardized.insetBy(dx: CGFloat(-slack), dy: CGFloat(-slack))
        return Pixels.with(field) { image -> CGRect? in
            let window = image.clamp(x0: Int(r.minX.rounded(.down)), y0: Int(r.minY.rounded(.down)),
                                     x1: Int(r.maxX.rounded(.up)), y1: Int(r.maxY.rounded(.up)))
            guard window.w >= 3, window.h >= 3 else { return nil }
            var best: CGRect?
            var budget = boxBudget
            for (fx, fy) in [(0.5, 0.5), (0.25, 0.5), (0.75, 0.5), (0.5, 0.25), (0.5, 0.75)] {
                let x = window.x0 + Int(Double(window.w) * fx), y = window.y0 + Int(Double(window.h) * fy)
                for found in read(at: x, y, in: image, window: window, minElement: minElement,
                                  budget: &budget, rimFallback: true).objects
                where best.map({ found.width * found.height > $0.width * $0.height }) ?? true {
                    best = found
                }
            }
            return best
        }
    }

    /// What a box drawn in Size mode measures: the biggest object wholly
    /// inside it, unless the box was drawn round a group (a row of avatars, a
    /// word, two buttons), which `ShapeBounds.content` reads as a whole.
    ///
    /// The object wins when nothing but soft paint touches it (its glow, its
    /// shadow, the page) and either all the group adds is soft too, or it is
    /// most of the group, the rest being small print the box took in beside
    /// it. A patch of one colour inside a photo is touched by the rest of the
    /// photo, and the group, the photo, wins.
    public static func snap(_ box: CGRect, field: LumaField, slack: Double, link: Double,
                            minElement: Double) -> CGRect? {
        let group = ShapeBounds.content(in: box, luma: field, slack: slack, link: link,
                                        minElement: minElement)
        guard let object = content(in: box, field: field, slack: slack, minElement: minElement) else {
            return group
        }
        guard let group, group.insetBy(dx: -2, dy: -2).contains(object) else { return object }
        let r = box.standardized.insetBy(dx: CGFloat(-slack), dy: CGFloat(-slack))
        let wins = Pixels.with(field) { image -> Bool in
            let window = image.clamp(x0: Int(r.minX.rounded(.down)), y0: Int(r.minY.rounded(.down)),
                                     x1: Int(r.maxX.rounded(.up)), y1: Int(r.maxY.rounded(.up)))
            guard let background = rimColour(of: window, in: image) else { return false }
            let ring = CGFloat(2 + max(2, (minElement / 4).rounded()))
            let bounds = CGRect(x: 0, y: 0, width: image.w, height: image.h)
            guard isSoft(object.insetBy(dx: -ring, dy: -ring).intersection(bounds), around: object,
                         in: image, background: background) else { return false }
            return isSoft(group.intersection(bounds), around: object, in: image, background: background)
                || Double(object.width * object.height) >= 0.5 * Double(group.width * group.height)
        }
        return wins ? object : group
    }

    // MARK: Reading

    private static func read(at px: Int, _ py: Int, in image: Pixels, window: Window,
                             minElement: Double, budget: inout Int,
                             rimFallback: Bool = false) -> Reading {
        let seed = py * image.w + px
        let own = image.colour(seed)
        var backgrounds = surroundings(of: px, py, in: image, window: window)
        // A box drawn tight round something with a glow may hold no flat page
        // at all; the colour its rim crosses most is the best guess there is.
        if backgrounds.isEmpty, rimFallback, let rim = rimColour(of: window, in: image) {
            backgrounds = [rim]
        }
        // No flat colour anywhere round the pointer: it is on open page, or
        // inside something bigger than the window, and neither is an object.
        guard let nearest = backgrounds.first else { return .none }
        var alike: [CGRect] = []
        var apart: [CGRect] = []
        // By likeness to the pointer's own colour, stopping short of the page
        // (joining the page would only cost time and can never hold still).
        let ceiling = image.distance(seed, nearest)
        if ceiling > tolerance {
            let growth = grow(from: seed, in: image, window: window,
                              metric: Likeness(image: image, colour: own), stop: ceiling,
                              budget: &budget)
            alike += plateaus(growth, minElement: minElement, against: nil)
        }
        // By difference from the background round it.
        for background in backgrounds.prefix(2) {
            let metric = Difference(image: image, background: background)
            if image.distance(seed, background) > tolerance {
                let growth = grow(from: seed, in: image, window: window, metric: metric,
                                  stop: 256 - tolerance, budget: &budget)
                apart += plateaus(growth, minElement: minElement, against: background)
                continue
            }
            // The pointer is on the background's colour: inside a ring (the
            // white middle of a bordered button on a white page). The ring is
            // the first paint on each side.
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                var x = px, y = py
                while x >= window.x0, y >= window.y0, x < window.x0 + window.w, y < window.y0 + window.h,
                      image.distance(y * image.w + x, background) <= tolerance {
                    x += dx
                    y += dy
                }
                guard x >= window.x0, y >= window.y0, x < window.x0 + window.w,
                      y < window.y0 + window.h else { continue }
                let growth = grow(from: y * image.w + x, in: image, window: window, metric: metric,
                                  stop: 256 - tolerance, budget: &budget)
                let point = CGPoint(x: Double(px) + 0.5, y: Double(py) + 0.5)
                apart += plateaus(growth, minElement: minElement, against: background)
                    .filter { $0.contains(point) }
            }
        }
        // A patch of one colour inside something that stands off the page
        // (the shirt in a photo) is a piece of it, unless all that lies
        // between the two is soft: then the outer reading is the patch's own
        // shadow or glow, and the patch is the object.
        let same = sameReading(minElement)
        var parts = Set<Int>(), halos = Set<Int>()
        for (k, outer) in apart.enumerated() {
            for (n, inner) in alike.enumerated()
            where outer.contains(inner) && !close(outer, inner, same) {
                if isSoft(outer, around: inner, in: image, background: nearest) {
                    halos.insert(k)
                } else {
                    parts.insert(n)
                }
            }
        }
        let found = alike.enumerated().filter { !parts.contains($0.offset) }.map(\.element)
            + apart.enumerated().filter { !halos.contains($0.offset) }.map(\.element)
        return Reading(objects: ladder(found, minElement: minElement), background: nearest.l)
    }

    /// How close two readings of one thing come, side by side.
    private static func sameReading(_ minElement: Double) -> CGFloat {
        CGFloat(max(3, (minElement / 10).rounded() + 1))
    }

    private static func close(_ a: CGRect, _ b: CGRect, _ same: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= same && abs(a.minY - b.minY) <= same
            && abs(a.maxX - b.maxX) <= same && abs(a.maxY - b.maxY) <= same
    }

    /// How far (0...255) from the background anything between a reading and
    /// one round it may be for that band to be a shadow or a glow, as
    /// `ElementBounds`' halo test.
    private static let haloContrast = 51

    /// Whether everything in `outer` outside `inner` is soft.
    private static func isSoft(_ outer: CGRect, around inner: CGRect, in image: Pixels,
                               background: Colour) -> Bool {
        let own = inner.insetBy(dx: -2, dy: -2)
        for y in Int(outer.minY)..<Int(outer.maxY) {
            for x in Int(outer.minX)..<Int(outer.maxX)
            where !own.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
                if image.distance(y * image.w + x, background) >= haloContrast { return false }
            }
        }
        return true
    }

    /// The commonest colour on a window's rim: the luma most of the rim sits
    /// near, and the average colour of the rim pixels that do.
    private static func rimColour(of window: Window, in image: Pixels) -> Colour? {
        var rim: [Int] = []
        for x in window.x0..<(window.x0 + window.w) {
            rim.append(window.y0 * image.w + x)
            rim.append((window.y0 + window.h - 1) * image.w + x)
        }
        for y in window.y0..<(window.y0 + window.h) {
            rim.append(y * image.w + window.x0)
            rim.append(y * image.w + window.x0 + window.w - 1)
        }
        var histogram = [Int](repeating: 0, count: 256)
        for i in rim { histogram[Int(image.l[i])] += 1 }
        var best = 0, votes = -1
        for v in 0..<256 {
            let n = histogram[max(0, v - flatness)...min(255, v + flatness)].reduce(0, +)
            if n > votes { best = v; votes = n }
        }
        let near = rim.filter { abs(Int(image.l[$0]) - best) <= flatness }
        guard !near.isEmpty else { return nil }
        var sum = Colour(l: 0, rg: 0, yb: 0)
        for i in near {
            let c = image.colour(i)
            sum.l += c.l
            sum.rg += c.rg
            sum.yb += c.yb
        }
        return Colour(l: sum.l / near.count, rg: sum.rg / near.count, yb: sum.yb / near.count)
    }

    /// The readings as a ladder, innermost first. Two readings of one thing
    /// (the two growths agree to within a few px) are one rung, the outer of
    /// the two: a spec quotes the outside of a border.
    private static func ladder(_ found: [CGRect], minElement: Double) -> [CGRect] {
        let same = sameReading(minElement)
        var out: [CGRect] = []
        for rect in found.sorted(by: { $0.width * $0.height > $1.width * $1.height }) {
            if !out.contains(where: { close($0, rect, same) }) { out.append(rect) }
        }
        return out.reversed()
    }

    // MARK: Growing a region

    /// How a pixel ranks in a growth: lower is taken sooner, 0...255.
    private protocol Metric {
        func rank(_ i: Int) -> Int
    }

    /// Likeness to one colour.
    private struct Likeness: Metric {
        let image: Pixels
        let colour: Colour
        @inline(__always) func rank(_ i: Int) -> Int { image.distance(i, colour) }
    }

    /// Difference from the background: the most different pixel is taken first.
    private struct Difference: Metric {
        let image: Pixels
        let background: Colour
        @inline(__always) func rank(_ i: Int) -> Int { 255 - image.distance(i, background) }
    }

    /// The region's box once everything ranked `level` or lower that connects
    /// to the seed is in.
    private struct Step {
        var level: Int
        var x0: Int, y0: Int, x1: Int, y1: Int
    }

    private struct Growth {
        var steps: [Step]
        /// The rank the growth stopped at: the last step holds up to here.
        var end: Int
    }

    /// Grows a four-way region from `seed`, always taking the lowest ranked
    /// pixel on its rim, and notes its box each time the rank rises. Stops
    /// before the first pixel ranked `stop` or more, when the region reaches an
    /// open side of `window` (it runs on past what the window can see), or when
    /// it has spent `budget`. Only steps whose region was complete are kept.
    private static func grow<M: Metric>(from seed: Int, in image: Pixels, window: Window,
                                        metric: M, stop: Int, budget: inout Int) -> Growth {
        let w = window.w, h = window.h
        guard budget > 0 else { return Growth(steps: [], end: 0) }
        let allowed = budget
        // One byte a pixel of the window, zeroed lazily by the system, so a
        // window the size of the screen costs only the pages a growth touches.
        guard let seen = calloc(w * h, 1)?.assumingMemoryBound(to: UInt8.self) else {
            return Growth(steps: [], end: 0)
        }
        defer { free(seen) }
        // The rim, as 256 stacks threaded through one pool: a pixel and the
        // pool slot of the one pushed before it at the same rank.
        let head = UnsafeMutablePointer<Int32>.allocate(capacity: 256)
        head.initialize(repeating: -1, count: 256)
        defer { head.deallocate() }
        var capacity = 1 << 14
        var pixel = UnsafeMutablePointer<Int32>.allocate(capacity: capacity)
        var link = UnsafeMutablePointer<Int32>.allocate(capacity: capacity)
        defer {
            pixel.deallocate()
            link.deallocate()
        }
        var used = 0
        var lowest = 256
        let local = ((seed / image.w) - window.y0) * w + (seed % image.w) - window.x0
        let seedRank = min(255, max(0, metric.rank(seed)))
        seen[local] = 1
        pixel[0] = Int32(local)
        link[0] = -1
        head[seedRank] = 0
        used = 1
        lowest = seedRank
        var steps: [Step] = []
        var level = -1, count = 0
        defer { budget -= count }
        var x0 = Int.max, y0 = Int.max, x1 = -1, y1 = -1
        var end = stop
        var complete = true
        let openLeft = window.x0 > 0, openTop = window.y0 > 0
        let openRight = window.x0 + w < image.w, openBottom = window.y0 + h < image.h
        let imageW = image.w, rowStart = window.y0 * imageW + window.x0
        while true {
            while lowest < 256, head[lowest] < 0 { lowest += 1 }
            guard lowest < 256 else { break }
            let rank = lowest
            if rank >= stop { break }
            if rank > level {
                if level >= 0 { steps.append(Step(level: level, x0: x0, y0: y0, x1: x1, y1: y1)) }
                level = rank
            }
            let slot = Int(head[rank])
            head[rank] = link[slot]
            let i = Int(pixel[slot])
            let y = i / w, x = i - y * w
            if x < x0 { x0 = x }
            if x > x1 { x1 = x }
            if y < y0 { y0 = y }
            if y > y1 { y1 = y }
            count += 1
            if (x == 0 && openLeft) || (y == 0 && openTop) || (x == w - 1 && openRight)
                || (y == h - 1 && openBottom) || count > allowed {
                end = level
                complete = false
                break
            }
            if used + 4 > capacity {
                let more = capacity * 2
                let p = UnsafeMutablePointer<Int32>.allocate(capacity: more)
                let l = UnsafeMutablePointer<Int32>.allocate(capacity: more)
                p.update(from: pixel, count: used)
                l.update(from: link, count: used)
                pixel.deallocate()
                link.deallocate()
                pixel = p
                link = l
                capacity = more
            }
            // The four neighbours, each ranked once, when first seen.
            let base = rowStart + y * imageW + x
            for (j, at, ok) in [(i - 1, base - 1, x > 0), (i + 1, base + 1, x < w - 1),
                                (i - w, base - imageW, y > 0), (i + w, base + imageW, y < h - 1)]
            where ok && seen[j] == 0 {
                seen[j] = 1
                let r = min(255, max(0, metric.rank(at)))
                pixel[used] = Int32(j)
                link[used] = head[r]
                head[r] = Int32(used)
                used += 1
                if r < lowest { lowest = r }
            }
        }
        if complete, level >= 0 {
            steps.append(Step(level: level, x0: x0, y0: y0, x1: x1, y1: y1))
            if lowest >= 256 { end = 256 }
        }
        // Back to image px.
        steps = steps.map { Step(level: $0.level, x0: $0.x0 + window.x0, y0: $0.y0 + window.y0,
                                 x1: $0.x1 + window.x0, y1: $0.y1 + window.y0) }
        return Growth(steps: steps, end: end)
    }

    // MARK: Where the box held still

    /// Every stretch of `growth` whose box held still for long enough to be a
    /// thing with an edge, each side placed where it held longest.
    private static func plateaus(_ growth: Growth, minElement: Double, against background: Colour?) -> [CGRect] {
        let steps = growth.steps
        guard !steps.isEmpty else { return [] }
        // How far a side may wander inside one stretch: an antialiased edge,
        // or a highlight a pixel or two thick along the top of a button.
        let drift = max(1, Int((minElement / 10).rounded()))
        var out: [CGRect] = []
        var i = 0
        while i < steps.count {
            var j = i
            while j + 1 < steps.count, near(steps[j + 1], steps[i], drift) { j += 1 }
            let upper = j + 1 < steps.count ? steps[j + 1].level : growth.end
            let start = steps[i].level
            // A real edge is a clear step, not a few levels of noise: against
            // the background, a quarter of how far the thing stands out from
            // it; by likeness, half of how far the fill already wandered.
            let needed = background == nil
                ? max(tolerance, start / 2)
                : max(tolerance, (255 - start) / 4)
            if upper - start >= needed {
                let rect = settle(steps[i...j], upper: upper)
                if Double(rect.width) >= minElement, Double(rect.height) >= minElement {
                    out.append(rect)
                }
                i = j + 1
            } else {
                i += 1
            }
        }
        return out
    }

    private static func near(_ a: Step, _ b: Step, _ drift: Int) -> Bool {
        abs(a.x0 - b.x0) <= drift && abs(a.y0 - b.y0) <= drift
            && abs(a.x1 - b.x1) <= drift && abs(a.y1 - b.y1) <= drift
    }

    /// Each side at the value it held over the most levels of the stretch;
    /// a tie goes to the outer value.
    private static func settle(_ steps: ArraySlice<Step>, upper: Int) -> CGRect {
        func held(_ side: (Step) -> Int, outward: Int) -> Int {
            var spans: [Int: Int] = [:]
            let all = Array(steps)
            for (k, step) in all.enumerated() {
                let next = k + 1 < all.count ? all[k + 1].level : upper
                spans[side(step), default: 0] += next - step.level
            }
            return spans.max { a, b in
                a.value != b.value ? a.value < b.value : a.key * outward < b.key * outward
            }?.key ?? side(all[0])
        }
        let x0 = held({ $0.x0 }, outward: -1), y0 = held({ $0.y0 }, outward: -1)
        let x1 = held({ $0.x1 }, outward: 1), y1 = held({ $0.y1 }, outward: 1)
        return CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
    }

    // MARK: The background round the pointer

    /// How many pixels in a row, each within a level of the first, make a walk
    /// call a stretch flat.
    private static let flatRun = 6
    /// How tightly two flat stretches must agree to be one colour.
    private static let flatness = 3
    /// How many different flat stretches one walk notes before it stops.
    private static let maxStretches = 24

    /// The flat colours round the pointer, nearest first: eight walks outward,
    /// each noting the flat stretches it reaches once past an edge. A colour most
    /// walks reach is all round the pointer (the card a button sits on, then
    /// the page the card sits on); one only a walk or two reach is a patch of
    /// the thing itself. As `ShapeBounds.surroundings`, in colour.
    private static func surroundings(of px: Int, _ py: Int, in image: Pixels,
                                     window: Window) -> [Colour] {
        var walks: [[(colour: Colour, distance: Int)]] = []
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
            var found: [(colour: Colour, distance: Int)] = []
            var prev = image.colour(py * image.w + px)
            var crossed = false, run = 0
            var start = prev
            var step = 1
            while true {
                let x = px + dx * step, y = py + dy * step
                guard x >= window.x0, y >= window.y0, x < window.x0 + window.w,
                      y < window.y0 + window.h else { break }
                let v = image.colour(y * image.w + x)
                if v.distance(to: prev) > tolerance { crossed = true }
                if run > 0 && v.distance(to: start) <= 1 {
                    run += 1
                } else {
                    run = 1
                    start = v
                }
                prev = v
                // Every flat stretch past the first edge counts, not only the
                // first: a glow fades into the page with no edge between them,
                // and a walk that stopped at the first flat patch of glow
                // would never reach the page.
                if crossed, run == flatRun,
                   !found.contains(where: { $0.colour.distance(to: start) <= flatness }) {
                    found.append((start, step))
                    if found.count >= maxStretches { break }
                }
                step += 1
            }
            if !found.isEmpty { walks.append(found) }
        }
        guard !walks.isEmpty else { return [] }
        let needed = max(3, Int((0.6 * Double(walks.count)).rounded(.up)))
        var colours: [(colour: Colour, reach: Double)] = []
        for walk in walks {
            for stretch in walk
            where !colours.contains(where: { $0.colour.distance(to: stretch.colour) <= flatness }) {
                var hits = 0, distance = 0
                for other in walks {
                    if let match = other.first(where: { $0.colour.distance(to: stretch.colour) <= flatness }) {
                        hits += 1
                        distance += match.distance
                    }
                }
                if hits >= needed { colours.append((stretch.colour, Double(distance) / Double(hits))) }
            }
        }
        return colours.sorted { $0.reach < $1.reach }.map(\.colour)
    }

    // MARK: Pixels

    struct Colour: Equatable {
        var l: Int, rg: Int, yb: Int

        /// How different two colours look: the largest of the three channel
        /// differences.
        @inline(__always) func distance(to o: Colour) -> Int {
            max(abs(l - o.l), abs(rg - o.rg), abs(yb - o.yb))
        }
    }

    struct Pixels {
        let l: UnsafeBufferPointer<UInt8>
        let rg: UnsafeBufferPointer<UInt8>
        let yb: UnsafeBufferPointer<UInt8>
        let hasColour: Bool
        let w: Int, h: Int

        static func with<T>(_ field: LumaField, _ body: (Pixels) -> T) -> T {
            field.samples.withUnsafeBufferPointer { l in
                field.redGreen.withUnsafeBufferPointer { rg in
                    field.yellowBlue.withUnsafeBufferPointer { yb in
                        body(Pixels(l: l, rg: rg, yb: yb, hasColour: field.hasColour,
                                    w: field.width, h: field.height))
                    }
                }
            }
        }

        @inline(__always) func colour(_ i: Int) -> Colour {
            hasColour ? Colour(l: Int(l[i]), rg: Int(rg[i]), yb: Int(yb[i]))
                : Colour(l: Int(l[i]), rg: 128, yb: 128)
        }

        @inline(__always) func distance(_ i: Int, _ c: Colour) -> Int {
            let dl = abs(Int(l[i]) - c.l)
            guard hasColour else { return dl }
            return max(dl, abs(Int(rg[i]) - c.rg), abs(Int(yb[i]) - c.yb))
        }

        func clamp(x0: Int, y0: Int, x1: Int, y1: Int) -> Window {
            let a = max(0, min(x0, w - 1)), b = max(0, min(y0, h - 1))
            let c = max(a + 1, min(x1, w)), d = max(b + 1, min(y1, h))
            return Window(x0: a, y0: b, w: c - a, h: d - b)
        }
    }

    /// A rectangle of the image being read. Local index `i` is window-local.
    struct Window {
        let x0: Int, y0: Int, w: Int, h: Int

        @inline(__always) func imageIndex(_ i: Int, imageW: Int) -> Int {
            (y0 + i / w) * imageW + x0 + i % w
        }
    }
}
