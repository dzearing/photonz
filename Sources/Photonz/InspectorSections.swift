// The panel's section vocabulary: the list of sections and what each one is called, the collapsible section shell and its resize handles, and the drops a section accepts.

import AppKit
import PhotonzCore
import SwiftUI

/// The dock's scrolling area as a coordinate space, so a section can say where
/// it sits relative to what is on screen rather than to the window.
let inspectorDockSpace = "inspector.dock"

/// The sections of the inspector, in their default order. `rawValue` persists.
enum InspectorSectionID: String, CaseIterable {
    case layers
    case measureTool
    case wandTool
    case cropTool
    // The Zoom Callout tool's own setting (`next-callout-shape`): whether the
    // next callout comes out a box or a circle. It sits with the other
    // tool-in-hand sections, and the picked-callout section below carries the
    // same choice for one that is already on the canvas.
    case calloutTool
    // The Lens tool's own settings (Next, `next-lens`): what the next lens you
    // draw does to the picture underneath it, and how hard. Beside the other
    // tool-in-hand sections, with the picked-lens section below carrying the
    // same two for one already on the canvas.
    case lensTool
    case measurements
    // Above Position & Size, because the two answer the same question at
    // different scales: where do these sit, and where does this one sit.
    case arrange
    // WHAT you have picked, before anything about where it sits: an original
    // component's name and its versions, and a copy's Version row and knobs.
    // Above Position & Size on purpose (2026-09-06). It used to sit under
    // Layout, which is the tallest section in the dock, and that put the
    // Version row — the biggest single fact about a copy — below the bottom of
    // the panel on a laptop window: you had to scroll to find out which
    // version you were looking at. Identity first, then where it is, then what
    // it looks like.
    case component
    // The sections named after the thing you have picked: Rectangle, Text,
    // Measurement, Zoom Callout, Collage, Canvas. They sit here, straight
    // under what the document holds and above everything general, because the
    // panel should answer "what did I just click" before it explains position,
    // colour and effects — the same rule Component follows just above.
    //
    // They used to trail Colour and Effects, which on a laptop window put them
    // below the bottom of the panel: on a marked-up screenshot even the header
    // was off screen, so there was no hint the settings existed at all (chosen
    // by the user on 2026-09-06, "Put what you picked first"). The cost is
    // that Colour, Effects and the X Y W H boxes each shift down by the height
    // of one section.
    case annotation
    // A picked zoom callout's own two settings, beside the shapes' own: how
    // much it magnifies and whether it is a box or a circle. Its ring is the
    // layer's border, so the ring's color stays in Color and its thickness
    // stays in Effects, like every other layer's.
    case callout
    // A picked lens's own two settings (Next, `next-lens`): what it does to
    // the picture underneath it and how hard. Its ring, its rounding and its
    // fade are the layer's own, so they stay in Appearance and Effects.
    case lens
    case text
    case measure
    case collage
    case canvas
    case geometry
    case frame
    // The column layout a selected screen is designed to (Next, `next-frames`).
    // Directly under Frame, because Frame says how big the screen is and this
    // says what it is laid out on. Its own section rather than three more rows
    // inside Frame, so the app's two grid-ish things each have their own place
    // with their own words: Columns on a screen, Grid on the canvas.
    case columns
    // Where the pieces sit when something is resized (Next, `next-placement`).
    // Under Frame, because Frame says how big the box is and this says what
    // happens to what is in it when that box changes.
    case placement
    // Every color the picked layers wear, and one place to set them all at
    // once. Under the per-kind sections, because those say what the thing IS
    // and this says what it looks like, and it sits in the SAME place whether
    // one layer is picked or twenty: adding to the selection widens what a row
    // answers for and never moves the row.
    //
    // With the Appearance/Effects split on (`next-shape-parts`) these two rise
    // to sit directly under Layers, in this order, which the user asked for on
    // 2026-09-07: they are the two sections touched on every single layer, so
    // they are the two that must never need scrolling to. That is a one-time
    // move of a saved order rather than a change here, so the release without
    // the split keeps the arrangement it has always had.
    case color
    // Fade, corners, blur and border: the look of the thing, right beside the
    // colors it is painted, because they are the same question. This is the
    // section people reach for most and it used to sit under Shadow and every
    // per-kind section, which in a normal window put Corner Radius below the
    // bottom of the panel (reported 2026-09-03).
    case effects
    // Shadow stays at the bottom. It is part of the same look family as Color
    // and Effects, but it is a switch you set once rather than a slider you
    // pull, and it is the tallest section in the panel: putting it above the
    // picked thing's own settings would push THOSE off the bottom instead.
    case shadow
    // The shelf sits under the property sections, where the mock puts it: it is
    // where you go to fetch something, not what the thing you have selected is.
    case library
    case libraryItem

