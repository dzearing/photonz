import AppKit
import Observation
import PhotonzCore
import SwiftUI

/// Drives the floating stop control shown during a recording (phase 12.3): a
/// small always-on-top HUD with a pulsing red dot, elapsed time, and a Stop
/// button. Its window is handed back to the recorder so `SCContentFilter` can
/// **exclude it from the captured video**. Non-activating so it never steals
/// focus from whatever the user is recording.
///
/// It starts bottom left and can be dragged anywhere on the recorded screen by
/// any part that is not its button; where it is let go is remembered for every
/// later recording (`RecordingControlSpotStore`), and a double click on it puts
/// it back bottom left. Recording a region, it is kept outside the region.
@MainActor
final class RecordingControlsController {
    /// Observed by the SwiftUI HUD; the coordinator ticks `elapsed` each second.
    let model = RecordingHUDModel()
    private var panel: NSPanel?
    /// The visible area of the screen the control is up on, which a drag stays inside.
    private var visible: CGRect = .zero
    /// The recorded region in screen points, when a region is being recorded.
    private var region: CGRect?
    /// Where the window and the pointer were when the drag in hand began.
    private var dragFrom: (origin: CGPoint, pointer: CGPoint)?

    init() {
        model.onDrag = { [weak self] translation, ended in self?.drag(translation, ended: ended) }
        model.onReset = { [weak self] in self?.resetSpot() }
    }

    /// Shows the HUD on `screen` where the person last left it (bottom left
    /// until they move it) and returns its window so the recorder can exclude
    /// it from the capture. A control already put up for this screen by
    /// `prepare` is simply made visible.
    @discardableResult
    func show(on screen: NSScreen, source: RecordingSource, onStop: @escaping () -> Void) -> NSWindow {
        model.elapsed = 0
        model.onStop = onStop
        if let panel, isUp(on: screen, source: source) {
            panel.alphaValue = 1
            panel.ignoresMouseEvents = false
            return panel
        }
        hide()
        let panel = makePanel(on: screen, source: source)
        panel.orderFrontRegardless()
        self.panel = panel
        return panel
    }

    #if PHOTONZ_PLAYTEST
    var playtestIsUp: Bool { panel != nil }
    /// The control's window, for the probe's drill of moving it.
    var playtestPanel: NSPanel? { panel }
    /// Where the drill's pointer is, in screen points; the real pointer when nil.
    static var playtestPointer: CGPoint?
    /// The start-latency drill puts the control over the region it records on
    /// purpose, to prove the control is left out of the picture there too.
    static var playtestKeepsOverRegion = false
    /// The level the drill puts the control at, under every other app's
    /// window, so it never covers the person's work.
    static var playtestLevel: NSWindow.Level?
    #endif

    /// Whether the control's window already exists on `screen`, placed for `source`.
    func isUp(on screen: NSScreen, source: RecordingSource) -> Bool {
        panel?.frame == Self.frame(on: screen, source: source)
    }

    /// Puts the control up on `screen` without anyone seeing it or being able
    /// to click it, so its window exists for a stream warmed while the
    /// recording card is up to leave out. `show` makes it visible.
    func prepare(on screen: NSScreen, source: RecordingSource) -> NSWindow {
        if let panel, isUp(on: screen, source: source) { return panel }
        hide()
        model.elapsed = 0
        let panel = makePanel(on: screen, source: source)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        self.panel = panel
        return panel
    }

