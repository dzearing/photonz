import CoreGraphics
import Foundation

/// Which pixels of a picture carry ink rather than background, as the sweep
/// read it. Kept so the patch can refuse to take a background reading off a
/// letter, a border or a neighbouring word.
///
/// One byte per pixel, top-left origin, row-major — the same shape every other
/// image buffer in the app has.
public struct InkMask: Sendable {
    public let width: Int
    public let height: Int
    /// 1 where the pixel is ink, 0 where it is background.
    public let samples: [UInt8]

    public init(width: Int, height: Int, samples: [UInt8]) {
        guard width > 0, height > 0, samples.count == width * height else {
            self.width = 0
            self.height = 0
            self.samples = []
            return
        }
        self.width = width
        self.height = height
        self.samples = samples
    }

    public static let empty = InkMask(width: 0, height: 0, samples: [])

    public var isEmpty: Bool { width == 0 || height == 0 }

    /// Whether the pixel is ink. Outside the picture reads as background, so a
    /// caller can probe past an edge without bounds-checking every read.
    public func isInk(_ x: Int, _ y: Int) -> Bool {
        guard !isEmpty, x >= 0, y >= 0, x < width, y < height else { return false }
        return samples[y * width + x] == 1
    }
}

/// Every run of text in a picture, found in ONE pass.
///
/// `TextLineBounds` already reads a line of text out of a screenshot, but it
/// reads the line under a PROBE POINT: it votes a local background from a
/// histogram, seeds on the ink nearest the pointer, and grows a band. That is
/// exactly right for a pointer moving over a picture and exactly wrong for
/// reading a whole one — a 12 megapixel capture is hundreds of thousands of
/// probe points, each with its own histogram.
///
/// So this is the same idea turned inside out: find ALL the ink at once, then
/// band it. It keeps `TextLineBounds`' own thresholds (the ink floor, the
/// visible gap that ends a line, the tallest thing that is still one line, the
/// rule test, the coverage and daylight tests) so the two readers agree about
/// what counts as text, and it costs two linear passes over the picture rather
/// than a histogram per pixel.
///
/// Full design: `docs/design/separate-into-layers.md`.
public enum TextRunSweep {

    /// What the sweep found: the runs, and the ink it read them out of.
    public struct Sweep: Sendable {
        /// The runs of text, in READING ORDER — banded by row, then left to
        /// right. In image pixels, top-left origin.
        public let runs: [CGRect]
        /// Which pixels carried ink, for whoever has to sample the background.
        public let ink: InkMask

        public init(runs: [CGRect], ink: InkMask) {
            self.runs = runs
            self.ink = ink
        }

        public static let empty = Sweep(runs: [], ink: .empty)
    }

    /// Ink covering more of a box than this is a fill, not letters — the same
    /// ceiling `TextLineBounds` applies to the line under the pointer.
    public static let maxCoverage = 0.85

    /// A row whose ink runs unbroken across this much of a segment is a rule
    /// (an underline, a divider, the top edge of a card), not a row of letters.
    /// Dropped BEFORE anything is joined to it, which is the sweep's version of
    /// the band `TextLineBounds` stops at a rule.
    public static let ruleFraction = 0.9

    /// The shortest thing that can still be one line of text, as a fraction of
    /// the narrowest box worth offering: half of it, the same floor
    /// `TextLineBounds` puts under the line beneath a pointer (a caption is
    /// short, but it is not a hairline).
    ///
    /// Without it the antialiased under-edge of a bold heading comes back as a
    /// run of its own — a four pixel strip 140 wide, which is not text and is
    /// not anything.
    public static let minHeightRatio = 0.5

    /// How many runs one sweep will return. A dense screenshot offers a couple
    /// of hundred; past that the picture is not a screenshot of a UI and the
    /// answer would be noise either way.
    public static let defaultLimit = 400

