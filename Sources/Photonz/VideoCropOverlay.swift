import PhotonzCore
import SwiftUI

/// Crop overlay over the video preview (phase 13.4). Starts empty: the user
/// drags a rectangle around the region to keep (like the image editor's crop
/// tool), then fine-tunes it — handles resize, the body moves, dragging
/// outside draws a fresh rect. All mapping between the video's natural-pixel
/// space (where `VideoCrop` lives) and the screen goes through the preview's
/// `Viewport`, so the overlay stays glued to the video while panning/zooming.
/// Non-destructive — the region only applies at export.
struct VideoCropOverlay: View {
    let state: VideoEditorState

    private let handleSize: CGFloat = 14
    private let handleHitRadius: CGFloat = 12

    /// What the active drag is doing, decided from where it started.
    private enum DragMode {
        /// Drawing a fresh rect from an anchor (video pixels).
        case define(anchor: CGPoint)
        /// Moving the whole rect; the rect as it was at drag start.
        case move(startRect: CGRect)
        /// Dragging one of the eight resize handles.
        case resize(ResizeHandle)
    }
    @State private var dragMode: DragMode?

    var body: some View {
        if let viewport = state.previewViewport, viewport.documentSize.width > 0 {
            let display = viewport.documentFrameInView

            ZStack(alignment: .topLeading) {
                if let crop = state.crop {
                    cropChrome(crop: crop, display: display, viewport: viewport)
                } else {
                    // Nothing chosen yet: dim the frame and invite the drag.
                    Rectangle()
                        .fill(.black.opacity(0.35))
                        .frame(width: display.width, height: display.height)
                        .offset(x: display.minX, y: display.minY)
                    Text("Drag to select the area to keep")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                        .position(x: display.midX, y: display.midY)
                }
            }
            .contentShape(Rectangle())
            .gesture(cropGesture(viewport: viewport))
        }
    }

    /// The dimmed surround, thirds grid, border, and handles for a chosen rect.
    @ViewBuilder
    private func cropChrome(crop: VideoCrop, display: CGRect, viewport: Viewport) -> some View {
        let rectInView = toView(crop.rect, viewport: viewport)

        // Dim everything outside the crop with an even-odd mask.
        Path { p in
            p.addRect(display)
            p.addRect(rectInView)
        }
        .fill(.black.opacity(0.45), style: FillStyle(eoFill: true))

        // Thirds grid inside the crop.
        Path { p in
            for line in Crop.thirdsLines(in: rectInView) {
                p.move(to: line.from)
                p.addLine(to: line.to)
            }
        }
        .stroke(.white.opacity(0.4), lineWidth: 0.5)

        // Crop border.
        Rectangle()
            .strokeBorder(.white, lineWidth: 1.5)
            .frame(width: rectInView.width, height: rectInView.height)
            .offset(x: rectInView.minX, y: rectInView.minY)

        // Eight resize handles.
        ForEach(ResizeHandle.allCases, id: \.self) { handle in
            Circle()
                .fill(.white)
                .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 0.5))
                .frame(width: handleSize, height: handleSize)
                .position(handlePoint(handle, in: rectInView))
        }
    }

    // MARK: - Gesture

    /// One drag drives everything, dispatched by where it starts: a handle
    /// resizes, inside the rect moves, anywhere else draws a fresh rect
    /// (including the very first one).
    private func cropGesture(viewport: Viewport) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let mode = dragMode ?? startMode(at: value.startLocation, viewport: viewport)
                dragMode = mode

                let bounds = CGRect(origin: .zero, size: state.naturalSize)
                let pixels = viewport.documentPoint(fromView: value.location)
                switch mode {
                case .define(let anchor):
                    // Nil while the drag is still empty (a stray click) — keep
                    // whatever rect exists rather than collapsing it.
                    if let rect = Crop.dragRect(anchor: anchor, current: pixels,
                                                aspect: state.cropAspectSelection, bounds: bounds) {
                        state.setCropRect(rect)
                    }
                case .resize(let handle):
                    guard var crop = state.crop else { return }
                    crop.resize(dragging: handle, to: pixels, videoSize: state.naturalSize)
                    state.setCropRect(crop.rect)
                case .move(let startRect):
                    guard viewport.zoom > 0 else { return }
                    var crop = VideoCrop(rect: startRect, videoSize: state.naturalSize,
                                         aspect: state.cropAspectSelection)
                    crop.move(by: CGPoint(x: value.translation.width / viewport.zoom,
                                          y: value.translation.height / viewport.zoom),
                              videoSize: state.naturalSize)
                    state.setCropRect(crop.rect)
                }
            }
            .onEnded { _ in dragMode = nil }
    }

    /// Classify a drag by its start point: handle → resize, inside → move,
    /// outside (or no crop yet) → define, anchored inside the video frame.
    private func startMode(at start: CGPoint, viewport: Viewport) -> DragMode {
        if let crop = state.crop {
            let rectInView = toView(crop.rect, viewport: viewport)
            for handle in ResizeHandle.allCases {
                let center = handlePoint(handle, in: rectInView)
                if hypot(start.x - center.x, start.y - center.y) <= handleHitRadius {
                    return .resize(handle)
                }
            }
            if rectInView.contains(start) { return .move(startRect: crop.rect) }
        }
        let p = viewport.documentPoint(fromView: start)
        let anchor = CGPoint(x: min(max(0, p.x), state.naturalSize.width),
                             y: min(max(0, p.y), state.naturalSize.height))
        return .define(anchor: anchor)
    }

    // MARK: - Mapping helpers

    private func toView(_ rect: CGRect, viewport: Viewport) -> CGRect {
        let origin = viewport.viewPoint(fromDocument: rect.origin)
        return CGRect(x: origin.x, y: origin.y,
                      width: rect.width * viewport.zoom, height: rect.height * viewport.zoom)
    }

    private func handlePoint(_ handle: ResizeHandle, in rect: CGRect) -> CGPoint {
        let x = handle.movesMinXPublic ? rect.minX : (handle.movesMaxXPublic ? rect.maxX : rect.midX)
        let y = handle.movesMinYPublic ? rect.minY : (handle.movesMaxYPublic ? rect.maxY : rect.midY)
        return CGPoint(x: x, y: y)
    }
}

/// `ResizeHandle`'s edge flags are internal to PhotonzCore; expose read-only
/// mirrors for the overlay's handle placement.
private extension ResizeHandle {
    var movesMinXPublic: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesMaxXPublic: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesMinYPublic: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesMaxYPublic: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
}
