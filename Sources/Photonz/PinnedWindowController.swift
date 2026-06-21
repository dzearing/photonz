import AppKit
import PhotonzCore
import SwiftUI

/// Manages pin-to-screen floating windows (phase 11.8): borderless, always-on-top
/// windows that float a screenshot above your work as reference material —
/// draggable anywhere, with adjustable size and opacity. One controller owns any
/// number of pinned windows; each unpins independently via its own close button.
/// Sizing/opacity policy is the tested `PinnedImageMetrics`; this is the shell.
@MainActor
final class PinnedWindowController {
    private var windows: [NSWindow] = []
    /// Each new pin is offset from the last so they don't stack exactly.
    private var cascadeStep = 0

    /// Largest initial edge of a freshly pinned window (it stays resizable).
    private static let initialMaxDimension: CGFloat = 360

    func pin(image: CGImage, on screen: NSScreen) {
        let imageSize = CGSize(width: image.width, height: image.height)
        let contentSize = PinnedImageMetrics.fittedSize(imageSize: imageSize, maxDimension: Self.initialMaxDimension)
        guard contentSize.width > 0 else { return }

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating                 // above normal windows
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true // drag from anywhere on the image
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.aspectRatio = contentSize          // lock proportions on resize
        window.minSize = CGSize(width: 80, height: 80)

        let hosting = NSHostingView(rootView: PinnedImageView(
            image: image,
            onClose: { [weak self, weak window] in
                if let window { self?.unpin(window) }
            }))
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        window.setFrameTopLeftPoint(cascadeOrigin(for: contentSize, on: screen))
        window.orderFrontRegardless()
        windows.append(window)
    }

    private func unpin(_ window: NSWindow) {
        window.orderOut(nil)
        windows.removeAll { $0 === window }
    }

    /// Top-left start point, cascading down-right from near the top-right corner
    /// of the display so multiple pins fan out instead of overlapping.
    private func cascadeOrigin(for size: CGSize, on screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        let inset: CGFloat = 24
        let offset = CGFloat(cascadeStep % 6) * 28
        cascadeStep += 1
        let x = visible.maxX - size.width - inset + offset
        let y = visible.maxY - inset - offset
        return NSPoint(x: x, y: y)
    }
}