    var title: String {
        switch self {
        case .layers: "Layers"
        case .measureTool: "Measure Tool"
        case .wandTool: "Magic Wand"
        case .cropTool: "Crop Tool"
        case .calloutTool: "Zoom Callout Tool"
        case .lensTool: "Lens Tool"
        case .measurements: "Measurements"
        case .arrange: "Arrange"
        case .geometry: "Position & Size"
        case .frame: "Frame"
        case .columns: FrameColumnsCopy.section
        case .placement: "Layout"
        case .component: "Component"
        case .color: "Color"
        case .annotation: "Annotation"
        case .callout: "Zoom Callout"
        case .lens: LensCopy.sectionTitle
        case .text: "Text"
        case .measure: "Measure"
        case .collage: "Collage"
        case .canvas: "Canvas"
        case .effects: "Effects"
        case .shadow: "Shadow"
        case .library: "Library"
        // Replaced at draw time by the scope's own noun; this is the fallback.
        case .libraryItem: "Library Item"
        }
    }
}

/// The panel itself answering for a file let go anywhere it has no other drop
/// target: the empty space under the last section, and the gaps between the
/// sections.
///
/// There is no `validateDrop`, on purpose. Answering false there takes the
/// delegate out of the drag altogether, and then the panel could never say it
/// was about to REFUSE something — the refusal would live in the pointer and
/// nowhere else, which is the thing this surface was fixed for.
struct PanelFileDrop: DropDelegate {
    let editorState: EditorState

    /// Who is speaking, for the one-voice rule in `offerPanelDrop`.
    private var owner: AnyHashable { "inspector-panel" }

    func dropEntered(info: DropInfo) { offerFile(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: offerFile(info))
    }

    func dropExited(info: DropInfo) { editorState.endPanelDrop(from: owner) }

    func performDrop(info: DropInfo) -> Bool {
        let landing = editorState.incomingDropOnTop
        editorState.endPanelDrop(from: owner)
        return FileDrop.accept(info, into: editorState, landingAt: landing)
    }

    @discardableResult
    private func offerFile(_ info: DropInfo) -> DropOperation {
        guard FileDrop.isAboutAFile(info) else { return .forbidden }
        guard FileDrop.carriesUsableFile(info) else {
            editorState.offerPanelDrop(.refuses, from: owner)
            return .forbidden
        }
        editorState.offerPanelDrop(.accepts(editorState.incomingDropOnTop), from: owner)
        return .copy
    }
}

/// What the panel draws while something is in the air over it, so the only
/// sign of what is about to happen is not the shape of the pointer.
///
/// Two answers, told apart at a glance rather than by reading: a solid accent
/// edge with a faint wash means the panel will take this, and a dashed red
/// edge means it will not. The precise slot the picture will take is drawn by
/// the layers list itself, in the same drop line a dragged row already gets.
struct PanelDropAffordance: View {
    let offer: EditorState.PanelDropOffer?

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10) }

    @ViewBuilder
    var body: some View {
        switch offer {
        case .accepts:
            shape
                .fill(Color.accentColor.opacity(0.07))
                .overlay { shape.strokeBorder(Color.accentColor, lineWidth: 2) }
                .padding(3)
        case .refuses:
            shape
                .strokeBorder(Color.red.opacity(0.55),
                              style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .padding(3)
        case nil:
            EmptyView()
        }
    }
}

/// The one line the panel says while a saved text style is held over a row.
///
/// The ring on the row already says yes or no at the pointer. This says WHY,
/// which is the half a ring cannot carry: this is not text, it is locked, it is
/// already wearing that name. It is the same sentence the picture says while a
/// style is over the words, worked out in the same place, so the two surfaces
/// can never drift into promising different things.
///
/// It sits at one END of the list rather than under the pointer, which is the
/// one way it differs from the canvas: a sentence does not fit in a row this
/// narrow. Which end is whichever one the aimed row is NOT near, so it is a
/// glance away from the row it is about and never drawn over it.
struct StyleRowDropNote: View {
    let drop: StyleRowDrop?

    @ViewBuilder
    var body: some View {
        if let drop {
            Text(drop.answer.note)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                // Accent for a style that lands, a plain dark plate for one
                // that does not: the colour repeats what the ring on the row
                // says, so a glance is enough and reading is only needed for
                // the why.
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(drop.lands ? Color.accentColor : Color.black.opacity(0.78))
                }
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .transition(.opacity)
        }
    }
}

