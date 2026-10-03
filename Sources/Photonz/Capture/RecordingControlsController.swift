import AppKit
import Observation
import PhotonzCore
import SwiftUI

/// Drives the floating stop control shown during a recording (phase 12.3): a
/// small always-on-top HUD with a pulsing red dot, elapsed time, and a Stop
/// button. Its window is handed back to the recorder so `SCContentFilter` can
/// **exclude it from the captured video**. Non-activating so it never steals
/// focus from whatever the user is recording.
@MainActor
final class RecordingControlsController {
    /// Observed by the SwiftUI HUD; the coordinator ticks `elapsed` each second.
    let model = RecordingHUDModel()
    private var panel: NSPanel?

    /// Shows the HUD top-center of `screen` and returns its window so the
    /// recorder can exclude it from the capture. A control already put up
    /// for this screen by `prepare` is simply made visible.
    @discardableResult
    func show(on screen: NSScreen, onStop: @escaping () -> Void) -> NSWindow {
        model.elapsed = 0
        model.onStop = onStop
        if let panel, panel.frame == Self.frame(on: screen) {
            panel.alphaValue = 1
            panel.ignoresMouseEvents = false
            return panel
        }
        hide()
        let panel = makePanel(on: screen)
        panel.orderFrontRegardless()
        self.panel = panel
        return panel
    }

    #if PHOTONZ_PLAYTEST
    var playtestIsUp: Bool { panel != nil }
    #endif

    /// Whether the control's window already exists on `screen`.
    func isUp(on screen: NSScreen) -> Bool {
        panel?.frame == Self.frame(on: screen)
    }

    /// Puts the control up on `screen` without anyone seeing it or being able
    /// to click it, so its window exists for a stream warmed while the
    /// recording card is up to leave out. `show` makes it visible.
    func prepare(on screen: NSScreen) -> NSWindow {
        if let panel, panel.frame == Self.frame(on: screen) { return panel }
        hide()
        model.elapsed = 0
        let panel = makePanel(on: screen)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        self.panel = panel
        return panel
    }

    private func makePanel(on screen: NSScreen) -> NSPanel {
        let frame = Self.frame(on: screen)
        let size = frame.size
        let panel = NonactivatingPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hosting = NSHostingView(rootView: RecordingControlsView(model: model))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.setFrameOrigin(frame.origin)
        return panel
    }

    /// Where the stop control sits on `screen`: top centre, just under the
    /// menu bar, in screen points.
    static func frame(on screen: NSScreen) -> CGRect {
        let size = CGSize(width: 232, height: 52)
        let vf = screen.visibleFrame
        return CGRect(origin: CGPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 12), size: size)
    }

    func updateElapsed(_ seconds: TimeInterval) {
        model.elapsed = seconds
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Borderless panels reject key/main by default; the stop HUD wants neither (it
/// must not steal focus from the recording), so this is purely for clarity.
private final class NonactivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
@Observable
final class RecordingHUDModel {
    var elapsed: TimeInterval = 0
    @ObservationIgnored var onStop: () -> Void = {}
}

/// The HUD card. Liquid Glass to match the other overlays.
private struct RecordingControlsView: View {
    @Bindable var model: RecordingHUDModel
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            Text(RecordingClock.elapsedString(model.elapsed))
                .font(.system(.body, design: .monospaced).weight(.medium))
                .contentTransition(.numericText())
            Spacer(minLength: 4)
            Button {
                model.onStop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .capsule)
        .padding(6)
        .onAppear { pulse = true }
    }
}
