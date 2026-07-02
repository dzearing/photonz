import CoreGraphics
import Foundation

/// One detected edge candidate along an axis: a pixel `position` (an x column for
/// a vertical boundary, a y row for a horizontal one) and a `strength` in 0...1
/// relative to the strongest peak in the queried window.
///
/// `position` is the GRADIENT PEAK — the middle of the transition ramp. What a
/// redliner wants to snap to is the first visually-clean background row hugging
/// the element (outside its antialiasing glow), and that differs by approach
/// side: `edgeBefore` is that landing on the lower-coordinate side (above /
/// left), `edgeAfter` on the higher side (below / right). Hard 1px edges land on
/// the peak itself; soft antialiased text edges land 1–2px past the glow.
public struct EdgeCandidate: Equatable, Sendable, Codable {
    public var position: Double
    public var strength: Double
    public var edgeBefore: Double
    public var edgeAfter: Double

    public init(position: Double, strength: Double,
                edgeBefore: Double? = nil, edgeAfter: Double? = nil) {
        self.position = position
        self.strength = strength
        self.edgeBefore = edgeBefore ?? position
        self.edgeAfter = edgeAfter ?? position
    }
}

/// The UI boundaries detectable in a screenshot bitmap, queryable LOCALLY.
///
/// A screenshot has no semantic UI tree — "the edge of a UI element" is
/// approximated from image gradients. Crucially, the edges a redliner wants
/// (text tops/baselines/bottoms, container borders) are LOCAL structures: a
/// baseline only spans its own text run. Global full-image projections dilute
/// them into nothing, so this map stores the directional gradient fields
/// (|Gy| for horizontal boundaries, |Gx| for vertical) pre-summed into small
/// column/row blocks, and answers windowed queries: "horizontal edges under
/// THIS x-span", "vertical edges within THIS y-span". The window is the span of
/// the ruler line being dragged, so the line snaps to edges it actually crosses.
///
/// Acceptance inside a window is driven purely by an ABSOLUTE floor on the mean
/// per-pixel gradient — deliberately NOT window-relative: a faint hairline
/// border must stay snappable even when a maximally-strong edge (dark panel →
/// white panel) shares the window with it.
///
/// Positions are in top-left image space. Built once per image (see
/// `EdgeMapAnalyzer`/`EdgeMapCache` in PhotonzRender) and consumed by
/// `EdgeSnapping`.
public struct EdgeMap: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// Column/row block granularity of the stored sums. Windows round outward to
    /// block boundaries — a few pixels of slack, irrelevant at snap scale.
    public let blockSize: Int

    /// `hSums[colBlock * height + row]` = Σ|Gy| over that block's columns at `row`.
    private let hSums: [Double]
    /// `vSums[rowBlock * width + col]` = Σ|Gx| over that block's rows at `col`.
    private let vSums: [Double]
    /// Σ luma, same layouts as `hSums`/`vSums`. Empty when no luma was provided;
    /// then landings degrade to the gradient peak positions.
    private let hLuma: [Double]
    private let vLuma: [Double]
    private let colBlocks: Int
    private let rowBlocks: Int

    /// Builds the map from directional gradient magnitude fields in top-left row
    /// order (`buffer[row * width + col]`), plus an optional PERCEPTUAL luma
    /// field (≈ sqrt of linear luminance) used to refine each candidate to the
    /// visually-clean background row on either side. Counts must be
    /// `width * height`; anything else yields an empty map rather than trapping.
    public init(width: Int, height: Int,
                gxMagnitude: [Double], gyMagnitude: [Double],
                luma: [Double]? = nil,
                blockSize: Int = 16) {
        let valid = width > 0 && height > 0 && blockSize > 0
            && gxMagnitude.count == width * height
            && gyMagnitude.count == width * height
            && (luma == nil || luma!.count == width * height)
        guard valid else {
            self.width = 0; self.height = 0; self.blockSize = max(blockSize, 1)
            hSums = []; vSums = []; hLuma = []; vLuma = []
            colBlocks = 0; rowBlocks = 0
            return
        }
        self.width = width
        self.height = height
        self.blockSize = blockSize
        let cb = (width + blockSize - 1) / blockSize
        let rb = (height + blockSize - 1) / blockSize
        colBlocks = cb
        rowBlocks = rb

        func blockRows(_ field: [Double]) -> [Double] {
            var out = [Double](repeating: 0, count: cb * height)
            field.withUnsafeBufferPointer { src in
                out.withUnsafeMutableBufferPointer { dst in
                    for row in 0..<height {
                        let rowBase = row * width
                        for col in 0..<width {
                            dst[(col / blockSize) * height + row] += src[rowBase + col]
                        }
                    }
                }
            }
            return out
        }
        func blockCols(_ field: [Double]) -> [Double] {
            var out = [Double](repeating: 0, count: rb * width)
            field.withUnsafeBufferPointer { src in
                out.withUnsafeMutableBufferPointer { dst in
                    for row in 0..<height {
                        let rowBase = row * width
                        let blockBase = (row / blockSize) * width
                        for col in 0..<width {
                            dst[blockBase + col] += src[rowBase + col]
                        }
                    }
                }
            }
            return out
        }
        hSums = blockRows(gyMagnitude)
        vSums = blockCols(gxMagnitude)
        hLuma = luma.map(blockRows) ?? []
        vLuma = luma.map(blockCols) ?? []
    }

    private init(empty: Void) {
        width = 0; height = 0; blockSize = 16
        hSums = []; vSums = []; hLuma = []; vLuma = []
        colBlocks = 0; rowBlocks = 0
    }

    public static let empty = EdgeMap(empty: ())

    public var isEmpty: Bool { width == 0 || height == 0 }

    /// Default absolute floor on the windowed mean per-pixel gradient. Sobel's
    /// response to a hard unit-contrast boundary is 4.0/px. Calibrated on real
    /// captures: dark-mode hairline card separators — exactly what a redliner
    /// measures to — come in around 0.15, while background noise and gentle
    /// gradients stay under ~0.08. The admitted weak text-antialiasing ghosts are
    /// handled by strength-weighted snapping (`EdgeSnapping`), not the floor.
    public static let defaultFloor: Double = 0.12

    /// Horizontal boundaries (text tops/baselines, borders) whose x-span overlaps
    /// `range` — candidates for snapping a horizontal ruler line moving vertically.
    public func horizontalEdges(inXRange range: ClosedRange<Double>,
                                threshold: Double = 0,
                                minSeparation: Int = 3,
                                floor: Double = EdgeMap.defaultFloor) -> [EdgeCandidate] {
        guard !isEmpty else { return [] }
        guard let blocks = blockRange(range, limit: width, blockCount: colBlocks) else { return [] }
        var profile = [Double](repeating: 0, count: height)
        var luma = hLuma.isEmpty ? [] : [Double](repeating: 0, count: height)
        var pixels = 0
        for b in blocks {
            pixels += min((b + 1) * blockSize, width) - b * blockSize
            let base = b * height
            for r in 0..<height { profile[r] += hSums[base + r] }
            if !hLuma.isEmpty {
                for r in 0..<height { luma[r] += hLuma[base + r] }
            }
        }
        return refinedPeaks(profile, luma: luma, pixels: pixels, threshold: threshold,
                            minSeparation: minSeparation, floor: floor)
    }

    /// Vertical boundaries (text-run starts, container edges) whose y-span
    /// overlaps `range` — candidates for a vertical ruler line moving horizontally.
    public func verticalEdges(inYRange range: ClosedRange<Double>,
                              threshold: Double = 0,
                              minSeparation: Int = 3,
                              floor: Double = EdgeMap.defaultFloor) -> [EdgeCandidate] {
        guard !isEmpty else { return [] }
        guard let blocks = blockRange(range, limit: height, blockCount: rowBlocks) else { return [] }
        var profile = [Double](repeating: 0, count: width)
        var luma = vLuma.isEmpty ? [] : [Double](repeating: 0, count: width)
        var pixels = 0
        for b in blocks {
            pixels += min((b + 1) * blockSize, height) - b * blockSize
            let base = b * width
            for c in 0..<width { profile[c] += vSums[base + c] }
            if !vLuma.isEmpty {
                for c in 0..<width { luma[c] += vLuma[base + c] }
            }
        }
        return refinedPeaks(profile, luma: luma, pixels: pixels, threshold: threshold,
                            minSeparation: minSeparation, floor: floor)
    }

    /// Clamps a pixel range to the image and converts to block indices.
    private func blockRange(_ range: ClosedRange<Double>, limit: Int,
                            blockCount: Int) -> ClosedRange<Int>? {
        let lo = max(0, Int(range.lowerBound.rounded(.down)))
        let hi = min(limit - 1, Int(range.upperBound.rounded(.up)))
        guard lo <= hi else { return nil }
        return (lo / blockSize)...min(hi / blockSize, blockCount - 1)
    }

    /// Peaks, then landing refinement: each candidate learns the visually-clean
    /// background position hugging the element on each side.
    private func refinedPeaks(_ sums: [Double], luma lumaSums: [Double], pixels: Int,
                              threshold: Double, minSeparation: Int,
                              floor: Double) -> [EdgeCandidate] {
        guard pixels > 0 else { return [] }
        let inv = 1 / Double(pixels)
        let profile = sums.map { $0 * inv }
        var peaks = EdgeProfile.peaks(in: profile, threshold: threshold,
                                      minSeparation: minSeparation, floor: floor)
        guard !lumaSums.isEmpty else { return peaks }
        let luma = lumaSums.map { $0 * inv }
        for i in peaks.indices {
            let p = Int(peaks[i].position)
            peaks[i].edgeBefore = Self.landing(from: p, direction: -1, luma: luma, gradient: profile)
            peaks[i].edgeAfter = Self.landing(from: p, direction: 1, luma: luma, gradient: profile)
        }
        return peaks
    }

    /// How far past a peak the landing search reaches (covers the widest
    /// antialiasing ramps seen on 2× text).
    private static let landingReach = 9

    /// Walks from a gradient peak toward `direction` and returns the first
    /// position whose luma has settled to the local background — the visually
    /// clean row/column hugging the element on that side. "Settled" is judged
    /// RELATIVE to the edge's own contrast (residual ≤ 10%), so a text line's
    /// sparse descender ink (a few percent of the baseline contrast) reads as
    /// background — the user measures from the BASELINE — while the much brighter
    /// antialiasing glow row does not. Hard edges match immediately (the peak
    /// straddles the boundary, so the peak position itself is already
    /// background). Falls back to the peak when nothing within reach settles.
    static func landing(from peak: Int, direction: Int,
                        luma: [Double], gradient: [Double]) -> Double {
        let n = luma.count
        guard n > 0 else { return Double(peak) }
        // Background reference: the calmest (lowest-gradient) sample in the band
        // beyond the ramp on this side. Using the calmest sample avoids reading
        // a neighboring element's ink as "background".
        var bg: Double?
        var calmest = Double.infinity
        for step in 4...landingReach {
            let i = peak + direction * step
            guard i >= 0, i < n else { break }
            if gradient[i] < calmest {
                calmest = gradient[i]
                bg = luma[i]
            }
        }
        guard let bg else { return Double(peak) }
        let contrast = abs(luma[min(max(peak, 0), n - 1)] - bg)
        // Peak already at background level (hard 1px boundary): stay on it.
        guard contrast > 0.02 else { return Double(peak) }
        let tolerance = 0.10 * contrast
        for step in 0...landingReach {
            let i = peak + direction * step
            guard i >= 0, i < n else { break }
            if abs(luma[i] - bg) <= tolerance { return Double(i) }
        }
        return Double(peak)
    }
}

/// Peak finding over a 1-D edge-magnitude profile.
public enum EdgeProfile {

    /// Finds the strong boundaries in `profile`.
    ///
    /// A position qualifies if it is a local maximum and clears BOTH the relative
    /// cutoff (`threshold` × the profile's max) and the absolute `floor`.
    /// Candidates closer together than `minSeparation` are deduped by
    /// non-maximum suppression, keeping the stronger. Returned sorted ascending
    /// by position with `strength` normalized to the strongest peak (1.0).
    public static func peaks(in profile: [Double],
                             threshold: Double = 0.25,
                             minSeparation: Int = 4,
                             floor: Double = 0) -> [EdgeCandidate] {
        let n = profile.count
        guard n > 0 else { return [] }

        var maxV = 0.0
        for v in profile where v > maxV { maxV = v }
        guard maxV > 0, maxV >= floor else { return [] }

        let cutoff = max(maxV * min(max(threshold, 0), 1), floor)

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
