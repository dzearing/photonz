import PhotonzCore
import SwiftUI

/// **Clicks**: the rows on a recording's Properties that draw an effect at
/// every click (`ClickEffect.swift`, `EditorState+ClickEffects`).
///
/// One switch, then while it is on the look (Ripple, Pulse, Spotlight), its
/// colour and its size: Screen Studio's click settings, as label and value
/// rows. A recording that kept no clicks has the switch dimmed, and its tip
/// says how to add one.
struct ClickEffectRows: View {
    @Environment(EditorState.self) private var editorState
    let clipID: UUID

    var body: some View {
        let effect = editorState.clickEffect(ofClip: clipID)
        let reason = editorState.clickEffectUnavailableReason(onClip: clipID)
        let on = effect.isOn && reason == nil
        VStack(alignment: .leading, spacing: 4) {
            VideoKit.FieldRow(label: "Clicks") {
                Toggle("Clicks", isOn: Binding(get: { on },
                                               set: { editorState.setClickEffectOn($0, onClip: clipID) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .disabled(reason != nil)
                    .playtestControl("Clicks", detail: on ? "on" : "off")
            }
            .playtestField("Clicks")
            .panelHelp(reason ?? "Show an effect at every click in the recording")
            if on {
                VideoKit.DropdownRow(
                    label: "Style", value: effect.style.title,
                    choices: .picking(ClickEffectStyle.allCases, current: effect.style, title: \.title) { style in
                        editorState.changeClickEffect(onClip: clipID) { $0.style = style }
                    })
                .playtestField("Click Style")
                .panelHelp("How each click looks")
                if effect.style.takesAColour {
                    VideoKit.FieldRow(label: "Color") {
                        ColorWellButton(hex: effect.colorHex, name: "Clicks", wellKey: "clicks") { hex in
                            editorState.changeClickEffect(onClip: clipID) { $0.colorHex = hex }
                            editorState.recordRecentColor(hex: hex)
                        }
                    }
                    .playtestField("Click Color")
                }
                VideoKit.FieldRow(label: "Size") {
                    SegmentedControl("Click Size", selection: effect.size,
                                     options: ClickEffectSize.allCases.map { .init($0, $0.title) },
                                     size: .small, fallsBackToSystem: false) { size in
                        editorState.changeClickEffect(onClip: clipID) { $0.size = size }
                    }
                }
                .playtestField("Click Size")
            }
            Rectangle()
                .fill(VideoKit.Palette.line)
                .frame(height: 1)
                .padding(.top, 4)
                .padding(.bottom, 4)
        }
    }
}
