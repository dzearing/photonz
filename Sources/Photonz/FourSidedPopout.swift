import PhotonzCore
import SwiftUI

/// The small control beside a one-number row, and the four numbers it opens.
///
/// Room inside a group's edges and the rounding of a box are the same question
/// asked twice: one number nearly always, four numbers once in a while. The
/// panel used to answer it by folding four more rows open underneath, which
/// cost about a hundred points of a panel that already does not fit its own
/// contents, and pushed whatever you came to the panel for off the bottom of it.
///
/// So the four open in a POPOUT instead. The row stays one row whether the
/// four are open or shut, the numbers arrive over the row they belong to, and
/// closing them is Escape or a click away. A panel is a place things live; a
/// popout is a place a thing happens: type 24 at the bottom, press Return, and
/// it is gone.
///
/// The four are laid out in the SHAPE they describe rather than as a list, so
/// nobody has to already carry the clockwise order to know which number is
/// which: the sides make a cross around a little box, and the corners sit at
/// the four corners of a square.
///
/// This is the pattern, not one control: three rows use it (`Padding` in the
/// Layout section, `Corner Radius` under Appearance, and a room knob on a copy
/// of a component), and the next number that turns out to have four of
/// something should reach for it rather than build a fifth grid of boxes.
struct FourSidedPopout: View {
    /// What the row is called, so the popout says what it is about.
    let heading: String
    /// Which four these are, which decides how they are arranged.
    let shape: Shape
    /// The four, in the order the shape draws them: clockwise from the top for
    /// sides, clockwise from the top left for corners.
    let numbers: [Number]

    /// Which four, and the picture they make.
    enum Shape {
        /// Top, right, bottom, left: a cross around a box.
        case sides
        /// Top left, top right, bottom right, bottom left: the corners of a square.
        case corners
    }

    /// One of the four: what it is called, what it reads, and where it goes.
    struct Number: Identifiable {
        /// What the field answers to by name, which is also its label under the
        /// box and what a walk focuses.
        let title: String
        let help: String
        /// The number, or nil where the things picked do not agree on one.
        let value: CGFloat?
        let commit: (CGFloat) -> Void
        /// Whether this number is the thing's OWN, or one it is still taking
        /// from somewhere else. Only a copy of a component has the second kind:
        /// a side it never typed in goes on following the original, and it says
        /// so by reading one step quieter than the sides it owns.
        var isOwn = true
        /// Puts this one number back to where it was following, for the rows
        /// where one number can be handed back on its own. Nil everywhere else,
        /// and the popout then shows no way back at all.
        var handBack: (() -> Void)?

        var id: String { title }
    }

    /// How wide one number's box is: the same box every other typed number in
    /// the dock uses, so the four here are not a second size of field.
    private static let boxWidth: CGFloat = 62

    /// How wide the SLOT one number sits in: the box, plus whatever its own
    /// word needs beside it, plus the way back where there is one.
    ///
    /// "Bottom Right" is 63 points at this size and the box is 62, so the
    /// corners get a slot a little wider than their boxes and the two words
    /// along the bottom keep a gap between them; the sides are all short words
    /// and sit in the box's own width.
    private var slotWidth: CGFloat {
        let box = switch shape {
        case .sides: Self.boxWidth
        case .corners: CGFloat(70)
        }
        // The way back lives beside the number it puts back, so the slot has to
        // hold it. The room is kept whether or not this particular side has
        // anything to hand back, so the little cross does not jump sideways the
        // moment somebody types in it.
        return box + (offersAWayBack ? Self.wayBackWidth : 0)
    }

    /// Whether ANY of the four can be handed back on its own, which is what
    /// puts the arrow column in the picture at all. A row whose four numbers
    /// are simply its own — the canvas Padding row, Corner Radius — shows none
    /// of it and is exactly the popout it always was.
    private var offersAWayBack: Bool { numbers.contains { $0.handBack != nil } }

