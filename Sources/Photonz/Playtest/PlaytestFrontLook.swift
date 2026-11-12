#if PHOTONZ_PLAYTEST
import AppKit
import ObjectiveC
import PhotonzCore

/// Draws a walk's window the way it looks in front, without putting it there.
/// Probe builds only.
///
/// A walk never takes key or the front (2026-09-26), and a window behind
/// another app draws its background look: an on switch, the system's blue
/// button, a picked segment and the traffic lights all go grey. Until
/// 2026-11-12 every audit picture showed that look and apologised for it, and
/// runners chased the grey as bugs (the View | Edit chip, 2026-11-10).
///
/// AppKit keeps a window's KEY LOOK apart from whether it is key: it is how a
/// panel shows itself active without taking the keys. `acquireKeyAppearance`
/// hands a window that look and nothing else. Measured on 2026-11-12 in a
/// window of an app behind another: the app stayed inactive, the window stayed
/// unkeyed, no become-key notification was posted, and an NSSwitch, a SwiftUI
/// switch, `.borderedProminent` and a segmented picker drew their accent
/// colour from the very next display. In the probe, a walk's picture of the
/// editor and of Settings then matched the same walk run with the probe in
/// front (`"front": true`) to the pixel. The one thing it does not reach is a
/// default button (Return), whose pulse wants the app itself active.
///
/// The window server does not always agree. A window shown a moment before (a
/// recording's window sits at alpha 0 between pictures) is told it is not key
/// by an AppKit-defined event a beat after each lend, and AppKit hands the
/// look back: a-video-clip-fades-walk lent the look six times running and
/// lost it each time within 0.1s, and all five of its pictures came out grey.
/// So once a window is lent the look it keeps it for the rest of the walk:
/// `resignKeyAppearance` is refused for it. Holding it rather than lending
/// and taking it back at each picture also keeps the views that read the
/// look from rebuilding between steps, which a walk counting rebuilds would
/// otherwise see.
@MainActor
enum PlaytestFrontLook {
    /// The walk said `behindLook`: its pictures keep the background look.
    static var keepsTheBackgroundLook = false

    /// The windows holding a lent look, by identity.
    private static var lent: Set<ObjectIdentifier> = []
    private static var installed = false

    /// A new walk starts with nothing lent.
    static func startWalk(keepingTheBackgroundLook keep: Bool) {
        keepsTheBackgroundLook = keep
        lent.removeAll()
    }

    /// Whether `window` keeps its lent look against AppKit.
    static func holds(_ window: NSWindow) -> Bool {
        lent.contains(ObjectIdentifier(window))
    }

    /// Lends `window` (its sheet, while one is up) the look it has in front.
    /// Returns whether it had to be redrawn; asking again costs nothing.
    @discardableResult
    static func lend(_ window: NSWindow) -> Bool {
        guard !keepsTheBackgroundLook, !(NSApp.isActive && window.isKeyWindow) else { return false }
        install()
        let keyed = window.attachedSheet ?? window
        lent.insert(ObjectIdentifier(keyed))
        guard !hasKeyLook(keyed) else { return false }
        let acquire = NSSelectorFromString("acquireKeyAppearance")
        guard keyed.responds(to: acquire) else { return false }
        keyed.perform(acquire)
        keyed.display()
        if keyed !== window { window.display() }
        return true
    }

    /// Whether a picture of `window` taken now shows its background look:
    /// the probe is not the active app with it key, and it holds no key look.
    static func showsBackgroundLook(_ window: NSWindow?) -> Bool {
        guard let window else { return PlaytestCaptureLedger.showsBackgroundLook(inFront: false, keyLook: false) }
        let keyed = window.attachedSheet ?? window
        return PlaytestCaptureLedger.showsBackgroundLook(
            inFront: NSApp.isActive && (keyed.isKeyWindow || window.isKeyWindow),
            keyLook: hasKeyLook(keyed))
    }

    static func hasKeyLook(_ window: NSWindow) -> Bool {
        let getter = "hasKeyAppearance"
        guard window.responds(to: NSSelectorFromString(getter)) else { return false }
        return (window.value(forKey: getter) as? Bool) ?? false
    }

    private static func install() {
        guard !installed else { return }
        installed = true
        guard let from = class_getInstanceMethod(NSWindow.self, NSSelectorFromString("resignKeyAppearance")),
              let to = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.photonz_resignKeyAppearance))
        else { return }
        method_exchangeImplementations(from, to)
    }
}

extension NSWindow {
    /// Exchanged with AppKit's `resignKeyAppearance`: a window holding a look
    /// a walk lent it keeps it (`PlaytestFrontLook`); any other window resigns
    /// as AppKit asks.
    @objc dynamic func photonz_resignKeyAppearance() {
        let holds = MainActor.assumeIsolated { PlaytestFrontLook.holds(self) }
        if holds { return }
        // Exchanged, so this call reaches AppKit's own.
        photonz_resignKeyAppearance()
    }
}
#endif
