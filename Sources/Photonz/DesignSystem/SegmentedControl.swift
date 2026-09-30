import AppKit
// The gallery script (`Scripts/segmented-gallery.swift`) compiles this file
// with the drag's own source beside it rather than as a module.
#if canImport(PhotonzCore)
import PhotonzCore
#endif
import SwiftUI

/// **The segmented control**: a small set of exclusive choices, all of them on
/// screen at once (`docs/design/mocks/pages/comp-segmented.html`,
/// `shared/components/segmented.css`).
///
/// The only segmented control in the app. Before it there were three: the
/// system's (`Picker` with `.segmented`, about forty of them across the panel,
/// the dialogs and the colour picker), a bare `NSSegmentedControl` for View |
/// Edit in the title bar, and a drawn one the video panel kept to itself.
/// The user turned down the title bar's on 2026-09-28 because it was not the
/// design system's, and the others were not either. `SegmentedControlUsageTests`
/// fails the build on a segmented control made any other way.
///
/// What the component page asks for, and where it is done here:
///
/// * **One look, everywhere.** A recessed capsule rail, darker than what it
///   sits on, with a hairline and a soft inner shadow, 2pt of padding, 2pt
///   between segments; capsule segments; ONE thumb under the picked segment,
///   a pane of the system's own Liquid Glass with nothing painted over it,
///   lighter than the rail. There is no style to pick: the history bar's
///   filter once lit its plate a solid blue, and the user, 2026-09-29: "I'm
///   seeing inconsistent segmented controls. What I'd like to see is the
///   system glass morph consistently." Only the size differs from place to
///   place.
/// * **Sizes.** 24, 28 (the default, and the only size the mocks' panels use)
///   and 32. The size sets the height and the type; the width always comes from
///   the words.
/// * **Forms.** `.fill` takes its container's width in equal columns, the form
///   inside a panel or a popover; `.natural` hugs its words. Pictures instead
///   of words are square segments, each named by its tooltip.
/// * **It never wraps.** When the words would have to be cut short, the
///   control becomes a dropdown holding the same choices. Pictures never do.
/// * **States.** Hovering an unpicked segment lifts its ink and lays a faint
///   glass behind it; pressing shrinks it to 97%; one option that cannot be
///   picked keeps its place, dimmed, and says why in its tooltip; the whole
///   control dims under `.disabled`. One tab stop, arrows move the pick and
///   stop at the ends, and the focus ring sits round the plate.
/// * **Changing the value.** The glass slides to the new segment and stops,
///   moved by SwiftUI's own animation of its frame on the system's smooth
///   curve (the page's 300ms), so the system reshapes the glass as it goes.
///   No overshoot, no bounce, never out of the rail (filmed by
///   `segmented-thumb-film-walk`). That curve is the thumb's ONLY animator: a
///   pick made inside another animation (View | Edit changes under
///   `.viewEditMode`) once flung a drawn thumb a whole segment out of its rail.
///   Grab the thumb and drag it and it follows the pointer, landing on the
///   nearest segment when let go. Under Reduce Motion it cross-fades instead;
///   under Increase Contrast or Reduce Transparency the system's glass turns
///   firmer by itself.
///
/// With the Next release's `next-designed-segmented` switch off, which is
/// always the case in Current, this is the system's segmented picker exactly as
/// each caller had it, so Current does not change.
struct SegmentedControl<Value: Hashable>: View {
    /// One choice.
    struct Option {
        var value: Value
        /// The word on the segment, and the name accessibility and a walk use
        /// for it even when the segment shows a picture instead.
        var title: String
        /// A picture in front of the word, or in place of it when the control
        /// `showsTitles` is false.
        var image: Image?
        /// What resting on it says. A picture segment without one says its title.
        var help: String?
        /// The key that picks it, printed quieter in its tooltip.
        var key: String?
        /// Set when this one cannot be picked right now: the segment keeps its
        /// place, dimmed, and its tooltip says this.
        var disabledReason: String?

        init(_ value: Value, _ title: String, image: Image? = nil, help: String? = nil,
             key: String? = nil, disabledReason: String? = nil) {
            self.value = value
            self.title = title
            self.image = image
            self.help = help
            self.key = key
            self.disabledReason = disabledReason
        }
    }

    /// `.seg.sm`, `.seg`, `.seg.lg`.
    enum Size {
        case small, regular, large

        var height: CGFloat {
            switch self {
            case .small: 24
            case .regular: 28
            case .large: 32
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: 11
            case .regular: 11.5
            case .large: 12.5
            }
        }

