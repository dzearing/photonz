import PhotonzCore
import SwiftUI

/// One row of an effects list, drawn as a SMALL PANE: a chevron, a lit name, a
/// grip, an eye, a cross, and its own settings under it behind a rule that says
/// they are its.
///
/// ONE row for every effects list in the panel: a layer's Effects (shadows,
/// glows, borders, blurs: `EffectsListInspector`) and a sound's Audio Effects
/// (noise reduction, EQ, compressor: `SoundEffectsInspector`). The two lists
/// were built separately once and drifted (the sound's had a cross and no
/// switch, no chevron, no right-click), which is why the row lives here and
/// each list only says what its row is and what its settings are.
///
/// The rule is the fix for the thing the user reported on 2026-09-07: a
/// shadow's Blur, Size and Opacity drawn flat under its row read as a second
/// copy of the layer's own Blur and Opacity. Now they are visibly the shadow's.
///
/// The heading is the fix for what they reported on 2026-09-08, looking at a
/// Border: the row wore a tick where every other heading in the dock wears a
/// chevron, and its title weighed exactly what the settings under it weighed,
/// so the row and its contents ran together into one grey list. An effect is
/// not a row with some numbers after it — it is a section of its own, four or
/// five settings deep, which is why it is drawn like one:
///
/// - **A chevron leads it** and folds its settings away, the same glyph the
///   layers list uses for a group and the dock uses for a section, one step
///   smaller (`PanelSectionLook.EffectRow`).
/// - **The name is lit**, semibold in the primary ink, so it reads as the
///   header of what sits under it rather than as another label.
/// - **The switch is an eye** at the end of the row, drawn and behaving like
///   the eye on a layer row, because "this one is not showing" is a thing this
///   app already has one picture for. On a sound it is the mock's `.en` dot
///   (`pages/video-audio.html`, `#gEffects`) in the app's one picture for off.
/// - **A reading** after the name where the list has one: the mock's `.emeta`
///   on a sound ("low cut 80", "3:1", "off").
struct EffectsListRow<Accessory: View, Settings: View, HeaderDrop: ViewModifier>: View {

    /// Where a row sits in a list whose order can be changed, and how to
    /// change it. Nil on a list whose order is fixed.
    struct Reorder {
        let index: Int
        let canMove: (Int) -> Bool
        let move: (Int) -> Void
    }

    let title: String
    /// What the tips call one of these: "shadow", "EQ".
    let kindWord: String
    /// The names a walk may also find the row by (`PlaytestSteadyName`).
    var steadyNames: [String] = []
    let isOn: Bool
    var isMixed: Bool = false
    let isFolded: Bool
    let toggleFold: () -> Void
    /// The value at the row's end, where the list prints one.
    var reading: String?
    /// What the switch says out loud, and its tip.
    let switchReading: String
    let switchHelp: String
    let setOn: (Bool) -> Void
    let remove: () -> Void
    var reorder: Reorder?
    /// A line of small print under the row, about the row.
    var note: String?
    /// Something the list does to the heading alone (a colour landing on a
    /// switched-off effect).
    let headerDrop: HeaderDrop
    /// How tall this pane is and whether it is open, told to the list so the
    /// dock can keep room for it. See `EffectsListInspector.onPanes`.
    var onExtent: ((DockHeightBudget.Block) -> Void)?
    /// ...and where it is sitting, in the dock's visible area, so opening it
    /// can bring it on screen. Measured in the DOCK's space rather than this
    /// list's, because the list may be inside its own scroller and the answer
    /// has to be "can a person see this", not "is it in the list".
    var onFrame: ((CGRect) -> Void)?
    /// What sits after the name on a switched-off row (a landing colour, the
    /// word mixed).
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let settings: () -> Settings

