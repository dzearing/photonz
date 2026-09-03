import AppKit
import PhotonzCore

/// The pointers the canvas puts on screen for its handles, and a name for each
/// one so a playtest can read what a person would be looking at.
///
/// Resize uses the platform's own frame-resize pointers, so the arrows around a
/// selected layer look exactly like the ones around a window or a table column
/// and no drawing of ours can drift from them. Rotate has no system pointer, so
/// it is drawn here in the same halo style as the selection crosshair.
@MainActor
enum CanvasCursor {

    /// The pointer for `cue`. `transform` is the selected layer's, so a turned
    /// or mirrored layer gets the arrows that match where its handle SITS
    /// rather than what the model calls it.
    static func cursor(for cue: CanvasPointerCue, transform: LayerTransform) -> NSCursor {
        switch cue {
        case .grab: .openHand
        case .rotate: rotate
        case .resize(let handle): resize(Handles.screenHandle(for: handle, transform: transform))
        }
    }

    // MARK: Resize

    private static var resizeCache: [ResizeHandle: NSCursor] = [:]

    /// The system's frame-resize pointer for a corner or edge. Cached because
    /// the pointer is re-read on every mouse move and only a CHANGE may touch
    /// `NSCursor`; a fresh instance each time would flicker.
    ///
    /// Opposite handles come back as the SAME object — one picture serves the
    /// top and the bottom — so the name registered here is the axis, not the
    /// handle, and the two entries agree instead of overwriting each other.
    private static func resize(_ handle: ResizeHandle) -> NSCursor {
        if let hit = resizeCache[handle] { return hit }
        let built = NSCursor.frameResize(position: position(handle), directions: .all)
        resizeCache[handle] = built
        register(built, as: "resize-" + handle.axis.rawValue)
        return built
    }

    private static func position(_ handle: ResizeHandle) -> NSCursor.FrameResizePosition {
        switch handle {
        case .topLeft: .topLeft
        case .top: .top
        case .topRight: .topRight
        case .left: .left
        case .right: .right
        case .bottomLeft: .bottomLeft
        case .bottom: .bottom
        case .bottomRight: .bottomRight
        }
    }

    // MARK: Rotate

    private static var rotateCache: NSCursor?

    /// A curved arrow over the top, arrowheads at both ends: the shape every
    /// design tool uses for "this turns". Drawn black on a white halo so it
    /// reads on a light screenshot and on a dark canvas alike.
    private static var rotate: NSCursor {
        if let hit = rotateCache { return hit }
        let built = buildRotate()
        rotateCache = built
        register(built, as: "rotate")
        return built
    }

    private static func buildRotate() -> NSCursor {
        let side: CGFloat = 26
        let center = NSPoint(x: side / 2, y: side / 2 - 1)
        let radius: CGFloat = 6.5
        let startAngle: CGFloat = 15, endAngle: CGFloat = 165
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            /// The arrowhead at one end of the arc, its point carrying on the
            /// way the arc was going. `grow` fattens it for the halo pass.
            func head(at degrees: CGFloat, forward: Bool, _ color: NSColor, _ grow: CGFloat) {
                let radians = degrees * .pi / 180
                let onArc = NSPoint(x: center.x + cos(radians) * radius,
                                    y: center.y + sin(radians) * radius)
                let sign: CGFloat = forward ? 1 : -1
                let dx = -sin(radians) * sign, dy = cos(radians) * sign
                let reach: CGFloat = 4 + grow, half: CGFloat = 2.6 + grow
                let path = NSBezierPath()
                path.move(to: NSPoint(x: onArc.x + dx * reach, y: onArc.y + dy * reach))
                path.line(to: NSPoint(x: onArc.x - dy * half, y: onArc.y + dx * half))
                path.line(to: NSPoint(x: onArc.x + dy * half, y: onArc.y - dx * half))
                path.close()
                color.setFill()
                path.fill()
            }
            func arc(_ color: NSColor, _ width: CGFloat) {
                let path = NSBezierPath()
                path.appendArc(withCenter: center, radius: radius,
                               startAngle: startAngle, endAngle: endAngle)
                path.lineWidth = width
                path.lineCapStyle = .round
                color.setStroke()
                path.stroke()
            }
            // Dark outline first, white mark over it: the same polarity the
            // platform's resize pointers use, so a canvas full of handles
            // reads as one family, and it carries on a light screenshot and
            // on the dark canvas alike.
            arc(.black, 4.6)
            head(at: startAngle, forward: false, .black, 1.0)
            head(at: endAngle, forward: true, .black, 1.0)
            arc(.white, 2.8)
            head(at: startAngle, forward: false, .white, 0)
            head(at: endAngle, forward: true, .white, 0)
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
    }

    // MARK: Names, for playtests

    private static var names: [ObjectIdentifier: String] = [:]

    /// Records what a drawn or system-built pointer should be called. The stock
    /// pointers are shared singletons a playtest can compare by identity; these
    /// are not, so they say their own name.
    static func register(_ cursor: NSCursor, as name: String) {
        names[ObjectIdentifier(cursor)] = name
    }

    /// The registered name for a pointer, or nil if nothing here made it.
    static func name(of cursor: NSCursor) -> String? {
        names[ObjectIdentifier(cursor)]
    }
}