/// Takes a picture let go on a dock section the way the rest of the window
/// does.
///
/// A section answers for files because nothing behind it can: SwiftUI gives the
/// drag to the innermost target under the pointer and stops there, so a section
/// that answered for nothing made the top half of the panel refuse a picture
/// the bottom half was happily taking.
///
/// FILES ONLY, and that is the whole point of it. Reordering sections used to
/// come through here as well, riding on a system drag that carried the
/// section's name as text — which every drop target in the panel then read as
/// a payload it could not use, and answered with the red dashes that mean a
/// file would be refused. A reorder is now the panel's own gesture
/// (`reorderGesture`) and never reaches the drop machinery at all.
struct SectionFileDrop: DropDelegate {
    let item: InspectorSectionID
    let editorState: EditorState

    func dropEntered(info: DropInfo) { offerFile(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: offerFile(info))
    }

    func dropExited(info: DropInfo) { editorState.endPanelDrop(from: item) }

    func performDrop(info: DropInfo) -> Bool {
        let landing = editorState.incomingDropOnTop
        editorState.endPanelDrop(from: item)
        return FileDrop.accept(info, into: editorState, landingAt: landing)
    }

    /// Tells the panel what it is about to do with the file in the air, and
    /// answers the pointer the same thing. A section is not a place in the
    /// stack, so a picture let go here lands on top — which is what the line
    /// at the top of the layers list is drawing while this is showing.
    @discardableResult
    private func offerFile(_ info: DropInfo) -> DropOperation {
        guard FileDrop.isAboutAFile(info) else { return .forbidden }
        guard FileDrop.carriesUsableFile(info) else {
            editorState.offerPanelDrop(.refuses, from: item)
            return .forbidden
        }
        editorState.offerPanelDrop(.accepts(editorState.incomingDropOnTop), from: item)
        return .copy
    }
}

/// A titled section with a chevron (tap to collapse) and a drag affordance on
/// its header (drag to reorder). Elegant/modern: clean header, smooth collapse.
struct CollapsibleSection<Content: View>: View {
    let title: String
    let isCollapsed: Bool
    let onToggle: () -> Void
    /// The header being dragged up or down the dock: where the pointer is in
    /// the dock's visible area, and how far it has carried this section.
    let onReorder: (CGFloat, CGFloat) -> Void
    /// The header let go.
    let onReorderEnd: () -> Void
    /// Optional header furniture between the title and the drag grip — the
    /// Measurements section puts its count badge and panel menu here.
    var accessory: AnyView?
    /// The height this body is allowed, past which it scrolls inside itself so
    /// the sections under it stay where they are. Nil is the normal case: the
    /// body is drawn whole, because the dock has room for all of it. See
    /// `DockHeightBudget`.
    var bodyCeiling: CGFloat?
    /// Told how tall the body would like to be, whether or not it got it. This
    /// is what the dock budgets from, and it is measured INSIDE the scroller,
    /// so it is the content's own height rather than the height it was given —
    /// the two being different is the whole point.
    var onBodyHeight: ((CGFloat) -> Void)?
    /// ...and how tall the header is, since a header whose words wrap is
    /// taller than the row it is pinned to.
    var onHeaderHeight: ((CGFloat) -> Void)?
    /// Where the body is DRAWN, in the dock's visible area: the window a
    /// shortened body shows through, and the body itself when it is whole.
    /// This is the room anything inside the section has, which is not the same
    /// as the room the dock has. See `LayersPanel.applyEffectReveal`.
    var onBodyFrame: ((CGRect) -> Void)?
    @ViewBuilder var content: () -> Content
    /// Whether this header's press has travelled far enough to have picked the
    /// section up. See `headerGesture`.
    @State private var isCarrying = false
    /// Which way a shortened body has more to show. Starts as "more below",
    /// which is what being shortened means, so the cue is right on the first
    /// frame rather than one scroll later.
    @State private var overflow = EdgeOverflow(above: false, below: true)

    /// Which edges of a shortened body have more content past them.
    private struct EdgeOverflow: Equatable {
        let above: Bool
        let below: Bool
    }

