import CoreGraphics
import Foundation
import IOSurface
import PhotonzCore
import Synchronization

/// Runs document renders off the main actor with latest-wins coalescing:
/// at most one render is in flight, and when multiple documents are submitted
/// while one is rendering, only the most recent of them renders next — stale
/// intermediates are skipped, and frames are delivered in submission order.
///
/// A document is handed in synchronously (`submit`), under a lock, so the
/// asker never waits for a turn on any actor before the drawing can start.
/// It was an actor until 2026-11-18, and the canvas asked through a task
/// started on the main actor: that task waited for the main actor's next turn
/// before it even reached this one, which while a hand dragged the playhead of
/// the 6 minute reference edit cost 0.8 ms in the middle and 3.5 at the slow
/// end of every picture (`a-long-edit-with-transitions-plays-scrubs-and-ed`,
/// pass 17).
public final class RenderScheduler: Sendable {

    /// One finished render: the picture, the document it was drawn from, and
    /// the stamp it was submitted with, so whoever shows it knows exactly what
    /// is on screen (a recording's canvas needs the MOMENT the picture was
    /// drawn at, since the playhead may have moved on while it drew).
    public struct Frame: Sendable {
        public let image: CGImage?
        /// The GPU surface `image` is on, when it was drawn onto one (a
        /// video's whole picture, `DocumentRenderer.renderInteractiveFrame`):
        /// what the canvas shows while a video plays or a hand moves the
        /// playhead, with nothing copied on the way up.
        public var surface: IOSurfaceRef? { drawn?.surface }
        let drawn: DocumentRenderer.InteractiveFrame?
        public let document: PhotonzDocument
        public let stamp: Int
        /// Whatever the asker handed in with the document, back with its
        /// picture: the canvas marks a recording's picture drawn from the very
        /// frames its moment shows, which a speed walk reads.
        public let tag: Int
        /// How long the composite itself took, and how long from the ask to
        /// the picture, waiting its turn included. What a perf note is
        /// written from.
        public let drawMS: Double
        public let sinceAskedMS: Double
    }

    private struct Job {
        let document: PhotonzDocument
        let store: ImageStore?
        let contentScale: CGFloat
        let colorSpace: CGColorSpace?
        let stamp: Int
        let tag: Int
        let asked: ContinuousClock.Instant
    }

    private let renderer: DocumentRenderer
    private let store: ImageStore
    private let onFrame: @Sendable (Frame) async -> Void

    private struct Queue {
        var pending: Job?
        /// The task drawing, while one is; it ends when nothing is pending.
        var drainTask: Task<Void, Never>?
    }
    private let queue = Mutex(Queue())

    public convenience init(store: ImageStore, renderer: DocumentRenderer = DocumentRenderer(),
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
    ///
    /// `contentScale` is how much `document` was magnified by on its way here
    /// (`DocumentRenderer.renderInteractive`), and `colorSpace` the colours
    /// the frame is written in: the window's own, so it goes up as it is.
    public func submit(_ document: PhotonzDocument, store: ImageStore? = nil, stamp: Int = 0,
                       contentScale: CGFloat = 1, colorSpace: CGColorSpace? = nil, tag: Int = 0) {
        let job = Job(document: document, store: store, contentScale: contentScale,
                      colorSpace: colorSpace, stamp: stamp, tag: tag, asked: .now)
        queue.withLock { queue in
            queue.pending = job
            guard queue.drainTask == nil else { return }
            // Started here, inside the lock, so the drain that sees nothing
            // pending and the next submit can never miss each other.
            queue.drainTask = Task(priority: .high) { [self] in await drain() }
        }
    }

    /// Sets out the words of the documents `posed` makes, at low priority
    /// and off the queue pictures are drawn on, so the pictures that will
    /// show them find them kept (`DocumentRenderer.drawWordsAhead`). `posed`
    /// runs there too: posing a long edit at a moment is work the main
    /// thread need not do.
    public func drawWordsAhead(contentScale: CGFloat,
                               _ posed: @escaping @Sendable () -> [PhotonzDocument]) {
        Task.detached(priority: .utility) { [renderer, store] in
            for document in posed() {
                renderer.drawWordsAhead(document, store: store, contentScale: contentScale)
            }
        }
    }

    /// Suspends until every submitted document has been rendered or skipped.
    public func waitUntilIdle() async {
        while let task = queue.withLock({ $0.drainTask }) {
            await task.value
        }
    }

    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    /// The next job, or nil with the drain marked finished, in one step.
    private func takeNext() -> Job? {
        queue.withLock { queue in
            guard let job = queue.pending else {
                queue.drainTask = nil
                return nil
            }
            queue.pending = nil
            return job
        }
    }

    private func drain() async {
        while let job = takeNext() {
            // Incremental: unchanged regions are reused from the last frame.
            let began = ContinuousClock.now
            let drawn = renderer.renderInteractiveFrame(job.document, store: job.store ?? store,
                                                        contentScale: job.contentScale,
                                                        colorSpace: job.colorSpace)
            let done = ContinuousClock.now
            await onFrame(Frame(image: drawn?.image, drawn: drawn, document: job.document,
                                stamp: job.stamp, tag: job.tag,
                                drawMS: Self.ms(done - began), sinceAskedMS: Self.ms(done - job.asked)))
        }
    }
}