    /// Every run of text in `luma`.
    ///
    /// `gap` is the clean stretch that ends a line and `minElement` the
    /// narrowest box worth offering, both in image pixels and both defaulting
    /// to what the measure tool uses on a 2x capture.
    public static func sweep(in luma: LumaField,
                             gap: Double = TextLineBounds.defaultGap,
                             minElement: Double = ElementBounds.defaultMinElement,
                             limit: Int = defaultLimit) -> Sweep {
        guard !luma.isEmpty, gap >= 1, limit > 0 else { return .empty }
        let w = luma.width, h = luma.height
        let gapPx = max(1, Int(gap.rounded()))
        let verticalGap = max(2, gapPx / 8)
        let maxHeight = max(gapPx, Int((TextLineBounds.maxHeightInGaps * gap).rounded()))
        let threshold = Int32((TextLineBounds.inkFloor * 255).rounded())

        // 1 & 2. Ink is any pixel far enough from the brightness around it —
        // read in TWO masks, one for the pixels darker than their surroundings
        // and one for the lighter, because a run of text is one or the other
        // and never both.
        //
        // A single two-sided mask breaks on exactly the text it most needs to
        // read. In a bold heading the gaps BETWEEN the letters are lighter than
        // a mean that the strokes either side have dragged down, so the gaps
        // read as ink too, every row runs unbroken across the word, and the
        // word is thrown away as a rule. Split by which side of the background
        // a pixel falls on, the strokes are in one mask with daylight between
        // them and the gaps are in the other, and the heading reads as words.
        let mean = boxMean(luma.samples, width: w, height: h, radius: gapPx)
        var dark = [UInt8](repeating: 0, count: w * h)
        var light = [UInt8](repeating: 0, count: w * h)
        var ink = [UInt8](repeating: 0, count: w * h)
        luma.samples.withUnsafeBufferPointer { source in
            mean.withUnsafeBufferPointer { background in
                dark.withUnsafeMutableBufferPointer { below in
                    light.withUnsafeMutableBufferPointer { above in
                        ink.withUnsafeMutableBufferPointer { either in
                            for i in 0..<(w * h) {
                                let d = Int32(source[i]) - Int32(background[i])
                                below[i] = d <= -threshold ? 1 : 0
                                above[i] = d >= threshold ? 1 : 0
                                either[i] = below[i] | above[i]
                            }
                        }
                    }
                }
            }
        }
        let mask = InkMask(width: w, height: h, samples: ink)

        // 3 & 4. Rows into segments with rules dropped, segments into runs —
        // each mask on its own, so a component is always one polarity of ink.
        var candidates: [(box: Box, mask: [UInt8])] = []
        for polarity in [dark, light] {
            let (segments, rowRanges) = self.segments(in: polarity, width: w, height: h,
                                                      gap: gapPx)
            guard !segments.isEmpty else { continue }
            candidates += components(of: segments, rowRanges: rowRanges, height: h,
                                     verticalGap: verticalGap)
                .map { ($0, polarity) }
        }

        // 5 & 6. Does each look like words, and does it stand on its own?
        var accepted: [CGRect] = []
        for candidate in candidates.sorted(by: {
            $0.box.width * $0.box.height > $1.box.width * $1.box.height
        }) {
            let box = candidate.box
            guard box.width >= Int(minElement.rounded()),
                  box.height >= Int((minElement * minHeightRatio).rounded()),
                  box.height <= maxHeight,
                  box.width >= box.height,
                  !isBox(box, ink: candidate.mask, width: w),
                  looksLikeWords(box, ink: candidate.mask, width: w, gap: gapPx)
            else { continue }
            let rect = CGRect(x: box.x0, y: box.y0,
                              width: box.width, height: box.height)
            if accepted.contains(where: { $0.intersects(rect) }) { continue }
            accepted.append(rect)
            if accepted.count == limit { break }
        }

        return Sweep(runs: readingOrder(accepted), ink: mask)
    }

    /// The runs sorted the way an eye reads them: banded by row, then left to
    /// right. The band is the median run height, so two labels whose tops
    /// differ by a pixel stay on one row while a heading above them does not
    /// join it.
    public static func readingOrder(_ runs: [CGRect]) -> [CGRect] {
        guard runs.count > 1 else { return runs }
        let heights = runs.map(\.height).sorted()
        let band = max(1, heights[heights.count / 2])
        return runs.sorted { a, b in
            let rowA = Int((a.midY / band).rounded(.down))
            let rowB = Int((b.midY / band).rounded(.down))
            if rowA != rowB { return rowA < rowB }
            if a.minX != b.minX { return a.minX < b.minX }
            return a.minY < b.minY
        }
    }

    // MARK: - The local background

