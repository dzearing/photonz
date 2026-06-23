import PhotonzCore
import SwiftUI

/// Lightweight crop overlay over the video preview (phase 13.4). Reuses the crop
/// overlay PATTERNS (dimmed surround, thirds grid, eight resize handles, a
/// movable body) without the image-editor's document coupling: it maps between
/// the video's natural-pixel space (where `VideoCrop` lives) and the displayed,
/// aspect-fit rect on screen. Non-destructive — the region only applies at
/// export.
struct VideoCropOverlay: View {
    let state: VideoEditorState

    private let handleSize: CGFloat = 14
    /// Crop rect (video pixels) captured at the start of the active drag, so
    /// cumulative `DragGesture.translation` maps to an absolute new rect rather
    /// than compounding per frame.
    @State private var dragStartRect: CGRect?

    var body: some View {
        GeometryReader { geo in
            // The video is aspect-fit inside the available space; compute that
            // display rect so pixel↔point mapping is exact.
            let display = Self.displayRect(videoSize: state.naturalSize, in: geo.size)
            if display.width > 1, let crop = state.crop {
                let rectInView = toView(crop.rect, display: display)

                ZStack(alignment: .topLeading) {
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

                    // Crop border + movable body.
                    Rectangle()
                        .strokeBorder(.white, lineWidth: 1.5)
                        .frame(width: rectInView.width, height: rectInView.height)
                        .offset(x: rectInView.minX, y: rectInView.minY)
                        .contentShape(Rectangle())
                        .gesture(moveGesture(display: display))

                    // Eight resize handles.
                    ForEach(ResizeHandle.allCases, id: \.self) { handle in
                        let center = handlePoint(handle, in: rectInView)
                        Circle()
                            .fill(.white)
                            .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 0.5))
                            .frame(width: handleSize, height: handleSize)
                            .position(center)
                            .gesture(resizeGesture(handle, display: display))
                    }
                }
                .allowsHitTesting(true)
            }
        }
    }

    // MARK: - Gestures

    private func moveGesture(display: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStartRect ?? state.crop?.rect
                guard let start else { return }
                if dragStartRect == nil { dragStartRect = start }
                var crop = VideoCrop(rect: start, videoSize: state.naturalSize,
                                     aspect: state.crop?.aspect ?? .free)
                crop.move(by: toPixelsDelta(value.translation, display: display),
                          videoSize: state.naturalSize)
                state.setCropRect(crop.rect)
            }
            .onEnded { _ in dragStartRect = nil }
    }

    private func resizeGesture(_ handle: ResizeHandle, display: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard var crop = state.crop else { return }
                let p = toPixels(value.location, display: display)
                crop.resize(dragging: handle, to: p, videoSize: state.naturalSize)
                state.setCropRect(crop.rect)
            }
    }

    // MARK: - Coordinate mapping (video pixels ↔ view points)

    private func scale(display: CGRect) -> CGFloat {
        guard state.naturalSize.width > 0 else { return 1 }
        return display.width / state.naturalSize.width
    }

    private func toView(_ rect: CGRect, display: CGRect) -> CGRect {
        let s = scale(display: display)
        return CGRect(x: display.minX + rect.minX * s, y: display.minY + rect.minY * s,
                      width: rect.width * s, height: rect.height * s)
    }

    private func toPixels(_ point: CGPoint, display: CGRect) -> CGPoint {
        let s = scale(display: display)
        guard s > 0 else { return .zero }
        return CGPoint(x: (point.x - display.minX) / s, y: (point.y - display.minY) / s)
    }

    private func toPixelsDelta(_ size: CGSize, display: CGRect) -> CGPoint {
        let s = scale(display: display)
        guard s > 0 else { return .zero }
        return CGPoint(x: size.width / s, y: size.height / s)
    }

    private func handlePoint(_ handle: ResizeHandle, in rect: CGRect) -> CGPoint {
        let x = handle.movesMinXPublic ? rect.minX : (handle.movesMaxXPublic ? rect.maxX : rect.midX)
        let y = handle.movesMinYPublic ? rect.minY : (handle.movesMaxYPublic ? rect.maxY : rect.midY)
        return CGPoint(x: x, y: y)
    }

    /// The aspect-fit rect the video occupies inside `size`.
    static func displayRect(videoSize: CGSize, in size: CGSize) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0 else { return .zero }
        let fit = Geometry.aspectFit(videoSize, in: size)
        return CGRect(x: (size.width - fit.width) / 2, y: (size.height - fit.height) / 2,
                      width: fit.width, height: fit.height)
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
