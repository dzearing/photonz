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
                    // The panel's dropdown, as wide as the section.
                    VideoKit.Dropdown(
                        label: "Mode",
                        value: editorState.measureToolMode.title,
                        help: Self.modeHelp,
                        choices: .picking(MeasureToolMode.available(
                            alignmentEnabled: Experiments.shared.measureAlignEnabled),
                                          current: editorState.measureToolMode,
                                          title: \.title) { state.measureToolMode = $0 })
                        .frame(maxWidth: .infinity)
                        .panelHelp(Self.modeHelp)
                        .playtestControl("Mode", detail: editorState.measureToolMode.title)
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
                field("Snap", reads: Self.snapTitle(editorState.measureSnapsToCenters)) {
                    // Two answers, so both show: the fields mock's segmented
                    // control, never a menu of two (comp-fields.html, Select).
                    SegmentedControl("Snap", selection: editorState.measureSnapsToCenters,
                                     options: [.init(false, Self.snapTitle(false), help: Self.snapHelp),
                                               .init(true, Self.snapTitle(true), help: Self.snapHelp)],
                                     pick: { state.measureSnapsToCenters = $0 })
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                }
            }
            if Experiments.shared.measureRolesEnabled {
                field("Show") {
                    VideoKit.Dropdown(
                        label: "Show",
                        value: editorState.measureShowFilter.title,
                        help: Self.showHelp,
                        choices: .picking(EditorState.MeasureShowFilter.allCases,
                                          current: editorState.measureShowFilter,
                                          title: \.title) { editorState.setMeasureShowFilter($0) })
                        .frame(maxWidth: .infinity)
                        .panelHelp(Self.showHelp)
                        .playtestControl("Show", detail: editorState.measureShowFilter.title)
                }
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }

    /// `reads`, for a row of segments: the caption carries what the row says,
    /// so a walk reads it, `{"control": "Snap", "reads": "Snap, Edges"}`, and
    /// presses each segment by its own word.
    @ViewBuilder private func field<Content: View>(_ label: String, reads: String? = nil,
                                                   @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let reads {
                Text(label).font(.caption).foregroundStyle(.secondary)
                    .playtestControl(label, detail: reads)
            } else {
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .playtestField(label)
    }

    /// Each dropdown's hover tip, on the AppKit button and in the panel's
    /// register where a walk reads it.
    static let modeHelp = "What a click does. The Measure button holds the same list, "
        + "and I cycles it. In Size, [ and ] pick a smaller or larger element."
    static let snapHelp = "What measure points magnetize to. Hold Command to drag free."
    static let showHelp = "Which measurements the canvas shows. A view filter only: exports "
        + "always include every visible measurement."

    static func snapTitle(_ toCenters: Bool) -> String { toCenters ? "Edges and centers" : "Edges" }
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
                // What this slider does, on the slider. It was a line under the
                // section, which is a line of panel spent describing a control
                // (UX-PATTERNS §4, "How much a section may say", 2026-09-14).
                .panelHelp("How far a color may drift and still join the selection")
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }
}

// MARK: - Fill tool properties (D15)

/// The paint bucket's own settings, shown while it is in hand: Photoshop's
/// three, in Photoshop's order. They decide how far a click on a picture
/// floods; a shape, a piece of text or an arrow takes the colour whole.
struct FillToolInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        @Bindable var state = editorState
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tolerance").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(editorState.bucketTolerance))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { editorState.bucketTolerance },
                                  set: { editorState.bucketTolerance = $0.rounded() }),
                   in: 0...128)
                .controlSize(.small)
                .panelHelp("How far a color may drift from the one you click and still fill")
            Toggle("Anti-alias", isOn: $state.bucketAntiAlias)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .panelHelp("Blend the fill into the edges of lines")
                .playtestField("Anti-alias")
            Toggle("Contiguous", isOn: $state.bucketContiguous)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .panelHelp("Off fills that color everywhere on the layer")
                .playtestField("Contiguous")
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

    static let help = "What shape the crop keeps. The Crop button holds the same list."

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Aspect").font(.caption).foregroundStyle(.secondary)
            VideoKit.Dropdown(
                label: "Aspect",
                value: editorState.cropAspect.label,
                help: Self.help,
                choices: .picking(CropAspect.allCases, current: editorState.cropAspect,
                                  title: \.label) { editorState.setCropAspect($0) })
                .frame(maxWidth: .infinity)
                .panelHelp(Self.help)
                .playtestControl("Aspect", detail: editorState.cropAspect.label)
        }
        .playtestField("Aspect")
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

    /// Either half can be off on its own, so each row asks for itself.
    static var hasAnySetting: Bool { MagnifierToolSettingsRows.hasAnySetting }

    var body: some View {
        MagnifierToolSettingsRows()
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 8)
    }
}
