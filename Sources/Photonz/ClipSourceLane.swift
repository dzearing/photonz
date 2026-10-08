import PhotonzCore
import SwiftUI

/// **Source**: the lane under a picked clip whose speed is not 100%, holding a
/// striped ghost of how long the clip was before (`ClipSourceGhost`,
/// `docs/design/mocks/pages/video-speed.html` `.srclane` and `.srcbar`).
///
/// The mock pairs a Source row with the Retimed one so the before and after
/// read at a glance. It opens under the clip, the way the Zoom and key lanes
/// do, so picking a clip never moves it under the pointer. It is a view of the
/// clip and nothing to edit: it takes no press and no drop, and a click on it
/// lands on whatever is behind, as it would on the gap between two tracks.
struct ClipSourceLane: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let laneWidth: CGFloat
    var indent: CGFloat = 0

    /// `.lane.srclane { height: 18px }` with its 16 point bar.
    static let height: CGFloat = 18
    static let barHeight: CGFloat = 16
    /// `.srcbar { border-radius: var(--r1) }`.
    static let cornerRadius: CGFloat = 6

    /// "Source" in the gutter, with the mock's picture mark.
    static func header(indent: CGFloat) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "photo").font(.system(size: 9, weight: .semibold))
            Text("Source").font(.system(size: 10, weight: .semibold)).kerning(0.2)
        }
        .foregroundStyle(VideoKit.Palette.dim)
        .padding(.leading, indent + 12)
        .frame(width: TimelineDock.gutter, alignment: .leading)
    }

    var body: some View {
        if let ghost = editorState.clipSourceGhost(for: layerID) {
            HStack(spacing: TimelineDock.gap) {
                Self.header(indent: indent)
                bar(ghost)
            }
            .frame(height: Self.height)
            .allowsHitTesting(false)
            .playtestField("Source lane")
        }
    }

    private func bar(_ ghost: ClipSourceGhost) -> some View {
        let ruler = editorState.motionStripRuler
        let x0 = laneWidth * ruler.fraction(ofMS: Double(ghost.startMS))
        let x1 = laneWidth * ruler.fraction(ofMS: Double(ghost.endMS))
        return TimelineEmptySlot(cornerRadius: Self.cornerRadius, readout: "source ghost")
            .frame(width: max(3, x1 - x0), height: Self.barHeight)
            .offset(x: x0)
            .frame(width: laneWidth, height: Self.height, alignment: .leading)
            .clipped()
    }
}
