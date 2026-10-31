import PhotonzCore
import SwiftUI

/// What a path's line is painted with, under the Outline row in Appearance
/// (`docs/design/brushes.md`, decision 9; the Stroke group of `draw.html`:
/// Brush, Size, Flow, Color). The Brush dropdown turns the line from a plain
/// stroke into one of the brushes, and the brush's first two own settings sit
/// under it, as they do in the Brush tool's options. The line's Size is the
/// Thickness row and its colour the Outline row's well, so neither is here
/// twice.
///
/// Every line picked takes the choice, so picking several paths and choosing a
/// brush restyles all of their lines in one undo step.
struct PathBrushSettings: View {
    @Environment(EditorState.self) private var editorState
    /// The part row these hang under, so a choice reaches whatever paths are
    /// picked when it is made (`PanelReach`).
    let rowID: String
    let selection: PathLineStyleSelection

    /// What the dropdown calls a line with no brush.
    static let plainTitle = "Plain"

    var body: some View {
        if !selection.isEmpty, selection.hasALine {
            let state = editorState
            let reach = PanelReach.partPathLine(rowID)
            let reading = selection.reading { $0.brush?.medium }
            let value = reading.isMixed ? LayerStyleSelection.mixedText
                : (reading.value.flatMap { $0 }?.title ?? Self.plainTitle)
            let pick: @MainActor (BrushMedium?) -> Void = { medium in
                state.setPathBrush(ids: state.layerIDs(reaching: reach), medium)
            }
            HStack(alignment: .center, spacing: ColorPartLayout.spacing) {
                Text("Brush")
                    .panelRowName()
                    .frame(width: ColorPartLayout.nameWidth, alignment: .leading)
                VideoKit.Dropdown(
                    label: "Brush",
                    value: value,
                    valueStyle: reading.isMixed ? MixedLook.style : nil,
                    help: "Paint the line with a brush. The path stays editable.",
                    choices: [.item(Self.plainTitle, isOn: !reading.isMixed && reading.value.flatMap { $0 } == nil) {
                        pick(nil)
                    }, .divider] + BrushMedium.allCases.map { medium in
                        .item(medium.title, isOn: !reading.isMixed && reading.value.flatMap { $0 } == medium) {
                            pick(medium)
                        }
                    })
                    .frame(maxWidth: .infinity)
                    .panelHelp("Paint the line with a brush. The path stays editable.")
                    .playtestControl("Brush", detail: value)
            }
            .playtestField("Brush")
            // The brush's own settings, once every line picked wears the same one.
            if !reading.isMixed, let medium = reading.value.flatMap({ $0 }) {
                ForEach(medium.toolOptionSettings, id: \.id) { spec in
                    PathBrushSettingRow(spec: spec, reach: reach,
                                        reading: selection.reading { $0.brush?.settings.value(spec.id) ?? spec.defaultValue })
                }
            }
        }
    }
}

/// One of a brushed line's own settings: a slider for a value, the choices
/// side by side for two or three, a dropdown for more
/// (`BrushSettingSpec.control`), the controls the Brush tool shows for it.
struct PathBrushSettingRow: View {
    @Environment(EditorState.self) private var editorState
    let spec: BrushSettingSpec
    let reach: PanelReach
    let reading: StyleReading<Double>

    /// What a walk calls it, apart from the Brush tool's own "Brush <name>".
    private var walkName: String { "Line " + spec.name }

    var body: some View {
        let state = editorState
        let id = spec.id
        switch spec.control {
        case .slider:
            ShapeSlider(reach: reach, isEnabled: true, label: spec.name,
                        reading: StyleReading(value: reading.value.map { CGFloat($0) }, isMixed: reading.isMixed),
                        range: CGFloat(spec.range.lowerBound)...CGFloat(spec.range.upperBound),
                        format: { [spec] in spec.reading(Double($0)) },
                        typing: SliderNumber(suffix: id == "size" ? DocumentUnit.word : "%"),
                        preview: { state.previewPathBrushSetting(ids: $0, id, Double($1)) },
                        commit: { state.commitPathBrushSetting(ids: $0, id, Double($1)) })
                .equatable()
        case .segmented:
            let options = spec.options ?? []
            HStack(alignment: .center, spacing: ColorPartLayout.spacing) {
                Text(spec.name)
                    .panelRowName()
                    .frame(width: ColorPartLayout.nameWidth, alignment: .leading)
                SegmentedControl(walkName, selection: reading.isMixed ? nil : reading.value.map { Int($0.rounded()) },
                                 options: options.enumerated().map { .init($0.offset, $0.element) },
                                 size: .small, form: .fill) { picked in
                    state.commitPathBrushSetting(ids: state.layerIDs(reaching: reach), id, Double(picked))
                }
            }
        case .dropdown:
            let options = spec.options ?? []
            let picked = reading.isMixed ? nil : reading.value.map { Int($0.rounded()) }
            HStack(alignment: .center, spacing: ColorPartLayout.spacing) {
                Text(spec.name)
                    .panelRowName()
                    .frame(width: ColorPartLayout.nameWidth, alignment: .leading)
                VideoKit.Dropdown(
                    label: walkName,
                    value: picked.map { spec.reading(Double($0)) } ?? LayerStyleSelection.mixedText,
                    choices: options.enumerated().map { index, title in
                        .item(title, isOn: index == picked) {
                            state.commitPathBrushSetting(ids: state.layerIDs(reaching: reach), id, Double(index))
                        }
                    })
                    .frame(maxWidth: .infinity)
                    .playtestField(walkName)
            }
        }
    }
}
