import PhotonzCore
import SwiftUI

// **The timeline's scrollers** (user 2026-09-28).
//
// Time's scroller runs under the lanes and the rows' scroller down the right
// hand side, each in space the dock keeps for it whether it is showing or not.
// The overview bar they replace sat ABOVE the ruler and only while the
// timeline was opened out, so every zoom that crossed Fit grew the dock and
// pushed the ruler, the transport and the picture: "it causes a horizontal
// zoom scrollbar to appear and disappear. this causes the page to jump".
//
// Both are drawn the way macOS draws an overlay scroller: a thin rounded thumb
// and no track until the pointer is on it.

/// Under the lanes: which stretch of the whole recording is on screen. Drag
/// the thumb to move along; press anywhere else on it to jump there.
struct TimelineTimeScroller: View {
    @Environment(EditorState.self) private var editorState
    let laneWidth: CGFloat

    static let height: CGFloat = 9

    @State private var grabbedAtMS: Double?
    @State private var isHovered = false

    var body: some View {
        let length = editorState.timelineLengthForZoomMS
        let window = editorState.timelineWindow
        let span = window.visibleMS(documentMS: length)
        let showing = editorState.isTimelineOpenedOut
        let x = laneWidth * CGFloat(window.startMS / length)
        let width = max(24, laneWidth * CGFloat(span / length))
        let active = isHovered || grabbedAtMS != nil
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(showing && active ? 0.07 : 0))
            if showing {
                // The playhead, so the window and the moment you are on are
                // read off the same picture.
                Capsule()
                    .fill(VideoKit.Palette.accent.opacity(0.7))
                    .frame(width: 1.5, height: Self.height)
                    .offset(x: min(max(0, laneWidth * CGFloat(Double(editorState.documentTimeMS) / length)),
                                   laneWidth - 1.5))
                Capsule()
                    .fill(Color.primary.opacity(active ? 0.45 : 0.28))
                    .frame(width: width, height: active ? 7 : 5)
                    .offset(x: min(max(0, x), laneWidth - width))
                    .transition(.opacity)
            }
        }
        .frame(width: laneWidth, height: Self.height, alignment: .leading)
        .animation(.easeOut(duration: 0.15), value: showing)
        .animation(.easeOut(duration: 0.12), value: active)
        .contentShape(Rectangle())
        .playtestHover("Timeline overview") { isHovered = $0 }
        .gesture(drag(length: length, span: span), including: showing ? .all : .none)
        .accessibilityLabel("Where you are in the recording")
        .panelHelp(showing ? "Drag to move along the recording" : "")
        .playtestField("Timeline overview")
        .panelReadout("overview \(editorState.timelineWindowReading)")
    }

    private func drag(length: Double, span: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let ms = Double(min(max(0, value.location.x), laneWidth) / max(1, laneWidth)) * length
                let held: Double
                if let grabbedAtMS {
                    held = grabbedAtMS
                } else if editorState.timelineWindow.contains(ms: ms, documentMS: length) {
                    // Taken hold of the thumb itself: it follows the hand from
                    // wherever on it the hand landed.
                    held = ms - editorState.timelineWindow.startMS
                    grabbedAtMS = held
                } else {
                    // Landed somewhere else: the window jumps there, centred,
                    // and carries on following the hand.
                    held = span / 2
                    grabbedAtMS = held
                }
                editorState.panTimeline(byMS: ms - held - editorState.timelineWindow.startMS)
            }
            .onEnded { _ in grabbedAtMS = nil }
    }
}

/// Down the right hand side of the tracks: which of them are on screen, once
/// there are more than fit. Grows the thumb under the pointer like a macOS
/// overlay scroller.
struct TimelineRowsScroller: View {
    @Environment(EditorState.self) private var editorState

    @State private var grabbedAt: CGFloat?
    @State private var isHovered = false

    var body: some View {
        let geometry = editorState.timelineTracksScrollGeometry
        GeometryReader { geo in
            let track = geo.size.height
            let showing = geometry.overflows && track > 0
            let content = max(1, geometry.contentHeight)
            let thumb = max(20, track * min(1, geometry.viewportHeight / content))
            let travel = max(0, geometry.contentHeight - geometry.viewportHeight)
            let share = travel > 0 ? min(max(0, geometry.offsetY / travel), 1) : 0
            let y = (track - thumb) * share
            let active = isHovered || grabbedAt != nil
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.primary.opacity(showing && active ? 0.07 : 0))
                if showing {
                    Capsule()
                        .fill(Color.primary.opacity(active ? 0.45 : 0.28))
                        .frame(width: active ? 7 : 5, height: thumb)
                        .offset(y: y)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: track)
            .animation(.easeOut(duration: 0.15), value: showing)
            .animation(.easeOut(duration: 0.12), value: active)
            .contentShape(Rectangle())
            .playtestHover("Timeline rows scroller") { isHovered = $0 }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let held: CGFloat
                    if let grabbedAt {
                        held = grabbedAt
                    } else if value.startLocation.y >= y, value.startLocation.y <= y + thumb {
                        held = value.startLocation.y - y
                        grabbedAt = held
                    } else {
                        held = thumb / 2
                        grabbedAt = held
                    }
                    let top = min(max(0, value.location.y - held), max(0, track - thumb))
                    let wanted = track > thumb ? top / (track - thumb) * travel : 0
                    editorState.scrollTimelineTracks(toY: wanted)
                }
                .onEnded { _ in grabbedAt = nil },
                including: showing ? .all : .none)
        }
        .accessibilityLabel("Scroll the tracks")
        .playtestField("Timeline rows scroller")
        .panelReadout(String(format: "tracks scrolled %.0f of %.0f", geometry.offsetY,
                             max(0, geometry.contentHeight - geometry.viewportHeight)))
    }
}
