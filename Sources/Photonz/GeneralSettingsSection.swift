import AppKit
import PhotonzCore
import SwiftUI

/// Settings' General section: the one switch that says whether Photonz opens
/// by itself when you log in. It reads the system's own answer every time the
/// window comes forward, so a change made under System Settings > Login Items
/// shows here.
struct GeneralSettingsSection: View {
    @State private var state: OpenAtLogin.SystemState = LoginItem.service.state
    @State private var trouble: String? = LoginItem.launchTrouble

    var body: some View {
        let row = OpenAtLogin.row(state: state, trouble: trouble)
        Section {
            VStack(alignment: .leading, spacing: 4) {
                // The words and the switch apart, so the switch's own face is
                // what a walk presses, the way a hand clicks it.
                HStack {
                    Text(OpenAtLogin.label)
                    Spacer(minLength: 8)
                    Toggle(OpenAtLogin.label, isOn: Binding(get: { row.isOn }, set: { on in flip(on) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!LoginItem.isAvailable)
                        .playtestControl("General Open at login", detail: row.isOn ? "on" : "off")
                }
                if !LoginItem.isAvailable {
                    Text(OpenAtLogin.unavailableLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if let line = row.line {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Label(line, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        if row.offersLoginItems {
                            Button(OpenAtLogin.openLoginItemsButton) { LoginItem.openLoginItems() }
                                .playtestControl("General Open Login Items", detail: OpenAtLogin.openLoginItemsButton)
                        }
                    }
                }
            }
        } header: {
            Text(OpenAtLogin.sectionTitle)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            state = LoginItem.service.state
        }
    }

    private func flip(_ on: Bool) {
        trouble = OpenAtLogin.set(on, service: LoginItem.service)
        state = LoginItem.service.state
    }
}
