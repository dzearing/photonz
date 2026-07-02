import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Builds a triangular edge response (center highest, ±1 half) into a profile,
/// mimicking what a Sobel projection produces at a single sharp boundary.
private func bump(_ profile: inout [Double], at center: Int, height: Double) {
    func add(_ i: Int, _ v: Double) {
        guard i >= 0, i < profile.count else { return }
        profile[i] = max(profile[i], v)
    }
    add(center - 1, height * 0.5)
    add(center, height)
    add(center + 1, height * 0.5)
}

// MARK: - Peak finding

@Suite("Edge peak finding")
struct EdgePeakTests {

    @Test func emptyProfileHasNoPeaks() {
        #expect(EdgeProfile.peaks(in: []).isEmpty)
    }

    @Test func flatProfileHasNoPeaks() {
        // A profile with no signal (all zero) yields nothing.
        #expect(EdgeProfile.peaks(in: [Double](repeating: 0, count: 50)).isEmpty)
    }

    @Test func whiteRectOnBlackDetectsLeftAndRightEdges() {
        // A white rectangle spanning columns 20...80 produces strong vertical
        // boundaries at its left and right edges when magnitude is projected onto X.
        var profile = [Double](repeating: 0, count: 100)
        bump(&profile, at: 20, height: 1.0)
        bump(&profile, at: 80, height: 1.0)

        let peaks = EdgeProfile.peaks(in: profile)
        #expect(peaks.map(\.position) == [20, 80])
    }

    @Test func peaksAreSortedAscendingByPosition() {
        var profile = [Double](repeating: 0, count: 120)
        bump(&profile, at: 90, height: 0.8)
        bump(&profile, at: 10, height: 1.0)
        bump(&profile, at: 50, height: 0.6)

        let positions = EdgeProfile.peaks(in: profile).map(\.position)
        #expect(positions == positions.sorted())
        #expect(positions == [10, 50, 90])
    }

    @Test func noiseBelowThresholdIsRejected() {
        var profile = [Double](repeating: 0, count: 100)
        bump(&profile, at: 30, height: 1.0)     // real edge
        bump(&profile, at: 60, height: 0.1)     // noise, 10% of max < 25% threshold

        let peaks = EdgeProfile.peaks(in: profile, threshold: 0.25)
        #expect(peaks.map(\.position) == [30])
    }

    @Test func nearbyPeaksAreDedupedKeepingTheStronger() {
        // Two candidates within minSeparation collapse to one: the stronger wins.
        var profile = [Double](repeating: 0, count: 100)
        bump(&profile, at: 40, height: 1.0)
        bump(&profile, at: 42, height: 0.8)     // 2px away, below the 4px separation

        let peaks = EdgeProfile.peaks(in: profile, minSeparation: 4)
        #expect(peaks.count == 1)
        #expect(peaks.first?.position == 40)
    }

    @Test func peaksFartherApartThanSeparationAreBothKept() {
        var profile = [Double](repeating: 0, count: 100)
        bump(&profile, at: 40, height: 1.0)
        bump(&profile, at: 46, height: 0.8)     // 6px away, beyond 4px separation

        let positions = EdgeProfile.peaks(in: profile, minSeparation: 4).map(\.position)
        #expect(positions == [40, 46])
    }

    @Test func strengthIsNormalizedToTheStrongestPeak() {
        var profile = [Double](repeating: 0, count: 100)
        bump(&profile, at: 25, height: 2.0)     // strongest
        bump(&profile, at: 75, height: 1.0)     // half as strong

        let peaks = EdgeProfile.peaks(in: profile)
        let byPos = Dictionary(uniqueKeysWithValues: peaks.map { ($0.position, $0.strength) })
        #expect(byPos[25] == 1.0)
        #expect(abs((byPos[75] ?? 0) - 0.5) < 1e-9)
    }
}

// MARK: - EdgeMap assembly

@Suite("EdgeMap assembly")
struct EdgeMapAssemblyTests {

    @Test func fromProjectionsPopulatesBothAxes() {
        var x = [Double](repeating: 0, count: 100)
        bump(&x, at: 20, height: 1.0)
        bump(&x, at: 80, height: 1.0)
        var y = [Double](repeating: 0, count: 60)
        bump(&y, at: 15, height: 1.0)
        bump(&y, at: 45, height: 1.0)

        let map = EdgeMap.from(xProfile: x, yProfile: y, width: 100, height: 60)
        #expect(map.width == 100)
        #expect(map.height == 60)
        #expect(map.verticalEdges.map(\.position) == [20, 80])
        #expect(map.horizontalEdges.map(\.position) == [15, 45])
    }

    @Test func emptyMapHasNoEdges() {
        #expect(EdgeMap.empty.verticalEdges.isEmpty)
        #expect(EdgeMap.empty.horizontalEdges.isEmpty)
    }

    @Test func edgeMapRoundTripsThroughCodable() throws {
        let map = EdgeMap(width: 10, height: 8,
                          verticalEdges: [EdgeCandidate(position: 3, strength: 1)],
                          horizontalEdges: [EdgeCandidate(position: 4, strength: 0.5)])
        let data = try JSONEncoder().encode(map)
        let decoded = try JSONDecoder().decode(EdgeMap.self, from: data)
        #expect(decoded == map)
    }
}
