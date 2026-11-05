#if PHOTONZ_PLAYTEST
import AppKit
import ObjectiveC

/// Keeps the probe off the Mac's real clipboard. Probe builds only.
///
/// The loop runs walks all day, and each copy a walk made went on the general
/// clipboard: over whatever the person at this Mac had just copied, and through
/// Universal Clipboard onto their other Macs. So in a probe, the general
/// clipboard IS a private named one: `+generalPasteboard` and asking for the
/// general board by name both answer with it. That is one switch at the root
/// rather than a change at each of the app's call sites, so it also covers what
/// AppKit does for itself, such as ⌘C and ⌘V in a text field.
///
/// `Scripts/clipboard-timing/` measures the real clipboard against real apps on
/// purpose and sets `PHOTONZ_PROBE_REAL_CLIPBOARD=1`. Nothing else may.
enum PlaytestPrivateClipboard {
    static let name = NSPasteboard.Name("com.dzearing.photonz.probe.clipboard")

    /// Before anything can touch a clipboard. A named board outlives the app,
    /// so it is emptied here and every launch starts from nothing.
    @MainActor
    static func install() {
        guard ProcessInfo.processInfo.environment["PHOTONZ_PROBE_REAL_CLIPBOARD"] != "1" else {
            NSLog("Probe clipboard: the real one, as asked")
            return
        }
        exchange(NSSelectorFromString("generalPasteboard"),
                 #selector(NSPasteboard.photonz_probeGeneralPasteboard))
        exchange(NSSelectorFromString("pasteboardWithName:"),
                 #selector(NSPasteboard.photonz_probePasteboard(withName:)))
        NSPasteboard.general.clearContents()
    }

    private static func exchange(_ original: Selector, _ replacement: Selector) {
        guard let from = class_getClassMethod(NSPasteboard.self, original),
              let to = class_getClassMethod(NSPasteboard.self, replacement) else {
            fatalError("The probe could not move off the real clipboard")
        }
        method_exchangeImplementations(from, to)
    }
}

extension NSPasteboard {
    @objc dynamic class func photonz_probeGeneralPasteboard() -> NSPasteboard {
        // Exchanged, so this is the real `pasteboardWithName:`'s stand-in, which
        // turns the private name into the private board.
        NSPasteboard(name: PlaytestPrivateClipboard.name)
    }

    @objc(photonz_probePasteboardWithName:)
    dynamic class func photonz_probePasteboard(withName name: NSPasteboard.Name) -> NSPasteboard {
        // Exchanged, so this call reaches the real one.
        photonz_probePasteboard(withName: name == .general ? PlaytestPrivateClipboard.name : name)
    }
}
#endif
