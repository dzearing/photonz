// Reading one of the app's plain SwiftUI windows the way a screen reader does,
// and pressing its buttons the way a keyboard does.
//
// The Tutorials window and the setup window are ordinary SwiftUI surfaces in a
// hosting view, so there are no `PanelTargetView` markers in them to press and
// their controls are not `NSButton`s to find. What IS there is the
// accessibility tree, which is the same tree VoiceOver reads, and asking our
// OWN process for it needs no grant from anybody. So one probe answers two
// questions at once: whether everything on show carries words a person
// listening would understand, and whether pressing a button really does the
// thing.
#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore

/// The generic half: any window, read and pressed.
@MainActor
enum WindowReadProbe {

    /// One element as the tree reads it.
    struct Element {
        let role: String
        /// What a screen reader would say for it: its label, its title, or the
        /// words it is showing, whichever it answers with.
        let label: String
        let depth: Int
        let element: Any
    }

    /// Everything under the window's CONTENT, depth kept sane: a hosting view
    /// nests deep and nothing useful lives past here.
    ///
    /// The title bar is left out on purpose. Its close, minimise and zoom
    /// buttons are the system's and carry no label of their own, so counting
    /// them would make every window in every app fail a check about whether OUR
    /// controls say anything.
    static func elements(in window: NSWindow) -> [Element] {
        guard let content = window.contentView else { return [] }
        var found: [Element] = []
        walk(content, depth: 0, into: &found)
        return found
    }

    private static func walk(_ node: Any, depth: Int, into found: inout [Element]) {
        guard depth < 24 else { return }
        let object = node as AnyObject
        let role = (object.accessibilityRole?()?.rawValue) ?? ""
        // A SwiftUI control answers with a label; an AppKit one with a title.
        // Either counts as saying something.
        let label: String = {
            if let spoken = object.accessibilityLabel?(), !spoken.isEmpty { return spoken }
            if let titled = object.accessibilityTitle?(), !titled.isEmpty { return titled }
            return ""
        }()
        // A plain piece of text answers with a VALUE rather than a label, and
        // the Swift overloads of `accessibilityValue()` are ambiguous, so it is
        // asked for the way Objective C would ask.
        let spokenValue: String = {
            guard label.isEmpty, let objc = node as? NSObject,
                  objc.responds(to: Selector(("accessibilityValue"))),
                  let value = objc.value(forKey: "accessibilityValue") as? String
            else { return label }
            return value
        }()
        if !role.isEmpty {
            found.append(Element(role: role, label: spokenValue, depth: depth, element: node))
        }
        for child in object.accessibilityChildren?() ?? [] {
            walk(child, depth: depth + 1, into: &found)
        }
    }

    /// Every button in the window, with the words it says. This is the proof
    /// that the list is reachable without a mouse: a control with no role and
    /// no label is one VoiceOver cannot announce and the keyboard cannot land
    /// on.
    static func buttons(in window: NSWindow) -> [Element] {
        elements(in: window).filter { $0.role == NSAccessibility.Role.button.rawValue }
    }

    /// Everything the window says from top to bottom, gathered by scrolling
    /// through it a screenful at a time and reading at each stop.
    ///
    /// One reading of a scrolling list is NOT the whole list. A row that has
    /// scrolled away is still in the tree, but SwiftUI has not worked out its
    /// words yet, so it comes back silent. Measured on 2026-09-13, when the
    /// Tutorials window grew from five guides to ten and four perfectly good
    /// Start buttons read as saying nothing. A person listening scrolls as
    /// they go, so this does too, and puts the list back where it found it.
    static func fullReading(in window: NSWindow) -> [Element] {
        guard let scroller = firstScrollView(in: window.contentView) else {
            return elements(in: window)
        }
        let clip = scroller.contentView
        let was = clip.bounds.origin
        let height = clip.bounds.height
        let total = scroller.documentView?.frame.height ?? height
        var found = elements(in: window)
        var y: CGFloat = 0
        // A screenful at a time with a little overlap, so nothing falls between
        // two stops.
        while y + height < total + height {
            scroller.contentView.scroll(to: CGPoint(x: was.x, y: y))
            scroller.reflectScrolledClipView(clip)
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            found += elements(in: window)
            y += height * 0.8
            if y >= total { break }
        }
        scroller.contentView.scroll(to: was)
        scroller.reflectScrolledClipView(clip)
        return found
    }

    private static func firstScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroller = view as? NSScrollView { return scroller }
        for child in view.subviews {
            if let found = firstScrollView(in: child) { return found }
        }
        return nil
    }

    /// What the window says, in one line per thing said, for the walk's log.
    static func reading(in window: NSWindow) -> String {
        let said = elements(in: window)
            .filter { !$0.label.isEmpty }
            .map { "\($0.role.replacingOccurrences(of: "AX", with: "")): \($0.label)" }
        return said.isEmpty ? "the window says nothing a screen reader could read"
            : said.joined(separator: "\n  ")
    }

    /// Presses the first button whose words start with any of `titles`.
    /// Returns what it said, so a walk's log records which one was pressed.
    static func press(startingWith titles: [String], in window: NSWindow) -> String? {
        guard let button = buttons(in: window).first(where: { element in
            titles.contains { element.label == $0 || element.label.hasPrefix($0 + " ") }
        }) else { return nil }
        let object = button.element as AnyObject
        _ = object.accessibilityPerformPress?()
        return button.label
    }
}

/// The Tutorials window.
@MainActor
enum TutorialHubProbe {
    static func window() -> NSWindow? {
        NSApp.windows.first { $0.title == TutorialHubModel.windowTitle && $0.isVisible }
    }

    /// Presses the first guide row's own button, whatever it currently says.
    static func pressFirstGuideButton() -> String? {
        guard let window = window() else { return nil }
        return WindowReadProbe.press(startingWith: ["Start", "Continue", "Again"], in: window)
    }
}

/// The setup window, which also carries the one first run tour offer.
@MainActor
enum WelcomeProbe {
    static func window() -> NSWindow? {
        NSApp.windows.first { $0.title == FirstRunOffer.windowTitle && $0.isVisible }
    }

    /// Presses one of the two ways on. Returns what the button said.
    static func press(_ title: String) -> String? {
        guard let window = window() else { return nil }
        return WindowReadProbe.press(startingWith: [title], in: window)
    }
}
#endif
