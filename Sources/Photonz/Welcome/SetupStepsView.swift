import AVFoundation
import PhotonzCore
import SwiftUI

/// The setup window as one step at a time (`next-setup-steps`, hosted by
/// `WelcomeController`): only the steps this Mac still needs and this person
/// has not seen (`SetupFlow`), then the tour offer when it is owed.
///
/// Each page is a short explainer, the one thing that does the step, and Skip.
/// Status is live, so granting access in System Settings turns the page done
/// while the person watches, and Continue takes over from Skip.
///
/// **One blue button at a time.** While the step has something to do, its own
/// action is the prominent one and the way on is a plain Skip; once it is done
/// the action goes and Continue is prominent and default.
struct SetupStepsView: View {
    let state: WelcomeState
    let onTakeTour: () -> Void
    let onGrantScreenRecording: () -> Void
    let onGrantMicrophone: () -> Void
    let onOpenKeyboardSettings: () -> Void
    let onRelaunch: () -> Void
    let onMoveOn: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 12)
            Group {
                if let step = state.run?.current {
                    page(step)
                        .id(step)
                } else if state.needsRelaunch {
                    relaunchPage
                } else {
                    tourPage
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            Spacer(minLength: 12)
            footer
        }
        .padding(20)
        .frame(width: 460, height: 420)
        .animation(.smooth(duration: 0.3), value: state.run?.index)
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
            Text(SetupFlow.windowHeading)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            if let counter = state.run?.counter {
                Text(counter)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .playtestControl("Setup \(counter)")
            }
        }
    }

    // MARK: - A step

    @ViewBuilder
    private func page(_ step: SetupStep) -> some View {
        let done = state.isDone(step)
        VStack(spacing: 12) {
            if step == .agents {
                SetupAgentsPicture(done: done)
            } else {
                stepSymbol(step, done: done)
            }
            Text(SetupFlow.title(step))
                .font(.title2.weight(.semibold))
                .playtestControl("Setup \(step.rawValue)", detail: done ? "done" : "to do")
            Text(words(step, done: done))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            action(step)
                .padding(.top, 4)
        }
        .animation(.easeOut(duration: 0.25), value: done)
    }

    private func stepSymbol(_ step: SetupStep, done: Bool) -> some View {
        let symbol = switch step {
        case .screenRecording: "rectangle.dashed.badge.record"
        case .microphone: "mic"
        case .screenshotKeys: "keyboard"
        case .agents: "terminal"
        }
        return Image(systemName: done ? "checkmark.circle.fill" : symbol)
            .font(.system(size: 34, weight: .regular))
            .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 72, height: 72)
            .background(.quinary, in: Circle())
    }

    private func words(_ step: SetupStep, done: Bool) -> String {
        let name = AppInfo.name
        switch step {
        case .screenRecording:
            if state.needsRelaunch { return SetupFlow.relaunchBody(appName: name) }
            if done { return SetupFlow.doneBody(step, appName: name) }
            let opening = SetupFlow.body(step, appName: name)
            return state.screenRecordingGrantAttempted
                ? opening + " " + SetupFlow.screenRecordingStuckHint : opening
        case .microphone:
            if done { return SetupFlow.doneBody(step, appName: name) }
            if state.microphone == .denied || state.microphone == .restricted {
                return SetupFlow.microphoneDeniedBody
            }
            return SetupFlow.body(step, appName: name)
        case .screenshotKeys:
            if done { return SetupFlow.doneBody(step, appName: name) }
            let keys = state.conflictingShortcuts.map(\.keyLabel).joined(separator: ", ")
            return SetupFlow.body(step, appName: name, keys: keys)
        case .agents:
            return SetupFlow.body(step, appName: name)
        }
    }

    @ViewBuilder
    private func action(_ step: SetupStep) -> some View {
        switch step {
        case .screenRecording:
            if state.needsRelaunch {
                Button("Relaunch \(AppInfo.name)") { onRelaunch() }
                    .buttonStyle(.borderedProminent)
                    .playtestControl("Setup Relaunch")
            } else if !state.screenRecordingGranted {
                Button("Open Screen Recording Settings…") { onGrantScreenRecording() }
                    .buttonStyle(.borderedProminent)
                    .playtestControl("Setup Open Screen Recording Settings")
            }
        case .microphone:
            switch state.microphone {
            case .authorized:
                EmptyView()
            case .notDetermined:
                Button("Allow Microphone") { onGrantMicrophone() }
                    .buttonStyle(.borderedProminent)
                    .playtestControl("Setup Allow Microphone")
            default:
                Button("Open Microphone Settings…") { onGrantMicrophone() }
                    .playtestControl("Setup Open Microphone Settings")
            }
        case .screenshotKeys:
            if !state.conflictingShortcuts.isEmpty {
                Button("Open Keyboard Settings…") { onOpenKeyboardSettings() }
                    .buttonStyle(.borderedProminent)
                    .playtestControl("Setup Open Keyboard Settings")
            }
        case .agents:
            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    ForEach(Array(state.agentToolsHere.enumerated()), id: \.element) { index, tool in
                        if index > 0 { Divider() }
                        agentRow(tool)
                    }
                }
                .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: 340)
                Text(SetupFlow.agentsAskLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func agentRow(_ tool: AgentSetup.Tool) -> some View {
        let name = AgentsSettingsSection.title(tool)
        let status = state.agentStatuses[tool]
        return HStack(spacing: 10) {
            Text(name)
                .font(.body.weight(.medium))
            Spacer(minLength: 8)
            if let trouble = state.agentTrouble[tool] {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .help(trouble)
            }
            if state.agentBusy == tool {
                ProgressView().controlSize(.small)
            } else {
                switch status?.state {
                case .notInstalled:
                    Button(SetupFlow.installButtonTitle) { state.installAgent(tool) }
                        .playtestControl("Setup Install \(name)")
                case .needsUpdate:
                    Button("Update") { state.installAgent(tool) }
                        .playtestControl("Setup Install \(name)")
                case .installed:
                    Label(SetupFlow.installedLabel, systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                        .playtestControl("Setup \(name) Installed")
                default:
                    EmptyView()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
    }

    // MARK: - The tour, and the restart

    private var tourPage: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("Welcome to \(AppInfo.name)")
                .font(.title2.weight(.semibold))
                .playtestControl("Setup tour")
            Text(SetupFlow.tourHeadline)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            VStack(spacing: 2) {
                Text("⇧⌘4 captures a region · ⇧⌘3 the full screen · ⇧⌘5 records")
                Text("⇧⌘6 opens the last capture for editing")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
    }

    /// The last page while a Screen Recording grant waits for a restart: the
    /// tour would be killed by it, so the restart is offered instead.
    private var relaunchPage: some View {
        VStack(spacing: 12) {
            stepSymbol(.screenRecording, done: true)
            Text("Relaunch \(AppInfo.name)")
                .font(.title2.weight(.semibold))
                .playtestControl("Setup relaunch")
            Text(SetupFlow.relaunchBody(appName: AppInfo.name))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Relaunch \(AppInfo.name)") { onRelaunch() }
                .buttonStyle(.borderedProminent)
                .playtestControl("Setup Relaunch")
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if state.run?.isLastPage == true {
                Text(SetupFlow.laterLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let step = state.run?.current {
                let title = state.run?.isLastPage == true
                    ? SetupFlow.doneButtonTitle : SetupFlow.continueButtonTitle
                if state.isDone(step) {
                    Button(title) { onMoveOn() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .playtestControl("Setup Continue", detail: title)
                } else {
                    Button(SetupFlow.skipButtonTitle) { onMoveOn() }
                        .keyboardShortcut(.cancelAction)
                        .playtestControl("Setup Skip")
                }
            } else if state.needsRelaunch {
                Button(SetupFlow.doneButtonTitle) { onFinish() }
                    .keyboardShortcut(.cancelAction)
                    .playtestControl("Setup Continue", detail: SetupFlow.doneButtonTitle)
            } else {
                Button(FirstRunOffer.skipButtonTitle) { onFinish() }
                    .keyboardShortcut(.cancelAction)
                    .playtestControl("Setup Start Working")
                if state.screenRecordingGranted {
                    Button(FirstRunOffer.tourButtonTitle) { onTakeTour() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .playtestControl("Setup Take the Tour")
                } else {
                    Button(FirstRunOffer.tourButtonTitle) { onTakeTour() }
                        .playtestControl("Setup Take the Tour")
                }
            }
        }
    }
}

/// The agents step's picture: a request typed to an agent on one side, and
/// Photonz answering it with a measurement on the other. Drawn in fixed dark
/// and light so its words read the same in either appearance.
private struct SetupAgentsPicture: View {
    let done: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Circle().fill(.red.opacity(0.85)).frame(width: 6, height: 6)
                    Circle().fill(.yellow.opacity(0.85)).frame(width: 6, height: 6)
                    Circle().fill(.green.opacity(0.85)).frame(width: 6, height: 6)
                }
                .padding(.bottom, 2)
                Text("› redline this screen")
                    .foregroundStyle(.white)
                Text(done ? "✓ done in Photonz" : "  measuring in Photonz…")
                    .foregroundStyle(Color(red: 0.55, green: 0.9, blue: 0.6))
            }
            .font(.system(size: 10.5, design: .monospaced))
            .padding(10)
            .frame(width: 190, height: 72, alignment: .topLeading)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 8))

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.97))
                    .frame(width: 84, height: 72)
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.82)).frame(width: 56, height: 10)
                    RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.82)).frame(width: 56, height: 10)
                    RoundedRectangle(cornerRadius: 3).fill(Color.accentColor).frame(width: 56, height: 12)
                }
                // The redline between the two fields.
                HStack(spacing: 0) {
                    Rectangle().fill(Color.red).frame(width: 1.5, height: 14)
                }
                .offset(x: 34, y: -8)
                Text("8")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 2))
                    .offset(x: 34, y: -24)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .offset(x: 8, y: 8)
            }
        }
        .frame(height: 84)
    }
}
