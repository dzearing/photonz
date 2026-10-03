import Foundation

/// Waits out the main run loop pass the caller is in, frame committed and all.
///
/// For work that may follow what a person just did by a frame but must not
/// share that frame with it: the history strip moves its ring in the frame an
/// arrow key lands in, and builds the focused tile's buttons and starts its
/// scroll in the next one, so neither frame runs long. A short sleep is not
/// the same thing: when the pass it started in runs longer than the sleep, the
/// work comes back inside that same pass.
@MainActor
enum NextRunLoopPass {
    /// Returns at the start of the next pass. The observer fires once, after
    /// every other before-waiting observer of the pass (the frame's commit is
    /// one of them), and resuming the caller there needs the main queue, which
    /// is the next pass.
    static func start() async {
        await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
            let observer = CFRunLoopObserverCreateWithHandler(
                nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max
            ) { _, _ in
                resume.resume()
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }
}
