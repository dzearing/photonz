import AVFoundation
import PhotonzCore
import SwiftUI

/// The first-run setup card (hosted by `WelcomeController`): plain-language
/// steps with live status, so granting access in System Settings flips rows to
/// green while the user watches. Every step either does the work for them
/// (microphone) or lands them on the exact Settings pane (everything else).
struct WelcomeView: View {
    let state: WelcomeState
    let onGrantScreenRecording: () -> Void
    let onGrantMicrophone: () -> Void
    let onOpenKeyboardSettings: () -> Void
    let onRelaunch: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            screenRecordingStep
            microphoneStep
            if state.hadShortcutConflictsAtOpen || !state.conflictingShortcuts.isEmpty {
                shortcutsStep
            }
            footer
        }
        .padding(20)
        .frame(width: 480)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("Welcome to Photonz")
                    .font(.title2.weight(.semibold))
                Text("Photonz lives in your menu bar. Two quick macOS settings and you're ready to capture anything.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Steps

    private var screenRecordingStep: some View {
        WelcomeStepCard(
            done: state.screenRecordingGranted && !state.needsRelaunch,
            icon: "rectangle.dashed.badge.record",
            title: "Screen Recording",
            badge: "Required",
            body: state.screenRecordingGranted
                ? (state.needsRelaunch
                    ? "Access granted! macOS applies it when Photonz reopens — one click and you're done."
                    : "Photonz can capture your screen. You're all set here.")
                : "This is how Photonz takes screenshots and records video. macOS keeps the switch in System Settings — turn on Photonz there and come back; this window updates by itself. If Photonz isn't in the list, click the + button under it and add Photonz yourself (or drag it in from Finder)."
        ) {
            if state.needsRelaunch {
                Button("Relaunch Photonz") { onRelaunch() }
                    .buttonStyle(.borderedProminent)
            } else if !state.screenRecordingGranted {
                Button("Open Screen Recording Settings…") { onGrantScreenRecording() }
                    .buttonStyle(.borderedProminent)
                // For the click-+-and-add fallback: puts the app bundle in hand
                // so the user can pick or drag it without hunting for it.
                Button("Show Photonz in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
            }
        }
    }

    private var microphoneStep: some View {
        WelcomeStepCard(
            done: state.microphone == .authorized,
            icon: "mic",
            title: "Microphone",
            badge: "Optional",
            body: micBody
        ) {
            switch state.microphone {
            case .authorized:
                EmptyView()
            case .notDetermined:
                Button("Allow Microphone") { onGrantMicrophone() }
            default:
                Button("Open Microphone Settings…") { onGrantMicrophone() }
            }
        }
    }

    private var micBody: String {
        switch state.microphone {
        case .authorized:
            "Your voice can be included in screen recordings."
        case .denied, .restricted:
            "Microphone access is turned off. Only needed if you narrate screen recordings — enable it in System Settings if you'd like that."
        default:
            "Adds your voice to screen recordings. Skip it if you never narrate — you can allow it later when you first record with a mic."
        }
    }

    private var shortcutsStep: some View {
        let conflicts = state.conflictingShortcuts
        let keys = conflicts.map(\.keyLabel).joined(separator: ", ")
        return WelcomeStepCard(
            done: conflicts.isEmpty,
            icon: "keyboard",
            title: "Free up the screenshot keys",
            badge: "Recommended",
            body: conflicts.isEmpty
                ? "The screenshot keys now trigger Photonz."
                : "macOS's built-in screenshot feature still owns \(keys), so those keys can't reach Photonz yet. In Keyboard Settings choose Keyboard Shortcuts… → Screenshots and uncheck them."
        ) {
            if !conflicts.isEmpty {
                Button("Open Keyboard Settings…") { onOpenKeyboardSettings() }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("⇧⌘4 captures a region · ⇧⌘3 the full screen · ⇧⌘5 records")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if state.everythingReady {
                Button("Start Capturing") { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Not Now") { onFinish() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.top, 4)
    }
}

/// One setup step: status icon that flips to a green check, a short
/// plain-language explanation, and the step's action (if anything is left to do).
private struct WelcomeStepCard<Action: View>: View {
    let done: Bool
    let icon: String
    let title: String
    let badge: String
    let body_: String
    @ViewBuilder let action: Action

    init(done: Bool, icon: String, title: String, badge: String, body: String,
         @ViewBuilder action: () -> Action) {
        self.done = done
        self.icon = icon
        self.title = title
        self.badge = badge
        self.body_ = body
        self.action = action()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Image(systemName: done ? "checkmark.circle.fill" : icon)
                    .font(.title2)
                    .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Text(body_)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                action
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
        .animation(.easeOut(duration: 0.25), value: done)
    }
}
