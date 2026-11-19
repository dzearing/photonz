import AppKit
import PhotonzCore
import QuartzCore
import SwiftUI

// The slide into Edit, run by Core Animation (`ViewEditSlide`). The window is
// laid out as Edit once, at the key. The canvas, the panel, the dock and the
// tool bar each sit in a geometry group, which SwiftUI gives a view of its own
// (an empty marker inside it finds that view); the start of each move is
// handed to that view's layer as an animation, and the render server slides
// it home. SwiftUI never hears about the motion, so the main thread draws
// nothing while it runs.
//
// Driven by SwiftUI (keyframes setting geometry effects, 2026-11-17), every
// frame of the slide was a whole-window SwiftUI render on the main thread:
// 11 to 14ms a frame, 8.5ms even with the effects switched off, and with no
// room to spare at 120Hz the slide's longest still ran 33 to 47ms on a five
// minute captioned recording (2026-11-19).
//
// If a group's view cannot be found, that piece simply lands at once: the
// window is already laid out as Edit, so nothing is ever drawn in the wrong
// place.

/// The pieces that slide.
enum ViewEditSlidePiece: Hashable {
    /// The canvas, scaled and moved back to where View drew the picture.
    case picture
    /// The canvas column, clipped at the panel's moving left edge so the
    /// picture never shows under the panel.
    case canvasClip
    /// The panel, from just off the window's right edge.
    case panel
    /// The dock, from as tall as View had it, its tracks below the window.
    case dock
    /// The tool bar, rising from below and fading in.
    case toolBar
}

extension View {
    /// Gives this piece a view of its own for the slide to move, and marks
    /// it so the slide can find it.
    func viewEditSlideLayer(_ piece: ViewEditSlidePiece) -> some View {
        modifier(ViewEditSlideLayerMark(piece: piece))
    }
}

private struct ViewEditSlideLayerMark: ViewModifier {
    @Environment(EditorState.self) private var editorState
    let piece: ViewEditSlidePiece

    func body(content: Content) -> some View {
        content
            .background {
                if piece == .picture {
                    PictureSlideMarker(layers: editorState.viewEditSlideLayers)
                } else {
                    ViewEditSlideMarker(piece: piece, layers: editorState.viewEditSlideLayers, viewport: nil)
                }
            }
            // The view SwiftUI makes for the group is what Core Animation
            // moves; without it every piece is drawn straight into the window.
            .geometryGroup()
    }
}

/// The canvas's marker, which hears the camera Edit fits the picture to:
/// read only while a slide runs, so a pan or a zoom at any other time does
/// not touch it.
private struct PictureSlideMarker: View {
    @Environment(EditorState.self) private var editorState
    let layers: ViewEditSlideLayers

    var body: some View {
        let to = editorState.viewEditSlide == nil ? nil : editorState.viewport
        ViewEditSlideMarker(piece: .picture, layers: layers, viewport: to)
    }
}

private struct ViewEditSlideMarker: NSViewRepresentable {
    let piece: ViewEditSlidePiece
    let layers: ViewEditSlideLayers
    let viewport: Viewport?

    func makeNSView(context: Context) -> ViewEditSlideMarkerView {
        let view = ViewEditSlideMarkerView(piece: piece, layers: layers)
        layers.register(view)
        return view
    }

    func updateNSView(_ view: ViewEditSlideMarkerView, context: Context) {
        // Updated in the same pass as the canvas draws this camera, so the
        // picture's move starts on the very frame Edit's picture appears.
        if let viewport { layers.pictureFitted(to: viewport) }
    }
}

/// Empty, never hit, never read aloud: it only tells the slide where its
/// piece is and how big it came out.
final class ViewEditSlideMarkerView: NSView {
    let piece: ViewEditSlidePiece
    private weak var layers: ViewEditSlideLayers?

    init(piece: ViewEditSlidePiece, layers: ViewEditSlideLayers) {
        self.piece = piece
        self.layers = layers
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Laid out as Edit in the key's pass, before Core Animation commits
        // it, so a move started here starts on the first frame of Edit.
        layers?.pieceSized(self)
    }

    /// The view SwiftUI made for this piece's group: the marker's own host,
    /// then the group. Nil when there is none and the piece is drawn straight
    /// into the window, which would move the whole window.
    var groupView: NSView? {
        guard let host = superview, let group = host.superview, let window,
              group !== window.contentView, group.superview != nil,
              !String(describing: type(of: group)).contains("HostingView") else { return nil }
        return group
    }
}

