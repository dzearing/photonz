import CoreGraphics
import Foundation
import PhotonzCore

/// Draws sharp tiles of a moving picture one at a time, newest first.
///
/// A zoomed-in canvas shows a sharp tile of what you can see over the
/// document-sized composite (`DocumentRenderer.renderTile`). While a picture
/// plays, that tile has to be drawn again for every frame, or the canvas shows
/// the composite blown up eight or sixteen times: an icon at 800% played as
/// 24 grey blocks across. This is the pacing for that: at most one tile draws
/// at a time, and every frame asked for while it draws is overtaken by the
/// newest, so a tile that takes longer than a frame lowers the rate it is
/// redrawn at rather than building a queue the playhead has already left.
public actor TileScheduler {

    /// One finished tile, the stamp it was asked with, and what it cost.
    public struct Delivery: Sendable {
        public let tile: CrispTile?
        public let stamp: Int
        public let drawMS: Double
    }

    private struct Job: Sendable {
        let document: PhotonzDocument
        let region: CGRect
        let scale: CGFloat
        let magnifyNearest: Bool
        let colorSpace: CGColorSpace?
        let stamp: Int
    }

    private let renderer: DocumentRenderer
    private let store: ImageStore
    private let onDelivery: @Sendable (Delivery) async -> Void
    private var pending: Job?
    private var drainTask: Task<Void, Never>?

    public init(store: ImageStore, renderer: DocumentRenderer = DocumentRenderer(),
                onDelivery: @escaping @Sendable (Delivery) async -> Void) {
        self.store = store
        self.renderer = renderer
        self.onDelivery = onDelivery
    }

    /// Asks for `region` of `document`, in document points, drawn at `scale`
    /// pixels per point, replacing whatever was asked for and not yet begun.
    public func submit(_ document: PhotonzDocument, region: CGRect, scale: CGFloat,
                       magnifyNearest: Bool, colorSpace: CGColorSpace? = nil, stamp: Int) {
        pending = Job(document: document, region: region, scale: scale,
                      magnifyNearest: magnifyNearest, colorSpace: colorSpace, stamp: stamp)
        guard drainTask == nil else { return }
        drainTask = Task { await drain() }
    }

    /// Forgets the tile asked for and not yet begun: the picture stopped.
    public func dropPending() {
        pending = nil
    }

    /// Suspends until every tile asked for has been drawn or skipped.
    public func waitUntilIdle() async {
        while let task = drainTask {
            await task.value
        }
    }

    private func drain() async {
        while let job = pending {
            pending = nil
            let began = ContinuousClock.now
            // Drawn off the actor, so the next frame's ask lands while this
            // one draws and overtakes everything asked before it, instead of
            // waiting its turn behind the draw and being drawn in order.
            let renderer = renderer, store = store
            let tile = await Task.detached(priority: .userInitiated) {
                renderer.renderTile(job.document, store: store, region: job.region,
                                    scale: job.scale, magnifyNearest: job.magnifyNearest,
                                    colorSpace: job.colorSpace)
            }.value
            let took = ContinuousClock.now - began
            let ms = Double(took.components.seconds) * 1000
                + Double(took.components.attoseconds) / 1e15
            await onDelivery(Delivery(tile: tile, stamp: job.stamp, drawMS: ms))
        }
        drainTask = nil
    }
}
