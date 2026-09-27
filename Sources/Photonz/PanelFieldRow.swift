import PhotonzCore
import SwiftUI

/// A panel row's name as the mocks write it (`inspector.css` `.irow>.rl`):
/// 10.5pt, the faint tone, one line. The same word `VideoKit.FieldRow` draws,
/// so the video sections and the picture sections read as one panel.
struct PanelRowLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: PanelRowLayout.labelSize))
            .foregroundStyle(VideoKit.Palette.faint)
            .lineLimit(1)
    }
}

/// One panel row, the mock's `.irow`: the name in the 76pt column and the
/// control beside it, starting on the line every other row's control starts
/// on (`PanelRowLayout`).
///
/// A control that cannot fit beside its name at the width the row has drops
/// onto its own line under the name, full width, instead of being cut: a
/// narrowed dock, or a setting stepped in under the effect it belongs to.
/// That is the one written reason a row stacks.
struct PanelFieldRow<Control: View>: View {
    let label: String
    /// The narrowest the control can be and still read. Nil asks the control
    /// itself: the width it takes when offered none, which is what a track's
    /// `minWidth` and a box's fixed width add up to.
    var controlMinimum: CGFloat?
    @ViewBuilder let control: Control

    init(_ label: String, controlMinimum: CGFloat? = nil,
         @ViewBuilder control: () -> Control) {
        self.label = label
        self.controlMinimum = controlMinimum
        self.control = control()
    }

    var body: some View {
        PanelFieldRowLayout(controlMinimum: controlMinimum) {
            PanelRowLabel(text: label)
            control
        }
    }
}

/// Lays a name and its control out beside each other or one over the other,
/// decided from the width the row is offered, in one pass: no state, no
/// geometry reader, and the row never flickers between the two.
private struct PanelFieldRowLayout: Layout {
    let controlMinimum: CGFloat?
    /// Between the name and the control when the control is under it.
    private let stackGap: CGFloat = 4

    private func minimum(of control: LayoutSubview) -> CGFloat {
        controlMinimum ?? control.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width
    }

    private func beside(_ width: CGFloat?, _ control: LayoutSubview) -> Bool {
        guard let width else { return true }
        return PanelRowLayout.sitsBeside(controlMinimum: minimum(of: control), rowWidth: width)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let label = subviews[0], control = subviews[1]
        if beside(proposal.width, control) {
            let controlWidth = proposal.width.map { PanelRowLayout.controlWidth(rowWidth: $0) }
            let c = control.sizeThatFits(ProposedViewSize(width: controlWidth, height: nil))
            let l = label.sizeThatFits(ProposedViewSize(width: PanelRowLayout.labelColumn, height: nil))
            return CGSize(width: proposal.width ?? PanelRowLayout.controlLeading + c.width,
                          height: max(l.height, c.height))
        }
        let width = proposal.width ?? 0
        let l = label.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let c = control.sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width, height: l.height + stackGap + c.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        guard subviews.count == 2 else { return }
        let label = subviews[0], control = subviews[1]
        if beside(bounds.width, control) {
            let controlWidth = PanelRowLayout.controlWidth(rowWidth: bounds.width)
            label.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                        proposal: ProposedViewSize(width: PanelRowLayout.labelColumn, height: nil))
            control.place(at: CGPoint(x: bounds.minX + PanelRowLayout.controlLeading, y: bounds.midY),
                          anchor: .leading,
                          proposal: ProposedViewSize(width: controlWidth, height: nil))
            return
        }
        let l = label.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        label.place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                    proposal: ProposedViewSize(width: bounds.width, height: nil))
        control.place(at: CGPoint(x: bounds.minX, y: bounds.minY + l.height + stackGap),
                      anchor: .topLeading,
                      proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

/// A slider row on `PanelFieldRow`: the track, then the box you type into.
enum PanelSliderRow {
    /// The shortest a track gets beside its name before the row drops it under
    /// the name instead. Low enough that every setting of an effect, stepped
    /// in under it, still sits beside its name at the dock's default width:
    /// at 60 the rows with a px box dropped under while Direction, with its
    /// narrower degree sign, stayed beside, and one effect read two ways.
    static let trackMinimum: CGFloat = 40
}

/// A name and the one control it names, in whichever of the two looks the
/// release has: the mock's row (`PanelFieldRow`) in Next, and the name over a
/// full width control, the way Appearance always drew it, in Current.
///
/// `accessory` is what sat beside the NAME in the old look, the revert arrow a
/// copy of a component shows: in the mock's row it follows the control, since
/// the label column holds the name and nothing else.
struct PanelNamedControl<Control: View, Accessory: View>: View {
    let label: String
    @ViewBuilder let control: Control
    @ViewBuilder let accessory: Accessory

    init(_ label: String, @ViewBuilder control: () -> Control,
         @ViewBuilder accessory: () -> Accessory) {
        self.label = label
        self.control = control()
        self.accessory = accessory()
    }

    var body: some View {
        if Experiments.shared.panelRowsInOneColumnEnabled {
            PanelFieldRow(label) {
                HStack(spacing: 6) {
                    control
                    accessory
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    accessory
                    Spacer()
                }
                control
            }
        }
    }
}

extension PanelNamedControl where Accessory == EmptyView {
    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.init(label, control: control) { EmptyView() }
    }
}

extension View {
    /// A row's name in the panel: the mock's small faint label in Next
    /// (`PanelRowLabel`), the caption it always was in Current.
    @MainActor
    func panelRowName() -> some View {
        modifier(PanelRowNameLook())
    }
}

private struct PanelRowNameLook: ViewModifier {
    func body(content: Content) -> some View {
        if Experiments.shared.panelRowsInOneColumnEnabled {
            content
                .font(.system(size: PanelRowLayout.labelSize))
                .foregroundStyle(VideoKit.Palette.faint)
        } else {
            content
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Two settings that used to share one line as two columns, Size beside
/// Weight, Across beside Down. In the mock every setting is its own row, so in
/// Next they stack as two rows; in Current they keep their two columns.
struct PanelPair<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if Experiments.shared.panelRowsInOneColumnEnabled {
            VStack(alignment: .leading, spacing: 8) { content }
        } else {
            HStack(alignment: .top, spacing: 8) { content }
        }
    }
}
