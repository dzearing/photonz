import AppKit
import PhotonzCore
import SwiftUI

/// The picked layer's transform values: a popover rising out of the tool
/// bar's Info button, one row per value, name left and number right, with
/// Reset at the foot (Next, `next-transform-bar`; the placement contract's
/// "Named exception: the transform values").
///
/// The user, 2026-10-12, of the bar that used to ride beside the layer: "why
/// is this weird toolbar 1. look different then the pill shaped one
/// (different material, different border), 2, why is it covering up the most
/// important aspect of the photo (the transform grippers?". So it wears the
/// tool bar's own glass and corner (`ToolBarSpacing.cornerRadius`, the same
/// `.glassEffect(.regular)` with no stroke the bar has), opens only when
/// asked, and slides sideways off any handle, the knob or its 3D arcs
/// (`TransformBar.popoverFrame`).
///
/// Its own view, read on its own, so a drag that moves its numbers re-runs
/// this body and nothing else of the editor's.
struct TransformValuesPopover: View {
    @Environment(EditorState.self) private var editorState

    /// The Info button's tip, and what a walk presses it by.
    static let infoHelp = "Transform Values (F8)"
    static let infoControl = "Info"
    /// The popover's width: the longest name, a number and its unit.
    static let width: CGFloat = 176

    var body: some View {
        GeometryReader { proxy in
            if editorState.showsTransformBar, let hold = editorState.transformBar {
                let floor = floor(in: proxy.size)
                let anchorX = anchorX(in: proxy)
                let keepOut = editorState.transformValuesKeepOut
                // Placed by its own size in the same pass it is laid out in,
                // so it lands where it belongs on the very first frame rather
                // than being measured and moved a frame later.
                let place = { (popover: ViewDimensions) in
                    TransformBar.popoverFrame(anchorX: anchorX,
                                              size: CGSize(width: popover.width, height: popover.height),
                                              canvas: proxy.size, floor: floor, keepOut: keepOut)
                }
                popover(hold)
                    .fixedSize()
                    .modifier(TransformBarMetering(canvas: proxy.size, floor: floor,
                                                   anchorX: anchorX, keepOut: keepOut))
                    .alignmentGuide(.leading) { -place($0).minX }
                    .alignmentGuide(.top) { -place($0).minY }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 4)),
                                            removal: .identity))
            }
        }
        // It rises with a short fade and leaves at once, whatever animation
        // the change that closed it was made in: a tool picked inside a spring
        // kept it up for the spring's length.
        .transaction(value: editorState.showsTransformBar) { transaction in
            transaction.animation = editorState.showsTransformBar ? .easeOut(duration: 0.14) : nil
        }
        // A menu opening anywhere is another operation: the popover closes the
        // moment one starts tracking. (F8 and Layer, Show Transform Values
        // still open it: the row's action runs after the menu has closed it.)
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            editorState.dropTransformBar()
        }
    }

    /// The middle of the Info button across the canvas, or, on a bar drawn
    /// before the button has reported where it is, the bar's right end.
    private func anchorX(in proxy: GeometryProxy) -> CGFloat {
        if let anchor = editorState.transformInfoAnchor {
            return anchor.midX - proxy.frame(in: .global).minX
        }
        let bar = EditorChromeLayout.toolBarFrame(canvasSize: proxy.size,
                                                  toolBarWidth: editorState.toolBarWidth,
                                                  bar: Experiments.shared.toolBar)
        return bar.maxX - Experiments.shared.toolBar.endPadding - EditorChromeLayout.toolBarControlSize / 2
    }

    /// The lowest the popover may come: clear of the tool bar and the tool's
    /// own settings above it.
    private func floor(in canvas: CGSize) -> CGFloat {
        let spacing = Experiments.shared.toolBar
        var top = EditorChromeLayout.toolBarFrame(canvasSize: canvas,
                                                  toolBarWidth: editorState.toolBarWidth,
                                                  bar: spacing).minY
        if let capsule = EditorChromeLayout.toolSettingsFrame(
            canvasSize: canvas, width: editorState.toolSettingsSize.width,
            height: editorState.toolSettingsSize.height, bar: spacing) {
            top = min(top, capsule.minY)
        }
        return top
    }

    private func popover(_ hold: TransformBarHold) -> some View {
        let fields = editorState.transformBarFields
        let corner = Experiments.shared.toolBar.cornerRadius
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(fields.enumerated()), id: \.element) { index, field in
                if index > 0, Self.startsGroup(field) { separator }
                TransformBarField(field: field, isLive: hold.live.contains(field))
            }
            separator
            Button("Reset") { editorState.resetTransformBar() }
                .buttonStyle(TransformBarButtonStyle())
                .disabled(!editorState.canResetTransformBar)
                .help("Reset size, turn and tilt. Position stays.")
                .playtestControl("Reset", detail: "Transform values")
        }
        .padding(10)
        .frame(width: Self.width)
        // The tool bar's own glass and corner, and like the bar no stroke:
        // the popover reads as part of the bar it rose out of.
        .glassEffect(.regular, in: .rect(cornerRadius: corner))
        .contentShape(.rect(cornerRadius: corner))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transform values")
        .playtestField("Transform values")
    }

    /// Where a hairline goes: before the angle, the space values and Reset.
    private static func startsGroup(_ field: TransformBar.Field) -> Bool {
        field == .angle || field == .tiltX
    }

    private var separator: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
    }
}

