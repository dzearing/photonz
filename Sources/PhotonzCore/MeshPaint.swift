import CoreGraphics
import Foundation

// A mesh paint: a few soft colour points that drift (task
// `title-backgrounds-move-gradients-grain-and-the-r`,
// `docs/design/video-titles-polish.md`, "Backgrounds").
//
// The default product video backdrop is two or three colours blended softly
// into each other and moving slowly, about one gentle sweep a clip. Each stop
// of the paint is one colour point; the points sit round the middle of the box,
// turned by the paint's angle, and each travels its own slow loop, so the blend
// shifts without anything ever reading as a moving object.
//
// Worked out here, in plain numbers, so the renderer, the panel's swatch and a
// test all read the same picture. The renderer samples it on a small grid and
// lets Core Image enlarge it: a blend this soft has nothing in it a small grid
// misses.

/// One colour point of a mesh, where it is at one moment.
public struct MeshPoint: Hashable, Sendable {
    /// In the box's own unit space: 0,0 its top-left corner, 1,1 its bottom-right.
    public var center: CGPoint
    public var color: RGBA
}

extension Paint {

    /// How long one loop of the drift takes at full drift (100%).
    public static let loopMSAtFullDrift = 8000

    /// The most colour points a mesh blends: a mesh of four is already busy.
    public static let meshPointLimit = 4

    /// How long one loop of a drifting mesh takes, or nil for a paint that
    /// does not drift.
    public var driftLoopMS: Int? {
        guard kind == .mesh, drift > 0 else { return nil }
        return Int((Double(Paint.loopMSAtFullDrift) * 100 / drift).rounded())
    }

    /// Whether this paint looks different from one moment to the next.
    public var moves: Bool { isGradient && driftLoopMS != nil }

    /// The colour points `ms` into the drift. A paint that does not drift
    /// holds them where they start.
    public func meshPoints(atMS ms: Int) -> [MeshPoint] {
        let ramp = orderedStops.prefix(Paint.meshPointLimit).compactMap { stop -> RGBA? in
            RGBA(hex: stop.hex)
        }
        guard !ramp.isEmpty else { return [] }
        let loop = driftLoopMS.map { Double(ms) / Double($0) } ?? 0
        let turn = 2 * Double.pi
        let start = angle * .pi / 180
        return ramp.enumerated().map { index, color in
            let share = Double(index) / Double(ramp.count)
            let around = start + turn * share
            // Spread round the middle, so every corner is near some colour.
            let anchor = CGPoint(x: 0.5 + 0.3 * sin(around), y: 0.5 - 0.3 * cos(around))
            // Each point's own slow figure, whole numbers of times round per
            // loop so the loop closes exactly, out of step with its
            // neighbours so they never move as one block.
            let phase = turn * share + 0.7 * Double(index)
            let wide = index.isMultiple(of: 2)
            let dx = 0.16 * sin(turn * loop * (wide ? 1 : 2) + phase)
            let dy = 0.12 * sin(turn * loop * (wide ? 2 : 1) + phase * 1.7)
            return MeshPoint(center: CGPoint(x: anchor.x + dx, y: anchor.y + dy), color: color)
        }
    }

    /// How far each point's colour reaches, in widths of the box's short side.
    public static let meshReach: Double = 0.42

    /// The colour at `unit` (the box's own unit space) of a box `size`, `ms`
    /// into the drift: every point's colour, weighted by a soft fall-off from
    /// where it is. Distances are measured square, so a wide box is not a
    /// stretched blend. Nil for a paint with no points.
    public func meshColor(at unit: CGPoint, in size: CGSize, atMS ms: Int) -> RGBA? {
        Paint.meshColor(at: unit, in: size, points: meshPoints(atMS: ms))
    }

    /// The same, for points already worked out: what the renderer calls once
    /// per sample of a frame.
    public static func meshColor(at unit: CGPoint, in size: CGSize, points: [MeshPoint]) -> RGBA? {
        guard !points.isEmpty else { return nil }
        let short = max(min(size.width, size.height), 1)
        let sx = Double(size.width / short), sy = Double(size.height / short)
        let spread = 2 * meshReach * meshReach
        var squared: [Double] = []
        squared.reserveCapacity(points.count)
        for point in points {
            let dx = (Double(unit.x) - Double(point.center.x)) * sx
            let dy = (Double(unit.y) - Double(point.center.y)) * sy
            squared.append(dx * dx + dy * dy)
        }
        // Measured from the nearest, so a corner far from every point still
        // has weights to divide by.
        let nearest = squared.min() ?? 0
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0, total = 0.0
        for (point, d2) in zip(points, squared) {
            let weight = exp(-(d2 - nearest) / spread)
            r += point.color.r * weight
            g += point.color.g * weight
            b += point.color.b * weight
            a += point.color.a * weight
            total += weight
        }
        guard total > 0 else { return points.first?.color }
        return RGBA(r: r / total, g: g / total, b: b / total, a: a / total)
    }
}

// MARK: - The clock a moving look runs on

extension Layer {

    /// Whether how this layer looks changes by itself from one moment to the
    /// next, with no key asking it to: a drifting mesh, or grain.
    public var looksRunOnAClock: Bool {
        if style.grain != nil { return true }
        switch content {
        case .annotation(let annotation): return annotation.fill?.moves == true
        case .path(let path): return path.fill?.moves == true
        case .group(let group): return group.background?.moves == true
        default: return false
        }
    }

    /// This layer told the moment it is drawn at, where it has a look that
    /// needs one (`drawnAtMS`). Anything else comes back exactly as it was.
    func withClockShown(atMotionMS ms: Int) -> Layer {
        guard looksRunOnAClock else { return self }
        var shown = self
        shown.drawnAtMS = ms
        return shown
    }
}