        /// Either side of a segment's words (`--gap-sm`, `--s3`, `--s4`).
        var padding: CGFloat {
            switch self {
            case .small: 8
            case .regular: 12
            case .large: 16
            }
        }
    }

    enum Form {
        /// Equal columns across the container (`.seg.fill`).
        case fill
        /// Each segment as wide as its words (`.seg`).
        case natural
    }

    let label: String
    let options: [Option]
    /// Nil lights nothing: the picked things disagree, or nothing is picked.
    let selection: Value?
    var size: Size = .regular
    var form: Form = .fill
    var showsTitles = true
    /// What the whole control's system help tag says with the designed control
    /// off, for a caller that had one (`segmentToolTips`' fallback).
    var systemHelp: String?
    /// Tooltips under the segments rather than over them, for a control at the
    /// very top of a window.
    var tipsBelow = false
    /// False for a control that was already drawn before the switch existed
    /// (the Library's scope, the video panel's rows): it stays drawn with the
    /// switch off too, because the system control is the thing it replaced.
    var fallsBackToSystem = true
    let pick: (Value) -> Void

    init(_ label: String, selection: Value?, options: [Option], size: Size = .regular,
         form: Form = .fill, showsTitles: Bool = true,
         systemHelp: String? = nil, tipsBelow: Bool = false, fallsBackToSystem: Bool = true,
         pick: @escaping (Value) -> Void) {
        self.label = label
        self.selection = selection
        self.options = options
        self.size = size
        self.form = form
        self.showsTitles = showsTitles
        self.systemHelp = systemHelp
        self.tipsBelow = tipsBelow
        self.fallsBackToSystem = fallsBackToSystem
        self.pick = pick
    }

    init(_ label: String, selection: Binding<Value>, options: [Option], size: Size = .regular,
         form: Form = .fill, showsTitles: Bool = true,
         systemHelp: String? = nil, tipsBelow: Bool = false) {
        self.init(label, selection: selection.wrappedValue, options: options, size: size,
                  form: form, showsTitles: showsTitles,
                  systemHelp: systemHelp, tipsBelow: tipsBelow) { selection.wrappedValue = $0 }
    }

    var body: some View {
        if Experiments.shared.designedSegmentedEnabled || !fallsBackToSystem {
            DesignedSegments(label: label, options: options, selection: selection, size: size,
                             form: form, showsTitles: showsTitles,
                             tipsBelow: tipsBelow, pick: pick)
        } else {
            systemPicker
        }
    }

