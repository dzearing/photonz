import AppKit
import PhotonzCore
import SwiftUI

/// The picked zoom's box on the picture (`EditorState+Zoom`).
///
/// While a zoom is picked and nothing is playing, the canvas shows the whole
/// recording and this box over the part the zoom fills the frame with, the
/// rest of the picture dimmed. Carry the box to move it, pull a corner to
/// resize it, or press beside it and drag to draw it again. It always keeps the
/// frame's shape, because any other shape would stretch the picture. A click
/// beside it without a drag lets the zoom go, the way a click off a crop does,
/// and so does Escape. While the box is up it is the only frame on the
/// picture: the clip's own outline and handles step aside (`CanvasNSView`).
///
/// Drawn over the canvas in its own view coordinates; the presses are the
/// canvas view's, which hands a press on the clip to the box before any tool
/// sees it (`EditorState.zoomBoxDown`).
struct ZoomBoxOverlay: View {
    @Environment(EditorState.self) private var editorState

    private static let handle: CGFloat = 8

    var body: some View {
        if let viewport = editorState.viewport,
           let box = editorState.zoomBoxInDocument,
           let frame = editorState.zoomClipFrameInDocument,
           let zoom = editorState.zoomInHand?.zoom {
            let viewBox = rect(box, in: viewport)
            let viewFrame = rect(frame, in: viewport)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    var dim = Path(viewFrame)
                    dim.addRect(viewBox)
                    context.fill(dim, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
                    // A dark rule under a light one, so the edge reads over
                    // any picture.
                    context.stroke(Path(viewBox), with: .color(.black.opacity(0.5)), lineWidth: 3)
                    context.stroke(Path(viewBox), with: .color(.white), lineWidth: 1.5)
                    for corner in Self.corners(of: viewBox) {
                        let square = CGRect(x: corner.x - Self.handle / 2, y: corner.y - Self.handle / 2,
                                            width: Self.handle, height: Self.handle)
                        context.fill(Path(square), with: .color(.white))
                        context.stroke(Path(square), with: .color(.black.opacity(0.6)), lineWidth: 1)
                    }
                }
                .allowsHitTesting(false)
                Text(ZoomLane.label(zoom))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.7)))
                    .offset(x: viewBox.minX + 6, y: viewBox.minY + 6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
            .playtestControl("Zoom box", detail: "Canvas")
        }
    }

    private func rect(_ r: CGRect, in viewport: Viewport) -> CGRect {
        let a = viewport.viewPoint(fromDocument: CGPoint(x: r.minX, y: r.minY))
        let b = viewport.viewPoint(fromDocument: CGPoint(x: r.maxX, y: r.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private static func corners(of r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }
}