    private func makePanel(on screen: NSScreen, source: RecordingSource) -> NSPanel {
        let frame = Self.frame(on: screen, source: source)
        visible = screen.visibleFrame
        region = Self.region(of: source, on: screen)
        let size = frame.size
        let panel = NonactivatingPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "Recording Control"
        panel.isFloatingPanel = true
        panel.level = .statusBar
        #if PHOTONZ_PLAYTEST
        if let playtestLevel = Self.playtestLevel { panel.level = playtestLevel }
        #endif
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

    /// Where the stop control sits on `screen` recording `source`: where the
    /// person last left it, measured from the nearest corner, bottom left
    /// until they move it, inside the visible area and outside the region.
    static func frame(on screen: NSScreen, source: RecordingSource) -> CGRect {
        var region = region(of: source, on: screen)
        #if PHOTONZ_PLAYTEST
        if playtestKeepsOverRegion { region = nil }
        #endif
        return RecordingControlPlacement.frame(spot: RecordingControlSpotStore.spot,
                                               visible: screen.visibleFrame, region: region)
    }

    private static func region(of source: RecordingSource, on screen: NSScreen) -> CGRect? {
        guard case .region(let rect) = source else { return nil }
        return RecordingControlPlacement.screenRect(ofRegion: rect, screenFrame: screen.frame)
    }

    private static var pointer: CGPoint {
        #if PHOTONZ_PLAYTEST
        if let playtestPointer { return playtestPointer }
        #endif
        return NSEvent.mouseLocation
    }

    /// Follows the pointer while the control is dragged, inside the visible
    /// area of its screen, and remembers where it was let go. `translation`
    /// is how far the pointer had gone when the drag was recognised, in
    /// SwiftUI's y-down points, so the control does not jump by the few
    /// points it takes to tell a drag from a click. The window moving keeps
    /// its window number, so the recording still leaves it out.
    private func drag(_ translation: CGSize, ended: Bool) {
        guard let panel else { return }
        let pointer = Self.pointer
        if dragFrom == nil {
            dragFrom = (panel.frame.origin,
                        CGPoint(x: pointer.x - translation.width, y: pointer.y + translation.height))
        }
        guard let from = dragFrom else { return }
        let moved = CGRect(origin: CGPoint(x: from.origin.x + pointer.x - from.pointer.x,
                                           y: from.origin.y + pointer.y - from.pointer.y),
                           size: panel.frame.size)
        panel.setFrameOrigin(RecordingControlPlacement.clamped(moved, into: visible).origin)
        if ended {
            dragFrom = nil
            RecordingControlSpotStore.spot = RecordingControlPlacement.spot(for: panel.frame, visible: visible)
        }
    }

    /// Back to bottom left, forgetting where it was left.
    private func resetSpot() {
        RecordingControlSpotStore.spot = nil
        guard let panel else { return }
        let home = RecordingControlPlacement.frame(spot: nil, visible: visible, region: region)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(home, display: true)
        }
    }

    func updateElapsed(_ seconds: TimeInterval) {
        model.elapsed = seconds
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        dragFrom = nil
    }
}

/// Where the person left the recording control, kept across launches.
@MainActor
enum RecordingControlSpotStore {
    static let defaultsKey = "photonz.recordingControlSpot"

    static var spot: RecordingControlSpot? {
        get {
            UserDefaults.standard.data(forKey: defaultsKey)
                .flatMap { try? JSONDecoder().decode(RecordingControlSpot.self, from: $0) }
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            }
        }
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
    /// The control is being dragged: how far the pointer has gone, and whether it was let go.
    @ObservationIgnored var onDrag: (CGSize, Bool) -> Void = { _, _ in }
    /// A double click on the control: back to its first spot.
    @ObservationIgnored var onReset: () -> Void = {}
}

/// The HUD card. Liquid Glass to match the other overlays.
private struct RecordingControlsView: View {
    @Bindable var model: RecordingHUDModel
    @State private var pulse = false
    /// Where the Stop button is in the window. A press that begins on it is
    /// the button's: SwiftUI hands the button's drag to the control's own
    /// gesture once the button lets go, which made the control jump.
    @State private var stopFrame: CGRect = .zero

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
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { stopFrame = $0 }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .capsule)
        // Anywhere but the button picks the control up; the button keeps its
        // own clicks.
        .contentShape(.capsule)
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged {
                    guard !stopFrame.contains($0.startLocation) else { return }
                    model.onDrag($0.translation, false)
                }
                .onEnded {
                    guard !stopFrame.contains($0.startLocation) else { return }
                    model.onDrag($0.translation, true)
                })
        .onTapGesture(count: 2) { model.onReset() }
        .padding(6)
        .onAppear { pulse = true }
    }
}
