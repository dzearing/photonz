import CoreGraphics
import Foundation

extension AskMotion {

    // MARK: A long rest shows the icon whole

    /// The longest a still stretch of the lap may last while a part that is
    /// seen elsewhere in it is gone (faded, shrunk to nothing, undrawn or
    /// outside the frame). Long enough to read as a pause before it starts
    /// over; anything longer is an icon shown broken.
    static let goneRest = 0.3
    /// A still stretch with a part gone is left alone up to this long.
    static let goneRestAllowed = 0.45
    /// A lap that loses its gone rest and has no whole one to give it to
    /// shrinks, never below this.
    static let shortestRestedLap = 1.0
    /// No stretch between two keys is cut shorter than this.
    private static let shortestBetweenKeys = 0.05

    /// `steps` with every long still stretch in which a part is gone cut down
    /// to `goneRest`, and the time it lost given to the longest still stretch
    /// where every part is seen, or, with none, taken off the lap. On the climb
    /// set of 2026-11-15 four plans of twelve rested a third to half of their
    /// lap with a part gone after its beat (dropped and faded, undrawn, burst),
    /// so most of the frames a person or the judge sees showed the icon
    /// incomplete or empty. Only time between keys where nothing moves
    /// changes: every motion plays at the speed it was planned, and every
    /// value still ends the lap where it began. Boxes, keys and time; no part
    /// is read for what it is.
    public static func restsWhole(_ steps: [AskStep]) -> [AskStep] {
        guard let lapStep = steps.lastIndex(where: { $0.tool == "set_timing" }),
              let lapSeconds = steps[lapStep].arguments["seconds"]?.doubleValue, lapSeconds > 0,
              let lap = Lap(steps), !lap.movers.isEmpty else { return steps }
        let view = lap.art.viewBox
        let keyed = lap.keyed
        // Every moment a key falls on, the lap's ends included.
        var moments = [0.0, lapSeconds]
        for step in keyed { moments += AskMotionCheck.timed(step).map(\.seconds).filter { $0 > 0 && $0 < lapSeconds } }
        moments.sort()
        var times: [Double] = []
        for moment in moments where times.last.map({ moment - $0 > 0.0005 }) ?? true { times.append(moment) }
        guard times.count >= 2 else { return steps }

        func same(_ a: AgentJSON?, _ b: AgentJSON?) -> Bool {
            if let x = a?.doubleValue, let y = b?.doubleValue { return abs(x - y) < 0.01 }
            if let ax = a?["x"]?.doubleValue, let ay = a?["y"]?.doubleValue,
               let bx = b?["x"]?.doubleValue, let by = b?["y"]?.doubleValue {
                return abs(ax - bx) < 0.001 && abs(ay - by) < 0.001
            }
            return a == b
        }
        // Still between two moments: every value the same at its start, its
        // middle and just before its end (a Hold that jumps at the end is still).
        func still(_ from: Double, _ to: Double) -> Bool {
            let end = max(from, to - 0.0005)
            return keyed.allSatisfy { step in
                let start = AskMotionCheck.played(of: step, at: from)
                return same(start, AskMotionCheck.played(of: step, at: (from + to) / 2))
                    && same(start, AskMotionCheck.played(of: step, at: end))
            }
        }
        func seen(_ name: String, at seconds: Double) -> Bool {
            guard let placed = lap.placed(name, at: seconds), placed.seen else { return false }
            if let scale = lap.value(name, .scale, at: seconds)?.doubleValue, scale < 10 { return false }
            if let drawn = lap.value(name, .trimEnd, at: seconds)?.doubleValue, drawn < 5 { return false }
            if let view {
                let xs = placed.quad.map(\.x), ys = placed.quad.map(\.y)
                if let left = xs.min(), let right = xs.max(), let top = ys.min(), let bottom = ys.max(),
                   !CGRect(x: left, y: top, width: right - left, height: bottom - top).intersects(view) { return false }
            }
            return true
        }
        // The parts seen at some moment of the lap: only they can be missed.
        var everSeen: [String] = []
        for name in lap.movers {
            var seconds = 0.0
            while seconds < lapSeconds {
                if seen(name, at: seconds) { everSeen.append(name); break }
                seconds += 0.05
            }
        }
        guard !everSeen.isEmpty else { return steps }

        // The still stretches, as runs of the gaps between moments, the one
        // at the lap's end joined to the one at its start.
        let gaps = Array(zip(times, times.dropFirst()))
        let stillGaps = gaps.map { still($0.0, $0.1) }
        var runs: [[Int]] = []
        var current: [Int] = []
        for (at, isStill) in stillGaps.enumerated() {
            if isStill { current.append(at) } else if !current.isEmpty { runs.append(current); current = [] }
        }
        if !current.isEmpty { runs.append(current) }
        if runs.count >= 2, let first = runs.first, first.first == 0, let last = runs.last, last.last == gaps.count - 1 {
            runs[0] = last + first
            runs.removeLast()
        }
        func length(_ run: [Int]) -> Double { run.reduce(0) { $0 + gaps[$1].1 - gaps[$1].0 } }
        func whole(_ run: [Int]) -> Bool {
            guard let at = run.max(by: { gaps[$0].1 - gaps[$0].0 < gaps[$1].1 - gaps[$1].0 }) else { return false }
            let middle = (gaps[at].0 + gaps[at].1) / 2
            return everSeen.allSatisfy { seen($0, at: middle) }
        }

        // How long each gap becomes.
        var lengths = gaps.map { $0.1 - $0.0 }
        var freed = 0.0
        for run in runs where !whole(run) && length(run) > goneRestAllowed + 0.0005 {
            let cut = length(run) - goneRest
            let room = run.map { max(0, lengths[$0] - shortestBetweenKeys) }
            let roomAll = room.reduce(0, +)
            guard roomAll > 0.0005 else { continue }
            let share = min(1, cut / roomAll)
            for (gap, spare) in zip(run, room) { lengths[gap] -= spare * share }
            freed += roomAll * share
        }
        guard freed > 0.0005 else { return steps }
        if let rest = runs.filter(whole).max(by: { length($0) < length($1) }),
           let gap = rest.max(by: { lengths[$0] < lengths[$1] }) {
            lengths[gap] += freed
        } else {
            // Nowhere whole to rest: the lap is shorter, but never too short.
            let total = lengths.reduce(0, +)
            if total < shortestRestedLap, let gap = lengths.indices.max(by: { lengths[$0] < lengths[$1] }) {
                lengths[gap] += shortestRestedLap - total
            }
        }
        var moved = [0.0]
        for one in lengths { moved.append(moved[moved.count - 1] + one) }
        func warp(_ seconds: Double) -> Double {
            if seconds <= 0 { return seconds }
            for (at, gap) in gaps.enumerated() where seconds <= gap.1 + 0.0005 {
                let span = gap.1 - gap.0
                let share = span > 0 ? min(1, max(0, (seconds - gap.0) / span)) : 1
                return rounded(CGFloat(moved[at] + share * lengths[at]))
            }
            return rounded(CGFloat(seconds - lapSeconds + moved[moved.count - 1]))
        }
        var out = steps
        for (at, step) in steps.enumerated() where step.tool == "set_keys" {
            guard var object = step.arguments.objectValue, let keys = step.arguments["keys"]?.arrayValue else { continue }
            object["keys"] = .array(keys.map { key in
                guard var one = key.objectValue, let seconds = key["seconds"]?.doubleValue else { return key }
                one["seconds"] = .number(warp(seconds))
                return .object(one)
            })
            out[at] = AskStep(tool: step.tool, arguments: .object(object))
        }
        if var timing = steps[lapStep].arguments.objectValue {
            timing["seconds"] = .number(warp(lapSeconds))
            out[lapStep] = AskStep(tool: "set_timing", arguments: .object(timing))
        }
        return out
    }
}