    /// A box mean of `samples` over a `2·radius+1` window, separably: a sliding
    /// sum along each row, then a sliding sum of column totals down the rows.
    ///
    /// Both passes walk memory forwards, so a 12 megapixel picture costs two
    /// linear reads rather than the cache-thrashing column walk a literal
    /// two-dimensional window would.
    static func boxMean(_ samples: [UInt8], width w: Int, height h: Int,
                        radius: Int) -> [UInt8] {
        guard w > 0, h > 0, samples.count == w * h else { return [] }
        let r = max(0, radius)
        var rows = [UInt8](repeating: 0, count: w * h)
        samples.withUnsafeBufferPointer { source in
            rows.withUnsafeMutableBufferPointer { out in
                for y in 0..<h {
                    let base = y * w
                    var sum: Int32 = 0
                    for x in 0...min(r, w - 1) { sum += Int32(source[base + x]) }
                    for x in 0..<w {
                        let left = x - r, right = x + r
                        if x > 0 {
                            if right <= w - 1 { sum += Int32(source[base + right]) }
                            if left >= 1 { sum -= Int32(source[base + left - 1]) }
                        }
                        let count = Int32(min(right, w - 1) - max(left, 0) + 1)
                        out[base + x] = UInt8(truncatingIfNeeded: (sum + count / 2) / count)
                    }
                }
            }
        }
        var out = [UInt8](repeating: 0, count: w * h)
        var columns = [Int32](repeating: 0, count: w)
        rows.withUnsafeBufferPointer { source in
            columns.withUnsafeMutableBufferPointer { totals in
                out.withUnsafeMutableBufferPointer { result in
                    for y in 0...min(r, h - 1) {
                        let base = y * w
                        for x in 0..<w { totals[x] += Int32(source[base + x]) }
                    }
                    for y in 0..<h {
                        let top = y - r, bottom = y + r
                        if y > 0 {
                            if bottom <= h - 1 {
                                let base = bottom * w
                                for x in 0..<w { totals[x] += Int32(source[base + x]) }
                            }
                            if top >= 1 {
                                let base = (top - 1) * w
                                for x in 0..<w { totals[x] -= Int32(source[base + x]) }
                            }
                        }
                        let count = Int32(min(bottom, h - 1) - max(top, 0) + 1)
                        let base = y * w
                        for x in 0..<w {
                            result[base + x] = UInt8(truncatingIfNeeded: (totals[x] + count / 2) / count)
                        }
                    }
                }
            }
        }
        return out
    }

    // MARK: - Rows into segments

    /// One row's worth of ink, already merged across word spaces.
    struct Segment {
        var y: Int
        var x0: Int
        var x1: Int
    }

    /// Every row's segments, flattened, with each row's slice of the array.
    /// A segment whose ink is one unbroken stretch across `ruleFraction` of
    /// itself is a rule and never appears.
    static func segments(in ink: [UInt8], width w: Int, height h: Int,
                         gap: Int) -> ([Segment], [Range<Int>]) {
        var segments: [Segment] = []
        var ranges: [Range<Int>] = []
        segments.reserveCapacity(h)
        ranges.reserveCapacity(h)
        ink.withUnsafeBufferPointer { mask in
            for y in 0..<h {
                let start = segments.count
                let base = y * w
                var x = 0
                // The segment being built, and the longest unbroken ink run in
                // it, which is what says whether it is a rule.
                var open: (x0: Int, x1: Int, longest: Int)?
                while x < w {
                    guard mask[base + x] == 1 else { x += 1; continue }
                    let runStart = x
                    while x < w, mask[base + x] == 1 { x += 1 }
                    let runEnd = x - 1
                    let length = runEnd - runStart + 1
                    if var current = open, runStart - current.x1 - 1 < gap {
                        current.x1 = runEnd
                        current.longest = max(current.longest, length)
                        open = current
                    } else {
                        if let current = open { append(current, y: y, to: &segments, gap: gap) }
                        open = (runStart, runEnd, length)
                    }
                }
                if let current = open { append(current, y: y, to: &segments, gap: gap) }
                ranges.append(start..<segments.count)
            }
        }
        return (segments, ranges)
    }

    private static func append(_ current: (x0: Int, x1: Int, longest: Int), y: Int,
                               to segments: inout [Segment], gap: Int) {
        let width = current.x1 - current.x0 + 1
        // A long unbroken stretch is a rule, not a row of letters. Short
        // segments are exempt: a lower-case "l" is unbroken and is not a rule.
        if width >= 2 * gap, Double(current.longest) >= ruleFraction * Double(width) { return }
        segments.append(Segment(y: y, x0: current.x0, x1: current.x1))
    }

    // MARK: - Segments into runs

    struct Box {
        var x0: Int
        var y0: Int
        var x1: Int
        var y1: Int
        var width: Int { x1 - x0 + 1 }
        var height: Int { y1 - y0 + 1 }
    }

