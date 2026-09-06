import AppKit
import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

/// The one thing that makes a colour swatch draggable, and droppable on.
///
/// It goes on the two wells the panel is built out of — `ColorWellButton` and
/// `SelectionColorWell` — so Outline, Fill, Text, the shadow's colour and a
/// collage backdrop all behave the same way without any of them knowing about
/// drag and drop. A third kind of well added tomorrow gets it by wearing this.
/// The toolbar's own swatches wear it too, so the colour the next shape comes
/// out in can be carried off the bar and kept, and a colour let go of on the
/// bar arms the tool with it.
///
/// What it puts on screen while a colour is in the air is deliberately the
/// least a Mac can say and still be understood: the swatch that would take the
/// colour lights up, the swatch that would not stays dark and the pointer shows
/// the no-entry sign. The one exception is a swatch wearing a SAVED colour,
/// where letting go costs something the ring alone cannot say, so the palette
/// mark the whole app uses for a saved colour rides on the ring. The sentence
/// under that is said out loud by the canvas AFTER the drop, by the same
/// "stopped following Accent" pill every other way of letting go raises.
struct ColorSwatchDrag: ViewModifier {
    /// Which swatch this is, so a colour dropped straight back where it came
    /// from can be refused rather than written into history as a no-op. The
    /// same key the well already answers to when a walk opens its picker.
    let key: String
    /// What this swatch paints, in its row's own words. The refusals are
    /// written out of it.
    let part: String
    /// What the swatch is wearing, read at the moment of the drag. Nil for a
    /// swatch with no one colour to give — a row that says Mixed — which can
    /// be picked up and carries nothing, so every other swatch refuses it.
    let paint: () -> Paint?
    /// The saved colour it wears, by name, when it wears one.
    let styleName: () -> String?
    /// How many layers letting go here would paint.
    let reaches: () -> Int
    /// Whether this swatch can hold a ramp.
    let acceptsGradient: Bool
    /// How round the ring is. Every swatch in the panel is a rounded square,
    /// which is the default; the bar's own swatch is a circle, and a boxy ring
    /// around a round chip looks like a mistake rather than a promise.
    let ringCornerRadius: CGFloat
    /// Letting go. One undo step, however many layers it reached.
    let onDrop: (ColorDrop.Landing) -> Void

    /// The answer to whatever is being held over this swatch right now. Nil
    /// when nothing is, and when what is being held is not a colour at all.
    @State private var incoming: ColorDrop.Answer?

    @ViewBuilder func body(content: Content) -> some View {
        // Off in the release that ships today, where a swatch is click only and
        // exactly what it always was.
        if Experiments.shared.colorDragEnabled {
            picked(content)
        } else {
            content
        }
    }

    private func picked(_ content: Content) -> some View {
        content
            // A picture of the colour follows the pointer, so picking a colour
            // up looks like picking anything up on a Mac. Nothing in here
            // touches the app's state: a change made while the drag is being
            // handed over redraws the swatch and SwiftUI asks all over again.
            .onDrag(item, preview: { travelling })
            .overlay { ring }
            .onDrop(of: ColorDrag.acceptedTypes,
                    delegate: ColorSwatchDropDelegate(target: target,
                                                      incoming: $incoming,
                                                      apply: onDrop))
            // The sentence the swatch would say. A tip does not show while a
            // drag is in the air, so this is here for the times the pointer
            // rests on a swatch mid-thought, and for the accessibility reader.
            .accessibilityValue(incoming?.note ?? "")
    }

    /// What dragging this swatch hands over. A swatch with no one colour hands
    /// over an empty carrier, which every other swatch refuses: dragging the
    /// word Mixed cannot mean anything, and starting a drag that then does
    /// nothing is more honest than a swatch that ignores the pull.
    private func item() -> NSItemProvider {
        guard let paint = paint() else { return NSItemProvider() }
        return ColorDrag.itemProvider(paint: paint, source: key)
    }

    /// The colour under the pointer while it travels.
    private var travelling: some View {
        PaintFill(paint: paint() ?? Paint(hex: "#FFFFFF"))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .background(CheckerBoard(square: 4).clipShape(RoundedRectangle(cornerRadius: 4)))
            .frame(width: 22, height: 22)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(.primary.opacity(0.35), lineWidth: 1))
    }

    /// This swatch as the thing being dropped on, worked out fresh every time
    /// so a selection that changed under an open drag is the one answered for.
    private func target(source: String) -> ColorDrop.Target {
        ColorDrop.Target(part: part,
                         wearing: paint() ?? Paint(hex: "#FFFFFF"),
                         styleName: styleName(),
                         reaches: paint() == nil ? 1 : reaches(),
                         isSource: !source.isEmpty && source == key,
                         acceptsGradient: acceptsGradient)
    }

    /// What the swatch about to take a colour looks like: a ring around it,
    /// outside its own hairline so the colour underneath is untouched, plus
    /// the palette mark when letting go here lets go of a saved colour.
    @ViewBuilder private var ring: some View {
        if let landing = incoming?.landing {
            RoundedRectangle(cornerRadius: ringCornerRadius)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .padding(-3)
                .overlay(alignment: .topTrailing) {
                    if landing.letsGoOf != nil {
                        Image(systemName: "swatchpalette")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(Circle().fill(Color.accentColor))
                            .offset(x: 6, y: -6)
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

/// The swatch as a drop target.
///
/// The paint is READ before the pointer is let go, because the ring is a
/// promise about what letting go would do. It comes off the drag pasteboard
/// rather than out of the carrier the drop hands over: a carrier gives up its
/// bytes asynchronously, and a ring that appears two frames after the pointer
/// arrives is a ring that flickers on an 18pt square.
private struct ColorSwatchDropDelegate: DropDelegate {
    /// This swatch, told which swatch the colour in the air came from.
    let target: (String) -> ColorDrop.Target
    @Binding var incoming: ColorDrop.Answer?
    let apply: (ColorDrop.Landing) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: ColorDrag.acceptedTypes).isEmpty
    }

    func dropEntered(info: DropInfo) {
        incoming = answer()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let answer = answer()
        if incoming != answer { incoming = answer }
        return DropProposal(operation: answer?.lightsUp == true ? .copy : .forbidden)
    }

    func dropExited(info: DropInfo) {
        incoming = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let landing = answer()?.landing
        incoming = nil
        guard let landing else { return false }
        apply(landing)
        return true
    }

    /// What this swatch would do with whatever is in the air right now.
    private func answer() -> ColorDrop.Answer? {
        guard let payload = ColorDrag.payloadInFlight() else { return nil }
        return ColorDrop.answer(dropping: payload.paint, on: target(payload.source))
    }
}

extension View {
    /// Makes this swatch something a colour can be pulled off and dropped onto.
    func colorSwatchDrag(key: String, part: String,
                         paint: @escaping () -> Paint?,
                         styleName: @escaping () -> String? = { nil },
                         reaches: @escaping () -> Int = { 1 },
                         acceptsGradient: Bool = false,
                         ringCornerRadius: CGFloat = 6,
                         onDrop: @escaping (ColorDrop.Landing) -> Void) -> some View {
        modifier(ColorSwatchDrag(key: key, part: part, paint: paint, styleName: styleName,
                                 reaches: reaches, acceptsGradient: acceptsGradient,
                                 ringCornerRadius: ringCornerRadius, onDrop: onDrop))
    }
}
