import SwiftUI

/// The system's blue (prominent) button while the window is in front, and its
/// plain bordered button while the window is behind another app.
///
/// With the window behind, macOS 26 draws a prominent button in light mode as
/// white words on a white pill: on the white title bar Edit Original's Done
/// vanished altogether (2026-10-09, reproduced with the probe behind and in
/// front). The bordered button is the system's own background look for a
/// button and keeps dark words on grey, so Done reads in both appearances,
/// and a person with the window in front sees the blue button unchanged.
struct ActiveProminentButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.appearsActive) private var appearsActive

        var body: some View {
            if appearsActive {
                Button(configuration).buttonStyle(.borderedProminent)
            } else {
                Button(configuration).buttonStyle(.bordered)
            }
        }
    }
}

extension PrimitiveButtonStyle where Self == ActiveProminentButtonStyle {
    /// `.borderedProminent` that stays readable with the window behind.
    static var activeProminent: ActiveProminentButtonStyle { ActiveProminentButtonStyle() }
}