/// Runs the slide on the pieces' layers. One per editor window, held by its
/// `EditorState`.
@MainActor
final class ViewEditSlideLayers {
    private struct Weak { weak var view: ViewEditSlideMarkerView? }
    private var markers: [ViewEditSlidePiece: Weak] = [:]

    private struct Run {
        let slide: ViewEditSlide
        let toolBarDrop: CGFloat
        /// The first move added, whose start Core Animation sets when it
        /// commits: every later one starts at the same moment.
        struct First {
            weak var layer: CALayer?
            let key: String
        }
        var first: First?
        var started: Set<ViewEditSlidePiece> = []
        var masked: CALayer?
    }
    private var run: Run?

    private static let key = "photonz.viewEditSlide"

    func register(_ marker: ViewEditSlideMarkerView) {
        markers[marker.piece] = Weak(view: marker)
    }

    /// The key into Edit: everything is about to be laid out as Edit, and
    /// each piece starts back where View had it as soon as its new place is
    /// known.
    func begin(_ slide: ViewEditSlide, toolBarDrop: CGFloat) {
        cancel()
        run = Run(slide: slide, toolBarDrop: toolBarDrop)
    }

    /// The slide has landed: what it added that is not an animation goes.
    func finish() {
        run?.masked?.mask = nil
        run = nil
    }

    /// Another switch while sliding: every piece goes straight to where the
    /// layout has it, for that switch to animate from.
    func cancel() {
        guard let current = run else { return }
        for piece in current.started {
            markers[piece]?.view?.groupView?.layer?.removeAnimation(forKey: Self.key)
            markers[piece]?.view?.groupView?.layer?.removeAnimation(forKey: Self.key + ".opacity")
        }
        current.masked?.mask = nil
        run = nil
    }

    /// A marker laid out at a new size: the panel and the dock learn how far
    /// they have to come from it.
    func pieceSized(_ marker: ViewEditSlideMarkerView) {
        guard let current = run else { return }
        let size = marker.bounds.size
        switch marker.piece {
        case .panel:
            guard size.width > 0, !current.started.contains(.panel) else { return }
            slide(.panel, by: CGSize(width: size.width, height: 0))
            clipCanvas(reach: size.width)
            startToolBar()
        case .dock:
            let drop = current.slide.dockDrop(dockHeight: size.height, progress: 1)
            guard drop > 0, !current.started.contains(.dock) else { return }
            slide(.dock, by: CGSize(width: 0, height: drop))
            startToolBar()
        default:
            return
        }
    }

    /// The canvas has the camera Edit fits the picture to: scale and move it
    /// back to where View drew it.
    func pictureFitted(to viewport: Viewport) {
        guard let current = run, !current.started.contains(.picture),
              viewport.viewSize != current.slide.from.viewSize,
              let marker = markers[.picture]?.view, let group = marker.groupView,
              let layer = group.layer, let superview = group.superview,
              CATransform3DIsIdentity(layer.transform) else { return }
        // The canvas's top-left corner, from the marker that fills it: the
        // group's own frame takes in everything the canvas draws past it.
        let topLeft = superview.convert(CGPoint.zero, from: marker)
        let transform = current.slide.pictureLayerTransform(
            to: viewport, canvasOrigin: topLeft, anchor: layer.position, yDown: superview.isFlipped)
        guard transform != .identity else { return }
        let move = spring("transform")
        move.fromValue = CATransform3DMakeAffineTransform(transform)
        move.toValue = CATransform3DIdentity
        add(move, forKey: Self.key, to: layer, piece: .picture)
        startToolBar()
    }

    private func startToolBar() {
        guard let current = run, !current.started.contains(.toolBar) else { return }
        slide(.toolBar, by: CGSize(width: 0, height: current.toolBarDrop))
        guard let layer = markers[.toolBar]?.view?.groupView?.layer else { return }
        let fade = spring("opacity")
        fade.fromValue = 0
        fade.toValue = 1
        add(fade, forKey: Self.key + ".opacity", to: layer, piece: .toolBar)
    }