    /// Current's control: the system picker, built the way every caller built
    /// it before this type existed.
    @ViewBuilder private var systemPicker: some View {
        let picker = Picker(label, selection: Binding<Value?>(
            get: { selection },
            set: { if let value = $0 { pick(value) } })) {
            ForEach(options.indices, id: \.self) { index in
                systemLabel(options[index]).tag(Value?.some(options[index].value))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        if let systemHelp {
            picker.segmentToolTips(options.map { $0.help ?? $0.title }, fallback: systemHelp)
        } else {
            picker
        }
    }

    @ViewBuilder private func systemLabel(_ option: Option) -> some View {
        if let image = option.image, !showsTitles {
            image
        } else {
            Text(option.title)
        }
    }
}

// MARK: - The drawn control

/// The row of segments, the space a thumb, a slot and a drag are measured in.
private let segmentedRowSpace = "segmented-row"

/// The drawn control. Internal rather than private so
/// `Scripts/segmented-gallery.swift` can draw each state beside the mock.
struct DesignedSegments<Value: Hashable>: View {
    typealias Option = SegmentedControl<Value>.Option

    let label: String
    let options: [Option]
    let selection: Value?
    let size: SegmentedControl<Value>.Size
    let form: SegmentedControl<Value>.Form
    let showsTitles: Bool
    let tipsBelow: Bool
    let pick: (Value) -> Void
    /// For the gallery only: draw this segment hovered, and the focus ring
    /// on, without a pointer or a keyboard.
    var shownHovered: Int?
    var shownFocused = false

    init(label: String, options: [Option], selection: Value?, size: SegmentedControl<Value>.Size,
         form: SegmentedControl<Value>.Form, showsTitles: Bool, tipsBelow: Bool,
         shownHovered: Int? = nil, shownFocused: Bool = false, pick: @escaping (Value) -> Void) {
        self.label = label
        self.options = options
        self.selection = selection
        self.size = size
        self.form = form
        self.showsTitles = showsTitles
        self.tipsBelow = tipsBelow
        self.shownHovered = shownHovered
        self.shownFocused = shownFocused
        self.pick = pick
    }

    @State private var pointerOver: Int?
    private var hovered: Int? { pointerOver ?? shownHovered }
    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    /// Every segment's box in the row, where the glass is placed and what a
    /// drag is measured against.
    @State private var slots: [Int: CGRect] = [:]
    /// A drag of the thumb under way: where its middle is, and how far from
    /// its middle the hand took hold.
    @State private var dragCenter: CGFloat?
    @State private var grabOffset: CGFloat = 0
    /// A drag that began off the thumb belongs to the segment it began on.
    @State private var dragIgnored = false
    @State private var rowWidth: CGFloat = 0

    private typealias Palette = VideoKit.Palette

    var body: some View {
        Group {
            if showsTitles {
                // Every word whole on one row, or a dropdown of the same
                // choices: a bar whose words do not fit is the wrong control
                // for the room, and a wrapped or cut-short one reads as broken.
                ViewThatFits(in: .horizontal) {
                    bar
                    collapsed
                }
            } else {
                bar
            }
        }
        .opacity(isEnabled ? 1 : 0.42)
    }

    /// Either side of a segment's words. The fill form is the one a panel, a
    /// dock or a popover uses, and there the words only claim the least room
    /// they can stand in: the columns share out whatever the row has on top,
    /// which at a dock's usual width is more than the mock's
    /// `calc(var(--s2) - 1px)`. So a tight row (Arrangement with Mixed beside
    /// its word) keeps its bar of words, and only a row too narrow for the
    /// words themselves becomes a dropdown.
    private var wordPadding: CGFloat {
        form == .fill ? 3 : size.padding
    }

    private var pickedIndex: Int? { options.firstIndex { $0.value == selection } }

    private var bar: some View {
        SegmentColumnsLayout(form: form, spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                segment(index)
            }
        }
        .coordinateSpace(.named(segmentedRowSpace))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .background(alignment: .topLeading) { thumb }
        .simultaneousGesture(thumbDrag)
        .padding(2)
        .frame(height: size.height)
        .frame(minWidth: 0, maxWidth: form == .fill ? .infinity : nil)
        // The recessed rail: darker than what it sits on, pressed in.
        .background(Capsule().fill(Palette.segRail.shadow(
            .inner(color: Palette.segRailInset.color(scheme), radius: 1, y: 1))))
        .overlay(Capsule().strokeBorder(Palette.edgeLo).allowsHitTesting(false))
        .focusable(interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    /// The system glass's one curve: the component page's 300ms, with no
    /// bounce, so the glass stops where it lands.
    private static var glassCurve: Animation { .smooth(duration: 0.3) }

    /// Under Reduce Motion the glass does not travel: it fades out where it
    /// was as it fades in on the new segment.
    private static var fadeCurve: Animation { .easeInOut(duration: 0.14) }

    /// Where the glass is: under the hand during a drag, else on the picked
    /// segment. Nil draws no thumb (nothing picked, or not measured yet).
    private var thumbRect: CGRect? {
        if let dragCenter, let ordered = orderedSlots {
            return SegmentThumbDrag.frame(centerX: dragCenter, slots: ordered, row: 0...rowWidth)
        }
        return pickedIndex.flatMap { slots[$0] }
    }

    /// The thumb: ONE pane of the system's Liquid Glass that stays put as a
    /// view and is moved by SwiftUI's own animation of its frame, so the
    /// system reshapes the glass as it slides. Nothing here places it frame
    /// by frame, and nothing is painted over it.
    ///
    /// The glass's other morph, removing the pane from one segment and
    /// putting one on the next under a shared `glassEffectID`, was filmed at
    /// 120 fps four ways on 2026-09-29 and every time it jumped: glass on View
    /// one frame, on Edit the next, nothing between.
    @ViewBuilder private var thumb: some View {
        if let rect = thumbRect {
            GlassEffectContainer {
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .glassEffect(thumbGlass, in: .capsule)
                        .overlay(focusRing)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        // Under Reduce Motion a new pick is a new pane, so the
                        // old one fades as the new one appears; otherwise it is
                        // the same pane, slid.
                        .id(reduceMotion ? pickedIndex : nil)
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            // A new pane for a new appearance: a pane changing the glass it
            // wears as the theme flipped once stayed dark on a light rail.
            .id(scheme)
            // The one animator. A pick made inside someone else's animation
            // (View | Edit changes under `.viewEditMode`) moves the glass on
            // this curve and no other.
            .transaction(value: pickedIndex) {
                $0.animation = reduceMotion ? Self.fadeCurve : Self.glassCurve
            }
        }
    }

    /// Lighter than the rail by the glass alone, measured on real captures
    /// (2026-09-29): in light the regular glass is the white pane; in dark the
    /// regular glass goes as dark as the rail, and the clear glass under a
    /// white tint is what clears 1.5:1. A white tint on light glass greys it
    /// (1.15:1), so light wears none. The numbers are on `segRail`.
    private var thumbGlass: Glass {
        scheme == .dark ? .clear.tint(Palette.segGlassTintDark) : .regular
    }

    private var orderedSlots: [CGRect]? {
        let ordered = options.indices.compactMap { slots[$0] }
        return ordered.count == options.count && !ordered.isEmpty ? ordered : nil
    }

    /// Take hold of the thumb and slide it: it follows the pointer along the
    /// rail, and on letting go the same pane slides onto the segment under its
    /// middle. A drag that starts anywhere else is left to the segment it
    /// started on.
    private var thumbDrag: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(segmentedRowSpace))
            .onChanged { drag in
                if dragIgnored { return }
                if dragCenter == nil {
                    guard !reduceMotion, let pickedIndex, let slot = slots[pickedIndex],
                          slot.contains(drag.startLocation) else {
                        dragIgnored = true
                        return
                    }
                    grabOffset = drag.startLocation.x - slot.midX
                }
                let lowest = slots[0]?.midX ?? 0
                let highest = slots[options.count - 1]?.midX ?? rowWidth
                dragCenter = min(max(drag.location.x - grabOffset, lowest), highest)
            }
            .onEnded { _ in
                defer { dragIgnored = false }
                guard let center = dragCenter, let ordered = orderedSlots else {
                    dragCenter = nil
                    return
                }
                let landing = SegmentThumbDrag.landing(
                    centerX: center, slots: ordered,
                    available: options.map { $0.disabledReason == nil })
                withAnimation(Self.glassCurve) {
                    dragCenter = nil
                    if let landing, landing != pickedIndex { pick(options[landing].value) }
                }
            }
    }

    @ViewBuilder private var focusRing: some View {
        if isFocused || shownFocused {
            Capsule().stroke(Palette.accent.opacity(0.38), lineWidth: 3).padding(-1.5)
        }
    }

    private func segment(_ index: Int) -> some View {
        let option = options[index]
        let isOn = index == pickedIndex
        let isAvailable = option.disabledReason == nil
        let lit = isOn || (hovered == index && isAvailable)
        return Button {
            pick(option.value)
        } label: {
            HStack(spacing: 5) {
                if let image = option.image {
                    image
                        .font(.system(size: 13, weight: .medium))
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                if showsTitles || option.image == nil {
                    Text(option.title)
                        .font(.system(size: size.fontSize, weight: isOn ? .semibold : .medium))
                        .tracking(-0.03)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .foregroundStyle(lit ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Palette.dim))
            .padding(.horizontal, showsTitles || option.image == nil ? wordPadding : 0)
            .frame(minWidth: showsTitles ? 0 : size.height - 4, maxWidth: .infinity,
                   maxHeight: .infinity)
            .background {
                if hovered == index, !isOn, isAvailable {
                    Capsule().fill(Palette.glassHover)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(SegmentPressStyle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(segmentedRowSpace)) } action: {
            slots[index] = $0
        }
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.42)
        .kitHover(option.title) { inside in
            if inside { pointerOver = index } else if pointerOver == index { pointerOver = nil }
        }
        .modifier(SegmentTip(text: tip(for: option),
                             key: option.disabledReason == nil ? option.key : nil,
                             below: tipsBelow))
        // Read the way a walk read a system segment: which one is on, then
        // what resting on it says.
        .playtestControl(option.title, detail: Self.walkDetail(isOn: isOn, title: option.title,
                                                               tip: tip(for: option)))
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// What resting on a segment says: why it cannot be picked, its own
    /// help, or for a picture (or a segment with a key) its name.
    private func tip(for option: Option) -> String? {
        option.disabledReason ?? option.help
            ?? (showsTitles && option.key == nil ? nil : option.title)
    }

    static func walkDetail(isOn: Bool, title: String, tip: String?) -> String {
        (isOn ? "already on \(title), " : "") + "tooltip " + (tip.map { "\"\($0)\"" } ?? "none")
    }

    /// An arrow moves the pick one segment, stepping over any that cannot be
    /// picked, and stops at the ends: both ends are in view, so they are real
    /// ends, and a plate jumping across the track reads as the value reset.
    private func step(_ direction: Int) -> KeyPress.Result {
        var index = (pickedIndex ?? (direction > 0 ? -1 : options.count)) + direction
        while options.indices.contains(index) {
            if options[index].disabledReason == nil {
                pick(options[index].value)
                return .handled
            }
            index += direction
        }
        return .handled
    }

    /// Short of room: the same choices in a dropdown, the picked one ticked.
    private var collapsed: some View {
        VideoKit.Dropdown(
            label: label,
            value: pickedIndex.map { options[$0].title } ?? "",
            size: size == .large ? .regular : .small,
            choices: options.map { option in
                .item(option.title, isOn: option.value == selection,
                      isEnabled: option.disabledReason == nil) { pick(option.value) }
            })
    }
}

/// A pressed segment shrinks a little (`.seg>button:active`).
private struct SegmentPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
    }
}

/// A segment's tooltip, when it has something to say.
private struct SegmentTip: ViewModifier {
    let text: String?
    let key: String?
    let below: Bool

    func body(content: Content) -> some View {
        if let text {
            content.toolTip(text, key: key, below: below)
        } else {
            content
        }
    }
}

extension VideoKit.Palette {
    /// Behind a hovered segment: `color-mix(var(--glass) 55%, transparent)`.
    static let glassHover = VideoKit.Tone(light: VideoKit.rgb(0xFFFFFF, 0.74 * 0.55),
                                          dark: VideoKit.rgb(0x1A1D27, 0.72 * 0.55))
    /// The recessed rail (`--seg-rail`, `--seg-rail-inset`). The glass thumb
    /// takes some of its shade from the rail under it, so the rail is what
    /// sets the user's 1.5:1. Measured on real captures (2026-09-29): at .22
    /// light and .30 dark the white title bar read 1.45:1 and the history
    /// strip's filter 1.30 to 1.40:1; at .32 and .45 the title bar reads 1.80,
    /// the panel 2.05 light and 1.81 dark, and the history strip, glass on
    /// glass and the hardest place, 1.50 light and 1.53 dark.
    static let segRail = VideoKit.Tone(light: VideoKit.rgb(0x121828, 0.32),
                                       dark: VideoKit.rgb(0x000000, 0.45))
    static let segRailInset = VideoKit.Tone(light: VideoKit.rgb(0x121828, 0.10),
                                            dark: VideoKit.rgb(0x000000, 0.35))
    /// The glass thumb's tint in dark, what lifts the clear glass above the
    /// rail with nothing painted over it: full white, which on the history
    /// strip's near-black glass is what clears 1.5:1 (.65 read 1.30:1).
    static let segGlassTintDark = Color.white
}

// MARK: - Columns

/// The segments laid out on one row, never two.
///
/// `.natural`: each segment as wide as its words. `.fill`: equal columns when
/// the widest word fits an equal share, which is the component's fill form;
/// when it does not, each segment keeps its own width and the room left over
/// is shared out, so no label is cut while there is room for all of them
/// (the dock rule in `segmented.css`). Short of room altogether, every
/// segment gives up the same share of its width; the control's own
/// `ViewThatFits` turns into a dropdown before that shows.
struct SegmentColumnsLayout: Layout {
    enum Form { case fill, natural }

    var form: Form
    var spacing: CGFloat

    init<Value>(form: SegmentedControl<Value>.Form, spacing: CGFloat) {
        self.form = form == .fill ? .fill : .natural
        self.spacing = spacing
    }

    init(fills: Bool, spacing: CGFloat) {
        self.form = fills ? .fill : .natural
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let natural = naturalWidths(subviews)
        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        let wanted = natural.reduce(0, +) + gaps
        let width: CGFloat
        switch form {
        case .fill: width = proposal.width ?? wanted
        case .natural: width = min(wanted, proposal.width ?? wanted)
        }
        return CGSize(width: width, height: proposal.height ?? height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sized = Self.widths(natural: naturalWidths(subviews), room: bounds.width,
                                spacing: spacing, fills: form == .fill)
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: sized[index], height: bounds.height))
            x += sized[index] + spacing
        }
    }

    /// The width each segment gets, given their natural widths and the room.
    static func widths(natural: [CGFloat], room total: CGFloat, spacing: CGFloat,
                       fills: Bool) -> [CGFloat] {
        guard !natural.isEmpty else { return [] }
        let count = CGFloat(natural.count)
        let room = max(0, total - spacing * (count - 1))
        let sum = natural.reduce(0, +)
        if sum > room {
            return natural.map { sum > 0 ? $0 * room / sum : room / count }
        }
        guard fills else { return natural }
        let share = room / count
        if let widest = natural.max(), widest <= share {
            return Array(repeating: share, count: natural.count)
        }
        return natural.map { $0 + (room - sum) / count }
    }

    private func naturalWidths(_ subviews: Subviews) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(.unspecified).width }
    }
}
