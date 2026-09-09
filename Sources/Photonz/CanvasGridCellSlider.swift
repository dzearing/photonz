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

    /// Whether the size on the button is finer than this zoom can draw, so the
    /// canvas is showing no grid. The button says so rather than leaving a
    /// switch that is on and a size that is set standing over an empty canvas.
    private var isTooFine: Bool { settings.cellIsTooFineToDraw(atZoom: editorState.zoom) }

    var body: some View {
        Button { isPresented.wrappedValue.toggle() } label: {
            Text(settings.cellButtonText)
                .font(.caption.weight(.medium).monospacedDigit())
                // Dimmed rather than struck through or badged: the size is
                // still set and still what you get the moment you come closer,
                // so the button is quiet about it, not cancelled.
                .foregroundStyle(isTooFine ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.primary))
                .lineLimit(1)
                // One fixed width for every size it can read, so nothing in the
                // bar shifts when the cell goes from "Auto" to "12 px".
                .frame(width: 40, height: 18)
                .contentShape(.rect)
        }
        // A soft fill at rest, because this is the one thing on the capsule
        // that has to look pressable without wearing a chevron: the size IS
        // the button, and a bare number on glass reads as a label.
        .buttonStyle(PillActionButtonStyle(prominent: true))
        .fixedSize()
        .panelHelp(settings.cellButtonHelp(atZoom: editorState.zoom))
        .playtestControl(CanvasGridCopy.cell, detail: "Tool bar, \(settings.cellButtonText)")
        .popover(isPresented: isPresented, arrowEdge: .top) {
            CanvasGridCellSlider(cell: settings.minimumCell) {
                editorState.setGridMinimumCell($0)
            }
        }
    }
}

/// The sizes, as a vertical slider: a track with a stop on it for every cell
/// real UI is built in, automatic at the very bottom, and ONE number under it
/// saying which one you are on.
///
/// It is vertical because the thing being chosen is a size and sizes read down
/// a column, and because the button it hangs off is on a horizontal bar with
/// no room to grow sideways.
///
/// **One readout, not nine labels.** It used to carry a number beside every
/// stop. Nine numbers down the side of a track is a lot of ink for a control
/// with one value, and reading them against the stops meant checking which
/// number belonged to which dot, which is precisely the work a slider is
/// supposed to save. So the column is gone and the number that was "Auto" at
/// the foot now says whatever is being chosen: run the knob up the track and
/// it counts up under your thumb.
struct CanvasGridCellSlider: View {
    var cell: CGFloat
    var onChange: (CGFloat) -> Void

    /// One stop per row. Tall enough to press without care, short enough that
    /// nine of them are a popover rather than a window.
    private static let rowHeight: CGFloat = 26
    private static let trackWidth: CGFloat = 44
    private static let knobDiameter: CGFloat = 13

    private var stops: [CGFloat] { CanvasGridCellStops.all }
    private var selected: Int { CanvasGridCellStops.index(of: cell) }

    var body: some View {
        let height = Self.rowHeight * CGFloat(stops.count)
        VStack(spacing: 6) {
            track(height: height)
            readout
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        // One gesture for both intentions, because they land in the same
        // place: a press puts the knob on the nearest stop, and holding on and
        // running down the column drags it there with the grid redrawing under
        // it, which is how you find the size you want by looking rather than
        // by knowing.
        .contentShape(.rect)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { pick(atY: $0.location.y - 12, height: height) })
    }

    /// The rail, its stops, and the knob on the one that is chosen, over a
    /// column of invisible rows — one per size, laid out rather than offset so
    /// each really occupies its own strip — so a press anywhere across from a
    /// size lands on that size. The rail itself takes no clicks, or the four
    /// point strip down the middle would swallow half of them.
    private func track(height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ForEach(stops.indices.reversed(), id: \.self) { index in
                    Button { onChange(stops[index]) } label: {
                        Color.clear
                            .frame(width: Self.trackWidth, height: Self.rowHeight)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .playtestControl(label(at: index), detail: "Grid cell sizes")
                }
            }
            ZStack(alignment: .top) {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: 4, height: height - Self.rowHeight + 6)
                    .offset(y: Self.rowHeight / 2 - 3)
                ForEach(stops.indices, id: \.self) { index in
                    Circle()
                        .fill(index == selected ? AnyShapeStyle(Color.clear)
                                                : AnyShapeStyle(.tertiary))
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
            .allowsHitTesting(false)
        }
        .frame(width: Self.trackWidth, height: height)
    }

    /// The one number, where the automatic label used to sit: the size being
    /// chosen right now, changing under the knob as it is dragged.
    private var readout: some View {
        Text(label(at: selected))
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            // Fixed, so the popover does not breathe as the number changes.
            .frame(width: Self.trackWidth, height: 14)
            .animation(nil, value: selected)
    }

    private func label(at index: Int) -> String {
        index == 0 ? CanvasGridCopy.automaticCell
                   : DocumentUnit.text(digits: CanvasGridNumber.text(stops[index]))
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
