import AppKit
import PhotonzCore
import SwiftUI

/// A list that opens OVER THE PANEL, inside the editor window, rather than in a
/// popover window of its own beside it: the mock's `.propPick`
/// (`video.html`, "anchored to this group so it opens over the pane rather
/// than over the canvas").
///
/// It is also the cheap way to open one. A popover window takes the keyboard
/// from the editor window when it opens and hands it back when it closes, and
/// each hand-over redraws every control in the panel that draws differently
/// in a window without the keyboard: about 50ms of popover machinery and 60ms
/// of panel to open Animate a property, 70ms to close it
/// (`perf/animate-pick-cost-walk.json`, 2026-10-06). Drawn in the window, in a
/// hosting view of its own, the list costs only its own rows.
///
/// A section asks for one with `panelPopover(isPresented:height:content:)` on
/// the view it opens over; the panel draws it with `panelPopoverHost()` on its
/// scroller, so the scroller never cuts it off and it stays over its section
/// as the panel scrolls.
struct PanelPopoverItem {
    let anchor: Anchor<CGRect>
    let height: CGFloat
    let content: AnyView
}

struct PanelPopoverKey: PreferenceKey {
    static var defaultValue: PanelPopoverItem? { nil }
    static func reduce(value: inout PanelPopoverItem?, nextValue: () -> PanelPopoverItem?) {
        value = nextValue() ?? value
    }
}

extension View {
    /// Opens `content` at this view's top edge, the width of this view less
    /// the mock's 8pt either side, on the mock's plate. `height` is the most
    /// it can grow to, which is the room it is kept on screen with. A click
    /// anywhere outside it, or Escape, closes it.
    func panelPopover<Content: View>(isPresented: Binding<Bool>, height: CGFloat,
                                     @ViewBuilder content: () -> Content) -> some View {
        let list = AnyView(
            content()
                .background(VideoKit.Palette.plate, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(VideoKit.Palette.edgeLo))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .background(PanelPopoverWatcher(close: { isPresented.wrappedValue = false }))
                .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
        )
        return anchorPreference(key: PanelPopoverKey.self, value: .bounds) { anchor in
            isPresented.wrappedValue
                ? PanelPopoverItem(anchor: anchor, height: height, content: list) : nil
        }
    }

    /// Draws the list a view inside asked for, over this view.
    func panelPopoverHost() -> some View {
        overlayPreferenceValue(PanelPopoverKey.self, alignment: .topLeading) { item in
            if let item {
                GeometryReader { proxy in
                    let frame = PanelDropdown.frame(over: proxy[item.anchor],
                                                    in: proxy.size, height: item.height)
                    PanelPopoverHosting(content: item.content)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
    }
}

/// The list in a hosting view of its own. Drawn straight into the panel, its
/// forty-odd rows joined the window's own tree of controls, which SwiftUI
/// walks whole for the keyboard and accessibility whenever a control comes or
/// goes: about 45ms more to open (`perf/animate-pick-cost-walk.json`). Apart,
/// they are walked alone, as they were in the popover window.
///
/// Sized by its frame rather than by measuring the list, which would build
/// every row a second time; the list sits at the top and what it does not
/// fill is empty.
private struct PanelPopoverHosting: NSViewRepresentable {
    let content: AnyView
    @Environment(\.self) private var environment

    func makeNSView(context: Context) -> NSHostingView<AnyView> {
        let view = NSHostingView(rootView: root)
        view.sizingOptions = []
        // The plate's shadow falls outside the list.
        view.clipsToBounds = false
        return view
    }

    func updateNSView(_ view: NSHostingView<AnyView>, context: Context) {
        view.rootView = root
    }

    private var root: AnyView {
        let environment = environment
        return AnyView(
            content
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transformEnvironment(\.self) { $0 = environment }
        )
    }
}

/// Closes the list on a click anywhere outside it, the way a popover window
/// closes. Escape is the list's key router's (`PanelPopoverKeys`).
private struct PanelPopoverWatcher: NSViewRepresentable {
    let close: () -> Void

    func makeNSView(context: Context) -> WatcherView {
        let view = WatcherView()
        view.close = close
        return view
    }

    func updateNSView(_ view: WatcherView, context: Context) { view.close = close }

    static func dismantleNSView(_ view: WatcherView, coordinator: ()) { view.stop() }

    final class WatcherView: NSView {
        var close: () -> Void = {}
        private var monitor: Any?
        private weak var host: NSWindow?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { stop(); return }
            guard monitor == nil else { return }
            host = window
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                guard let self, let window = self.host else { return event }
                let inside = event.window === window && self.window != nil
                    && self.bounds.contains(self.convert(event.locationInWindow, from: nil))
                if !inside { self.close() }
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

/// Typing into a list over the panel without taking the window's keyboard
/// from the canvas. Moving it to a real text box costs a walk over every
/// control in the window (about 45ms with accessibility on, which every walk
/// and every screen reader turns on), so the list reads the keys itself while
/// it is open: Escape closes it, a menu shortcut goes on to the menu, and
/// every other key goes to `onKey` and no further, so B, V or J typed into it
/// never reach the timeline or the canvas behind.
struct PanelPopoverKeys: NSViewRepresentable {
    let onKey: (PanelDropdown.Key) -> Void
    let close: () -> Void

    func makeNSView(context: Context) -> KeysView {
        let view = KeysView()
        view.onKey = onKey
        view.close = close
        return view
    }

    func updateNSView(_ view: KeysView, context: Context) {
        view.onKey = onKey
        view.close = close
    }

    static func dismantleNSView(_ view: KeysView, coordinator: ()) { view.stop() }

    final class KeysView: NSView {
        var onKey: (PanelDropdown.Key) -> Void = { _ in }
        var close: () -> Void = {}
        private weak var host: NSWindow?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { stop(); return }
            host = window
            PanelPopoverKeyRouter.open(in: window) { [weak self] event in
                self?.take(event) ?? false
            }
        }

        func stop() {
            if let host { PanelPopoverKeyRouter.close(in: host) }
            host = nil
        }

        private func take(_ event: NSEvent) -> Bool {
            guard event.type == .keyDown else { return false }
            if event.keyCode == 53 {
                close()
                return true
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) {
                guard event.charactersIgnoringModifiers?.lowercased() == "v",
                      let pasted = NSPasteboard.general.string(forType: .string) else { return false }
                onKey(.text(pasted))
                return true
            }
            if let key = PanelDropdown.key(keyCode: event.keyCode, characters: event.characters ?? "") {
                onKey(key)
            }
            return true
        }
    }
}

/// Where a key goes while a list is open over the panel: to the list, before
/// the timeline, the canvas or a menu sees it. A person's key arrives through
/// the monitor here; a walk's press is handed over by `TimelineKeyRouter`,
/// which every walk key is offered to before anything else.
@MainActor enum PanelPopoverKeyRouter {
    private static var lists: [ObjectIdentifier: (NSEvent) -> Bool] = [:]
    private static var monitor: Any?

    static func open(in window: NSWindow, take: @escaping (NSEvent) -> Bool) {
        lists[ObjectIdentifier(window)] = take
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard let window = event.window else { return event }
            return offer(event, in: window) ? nil : event
        }
    }

    static func close(in window: NSWindow) {
        lists[ObjectIdentifier(window)] = nil
    }

    /// True when a list open in `window` took the key.
    static func offer(_ event: NSEvent, in window: NSWindow) -> Bool {
        lists[ObjectIdentifier(window)]?(event) ?? false
    }
}
