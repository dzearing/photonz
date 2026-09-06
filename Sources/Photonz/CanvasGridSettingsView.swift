import PhotonzCore
import SwiftUI

/// Every setting the canvas grid has, drawn once and shown in two places
/// (Next, `next-canvas-grid`).
///
/// The grid's numbers used to live in exactly one place: the Canvas section of
/// the right hand panel, which only appears after you click the Canvas row at
/// the bottom of the layers list. The switch was on the View menu, so the two
/// halves of the same feature were nowhere near each other and the half nobody
/// could find was the half with all the numbers in it.
///
/// So the controls moved into one view and grew a second home. They are now
/// reachable three ways, and they are the SAME controls each time rather than
/// three arrangements that drift apart:
///
/// - **From the grid itself.** While the grid is showing, a chip sits in the
///   floating tool bar beside the zoom reading what the lines on screen are
///   worth, and pressing it opens these in a popover. It appears at the instant
///   the lines do, which is the moment a person wants it.
///
/// When the zoom has coarsened the grid, the Spacing row carries a second line
/// saying what is actually being drawn. That is the other half of the chip's
/// "4 → 32 pt": the chip says both numbers exist, and this says why.
/// What is NOT here: the cell the grid works to, and where it starts. Both
/// moved to the tool bar, where the lines they shape are in front of you while
/// you move them. See `EditorView.gridChip`.
///
/// - **From where the grid is switched on.** View ▸ Grid Settings, directly
///   under Show Grid, opens the same popover — and switches the grid on first
///   if it was off, because nobody tunes a grid they cannot see.
/// - **From the Canvas**, where it always was, for anyone who arrives by
///   clicking the Canvas row. Nothing that worked before stopped working.
///
/// Each number carries one line saying what it does, because "Smallest cell" is
/// not a phrase anyone can decode from the words alone.
struct CanvasGridControls: View {
    @Environment(EditorState.self) private var editorState

    /// How wide the label column is. The popover has room for the words to sit
    /// beside their control; the panel is narrower, so it gets less.
    var labelWidth: CGFloat = 92

    private var grid: CanvasGridSettings { editorState.canvasGrid }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(CanvasGridCopy.grid, isOn: Binding(
                get: { grid.isVisible },
                set: { editorState.canvasGrid.isVisible = $0 }))
                .font(.callout)
                .controlSize(.small)
                .help(CanvasGridCopy.gridCaption)
                .playtestControl(CanvasGridCopy.grid,
                                 detail: "Grid settings, \(grid.isVisible ? "shown" : "hidden")")
            if grid.isVisible {
                // Only while the grid is showing: with no lines on the picture
                // there is nothing to pull to, so a switch for it would be a
                // control that does nothing.
                Toggle(CanvasGridCopy.snap, isOn: Binding(
                    get: { grid.snapsToGrid },
                    set: { editorState.canvasGrid.snapsToGrid = $0 }))
                    .font(.callout)
                    .controlSize(.small)
                    .help(CanvasGridCopy.snapCaption)
                    .playtestControl(CanvasGridCopy.snap,
                                     detail: "Grid settings, \(grid.snapsToGrid ? "on" : "off")")
                // The one checkbox here that carries its explanation on the
                // surface rather than in a tooltip: the magnet holds the arrow
                // keys as well as a drag now, and nobody discovers that by
                // pressing one and watching a layer travel a whole cell.
                Text(CanvasGridCopy.snapCaption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                // The picker is as wide as the popover, so its word sits ABOVE
                // it rather than beside it. Unlabelled it was two phrases
                // floating between two checkboxes, and a first timer had no
                // way to tell what they were choosing between.
                stackedRow(CanvasGridCopy.lines, caption: CanvasGridCopy.linesCaption) {
                    Picker(CanvasGridCopy.lines, selection: Binding(
                        get: { grid.axes },
                        set: { editorState.setCanvasGridAxes($0) })) {
                        ForEach(CanvasGridAxes.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                    .help(CanvasGridCopy.linesCaption)
                }
                numberRow(CanvasGridCopy.spacing, caption: CanvasGridCopy.spacingCaption,
                          suffix: "pt", value: Double(grid.spacing),
                          note: grid.liveSpacingNote(atZoom: editorState.zoom),
                          set: { editorState.setCanvasGridSpacing(CGFloat($0)) })
                numberRow(CanvasGridCopy.majorEvery, caption: CanvasGridCopy.majorEveryCaption,
                          suffix: "lines", value: Double(grid.majorEvery),
                          set: { editorState.setCanvasGridMajorEvery(Int($0.rounded())) })
                // Two rows are deliberately NOT here any more. The cell the
                // grid works to has a slider on the tool bar, where you can
                // watch the lines change as you move it, and where the grid
                // starts is placed by taking the canvas over rather than by
                // typing two numbers at a picture you cannot see while you
                // type them. Both are one press away on the bar; what is left
                // in here is only what the bar does not carry.
                Text(CanvasGridCopy.footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One labelled row with its one line of explanation underneath. The
    /// caption is under the pair rather than beside it so a long sentence never
    /// squeezes the control it is describing.
    ///
    /// `note` is a SECOND line, present only when the canvas is doing something
    /// the number in the field does not say by itself. It sits under the
    /// caption in the plainer colour, because it is about the picture in front
    /// of you rather than about what the control is for.
    @ViewBuilder private func row<Content: View>(_ label: String, caption: String,
                                                 note: String? = nil,
                                                 @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth, alignment: .leading)
                content()
                Spacer(minLength: 0)
            }
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .playtestField(label)
    }

    /// A row whose control is too wide to share a line with its word: the word
    /// goes above it, the explanation below, and the control keeps the full
    /// width of the surface.
    @ViewBuilder private func stackedRow<Content: View>(_ label: String, caption: String,
                                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .playtestField(label)
    }

    /// One of the grid's numbers. It commits on Return and on losing the
    /// keyboard, steps with the arrow keys like every other number in the
    /// panel, and hands the keyboard back afterwards so the next letter picks
    /// a tool.
    @ViewBuilder private func numberRow(_ label: String, caption: String, suffix: String,
                                        value: Double, note: String? = nil,
                                        set: @escaping (Double) -> Void) -> some View {
        row(label, caption: caption, note: note) {
            TextField(label, value: Binding(get: { value }, set: { set($0) }),
                      format: .number.precision(.fractionLength(0)).grouping(.never))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                .numberFieldKeys(
                    commit: {},
                    revert: {},
                    step: { direction, coarse in
                        set(Double(LayerGeometry.stepped(value, direction: direction,
                                                         coarse: coarse)))
                    })
            Text(suffix).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

/// The grid's settings as the canvas opens them: the same controls with a title
/// over them, so a popover that arrived from a menu says what it is.
struct CanvasGridSettingsPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(CanvasGridCopy.settingsTitle)
                .font(.headline)
            CanvasGridControls()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 300)
    }
}
