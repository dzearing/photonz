import AppKit
import QuartzCore
import PhotonzCore
import SwiftUI

// **The picture a History tile is carried by is the app's own** (user
// 2026-10-29: "i see the ghost in the timeline but the thumbnail is still
// visible!!! EITHER OR, not both!!!").
//
// The picture AppKit draws under the pointer belongs to the drag session, and
// three ways of reaching it from the app (the view the strip was hosted in,
// every view starting a drag, every window and view the drag passed over)
// never once changed it in a real drag. So the tile now hands AppKit an empty
// picture (`CaptureThumbnailView`) and this panel carries the tile instead: it
// follows the pointer until the button comes up, and fades away while the
// timeline draws the clip's ghost (`TimelineDragPicture.ghost`), back again
// when the drag leaves the timeline. Both pictures are the app's, so there is
// only ever one.

@MainActor enum HistoryDragPicture {

    private static var panel: NSPanel?
    /// Moves the panel once a frame, on the display's own beat, so the
    /// picture keeps up with the pointer rather than trailing a timer.
    private static var follow: CADisplayLink?
    /// Where the pointer sits in the picture, from its bottom left.
    private static var grip = CGSize.zero
    private static var hidden = false
    private static let ticker = DisplayTicker()

    /// A tile was pulled: its picture follows the pointer from here.
    ///
    /// The tile is drawn once, into a still picture, the moment it is pulled.
    /// Following the pointer after that only moves a window: nothing is laid
    /// out or drawn again while it is carried.
    static func lift(_ entry: CaptureEntry, store: CaptureStore, height: CGFloat) {
        drop()
        let size = pictureSize(entry, store: store, height: height)
        let tile = CaptureThumbnailView(entry: entry, store: store, fixedHeight: size.height)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            .padding(12)
        let renderer = ImageRenderer(content: tile)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let picture = renderer.cgImage else { return }
        let frame = CGRect(origin: .zero, size: CGSize(width: size.width + 24, height: size.height + 24))
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.contents = picture
        view.layer?.contentsGravity = .resize
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.alphaValue = 0.85
        panel.contentView = view
        grip = CGSize(width: frame.width / 2, height: frame.height / 2)
        hidden = false
        self.panel = panel
        place()
        panel.orderFrontRegardless()
        let link = view.displayLink(target: ticker, selector: #selector(DisplayTicker.tick))
        link.add(to: .main, forMode: .common)
        follow = link
    }

    /// Calls `tick` for the display link, which wants an object to call.
    private final class DisplayTicker: NSObject {
        @objc func tick() { MainActor.assumeIsolated { HistoryDragPicture.tick() } }
    }

    /// The timeline's ghost came up, or went: the picture gives way to it.
    static func give(way: Bool) {
        guard let panel, way != hidden else { return }
        hidden = way
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = way ? 0 : 0.85
        }
    }

    fileprivate static func tick() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return drop() }
        place()
    }

    private static func place() {
        let point = NSEvent.mouseLocation
        panel?.setFrameOrigin(CGPoint(x: point.x - grip.width, y: point.y - grip.height))
    }

    /// Let go of, anywhere: the picture goes with no flourish, as AppKit's
    /// does when a drop is taken.
    static func drop() {
        follow?.invalidate()
        follow = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private static func pictureSize(_ entry: CaptureEntry, store: CaptureStore, height: CGFloat) -> CGSize {
        let pixels = store.thumbnail(for: entry).pixelSize ?? CGSize(width: 16, height: 9)
        let ratio = pixels.height > 0 ? pixels.width / pixels.height : 16.0 / 9
        return CGSize(width: (height * min(max(ratio, 0.5), 3)).rounded(), height: height)
    }
}
