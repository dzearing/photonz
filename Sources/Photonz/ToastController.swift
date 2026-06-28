import AppKit
import SwiftUI

/// Bottom-right capture toasts (replaces popping the whole history overlay after
/// a capture). Each toast is its own borderless, non-activating panel so the
/// gaps between toasts let clicks fall through to whatever's underneath, and the
/// stack can re-flow by animating each panel's frame independently.
///
/// Newest toast sits in the corner; older ones stack upward. Adding pushes the
/// stack up; dismissing lets the ones above slide back down. Each toast holds
/// full opacity for 2s, fades over the next 5s, then removes itself — unless the
/// pointer is over it, which pins it open and reveals Edit / Dismiss.
@MainActor
final class ToastController {
    private final class Item {
        let id = UUID()
        let panel: NSPanel
        init(panel: NSPanel) { self.panel = panel }
    }

    /// Index 0 is the newest (corner-most) toast; later indices stack upward.
    private var items: [Item] = []
    private var screen: NSScreen?

    private let margin: CGFloat = 16
    private let spacing: CGFloat = 10
    /// Keep the stack from marching off the top of the screen on a capture burst.
    private let maxVisible = 5

    /// Show a toast for a freshly captured image. `onEdit` opens it for editing.
    func present(image: NSImage, message: String, on screen: NSScreen,
                 onEdit: @escaping () -> Void) {
        self.screen = screen

        // Soft-cap the stack: drop the oldest before adding a new one.
        while items.count >= maxVisible, let oldest = items.last {
            remove(oldest.id, animated: false)
        }

        let panel = makePanel()
        let item = Item(panel: panel)
        let id = item.id

        let view = ToastView(
            image: image,
            message: message,
            onEdit: { [weak self] in onEdit(); self?.remove(id, animated: true) },
            onDismiss: { [weak self] in self?.remove(id, animated: true) })
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        panel.setContentSize(size)
        panel.contentView = hosting

        items.insert(item, at: 0)

        // Place the new toast directly in the corner slot — the toast's own
        // content fades itself in (SwiftUI), and the already-present toasts
        // animate upward to make room. (We must position directly, not via the
        // window animator, which silently no-ops on these borderless panels.)
        let vf = screen.visibleFrame
        panel.setFrame(CGRect(x: vf.maxX - margin - size.width,
                              y: vf.minY + margin,
                              width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        layout(animated: true)
    }

    private func remove(_ id: UUID, animated: Bool) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: idx)
        item.panel.orderOut(nil)
        layout(animated: animated)
    }

    /// Re-stack every toast from the corner upward. `animated` slides each panel
    /// from its current origin to its slot; the newest (just placed) doesn't move.
    private func layout(animated: Bool) {
        guard let screen else { return }
        let vf = screen.visibleFrame
        var moves: [(panel: NSPanel, from: CGPoint, to: CGPoint)] = []
        var y = vf.minY + margin
        for item in items {
            let size = item.panel.frame.size
            let target = CGPoint(x: vf.maxX - margin - size.width, y: y)
            moves.append((item.panel, item.panel.frame.origin, target))
            y += size.height + spacing
        }
        if animated {
            animate(moves)
        } else {
            for m in moves { m.panel.setFrameOrigin(m.to) }
        }
    }

    // MARK: - Frame animation

    // NSWindow's `.animator()` proxy doesn't move these borderless non-activating
    // panels, so we interpolate origins ourselves on a main-runloop timer.
    private var animTimer: Timer?
    private var animStart: Date?
    private var animDuration: TimeInterval = 0.32
    private var animMoves: [(panel: NSPanel, from: CGPoint, to: CGPoint)] = []

    private func animate(_ moves: [(panel: NSPanel, from: CGPoint, to: CGPoint)]) {
        animTimer?.invalidate()
        // Re-base each move on where the panel actually is right now (so a new
        // toast arriving mid-slide continues smoothly from the live position).
        animMoves = moves.map { ($0.panel, $0.panel.frame.origin, $0.to) }
        animStart = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        animTimer = timer
    }

    private func tick() {
        guard let animStart else { animTimer?.invalidate(); animTimer = nil; return }
        let raw = animDuration > 0 ? min(1, Date().timeIntervalSince(animStart) / animDuration) : 1
        let e = 1 - pow(1 - raw, 3) // easeOutCubic
        for m in animMoves {
            m.panel.setFrameOrigin(CGPoint(x: m.from.x + (m.to.x - m.from.x) * e,
                                           y: m.from.y + (m.to.y - m.from.y) * e))
        }
        if raw >= 1 {
            animTimer?.invalidate()
            animTimer = nil
            self.animStart = nil
        }
    }

    private func makePanel() -> NSPanel {
        let panel = ToastPanel(contentRect: .zero,
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}

/// A toast never takes keyboard focus — it must not pull the key window away
/// from whatever the user is typing in (that caused stray keystrokes + beeps).
/// Mouse events (hover, Edit/Dismiss clicks) still reach it without key status.
private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One capture toast: the thumbnail with a "Copied to clipboard" caption,
/// Liquid Glass surface. Self-driving lifecycle (hold → fade → dismiss); hover
/// pins it open at full opacity and reveals Edit / Dismiss.
private struct ToastView: View {
    let image: NSImage
    let message: String
    var onEdit: () -> Void
    var onDismiss: () -> Void

    @State private var hovering = false
    @State private var opacity: Double = 0 // fades in on appear
    @State private var lifecycle: Task<Void, Never>?

    private let holdSeconds: Double = 7
    private let fadeSeconds: Double = 3

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 196, height: 124)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.12)))
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .overlay(alignment: .topTrailing) { hoverControls }
        .opacity(opacity)
        .padding(8) // room for the shadow / hover controls so they aren't clipped
        .fixedSize()
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) { opacity = 1 }
            startLifecycle()
        }
        .onHover { hovering in
            self.hovering = hovering
            if hovering {
                lifecycle?.cancel()
                withAnimation(.easeOut(duration: 0.18)) { opacity = 1 }
            } else {
                startLifecycle()
            }
        }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }

    @ViewBuilder
    private var hoverControls: some View {
        if hovering {
            HStack(spacing: 4) {
                Button(action: onEdit) { Image(systemName: "square.and.pencil") }
                    .help("Edit")
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .help("Dismiss")
            }
            .buttonStyle(IconActionButtonStyle(diameter: 24))
            .padding(6)
            .background(.thinMaterial, in: Capsule())
            .padding(6)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    /// Hold at full opacity, fade out, then ask to be removed. Restarted on
    /// hover-exit; cancelled on hover-enter so the toast stays put while pointed at.
    private func startLifecycle() {
        lifecycle?.cancel()
        lifecycle = Task {
            try? await Task.sleep(for: .seconds(holdSeconds))
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: fadeSeconds)) { opacity = 0 }
            try? await Task.sleep(for: .seconds(fadeSeconds))
            if Task.isCancelled { return }
            onDismiss()
        }
    }
}
