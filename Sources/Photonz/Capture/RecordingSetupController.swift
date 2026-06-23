import AppKit
import PhotonzCore
import SwiftUI

/// Hosts the pre-recording setup card (phase 12.1 / 12.2): pick full-screen vs a
/// dragged region, and which audio to capture (system and/or a microphone). A
/// key-capable centered panel, since the menu-bar agent may have no other window.
@MainActor
final class RecordingSetupController {
    private var panel: NSPanel?

    func present(initial: RecordingConfig,
                 microphones: [(id: String, name: String)],
                 onStart: @escaping (RecordingConfig) -> Void) {
        dismiss()
        NSApp.activate(ignoringOtherApps: true)

        let view = RecordingSetupView(
            initial: initial,
            microphones: microphones,
            onStart: { [weak self] config in self?.dismiss(); onStart(config) },
            onCancel: { [weak self] in self?.dismiss() })

        let size = CGSize(width: 360, height: 260)
        let panel = KeyPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: view)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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
