import PhotonzCore
import SwiftUI

/// Where the bottom of the canvas last put its pieces, in canvas view points.
/// Nil when that piece was not up.
struct CanvasFootReading: Equatable {
    var capsule: CGRect?
    var notice: CGRect?
    var captions: [CGRect] = []
}

/// The band just above the floating tool bar, laid out as one thing: the
/// capsule a modal tool puts up (Trim, Crop), the notice pill stacked on top of
/// it, and both kept off the captions on the picture
/// (`EditorChromeLayout.canvasFoot`).
///
/// A view of its own because where the captions sit on screen moves with the
/// zoom and the scroll, and a read of the viewport out in `EditorView` would
/// be a read by the whole editor. The two pieces are built by the editor and
/// handed in; this only measures them and says where they go.
struct CanvasFootStack<Capsule: View, Notice: View>: View {
    @Environment(EditorState.self) private var editorState

    /// The padding everything here starts from: clear of the tool bar and of
    /// the tool settings capsule when one is up.
    let base: CGFloat
    let hasCapsule: Bool
    @ViewBuilder let capsule: () -> Capsule
    @ViewBuilder let notice: () -> Notice

    @State private var canvasSize: CGSize = .zero
    @State private var capsuleSize: CGSize = .zero
    @State private var noticeSize: CGSize = .zero

    var body: some View {
        let captions = captionBoxesOnScreen
        let foot = EditorChromeLayout.canvasFoot(
            canvasSize: canvasSize, base: base,
            capsuleSize: hasCapsule ? capsuleSize : nil,
            noticeSize: noticeSize, keepClear: captions)
        ZStack(alignment: .bottom) {
            notice()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { noticeSize = $0 }
                .padding(.bottom, foot.noticeBottom)
            capsule()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { capsuleSize = $0 }
                .padding(.bottom, foot.capsuleBottom)
        }
        .animation(.spring(duration: 0.25), value: foot)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { canvasSize = $0 }
        .onChange(of: reading(foot, captions: captions), initial: true) { _, now in
            editorState.canvasFootReading = now
        }
    }

    /// The caption boxes, where the picture is drawn right now.
    private var captionBoxesOnScreen: [CGRect] {
        guard let viewport = editorState.viewport,
              let boxes = editorState.document?.captionBoxesOnCanvas, !boxes.isEmpty else { return [] }
        return boxes.map { box in
            let origin = viewport.viewPoint(fromDocument: box.origin)
            return CGRect(x: origin.x, y: origin.y,
                          width: box.width * viewport.zoom, height: box.height * viewport.zoom)
        }
    }

    private func reading(_ foot: EditorChromeLayout.CanvasFoot, captions: [CGRect]) -> CanvasFootReading {
        func placed(_ size: CGSize, bottom: CGFloat) -> CGRect? {
            guard size.width > 0, size.height > 0 else { return nil }
            return CGRect(x: (canvasSize.width - size.width) / 2,
                          y: canvasSize.height - bottom - size.height,
                          width: size.width, height: size.height)
        }
        return CanvasFootReading(
            capsule: hasCapsule ? placed(capsuleSize, bottom: foot.capsuleBottom) : nil,
            notice: placed(noticeSize, bottom: foot.noticeBottom),
            captions: captions)
    }
}
