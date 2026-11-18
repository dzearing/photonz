import PhotonzCore
import SwiftUI

// The slide into Edit drawn as layers (`ViewEditSlide`): the window is laid
// out as Edit once, at the key, and these move the canvas, the panel and the
// dock back to where View had them and slide them home. Each is a geometry
// effect, so a frame of the slide moves what is already drawn and lays
// nothing out: animating the panel's width and the dock's height re-laid out
// the whole window on every frame (18 to 25ms a frame, against about 9 this
// way), and on a five minute captioned recording left the slide's first
// frames sitting still for 35 to 49ms (2026-11-17).
//
// Each runs its own keyframes, set off by the same count in the same pass,
// so all of them are at the same point of the slide in every frame. Keyframes
// rather than an animated value because they start in the pass that lays the
// window out as Edit: a value sent home a pass later left the first moving
// frame waiting behind that pass, a 40ms still at the start of the slide.

extension View {
    /// `moved` applied with how far the slide still has to go: 1 where View
    /// had everything, 0 home, and 0 whenever nothing slides.
    func viewEditSlide<Moved: View>(
        run: Int, @ViewBuilder _ moved: @escaping @Sendable (PlaceholderContentView<Self>, CGFloat) -> Moved
    ) -> some View {
        keyframeAnimator(initialValue: CGFloat(0), trigger: run, content: moved) { _ in
            MoveKeyframe(1)
            SpringKeyframe(0, duration: ViewEditSlide.seconds,
                           spring: .smooth(duration: ViewEditMode.transitionSeconds))
            // The spring stops a hair short of home when its time is up: 0.4%
            // of the panel's width left it a point off the window's edge.
            LinearKeyframe(0, duration: 0.001)
        }
    }
}

/// The canvas, scaled and moved so the picture Edit draws starts where View
/// drew it.
struct ViewEditSlideCanvasMove: ViewModifier {
    @Environment(EditorState.self) private var editorState

    func body(content: Content) -> some View {
        let slide = editorState.viewEditSlide
        // The camera is read only while sliding, so a pan or a zoom at any
        // other time does not run this again.
        let to = slide == nil ? nil : editorState.viewport
        content.viewEditSlide(run: editorState.viewEditSlideRun) { content, progress in
            content.modifier(PictureMove(slide: slide, to: to, progress: progress))
        }
    }

    private struct PictureMove: GeometryEffect {
        let slide: ViewEditSlide?
        let to: Viewport?
        var progress: CGFloat
        var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }

        func effectValue(size: CGSize) -> ProjectionTransform {
            guard let slide, let to else { return ProjectionTransform() }
            // A camera not yet fitted to the canvas's new size draws the
            // picture where View had it already.
            guard abs(to.viewSize.width - size.width) < 1, abs(to.viewSize.height - size.height) < 1 else {
                return ProjectionTransform()
            }
            return ProjectionTransform(slide.pictureMove(to: to, progress: progress))
        }
    }
}

/// While the canvas is slid back to where View had it, it draws past its own
/// frame: down under the rising dock, and right as far as the panel's left
/// edge as it slides in, never under the panel, so the panel shows over the
/// window exactly as it does at rest. Clipped to its frame the rest of the
/// time.
struct ViewEditSlideCanvasClip: ViewModifier {
    @Environment(EditorState.self) private var editorState
    /// How far right of the canvas's frame the panel's left edge starts.
    let panelReach: CGFloat

    func body(content: Content) -> some View {
        let open = editorState.viewEditSlide != nil
        content.viewEditSlide(run: editorState.viewEditSlideRun) { [panelReach] content, progress in
            content.clipShape(Clip(open: open, panelReach: panelReach, progress: progress))
        }
    }

    private struct Clip: Shape {
        var open: Bool
        var panelReach: CGFloat
        var progress: CGFloat

        func path(in rect: CGRect) -> Path {
            guard open else { return Path(rect) }
            let far: CGFloat = 4000
            return Path(CGRect(x: rect.minX - far, y: rect.minY - far,
                               width: far + rect.width
                                   + ViewEditSlide.panelShift(width: panelReach, progress: progress),
                               height: far * 2 + rect.height))
        }
    }
}

/// The panel, drawn off the window's right edge and slid in. On a container
/// that is always there, so a panel put in by the switch itself slides too.
struct ViewEditSlidePanelShift: ViewModifier {
    @Environment(EditorState.self) private var editorState

    func body(content: Content) -> some View {
        let sliding = editorState.viewEditSlide != nil
        content
            // The panel's material reaches down under the rising dock, so no
            // gap opens below it while the dock is still coming up.
            .background(alignment: .bottom) {
                if sliding {
                    Rectangle().fill(.regularMaterial)
                        .frame(height: Self.reach)
                        .offset(y: Self.reach)
                        .allowsHitTesting(false)
                }
            }
            .viewEditSlide(run: editorState.viewEditSlideRun) { content, progress in
                content.modifier(Shift(progress: sliding ? progress : 0))
            }
    }

    /// How far below its foot the panel's material reaches while it slides:
    /// past the tallest the dock rises.
    private static let reach: CGFloat = 1200

    private struct Shift: GeometryEffect {
        var progress: CGFloat
        var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }

        func effectValue(size: CGSize) -> ProjectionTransform {
            ProjectionTransform(CGAffineTransform(
                translationX: ViewEditSlide.panelShift(width: size.width, progress: progress), y: 0))
        }
    }
}

/// The dock, drawn as tall as View had it (its tracks below the window's
/// foot) and risen.
struct ViewEditSlideDockDrop: ViewModifier {
    @Environment(EditorState.self) private var editorState

    func body(content: Content) -> some View {
        let slide = editorState.viewEditSlide
        content.viewEditSlide(run: editorState.viewEditSlideRun) { content, progress in
            content.modifier(Drop(slide: slide, progress: progress))
        }
    }

    private struct Drop: GeometryEffect {
        let slide: ViewEditSlide?
        var progress: CGFloat
        var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }

        func effectValue(size: CGSize) -> ProjectionTransform {
            guard let slide else { return ProjectionTransform() }
            return ProjectionTransform(CGAffineTransform(
                translationX: 0, y: slide.dockDrop(dockHeight: size.height, progress: progress)))
        }
    }
}
