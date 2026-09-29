import AppKit
import SwiftUI

// MARK: - The key diamond

extension VideoKit {
    /// Where a property stands at the playhead, as its diamond says it.
    enum KeyState {
        /// Not animated. A dim outline, the quietest thing in the row.
        case dormant
        /// Animated, with no key on this frame. An outline in the key colour.
        case armed
        /// A key on this very frame. Filled.
        case onKey
    }

    /// The key diamond (`video.html` `.kfkey`): an 11pt diamond in a 16pt box.
    /// Three states told apart by weight alone, so the column of them down a
    /// panel reads "what is animating, and what is keyed here" at a glance.
    ///
    /// Drawing only; the caller wraps it in its own button, because what a
    /// click does (set a key, clear one, start animating) is the caller's.
    struct KeyDiamond: View {
        let state: KeyState
        var isHovering = false

        var body: some View {
            ZStack {
                Rectangle()
                    .fill(state == .onKey ? AnyShapeStyle(Palette.comp) : AnyShapeStyle(Color.clear))
                Rectangle()
                    .strokeBorder(stroke, lineWidth: 1.5)
            }
            // 11pt, not 8: the mock's 8px box is content-box with a 1.5px
            // border outside it, so what you see is 11px across.
            .frame(width: 11, height: 11)
            .rotationEffect(.degrees(45))
            .frame(width: 16, height: 16)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? AnyShapeStyle(Palette.panel2) : AnyShapeStyle(Color.clear)))
            .contentShape(Rectangle())
        }

        private var stroke: AnyShapeStyle {
            switch state {
            case .dormant: isHovering ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Palette.lineStrong)
            case .armed, .onKey: AnyShapeStyle(Palette.comp)
            }
        }
    }
}

// MARK: - A labelled row, and the dropdown that goes in one

extension VideoKit {
    /// A panel row (`inspector.css` `.irow`): a short label in a 76pt column
    /// and the control taking the rest. A label, never a sentence.
    ///
    /// The one row every section of the panel draws (`PanelFieldRow`), so a
    /// control too wide to sit beside its name drops under it here too. Until
    /// 2026-09-27 this row could not: the Sound section's Gain track and box
    /// needed 212pt beside a 192pt row in the narrowest dock, and the whole
    /// panel grew 19.5pt past its dock whenever a clip was picked.
    struct FieldRow<Control: View>: View {
        let label: String
        @ViewBuilder let control: Control

