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

    /// Watches the card's close button, which closes it without Cancel.
    private var closeObserver: NSObjectProtocol?
    private var onCancel: () -> Void = {}

    /// The card's window while it is up.
    var window: NSWindow? { panel }

    /// `onChange` hears every choice made on the card as it is made, and
    /// `onCancel` every way the card goes away without a recording (Cancel,
    /// Escape, its close button).
    func present(initial: RecordingConfig,
                 microphones: [(id: String, name: String)],
                 onChange: @escaping (RecordingConfig) -> Void = { _ in },
                 onCancel: @escaping () -> Void = {},
                 onStart: @escaping (RecordingConfig) -> Void) {
        dismiss()
        self.onCancel = onCancel

        // The hotkey fires without activating Photonz, so the frontmost app here
        // is still whatever the user was in (the browser, an editor, …). Remember
        // it so dismiss can return focus rather than let an editor window claim it.
        let current = NSRunningApplication.current
        previousApp = NSWorkspace.shared.frontmostApplication.flatMap { $0 == current ? nil : $0 }

        let view = RecordingSetupView(
            initial: initial,
            microphones: microphones,
            onChange: onChange,
            onStart: { [weak self] config in
                // A full-screen recording starts first: the card is left out
                // of its picture, and handing focus back to the person's app
                // costs several milliseconds the first frame should not wait
                // behind. A region's overlay has to come up after focus is
                // handed back, or the hand-back takes the overlay's keys.
                guard config.source == .fullDisplay else {
                    self?.dismiss()
                    onStart(config)
                    return
                }
                onStart(config)
                Task { @MainActor in self?.dismiss() }
            },
            onCancel: { [weak self] in self?.dismiss(); onCancel() })

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
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel === panel else { return }
                let cancel = self.onCancel
                self.dismiss()
                cancel()
            }
        }
        panel.orderFrontRegardless()
        #if PHOTONZ_PLAYTEST
        if !playtestLeavesKeyAlone { panel.makeKey() }
        #else
        panel.makeKey()
        #endif
        self.panel = panel
    }

    #if PHOTONZ_PLAYTEST
    /// Probe only: put the card up without taking the keyboard from whoever is
    /// typing, for the start drill.
    var playtestLeavesKeyAlone = false

    /// Probe only: press Return on the card, the way the person's Enter
    /// reaches its default button. False when the card did not take it.
    @discardableResult
    func playtestPressReturn() -> Bool {
        guard let panel,
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: panel.windowNumber, context: nil,
                                           characters: "\r", charactersIgnoringModifiers: "\r",
                                           isARepeat: false, keyCode: 36)
        else { return false }
        return panel.performKeyEquivalent(with: event)
    }

    /// Probe only: press Escape on the card, which is its Cancel.
    @discardableResult
    func playtestPressEscape() -> Bool {
        guard let panel,
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: panel.windowNumber, context: nil,
                                           characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                           isARepeat: false, keyCode: 53)
        else { return false }
        return panel.performKeyEquivalent(with: event)
    }
    #endif

    func dismiss() {
        // Hand focus back BEFORE ordering the panel out: re-activating the prior
        // app first means AppKit never promotes an editor window to key, so the
        // app doesn't flash to the foreground. Regifting focus only when a *different*
        // app was frontmost keeps the "invoked from within Photonz" case put.
        if let previousApp, !previousApp.isTerminated {
            AppFront.activate(previousApp)
        }
        previousApp = nil
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
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
    let onChange: (RecordingConfig) -> Void
    let onStart: (RecordingConfig) -> Void
    let onCancel: () -> Void

    @State private var source: SourceChoice
    @State private var systemAudio: Bool
    @State private var micID: String?  // nil = no microphone

    init(initial: RecordingConfig,
         microphones: [(id: String, name: String)],
         onChange: @escaping (RecordingConfig) -> Void,
         onStart: @escaping (RecordingConfig) -> Void,
         onCancel: @escaping () -> Void) {
        self.microphones = microphones
        self.onChange = onChange
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

            HStack(spacing: 8) {
                Text("Capture")
                SegmentedControl("Capture", selection: $source,
                                 options: [.init(SourceChoice.full, "Full Screen"),
                                           .init(SourceChoice.region, "Region…")])
            }

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
        .onAppear { onChange(chosen) }
        .onChange(of: source) { onChange(chosen) }
        .onChange(of: systemAudio) { onChange(chosen) }
        .onChange(of: micID) { onChange(chosen) }
    }

    private func start() { onStart(chosen) }

    private var chosen: RecordingConfig {
        var audio: AudioSources = []
        if systemAudio { audio.insert(.systemAudio) }
        if micID != nil { audio.insert(.microphone) }
        // Region rect is a placeholder here; the selection overlay fills it in.
        let src: RecordingSource = source == .region ? .region(.zero) : .fullDisplay
        return RecordingConfig(source: src, audio: audio, microphoneDeviceID: micID, format: .mp4)
    }
}
