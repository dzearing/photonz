import PhotonzCore
import SwiftUI

/// A picked zoom callout's own two settings: how much it magnifies, and
/// whether it is a box or a circle.
///
/// Nothing else about a callout is here, because a callout's ring is the
/// layer's OWN border: the ring's color is the Border row in the Color
/// section, where every color lives, and its thickness is the Border slider in
/// Effects, where every layer's is. One home each, and no copy of either down
/// here to wonder about.
///
/// These two controls used to live in the tool bar's style popover, which a
/// picked callout can never open: that popover belongs to the tool in your
/// hand, and picking up a drawing tool drops the layer selection. So until
/// 2026-09-04 a callout could be drawn and then never made bigger or made
/// round. The popover's callout half is gone and this is where it landed.
struct CalloutInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer

    /// Live through a slider drag: a preview lives in the frame, and frame
    /// over source IS the magnification.
    private var magnification: CGFloat {
        editorState.selectedCalloutMagnification ?? ZoomCalloutBuilder.defaultMagnification
    }

    /// What the document says right now, which a drag does not move — so the
    /// slider's range cannot change under the thumb mid-pull.
    private var committedMagnification: CGFloat {
        editorState.document?.layer(id: layer.id)?.zoomCallout?.magnification
            ?? ZoomCalloutBuilder.defaultMagnification
    }

    private var shape: ZoomCalloutShape {
        editorState.document?.layer(id: layer.id)?.zoomCallout?.shape ?? .rectangle
    }

    private var range: ClosedRange<Double> {
        let range = ZoomCalloutBuilder.magnificationRange(including: committedMagnification)
        return Double(range.lowerBound)...Double(range.upperBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Magnification").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(ZoomCalloutBuilder.magnificationLabel(magnification))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                // Drags preview through the regular frame path and commit one
                // undo step on release, so a pull is one step to undo rather
                // than forty.
                Slider(value: Binding(
                    get: { Double(magnification) },
                    set: { editorState.previewCalloutMagnification(CGFloat($0)) }),
                       in: range) { editing in
                    if !editing { editorState.commitCalloutMagnification() }
                }
                .controlSize(.small)
                .help("How much bigger the callout draws the region it points at. "
                      + "Dragging the callout's corners sets the same number.")
            }
            HStack(spacing: 8) {
                Text("Shape").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Picker("Shape", selection: Binding(
                    get: { shape },
                    set: { editorState.setCalloutShape($0) })) {
                    ForEach(ZoomCalloutShape.allCases, id: \.self) { shape in
                        Text(shape.title).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .help("Whether the magnified region is drawn in a box or in a circle.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .id(layer.id)
    }
}
