import CoreGraphics
import Foundation
import PhotonzCore

/// Runs document renders off the main actor with latest-wins coalescing:
/// at most one render is in flight, and when multiple documents are submitted
/// while one is rendering, only the most recent of them renders next — stale
/// intermediates are skipped, and frames are delivered in submission order.
public actor RenderScheduler {
    private let renderer: DocumentRenderer
    private let store: ImageStore
    private let onFrame: @Sendable (CGImage?) async -> Void

    private var pending: PhotonzDocument?
    private var drainTask: Task<Void, Never>?

    public init(store: ImageStore, renderer: DocumentRenderer = DocumentRenderer(),
                onFrame: @escaping @Sendable (CGImage?) async -> Void) {
        self.store = store
        self.renderer = renderer
        self.onFrame = onFrame
    }

    /// Queues `document` as the next thing to render, replacing any document
    /// that was queued but not yet started.
    public func submit(_ document: PhotonzDocument) {
        pending = document
        guard drainTask == nil else { return }
        drainTask = Task { await drain() }
    }

    /// Suspends until every submitted document has been rendered or skipped.
    public func waitUntilIdle() async {
        while let task = drainTask {
            await task.value
        }
    }

    private func drain() async {
        while let document = pending {
            pending = nil
            await onFrame(renderer.render(document, store: store))
        }
        drainTask = nil
    }
}
