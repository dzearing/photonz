import AppKit
import PhotonzCore
import SwiftUI

// The camera's keys on a thin row at the top of the timeline
// (`show-the-camera-s-keys-on-a-thin-row-at-the-top`).
//
// `video-depth.html`, "Camera A · a setting of the frame": "Keyed camera moves
// show on a thin row at the top of the timeline." The camera is not a layer,
// so this is not a track: it has no clip, no switches and no place in the
// track order. It comes in once a camera value is keyed and goes with the last
// key. Its diamonds are moments (`CameraRow.swift`): a click picks the frame
// and goes to the key, a drag retimes every camera key there, and a right
// click or ⌫ deletes them, each one undo step.

struct TimelineCameraRow: View {
    @Environment(EditorState.self) private var editorState
    let laneWidth: CGFloat

    /// As thin as a key lane under a track (`KeyLanesView.laneHeight`).
    static let height: CGFloat = KeyLanesView.laneHeight
    /// How near the playhead a dragged diamond lands on it, as a key's does.
    private static let keySnap: CGFloat = 6

    var body: some View {
        HStack(spacing: TimelineDock.gap) {
            label
            lane
        }
        .frame(height: Self.height)
        .playtestField("Camera row")
    }

    // MARK: The name in the gutter

    private var label: some View {
        Button {
            editorState.pickCameraRow()
        } label: {
            VideoKit.TrackHeader(title: "Camera", symbol: "camera", width: TimelineDock.gutter,
                                 uppercase: false, isSelected: editorState.showsCameraSection)
                .frame(height: Self.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Camera keys")
        .playtestControl("Camera row", detail: "Timeline")
    }

    // MARK: The lane

    private var lane: some View {
        let ruler = editorState.motionStripRuler
        let moments = editorState.cameraKeyMoments
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(VideoKit.Palette.panel2)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(
                    editorState.showsCameraSection ? AnyShapeStyle(VideoKit.Palette.accent.opacity(0.6))
                                                    : AnyShapeStyle(VideoKit.Palette.line),
                    lineWidth: 1))
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { editorState.pickCameraRow() }
                .contextMenu {
                    MenuRowsView(rows: [.command("Show Camera Settings") { editorState.pickCameraRow() }])
                }
            segment(moments, ruler: ruler)
            ForEach(Array(moments.enumerated()), id: \.element.ms) { index, moment in
                diamond(moment, index: index, ruler: ruler)
            }
        }
        .frame(width: laneWidth, height: Self.height, alignment: .topLeading)
        .clipShape(TimelineEdgeClip())
        .panelReadout("camera row: \(moments.count) key\(moments.count == 1 ? "" : "s") at "
                      + moments.map { MotionStripRuler.timecode(Double($0.ms)) }.joined(separator: ", "))
    }

    private func x(_ ms: Int, _ ruler: MotionStripRuler) -> CGFloat {
        laneWidth * ruler.fraction(ofMS: Double(ms))
    }

    /// Where a diamond is drawn: carried by the drag in the air.
    private func shownMS(_ moment: CameraKeyMoment) -> Int {
        guard let drag = editorState.cameraKeyDrag, abs(drag.fromMS - moment.ms) <= PropertyKeys.nearMS
        else { return moment.ms }
        return min(max(0, moment.ms + drag.byMS), editorState.document?.documentDurationMS ?? moment.ms)
    }

    /// The faint accent line from the first key to the last, as a key lane
    /// draws it (`.kfseg`), so the stretch where the camera moves reads at a
    /// glance.
    private func segment(_ moments: [CameraKeyMoment], ruler: MotionStripRuler) -> some View {
        let spots = moments.map { x(shownMS($0), ruler) }.sorted()
        return Canvas { context, size in
            guard spots.count > 1, let first = spots.first, let last = spots.last else { return }
            let rect = CGRect(x: first, y: size.height / 2 - 1, width: last - first, height: 2)
            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.accentColor.opacity(0.45)))
        }
        .allowsHitTesting(false)
    }

    private func diamond(_ moment: CameraKeyMoment, index: Int, ruler: MotionStripRuler) -> some View {
        let isPicked = editorState.isCameraKeyPicked(moment.ms)
        let dragging = editorState.cameraKeyDrag.map { abs($0.fromMS - moment.ms) <= PropertyKeys.nearMS } ?? false
        let at = x(shownMS(moment), ruler)
        let grab: CGFloat = 14
        let time = MotionStripRuler.timecode(Double(moment.ms))
        return KeyGlyph(ease: .linear, isPicked: isPicked)
            .scaleEffect(dragging ? 1.25 : 1)
            .frame(width: grab, height: grab)
            .contentShape(Rectangle())
            .gesture(drag(moment, ruler: ruler))
            .onTapGesture { editorState.pickCameraKey(atMS: moment.ms) }
            .contextMenu { MenuRowsView(rows: editorState.cameraKeyMenuRows(atMS: moment.ms)) }
            .help("\(moment.reading) at \(time)")
            .playtestControl("Camera key \(index + 1)", detail: "Timeline")
            .panelReadout("camera key \(index + 1): \(moment.reading) at \(time)" + (isPicked ? ", picked" : ""))
            // Placed by padding, so the diamond's frame is where it is drawn
            // and a right click lands on it.
            .padding(.leading, max(0, at - grab / 2))
            .padding(.top, max(0, Self.height / 2 - grab / 2))
    }

    private func drag(_ moment: CameraKeyMoment, ruler: MotionStripRuler) -> some Gesture {
        // Read in a space that does not move with the diamond
        // (`ClipPiecesBar.handSpace`).
        DragGesture(minimumDistance: 2, coordinateSpace: ClipPiecesBar.handSpace)
            .onChanged { value in
                if editorState.cameraKeyDrag == nil { editorState.beginCameraKeyDrag(fromMS: moment.ms) }
                var moved = Int(ruler.msSpanning(fraction: Double(value.translation.width / laneWidth)).rounded())
                // It lands on the playhead as it comes near, the way a key does.
                let playhead = editorState.documentTimeMS
                if laneWidth * ruler.fraction(spanningMS: Double(abs(moment.ms + moved - playhead))) <= Self.keySnap {
                    moved = playhead - moment.ms
                }
                editorState.updateCameraKeyDrag(byMS: moved)
            }
            .onEnded { _ in editorState.commitCameraKeyDrag() }
    }
}
