import AppKit
import PhotonzCore
import SwiftUI

/// Borderless panel for the global slide-down history overlay (phase 11.4).
/// A non-activating panel can't become key, so Esc wouldn't reach it — allow it.
private final class HistoryOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Drives the global history overlay's window: a borderless, floating panel
/// pinned to the top edge of the active display that **slides down + fades in**
/// on show and **slides up + fades out** on dismiss. Placement geometry is the
/// tested `HistoryOverlayLayout`; this is the thin AppKit shell. Dismisses on
/// Esc, click-away (inside or outside the app), or a re-toggle.
@MainActor
final class HistoryOverlayController {
    /// Called whenever the overlay goes away (Esc / click-away / re-toggle), so
    /// the coordinator can keep its `isHistoryShown` mirror in sync.
    var onDismiss: (() -> Void)?

    private var panel: HistoryOverlayPanel?
    private var layout: HistoryOverlayLayout?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    var isShown: Bool { panel != nil }

    /// The presented panel's screen frame (bottom-left origin) — used to convert
    /// an icon's overlay-local frame to screen coords for anchoring tooltips.
    var panelFrame: CGRect? { panel?.frame }

    private static let panelHeight: CGFloat = 208

    func show(content: some View, on screen: NSScreen) {
        if panel != nil { return }
        let layout = HistoryOverlayLayout(screen: screen.visibleFrame, height: Self.panelHeight)
        self.layout = layout

        let panel = HistoryOverlayPanel(
            contentRect: layout.hiddenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // No window shadow: it draws a rectangular outline around the full panel
        // bounds, reading as a second border outside the rounded glass shape.
        // The Liquid Glass surface provides its own depth.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = CGRect(origin: .zero, size: layout.hiddenFrame.size)
        panel.contentView = hosting

        panel.alphaValue = 0
        panel.setFrame(layout.hiddenFrame, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.34
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(layout.presentedFrame, display: true)
            panel.animator().alphaValue = 1
        }

        installDismissMonitors()
    }

    /// Slides the panel back up and removes it. `notify` fires `onDismiss` —
    /// false when the coordinator already knows (it called us), true for
    /// self-initiated dismissals (Esc / click-away).
    func hide(notify: Bool = true) {
        guard let panel, let layout else { return }
        removeDismissMonitors()
        self.panel = nil
        self.layout = nil
        if notify { onDismiss?() }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(layout.hiddenFrame, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            // AppKit invokes the completion on the main thread; assert it so the
            // main-actor `orderOut` call is statically clean under Swift 6.
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    // MARK: - Dismiss monitors

    private func installDismissMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.hide()
                return nil
            }
            return event
        }
        // Clicks inside our app but outside the panel dismiss it; clicks on the
        // panel pass through so its buttons work.
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window !== panel { self.hide() }
            return event
        }
        // Clicks in other apps dismiss it too.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeDismissMonitors() {
        for monitor in [keyMonitor, localClickMonitor, globalClickMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        keyMonitor = nil
        localClickMonitor = nil
        globalClickMonitor = nil
    }
}
