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
    /// recorder can exclude it from the capture.
    @discardableResult
    func show(on screen: NSScreen, onStop: @escaping () -> Void) -> NSWindow {
        model.elapsed = 0
        model.onStop = onStop

        let size = CGSize(width: 232, height: 52)
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

        let vf = screen.visibleFrame
        let origin = CGPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 12)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        self.panel = panel
        return panel
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