    /// Solid over the body, fading out at whichever edge has more past it.
    private var edgeFade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0), .black],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: overflow.above ? InspectorPanel.bodyEdgeFade : 0)
            Rectangle()
            LinearGradient(colors: [.black, .black.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: overflow.below ? InspectorPanel.bodyEdgeFade : 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    onHeaderHeight?($0)
                }
            if !isCollapsed {
                boundedBody
                    .onGeometryChange(for: CGRect.self) {
                        $0.frame(in: .named(inspectorDockSpace))
                    } action: { onBodyFrame?($0) }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// The body, inside its own scroller when the dock has had to shorten it.
    ///
    /// Whole and unwrapped the rest of the time, which is every case where the
    /// panel fits: a section that would be drawn at exactly its own height
    /// gains nothing from a scroller and loses a frame of lag every time its
    /// content changes, because the height it is given is measured one pass
    /// behind the content it is given for.
    @ViewBuilder private var boundedBody: some View {
        let measured = content()
            .padding(.bottom, InspectorPanel.bodyBottomPadding)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                onBodyHeight?($0)
            }
        if let bodyCeiling {
            ScrollView(.vertical) { measured }
                .frame(height: bodyCeiling)
                .scrollBounceBehavior(.basedOnSize)
                // Which way there is more to see, so the edge that says so is
                // only drawn where it is true.
                .onScrollGeometryChange(for: EdgeOverflow.self) { geometry in
                    EdgeOverflow(
                        above: geometry.contentOffset.y > 1,
                        below: geometry.contentOffset.y + geometry.containerSize.height
                            < geometry.contentSize.height - 1)
                } action: { _, edges in
                    overflow = edges
                }
                // A body the dock has shortened is cut off mid-control, and
                // macOS hides its scrollers until you scroll, so the first
                // build of this clipped a sentence in half and gave no hint
                // why: it read as a rendering fault rather than as something
                // that scrolls. The edge fades out instead, which is the
                // ordinary way of saying there is more this way, and it is
                // only ever on a body that really is shorter than its content.
                .mask { edgeFade }
                .animation(.easeOut(duration: 0.12), value: overflow)
        } else {
            measured
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: PanelSectionLook.Section.chevronSize,
                              weight: PanelSectionLook.Section.chevronWeight))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            Text(title)
                .font(PanelSectionLook.Section.titleFont)
            Spacer(minLength: 8)
            if let accessory { accessory }
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .panelEdgeIcon("section grip", of: title)
        }
        // Where a walk reads the heading's own leading edge back as a number,
        // so "the section's content lines up with its heading" is a
        // measurement rather than a picture.
        .panelStartProbe(.heading, owner: title)
        // Leading and trailing separately, and both on the panel's own margin:
        // the heading begins exactly where the rows under it do. It used to be
        // padded in by 12 against their 14, so every section's title started
        // two points left of its own content (measured 2026-09-08).
        .padding(.leading, EditorChromeLayout.panelStartInset)
        .panelEdgePadding()
        .padding(.vertical, 8)
        // A floor, not a fixed height: a header whose words grow still grows.
        .frame(minHeight: InspectorPanel.headerRowHeight)
        .contentShape(Rectangle())
        .gesture(headerGesture)
        .panelHelp("Drag to reorder • click to collapse")
        // Named for a scripted walk, so one can collapse a section, or pick it
        // up, by the words on it.
        .playtestControl("\(title) section", detail: "a dock section header")
    }

    /// Click to collapse, drag to reorder — ONE gesture, which is the only way
    /// the two can be told apart without arbitration: a press that never
    /// travels is a click, and a press that travels 4pt has picked the section
    /// up and stays a carry until it is let go.
    ///
    /// Reordering is a plain drag of the panel's own, NOT a system drag. A
    /// system drag hands the pointer a picture of the title and nothing else,
    /// lets the section be pulled sideways out of the column, and — because
    /// what it is carrying looks like a payload to every drop target it crosses
    /// — makes the panel flash the marks that answer for a dropped file,
    /// including the red dashes that mean a file would be refused.
    private var headerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(inspectorDockSpace))
            .onChanged { value in
                guard isCarrying || abs(value.translation.height) > 4 else { return }
                isCarrying = true
                onReorder(value.location.y, value.translation.height)
            }
            .onEnded { _ in
                guard isCarrying else {
                    withAnimation(.spring(duration: 0.25)) { onToggle() }
                    return
                }
                isCarrying = false
                onReorderEnd()
            }
    }
}

/// The 1px resize handle on the panel's left edge. Drag to set the panel width;
/// the value persists via the caller's `@AppStorage` binding.
struct InspectorResizeHandle: View {
    @Binding var width: Double
    @State private var dragStartWidth: Double?

    static let minWidth: Double = 220
    static let maxWidth: Double = 480

