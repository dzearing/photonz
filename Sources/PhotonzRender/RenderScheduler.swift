import CoreGraphics
import Foundation
import PhotonzCore

/// Runs document renders off the main actor with latest-wins coalescing:
/// at most one render is in flight, and when multiple documents are submitted
/// while one is rendering, only the most recent of them renders next — stale
/// intermediates are skipped, and frames are delivered in submission order.
public actor RenderScheduler {

    /// One finished render: the picture, the document it was drawn from, and
    /// the stamp it was submitted with, so whoever shows it knows exactly what
    /// is on screen (a recording's canvas needs the MOMENT the picture was
    /// drawn at, since the playhead may have moved on while it drew).
    public struct Frame: Sendable {
        public let image: CGImage?
        public let document: PhotonzDocument
        public let stamp: Int
        /// How long the composite itself took, and how long from the ask to
        /// the picture, waiting its turn included. What a perf note is
        /// written from.
        public let drawMS: Double
        public let sinceAskedMS: Double
    }

    private struct Job {
        let document: PhotonzDocument
        let store: ImageStore?
        let stamp: Int
        let asked: ContinuousClock.Instant
    }

    private let renderer: DocumentRenderer
    private let store: ImageStore
    private let onFrame: @Sendable (Frame) async -> Void

    private var pending: Job?
    private var drainTask: Task<Void, Never>?

    public init(store: ImageStore, renderer: DocumentRenderer = DocumentRenderer(),
                onFrame: @escaping @Sendable (CGImage?) async -> Void) {
        self.init(store: store, renderer: renderer, onDelivery: { await onFrame($0.image) })
    }

    public init(store: ImageStore, renderer: DocumentRenderer = DocumentRenderer(),
                onDelivery: @escaping @Sendable (Frame) async -> Void) {
        self.store = store
        self.renderer = renderer
        self.onFrame = onDelivery
    }

    /// Queues `document` as the next thing to render, replacing any document
    /// that was queued but not yet started.
    ///
    /// `store` draws the render from a copy of the pictures taken when it was
    /// asked for (`ImageStore.snapshot`) rather than the live store, so a
    /// picture taken out of the store while the render waits its turn is still
    /// there when it draws. A recording's frames come and go many times a
    /// second while a hand scrubs, and a frame dropped between the ask and the
    /// draw used to draw as nothing: the black flash of
    /// `scrubbing-is-smooth-never-goes-black-and-the-pic`.
    public func submit(_ document: PhotonzDocument, store: ImageStore? = nil, stamp: Int = 0) {
        pending = Job(document: document, store: store, stamp: stamp, asked: .now)
        guard drainTask == nil else { return }
        drainTask = Task { await drain() }
    }

    /// Suspends until every submitted document has been rendered or skipped.
    public func waitUntilIdle() async {
        while let task = drainTask {
            await task.value
        }
    }

    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    private func drain() async {
        while let job = pending {
            pending = nil
            // Incremental: unchanged regions are reused from the last frame.
            let began = ContinuousClock.now
            let image = renderer.renderInteractive(job.document, store: job.store ?? store)
            let done = ContinuousClock.now
            await onFrame(Frame(image: image, document: job.document, stamp: job.stamp,
                                drawMS: Self.ms(done - began), sinceAskedMS: Self.ms(done - job.asked)))
        }
        drainTask = nil
    }
}
