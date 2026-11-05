import AppKit
import PhotonzCore
import SwiftUI

/// Settings' list of the capture shortcuts: each key and whether it reaches
/// Photonz. Read again whenever the window comes forward, because the usual fix
/// is made over in System Settings.
struct CaptureShortcutsSettingsSection: View {
    let rows: () -> [CaptureShortcutReport.Row]

    @State private var shown: [CaptureShortcutReport.Row] = []

    var body: some View {
        Section("Capture Shortcuts") {
            ForEach(shown) { row in
                HStack(spacing: 8) {
                    Text(row.name)
                    Spacer(minLength: 8)
                    Text(row.keys)
                        .foregroundStyle(.secondary)
                    state(row.state)
                        .frame(minWidth: 150, alignment: .trailing)
                }
                .playtestTarget("Shortcut \(row.keys)", kind: .row, detail: row.state.label)
            }
            if shown.contains(where: { $0.state == .heldByMacOS || $0.state == .notRegistered }) {
                HStack {
                    Spacer()
                    Button(CaptureShortcutReport.settingsAction) { WelcomeController.openKeyboardSettings() }
                        .playtestControl(CaptureShortcutReport.settingsAction)
                }
            }
        }
        .onAppear { shown = rows() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            shown = rows()
        }
    }

    @ViewBuilder private func state(_ state: CaptureShortcutReport.State) -> some View {
        switch state {
        case .ready, .anotherPhotonz:
            Text(state.label).foregroundStyle(.secondary)
        case .heldByMacOS, .notRegistered:
            Label(state.label, systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.primary)
        }
    }
}