    var body: some View {
        Divider()
            .frame(width: 1)
            .overlay {
                // A wide, invisible strip makes the 1px line easy to grab — a
                // hairline is nearly impossible to hit, so give it a 14pt target
                // (extends 7pt each side of the divider).
                Color.clear
                    .frame(width: 14)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                let base = dragStartWidth ?? width
                                if dragStartWidth == nil { dragStartWidth = width }
                                // Dragging left (negative dx) widens the right panel.
                                width = min(Self.maxWidth, max(Self.minWidth, base - value.translation.width))
                            }
                            .onEnded { _ in dragStartWidth = nil }
                    )
            }
            // The 14pt grab strip spills past the 1pt divider; let it receive
            // hits in that overhang instead of being clipped to 1pt.
            .frame(width: 1)
            .zIndex(1)
    }
}

/// The grab bar under a bounded list area (the layers rows, the Library
/// tiles): drag it to set how tall that area may get before it scrolls on its
/// own, so the sections below it stay in view. One idiom, so every resizable
/// area in the dock feels the same.
///
/// It is drawn only while there is something to resize. The area is as tall as
/// its content or the ceiling this bar sets, whichever is smaller, so under a
/// list shorter than the floor every ceiling draws the same picture — and a bar
/// that turns the pointer into a resize cursor and then moves nothing is worse
/// than no bar at all. `PanelAreaResize` in PhotonzCore owns that rule and the
/// arithmetic under it.
struct PanelAreaResizeHandle: View {
    /// The persisted ceiling, owned by the caller's `@AppStorage`.
    @Binding var maxHeight: Double
    /// What a walk calls this area: "Layers", "Library".
    let area: String
    /// How tall the area would be with nothing capping it. Dragging is bounded
    /// by this, so every point of the drag moves the area under the pointer.
    let contentHeight: CGFloat
    let minHeight: CGFloat
    let maxAllowedHeight: CGFloat
    let help: String

    @State private var dragStartHeight: Double?
    /// Whether the pointer is on the bar, so the resize cursor is pushed and
    /// popped exactly once each.
    @State private var isHovering = false

    /// How tall the area is right now: its content, capped.
    private var height: CGFloat {
        PanelAreaResize.height(contentHeight: contentHeight, ceiling: CGFloat(maxHeight))
    }

    /// Whether there is a bar at all. Under content shorter than the floor
    /// there is nothing a ceiling could change, so nothing is drawn and the
    /// pointer stays as it was.
    private var isShown: Bool {
        PanelAreaResize.isResizable(contentHeight: contentHeight,
                                    minHeight: minHeight,
                                    maxAllowedHeight: maxAllowedHeight)
    }

    var body: some View {
        Group {
            if isShown {
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 32, height: 4)
                    .frame(maxWidth: .infinity)
                    .frame(height: 12)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        guard inside != isHovering else { return }
                        isHovering = inside
                        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    // The bar can now go away under the pointer, when the last
                    // rows that made it worth having are deleted. Without this
                    // the resize cursor it pushed would stay on screen with
                    // nothing under it to resize.
                    .onDisappear {
                        if isHovering { isHovering = false; NSCursor.pop() }
                    }
                    .gesture(
                        // GLOBAL space: the handle moves as the area resizes, so a
                        // local-space translation would be measured against the moving
                        // handle and jiggle.
                        DragGesture(coordinateSpace: .global)
                            .onChanged { carry($0.translation.height) }
                            .onEnded { _ in end() }
                    )
                    .panelHelp(help)
            } else {
                // The bar's room, kept, so a list does not shift the sections
                // under it by twelve points as it crosses the threshold.
                Color.clear.frame(height: 12)
            }
        }
        .panelAreaHandleProbe(
            PanelAreaHandleReading(area: area, isShown: isShown, height: height,
                                   contentHeight: contentHeight, minHeight: minHeight,
                                   maxAllowedHeight: maxAllowedHeight),
            carry: carry, end: end)
    }

    /// The pointer has travelled `translation` points down from where it took
    /// hold. Bases off the area's ACTUAL height rather than the stored ceiling
    /// — which can sit above short content — so the bar tracks the cursor one
    /// for one instead of needing a big pull to catch up.
    private func carry(_ translation: CGFloat) {
        let base = dragStartHeight ?? Double(height)
        if dragStartHeight == nil { dragStartHeight = Double(height) }
        maxHeight = Double(PanelAreaResize.storedCeiling(base: CGFloat(base),
                                                        translation: translation,
                                                        contentHeight: contentHeight,
                                                        minHeight: minHeight,
                                                        maxAllowedHeight: maxAllowedHeight))
    }

    private func end() { dragStartHeight = nil }
}
