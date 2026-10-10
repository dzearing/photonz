import PhotonzCore
import SwiftUI

/// **Zoom**: the zooms picked on a recording's Zoom lane, as label and value
/// rows (`ClipZoom.swift`, `EditorState+Zoom`). With several picked each row
/// shows what they share, Mixed where they differ, and a change reaches all
/// of them in one undo step.
///
/// How far in, whether it follows the pointer, and how long its way in and out
/// take. Where it is on the picture is its box on the canvas, and when it runs
/// is its bar on the lane: both are moved by hand there, not typed here.
struct ZoomInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let refs = editorState.pickedZooms
            if !refs.isEmpty, editorState.zoomInHand != nil {
                let reading = editorState.pickedZoomsReading
                scale(refs, reading)
                follow(refs, reading)
                ease(refs, now: reading.easeInMS, easeIn: true)
                ease(refs, now: reading.easeOutMS, easeIn: false)
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The stops a dropdown offers, with the value now among them.
    private static func stops(_ stops: [Int], now: Int?) -> [Int] {
        Array(Set(stops + (now.map { [$0] } ?? []))).sorted()
    }

    private func scale(_ refs: Set<ClipZoomRef>, _ reading: ClipZoomsReading) -> some View {
        let now = reading.scalePercent
        return VideoKit.DropdownRow(
            label: "Zoom", value: now.map { "\($0)%" } ?? MixedValue.text,
            choices: .picking(Self.stops(EditorState.zoomScaleStops, now: now), current: now,
                              title: { "\($0)%" }, isEnabled: { _ in true }) { percent in
                editorState.setZoomScale(refs, percent: percent)
            })
        .playtestField("Zoom amount")
        .panelHelp("How far in. Drag a corner of the box on the picture to set any amount.")
    }

    private func follow(_ refs: Set<ClipZoomRef>, _ reading: ClipZoomsReading) -> some View {
        let can = editorState.canFollowCursor(refs)
        let isMixed = reading.followsCursor == nil
        return VideoKit.FieldRow(label: "Follow Cursor") {
            HStack(spacing: 6) {
                if isMixed { MixedWord().fixedSize() }
                Toggle("Follow Cursor", isOn: Binding(get: { reading.followsCursor == true },
                                                      set: { editorState.setZoomFollowsCursor(refs, $0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .disabled(!can)
                    .opacity(isMixed ? MixedLook.controlOpacity : 1)
                    .playtestControl("Follow Cursor", detail: "the Zoom section")
            }
        }
        .playtestField("Follow Cursor")
        .panelHelp(can ? "The box rides along with the pointer, keeping it in view."
                       : "This recording did not keep where the pointer went.")
    }

    @ViewBuilder
    private func ease(_ refs: Set<ClipZoomRef>, now: Int?, easeIn: Bool) -> some View {
        let value = now.map(EditorState.easeTitle) ?? MixedValue.text
        if easeIn {
            VideoKit.DropdownRow(label: "Ease In", value: value,
                                 choices: easeChoices(refs, now: now, easeIn: true))
                .playtestField("Ease In")
                .panelHelp("How long the zoom takes to arrive.")
        } else {
            VideoKit.DropdownRow(label: "Ease Out", value: value,
                                 choices: easeChoices(refs, now: now, easeIn: false))
                .playtestField("Ease Out")
                .panelHelp("How long it takes to leave.")
        }
    }

    private func easeChoices(_ refs: Set<ClipZoomRef>, now: Int?, easeIn: Bool) -> [VideoKit.Choice] {
        .picking(Self.stops(EditorState.zoomEaseStops, now: now), current: now,
                 title: EditorState.easeTitle, isEnabled: { _ in true }) { ms in
            editorState.setZoomEase(refs, easeIn: easeIn, ms: ms)
        }
    }
}
