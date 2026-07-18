import SwiftUI

/// Standard player scrubber (QuickTime style): a slim neutral track showing
/// playback progress with a prominent white thumb. Click anywhere to jump; drag
/// to scrub. Scrubbing pauses, then playback resumes if it was playing when the
/// drag began. Trim editing lives in `TrimTimeline` (trim mode) — this is purely
/// the playback position line.
struct PlaybackScrubber: View {
    let state: VideoEditorState

    @State private var hovering = false
    @State private var dragging = false
    @State private var wasPlayingBeforeDrag = false

    private let trackHeight: CGFloat = 4
    /// Full-height hit area so the slim track is easy to grab.
    private let hitHeight: CGFloat = 22
    private let thumbSize: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let duration = max(state.duration, 0.0001)
            // The thumb center travels an inset span so it never clips at 0/100%.
            let usable = max(1, geo.size.width - thumbSize)
            let progress = CGFloat(min(max(0, state.currentTime), duration) / duration)
            let thumbX = thumbSize / 2 + progress * usable

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.2))
                    .frame(height: trackHeight)
                // Played portion: neutral (not accent), matching QuickTime.
                Capsule()
                    .fill(.primary.opacity(0.85))
                    .frame(width: max(trackHeight, thumbX), height: trackHeight)
                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .scaleEffect(dragging ? 1.2 : (hovering ? 1.08 : 1))
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

/// Compact volume control: a speaker button (click to mute/unmute) beside a
/// short neutral slider, styled to match the scrubber. Mirrors QuickTime's
/// top-left volume affordance.
struct VolumeControl: View {
    let state: VideoEditorState

    @State private var hovering = false

    private let trackWidth: CGFloat = 56
    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 11

    private var speakerSymbol: String {
        if state.isMuted { return "speaker.slash.fill" }
        if state.volume < 0.34 { return "speaker.fill" }
        if state.volume < 0.67 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }

    var body: some View {
        HStack(spacing: 6) {
            Button { state.toggleMute() } label: {
                Image(systemName: speakerSymbol)
                    .frame(width: 18, alignment: .leading)
            }
            .buttonStyle(IconActionButtonStyle(diameter: 24))
            .help(state.isMuted ? "Unmute" : "Mute")

            GeometryReader { geo in
                let usable = max(1, geo.size.width - thumbSize)
                let progress = CGFloat(min(max(0, state.volume), 1))
                let thumbX = thumbSize / 2 + progress * usable
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.2))
                        .frame(height: trackHeight)
                    Capsule()
                        .fill(.primary.opacity(0.85))
                        .frame(width: max(trackHeight, thumbX), height: trackHeight)
                    Circle()
                        .fill(.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                        .scaleEffect(hovering ? 1.1 : 1)
                        .offset(x: thumbX - thumbSize / 2)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = min(max(0, (value.location.x - thumbSize / 2) / usable), 1)
                            state.setVolume(Double(fraction))
                        }
                )
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
            }
            .frame(width: trackWidth, height: 22)
        }
    }
}
