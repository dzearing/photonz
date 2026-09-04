// Opening a menu that lives inside the window, for a scripted walk.
//
// A menu is not part of the window it hangs off. It is a window of its own, and
// while it is open AppKit runs its own event loop: the click that opened it
// does not return until the menu closes, and nothing on the ordinary main queue
// runs in the meantime. So a walk that clicked one simply stopped, forever, and
// every audit that wanted to show the words on a dock menu's rows had to settle
// for a test that asserted them instead.
//
// The way out is to arrange the way out first. A thread waits, then reaches the
// main thread with `perform(_:on:with:waitUntilDone:modes:)` naming the tracking
// mode by hand — which IS serviced while a menu is up, unlike anything posted to
// the main queue. From in there the menu can be read, photographed, chosen from,
// and told to close, which lets the original click finally return.
//
// The picture cannot be an offscreen render: a menu's contents are drawn outside
// this process, so drawing its window into a bitmap yields a blank plate. It has
// to be a real screen capture, which is the only kind of picture of a menu there
// is.
#if PHOTONZ_PLAYTEST
import AppKit
import ScreenCaptureKit

/// A block to run on the main thread in whatever run loop mode is current,
/// including the one a menu's tracking loop uses.
@MainActor final class PlaytestTrackingHop: NSObject {
    private let body: @MainActor () -> Void

    init(_ body: @escaping @MainActor () -> Void) {
        self.body = body
    }

    /// Runs `body` on the main thread after `delay`, even if the main thread is
    /// inside a menu's tracking loop by then.
    func schedule(after delay: TimeInterval) {
        Thread.detachNewThread { [self] in
            Thread.sleep(forTimeInterval: delay)
            perform(#selector(fire), on: .main, with: nil as AnyObject?, waitUntilDone: false,
                    modes: [RunLoop.Mode.eventTracking.rawValue,
                            RunLoop.Mode.default.rawValue,
                            RunLoop.Mode.modalPanel.rawValue])
        }
    }

    @objc nonisolated private func fire() {
        MainActor.assumeIsolated { body() }
    }
}

/// What happened while a panel menu was open.
struct PlaytestMenuReading: Sendable {
    /// Every row, top to bottom, in the words on screen. A separator reads as
    /// an empty string, so the shape of the menu survives too.
    var rows: [String] = []
    /// The rows nothing would happen on, which is how a dimmed row reads.
    var dimmed: [String] = []
    /// The row that was picked, if the step asked for one.
    var chose: String?
    /// Why no row was picked when one was asked for.
    var problem: String?
    /// Where the picture went, when one was taken.
    var shot: String?
}

enum PlaytestPanelMenu {
    /// Every menu inside the window, by the words on its button. SwiftUI draws
    /// a `Menu` as a pop up button, so this is the whole list of them.
    @MainActor static func buttons(in content: NSView) -> [NSPopUpButton] {
        var found: [NSPopUpButton] = []
        func walk(_ view: NSView) {
            if let button = view as? NSPopUpButton, !button.isHidden { found.append(button) }
            for sub in view.subviews { walk(sub) }
        }
        walk(content)
        return found
    }

    /// What the button says, which is the name a walk uses for it. A menu drawn
    /// as an icon says nothing, and reads as its accessibility label instead.
    @MainActor static func title(of button: NSPopUpButton) -> String {
        if !button.title.isEmpty { return button.title }
        return button.accessibilityLabel() ?? button.accessibilityTitle() ?? ""
    }

    /// What a walk calls this menu, and what it is showing right now.
    ///
    /// A menu wears its own value — "24 pt", "Top" — so naming it by what it
    /// says is naming it by something that changes the moment the walk uses
    /// it. The row it sits on does not change, so that is its name, and its
    /// value goes in the detail, the same promise every other control in the
    /// panel makes. A menu on no named row keeps its words as its name.
    @MainActor static func naming(of button: NSPopUpButton,
                                  among fields: [PanelTargetView]) -> (name: String, detail: String) {
        let showing = title(of: button)
        let box = button.convert(button.bounds, to: nil)
        guard let row = PlaytestPanelPress.field(at: box, among: fields), row != showing else {
            return (showing, "")
        }
        return (row, showing)
    }

    /// The visible window a menu is showing in, if one is up.
    @MainActor static func openMenuWindow() -> NSWindow? {
        NSApp.windows.first {
            $0.isVisible && $0.level.rawValue >= NSWindow.Level.popUpMenu.rawValue
        }
    }

    /// Photographs an open menu, in place over the window it belongs to.
    ///
    /// Everything here is deliberately callback-based and answers on a
    /// background queue: awaiting anything would wait on the main queue, which
    /// the menu's own event loop is holding, and the walk would never come
    /// back.
    ///
    /// The filter names the two windows by hand — the editor and the menu — so
    /// the picture is our app and nothing else. A whole-display capture would
    /// have caught whatever the person at this machine happens to be looking
    /// at, and a capture of the menu on its own is a plate of words floating in
    /// the dark with no clue where it came from.
    nonisolated static func capture(menuWindow: Int, over hostWindow: Int, host frame: CGRect,
                                    to url: URL, then done: @escaping @Sendable (String) -> Void) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            guard let content else {
                done("could not read the screen: \(error?.localizedDescription ?? "unknown")")
                return
            }
            let wanted = [menuWindow, hostWindow].compactMap { number in
                content.windows.first { $0.windowID == CGWindowID(number) }
            }
            guard wanted.count == 2, let display = content.displays.first(where: {
                $0.frame.intersects(frame)
            }) ?? content.displays.first else {
                done("the open menu is not a window the screen recorder can see")
                return
            }
            let filter = SCContentFilter(display: display, including: wanted)
            // A menu opens where it fits, which for one on the far right of the
            // dock is half outside the window. The picture takes in both, so no
            // row is ever cut off the edge of it.
            let crop = wanted.reduce(frame) { $0.union($1.frame) }
            let config = SCStreamConfiguration()
            config.sourceRect = CGRect(x: crop.minX - display.frame.minX,
                                       y: crop.minY - display.frame.minY,
                                       width: crop.width, height: crop.height)
            config.width = Int(crop.width * 2)
            config.height = Int(crop.height * 2)
            config.showsCursor = false
            config.captureResolution = .best
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
                guard let image else {
                    done("the menu would not photograph: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                    done("the menu's picture would not encode")
                    return
                }
                do {
                    try png.write(to: url)
                    done("\(url.lastPathComponent) \(image.width)x\(image.height)")
                } catch {
                    done("the menu's picture would not save: \(error.localizedDescription)")
                }
            }
        }
    }
}
#endif