extension AskMotion {

    // MARK: A fading mark stays inside the frame

    /// `steps` with every mark that travels as it fades kept inside the
    /// frame while it can be seen: its moves scaled down, all by one factor,
    /// until no moment it is seen fading out (opacity 10 or more and going
    /// down) has its box past the frame. A mark is a part with position and opacity keys that is gone
    /// (opacity 5 or less) at some moment of the lap; a part that never fades
    /// is left to the rules for leaving (`leaving`, `edgeHides`). On the climb
    /// set of 2026-11-15 (run 20261115-005857-ask) two small marks beside a
    /// swinging part slid six units sideways while fading, through the frame's
    /// edge: "cut off by the right edge" in the judge's notes. Keys keep their
    /// times; boxes, keys and time only.
    public static func marksStayIn(_ steps: [AskStep]) -> [AskStep] {
        guard let svg = steps.first(where: { $0.tool == "add_drawing" })?.arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true), let view = art.viewBox,
              let lapSeconds = steps.last(where: { $0.tool == "set_timing" })?.arguments["seconds"]?.doubleValue,
              lapSeconds > 0 else { return steps }
        func part(_ step: AskStep) -> String? { (step.arguments["layer"]?.stringValue).flatMap(partReference)?.part }
        func property(_ step: AskStep) -> String? { step.arguments["property"]?.stringValue }
        let folded = AskMotion.folded(steps)
        var out = steps
        for (at, step) in steps.enumerated() where step.tool == "set_keys" && property(step) == MotionProperty.position.rawValue {
            guard let name = part(step), let own = AskMotionCheck.box(of: name, in: art),
                  let fade = folded.last(where: { $0.tool == "set_keys" && property($0) == MotionProperty.opacity.rawValue
                      && part($0).map { plain($0) == plain(name) } ?? false }),
                  folded.contains(where: { $0.arguments == step.arguments }) else { continue }
            let moments = stride(from: 0.0, through: lapSeconds, by: 0.02).map { $0 }
            // Seen and fading out: a part fading in as it comes in from
            // outside the frame is thrown in on purpose (the story rules).
            let seen = moments.filter { moment in
                let now = AskMotionCheck.played(of: fade, at: moment)?.doubleValue ?? 100
                let next = AskMotionCheck.played(of: fade, at: moment + 0.01)?.doubleValue ?? 100
                return now >= 10 && next < now - 0.01
            }
            let gone = moments.contains { (AskMotionCheck.played(of: fade, at: $0)?.doubleValue ?? 100) <= unseen }
            guard gone, !seen.isEmpty else { continue }
            let room = view.insetBy(dx: -0.01, dy: -0.01)
            func inside(_ factor: Double) -> Bool {
                seen.allSatisfy { moment in
                    let shift = AskMotionCheck.played(of: step, at: moment)
                    let dx = (shift?["x"]?.doubleValue ?? 0) * factor, dy = (shift?["y"]?.doubleValue ?? 0) * factor
                    return room.contains(own.offsetBy(dx: dx, dy: dy))
                }
            }
            // Drawn inside the frame, or nothing to pull it in towards.
            guard room.contains(own), !inside(1) else { continue }
            var low = 0.0, high = 1.0
            for _ in 0..<24 {
                let middle = (low + high) / 2
                if inside(middle) { low = middle } else { high = middle }
            }
            guard var object = step.arguments.objectValue, let keys = step.arguments["keys"]?.arrayValue else { continue }
            object["keys"] = .array(keys.map { key in
                guard var one = key.objectValue, let x = key["value"]?["x"]?.doubleValue, let y = key["value"]?["y"]?.doubleValue else { return key }
                one["value"] = ["x": .number(rounded(CGFloat(x * low))), "y": .number(rounded(CGFloat(y * low)))]
                return .object(one)
            })
            out[at] = AskStep(tool: step.tool, arguments: .object(object))
        }
        return out
    }
}
