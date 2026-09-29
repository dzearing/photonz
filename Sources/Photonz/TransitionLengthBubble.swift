import SwiftUI
import PhotonzCore

/// The length a transition's band is being dragged to, in a bubble riding
/// beside the pointer (user 2026-09-29: "display the length of the transition
/// while I'm adjusting it"). Drawn as the canvas draws its own drag readout
/// (`CanvasDragReadout`): the same dark plate, type and room round the words,
/// so the app has one voice for "this is about the thing in your hand". When
/// the spare media or the shortest length holds the end back, the plate turns
/// amber and the words say max or min.
struct TransitionLengthBubble: View {
    @Environment(EditorState.self) private var editorState
    /// Where the pointer is across the lane, in the lane's own points.
    let pointerX: CGFloat
    let laneWidth: CGFloat
    let height: CGFloat

    /// How far clear of the pointer the plate sits.
    static let gap: CGFloat = 12

    var body: some View {
        if let session = editorState.clipTransitionDrag, let words = editorState.clipTransitionReadout {
            let atStop = session.stop != nil
            let inset = CanvasNSView.DragReadoutPill.inset
            Text(words)
                .font(Font(CanvasNSView.dragReadoutFont))
                .monospacedDigit()
                .foregroundStyle(atStop ? Color.black : Color.white)
                .padding(.horizontal, inset.width)
                .padding(.vertical, inset.height)
                .background(Capsule().fill(atStop ? AnyShapeStyle(VideoKit.Palette.warn)
                                                  : AnyShapeStyle(Color.black.opacity(0.82))))
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { plateWidth = $0 }
                .offset(x: plateX)
                .frame(width: laneWidth, height: height, alignment: .leading)
                .allowsHitTesting(false)
                .panelReadout("transition length \(words)")
                .playtestField("Transition length")
                .transition(.opacity.animation(.easeOut(duration: 0.18)))
        }
    }

    @State private var plateWidth: CGFloat = 0

    /// To the right of the pointer, or its left when that would run off the
    /// lane's right hand edge.
    private var plateX: CGFloat {
        let right = pointerX + Self.gap
        if right + plateWidth <= laneWidth { return right }
        return max(0, pointerX - Self.gap - plateWidth)
    }
}
