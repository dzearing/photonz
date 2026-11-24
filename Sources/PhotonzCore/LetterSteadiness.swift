import Foundation

/// Whether words moving on screen move as one solid piece
/// (`text-that-zooms-or-scales-in-a-video-moves-as-on`).
///
/// Each mark of ink in a picture of the words (a letter, the dot of an i) is
/// found, and its centre followed from picture to picture. What is measured is
/// how far a mark slips against the others, once the whole's own growing and
/// travelling are taken out, and whether the whole ever steps backwards.
public struct LetterSteadiness: Equatable, Sendable {

    /// One mark's centre of ink, in pixels, y down, and how much ink it is.
    public struct Mark: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var ink: Double
        public init(x: Double, y: Double, ink: Double) {
            self.x = x
            self.y = y
            self.ink = ink
        }
    }

    /// The marks in a picture's ink (one value a pixel, nought for none),
    /// left to right. Specks of less than `least` full pixels are nothing.
    public static func marks(in ink: [UInt8], width: Int, height: Int, least: Double = 4) -> [Mark] {
        guard width > 0, height > 0, ink.count >= width * height else { return [] }
        var seen = [Bool](repeating: false, count: width * height)
        var out: [Mark] = []
        var stack: [Int] = []
        for start in 0..<(width * height) where ink[start] > 0 && !seen[start] {
            seen[start] = true
            stack.append(start)
            var total = 0.0, sumX = 0.0, sumY = 0.0
            while let at = stack.popLast() {
                let x = at % width, y = at / width
                let value = Double(ink[at])
                total += value
                sumX += value * (Double(x) + 0.5)
                sumY += value * (Double(y) + 0.5)
                for ny in max(0, y - 1)...min(height - 1, y + 1) {
                    for nx in max(0, x - 1)...min(width - 1, x + 1) {
                        let next = ny * width + nx
                        if !seen[next], ink[next] > 0 {
                            seen[next] = true
                            stack.append(next)
                        }
                    }
                }
            }
            if total >= least * 255 { out.append(Mark(x: sumX / total, y: sumY / total, ink: total / 255)) }
        }
        return out.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
    }

    /// The furthest any mark slips against the whole, in pixels.
    public var slip: Double
    /// The whole's size in each picture, against the last one's.
    public var sizes: [Double]
    /// Pictures whose marks could not be told apart.
    public var unread: Int

    /// Whether the whole only ever grew, or only ever shrank, give or take
    /// what reading it can tell.
    public func sizesKeepGoing(within slack: Double = 0.0002) -> Bool {
        let steps = zip(sizes, sizes.dropFirst()).map { $1 - $0 }
        return steps.allSatisfy { $0 >= -slack } || steps.allSatisfy { $0 <= slack }
    }

    /// Reads the marks of the same words in picture after picture.
    public init(_ pictures: [[Mark]]) {
        slip = 0
        sizes = []
        unread = 0
        guard let last = pictures.last, last.count > 1 else {
            unread = pictures.count
            return
        }
        let n = Double(last.count)
        let mx = last.map(\.x).reduce(0, +) / n, my = last.map(\.y).reduce(0, +) / n
        let spread = last.map { ($0.x - mx) * ($0.x - mx) + ($0.y - my) * ($0.y - my) }.reduce(0, +)
        guard spread > 0 else {
            unread = pictures.count
            return
        }
        var left: [[Double]] = []
        for marks in pictures {
            guard marks.count == last.count else {
                unread += 1
                continue
            }
            let cx = marks.map(\.x).reduce(0, +) / n, cy = marks.map(\.y).reduce(0, +) / n
            // The same mark in both, whatever order they were found in: the
            // dot of an i sits straight over its stem, and which of the two is
            // the further left is a matter of a hundredth of a pixel.
            let reach = marks.map { ($0.x - cx) * ($0.x - cx) + ($0.y - cy) * ($0.y - cy) }.reduce(0, +)
            let about = (reach / spread).squareRoot()
            var free = marks
            let marks = last.map { was -> Mark in
                let x = cx + (was.x - mx) * about, y = cy + (was.y - my) * about
                func far(_ mark: Mark) -> Double { (mark.x - x) * (mark.x - x) + (mark.y - y) * (mark.y - y) }
                let nearest = free.indices.min { far(free[$0]) < far(free[$1]) } ?? 0
                return free.remove(at: nearest)
            }
            var along = 0.0
            for (was, now) in zip(last, marks) { along += (was.x - mx) * (now.x - cx) + (was.y - my) * (now.y - cy) }
            let size = along / spread
            var off: [Double] = []
            for (was, now) in zip(last, marks) {
                off.append(now.x - cx - size * (was.x - mx))
                off.append(now.y - cy - size * (was.y - my))
            }
            sizes.append(size)
            left.append(off)
        }
        guard left.count > 2 else { return }
        // What is left of a mark, against the size it was at: a straight line
        // is the same shape seen at other sizes, anything else is slipping.
        for mark in left[0].indices {
            slip = max(slip, Self.offLine(left.map { $0[mark] }, against: sizes))
        }
    }

    /// The furthest `track` goes from the straight line that best fits it
    /// against `at`.
    public static func offLine(_ track: [Double], against at: [Double]) -> Double {
        guard !track.isEmpty, track.count == at.count else { return 0 }
        let n = Double(track.count)
        let ma = at.reduce(0, +) / n, mt = track.reduce(0, +) / n
        var top = 0.0, bottom = 0.0
        for (a, t) in zip(at, track) {
            top += (a - ma) * (t - mt)
            bottom += (a - ma) * (a - ma)
        }
        let slope = bottom > 0 ? top / bottom : 0
        return zip(at, track).map { abs($1 - (mt + slope * ($0 - ma))) }.max() ?? 0
    }
}

/// `expectWordsSteady`: what a walk asks of words that grow or travel.
public struct PlaytestWordsSteady: Equatable, Sendable {
    public var name: String
    /// The stretch watched, in seconds of the document.
    public var fromSeconds: Double
    public var toSeconds: Double
    /// The furthest a letter may slip, in pixels of the export.
    public var within: Double
    public init(name: String, fromSeconds: Double, toSeconds: Double, within: Double) {
        self.name = name
        self.fromSeconds = fromSeconds
        self.toSeconds = toSeconds
        self.within = within
    }
}
