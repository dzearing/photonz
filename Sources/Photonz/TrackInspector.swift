import PhotonzCore
import SwiftUI

/// **Track**: a track picked on its header, as `pages/video-audio.html` draws
/// the picked track's strip (`#propBody`): its name beside the title, its
/// switches as the mock's `.btnrow`, and how many clips are on it, which is
/// what ⌫ takes with it.
///
/// The switches are the ones on the track's header, so the two places can
/// never disagree. With several tracks picked the section says how many and
/// how many clips they hold; the switches belong to one track at a time.
struct TrackInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let held = editorState.orderedTracksInHand
            if held.count == 1, let track = editorState.document?.track(id: held[0]) {
                switches(track)
            }
            if !held.isEmpty {
                clips
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the header says beside Track: the track's name, or how many.
    static func headerNote(_ editorState: EditorState) -> String? {
        let held = editorState.orderedTracksInHand
        if held.count > 1 { return "\(held.count) tracks" }
        return held.first.flatMap { editorState.document?.track(id: $0)?.name }
    }

    private func switches(_ track: DocumentTrack) -> some View {
        let isSound = track.kind == .audio
        return HStack(spacing: 8) {
            if isSound {
                ChannelSwitch(title: "Mute",
                              symbol: track.isMuted ? "speaker.slash.fill" : "speaker.wave.2",
                              isOn: track.isMuted, tint: AnyShapeStyle(VideoKit.Palette.crit),
                              help: "Silence this track.", section: "Track") {
                    editorState.toggleTrackMuted(track.id)
                }
            } else {
                ChannelSwitch(title: "Hide", symbol: track.isHidden ? "eye.slash" : "eye",
                              isOn: track.isHidden, tint: AnyShapeStyle(VideoKit.Palette.crit),
                              help: "Take this track off the picture.", section: "Track") {
                    editorState.toggleTrackHidden(track.id)
                }
            }
            ChannelSwitch(title: "Solo", symbol: "headphones", isOn: track.isSolo,
                          tint: AnyShapeStyle(VideoKit.Palette.accent),
                          help: "Play only this track.", section: "Track") {
                editorState.toggleTrackSolo(track.id)
            }
            ChannelSwitch(title: "Lock", symbol: track.isLocked ? "lock.fill" : "lock.open",
                          isOn: track.isLocked, tint: AnyShapeStyle(VideoKit.Palette.accent),
                          help: "Keep everything on this track where it is.", section: "Track") {
                editorState.toggleTrackLocked(track.id)
            }
        }
    }

    /// How many clips are on the picked tracks: what ⌫ takes with them.
    private var clips: some View {
        let going = editorState.goingWithTracksInHand
        let count = going.clips.count + going.sounds.count
        let value = count == 0 ? "None" : "\(count)"
        return VideoKit.FieldRow(label: "Clips") {
            VideoKit.ValueFace(value: value)
                .panelReadout(value)
        }
        .playtestField("Track clips")
    }
}
