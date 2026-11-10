import AppKit
import ObjectiveC

/// Key presses for a drag that is in hand.
///
/// From macOS 27 AppKit drops every key press that arrives while a SwiftUI
/// gesture is tracking the pointer. `-[NSApplication run]` takes the press off
/// the queue and, while `+[_NSGestureEnvironmentBase isTrackingExclusiveGesture]`
/// says yes, never hands it to `sendEvent`, so no event monitor, window or view
/// ever sees it, and it is not waiting when the button comes up either. Every
/// SwiftUI drag counts (`gesture`, `simultaneousGesture` and
/// `highPriorityGesture` alike) and every key does; a drag in a plain AppKit
/// view keeps its keys, and the `NSGestureRecognizerSuppressesMainMenuActions`
/// setting AppKit reads beside the check does not turn it off (all traced on
/// 2026-11-10 with a test app and the disassembly of `run`).
///
/// So Escape, the key that calls a drag off, cannot be listened for with
/// `NSEvent.addLocalMonitorForEvents` while a SwiftUI drag holds the pointer.
/// A drag listens here instead. `install` puts a step in front of
/// `nextEventMatchingMask:untilDate:inMode:dequeue:`, the call `run` takes the
/// press with, which offers each press to the watches before AppKit
/// decides whether to drop it; and one in front of `sendEvent:`, so a press a
/// watch took goes no further where AppKit did not drop it (macOS 26).
///
/// Both steps go on `NSApplication` itself. The app object is SwiftUI's own
/// subclass (`AppKitApplication`), which overrides neither call, and SwiftUI
/// ignores an Info.plist `NSPrincipalClass`, so a subclass of ours would never
/// be the one running.
@MainActor
enum HeldDragKeys {
    /// One drag's watch, to give back when the drag is over.
    struct Watch: Equatable {
        fileprivate let id: Int
        fileprivate let monitor: Any?

        static func == (lhs: Watch, rhs: Watch) -> Bool { lhs.id == rhs.id }
    }

    private static var installed = false
    private static var watches: [(id: Int, take: @MainActor (NSEvent) -> Bool)] = []
    private static var nextID = 0
    /// The last press a watch took, so `sendEvent` can let it go no further.
    private static weak var taken: NSEvent?

    /// Once, at launch, before the first key press.
    static func install() {
        let next = (#selector(NSApplication.nextEvent(matching:until:inMode:dequeue:)),
                    #selector(NSApplication.photonz_nextEvent(matching:until:inMode:dequeue:)))
        let send = (#selector(NSApplication.sendEvent(_:)), #selector(NSApplication.photonz_sendEvent(_:)))
        guard !installed, exchange(next) else { return }
        guard exchange(send) else {
            // Put the first back: half a hook is worse than none.
            _ = exchange(next)
            return
        }
        installed = true
    }

    private static func exchange(_ pair: (Selector, Selector)) -> Bool {
        guard let from = class_getInstanceMethod(NSApplication.self, pair.0),
              let to = class_getInstanceMethod(NSApplication.self, pair.1) else { return false }
        method_exchangeImplementations(from, to)
        return true
    }

    /// Start watching key presses. `take` answers true when it used the press;
    /// one it leaves goes on to the app as it would have.
    static func watch(_ take: @escaping @MainActor (NSEvent) -> Bool) -> Watch {
        nextID += 1
        guard installed else {
            // Nothing in front of the run loop: an event monitor, which hears
            // every key except the ones a SwiftUI drag drops.
            let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                MainActor.assumeIsolated { take(event) } ? nil : event
            }
            return Watch(id: nextID, monitor: monitor)
        }
        watches.append((nextID, take))
        return Watch(id: nextID, monitor: nil)
    }

    /// Stop watching. Safe to call twice.
    static func stop(_ watch: Watch) {
        if let monitor = watch.monitor { NSEvent.removeMonitor(monitor) }
        watches.removeAll { $0.id == watch.id }
    }

    /// A press the run loop just took off the queue, offered newest watch first
    /// until one takes it.
    fileprivate static func offer(_ event: NSEvent) {
        guard event.type == .keyDown, !watches.isEmpty else { return }
        for watch in watches.reversed() where watch.take(event) {
            taken = event
            return
        }
    }

    /// Whether a watch already used this press.
    fileprivate static func took(_ event: NSEvent) -> Bool {
        guard let taken else { return false }
        return taken === event
    }
}

extension NSApplication {
    /// Exchanged with `nextEventMatchingMask:untilDate:inMode:dequeue:` by
    /// `HeldDragKeys.install`, so calling it here reaches the real one.
    @objc(photonz_nextEventMatchingMask:untilDate:inMode:dequeue:)
    dynamic func photonz_nextEvent(matching mask: NSEvent.EventTypeMask, until expiration: Date?,
                                   inMode mode: RunLoop.Mode, dequeue deqFlag: Bool) -> NSEvent? {
        let event = photonz_nextEvent(matching: mask, until: expiration, inMode: mode, dequeue: deqFlag)
        if deqFlag, let event { HeldDragKeys.offer(event) }
        return event
    }

    /// Exchanged with `sendEvent:`, so calling it here reaches the real one.
    @objc(photonz_sendEvent:)
    dynamic func photonz_sendEvent(_ event: NSEvent) {
        if HeldDragKeys.took(event) { return }
        photonz_sendEvent(event)
    }
}
