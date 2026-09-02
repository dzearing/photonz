import SwiftUI

/// Shared design language for small icon action buttons (history overlay,
/// Quick Access overlay, …): a circular hit target that stays quiet at rest,
/// shows a soft fill on hover, and a stronger fill + slight shrink while
/// pressed. Destructive buttons (`Button(role: .destructive)`) tint red
/// automatically. Use via `.buttonStyle(IconActionButtonStyle())` on a button
/// or a row of buttons.
///
/// The floating tool bar speaks the same language through `.tool(isActive:in:)`
/// below: a full-weight glyph at rest, the same hover and pressed fills, and,
/// for the tool in hand, the accent circle that slides between buttons. One
/// style for both, so an icon button behaves the same wherever it sits.
struct IconActionButtonStyle: ButtonStyle {
    /// Diameter of the circular button.
    var diameter: CGFloat = 28
    /// The label's color while nothing is happening. Small action buttons
    /// rest at secondary and come up to primary under the pointer; a tool bar
    /// glyph rests at primary, because a tool is never a quiet extra.
    var restingTint: Color = .secondary
    /// Whether the label carries a font of its own that the style should
    /// leave alone (the tool bar's 15pt medium glyphs), or takes the style's
    /// 13pt semibold.
    var keepsLabelFont: Bool = false
    /// True for the tool in hand: the accent circle behind a white glyph.
    var isActive: Bool = false
    /// The namespace the accent circle slides in (`matchedGeometryEffect`),
    /// so picking another tool moves one circle instead of blinking two.
    var activeNamespace: Namespace.ID? = nil
    /// Whether clicks land anywhere in the square frame (a row of tools has
    /// no dead corners between neighbours) or only inside the circle.
    var squareHitTarget: Bool = false
    /// Whether the pointer gets a response. Off keeps only the press
    /// highlight a plain button has always had (no hover fill, no shrink),
    /// which is what Current ships for its tool bar.
    var pointerFeedback: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, style: self)
    }

    private struct IconButtonBody: View {
        let configuration: Configuration
        let style: IconActionButtonStyle
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let destructive = configuration.role == .destructive
            let pressed = configuration.isPressed
            let hovered = style.pointerFeedback && hovering
            let lit = pressed || hovered
            // Over the accent circle the wash is white, so the tool in hand
            // brightens under the pointer instead of going muddy.
            let tint: Color = style.isActive ? .white : (destructive ? .red : .primary)
            let foreground: Color = style.isActive ? .white : (lit ? tint : style.restingTint)

            configuration.label
                .font(style.keepsLabelFont ? nil : .system(size: 13, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: style.diameter, height: style.diameter)
                .background {
                    if style.isActive {
                        accentCircle
                    }
                    Circle().fill(tint.opacity(fillOpacity(pressed: pressed, hovered: hovered)))
                }
                .scaleEffect(pressed && style.pointerFeedback ? 0.90 : 1)
                .contentShape(style.squareHitTarget ? AnyShape(Rectangle()) : AnyShape(Circle()))
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.10), value: pressed)
        }

        @ViewBuilder private var accentCircle: some View {
            if let namespace = style.activeNamespace {
                Circle().fill(Color.accentColor)
                    .matchedGeometryEffect(id: "activeTool", in: namespace)
            } else {
                Circle().fill(Color.accentColor)
            }
        }

        private func fillOpacity(pressed: Bool, hovered: Bool) -> Double {
            if pressed { return 0.22 }
            if hovered { return 0.12 }
            return 0
        }
    }
}

extension ButtonStyle where Self == IconActionButtonStyle {
    /// A button in the floating tool bar, or any icon button that should read
    /// as one: full-weight glyph at rest, the shared hover and pressed fills,
    /// and the accent circle while it is the tool in hand. The pointer
    /// response follows the Next release's `next-tool-bar-feedback` flag;
    /// with it off the button draws its resting look and nothing more.
    @MainActor
    static func tool(isActive: Bool = false, in namespace: Namespace.ID? = nil,
                     diameter: CGFloat = 28) -> IconActionButtonStyle {
        IconActionButtonStyle(diameter: diameter,
                              restingTint: .primary,
                              keepsLabelFont: true,
                              isActive: isActive,
                              activeNamespace: namespace,
                              squareHitTarget: true,
                              pointerFeedback: Experiments.shared.toolBarFeedbackEnabled)
    }
}

/// The same design language as `IconActionButtonStyle`, but a content-sized
/// **capsule** for text (or text+icon) buttons like "Clear All": quiet at rest,
/// soft fill on hover, stronger fill + slight shrink while pressed; destructive
/// buttons tint red on interaction.
struct PillActionButtonStyle: ButtonStyle {
    /// A `prominent` pill keeps a soft fill at rest, so it reads as a button
    /// before anyone points at it (the capture toast's Edit row); the default
    /// is quiet until hovered.
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration, prominent: prominent)
    }

    private struct PillButtonBody: View {
        let configuration: Configuration
        let prominent: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let destructive = configuration.role == .destructive
            let pressed = configuration.isPressed
            let active = pressed || hovering
            let tint: Color = destructive ? .red : .primary

            configuration.label
                .font(.caption.weight(.medium))
                .foregroundStyle(active ? tint : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule().fill(tint.opacity(fillOpacity(pressed: pressed)))
                }
                .scaleEffect(pressed ? 0.96 : 1)
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.10), value: pressed)
        }

        private func fillOpacity(pressed: Bool) -> Double {
            if pressed { return 0.20 }
            if hovering { return prominent ? 0.14 : 0.12 }
            return prominent ? 0.08 : 0
        }
    }
}