/// One row of the popover: its key diamond once the property animates, its
/// name on the left, its number and unit on the right.
private struct TransformBarField: View {
    @Environment(EditorState.self) private var editorState
    let field: TransformBar.Field
    let isLive: Bool

    /// The name a walk and a screen reader know this row by. Prefixed, so it
    /// never answers for the panel's own X or W.
    private var name: String { "Transform \(field.label)" }

    var body: some View {
        let showing = editorState.transformBarShowing(field)
        let key = editorState.transformBarKey(field)
        Group {
            if editorState.transformBarTakesTyping(field) {
                PanelNumberField(
                    showing: showing,
                    label: name,
                    identity: editorState.transformBar?.layerIDs,
                    leading: field.label,
                    suffix: field.unit,
                    width: .flexible(least: 56),
                    playtest: (name, "Transform values"),
                    stepEach: { direction, coarse in
                        editorState.stepTransformBarValue(field, direction: direction, coarse: coarse)
                    },
                    spell: { SpaceRowText.text(Double($0)) },
                    look: .row,
                    sums: true,
                    isLive: isLive,
                    accessory: key == .dormant ? nil : AnyView(TransformBarDiamond(state: key)),
                    escape: { _ = editorState.escapeTransformBar() },
                    land: { value in editorState.setTransformBarValue(field, value) })
            } else {
                // A number the picked layers work out for themselves (a box a
                // stack places, a locked layer): read, never typed.
                HStack(spacing: 4) {
                    Text(field.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(showing.text)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
                .padding(.horizontal, 6)
                .frame(height: VideoKit.Metrics.controlSmall)
                .panelReadout(showing.text)
            }
        }
        // What the diamond says, for a walk: the same three words every key
        // diamond in the app reads back. A typed value reads back by its box's
        // own name ("Transform Tilt Y").
        .overlay(alignment: .leading) {
            Color.clear.frame(width: 2, height: 2)
                .panelReadout(Self.word(key))
                .playtestField("\(name) Key")
        }
        .playtestField(name)
    }

    static func word(_ state: KeyDiamond) -> String {
        switch state {
        case .dormant: "not keyed"
        case .betweenKeys: "between keys"
        case .onKey: "on a key"
        }
    }
}

/// The mark in front of a row whose property animates: filled on a key,
/// hollow between keys (`.va-kd`).
private struct TransformBarDiamond: View {
    let state: KeyDiamond

    var body: some View {
        ZStack {
            Rectangle().fill(state == .onKey ? AnyShapeStyle(VideoKit.Palette.comp)
                                             : AnyShapeStyle(Color.clear))
            Rectangle().strokeBorder(state == .onKey ? AnyShapeStyle(VideoKit.Palette.comp)
                                                     : AnyShapeStyle(.secondary),
                                     lineWidth: 1.3)
        }
        .frame(width: 7, height: 7)
        .rotationEffect(.degrees(45))
        .frame(width: 10, height: 10)
        .help(state == .onKey ? "Keyed at the playhead" : "Animating; a change adds a key here")
        .accessibilityHidden(true)
    }
}

/// Reset: a text button on a soft plate the popover's width.
private struct TransformBarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity)
            .frame(height: VideoKit.Metrics.controlSmall)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(.primary.opacity(configuration.isPressed ? 0.16 : 0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

/// Tells the probe when the popover came and went and where it sat, so a walk
/// can hold it to one frame, to the canvas and off every handle
/// (`TransformBarMeter`). Nothing at all in the shipping app.
private struct TransformBarMetering: ViewModifier {
    let canvas: CGSize
    let floor: CGFloat
    let anchorX: CGFloat
    let keepOut: [CGRect]

    func body(content: Content) -> some View {
        #if PHOTONZ_PLAYTEST
        content
            .onAppear { TransformBarMeter.shared.drawn(true) }
            .onDisappear { TransformBarMeter.shared.drawn(false) }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { TransformBarMeter.shared.size = $0 }
            .onChange(of: TransformBarMeter.Place(canvas: canvas, floor: floor, anchorX: anchorX,
                                                  keepOut: keepOut),
                      initial: true) { _, place in
                TransformBarMeter.shared.place = place
            }
        #else
        content
        #endif
    }
}
