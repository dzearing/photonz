import CoreFoundation
import PhotonzCore

/// Hands each run-loop pass to one piece of the dock (`PanelLandingTurns`):
/// a section the dock lets in, or the rows a section brings a pass late.
///
/// A pass here runs from one sleep of the main run loop to the next, which is
/// when SwiftUI hands what changed to Core Animation, so two pieces that ask
/// within one pass would be built in the same frame.
@MainActor
enum PanelLanding {
    private static var turns = PanelLandingTurns()
    private static var pass = 0
    private static var counting = false

    /// Whether a piece may land now. True takes the pass; false means wait for
    /// the next pass (`NextRunLoopPass.start()`) and ask again.
    static func mayLand(restAfter: Int = 0) -> Bool {
        countPasses()
        return turns.claim(pass: pass, restAfter: restAfter)
    }

    /// Counts passes from the first ask on. Last of the before-waiting
    /// observers, so the frame's own commit is inside the pass it ends.
    private static func countPasses() {
        guard !counting else { return }
        counting = true
        let observer = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max
        ) { _, _ in
            MainActor.assumeIsolated { pass &+= 1 }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}
