import PhotonzCore
import SwiftUI

/// The size of the cell the grid works to, as one button and one slider
/// (Next, `next-canvas-grid`).
///
/// The tool bar used to carry the cell as a horizontal slider parked beside a
/// two number readout, and pressing the readout opened a popover of every
/// setting the grid has. Between them they said far more than anybody needed
/// while they were doing something else, so the whole thing is now a button
/// with a size on it. Press it and the sizes appear as a plain vertical
/// slider, finest at the foot, and that is all that appears: the rest of the
/// grid's settings are on the View menu and in the Canvas section of the
/// panel, where you go when you are actually tuning a grid rather than using
/// one.
///
/// **Automatic is the bottom stop.** It means no floor, so the cell follows the
/// zoom on the same level-of-detail ladder the canvas draws with — which is
/// also the ladder a drag lands on. Automatic can therefore never disagree
/// with the picture. See `CanvasGridCellStops.automatic`.
struct CanvasGridSizeButton: View {
    @Environment(EditorState.self) private var editorState

    /// The settings the button is reading: the grid itself outside the adjust
    /// mode, the working copy inside it. One button, one slider, both places.
    var settings: CanvasGridSettings
    /// Where the mode's own bar draws it, the glass is already dark, so the
    /// button sheds its own background and reads as one of the row.
    var isPresented: Binding<Bool>

    var body: some View {
        Button { isPresented.wrappedValue.toggle() } label: {
            Text(settings.cellButtonText)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                // One fixed width for every size it can read, so nothing in the
                // bar shifts when the cell goes from "Auto" to "12 pt".
                .frame(width: 40, height: 18)
                .contentShape(.rect)
        }
        // A soft fill at rest, because this is the one thing on the capsule
        // that has to look pressable without wearing a chevron: the size IS
        // the button, and a bare number on glass reads as a label.
        .buttonStyle(PillActionButtonStyle(prominent: true))
        .fixedSize()
        .help(settings.cellButtonHelp(atZoom: editorState.zoom))
        .playtestControl(CanvasGridCopy.cell, detail: "Tool bar, \(settings.cellButtonText)")
        .popover(isPresented: isPresented, arrowEdge: .top) {
            CanvasGridCellSlider(cell: settings.minimumCell) {
                editorState.setGridMinimumCell($0)
            }
        }
    }
}

/// The sizes, as a vertical slider: a track with a stop on it for every cell
/// real UI is built in, automatic at the very bottom.
///
/// It is vertical because the thing being chosen is a size and sizes read down
/// a column, and because the button it hangs off is on a horizontal bar with
/// no room to grow sideways. Every stop carries its own number beside the
/// track, so choosing one is reading rather than aiming: press a number, or
/// take hold of the knob and run down the column.
struct CanvasGridCellSlider: View {
    var cell: CGFloat
    var onChange: (CGFloat) -> Void

    /// One stop per row. Tall enough to press without care, short enough that
    /// nine of them are a popover rather than a window.
    private static let rowHeight: CGFloat = 26
    private static let trackWidth: CGFloat = 20
    private static let knobDiameter: CGFloat = 13

    private var stops: [CGFloat] { CanvasGridCellStops.all }
    private var selected: Int { CanvasGridCellStops.index(of: cell) }

    var body: some View {
        let height = Self.rowHeight * CGFloat(stops.count)
        HStack(spacing: 6) {
            track(height: height)
            labels
        }
        .frame(height: height)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        // Two ways to use it, because they are two different intentions. A
        // press on a size is a decision already made; a drag runs the knob up
        // and down the column with the grid redrawing under it, which is how
        // you find the cell you want by looking rather than by knowing. The
        // drag only starts once the pointer has actually moved, so a press
        // stays a press.
        .contentShape(.rect)
        .simultaneousGesture(DragGesture(minimumDistance: 2)
            .onChanged { pick(atY: $0.location.y - 12, height: height) })
    }

    /// The rail, its stops, and the knob on the one that is chosen.
    private func track(height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(.quaternary)
                .frame(width: 4, height: height - Self.rowHeight + 6)
                .offset(y: Self.rowHeight / 2 - 3)
            ForEach(stops.indices, id: \.self) { index in
                Circle()
                    .fill(.tertiary)
                    .frame(width: 3, height: 3)
                    .offset(y: centre(ofIndex: index) - 1.5)
            }
            Circle()
                .fill(Color.accentColor)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                .frame(width: Self.knobDiameter, height: Self.knobDiameter)
                .offset(y: centre(ofIndex: selected) - Self.knobDiameter / 2)
                .animation(.spring(duration: 0.2), value: selected)
        }
        .frame(width: Self.trackWidth, height: height)
    }

    /// The sizes themselves, coarsest at the top, automatic at the foot. Each
    /// one is its own press: the chosen one is the only one in the accent, so
    /// the column can be read at a glance without hunting for the knob.
    private var labels: some View {
        VStack(spacing: 0) {
            ForEach(stops.indices.reversed(), id: \.self) { index in
                Button { onChange(stops[index]) } label: {
                    Text(label(at: index))
                        .font(.system(size: 11,
                                      weight: index == selected ? .semibold : .regular)
                            .monospacedDigit())
                        .foregroundStyle(index == selected ? AnyShapeStyle(Color.accentColor)
                                                           : AnyShapeStyle(.secondary))
                        .frame(width: 44, height: Self.rowHeight, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .playtestControl(label(at: index), detail: "Grid cell sizes")
            }
        }
    }

    private func label(at index: Int) -> String {
        index == 0 ? CanvasGridCopy.automaticCell
                   : "\(CanvasGridNumber.text(stops[index])) pt"
    }

    /// The middle of a stop's row, measured from the top of the control. Stop
    /// zero is automatic and sits at the bottom, so the column counts up.
    private func centre(ofIndex index: Int) -> CGFloat {
        let row = CGFloat(stops.count - 1 - index)
        return Self.rowHeight * (row + 0.5)
    }

    /// A point on the column, turned into the stop nearest it. The rounding
    /// rule is `CanvasGridCellStops`, so the slider and anything else that
    /// places a knob agree.
    private func pick(atY y: CGFloat, height: CGFloat) {
        guard height > 0, stops.count > 1 else { return }
        let row = y / Self.rowHeight - 0.5
        let fraction = (CGFloat(stops.count - 1) - row) / CGFloat(stops.count - 1)
        let chosen = CanvasGridCellStops.cell(at: CanvasGridCellStops.index(atFraction: fraction))
        guard chosen != cell else { return }
        onChange(chosen)
    }
}