    /// Moves a piece's group `offset` points right and down (on screen) and
    /// slides it home.
    private func slide(_ piece: ViewEditSlidePiece, by offset: CGSize) {
        guard let group = markers[piece]?.view?.groupView, let layer = group.layer,
              let superview = group.superview else { return }
        let move = spring("position")
        move.isAdditive = true
        move.fromValue = CGPoint(x: offset.width, y: superview.isFlipped ? offset.height : -offset.height)
        move.toValue = CGPoint.zero
        add(move, forKey: Self.key, to: layer, piece: piece)
    }

    /// The canvas column is drawn no further right than the panel's left
    /// edge as it slides in, so the picture never shows under the panel.
    private func clipCanvas(reach: CGFloat) {
        guard run?.masked == nil, let marker = markers[.canvasClip]?.view, let group = marker.groupView,
              let layer = group.layer, layer.mask == nil else { return }
        // The canvas column in the group's own points: open every way but
        // right, where it stops at the column's edge, the panel's at rest.
        let column = group.convert(marker.bounds, from: marker)
        let far: CGFloat = 4000
        let mask = CALayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.backgroundColor = CGColor(gray: 0, alpha: 1)
        mask.frame = CGRect(x: column.minX - far, y: column.minY - far,
                            width: far + column.width, height: far * 2 + column.height)
        layer.mask = mask
        CATransaction.commit()
        let move = spring("position")
        move.isAdditive = true
        move.fromValue = CGPoint(x: reach, y: 0)
        move.toValue = CGPoint.zero
        add(move, forKey: Self.key, to: mask, piece: .canvasClip)
        run?.masked = layer
    }

    private func add(_ animation: CABasicAnimation, forKey key: String, to layer: CALayer,
                     piece: ViewEditSlidePiece) {
        guard run != nil else { return }
        // Every piece on one clock. The first ones start when Core Animation
        // commits the pass that lays the window out as Edit, which is the
        // first frame anybody sees: begun at the moment they were added, the
        // key's own pass ran a fifth of the slide off before its first frame.
        // A piece started a pass later joins the slide where it has got to.
        if let first = run?.first, let begun = first.layer?.animation(forKey: first.key)?.beginTime, begun > 0 {
            animation.beginTime = layer.convertTime(first.layer?.convertTime(begun, to: nil) ?? begun, from: nil)
        } else if run?.first == nil {
            run?.first = Run.First(layer: layer, key: key)
        }
        layer.add(animation, forKey: key)
        run?.started.insert(piece)
    }

    /// The switch's own curve (`Animation.viewEditMode`), cut at the slide's
    /// length: the last hair of the spring is the layout's resting place.
    private func spring(_ keyPath: String) -> CASpringAnimation {
        let spring = CASpringAnimation(perceptualDuration: ViewEditMode.transitionSeconds, bounce: 0)
        spring.keyPath = keyPath
        spring.duration = ViewEditSlide.seconds
        spring.fillMode = .backwards
        spring.isRemovedOnCompletion = true
        return spring
    }
}

/// While the canvas slides, it draws past its own frame: down under the
/// rising dock, and right as far as the panel's left edge at the start (the
/// moving edge is the slide's mask, `ViewEditSlideLayers.clipCanvas`).
/// Clipped to its frame the rest of the time.
struct ViewEditSlideCanvasClip: ViewModifier {
    @Environment(EditorState.self) private var editorState
    /// How far right of the canvas's frame the panel's left edge starts.
    let panelReach: CGFloat

    func body(content: Content) -> some View {
        content.clipShape(Clip(open: editorState.viewEditSlide != nil, panelReach: panelReach))
    }

    private struct Clip: Shape {
        var open: Bool
        var panelReach: CGFloat

        func path(in rect: CGRect) -> Path {
            guard open else { return Path(rect) }
            let far: CGFloat = 4000
            return Path(CGRect(x: rect.minX - far, y: rect.minY - far,
                               width: far + rect.width + panelReach, height: far * 2 + rect.height))
        }
    }
}

/// The panel's material reaches down under the rising dock while it slides,
/// so no gap opens below it while the dock is still coming up.
struct ViewEditSlidePanelUnder: ViewModifier {
    @Environment(EditorState.self) private var editorState

    func body(content: Content) -> some View {
        content.background(alignment: .bottom) {
            if editorState.viewEditSlide != nil {
                Rectangle().fill(.regularMaterial)
                    .frame(height: Self.reach)
                    .offset(y: Self.reach)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Past the tallest the dock rises.
    private static let reach: CGFloat = 1200
}

