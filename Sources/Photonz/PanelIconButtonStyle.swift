import AppKit
import PhotonzCore
import SwiftUI

/// The small icon buttons on the panel's rows and headers: the eye, the
/// padlock, the cross that takes an effect out, the grip that reorders it.
///
/// Every one of them takes its tone from `IconButtonTone`, the one rule:
/// the system's label tone at rest (the eye's), a little brighter with a soft
/// wash under the pointer, a stronger wash while pressed, the secondary label
/// for a switch that is off, and the faint tertiary only when the button
/// cannot be pressed. A row button never sets its own colour, so a button you
/// can press never looks like one you cannot (the user, 2026-10-24: "buttons
/// which are active should not look diminished").
///
/// The label keeps its own font and frame; the style draws only the ink and
/// the wash behind it.
struct PanelIconButtonStyle: ButtonStyle {
    /// False for a switch that is off: a hidden layer's eye, an open padlock.
    var isOn: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration, isOn: isOn)
    }

    private struct IconBody: View {
        let configuration: Configuration
        let isOn: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.shownPointer) private var shown

        var body: some View {
            let look = ButtonPointerLook(enabled: isEnabled, hovering: hovering,
                                         pressed: configuration.isPressed || shown == .pressed)
            let tone = IconButtonTone(enabled: isEnabled, isOn: isOn, look: look)
            configuration.label
                .panelIconInk(tone)
                .playtestHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: tone)
        }
    }
}

extension ButtonStyle where Self == PanelIconButtonStyle {
    /// A panel row's icon button, toned by `IconButtonTone`.
    static func panelIcon(isOn: Bool = true) -> PanelIconButtonStyle {
        PanelIconButtonStyle(isOn: isOn)
    }
}

extension View {
    /// The same tone for an icon that is a control but not a `Button` (the
    /// reorder grip, which a drag drives): `active` while it is being used.
    func panelIconTone(active: Bool = false, enabled: Bool = true) -> some View {
        modifier(PanelIconToneModifier(active: active, enabled: enabled))
    }

    /// Draws an icon in a tone of the rule: the ink, and the wash behind it.
    fileprivate func panelIconInk(_ tone: IconButtonTone) -> some View {
        measuredInk()
            .foregroundStyle(PanelIconInk.ink(tone))
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(PanelIconInk.full.opacity(tone.wash))
            }
    }
}

/// The colours the rule's numbers are drawn in.
enum PanelIconInk {
    /// The full foreground: black in light, white in dark. The system's label
    /// colours are this at 0.85, 0.55 and 0.25, which is what the rule's
    /// numbers are.
    static let full = Color(nsColor: .textColor)

    static func ink(_ tone: IconButtonTone) -> Color { full.opacity(tone.ink) }
}

private struct PanelIconToneModifier: ViewModifier {
    let active: Bool
    let enabled: Bool
    @State private var hovering = false
    @Environment(\.shownPointer) private var shown

    func body(content: Content) -> some View {
        let look = ButtonPointerLook(enabled: enabled, hovering: hovering,
                                     pressed: active || shown == .pressed)
        let tone = IconButtonTone(enabled: enabled, look: look)
        content
            .panelIconInk(tone)
            .playtestHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: tone)
    }
}
