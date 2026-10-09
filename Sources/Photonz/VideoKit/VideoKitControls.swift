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

    // The segmented control is not a kit piece any more: it is the app's one
    // `SegmentedControl` (Sources/Photonz/DesignSystem), used by every surface.

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
        /// What the value is drawn in, when not the ink: the word Mixed wears
        /// `MixedLook.style`, the strength every other control says it at.
        var valueStyle: AnyShapeStyle?
        /// The chevron and nothing else, for a list that hangs off something
        /// that is not a dropdown: the preset sizes at the end of the Size
        /// box. The value is still the button's title, so a walk reads it.
        var isBare = false
        /// The component mark in front of the value: the variants mock's
        /// main-component field (`ui-variants.html`, `.select.comp`).
        var showsComponentMark = false
        /// A picture in front of the value, drawn in the face's own ink: the
        /// icon a copy's Icon field shows before its name (`ui-variants.html`,
        /// `#iconTrigger`). A template, so it reads in light and dark alike.
        var leadImage: NSImage?
        /// The chevron at the end. Down for a list; right for a field that
        /// takes you somewhere, as the variants mock's main-component field does.
        var chevron = "chevron.down"

        @State private var isHovering = false

        var body: some View {
            if isBare { bareBody } else { faceBody }
        }

        private var bareBody: some View {
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isOpen || isHovering ? AnyShapeStyle(Palette.accent)
                                                      : AnyShapeStyle(Palette.faint))
                .frame(width: 16, height: size == .small ? Metrics.controlSmall : Metrics.control)
                .contentShape(Rectangle())
                .kitHover(value) { isHovering = $0 }
        }

        private var faceBody: some View {
            let radius: CGFloat = size == .small ? 6 : 8
            return HStack(spacing: 8) {
                HStack(spacing: 7) {
                    if let swatch {
                        RoundedRectangle(cornerRadius: 4).fill(swatch).frame(width: 14, height: 14)
                    }
                    if showsComponentMark {
                        VideoKit.ComponentMarkShape().fill(Palette.comp).frame(width: 11, height: 11)
                    }
                    if let leadImage {
                        Image(nsImage: leadImage)
                            .renderingMode(.template)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 14, height: 14)
                            .foregroundStyle(valueStyle ?? AnyShapeStyle(Palette.ink))
                    }
                    Text(value)
                        .font(.system(size: size == .small ? 11 : 11.5, weight: .medium))
                        .foregroundStyle(valueStyle ?? AnyShapeStyle(Palette.ink))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                Image(systemName: chevron)
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

        /// Whether a value is drawn in full in a face this wide, or cut with an
        /// ellipsis. The same sums the body does: the words, the padding either
        /// side, the chevron, and the 8pt gap the stack puts on BOTH sides of
        /// the spacer between them, which is 16 even when the spacer is 0.
        @MainActor static func fits(_ value: String, swatch: Bool = false, size: Size = .small,
                                    in width: CGFloat) -> Bool {
            let font = NSFont.systemFont(ofSize: size == .small ? 11 : 11.5, weight: .medium)
            let words = (value as NSString).size(withAttributes: [.font: font]).width
            let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .bold))?.size.width ?? 8
            let padding: CGFloat = size == .small ? 8 : 10
            let room = width - 2 * padding - 16 - chevron - (swatch ? 14 + 7 : 0)
            return words.rounded(.up) <= room
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
        /// The app is asking for this list open (`Dropdown.opensWhenAsked`).
        var opensWhenAsked: Bool
        var opened: @MainActor () -> Void

        init(label: String, value: String, swatch: AnyShapeStyle? = nil, size: SelectFace.Size = .small,
             choices: [Choice], opensWhenAsked: Bool = false, opened: @escaping @MainActor () -> Void = {}) {
            self.label = label
            self.value = value
            self.swatch = swatch
            self.size = size
            self.choices = choices
            self.opensWhenAsked = opensWhenAsked
            self.opened = opened
        }

        var body: some View {
            FieldRow(label: label) {
                Dropdown(label: label, value: value, swatch: swatch, size: size, choices: choices,
                         opensWhenAsked: opensWhenAsked, opened: opened)
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
        /// What resting the pointer on the row says.
        var help: String?
        var action: @MainActor () -> Void = {}

        static func item(_ title: String, isOn: Bool = false, isEnabled: Bool = true,
                         image: NSImage? = nil, help: String? = nil,
                         action: @escaping @MainActor () -> Void) -> Choice {
            Choice(kind: .item, title: title, isOn: isOn, isEnabled: isEnabled, image: image, help: help,
                   action: action)
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
        /// What the value is drawn in, when not the ink (`SelectFace`).
        var valueStyle: AnyShapeStyle?
        /// What resting the pointer on it says. On the button itself: a
        /// SwiftUI `.help` around an AppKit view does not reach it.
        var help: String?
        /// Just the chevron (`SelectFace.isBare`).
        var isBare = false
        /// The component's own face: its mark in front and its colour on the
        /// edge (`SelectFace.showsComponentMark`, `isComponent`).
        var isComponent = false
        /// The chevron the face ends in (`SelectFace.chevron`).
        var chevron = "chevron.down"
        /// A picture in front of the value (`SelectFace.leadImage`).
        var leadImage: NSImage?
        let choices: [Choice]
        /// The app is asking for this list open, the way ⌘R asks for the
        /// Speed list (`EditorState+SpeedKey`). It opens once the dropdown is
        /// in a window and the panel has settled round it, then `opened` says
        /// so, so the ask is answered once.
        var opensWhenAsked = false
        var opened: @MainActor () -> Void = {}

        init(label: String, value: String, swatch: AnyShapeStyle? = nil, size: SelectFace.Size = .small,
             valueStyle: AnyShapeStyle? = nil, help: String? = nil, isBare: Bool = false,
             isComponent: Bool = false, chevron: String = "chevron.down", leadImage: NSImage? = nil,
             choices: [Choice], opensWhenAsked: Bool = false, opened: @escaping @MainActor () -> Void = {}) {
            self.label = label
            self.value = value
            self.swatch = swatch
            self.size = size
            self.valueStyle = valueStyle
            self.help = help
            self.isBare = isBare
            self.isComponent = isComponent
            self.chevron = chevron
            self.leadImage = leadImage
            self.choices = choices
            self.opensWhenAsked = opensWhenAsked
            self.opened = opened
        }

        private var face: SelectFace {
            SelectFace(value: value, swatch: swatch, size: size, isComponent: isComponent,
                       valueStyle: valueStyle, isBare: isBare, showsComponentMark: isComponent,
                       leadImage: leadImage, chevron: chevron)
        }

        func makeNSView(context: Context) -> DropdownButton {
            let button = DropdownButton(face: face)
            button.update(label: label, value: value, radius: size == .small ? 6 : 8, choices: choices)
            button.toolTip = help
            enable(button, context.environment.isEnabled)
            button.open(whenAsked: opensWhenAsked, opened: opened)
            return button
        }

        /// A `.disabled` around it reaches the AppKit button, which SwiftUI
        /// does not do for a view it did not build: dimmed, and its menu shut.
        private func enable(_ button: DropdownButton, _ isEnabled: Bool) {
            guard button.isEnabled != isEnabled else { return }
            button.isEnabled = isEnabled
            button.alphaValue = isEnabled ? 1 : 0.45
        }

        func updateNSView(_ button: DropdownButton, context: Context) {
            button.face = face
            button.update(label: label, value: value, radius: size == .small ? 6 : 8, choices: choices)
            if button.toolTip != help { button.toolTip = help }
            enable(button, context.environment.isEnabled)
            button.open(whenAsked: opensWhenAsked, opened: opened)
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsView button: DropdownButton,
                          context: Context) -> CGSize? {
            let fitting = button.host.intrinsicContentSize
            let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? fitting.width
            return CGSize(width: width, height: fitting.height)
        }
    }

    /// A dropdown whose list opens in a popover rather than a menu: the same
    /// face as `Dropdown`, for a list a menu cannot be. Blending's paints each
    /// mode on the canvas while the pointer rests on it, which an `NSMenu`
    /// never does. Until 2026-10-05 those rows drew the system pop-up's up and
    /// down arrows by hand, right under the Text section's drawn dropdowns.
    ///
    /// The whole face is the button, so a click anywhere a person can see it
    /// opens the list, and its edge goes accent while the list is up.
    struct ListDropdown<List: View>: View {
        let value: String
        /// What the value is drawn in, when not the ink (`SelectFace`).
        var valueStyle: AnyShapeStyle?
        @Binding var isOpen: Bool
        /// Run just before the list opens, to note what was true before it.
        var willOpen: () -> Void = {}
        @ViewBuilder let list: () -> List

        var body: some View {
            Button {
                willOpen()
                isOpen = true
            } label: {
                SelectFace(value: value, size: .small, isOpen: isOpen, valueStyle: valueStyle)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isOpen, arrowEdge: .bottom) { list() }
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
        /// An ask to open is on its way, so a redraw while it waits does not
        /// queue a second one.
        private var openAsked = false

        /// The dropdowns a walk is holding open, by label: a walk never puts
        /// a menu on screen, since an open menu takes every key on the Mac,
        /// so an ask to open shows the open face and is recorded here instead
        /// (`PlaytestCondition.panelMenuOpen`).
        private static var heldOpenForAWalk: [String: WeakDropdown] = [:]

        /// Set by a walk as it starts. The kit cannot ask the app whether a
        /// walk is driving it, so the walk tells the kit.
        static var holdsOpenInsteadOfShowing = false

        private struct WeakDropdown { weak var button: DropdownButton? }

        /// Whether a walk is holding the dropdown called `label` open.
        static func isHeldOpenForAWalk(_ label: String) -> Bool {
            heldOpenForAWalk[label]?.button?.isOpen == true
        }

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
            if Self.heldOpenForAWalk[accessibilityLabel() ?? ""]?.button === self {
                isOpen = false
                Self.heldOpenForAWalk[accessibilityLabel() ?? ""] = nil
            }
            actions[item.tag]()
        }

        /// Open when the app asks, once per ask. A beat late on purpose: the
        /// ask may have just opened a folded section or brought the panel
        /// out, and the list hangs from the face, so it waits for the face to
        /// have stopped moving.
        func open(whenAsked asked: Bool, opened: @escaping @MainActor () -> Void) {
            guard asked else { openAsked = false; return }
            guard !openAsked else { return }
            openAsked = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                // A dropdown the panel rebuilt in the meantime leaves the ask
                // to the one that replaced it.
                guard let self, self.openAsked else { return }
                self.openAsked = false
                guard self.window != nil else { return }
                // Answered before the menu opens: an open menu holds this
                // thread until it shuts.
                opened()
                if Self.holdsOpenInsteadOfShowing {
                    self.isOpen = true
                    Self.heldOpenForAWalk[self.accessibilityLabel() ?? ""] = WeakDropdown(button: self)
                } else {
                    self.openMenu()
                }
            }
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

        /// None. A pop-up button reports the inset of the bezel it would draw,
        /// and SwiftUI lines up that inset rather than the frame, so every
        /// dropdown in the panel stood 4pt left of the column the sliders and
        /// boxes under it start on (seen 2026-10-05 beside Blending, whose
        /// face is drawn by SwiftUI). This button draws no bezel: its frame is
        /// its face.
        override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

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

extension VideoKit {

    /// The four-diamond mark a component wears, drawn by the kit itself so a
    /// kit control can carry it and the kit still stands on its own. The app's
    /// own `ComponentGlyph` draws the same path.
    struct ComponentMarkShape: Shape {
        func path(in rect: CGRect) -> Path { Path(VideoKit.componentMarkPath(in: rect)) }
    }

    static func componentMarkPath(in rect: CGRect) -> CGPath {
        let side = min(rect.width, rect.height)
        let radius = side * 0.22
        let reach = side * 0.28
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let path = CGMutablePath()
        for offset in [CGPoint(x: 0, y: -reach), CGPoint(x: 0, y: reach),
                       CGPoint(x: -reach, y: 0), CGPoint(x: reach, y: 0)] {
            let point = CGPoint(x: center.x + offset.x, y: center.y + offset.y)
            path.move(to: CGPoint(x: point.x, y: point.y - radius))
            path.addLine(to: CGPoint(x: point.x + radius, y: point.y))
            path.addLine(to: CGPoint(x: point.x, y: point.y + radius))
            path.addLine(to: CGPoint(x: point.x - radius, y: point.y))
            path.closeSubpath()
        }
        return path
    }
}
