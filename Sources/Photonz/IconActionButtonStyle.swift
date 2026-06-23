import SwiftUI

/// Shared design language for small icon action buttons (history overlay,
/// Quick Access overlay, …): a circular hit target that stays quiet at rest,
/// shows a soft fill on hover, and a stronger fill + slight shrink while
/// pressed. Destructive buttons (`Button(role: .destructive)`) tint red
/// automatically. Use via `.buttonStyle(IconActionButtonStyle())` on a button
/// or a row of buttons.
struct IconActionButtonStyle: ButtonStyle {
    /// Diameter of the circular button.
    var diameter: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, diameter: diameter)
    }

    private struct IconButtonBody: View {
        let configuration: Configuration
        let diameter: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let destructive = configuration.role == .destructive
            let pressed = configuration.isPressed
            let active = pressed || hovering
            let tint: Color = destructive ? .red : .primary

            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? tint : Color.secondary)
                .frame(width: diameter, height: diameter)
                .background {
                    Circle().fill(tint.opacity(fillOpacity(pressed: pressed)))
                }
                .scaleEffect(pressed ? 0.90 : 1)
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.10), value: pressed)
        }

        private func fillOpacity(pressed: Bool) -> Double {
            if pressed { return 0.22 }
            if hovering { return 0.12 }
            return 0
        }
    }
}

/// The same design language as `IconActionButtonStyle`, but a content-sized
/// **capsule** for text (or text+icon) buttons like "Clear All": quiet at rest,
/// soft fill on hover, stronger fill + slight shrink while pressed; destructive
/// buttons tint red on interaction.
struct PillActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration)
    }

    private struct PillButtonBody: View {
        let configuration: Configuration
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
            if hovering { return 0.12 }
            return 0
        }
    }
}
