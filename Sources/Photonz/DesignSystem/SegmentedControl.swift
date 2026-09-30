import AppKit
import PhotonzCore
import SwiftUI

/// **The segmented control**: a small set of exclusive choices, all of them on
/// screen at once (`docs/design/mocks/pages/comp-segmented.html`,
/// `shared/components/segmented.css`).
///
/// The only segmented control in the app: panel rows, popovers, dialogs, the
/// history bar and the title bar's View | Edit. `SegmentedControlUsageTests`
/// fails the build on one made any other way.
///
/// It is drawn by us, not by AppKit. For one day (2026-09-29) it was the Mac's
/// own `NSSegmentedControl`, and the user sent it back on 2026-09-30: "this IS
/// the native slider, but it's ugly and I want to go back to our custom one",
/// with the picked choice as a TINTED Liquid Glass chip that moves as glass.
///
/// * **One look, everywhere.** A recessed capsule rail, 2pt of padding, 2pt
///   between segments, capsule segments, and ONE chip over the picked
///   segment: a pane of the system's Liquid Glass tinted with the accent,
///   nothing painted over it, the picked word inside it in the system's own
///   label for glass. Only the size differs from place to place.
/// * **Every word is legible, always** (the user, 2026-09-30: "I do not
///   want white on white or black on black cases EVER"). The colours are
///   `SegmentInk`'s, which PhotonzCore tests for every state, scheme and
///   accent, and the legibility check (`LegibilitySheet`) measures on the
///   drawn control on every test run. The rail is solid, so nothing behind
///   the control reaches its words; the picked word is the system's label
///   on glass, white in dark and black in light, and the other scheme's
///   only where that one would not read on the accent (yellow in dark).
/// * **Sizes.** 24, 28 (the default, and the only size the mocks' panels use)
///   and 32. The size sets the height and the type; the width always comes from
///   the words.
/// * **Forms.** `.fill` takes its container's width in equal columns, the form
///   inside a panel or a popover; `.natural` hugs its words. Pictures instead
///   of words are square segments, each named by its tooltip.
/// * **It never wraps.** When the words would have to be cut short, the
///   control becomes a dropdown holding the same choices. Pictures never do.
/// * **States.** Hovering an unpicked segment lays a faint plate behind it and
///   darkens its word; pressing shrinks it to 97%; one option that cannot be
///   picked keeps its place in a quieter word and says why in its tooltip; the
///   whole control under `.disabled` greys its chip and stops answering. One
///   tab stop, arrows move the pick and stop at the ends, and the focus ring
///   sits round the chip.
/// * **Changing the value.** The chip lifts off its word and travels to the
///   new segment as a lens: clear glass with a hint of the accent, riding
///   over the words so they bend at its edges as it passes, the way the
///   system's own segmented thumb lenses its labels (the user, 2026-09-30:
///   "I see no liquid glass refraction on the edges"). It lands as the
///   tinted chip with its word inside. It is moved by SwiftUI's own
///   animation: its leading edge sets off first and its trailing edge
///   follows, so it stretches across the gap and draws itself in as it
///   lands. Both edges ride timing curves that end exactly where they are
///   going, so it never overshoots and never leaves the rail (filmed at 120
///   fps by `segmented-thumb-film-walk`, `segmented-history-film-walk` and
///   `segmented-chip-refraction-film-walk`). Those two curves are the chip's
///   ONLY animators: a pick made inside another animation (View | Edit
///   changes under `.viewEditMode`) once flung a drawn thumb a whole segment
///   out of its rail. Grab the chip and drag it and it follows the pointer as
///   the same lens, landing on the nearest segment when let go. Under Reduce
///   Motion it moves at once.
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
        /// `showsTitles` is false. Build it named (`SegmentedControl.symbol`):
        /// Current's system picker reads a segment's name off its picture.
        var image: NSImage?
        /// What resting on it says. A picture segment without one says its title.
        var help: String?
        /// The key that picks it, printed quieter in its tooltip.
        var key: String?
        /// Set when this one cannot be picked right now: the segment keeps its
        /// place in a quieter word, and its tooltip says this.
        var disabledReason: String?

        init(_ value: Value, _ title: String, image: NSImage? = nil, help: String? = nil,
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
    /// What the whole control's system help tag says in Current, for a caller
    /// that had one (`segmentToolTips`' fallback).
    var systemHelp: String?
    /// Tooltips under the segments rather than over them, for a control at the
    /// very top of a window.
    var tipsBelow = false
    /// False for a control that was already drawn before the switch existed
    /// (the Library's scope, the video panel's rows): it stays drawn with the
    /// switch off too, because the system control is not what it replaced.
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

    /// A symbol as a segment's picture, carrying the option's name: Current's
    /// system picker names a segment by its picture's description (a SwiftUI
    /// `.accessibilityLabel` does not reach it), which is what a screen reader
    /// says and what a walk presses it by.
    static func symbol(_ name: String, named title: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: title)
        image?.accessibilityDescription = title
        return image
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
            Image(nsImage: image)
        } else {
            Text(option.title)
        }
    }
}

