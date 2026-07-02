import CoreGraphics
import Foundation

/// One detected edge candidate along an axis: a pixel `position` (an x column for
/// a vertical boundary, a y row for a horizontal one) and a normalized `strength`
/// in 0...1 relative to the strongest peak on that axis.
public struct EdgeCandidate: Equatable, Sendable, Codable {
    public var position: Double
    public var strength: Double

    public init(position: Double, strength: Double) {
        self.position = position
        self.strength = strength
    }
}

/// The strong vertical/horizontal boundaries found in a screenshot bitmap.
///
/// There is no semantic UI tree in a screenshot — it is just pixels. We
/// approximate "the edge of a UI element" by running an edge/gradient pass over
/// the base image (render side), projecting the magnitude onto each axis to get
/// two 1-D profiles, and finding the thresholded peaks (this file). For clean UX
/// screenshots the contrast edges ARE the element edges.
///
/// `verticalEdges` are x coordinates (columns) of strong vertical boundaries;
/// `horizontalEdges` are y coordinates (rows). Both are in top-left image space
/// and sorted ascending by position. Built once per image, cached, and consumed
/// by `EdgeSnapping` (16.5) to magnetize measure corners.
public struct EdgeMap: Equatable, Sendable, Codable {
    public var width: Int
    public var height: Int
    public var verticalEdges: [EdgeCandidate]
    public var horizontalEdges: [EdgeCandidate]

    public init(width: Int, height: Int,
                verticalEdges: [EdgeCandidate],
                horizontalEdges: [EdgeCandidate]) {
        self.width = width
        self.height = height
        self.verticalEdges = verticalEdges
        self.horizontalEdges = horizontalEdges
    }

    public static let empty = EdgeMap(width: 0, height: 0,
                                      verticalEdges: [], horizontalEdges: [])

    /// Assembles an `EdgeMap` from the per-axis projection profiles produced by
    /// the render-side edge pass. `xProfile[x]` is the summed edge magnitude in
    /// column `x` (length == `width`); `yProfile[y]` likewise for row `y`
    /// (length == `height`, top-left order).
    public static func from(xProfile: [Double], yProfile: [Double],
                            width: Int, height: Int,
                            threshold: Double = 0.25,
                            minSeparation: Int = 4) -> EdgeMap {
        EdgeMap(width: width, height: height,
                verticalEdges: EdgeProfile.peaks(in: xProfile,
                                                 threshold: threshold,
                                                 minSeparation: minSeparation),
                horizontalEdges: EdgeProfile.peaks(in: yProfile,
                                                   threshold: threshold,
                                                   minSeparation: minSeparation))
    }
}

/// Peak finding over a 1-D edge-magnitude profile.
public enum EdgeProfile {

    /// Finds the strong boundaries in `profile`.
    ///
    /// A position qualifies if its magnitude is a local maximum and clears
    /// `threshold` (a fraction of the profile's peak — so it is contrast- and
    /// exposure-independent). Candidates closer together than `minSeparation`
    /// pixels are deduped by non-maximum suppression, keeping the stronger.
    /// Returned candidates are sorted ascending by position with `strength`
    /// normalized to the strongest peak (1.0).
    public static func peaks(in profile: [Double],
                             threshold: Double = 0.25,
                             minSeparation: Int = 4) -> [EdgeCandidate] {
        let n = profile.count
        guard n > 0 else { return [] }

        var maxV = 0.0
        for v in profile where v > maxV { maxV = v }
        guard maxV > 0 else { return [] }

        let cutoff = maxV * min(max(threshold, 0), 1)

        // Local maxima above the cutoff.
        var locals: [EdgeCandidate] = []
        for i in 0..<n {
            let v = profile[i]
            if v < cutoff { continue }
            let leftOK = i == 0 || profile[i - 1] <= v
            let rightOK = i == n - 1 || profile[i + 1] <= v
            if leftOK && rightOK {
                locals.append(EdgeCandidate(position: Double(i), strength: v / maxV))
            }
        }

        // Non-maximum suppression: strongest first (ties broken by lower
        // position for determinism), reject anything within minSeparation.
        let sep = Double(max(minSeparation, 1))
        var accepted: [EdgeCandidate] = []
        let ranked = locals.sorted { a, b in
            a.strength != b.strength ? a.strength > b.strength : a.position < b.position
        }
        for cand in ranked {
            if accepted.contains(where: { abs($0.position - cand.position) < sep }) { continue }
            accepted.append(cand)
        }
        return accepted.sorted { $0.position < $1.position }
    }
}
