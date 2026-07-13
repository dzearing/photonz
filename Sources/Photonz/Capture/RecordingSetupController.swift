import AppKit
import PhotonzCore
import SwiftUI

/// Hosts the pre-recording setup card (phase 12.1 / 12.2): pick full-screen vs a
/// dragged region, and which audio to capture (system and/or a microphone). A
/// key-capable centered panel, since the menu-bar agent may have no other window.
@MainActor
final class RecordingSetupController {
    private var panel: NSPanel?
    /// Whoever was frontmost when the card appeared. The card is non-activating,
    /// so it floats over the user's current app without pulling Photonz forward —
    /// but `orderOut`ing a key panel makes AppKit hand key status to the next
    /// window (an open editor), which drags the app to the foreground. Restoring
    /// this app on dismiss keeps focus where the user left it.
    private var previousApp: NSRunningApplication?

    func present(initial: RecordingConfig,
                 microphones: [(id: String, name: String)],
                 onStart: @escaping (RecordingConfig) -> Void) {
        dismiss()

        // The hotkey fires without activating Photonz, so the frontmost app here
        // is still whatever the user was in (the browser, an editor, …). Remember
        // it so dismiss can return focus rather than let an editor window claim it.
        let current = NSRunningApplication.current
        previousApp = NSWorkspace.shared.frontmostApplication.flatMap { $0 == current ? nil : $0 }

        let view = RecordingSetupView(
            initial: initial,
            microphones: microphones,
            onStart: { [weak self] config in self?.dismiss(); onStart(config) },
            onCancel: { [weak self] in self?.dismiss() })

        let size = CGSize(width: 360, height: 260)
        // A non-activating panel: it takes key focus on its own (so its buttons
        // and the default Return action work even when the agent has no other
        // window) WITHOUT activating Photonz. Activating the app here would drag
        // every open editor/recording window to the foreground — exactly what
        // the history overlay avoids for the same reason.
        let panel = KeyPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: view)
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel
    }

    func dismiss() {
        // Hand focus back BEFORE ordering the panel out: re-activating the prior
        // app first means AppKit never promotes an editor window to key, so the
        // app doesn't flash to the foreground. Regifting focus only when a *different*
        // app was frontmost keeps the "invoked from within Photonz" case put.
        if let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
        previousApp = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class KeyPanel: NSPanel {
    // Key (so the segmented control, toggles, and Return/Escape work) but never
    // main — a main window would pull the app forward, defeating the whole point
    // of the non-activating panel.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct RecordingSetupView: View {
    enum SourceChoice: Hashable { case full, region }

    let microphones: [(id: String, name: String)]
    let onStart: (RecordingConfig) -> Void
    let onCancel: () -> Void

    @State private var source: SourceChoice
    @State private var systemAudio: Bool
    @State private var micID: String?  // nil = no microphone

    init(initial: RecordingConfig,
         microphones: [(id: String, name: String)],
         onStart: @escaping (RecordingConfig) -> Void,
         onCancel: @escaping () -> Void) {
        self.microphones = microphones
        self.onStart = onStart
        self.onCancel = onCancel
        if case .region = initial.source { _source = State(initialValue: .region) }
        else { _source = State(initialValue: .full) }
        _systemAudio = State(initialValue: initial.audio.capturesSystemAudio)
        // Only honor a saved mic if it's still attached.
        let savedMic = initial.audio.capturesMicrophone ? initial.microphoneDeviceID : nil
        _micID = State(initialValue: microphones.contains { $0.id == savedMic } ? savedMic : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Record Screen")
                .font(.title3.weight(.semibold))

            Picker("Capture", selection: $source) {
                Text("Full Screen").tag(SourceChoice.full)
                Text("Region…").tag(SourceChoice.region)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("System Audio", isOn: $systemAudio)
                Picker("Microphone", selection: $micID) {
                    Text("None").tag(String?.none)
                    ForEach(microphones, id: \.id) { mic in
                        Text(mic.name).tag(String?.some(mic.id))
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(source == .region ? "Choose Region…" : "Start Recording") { start() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func start() {
        var audio: AudioSources = []
        if systemAudio { audio.insert(.systemAudio) }
        if micID != nil { audio.insert(.microphone) }
        // Region rect is a placeholder here; the selection overlay fills it in.
        let src: RecordingSource = source == .region ? .region(.zero) : .fullDisplay
        onStart(RecordingConfig(source: src, audio: audio, microphoneDeviceID: micID, format: .mp4))
    }
}
