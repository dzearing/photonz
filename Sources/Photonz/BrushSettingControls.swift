import PhotonzCore
import SwiftUI

// The brush's settings as controls (Next, `next-brush`; `docs/design/brushes.md`
// decision 7). One control per setting the medium declares
// (`BrushMedium.settings`), so the capsule over the tool bar and the panel's
// Brush section read the same list and write the same armed brush: changing
// either moves both, and the next stroke paints with it.

/// One brush setting's control: a slider and its number for a value, the
/// choices side by side for two or three, a dropdown for more
/// (`BrushSettingSpec.control`).
struct BrushSettingControl: View {
    @Environment(EditorState.self) private var editorState
    let spec: BrushSettingSpec
    /// In the capsule over the tool bar: a short track and a plain number.
    /// In the panel the track takes the row and the number can be typed.
    var inCapsule: Bool

    /// What a walk and accessibility call it: the capsule's "Tool Grain", the
    /// panel's "Brush Grain", apart from a picked layer's own Opacity and
    /// Size rows in the same panel.
    private var walkName: String { (inCapsule ? "Tool " : "Brush ") + spec.name }

    var body: some View {
        let value = editorState.armedBrush.value(spec.id)
        switch spec.control {
        case .slider:
            slider(value)
        case .segmented:
            let options = spec.options ?? []
            SegmentedControl(spec.name, selection: Int(value.rounded()),
                             options: options.enumerated().map { .init($0.offset, $0.element) },
                             size: .small, form: inCapsule ? .natural : .fill) { picked in
                editorState.setArmedBrushSetting(spec.id, to: Double(picked))
            }
            .fixedSize(horizontal: inCapsule, vertical: false)
        case .dropdown:
            let options = spec.options ?? []
            let picked = Int(value.rounded())
            VideoKit.Dropdown(
                label: walkName, value: spec.reading(value), size: .small,
                choices: options.enumerated().map { index, title in
                    .item(title, isOn: index == picked) {
                        editorState.setArmedBrushSetting(spec.id, to: Double(index))
                    }
                })
            .frame(width: inCapsule ? 64 : nil)
            .frame(maxWidth: inCapsule ? nil : .infinity)
            .playtestField(walkName)
        }
    }

    @ViewBuilder private func slider(_ value: Double) -> some View {
        let track = Slider(value: Binding(get: { value },
                                          set: { editorState.setArmedBrushSetting(spec.id, to: $0.rounded()) }),
                           in: spec.range)
            .controlSize(.small)
            .playtestControl("Slider", detail: walkName)
        if inCapsule {
            HStack(spacing: 6) {
                track.frame(width: spec.id == "size" ? 96 : 72)
                Text(spec.reading(value))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: spec.id == "size" ? 40 : 32, alignment: .trailing)
            }
        } else {
            HStack(spacing: 6) {
                track.frame(minWidth: PanelSliderRow.trackMinimum)
                SliderReadout(
                    typing: SliderNumber(suffix: spec.id == "size" ? "pt" : "%"),
                    label: walkName, value: CGFloat(value), isMixed: false,
                    range: CGFloat(spec.range.lowerBound)...CGFloat(spec.range.upperBound),
                    identity: "brush.\(editorState.armedBrush.medium.rawValue).\(spec.id)",
                    land: { editorState.setArmedBrushSetting(spec.id, to: Double($0).rounded()) })
            }
        }
    }
}