        var body: some View {
            PanelFieldRow(label) {
                control
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// A segmented control that fills its row (`segmented.css`, `.seg.fill.sm`):
    /// a capsule track, equal columns, and one raised plate that slides to the
    /// picked segment rather than blinking between two.
    ///
    /// It exists because the system's segmented control cannot shrink below
    /// its own words: three caption styles came out 1.5pt wider than the panel
    /// has, and the dock centres a section that will not fit, so every section
    /// slid out past both of the panel's edges (2026-09-24). Here the columns
    /// share whatever width the row has, and when their words will not all
    /// fit whole the bar becomes a dropdown, which is what the mock's `.seg`
    /// asks for. Two to four short options; more than that is a dropdown.
    struct Segmented<Value: Hashable>: View {
        let options: [(value: Value, title: String)]
        let selection: Value?
        let pick: (Value) -> Void

        @Namespace private var plate

        var body: some View {
            // Every label whole on one row, or a dropdown: the mock's rule for
            // `.seg` is that a bar whose words do not fit is the wrong control
            // for that space. A narrowed dock gets the dropdown.
            ViewThatFits(in: .horizontal) {
                bar
                Dropdown(label: options.first { $0.value == selection }?.title ?? "",
                         value: options.first { $0.value == selection }?.title ?? "",
                         choices: options.map { option in
                             .item(option.title, isOn: option.value == selection) { pick(option.value) }
                         })
            }
        }

        private var bar: some View {
            SegmentColumns(spacing: 2) {
                ForEach(options, id: \.value) { option in
                    let isOn = option.value == selection
                    Button {
                        pick(option.value)
                    } label: {
                        Text(option.title)
                            .font(.system(size: 11, weight: isOn ? .semibold : .medium))
                            .foregroundStyle(isOn ? Palette.ink : Palette.dim)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            // 6 where the mock's `.seg.sm` says 8, so Bottom,
                            // Middle and Top fit whole beside a row label at
                            // the dock's default width.
                            .padding(.horizontal, 6)
                            // The whole column, so the plate is the segment's
                            // width and not its word's once the bar has room
                            // to spare (a full-width Path read as a pill round
                            // "Straight" beside a wide empty "Curved").
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background {
                                if isOn {
                                    Capsule()
                                        .fill(Palette.raised)
                                        .overlay(Capsule().strokeBorder(Palette.edgeLo))
                                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                                        .matchedGeometryEffect(id: "plate", in: plate)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .kitControl(option.title, detail: isOn ? "on" : "off")
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(2)
            .frame(height: Metrics.controlSmall)
            .frame(minWidth: 0, maxWidth: .infinity)
            .background(Capsule().fill(Palette.glassThin))
            .overlay(Capsule().strokeBorder(Palette.edgeLo))
            .animation(.spring(duration: 0.24), value: selection)
        }
    }

    /// The columns of a `Segmented`: each segment its own width, and what the
    /// row has over is shared out equally, so the plate is never a sliver
    /// beside a wide neighbour. Short of room, every segment gives up the same
    /// share of its width and its label is cut short, so no one word is
    /// sacrificed for the others while there is room for all of them.
    struct SegmentColumns: Layout {
        var spacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let natural = widths(subviews)
            let gaps = spacing * CGFloat(max(0, subviews.count - 1))
            let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            let width = proposal.width ?? (natural.reduce(0, +) + gaps)
            return CGSize(width: width, height: proposal.height ?? height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let natural = widths(subviews)
            guard !natural.isEmpty else { return }
            let gaps = spacing * CGFloat(natural.count - 1)
            let room = max(0, bounds.width - gaps)
            let total = natural.reduce(0, +)
            let sized: [CGFloat] = total <= room
                ? natural.map { $0 + (room - total) / CGFloat(natural.count) }
                : natural.map { total > 0 ? $0 * room / total : room / CGFloat(natural.count) }
            var x = bounds.minX
            for (index, subview) in subviews.enumerated() {
                subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                              proposal: ProposedViewSize(width: sized[index], height: bounds.height))
                x += sized[index] + spacing
            }
        }

        private func widths(_ subviews: Subviews) -> [CGFloat] {
            subviews.map { $0.sizeThatFits(.unspecified).width }
        }
    }

    /// A value you read rather than set (`.field .v`): the mock's filled box
    /// with the value in it, the same height as a small dropdown so a column
    /// of rows mixing the two lines up.
    struct ValueFace: View {
        let value: String
        var tint: AnyShapeStyle?

        var body: some View {
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(tint ?? AnyShapeStyle(Palette.ink))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .frame(height: Metrics.controlSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.panel))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line))
        }
    }

    /// The face of a dropdown (`.select`): the value, an optional swatch in
    /// front of it, a chevron at the end, on a raised panel-coloured button.
    /// `DropdownRow` puts it on a menu; this is split out so the same face can
    /// be drawn anywhere a menu cannot be (a snapshot, a disabled row).
    struct SelectFace: View {
        enum Size { case small, regular }

        let value: String
        var swatch: AnyShapeStyle?
        var size: Size = .regular
        /// A component's dropdown wears the component colour on its edge.
        var isComponent = false
        /// Its menu is up: the accent edge the mock's Open state wears
        /// (`comp-fields.html`, 05 Select).
        var isOpen = false

        @State private var isHovering = false

        var body: some View {
            let radius: CGFloat = size == .small ? 6 : 8
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    if let swatch {
                        RoundedRectangle(cornerRadius: 4).fill(swatch).frame(width: 14, height: 14)
                    }
                    Text(value)
                        .font(.system(size: size == .small ? 11 : 11.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, size == .small ? 8 : 10)
            .frame(height: size == .small ? Metrics.controlSmall : Metrics.control)
            .background(RoundedRectangle(cornerRadius: radius).fill(Palette.panel))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(borderStyle))
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .kitHover(value) { isHovering = $0 }
        }

        private var borderStyle: AnyShapeStyle {
            if isOpen { return AnyShapeStyle(Palette.accent) }
            if isHovering { return AnyShapeStyle(Palette.accent.opacity(0.45)) }
            return isComponent ? AnyShapeStyle(Palette.compLine) : AnyShapeStyle(Palette.line)
        }
    }

    /// A labelled dropdown: `FieldRow` with a `SelectFace` that opens a menu.
    /// A list of more than three exclusive choices is one of these, never a
    /// column of radio buttons.
    struct DropdownRow: View {
        let label: String
        let value: String
        var swatch: AnyShapeStyle?
        var size: SelectFace.Size = .small
        let choices: [Choice]

        init(label: String, value: String, swatch: AnyShapeStyle? = nil, size: SelectFace.Size = .small,
             choices: [Choice]) {
            self.label = label
            self.value = value
            self.swatch = swatch
            self.size = size
            self.choices = choices
        }

        var body: some View {
            FieldRow(label: label) {
                Dropdown(label: label, value: value, swatch: swatch, size: size, choices: choices)
            }
        }
    }

    /// One row of a dropdown's menu: a choice, a line between groups, or a
    /// group's heading.
    ///
    /// Rows are values rather than SwiftUI menu content because the dropdown
    /// builds its own AppKit menu (see `Dropdown`), and because a list of
    /// values is a list a test can read.
    struct Choice {
        enum Kind { case item, divider, heading }

        var kind: Kind
        var title: String
        /// Wears a checkmark: the value the dropdown is showing.
        var isOn = false
        /// Dimmed and unpickable when false.
        var isEnabled = true
        /// A small picture beside the words, for a row a word alone does not
        /// describe (a curve's shape). A menu row draws pictures, not views.
        var image: NSImage?
        var action: @MainActor () -> Void = {}

        static func item(_ title: String, isOn: Bool = false, isEnabled: Bool = true,
                         image: NSImage? = nil, action: @escaping @MainActor () -> Void) -> Choice {
            Choice(kind: .item, title: title, isOn: isOn, isEnabled: isEnabled, image: image, action: action)
        }

        static var divider: Choice { Choice(kind: .divider, title: "") }

        static func heading(_ title: String) -> Choice { Choice(kind: .heading, title: title) }
    }

    /// The dropdown on its own (`.select`), for a row that already has its
    /// word, or none.
    ///
    /// The face IS the button. It is a real AppKit pull-down button exactly the
    /// size of the face, with the drawn `SelectFace` inside it as its content,
    /// so a click anywhere a person can see the dropdown lands on it and opens
    /// its menu. Until 2026-09-28 the face was drawn by itself with a SwiftUI
    /// menu laid over it at 1% opacity to take the click; that menu was as
    /// wide as its own invisible title (37 of the Show row's 148 points), and
    /// AppKit handed clicks even inside it to the panel behind, so every
    /// dropdown in the panel was dead to the pointer while every walk that
    /// pressed it by name was green.
    ///
    /// It stays a pop-up button, with a blank first row the way a pull-down
    /// keeps its title, so a walk reads its value and its rows, and picks one,
    /// without putting the menu on screen.
    struct Dropdown: NSViewRepresentable {
        /// What accessibility calls it, and so what a walk reads it back by.
        let label: String
        let value: String
        var swatch: AnyShapeStyle?
        var size: SelectFace.Size = .small
        let choices: [Choice]

        init(label: String, value: String, swatch: AnyShapeStyle? = nil, size: SelectFace.Size = .small,
             choices: [Choice]) {
            self.label = label
            self.value = value
            self.swatch = swatch
            self.size = size
            self.choices = choices
        }

        private var face: SelectFace { SelectFace(value: value, swatch: swatch, size: size) }

        func makeNSView(context: Context) -> DropdownButton {
            let button = DropdownButton(face: face)
            button.update(label: label, value: value, radius: size == .small ? 6 : 8, choices: choices)
            return button
        }

        func updateNSView(_ button: DropdownButton, context: Context) {
            button.face = face
            button.update(label: label, value: value, radius: size == .small ? 6 : 8, choices: choices)
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsView button: DropdownButton,
                          context: Context) -> CGSize? {
            let fitting = button.host.intrinsicContentSize
            let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? fitting.width
            return CGSize(width: width, height: fitting.height)
        }
    }

    /// The AppKit half of `Dropdown`: a borderless pull-down that draws
    /// nothing of its own and carries the face inside it.
    final class DropdownButton: NSPopUpButton, NSMenuDelegate {
        let host: NSHostingView<SelectFace>
        /// The face as the row draws it; `isOpen` is laid on here.
        var face: SelectFace {
            didSet { showFace() }
        }
        private var isOpen = false {
            didSet { showFace() }
        }
        private var value = ""
        private var radius: CGFloat = 6
        private var actions: [@MainActor () -> Void] = []
        /// What the menu was last built from, so an update that changes
        /// nothing in it leaves the open menu alone.
        private var built: [String] = []

        init(face: SelectFace) {
            self.face = face
            host = NSHostingView(rootView: face)
            super.init(frame: .zero, pullsDown: true)
            cell = DropdownCell(textCell: "", pullsDown: true)
            isBordered = false
            focusRingType = .default
            // Its natural size is what the dropdown asks SwiftUI for; the
            // frame it gets is the button's, whatever the row gives it.
            host.sizingOptions = [.intrinsicContentSize]
            host.translatesAutoresizingMaskIntoConstraints = true
            host.autoresizingMask = [.width, .height]
            addSubview(host)
            menu = NSMenu()
            menu?.autoenablesItems = false
            menu?.delegate = self
        }

        private func showFace() {
            var shown = face
            shown.isOpen = isOpen
            host.rootView = shown
        }

        func menuWillOpen(_ menu: NSMenu) { isOpen = true }

        func menuDidClose(_ menu: NSMenu) { isOpen = false }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        func update(label: String, value: String, radius: CGFloat, choices: [Choice]) {
            self.value = value
            self.radius = radius
            setAccessibilityLabel(label)
            setAccessibilityValue(value)
            (cell as? NSPopUpButtonCell)?.usesItemFromMenu = false
            (cell as? NSPopUpButtonCell)?.menuItem = NSMenuItem(title: value, action: nil, keyEquivalent: "")
            actions = choices.map(\.action)
            let shape = choices.map { "\($0.kind)|\($0.title)|\($0.isOn)|\($0.isEnabled)|\($0.image.map { ObjectIdentifier($0).hashValue } ?? 0)" }
            guard shape != built, let menu else { return }
            built = shape
            menu.removeAllItems()
            // A pull-down's first row is its title and is never shown.
            let title = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            title.isHidden = true
            menu.addItem(title)
            for (index, choice) in choices.enumerated() {
                switch choice.kind {
                case .divider:
                    menu.addItem(.separator())
                case .heading:
                    menu.addItem(.sectionHeader(title: choice.title))
                case .item:
                    let item = NSMenuItem(title: choice.title, action: #selector(pick(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = index
                    item.state = choice.isOn ? .on : .off
                    item.isEnabled = choice.isEnabled
                    item.image = choice.image
                    menu.addItem(item)
                }
            }
        }

        @objc private func pick(_ item: NSMenuItem) {
            guard actions.indices.contains(item.tag) else { return }
            actions[item.tag]()
        }

        override var title: String {
            get { value }
            set { super.title = newValue }
        }

        override func layout() {
            super.layout()
            host.frame = bounds
        }

        /// Every point of the face is the button's, including the parts the
        /// face draws: the words, the swatch and the chevron.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard !isHidden, let superview else { return nil }
            return bounds.contains(convert(point, from: superview)) ? self : nil
        }

        override func draw(_ dirtyRect: NSRect) {}

        override var focusRingMaskBounds: NSRect { bounds }

        override func drawFocusRingMask() {
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        }

        /// Opens the menu the way the mock draws it (`comp-fields.html`, 05
        /// Select): hanging from the face's left edge, at least the face's
        /// width, just under it. AppKit's own pull-down lines its rows up with
        /// a title this button never draws, a dozen points in and narrower.
        private func openMenu() {
            guard let menu, isEnabled else { return }
            menu.minimumWidth = bounds.width
            let below = isFlipped ? bounds.maxY + 3 : bounds.minY - 3
            menu.popUp(positioning: nil, at: NSPoint(x: bounds.minX, y: below), in: self)
        }

        override func mouseDown(with event: NSEvent) { openMenu() }

        override func performClick(_ sender: Any?) { openMenu() }

        /// Return opens it as well as space, the way a person expects of a
        /// focused dropdown.
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 || event.keyCode == 76 || event.charactersIgnoringModifiers == " " {
                performClick(nil)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    /// Draws nothing: the face inside the button is the whole look.
    final class DropdownCell: NSPopUpButtonCell {

        override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {}
        override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {}
        override func drawBorderAndBackground(withFrame cellFrame: NSRect, in controlView: NSView) {}
    }
}

extension [VideoKit.Choice] {
    /// Every value in a list as a choice, the one that is `current` ticked.
    @MainActor static func picking<Value: Equatable>(_ values: [Value], current: Value?,
                                          title: (Value) -> String,
                                          isEnabled: (Value) -> Bool = { _ in true },
                                          pick: @escaping @MainActor (Value) -> Void) -> [VideoKit.Choice] {
        values.map { value in
            .item(title(value), isOn: value == current, isEnabled: isEnabled(value)) { pick(value) }
        }
    }
}
