import SwiftUI

/// Standard player scrubber (QuickTime style): a slim track showing playback
/// progress with a draggable thumb. Click anywhere to jump; drag to scrub.
/// Scrubbing pauses, then playback resumes if it was playing when the drag
/// began. Trim editing lives in `TrimTimeline` (trim mode) — this is purely
/// the playback position line.
struct PlaybackScrubber: View {
    let state: VideoEditorState

    @State private var hovering = false
    @State private var dragging = false
    @State private var wasPlayingBeforeDrag = false

    private let trackHeight: CGFloat = 5
    /// Full-height hit area so the slim track is easy to grab.
    private let hitHeight: CGFloat = 22
    private let thumbSize: CGFloat = 13

    var body: some View {
        GeometryReader { geo in
            let duration = max(state.duration, 0.0001)
            // The thumb center travels an inset span so it never clips at 0/100%.
            let usable = max(1, geo.size.width - thumbSize)
            let progress = CGFloat(min(max(0, state.currentTime), duration) / duration)
            let thumbX = thumbSize / 2 + progress * usable

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.15))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(trackHeight, thumbX), height: trackHeight)
                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .scaleEffect(dragging ? 1.25 : (hovering ? 1.1 : 1))
                    .offset(x: thumbX - thumbSize / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !dragging {
                            dragging = true
                            wasPlayingBeforeDrag = state.isPlaying
                        }
                        let fraction = min(max(0, (value.location.x - thumbSize / 2) / usable), 1)
                        state.scrub(to: TimeInterval(fraction) * duration)
                    }
                    .onEnded { _ in
                        dragging = false
                        if wasPlayingBeforeDrag { state.play() }
                    }
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.12), value: dragging)
        }
        .frame(height: hitHeight)
    }
}
