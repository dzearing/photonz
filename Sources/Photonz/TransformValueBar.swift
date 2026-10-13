import AppKit
import PhotonzCore
import SwiftUI

/// The transform bar: one small Liquid Glass bar of label and value fields,
/// with a Reset, beside the layer in hand (Next, `next-transform-bar`;
/// `pages/video-animate.html`, `.va-bar`; the placement contract's "Named
/// exception: the value overlay").
///
/// Canvas furniture, like the zoom control: it exists only while a transform
/// is in hand, never takes the keyboard unless a field is clicked, and sits by
/// `TransformBar.frame`'s one rule, under the object, above it while a bottom
/// handle is held, inside the canvas and clear of the tool bar.
///
/// Its own view, read on its own, so a drag that moves its numbers re-runs
/// this body and nothing else of the editor's.
struct TransformValueBar: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        GeometryReader { proxy in
            if editorState.showsTransformBar, let hold = editorState.transformBar,
               let box = editorState.transformBarBox {
                let floor = floor(in: proxy.size)
                // Placed by its own size in the same pass it is laid out in,
                // so it lands where it belongs on the very first frame rather
                // than being measured and moved a frame later.
                let place = { (bar: ViewDimensions) in
                    TransformBar.frame(around: box, bar: CGSize(width: bar.width, height: bar.height),
                                       canvas: proxy.size, floor: floor, side: hold.side)
                }
                bar(hold)
                    .fixedSize()
                    .modifier(TransformBarMetering(canvas: proxy.size, floor: floor, box: box,
                                                   side: hold.side))
                    .alignmentGuide(.leading) { -place($0).minX }
                    .alignmentGuide(.top) { -place($0).minY }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 3)),
                                            removal: .identity))
            }
        }
        // It arrives with the mock's short fade (`va-in`, 0.14s) and leaves at
        // once, whatever animation the change that took it down was made in: a
        // tool picked inside a spring kept the bar up for the spring's length.
        .transaction(value: editorState.showsTransformBar) { transaction in
            transaction.animation = editorState.showsTransformBar ? .easeOut(duration: 0.14) : nil
        }
        // A menu opening anywhere is another operation (UX-PATTERNS, "the value
        // overlay"): the bar goes the moment one starts tracking.
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            editorState.dropTransformBar()
        }
    }

    /// The lowest the bar may come: clear of the tool bar and the tool's own
    /// settings above it.
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
        return top - 8
    }

    private func bar(_ hold: TransformBarHold) -> some View {
        let fields = editorState.transformBarFields
        return HStack(spacing: 1) {
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
        .padding(4)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transform values")
        .playtestField("Transform values")
    }

    /// Where the mock draws a hairline: before the size, the angle, the space
    /// values and Reset.
    private static func startsGroup(_ field: TransformBar.Field) -> Bool {
        field == .width || field == .angle || field == .tiltX
    }

    private var separator: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 3)
    }
}

/// One value on the bar: its key diamond once the property animates, its
/// label, its number and its unit.
private struct TransformBarField: View {
    @Environment(EditorState.self) private var editorState
    let field: TransformBar.Field
    let isLive: Bool

    /// The name a walk and a screen reader know this field by. Prefixed, so
    /// it never answers for the panel's own X or W.
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
                    leading: field == .angle ? "\u{2220}" : field.label,
                    suffix: field.unit,
                    width: .fixed(field.isSpace ? 44 : 40),
                    help: field == .angle ? "Rotation" : nil,
                    playtest: (name, "Transform values"),
                    stepEach: { direction, coarse in
                        editorState.stepTransformBarValue(field, direction: direction, coarse: coarse)
                    },
                    spell: { SpaceRowText.text(Double($0)) },
                    look: .bar,
                    sums: true,
                    isLive: isLive,
                    accessory: key == .dormant ? nil : AnyView(TransformBarDiamond(state: key)),
                    land: { value in editorState.setTransformBarValue(field, value) })
            } else {
                // A number the picked layers work out for themselves (a box a
                // stack places, a locked layer): read, never typed.
                HStack(spacing: 4) {
                    Text(field == .angle ? "\u{2220}" : field.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(showing.text)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
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

/// The mark in front of a field whose property animates: filled on a key,
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

/// Reset: a text button on a soft plate (`.va-tb`).
private struct TransformBarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 9)
            .frame(height: VideoKit.Metrics.controlSmall)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(.primary.opacity(configuration.isPressed ? 0.16 : 0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

/// Tells the probe when the bar came and went and where it sat, so a walk can
/// hold it to one frame and to the canvas (`TransformBarMeter`). Nothing at
/// all in the shipping app.
private struct TransformBarMetering: ViewModifier {
    let canvas: CGSize
    let floor: CGFloat
    let box: CGRect
    let side: TransformBar.Side

    func body(content: Content) -> some View {
        #if PHOTONZ_PLAYTEST
        content
            .onAppear { TransformBarMeter.shared.drawn(true) }
            .onDisappear { TransformBarMeter.shared.drawn(false) }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { TransformBarMeter.shared.size = $0 }
            .onChange(of: TransformBarMeter.Place(canvas: canvas, floor: floor, box: box, side: side),
                      initial: true) { _, place in
                TransformBarMeter.shared.place = place
            }
        #else
        content
        #endif
    }
}
