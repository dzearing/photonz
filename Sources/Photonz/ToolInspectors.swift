// The settings shown for the tool in your hand: measure, magic wand, crop and zoom callout.

import PhotonzCore
import SwiftUI

// MARK: - Measure tool properties (D15)

/// The Measure tool's own properties, shown while the tool is in hand.
///
/// These used to ride in the tool bar as a Snap menu and a Show menu next to
/// four mode chips, six controls that grew a fixed strip the moment you picked
/// the tool up. D15 draws the line: a mode changes what a click DOES and can
/// live in the tool button, and everything else is a setting that belongs with
/// the tool's properties. Snap changes where a point lands, Show changes what
/// the canvas draws, and both read better as words in a panel than as menus in
/// a strip.
///
/// Mode is here too, on purpose. The button's flyout is the fast path, but a
/// glyph cannot tell you three minutes later that you are still in Gap, so the
/// live mode stays readable as a word for anyone with the inspector open.
struct MeasureToolInspector: View {
    @Environment(EditorState.self) private var editorState

    /// Whether any of the tool's settings exist in this release, so the panel
    /// can leave the section out entirely rather than show an empty box.
    static var hasAnySetting: Bool {
        Experiments.shared.measureModesEnabled || Experiments.shared.measureCenterSnapEnabled
            || Experiments.shared.measureRolesEnabled
    }

    var body: some View {
        @Bindable var state = editorState
        VStack(alignment: .leading, spacing: 8) {
            if Experiments.shared.measureModesEnabled {
                field("Mode") {
                    Picker("Mode", selection: $state.measureToolMode) {
                        ForEach(MeasureToolMode.available(
                            alignmentEnabled: Experiments.shared.measureAlignEnabled), id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden().controlSize(.small)
                    .panelHelp("What a click does. The Measure button holds the same list, "
                          + "and I cycles it. In Size, [ and ] pick a smaller or larger element.")
                    // The keys the mode answers to, taught here because this
                    // line stays: the canvas hint fades in two seconds and
                    // used to be the only place the [ and ] keys were written.
                    if let tip = editorState.measureToolMode.keyTip {
                        Text(tip)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if Experiments.shared.measureCenterSnapEnabled {
                field("Snap") {
                    Picker("Snap", selection: $state.measureSnapsToCenters) {
                        Text("Edges").tag(false)
                        Text("Edges and centers").tag(true)
                    }
                    .labelsHidden().controlSize(.small)
                    .panelHelp("What measure points magnetize to. Hold Command to drag free.")
                }
            }
            if Experiments.shared.measureRolesEnabled {
                field("Show") {
                    Picker("Show", selection: Binding(
                        get: { editorState.measureShowFilter },
                        set: { editorState.setMeasureShowFilter($0) })) {
                        ForEach(EditorState.MeasureShowFilter.allCases, id: \.self) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .labelsHidden().controlSize(.small)
                    .panelHelp("Which measurements the canvas shows. A view filter only: exports "
                          + "always include every visible measurement.")
                }
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }

    @ViewBuilder private func field<Content: View>(_ label: String,
                                                   @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .playtestField(label)
    }
}

// MARK: - Magic Wand tool properties (D15)

/// The Magic Wand's own properties, shown while the tool is in hand.
///
/// Tolerance used to ride in the tool bar as a labelled slider, 152pt that
/// appeared the moment you picked the wand up. It is a setting by D15's test —
/// it changes what the result looks like, not what the pointer does — so it
/// belongs with the tool's properties, and it reads better here with room for
/// the number and a line saying what it means.
struct WandToolInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        @Bindable var state = editorState
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tolerance").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(editorState.wandTolerance))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { editorState.wandTolerance },
                                  set: { editorState.wandTolerance = $0.rounded() }),
                   in: 0...128)
                .controlSize(.small)
            Text("How far a color may drift and still join the selection.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }
}

// MARK: - Crop tool properties (D15)

/// The Crop tool's own properties, shown while the tool is in hand: the aspect
/// lock as a word.
///
/// The four locks used to be four chips in the tool bar. They are modes, so
/// they moved into the crop button's flyout; this is the same choice spelled
/// out, for anyone with the inspector open. Picking here reshapes the pending
/// crop rect exactly as the flyout does.
struct CropToolInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Aspect").font(.caption).foregroundStyle(.secondary)
            Picker("Aspect", selection: Binding(get: { editorState.cropAspect },
                                                set: { editorState.setCropAspect($0) })) {
                ForEach(CropAspect.allCases, id: \.self) { aspect in
                    Text(aspect.label).tag(aspect)
                }
            }
            .labelsHidden().controlSize(.small)
            .panelHelp("What shape the crop keeps. The Crop button holds the same list.")
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }
}

// MARK: - Zoom Callout tool properties (D15)

/// The Zoom Callout tool's own properties, shown while the tool is in hand:
/// whether the next callout is a box or a circle, and how much it magnifies.
///
/// Both used to be reachable only after the fact, in a picked callout's own
/// section, so getting a round 4× callout meant drawing a 2× rectangle and then
/// going to fix it twice. They are settings by D15's test — they change what
/// the drag produces, not what the pointer does — so they belong with the
/// tool's properties, and the tool keeps whatever you last chose.
///
/// Same order as the capsule above the tool bar, because they are the same two
/// settings: whichever place you learn them in, the other reads the same.
struct CalloutToolInspector: View {
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
                    .panelHelp("What the next callout is drawn in. The box you drag out previews "
                          + "in the same shape, and a callout already on the canvas is "
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
                    // picked callout's slider there is nothing to preview and
                    // nothing to undo: it just moves.
                    Slider(value: Binding(get: { state.calloutToolMagnification },
                                          set: { state.calloutToolMagnification = $0 }),
                           in: ZoomCalloutBuilder.magnificationRange)
                        .controlSize(.small)
                        .panelHelp("How much bigger the next callout draws the region it points at. "
                              + "A callout already on the canvas is resized by the slider in "
                              + "its own section.")
                }
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }
}