    /// Segments in rows within `verticalGap` of each other that overlap
    /// horizontally are one run. Union-find over the flattened segments.
    static func components(of segments: [Segment], rowRanges: [Range<Int>],
                           height h: Int, verticalGap: Int) -> [Box] {
        guard !segments.isEmpty else { return [] }
        var parent = Array(segments.indices)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root { root = parent[root] }
            var walk = i
            while parent[walk] != walk {
                let next = parent[walk]
                parent[walk] = root
                walk = next
            }
            return root
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[rb] = ra }
        }
        // An accent can float a clean row or two above its letter, so the
        // lookback is the clean stretch plus the row that ends it.
        let lookback = verticalGap + 1
        for y in 0..<h {
            for i in rowRanges[y] {
                let s = segments[i]
                for back in 1...lookback where y - back >= 0 {
                    for j in rowRanges[y - back] {
                        let t = segments[j]
                        if s.x0 <= t.x1, t.x0 <= s.x1 { union(i, j) }
                    }
                }
            }
        }
        var boxes: [Int: Box] = [:]
        for (i, s) in segments.enumerated() {
            let root = find(i)
            if var box = boxes[root] {
                box.x0 = min(box.x0, s.x0)
                box.x1 = max(box.x1, s.x1)
                box.y0 = min(box.y0, s.y)
                box.y1 = max(box.y1, s.y)
                boxes[root] = box
            } else {
                boxes[root] = Box(x0: s.x0, y0: s.y, x1: s.x1, y1: s.y)
            }
        }
        return Array(boxes.values)
    }

    // MARK: - Is it a box rather than a line of text?

    /// How much of a component's own outline has to be ink before it is a BOX
    /// — a button, a switch, a card — rather than a line of text.
    ///
    /// This is the one question that separates the two, and it separates them
    /// cleanly: a box's ink runs all the way round it, while a line of text
    /// touches its own outline only where one stem reaches the left edge and
    /// another the right. On the capture this was tuned against, a switch reads
    /// 0.77 and a filled button 0.90, while every row label reads under 0.15.
    ///
    /// It matters twice over. It keeps a switch from arriving in the layers
    /// list called "Text 3", and it lets the LABEL INSIDE a button come out:
    /// the button's own outline is a bigger component that would otherwise be
    /// taken first and swallow the words it contains. Boxes themselves are a
    /// later slice (`docs/design/separate-into-layers.md`); this slice only has
    /// to stop mistaking one for a sentence.
    public static let maxPerimeterInk = 0.5

    static func isBox(_ box: Box, ink: [UInt8], width w: Int) -> Bool {
        var inked = 0
        ink.withUnsafeBufferPointer { mask in
            for x in box.x0...box.x1 {
                if mask[box.y0 * w + x] == 1 { inked += 1 }
                if mask[box.y1 * w + x] == 1 { inked += 1 }
            }
            // The corners are already counted by the rows above, so the sides
            // stop short of them.
            guard box.height > 2 else { return }
            for y in (box.y0 + 1)...(box.y1 - 1) {
                if mask[y * w + box.x0] == 1 { inked += 1 }
                if mask[y * w + box.x1] == 1 { inked += 1 }
            }
        }
        let perimeter = 2 * box.width + 2 * max(0, box.height - 2)
        guard perimeter > 0 else { return false }
        return Double(inked) / Double(perimeter) >= maxPerimeterInk
    }

    // MARK: - Does it look like words?

    /// Daylight between at least two letters, ink covering no more than
    /// `maxCoverage` of the box, and no row running unbroken across it — the
    /// same three questions `TextLineBounds` asks of the line under a pointer.
    static func looksLikeWords(_ box: Box, ink: [UInt8], width w: Int, gap: Int) -> Bool {
        var inked = 0
        var daylight = false
        ink.withUnsafeBufferPointer { mask in
            for x in box.x0...box.x1 {
                var column = 0
                for y in box.y0...box.y1 where mask[y * w + x] == 1 { column += 1 }
                if column == 0 { daylight = true }
                inked += column
            }
        }
        guard daylight else { return false }
        guard Double(inked) <= maxCoverage * Double(box.width * box.height) else { return false }
        var isRule = false
        ink.withUnsafeBufferPointer { mask in
            for y in box.y0...box.y1 {
                var run = 0, longest = 0
                for x in box.x0...box.x1 {
                    if mask[y * w + x] == 1 {
                        run += 1
                        if run > longest { longest = run }
                    } else {
                        run = 0
                    }
                }
                if box.width >= 2 * gap, Double(longest) >= ruleFraction * Double(box.width) {
                    isRule = true
                    break
                }
            }
        }
        return !isRule
    }
}
