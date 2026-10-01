import PhotonzCore
import SwiftUI

/// **Zoom**: the zoom picked on a recording's Zoom lane, as label and value
/// rows (`ClipZoom.swift`, `EditorState+Zoom`).
///
/// How far in, whether it follows the pointer, and how long its way in and out
/// take. Where it is on the picture is its box on the canvas, and when it runs
/// is its bar on the lane: both are moved by hand there, not typed here.
struct ZoomInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let ref = editorState.selectedZoom, let (layer, zoom) = editorState.zoomInHand {
                scale(ref, zoom)
                follow(ref, zoom, clip: layer.id)
                ease(ref, zoom, easeIn: true)
                ease(ref, zoom, easeIn: false)
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scale(_ ref: ClipZoomRef, _ zoom: ClipZoom) -> some View {
        let now = EditorState.zoomPercent(zoom)
        let stops = Array(Set(EditorState.zoomScaleStops + [now])).sorted()
        return VideoKit.DropdownRow(
            label: "Zoom", value: "\(now)%",
            choices: .picking(stops, current: now, title: { "\($0)%" }, isEnabled: { _ in true }) { percent in
                editorState.setZoomScale(ref, percent: percent)
            })
        .playtestField("Zoom amount")
        .panelHelp("How far in. Drag a corner of the box on the picture to set any amount.")
    }

    private func follow(_ ref: ClipZoomRef, _ zoom: ClipZoom, clip: UUID) -> some View {
        let can = zoom.followsCursor || editorState.canFollowCursor(onClip: clip)
        return VideoKit.FieldRow(label: "Follow Cursor") {
            Toggle("Follow Cursor", isOn: Binding(get: { zoom.followsCursor },
                                                  set: { editorState.setZoomFollowsCursor(ref, $0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(!can)
                .playtestControl("Follow Cursor", detail: "the Zoom section")
        }
        .playtestField("Follow Cursor")
        .panelHelp(can ? "The box rides along with the pointer, keeping it in view."
                       : "This recording did not keep where the pointer went.")
    }

    @ViewBuilder
    private func ease(_ ref: ClipZoomRef, _ zoom: ClipZoom, easeIn: Bool) -> some View {
        if easeIn {
            VideoKit.DropdownRow(label: "Ease In", value: EditorState.easeTitle(zoom.easeInMS),
                                 choices: easeChoices(ref, now: zoom.easeInMS, easeIn: true))
                .playtestField("Ease In")
                .panelHelp("How long the zoom takes to arrive.")
        } else {
            VideoKit.DropdownRow(label: "Ease Out", value: EditorState.easeTitle(zoom.easeOutMS),
                                 choices: easeChoices(ref, now: zoom.easeOutMS, easeIn: false))
                .playtestField("Ease Out")
                .panelHelp("How long it takes to leave.")
        }
    }

    private func easeChoices(_ ref: ClipZoomRef, now: Int, easeIn: Bool) -> [VideoKit.Choice] {
        let stops = Array(Set(EditorState.zoomEaseStops + [now])).sorted()
        return .picking(stops, current: now, title: EditorState.easeTitle, isEnabled: { _ in true }) { ms in
            editorState.setZoomEase(ref, easeIn: easeIn, ms: ms)
        }
    }
}