// MARK: - The drawn control

/// The row of segments, the space the chip, a slot and a drag are measured in.
private let segmentedRowSpace = "segmented-row"

/// The drawn control. Internal rather than private so the legibility check
/// (`LegibilityCatalogue`) can draw each state and measure it.
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
    /// For the legibility sheet only: draw this segment hovered, the focus
    /// ring on, and the chip stopped part way (a fraction of the way from the
    /// first segment to the picked one), without a pointer, a keyboard or a
    /// clock.
    var shownHovered: Int?
    var shownFocused = false
    var shownTravel: CGFloat?
    /// For the legibility sheet: draw the chip's glass as the colour it draws
    /// (measured with the window in front), since an offscreen render has no
    /// glass.
    var glassAsPaint = false

    init(label: String, options: [Option], selection: Value?, size: SegmentedControl<Value>.Size,
         form: SegmentedControl<Value>.Form, showsTitles: Bool, tipsBelow: Bool,
         shownHovered: Int? = nil, shownFocused: Bool = false, shownTravel: CGFloat? = nil,
         glassAsPaint: Bool = false, pick: @escaping (Value) -> Void) {
        self.label = label
        self.options = options
        self.selection = selection
        self.size = size
        self.form = form
        self.showsTitles = showsTitles
        self.tipsBelow = tipsBelow
        self.shownHovered = shownHovered
        self.shownFocused = shownFocused
        self.shownTravel = shownTravel
        self.glassAsPaint = glassAsPaint
        self.pick = pick
    }

    @State private var pointerOver: Int?
    private var hovered: Int? { isEnabled ? (pointerOver ?? shownHovered) : nil }
    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appearsActive) private var appearsActive

    /// Every segment's box in the row, where the chip is placed and what a
    /// drag is measured against.
    @State private var slots: [Int: CGRect] = [:]
    /// The chip's two edges in the row. Each is moved on its own curve, which
    /// is what stretches the chip as it travels. Nil before the row is
    /// measured, and while nothing is picked.
    @State private var chipLeading: CGFloat?
    @State private var chipTrailing: CGFloat?
    /// A drag of the chip under way: where its middle is, and how far from
    /// its middle the hand took hold.
    @State private var dragCenter: CGFloat?
    @State private var grabOffset: CGFloat = 0
    /// A drag that began off the chip belongs to the segment it began on.
    @State private var dragIgnored = false
    @State private var rowWidth: CGFloat = 0
    /// The chip is on its way to a new pick. `travelToken` tells the end of
    /// the latest trip from the end of one it overtook.
    @State private var travelling = false
    @State private var travelToken = 0
    /// The chip is a lens over the words: travelling, under the hand, or
    /// stopped part way for the legibility sheet.
    private var isLifted: Bool { travelling || dragCenter != nil || shownTravel != nil }

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

    private var inkScheme: SegmentInk.Scheme { scheme == .dark ? .dark : .light }

    private var bar: some View {
        SegmentColumnsLayout(form: form, spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                segment(index)
            }
        }
        // The words in their own ink everywhere the chip is not at rest...
        .mask { outsideChip }
        .coordinateSpace(.named(segmentedRowSpace))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        // ...and the chip over them: the picked word inside it at rest, a
        // lens over the words it passes while it travels.
        .overlay(alignment: .topLeading) { chip }
        .simultaneousGesture(chipDrag)
        .onChange(of: pickedIndex) { _, picked in moveChip(to: picked) }
        .onChange(of: slots) { settleChip() }
        .onAppear { settleChip() }
        .padding(2)
        .frame(height: size.height)
        .frame(minWidth: 0, maxWidth: form == .fill ? .infinity : nil)
        // The recessed rail: solid, so nothing behind it reaches the words.
        .background(Capsule().fill(Self.paint(SegmentInk.rail(inkScheme)).shadow(
            .inner(color: Palette.segRailInset.color(scheme), radius: 1, y: 1))))
        .overlay(Capsule().strokeBorder(Palette.edgeLo).allowsHitTesting(false))
        .focusable(isEnabled, interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    // MARK: The chip

    /// The leading edge's curve: fast out, easing in to land. A timing curve
    /// and not a spring: filmed on 2026-09-30, the "no bounce" `.smooth`
    /// spring still carried the front edge 5pt past its segment and the
    /// rail's end before settling back. A curve whose control points lie
    /// inside 0...1 never passes where it is going.
    private static var leadCurve: Animation { .timingCurve(0.3, 0, 0, 1, duration: 0.24) }
    /// The trailing edge sets off a beat later and takes a little longer, so
    /// the chip stretches over the gap and draws itself in as it lands.
    private static var trailCurve: Animation { .timingCurve(0.4, 0, 0, 1, duration: 0.3).delay(0.05) }

    /// Where the chip is: under the hand during a drag, else between its two
    /// edges. Nil draws no chip (nothing picked, or not measured yet).
    private var chipRect: ChipBox? {
        if let shownTravel, let ordered = orderedSlots, let pickedIndex {
            // Stopped part way from the first segment: the front edge that
            // far along, the back edge lagging behind it, as in flight.
            let from = ordered[0], to = ordered[pickedIndex]
            let front = from.maxX + (to.maxX - from.maxX) * shownTravel
            let back = from.minX + (to.minX - from.minX) * shownTravel * 0.6
            return ChipBox(leading: back, trailing: front, top: from.minY, bottom: from.maxY)
        }
        if let dragCenter, let ordered = orderedSlots {
            return ChipBox(SegmentThumbDrag.frame(centerX: dragCenter, slots: ordered, row: 0...rowWidth))
        }
        guard pickedIndex != nil, let leading = chipLeading, let trailing = chipTrailing,
              let any = slots.values.first else { return nil }
        return ChipBox(leading: leading, trailing: max(leading, trailing), top: any.minY, bottom: any.maxY)
    }

    /// The chip: ONE pane of the system's Liquid Glass tinted with the chip's
    /// colour, with nothing painted over it, riding ABOVE the row's words.
    /// At rest it is regular glass, the words under it cut away and the
    /// picked word drawn inside it in the system's own label for glass
    /// (`chipWords`), so it reads as the tinted chip behind its word. While
    /// it travels (`isLifted`) it turns to clear glass with a hint of the
    /// accent and its own words go, so the words it passes over are seen
    /// through it and bend at its edges, the way the system's own segmented
    /// thumb lenses its labels (the user, 2026-09-30: "I see no liquid glass
    /// refraction on the edges" of a chip painted over at 88%). It stays put
    /// as a view and is moved by SwiftUI's animation of its edges; nothing
    /// places it frame by frame.
    ///
    /// Not in a `GlassEffectContainer`, and not morphed between segments under
    /// a shared `glassEffectID`: that morph was filmed at 120 fps four ways on
    /// 2026-09-29 and every time it jumped, glass on View one frame, on Edit
    /// the next, nothing between.
    @ViewBuilder private var chip: some View {
        if let box = chipRect {
            let fill = Self.paint(chipTint)
            atChip(box) {
                ZStack {
                    // What the glass draws, as paint, only where no glass can
                    // be drawn: an offscreen picture (the legibility sheet,
                    // a walk's labelsWhole), where glass draws nothing.
                    Capsule()
                        .fill(fill.opacity(isLifted ? SegmentInk.lensTint : 1))
                        .opacity(paintsGlass ? 1 : 0)
                    chipWords(box)
                }
                .clipShape(Capsule())
                // Not `.interactive()`: interactive glass swells 1.5pt past
                // the chip under a press, drawn outside any clip SwiftUI puts
                // on it (filmed on 2026-09-30 in the history bar). The
                // pressed segment shrinks to 97% instead.
                //
                // The same view whether or not a walk is taking an offscreen
                // picture, only its glass changes: taking the glass view out
                // and putting it back left the history bar's filter deaf to
                // the next click.
                .modifier(ChipGlass(glass: glass(fill), drawn: !glassAsPaint))
                .overlay(focusRing)
            }
            .allowsHitTesting(false)
        }
    }

    /// Which glass the chip is: none while a picture is taken offscreen,
    /// clear with a hint of the accent while it travels, regular glass tinted
    /// with the accent at rest.
    private func glass(_ fill: Color) -> Glass {
        if ChipGlassSwitch.shared.offscreen { return .identity }
        return isLifted ? .clear.tint(fill.opacity(SegmentInk.lensTint)) : .regular.tint(fill)
    }

    /// Whether the chip's glass is drawn as paint rather than as glass.
    private var paintsGlass: Bool { glassAsPaint || ChipGlassSwitch.shared.offscreen }

    /// The words inside the chip, laid exactly where the row lays them, in
    /// the system's primary label for glass. That label is white in dark and
    /// black in light; where it would not read on the accent (white on
    /// yellow in dark) the words take the other scheme's
    /// (`SegmentInk.pickedWordScheme`). In a window in the back the system
    /// greys the chip, and the window's own label reads on that grey. They go while the chip travels, so the words it passes
    /// over are the ones seen through it.
    private func chipWords(_ box: ChipBox) -> some View {
        GeometryReader { inside in
            wordRow(ink: chipWordInk)
                .environment(\.colorScheme, chipWordScheme)
                .frame(width: rowWidth, height: inside.size.height + box.top * 2, alignment: .topLeading)
                .offset(x: -box.leading, y: -box.top)
        }
        .opacity(isLifted ? 0 : 1)
        .accessibilityHidden(true)
    }

    /// The system's primary label, drawn by the glass: near pure white or
    /// black (measured 2026-09-30). Painted as that where the glass is
    /// painted, since offscreen the primary label is white at 85% and thin
    /// icon strokes blend into the accent.
    private var chipWordInk: AnyShapeStyle {
        guard paintsGlass else { return AnyShapeStyle(.primary) }
        return AnyShapeStyle(Self.paint(SegmentInk.systemLabel(chipWordScheme == .dark ? .dark : .light)))
    }

    private var chipWordScheme: ColorScheme {
        guard paintsGlass || appearsActive else { return scheme }
        return SegmentInk.pickedWordScheme(on: chipTint, in: inkScheme) == .dark ? .dark : .light
    }

    /// Something the chip's size, where the chip is in the row: the row's
    /// box inset to the chip, each edge by its own inset, taken straight from
    /// that edge's number. The two edges travel on two curves, and this way
    /// each inset is only ever moved by its own edge's curve.
    private func atChip<Content: View>(_ box: ChipBox, @ViewBuilder _ content: () -> Content) -> some View {
        let content = content()
        return GeometryReader { row in
            content
                .padding(.leading, box.leading)
                .padding(.trailing, max(0, row.size.width - box.trailing))
                .padding(.top, box.top)
                .padding(.bottom, max(0, row.size.height - box.bottom))
        }
    }

    /// The chip's colour: the accent as the system draws it
    /// (`SegmentInk.chip`), or grey while the control is disabled.
    private var chipTint: RGBA {
        isEnabled ? SegmentInk.chip(accent: accent) : SegmentInk.disabledChip(inkScheme)
    }

    /// The Mac's accent as it is drawn in this scheme.
    private var accent: RGBA {
        var drawn = RGBA(r: 0, g: 0.478, b: 1)
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            if let color = NSColor.controlAccentColor.usingColorSpace(.sRGB) {
                drawn = RGBA(r: Double(color.redComponent), g: Double(color.greenComponent),
                             b: Double(color.blueComponent))
            }
        }
        return drawn
    }

    /// The row with the chip cut out of it.
    private var outsideChip: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
            if let rect = chipRect, !isLifted {
                atChip(rect) { Capsule() }
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
    }

    /// The row's words, every one in one ink.
    private func wordRow(ink: some ShapeStyle) -> some View {
        SegmentColumnsLayout(form: form, spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                face(index, ink: ink)
            }
        }
    }

    /// Sends the chip to a new pick: the edge on the side it is heading sets
    /// off first. The chip's own curves, whatever animation the pick was
    /// made inside.
    private func moveChip(to picked: Int?) {
        guard dragCenter == nil else { return }
        guard let picked, let target = slots[picked] else {
            if picked == nil { place(nil) }
            return
        }
        guard !reduceMotion, let leading = chipLeading, let trailing = chipTrailing else {
            place(target)
            return
        }
        let forward = target.midX >= (leading + trailing) / 2
        travelToken += 1
        let token = travelToken
        travelling = true
        withAnimation(Self.leadCurve) {
            if forward { chipTrailing = target.maxX } else { chipLeading = target.minX }
        }
        withAnimation(Self.trailCurve) {
            if forward { chipLeading = target.minX } else { chipTrailing = target.maxX }
        } completion: {
            if token == travelToken { travelling = false }
        }
    }

    /// The row was laid out again (it appeared, or its room changed): the
    /// chip goes straight to the picked segment, in whatever transaction
    /// moved the row, so it moves with it.
    private func settleChip() {
        guard dragCenter == nil else { return }
        guard let pickedIndex else {
            if chipLeading != nil { chipLeading = nil; chipTrailing = nil }
            return
        }
        guard let target = slots[pickedIndex],
              chipLeading != target.minX || chipTrailing != target.maxX else { return }
        chipLeading = target.minX
        chipTrailing = target.maxX
    }

    /// Puts the chip somewhere at once, with no animation at all.
    private func place(_ rect: CGRect?) {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            chipLeading = rect?.minX
            chipTrailing = rect?.maxX
        }
    }

    private var orderedSlots: [CGRect]? {
        let ordered = options.indices.compactMap { slots[$0] }
        return ordered.count == options.count && !ordered.isEmpty ? ordered : nil
    }

    /// Take hold of the chip and slide it: it follows the pointer along the
    /// rail, and on letting go it travels on to the segment under its middle.
    /// A drag that starts anywhere else is left to the segment it started on.
    private var chipDrag: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(segmentedRowSpace))
            .onChanged { drag in
                if dragIgnored { return }
                if dragCenter == nil {
                    guard isEnabled, !reduceMotion, let pickedIndex, let slot = slots[pickedIndex],
                          slot.contains(drag.startLocation) else {
                        dragIgnored = true
                        return
                    }
                    grabOffset = drag.startLocation.x - slot.midX
                }
                let lowest = slots[0]?.midX ?? 0
                let highest = slots[options.count - 1]?.midX ?? rowWidth
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) {
                    dragCenter = min(max(drag.location.x - grabOffset, lowest), highest)
                }
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
                // The chip carries on from where the hand let go of it.
                place(SegmentThumbDrag.frame(centerX: center, slots: ordered, row: 0...rowWidth))
                dragCenter = nil
                if let landing, landing != pickedIndex {
                    pick(options[landing].value)
                } else {
                    moveChip(to: pickedIndex)
                }
            }
    }

    @ViewBuilder private var focusRing: some View {
        if isFocused || shownFocused {
            Capsule().stroke(Palette.accent.opacity(0.38), lineWidth: 3).padding(-1.5)
        }
    }

    // MARK: Segments

    private func segment(_ index: Int) -> some View {
        let option = options[index]
        let isOn = index == pickedIndex
        let isAvailable = option.disabledReason == nil
        let ink: SegmentInk.Scheme = inkScheme
        let word = !isAvailable ? SegmentInk.unavailableWord(ink)
            : hovered == index && !isOn ? SegmentInk.hoveredWord(ink) : SegmentInk.word(ink)
        return Button {
            pick(option.value)
        } label: {
            face(index, ink: Self.paint(word))
                .background {
                    if hovered == index, !isOn, isAvailable {
                        Capsule().fill(Self.paint(SegmentInk.hoverPlate(ink)))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(SegmentPressStyle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(segmentedRowSpace)) } action: {
            slots[index] = $0
        }
        .disabled(!isAvailable)
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

    /// A segment's picture and word in one ink, laid out the same whichever
    /// layer draws it. The width is always the picked (semibold) word's, so a
    /// pick never reflows the row under a travelling chip.
    private func face(_ index: Int, ink: some ShapeStyle) -> some View {
        let option = options[index]
        let isOn = index == pickedIndex
        return HStack(spacing: 5) {
            if let image = option.image {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .font(.system(size: 13, weight: .medium))
                    .imageScale(.small)
                    .measuredInk()
                    .accessibilityHidden(true)
            }
            if showsTitles || option.image == nil {
                Text(option.title)
                    .font(.system(size: size.fontSize, weight: .semibold))
                    .tracking(-0.03)
                    .lineLimit(1)
                    .hidden()
                    .overlay {
                        Text(option.title)
                            .font(.system(size: size.fontSize, weight: isOn ? .semibold : .medium))
                            .tracking(-0.03)
                            .lineLimit(1)
                            .fixedSize()
                    }
            }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, showsTitles || option.image == nil ? wordPadding : 0)
        .frame(minWidth: showsTitles ? 0 : size.height - 4, maxWidth: .infinity, maxHeight: .infinity)
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
    /// ends, and a chip jumping across the track reads as the value reset.
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

    static func paint(_ ink: RGBA) -> Color {
        Color(.sRGB, red: ink.r, green: ink.g, blue: ink.b, opacity: ink.a)
    }
}

/// Whether the chips draw their glass. A view holding SwiftUI's glass stops
/// drawing into an offscreen picture altogether, so every walk step that reads
/// the window's picture (`labelsWhole`, the panel's margins) saw a panel
/// section gone blank round any segmented row (found 2026-09-30,
/// captions-panel-keeps-its-margins-walk). The walk harness turns the glass
/// off for the instant it takes such a picture, which then shows the chip's
/// colour, most of what a person sees there anyway.
///
/// (AppKit's own glass view, tried the same day, drew into no offscreen
/// picture either, and the container SwiftUI wraps round an AppKit view
/// swallowed clicks on the history bar's filter.)
@MainActor @Observable final class ChipGlassSwitch {
    static let shared = ChipGlassSwitch()
    var offscreen = false
}

/// The chip's glass, or none for the legibility sheet's offscreen picture,
/// which is told once and never changes, so the view is never swapped.
private struct ChipGlass: ViewModifier {
    let glass: Glass
    let drawn: Bool

    func body(content: Content) -> some View {
        if drawn {
            content.glassEffect(glass, in: .capsule)
        } else {
            content
        }
    }
}

/// Where the chip is in its row, edge by edge.
private struct ChipBox {
    var leading: CGFloat
    var trailing: CGFloat
    var top: CGFloat
    var bottom: CGFloat

    init(leading: CGFloat, trailing: CGFloat, top: CGFloat, bottom: CGFloat) {
        self.leading = leading
        self.trailing = trailing
        self.top = top
        self.bottom = bottom
    }

    init(_ rect: CGRect) {
        self.init(leading: rect.minX, trailing: rect.maxX, top: rect.minY, bottom: rect.maxY)
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
    /// The rail's pressed-in shadow (`--seg-rail-inset`).
    static let segRailInset = VideoKit.Tone(light: VideoKit.rgb(0x121828, 0.10),
                                            dark: VideoKit.rgb(0x000000, 0.35))
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
