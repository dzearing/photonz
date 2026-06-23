import AppKit
import SwiftUI

/// A floating tooltip on its own window, so it can **escape** the history
/// overlay's bounds (no reserved space inside each cell). Shown below the
/// pointer while hovering a capture's action icon; hidden on leave. Passive
/// (ignores mouse events) and above the overlay.
@MainActor
final class TooltipController {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    /// Show `text` with its top edge just below `screenPoint` (screen coords,
    /// bottom-left origin), horizontally centered and clamped to the screen.
    func show(_ text: String, below screenPoint: CGPoint) {
        hideWork?.cancel()
        hideWork = nil

        let hosting = NSHostingView(rootView: TooltipLabel(text: text))
        let size = hosting.fittingSize
        let panel = ensurePanel()
        hosting.frame = CGRect(origin: .zero, size: size)
        panel.contentView = hosting

        var origin = CGPoint(x: screenPoint.x - size.width / 2, y: screenPoint.y - size.height)
        let screen = NSScreen.screens.first { $0.frame.contains(screenPoint) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX + 4), vf.maxX - size.width - 4)
            origin.y = max(origin.y, vf.minY + 4)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    /// Hide shortly after (so moving between adjacent icons — leave then enter —
    /// doesn't flicker; the next `show` cancels the pending hide).
    func hide() {
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        hideWork?.cancel()
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu  // above the .floating history overlay
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.panel = panel
        return panel
    }
}

private struct TooltipLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
            .fixedSize()
    }
}
