import PhotonzCore
import SwiftUI

/// The five rows a Color Grade's section holds, in Lumetri's order: the white
/// balance, then the light, then the colour. One list, read by the Effects
/// list and by a saved grade's own panel, so both ask the same things in the
/// same words with the same ranges.
enum ColorGradeRows {
    struct Row {
        let property: MotionProperty
        let range: ClosedRange<Double>
        let typing: SliderNumber
        var label: String { property.title }

        /// A slider's number as the box beside it spells it, so a knob put
        /// back at the middle IS the middle and the picture is the untouched
        /// one exactly, not one graded by a hair.
        func spelled(_ value: Double) -> Double {
            let places = pow(10, Double(typing.decimals))
            return (value * places).rounded() / places
        }
    }

    static let rows: [Row] = [
        Row(property: .gradeTemperature, range: ColorGradeEffect.temperatureRange, typing: SliderNumber()),
        Row(property: .gradeTint, range: ColorGradeEffect.tintRange, typing: SliderNumber()),
        Row(property: .gradeExposure, range: ColorGradeEffect.exposureRange, typing: SliderNumber(decimals: 1)),
        Row(property: .gradeContrast, range: ColorGradeEffect.contrastRange, typing: SliderNumber()),
        Row(property: .gradeSaturation, range: ColorGradeEffect.saturationRange,
            typing: SliderNumber(suffix: "%")),
    ]
}

/// A Color Grade's settings in the Effects list: five sliders, each with the
/// number beside it and, on a video, the key diamond ahead of its name the way
/// the video mock's property rows have it, so a grade warms over a shot the
/// way a title fades in.
struct ColorGradeEffectRows: View {
    @Environment(EditorState.self) private var editorState
    let row: LayerEffectRow

    var body: some View {
        let grades = editorState.layerStyleSelection.colorGrades(at: row.index)
        let index = row.index
        // Keys need one picked layer in a document with time, the same as
        // every other diamond in the panel (`EditorState.keyLayer`).
        let keyable = editorState.keyLayer.map { grades.layerIDs == [$0.id] } ?? false
        ForEach(ColorGradeRows.rows, id: \.property) { grade in
            LayerStyleSlider(layerIDs: grades.layerIDs, label: grade.label,
                             reading: grades.reading {
                                 $0.colorGradeEffect(at: index)?.value(of: grade.property)
                                     ?? grade.property.gradeMiddle ?? 0
                             },
                             range: grade.range, typing: grade.typing,
                             keyed: keyable ? .motion(grade.property) : nil) { style, v in
                style.updateColorGradeEffect(at: index) {
                    $0.set(grade.property, to: grade.spelled(v))
                    $0.isOn = true
                }
            }
            // The diamond and the slider as one row a walk can name, the 3D
            // rows' way: `{"control": "Key", "in": "Grade Temperature"}`.
            .playtestField("Grade \(grade.label)")
            .contextMenu {
                if keyable {
                    let keyed = KeyedProperty.motion(grade.property)
                    Button("Add Key Here") { editorState.addKeyHere(keyed) }
                        .disabled(editorState.keyDiamond(keyed) == .onKey)
                    Button("Remove Key Here") { editorState.removeKeyHere(keyed) }
                        .disabled(editorState.keyDiamond(keyed) != .onKey)
                }
            }
        }
    }
}