    /// How much room the way back takes beside a number.
    private static let wayBackWidth: CGFloat = 20
    /// The narrowest the popout is allowed to get. It otherwise takes the width
    /// its own four boxes need, rather than a number written down here that a
    /// change of field width could quietly start clipping; the floor is only so
    /// that the corners, which make a narrower picture than the sides, do not
    /// come out as a cramped little square.
    private static let minWidth: CGFloat = 178

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Text(heading)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            switch shape {
            case .sides: sides
            case .corners: corners
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: Self.minWidth)
        .fixedSize()
    }

    /// Top above, left and right either side of the box they keep clear, bottom
    /// below. The shape a person already draws on a whiteboard when they are
    /// explaining what padding is.
    @ViewBuilder private var sides: some View {
        VStack(spacing: 6) {
            box(0)
            HStack(spacing: 8) {
                box(3)
                Image(systemName: "square.dashed")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                box(1)
            }
            box(2)
        }
    }

    /// The four corners where the four corners are.
    @ViewBuilder private var corners: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) { box(0); box(1) }
            HStack(spacing: 8) { box(3); box(2) }
        }
    }

    /// One number, with its own word under it. The word is small and quiet
    /// because the position has already said which one it is; it is there for
    /// the reading that is not a glance.
    @ViewBuilder private func box(_ index: Int) -> some View {
        if numbers.indices.contains(index) {
            let number = numbers[index]
            VStack(spacing: 1) {
                HStack(spacing: 2) {
                    PanelNumberField(
                        showing: NumberBox.showing(
                            number.value,
                            standingIn: FourSidedNumber.standIn(uniform: number.value)),
                        label: number.title,
                        width: .fitting(least: 62, most: 148),
                        floor: 0,
                        wholeNumbers: true,
                        help: number.help,
                        isFollowing: !number.isOwn,
                        land: { number.commit($0); return nil }
                    )
                    .playtestField(number.title)
                    if offersAWayBack { wayBack(number) }
                }
                Text(number.title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityHidden(true)
            }
            .frame(width: slotWidth)
        }
    }

    /// The way back for ONE number: the same arrow the knob's own row wears,
    /// put beside the number it puts back.
    ///
    /// It only exists for a number that has something to hand back, so it is
    /// kept in the layout and drawn away rather than removed: a cross that
    /// re-centred itself every time somebody typed in it would be a cross that
    /// moved under the pointer.
    @ViewBuilder private func wayBack(_ number: Number) -> some View {
        let offered = number.handBack != nil && number.isOwn
        let arrow = Button { number.handBack?() } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.caption2.weight(.semibold))
                .frame(width: 18, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .opacity(offered ? 1 : 0)
        .disabled(!offered)
        .panelHelp("Follow the original again for the \(number.title.lowercased()) side")
        // Named only while it is there to press, so a walk claiming it is not
        // there yet is claiming what a person sees rather than finding an
        // invisible button that is always in the tree.
        if offered {
            arrow.playtestControl("Follow again \(number.title)",
                                  detail: "one side of a copy's room")
        } else {
            arrow
        }
    }
}

/// The little control beside the number that opens its four.
///
/// A chevron, because that is what the app already draws in front of anything
/// that opens, and because the thing it opens is the number's own detail rather
/// than a menu of other numbers. It sits AFTER the box rather than before the
/// word: the box is where the eye is when the one number turns out not to be
/// enough.
struct FourSidedButton<Popout: View>: View {
    @Binding var isOpen: Bool
    let help: String
    /// What a walk calls it, kept the same as the twist it replaces so the
    /// walks that already press it go on meaning what they meant.
    let control: String
    let detail: String
    @ViewBuilder let popout: () -> Popout

    var body: some View {
        Button { isOpen.toggle() } label: {
            // The glyph stays small — it is a hint beside a number, not a
            // button competing with it — but what you can HIT is the whole
            // height of the row it sits on. A 14 point target on its own is a
            // mean thing to ask a hand for, and this one no longer shares a
            // press with the row's name the way the twist it replaces did.
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isOpen ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 18, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .panelHelp(help)
        .playtestControl(control, detail: detail)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) { popout() }
    }
}
