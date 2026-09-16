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
    let layer: Layer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MagnifierSettingsRows(layer: layer)
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
        .id(layer.id)
    }
}

/// The two rows a picked magnifier has, wherever it is shown: how much bigger
/// it draws what it points at, and whether that comes out a box or a circle.
///
/// Their own view because they now appear in two places. Current shows them in
/// its Zoom Callout section; Next shows them in the LENS section, because a
/// callout there is the Lens set to Magnify and one section covers both
/// (`LensKind`). Two copies of two sliders would be two things to keep in step.
struct MagnifierSettingsRows: View {
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
                .panelHelp("How much bigger this draws the region it points at. "
                      + "Dragging its corners sets the same number.")
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
                .panelHelp("Whether the magnified region is drawn in a box or in a circle.")
            }
        }
    }
}

/// The same two rows for the TOOL: what the next magnifier you draw will be,
/// as opposed to what a picked one is. Shared by Current's Zoom Callout Tool
/// section and Next's Lens Tool section for the same reason as the pair above.
struct MagnifierToolSettingsRows: View {
    @Environment(EditorState.self) private var editorState

    /// Either half can be off on its own, so each row asks for itself.
    static var hasAnySetting: Bool {
        Experiments.shared.calloutShapeEnabled || Experiments.shared.calloutMagnificationEnabled
    }

    var body: some View {
        @Bindable var state = editorState
        VStack(alignment: .leading, spacing: 10) {
            if Experiments.shared.calloutShapeEnabled {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shape").font(.caption).foregroundStyle(.secondary)
                    Picker("Shape", selection: $state.calloutToolShape) {
                        ForEach(ZoomCalloutShape.allCases, id: \.self) { shape in
                            Text(shape.title).tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .panelHelp("What the next one is drawn in. The box you drag out previews "
                          + "in the same shape, and one already on the canvas is "
                          + "switched in its own section.")
                }
            }
            if Experiments.shared.calloutMagnificationEnabled {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Magnification").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(ZoomCalloutBuilder
                            .magnificationLabel(editorState.calloutToolMagnification))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    // The tool's number is not a document edit, so unlike the
                    // picked one's slider there is nothing to preview and
                    // nothing to undo: it just moves.
                    Slider(value: Binding(get: { state.calloutToolMagnification },
                                          set: { state.calloutToolMagnification = $0 }),
                           in: ZoomCalloutBuilder.magnificationRange)
                        .controlSize(.small)
                        .panelHelp("How much bigger the next one draws the region it points at. "
                              + "One already on the canvas is resized by the slider in "
                              + "its own section.")
                }
            }
        }
    }
}
