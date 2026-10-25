import CoreGraphics
import PhotonzCore
@testable import PhotonzRender

/// The dabs of `stroke` in the batches the live stroke is handed them, one
/// per sample and the last on lifting, with a mouse stroke's end already
/// thinned (`BrushPlacement.taperedOut`). Marking these a batch at a time is
/// what the live overlay would draw had it known where the stroke ends, so
/// comparing it with the landed stroke checks the marking alone, apart from
/// the taper laid on when the pointer lifts (`BrushDynamicsTests`).
func landedBatches(_ stroke: BrushStroke, jitter: CGFloat = 0) -> [[BrushDab]] {
    var walker = BrushPlacement.Walker(settings: stroke.settings, seed: stroke.seed, jitter: jitter)
    var batches = stroke.samples.map { walker.add($0) }
    batches.append(walker.finish())
    var landed = BrushPlacement.taperedOut(batches.flatMap { $0 }, for: stroke)[...]
    return batches.map { batch in
        let next = Array(landed.prefix(batch.count))
        landed = landed.dropFirst(batch.count)
        return next
    }
}
