import AppKit
import PhotonzCore
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
        /// Non-nil for a progress toast (GIF prep), so it can be updated/dismissed
        /// via its handle instead of the auto-fade lifecycle.
        let progress: ToastProgress?
        init(panel: NSPanel, progress: ToastProgress? = nil) {
            self.panel = panel
            self.progress = progress
        }
    }

    /// Index 0 is the newest (corner-most) toast; later indices stack upward.
    private var items: [Item] = []
    private var screen: NSScreen?

    private let margin: CGFloat = 16
    private let spacing: CGFloat = 10
    /// Keep the stack from marching off the top of the screen on a capture burst.
    private let maxVisible = 5

    /// Show a toast for a freshly captured image or recording. The thumbnail is
    /// read live from the store so a recording's poster frame (generated async)
    /// pops in when it lands; a nil entry shows a generic placeholder. `onEdit`
    /// opens the capture for editing. For recordings, `onCopyVideo`/`onCopyGIF`
    /// add a Copy button whose menu re-copies the clip as an MP4 or animated GIF;
    /// pass nil (the default) for screenshots, which are already on the clipboard.
    func present(entry: CaptureEntry?, store: CaptureStore, message: String, on screen: NSScreen,
                 onEdit: @escaping () -> Void,
                 onCopyVideo: (() -> Void)? = nil,
                 onCopyGIF: (() -> Void)? = nil) {
        self.screen = screen

        // Soft-cap the stack: drop the oldest before adding a new one.
        while items.count >= maxVisible, let oldest = items.last {
            remove(oldest.id, animated: false)
        }

        let panel = makePanel()
        let item = Item(panel: panel)
        let id = item.id

        let view = ToastView(
            entry: entry,
            store: store,
            message: message,
            onEdit: { [weak self] in onEdit(); self?.remove(id, animated: true) },
            onCopyVideo: onCopyVideo.map { copy in { [weak self] in copy(); self?.remove(id, animated: true) } },
            onCopyGIF: onCopyGIF.map { copy in { [weak self] in copy(); self?.remove(id, animated: true) } },
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

    // MARK: - Progress toast (GIF prep)

    /// Show a non-fading progress toast in the same bottom-right stack (e.g. while
    /// "Copy as GIF" re-encodes). Returns the `ToastProgress` to drive from the
    /// export loop; call `dismissProgress(_:)` when the work finishes. Unlike a
    /// capture toast, it has no auto-fade lifecycle — it lives until dismissed.
    @discardableResult
    func presentProgress(title: String, on screen: NSScreen) -> ToastProgress {
        self.screen = screen

        // Soft-cap the stack: drop the oldest before adding a new one.
        while items.count >= maxVisible, let oldest = items.last {
            remove(oldest.id, animated: false)
        }

        let panel = makePanel()
        let progress = ToastProgress(title: title)
        let item = Item(panel: panel, progress: progress)

        let hosting = NSHostingView(rootView: ProgressToastView(progress: progress))
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        panel.setContentSize(size)
        panel.contentView = hosting

        items.insert(item, at: 0)

        let vf = screen.visibleFrame
        panel.setFrame(CGRect(x: vf.maxX - margin - size.width,
                              y: vf.minY + margin,
                              width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        layout(animated: true)
        return progress
    }

    /// Remove a progress toast once its work is done (or failed).
    func dismissProgress(_ progress: ToastProgress) {
        guard let item = items.first(where: { $0.progress === progress }) else { return }
        remove(item.id, animated: true)
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

/// Observable progress for a `ProgressToastView` — the reusable model the GIF
/// export loop drives. `@MainActor` (and thus implicitly `Sendable`) so the
/// off-main exporter can hop back to update it. Fraction is clamped and
/// monotonic so out-of-order frame callbacks never make the bar jump backward.
@MainActor
@Observable
final class ToastProgress {
    /// Caption above the bar (e.g. "Preparing GIF…").
    var title: String
    /// Completion in 0...1.
    private(set) var fraction: Double = 0

    init(title: String) { self.title = title }

    func update(fraction newValue: Double) {
        fraction = min(1, max(fraction, newValue))
    }
}

/// A compact, reusable progress toast for the bottom-right stack: an icon, a
/// caption, and a determinate bar with a percentage. Used for GIF prep, but it
/// takes any `ToastProgress`, so any longer job can surface progress here.
struct ProgressToastView: View {
    var progress: ToastProgress

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(.quaternary)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(progress.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text("\(Int((progress.fraction * 100).rounded()))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            }
        }
        .frame(width: 216)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(8) // room for the shadow so it isn't clipped, matching ToastView
    }
}

/// A toast never takes keyboard focus — it must not pull the key window away
/// from whatever the user is typing in (that caused stray keystrokes + beeps).
/// Mouse events (hover, Edit/Dismiss clicks) still reach it without key status.
private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// An NSMenuItem that runs a Swift closure — lets the toast build its Copy menu
/// without wiring up @objc selector targets.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
    @objc private func fire() { handler() }
}

/// One capture toast: the thumbnail with a "Copied to clipboard" caption,
/// Liquid Glass surface. Self-driving lifecycle (hold → fade → dismiss); hover
/// pins it open at full opacity and reveals Edit / Dismiss.
private struct ToastView: View {
    let entry: CaptureEntry?
    let store: CaptureStore
    let message: String
    var onEdit: () -> Void
    /// Non-nil only for recordings: the Copy button's menu re-copies the clip.
    var onCopyVideo: (() -> Void)?
    var onCopyGIF: (() -> Void)?
    var onDismiss: () -> Void

    /// Anchors the Copy menu so it pops from the (non-key) toast panel correctly.
    private let copyMenuAnchor = MenuAnchor.Handle()

    @State private var hovering = false
    @State private var opacity: Double = 0 // fades in on appear
    @State private var lifecycle: Task<Void, Never>?

    private let holdSeconds: Double = 7
    private let fadeSeconds: Double = 3

    var body: some View {
        VStack(spacing: 8) {
            thumbnail
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
        .contentShape(RoundedRectangle(cornerRadius: 16))
        // Double-click anywhere on the toast = Edit (same as the hover button).
        .onTapGesture(count: 2, perform: onEdit)
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

    /// The capture's thumbnail, read live from the store: screenshots show
    /// immediately; a recording's poster frame pops in when its async generation
    /// lands (a placeholder holds the slot until then). Recordings get the same
    /// play badge + duration pill as their history tiles.
    private var thumbnail: some View {
        Group {
            if let entry, let image = store.image(for: entry) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay {
                        if entry.kind == .video {
                            VideoBadgeOverlay(duration: store.duration(for: entry))
                        }
                    }
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: entry?.kind == .image ? "photo" : "film")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 196, height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.12)))
    }

    @ViewBuilder
    private var hoverControls: some View {
        if hovering {
            HStack(spacing: 4) {
                Button(action: onEdit) { Image(systemName: "square.and.pencil") }
                    .help("Edit")
                if onCopyVideo != nil || onCopyGIF != nil {
                    Button(action: presentCopyMenu) { Image(systemName: "doc.on.doc") }
                        .help("Copy as…")
                        .background(MenuAnchor(handle: copyMenuAnchor))
                }
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

    /// Pop the "Copy Video / Copy GIF" menu below the Copy button. Uses an
    /// NSMenu (not a SwiftUI `Menu`) because the toast panel never becomes key.
    private func presentCopyMenu() {
        guard let anchor = copyMenuAnchor.view else { return }
        let menu = NSMenu()
        if let onCopyVideo {
            menu.addItem(ClosureMenuItem(title: "Copy Video", handler: onCopyVideo))
        }
        if let onCopyGIF {
            menu.addItem(ClosureMenuItem(title: "Copy GIF", handler: onCopyGIF))
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: anchor.bounds.height + 4),
                   in: anchor)
    }

    /// A zero-cost NSView living behind the Copy button, used purely as the
    /// anchor for `NSMenu.popUp(_:at:in:)`. SwiftUI actions have no NSView of
    /// their own, and the toast panel can't become key (so a SwiftUI `Menu`
    /// would misbehave), so we bridge to AppKit for the popup.
    private struct MenuAnchor: NSViewRepresentable {
        @MainActor final class Handle { weak var view: NSView? }
        let handle: Handle
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            handle.view = view
            return view
        }
        func updateNSView(_ nsView: NSView, context: Context) { handle.view = nsView }
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
