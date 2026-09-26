import AppKit
import QuartzCore

/// The display's own refresh, as something the main actor can wait on or be
/// called on.
///
/// A hand dragging the playhead sends moves faster than a screen shows
/// pictures (a trackpad at 120 a second on a 60 hertz display), and drawing a
/// picture per move built a queue behind a fast drag. Pacing the work by the
/// display draws exactly one picture per refresh, whatever the hand does
/// (`scrubbing-is-smooth-never-goes-black-and-the-pic`).
///
/// A display asleep behind a locked screen may stop refreshing altogether, so
/// every wait has a fallback: a refresh that has not come in `fallback` seconds
/// is taken as having come.
@MainActor
final class DisplayFrames: NSObject {

    private var link: CADisplayLink?
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var onFrame: (() -> Void)?
    private let fallback: Double
    private var fallbackTask: Task<Void, Never>?

    /// How many refreshes have come since this was made. A walk reads it to
    /// say how many display frames something took.
    private(set) var count = 0

    init(view: NSView, fallback: Double = 1.0 / 50) {
        self.fallback = fallback
        super.init()
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        link.isPaused = true
        self.link = link
    }

    /// Wait for the next refresh.
    func next() async {
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
            wake()
        }
    }

    /// Call `work` once per refresh until `stop()`. Replaces any work already
    /// running.
    func run(_ work: @escaping () -> Void) {
        onFrame = work
        wake()
    }

    /// Stop calling the work. Anybody waiting is still woken on the next
    /// refresh.
    func stop() {
        onFrame = nil
        if waiting.isEmpty { sleepUntilNeeded() }
    }

    func invalidate() {
        onFrame = nil
        fallbackTask?.cancel()
        link?.invalidate()
        link = nil
        let woken = waiting
        waiting = []
        woken.forEach { $0.resume() }
    }

    private func wake() {
        link?.isPaused = false
        armFallback()
    }

    private func sleepUntilNeeded() {
        link?.isPaused = true
        fallbackTask?.cancel()
        fallbackTask = nil
    }

    private func armFallback() {
        guard fallbackTask == nil else { return }
        let delay = fallback
        fallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.fallbackTask = nil
            self.refresh()
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        fallbackTask?.cancel()
        fallbackTask = nil
        refresh()
    }

    private func refresh() {
        count += 1
        let woken = waiting
        waiting = []
        onFrame?()
        woken.forEach { $0.resume() }
        if onFrame == nil && waiting.isEmpty {
            sleepUntilNeeded()
        } else {
            armFallback()
        }
    }
}
