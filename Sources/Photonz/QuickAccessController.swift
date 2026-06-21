import AppKit
import PhotonzCore
import SwiftUI

/// Borderless, non-activating panel for the Quick Access Overlay (phase 11.7).
/// Unlike the history overlay it never needs to become key (no Esc / text), so
/// it stays a passive HUD that never steals focus from what you're doing.
private final class QuickAccessPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Drives the post-capture Quick Access Overlay window: a small floating
/// thumbnail that **slides into a screen corner + fades in** after a capture and
/// **auto-closes** after a timeout (paused while the pointer is over it).
/// Placement is the tested `QuickAccessLayout`; this is the thin AppKit shell.
/// A second capture while one is up just retargets the same panel.
@MainActor
final class QuickAccessController {
    /// Fired when the overlay goes away (timeout or an action), so the
    /// coordinator can drop its reference to the shown entry.
    var onDismiss: (() -> Void)?

    private var panel: QuickAccessPanel?
    private var hosting: NSHostingView<AnyView>?
    private var layout: QuickAccessLayout?
    private var autoCloseItem: DispatchWorkItem?

    var isShown: Bool { panel != nil }

    private static let size = CGSize(width: 232, height: 196)
    private static let autoCloseDelay: TimeInterval = 6
    /// Shorter grace period after the pointer leaves, so it doesn't linger.
    private static let hoverExitDelay: TimeInterval = 1.5

    /// Show the overlay for `content` on `screen`, or — if one is already up —
    /// swap in the new content and restart the timer (rapid successive captures).
    func show(content: some View, on screen: NSScreen, corner: ScreenCorner = .bottomLeft) {
        let wrapped = AnyView(content)
        if let hosting {
            hosting.rootView = wrapped
            scheduleAutoClose()
            return
        }

        let layout = QuickAccessLayout(screen: screen.visibleFrame, size: Self.size, corner: corner)
        self.layout = layout

        let panel = QuickAccessPanel(
            contentRect: layout.hiddenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false  // the glass surface carries its own depth (see history overlay)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let hosting = NSHostingView(rootView: wrapped)
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = CGRect(origin: .zero, size: layout.hiddenFrame.size)
        panel.contentView = hosting
        self.hosting = hosting

        panel.alphaValue = 0
        panel.setFrame(layout.hiddenFrame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(layout.restingFrame, display: true)
            panel.animator().alphaValue = 1
        }

        scheduleAutoClose()
    }

    func hide(notify: Bool = true) {
        guard let panel, let layout else { return }
        cancelAutoClose()
        self.panel = nil
        self.hosting = nil
        self.layout = nil
        if notify { onDismiss?() }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(layout.hiddenFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    /// The SwiftUI content reports hover here: pause the auto-close while the
    /// pointer is over the card, restart a short countdown when it leaves.
    func setHovering(_ hovering: Bool) {
        if hovering {
            cancelAutoClose()
        } else {
            scheduleAutoClose(after: Self.hoverExitDelay)
        }
    }

    // MARK: - Auto-close

    private func scheduleAutoClose(after delay: TimeInterval = QuickAccessController.autoCloseDelay) {
        cancelAutoClose()
        let item = DispatchWorkItem { [weak self] in self?.hide() }
        autoCloseItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelAutoClose() {
        autoCloseItem?.cancel()
        autoCloseItem = nil
    }
}
