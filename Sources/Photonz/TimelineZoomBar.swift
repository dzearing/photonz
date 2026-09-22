import PhotonzCore
import SwiftUI

// **Opening the timeline out** (`TimelineZoom.swift`,
// `docs/design/video-surface.md`, the `.tlbar` row).
//
// Two things on screen and they answer two different questions. The CONTROL in
// the timeline's own bar says how far in you are and moves in and out. The
// OVERVIEW above the ruler says where in the whole recording your window is,
// and moves it along.
//
// The overview is only there while the timeline IS opened out. A strip showing
// the whole document has nothing to say about where you are in it, so a bar
// saying "you are looking at all of it" would be a row of chrome telling you
// what you already know by looking.

/// The zoom, in the timeline's own local bar: out, in, what is on screen, and
/// the one press back to the whole thing.
///
/// Steps rather than a slider, deliberately. A five minute recording opens out
/// three hundred times, so a slider from the whole thing to a second of it
/// would spend nine tenths of its travel in the first two seconds of useful
/// range and be unaimable for the rest. Doubling reaches the closest window in
/// eight presses and every press is the same size.
struct TimelineZoomControl: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        HStack(spacing: 5) {
            button("minus.magnifyingglass", name: "Timeline Zoom Out",
                   help: "Show more of the recording",
                   enabled: editorState.canZoomTimelineOut) {
                editorState.zoomTimelineOut()
            }
            button("plus.magnifyingglass", name: "Timeline Zoom In",
                   help: "Open out around the playhead",
                   enabled: editorState.canZoomTimelineIn) {
                editorState.zoomTimelineIn()
            }
            // What is on screen, said as two moments rather than as a
            // percentage: a timeline at 1200% tells you nothing, and "1:00 to
            // 1:30" tells you both how far in you are and where you are.
            Text(editorState.timelineWindowReading)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            Button { editorState.fitTimeline() } label: {
                Text("Fit")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(editorState.isTimelineOpenedOut
                             ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
            .disabled(!editorState.isTimelineOpenedOut)
            .accessibilityLabel("Fit The Timeline")
            .panelHelp("Put the whole recording back across the width")
            .playtestControl("Timeline Fit", detail: "Timing strip")
        }
        // Room between Fit and the × that puts the whole strip away, which is
        // the one misclick on this row that would cost you the timeline.
        .padding(.trailing, 4)
        .panelReadout("timeline \(editorState.timelineWindowReading)")
    }

    private func button(_ symbol: String, name: String, help: String,
                        enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
        .disabled(!enabled)
        .accessibilityLabel(name)
        .panelHelp(help)
        .playtestControl(name, detail: "Timing strip")
    }
}

/// **Where you are in the whole recording**, over the ruler: the document as
/// one thin track, with the stretch you are looking at marked on it.
///
/// It is the answer to the question a zoom creates. The moment the ruler stops
/// measuring the whole document, the numbers along it can say where you are
/// but not how much of the recording is behind and ahead of you, and that is
/// exactly what you need to know to work in one part of a long take.
///
/// It is also how you move: drag the marked stretch and the window goes with
/// it, or press anywhere else on the track and the window jumps there.
struct TimelineOverviewBar: View {
    @Environment(EditorState.self) private var editorState
    let laneWidth: CGFloat

    static let height: CGFloat = 11

    /// How far into the window the hand took hold of it, in milliseconds. Held
    /// for the length of the drag so the window follows the hand exactly
    /// rather than jumping its middle to the pointer on the first move.
    @State private var grabbedAtMS: Double?

    var body: some View {
        let length = editorState.timelineLengthForZoomMS
        let window = editorState.timelineWindow
        let span = window.visibleMS(documentMS: length)
        let x = laneWidth * CGFloat(window.startMS / length)
        let width = max(6, laneWidth * CGFloat(span / length))
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.quaternary.opacity(0.7))
                .frame(height: 5)
            // The playhead, so the window and the moment you are on are read
            // off the same picture.
            Capsule()
                .fill(.secondary)
                .frame(width: 1.5, height: Self.height - 2)
                .offset(x: min(max(0, laneWidth * CGFloat(Double(editorState.documentTimeMS) / length)),
                               laneWidth - 1.5))
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.accentColor.opacity(0.45))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 1)
                }
                .frame(width: width, height: Self.height - 1)
                .offset(x: min(x, laneWidth - width))
        }
        .frame(width: laneWidth, height: Self.height, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(drag(length: length, span: span))
        .accessibilityLabel("Where you are in the recording")
        .panelHelp("Where you are in the whole recording. Drag it to move along.")
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
                    // Taken hold of the window itself: it follows the hand from
                    // wherever on it the hand landed.
                    held = ms - editorState.timelineWindow.startMS
                    grabbedAtMS = held
                } else {
                    // Landed on the track somewhere else: the window jumps
                    // there, centred, and carries on following the hand.
                    held = span / 2
                    grabbedAtMS = held
                }
                let wanted = ms - held
                editorState.panTimeline(byMS: wanted - editorState.timelineWindow.startMS)
            }
            .onEnded { _ in grabbedAtMS = nil }
    }
}

/// A clip that cuts the SIDES of a lane and leaves the top and the bottom
/// alone.
///
/// Both halves matter. Once the timeline is opened out, a clip's bar is wider
/// than the strip and runs off both ends, so without the sides cut it would be
/// drawn straight over the lane names and out past the window. But the strip
/// draws things deliberately outside its lanes — the readout capsule over a
/// drag, the bracket a lag is measured with, the playhead's head — and a plain
/// `.clipped()` would take those with it.
struct TimelineEdgeClip: Shape {
    /// Room left above and below, which nothing on the strip comes near.
    var slack: CGFloat = 400

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - slack,
                    width: rect.width, height: rect.height + slack * 2))
    }
}
