import PhotonzCore
import SwiftUI

/// Custom Liquid-Glass trim scrubber (phase 13.3): a track with draggable in/out
/// handles bracketing the kept window, a dimmed mask over the trimmed-away ends,
/// and a playhead that tracks playback. All time↔x mapping is linear over the
/// full clip duration; the handles drive `VideoEditorState.setTrimIn/out` and a
/// drag on the body scrubs.
struct TrimTimeline: View {
    let state: VideoEditorState

    /// Half-width of a handle's hit/visual area.
    private let handleWidth: CGFloat = 12
    private let trackHeight: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let duration = max(state.duration, 0.0001)
            let inX = x(for: state.trim.inPoint, width: width, duration: duration)
            let outX = x(for: state.trim.outPoint, width: width, duration: duration)
            let playX = x(for: state.currentTime, width: width, duration: duration)

            ZStack(alignment: .topLeading) {
                // Track base.
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.08))

                // Trimmed-away ends, dimmed.
                Rectangle()
                    .fill(.black.opacity(0.35))
                    .frame(width: max(0, inX))
                Rectangle()
                    .fill(.black.opacity(0.35))
                    .frame(width: max(0, width - outX))
                    .offset(x: outX)

                // Kept-window highlight border.
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: max(0, outX - inX))
                    .offset(x: inX)

                // Scrub anywhere in the kept window.
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: max(0, outX - inX))
                    .offset(x: inX)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                state.scrub(to: time(forX: value.location.x + inX,
                                                     width: width, duration: duration))
                            }
                    )

                // Playhead.
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: trackHeight)
                    .shadow(radius: 2)
                    .offset(x: playX - 1.5)
                    .allowsHitTesting(false)

                // In/out handles last so they sit above the mask + scrub area.
                handle(systemImage: "chevron.compact.left", at: inX) { newX in
                    state.setTrimIn(time(forX: newX, width: width, duration: duration))
                }
                handle(systemImage: "chevron.compact.right", at: outX) { newX in
                    state.setTrimOut(time(forX: newX, width: width, duration: duration))
                }
            }
        }
        .frame(height: trackHeight)
    }

    private func handle(systemImage: String, at xPos: CGFloat,
                        onDrag: @escaping (CGFloat) -> Void) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.accentColor)
            .frame(width: handleWidth, height: trackHeight)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(radius: 2)
            .offset(x: xPos - handleWidth / 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in onDrag(value.location.x + xPos - handleWidth / 2) }
            )
            .contentShape(Rectangle())
    }

    private func x(for seconds: TimeInterval, width: CGFloat, duration: TimeInterval) -> CGFloat {
        CGFloat(min(max(0, seconds), duration) / duration) * width
    }

    private func time(forX x: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard width > 0 else { return 0 }
        return TimeInterval(min(max(0, x), width) / width) * duration
    }
}