    /// How far the row has been dragged, while it is being dragged. The list
    /// order IS the paint order, so this is not decoration: it is how you say
    /// which shadow goes over which.
    @State private var carry: CGFloat = 0
    /// The height of one block, measured off this row, so a drag can be turned
    /// into a number of places moved.
    @State private var blockHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: ColorPartLayout.spacing) {
                // The chevron and the lit name, as one press: a section header
                // opens on its title as well as on its arrow, and a 9pt glyph
                // on its own is a mean target for a control you use as often
                // as this one.
                foldControl
                // The colour is NOT here. It is a setting of the effect, so it
                // sits with the width and the position under the rule below,
                // and the header carries only the name, the eye and the two
                // controls that act on the whole entry (reported by the user on
                // 2026-09-07: the colour was the one setting in the wrong
                // place, and the only colour in the app that could not take a
                // saved name).
                accessory()
                Spacer(minLength: 0)
                if let reading { readingText(reading) }
                // The three things at the end of the row: a grip to put the
                // entry somewhere else in the order, the eye that stops it
                // drawing, and the cross that takes it out. The eye sits
                // BETWEEN them so the cross keeps the panel edge it has always
                // had, and so the two presses that mean opposite things — stop
                // it drawing, throw it away — are never the same target twice
                // running.
                if reorder != nil { grip }
                effectEye
                removeButton
            }
            .modifier(headerDrop)
            if let note {
                // On the panel's margin, the same as the Appearance list above
                // it: a note padded in under the row's NAME made a second left
                // edge inside the section, which is what the user reported on
                // 2026-09-08. It sits directly under the row it is about, one
                // gap below it and a pane gap above the next effect, so what it
                // belongs to is said by where it sits.
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isFolded {
                // Shown whether or not the effect is on. An effect that is
                // off keeps every number on it, and the reason you switched it
                // off is usually that you are about to change one of them, so
                // the settings stay open and stay live and only say quietly, by
                // being a shade fainter, that nothing they describe is on the
                // canvas right now.
                OwnedSettings(owner: title) { settings() }
                    // Flattened BEFORE it is faded. Without the group SwiftUI
                    // fades each child on its own, and the colour well is a
                    // solid swatch drawn over a checkerboard that says "this
                    // paint has alpha": fade them separately and the checker
                    // comes up through the swatch, so a switched-off border
                    // claimed its colour was half transparent (seen in a probe
                    // capture, 2026-09-08).
                    .compositingGroup()
                    .opacity(isOn || isMixed ? 1 : PanelSectionLook.EffectRow.offSettingsOpacity)
            }
        }
        // On every scroll tick, and deliberately not through @State: the panel
        // writes it into a plain box and reads it back only when a reveal is
        // waiting, so remembering where this pane is costs nothing to draw.
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(inspectorDockSpace))
        } action: { onFrame?($0) }
        // Named twice: the word a person reads, and the steady name a walk
        // writes when it wants to survive that word changing. The row that
        // reads Border today read Outline last week and broke thirteen walks
        // doing it (`PlaytestSteadyName`).
        .playtestField(title, steady: steadyNames)
        .panelStartProbe(.row, owner: title)
        // The same moves the grip, the eye and the cross make, for a hand that
        // is not going to drag a 20pt strip: a pointer that right clicks, and
        // a screen reader. It is also the only way a scripted walk can reorder,
        // since a synthesized press cannot start a SwiftUI drag.
        .contextMenu { rowMenu }
        .offset(y: carry)
        .zIndex(carry == 0 ? 0 : 1)
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { new in
                    blockHeight = new
                    report(new)
                }
        }
        // A fold always changes the height, so this is belt and braces — but
        // the dock's floor turns on `isOpen`, and a floor that lagged a fold by
        // a frame is the same cut slider one frame later.
        .onChange(of: isFolded) { report(blockHeight) }
    }

    private func report(_ height: CGFloat) {
        onExtent?(DockHeightBudget.Block(height: height, isOpen: !isFolded))
    }

    // MARK: The things a list row can do

    @ViewBuilder private var rowMenu: some View {
        if let reorder {
            Button("Move Up") { reorder.move(reorder.index - 1) }
                .disabled(!reorder.canMove(reorder.index - 1))
            Button("Move Down") { reorder.move(reorder.index + 1) }
                .disabled(!reorder.canMove(reorder.index + 1))
            Divider()
        }
        Button("Remove", action: remove)
    }

    private var grip: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10))
            .foregroundStyle(carry == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .frame(height: ColorPartLayout.rowHeight)
            .panelEdgeIcon("reorder", of: title)
            .contentShape(Rectangle())
            .panelHelp("Drag to change what paints over what")
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { carry = $0.translation.height }
                    .onEnded { value in
                        defer { carry = 0 }
                        guard blockHeight > 1, let reorder else { return }
                        let steps = Int((value.translation.height / blockHeight).rounded())
                        reorder.move(reorder.index + steps)
                    }
            )
            .playtestControl("Reorder", detail: "drag to change the paint order")
    }

    private var removeButton: some View {
        Button(action: remove) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .frame(height: ColorPartLayout.rowHeight)
                .panelEdgeIcon("remove", of: title)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
        .panelHelp("Remove this \(kindWord)")
        .playtestControl("Remove", detail: "takes the effect out of the list")
    }

    /// The mock's `.emeta`: quiet, after the name, never wrapping.
    private func readingText(_ reading: String) -> some View {
        Text(reading)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .frame(minHeight: ColorPartLayout.rowHeight)
            .panelReadout(reading)
            .playtestField("\(title) reading")
    }

    // MARK: The heading

    /// The chevron and the name, as one control.
    ///
    /// The chevron sits in the column the tick used to hold, centred on
    /// `ColorPartLayout.tickCenter`, because that is where `OwnedSettings`
    /// hangs the rule that marks this effect's settings: the rule now hangs
    /// from the chevron that folds them, which is a better sentence than the
    /// one it replaced.
    private var foldControl: some View {
        Button {
            withAnimation(.spring(duration: 0.2)) { toggleFold() }
        } label: {
            HStack(alignment: .top, spacing: ColorPartLayout.spacing) {
                PanelFoldChevron(isFolded: isFolded)
                Text(title)
                    .font(PanelSectionLook.EffectRow.titleFont)
                    // Lit when it is on, quiet when it is not, so a
                    // switched-off effect reads as off from the name as well as
                    // from the eye at the other end of the row.
                    .foregroundStyle(isOn || isMixed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    // At least the label column, so a short name lines its
                    // settings up with every other row; a longer one
                    // ("Noise reduction") takes the room it needs rather
                    // than being cut.
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: ColorPartLayout.labelWidth,
                           minHeight: ColorPartLayout.rowHeight,
                           maxHeight: ColorPartLayout.rowHeight, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .panelHelp(isFolded ? "Show this \(kindWord)'s settings" : "Hide this \(kindWord)'s settings")
        .accessibilityLabel(title)
        .accessibilityValue(isFolded ? "settings hidden" : "settings showing")
        // The same word the layers list uses for the chevron on a group, so a
        // scripted walk folds an effect the way it opens a group, and so the
        // one gesture has one name across the app.
        .playtestControl("Twist", detail: isFolded ? "shut" : "open")
    }

    // MARK: The eye

    /// Whether this effect is on. Mixed reads as off, because a Mac has no
    /// third eye and the row says "mixed" in words beneath itself.
    private var isShowing: Bool { isMixed ? false : isOn }

    /// The switch, drawn as the eye a layer row wears: the same glyph pair, the
    /// same 11pt, the same tertiary tint when off, in the same shared slot down
    /// the panel's edge. Asked for by the user on 2026-09-08 — the app has one
    /// picture for "this is not showing" and an effect had a second one.
    private var effectEye: some View {
        Button {
            setOn(isMixed ? true : !isShowing)
        } label: {
            Image(systemName: isShowing ? "eye" : "eye.slash")
                .font(.system(size: 11))
                .foregroundStyle(isShowing ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(height: ColorPartLayout.rowHeight)
                .panelEdgeIcon("eye", of: title)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isMixed ? MixedLook.controlOpacity : 1)
        .panelHelp(switchHelp)
        .accessibilityLabel(isShowing ? "Hide \(title)" : "Show \(title)")
        // The row's own reading, not a bare on/off: over two shapes where only
        // one holds the effect the switch used to announce a flat "on" while
        // the line under it said "Applies to 1 of the 2 selected layers". A
        // screen reader hears the control, not the caption.
        .accessibilityValue(switchReading)
        // Still "Switch": it is the row's switch whatever it is drawn as, and
        // every scripted walk that compares a shape with and without an effect
        // reaches it by that word.
        .playtestControl("Switch", detail: switchReading)
    }
}
