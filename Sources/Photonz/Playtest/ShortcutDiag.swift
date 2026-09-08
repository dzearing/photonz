#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore

/// Probe-only answer to one question (`--shortcut-diag`): when a number field
/// in the right hand panel has the keyboard, does a plain letter go into the
/// field, or does it fire the tool shortcut that letter also carries?
///
/// A scripted walk cannot answer it. A walk never makes the app active, and it
/// asks the window `performKeyEquivalent` by hand rather than letting
/// `NSApplication.sendEvent` decide, so anything it sees about shortcuts could
/// be an artefact of both. This runs in a normally launched probe — visible
/// window, app brought to the front — and presses the letter three ways, so the
/// answer says WHICH path fires the shortcut and which lets the field have it:
///
///  * `sendEvent`: the press handed to `NSApplication` exactly as the run loop
///    hands it a real one. This is the app as a person has it.
///  * `postToPid`: the same press pushed through CoreGraphics into our own
///    process, so it arrives from outside like a keyboard's.
///  * `performKeyEquivalent`: what the playtest harness does. Here only to say
///    whether the walk's answer was the app's answer.
///
/// Writes /tmp/photonz-shortcut-diag.txt and quits.
@MainActor
enum ShortcutDiag {
    static let argument = "--shortcut-diag"

    static func runIfRequested() {
        guard AppInfo.flavor == .probe, CommandLine.arguments.contains(argument) else { return }
        Task { await run() }
    }

    private static var out: [String] = []
    private static func say(_ line: String) {
        out.append(line)
        NSLog("[shortcut-diag] \(line)")
    }

    private static func run() async {
        // The app is a menu-bar agent until a window opens, and an accessory
        // cannot come to the front. Whoever opened the file makes it regular;
        // wait for the editor, then ask for the front honestly and REPORT what
        // we got rather than assuming it worked.
        guard let editor = await waitForEditor() else {
            say("no editor window opened; launch the probe with a file")
            return finish()
        }
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .milliseconds(800))
        guard let window = editor.hostWindow else {
            say("the editor lost its window")
            return finish()
        }
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(400))
        say("app active: \(NSApp.isActive); activation policy: \(NSApp.activationPolicy() == .regular ? "regular" : "accessory"); "
            + "editor window is key: \(window.isKeyWindow)")
        if !NSApp.isActive || !window.isKeyWindow {
            say("NOT A REAL-APP READING: the probe never got the front, so what follows says "
                + "nothing about what a person's keyboard would do.")
        }

        // Put the fill pair back on the way out: swapping it is one of the two
        // things this run measures, and the pair is remembered across launches,
        // so a run that walked away from a swap would leave the next one
        // starting from white on black.
        restore = (editor.foregroundFillHex, editor.backgroundFillHex, editor)

        // The canvas itself gives the panel its W and H, which is the field a
        // person types a size into.
        editor.selectCanvas()
        try? await Task.sleep(for: .milliseconds(600))

        // The control first. If a press built and sent this way cannot fire the
        // shortcut even with NOTHING in the panel holding the keyboard, then
        // "no shortcut fired" below would only mean the press never reached the
        // shortcut machinery, and the whole run would prove nothing.
        for letter in Letter.all {
            await probe(letter, path: .sendEvent, focused: false, editor: editor, window: window)
        }
        for letter in Letter.all {
            for path in Path.allCases {
                await probe(letter, path: path, focused: true, editor: editor, window: window)
            }
        }
        finish()
    }

    // MARK: - One press

    private enum Path: String, CaseIterable {
        case sendEvent, postToPid, performKeyEquivalent
    }

    private struct Letter {
        /// What the keyboard would put in a field, and what it would say with
        /// the modifiers taken off — the two are the same for a plain letter
        /// and differ the moment shift is held.
        let character: String
        let unshifted: String
        let keyCode: UInt16
        let flags: NSEvent.ModifierFlags
        /// How the press is written in the log.
        let name: String
        /// What the app would show for it if the shortcut fired.
        let fires: String

        static let t = Letter(character: "t", unshifted: "t", keyCode: 17, flags: [],
                              name: "t", fires: "the Text tool")
        static let x = Letter(character: "x", unshifted: "x", keyCode: 7, flags: [],
                              name: "x", fires: "the fill colours swapped")
        /// Shift is the other half of the question. It is a TYPING modifier —
        /// it is how a capital letter gets into a name field — but it is still
        /// a modifier, and the app hangs a real shortcut on this one, so a
        /// press that carries it has to be measured rather than assumed.
        static let shiftM = Letter(character: "M", unshifted: "m", keyCode: 46, flags: .shift,
                                   name: "⇧M", fires: "the selection tool cycled")

        static let all = [t, x, shiftM]
    }

    private static func probe(_ letter: Letter, path: Path, focused: Bool,
                              editor: EditorState, window: NSWindow) async {
        // Every probe starts from the same place: the select tool, black on
        // white, the canvas picked so the panel is showing W at all. A shortcut
        // that fired in the probe before this one leaves none of that standing.
        editor.setTool(.select)
        editor.foregroundFillHex = "#000000"
        editor.backgroundFillHex = "#FFFFFF"
        editor.selectCanvas()
        try? await Task.sleep(for: .milliseconds(500))
        let where_ = focused ? "with the W field holding the keyboard" : "with nothing in the panel focused"
        var field: NSTextField?
        if focused {
            guard let box = widthField(in: window) else {
                say("\(letter.name) via \(path.rawValue) \(where_): no editable W field on screen, so nothing to type into")
                return
            }
            guard window.makeFirstResponder(box) else {
                say("\(letter.name) via \(path.rawValue) \(where_): the W field would not take the keyboard")
                return
            }
            field = box
        } else {
            _ = window.makeFirstResponder(nil)
        }
        try? await Task.sleep(for: .milliseconds(200))
        let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nobody"
        let editing = window.firstResponder is NSTextView

        switch path {
        case .sendEvent:
            for down in [true, false] {
                if let event = keyEvent(letter, window: window, down: down) { NSApp.sendEvent(event) }
            }
        case .postToPid:
            let source = CGEventSource(stateID: .combinedSessionState)
            for down in [true, false] {
                guard let cg = CGEvent(keyboardEventSource: source, virtualKey: letter.keyCode, keyDown: down)
                else { continue }
                cg.flags = Self.cgFlags(letter.flags)
                cg.postToPid(ProcessInfo.processInfo.processIdentifier)
            }
        case .performKeyEquivalent:
            // Exactly the harness's move: a CoreGraphics-built press offered
            // straight to the window's key equivalents.
            let source = CGEventSource(stateID: .privateState)
            guard let cg = CGEvent(keyboardEventSource: source, virtualKey: letter.keyCode, keyDown: true)
            else {
                say("\(letter.name) via \(path.rawValue): could not build the press")
                return
            }
            cg.flags = Self.cgFlags(letter.flags)
            guard let matcher = NSEvent(cgEvent: cg) else {
                say("\(letter.name) via \(path.rawValue): could not build the press")
                return
            }
            let taken = window.performKeyEquivalent(with: matcher)
            if !taken, let event = keyEvent(letter, window: window, down: true) { window.sendEvent(event) }
            if let event = keyEvent(letter, window: window, down: false) { window.sendEvent(event) }
        }
        // A press pushed in from outside has to be picked up by the run loop
        // like any other, so give it more than one turn before calling it lost.
        for _ in 0..<12 { try? await Task.sleep(for: .milliseconds(100)) }

        // Read the field from the editor that is open on it, not from the
        // control: while a field is being typed into, the words live in the
        // window's field editor and the control still holds its old value.
        let typed = field.flatMap { box in
            (window.fieldEditor(false, for: box) as? NSTextView)?.string ?? box.stringValue
        }
        let tool = editor.activeTool.rawValue
        let fills = "\(editor.foregroundFillHex)/\(editor.backgroundFillHex)"
        let fired = letter.unshifted == "x" ? fills != "#000000/#FFFFFF" : tool != "select"
        let landed = typed?.lowercased().contains(letter.unshifted) ?? false
        let box = typed.map { "field holds \"\($0)\" (\(landed ? "the letter LANDED" : "nothing typed"))" }
            ?? "no field to type into"
        say("\(letter.name) via \(path.rawValue) \(where_): \(box), "
            + "tool \(tool), fills \(fills) -> \(fired ? "SHORTCUT FIRED (\(letter.fires))" : "no shortcut"). "
            + "keyboard was with \(responder)\(editing ? " (a field editor)" : "")")
    }

    private static func keyEvent(_ letter: Letter, window: NSWindow, down: Bool) -> NSEvent? {
        NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: letter.flags,
                         timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: window.windowNumber, context: nil,
                         characters: letter.character, charactersIgnoringModifiers: letter.unshifted,
                         isARepeat: false, keyCode: letter.keyCode)
    }

    private static func cgFlags(_ flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var out: CGEventFlags = []
        if flags.contains(.shift) { out.insert(.maskShift) }
        if flags.contains(.command) { out.insert(.maskCommand) }
        if flags.contains(.option) { out.insert(.maskAlternate) }
        if flags.contains(.control) { out.insert(.maskControl) }
        return out
    }

    // MARK: - Finding things

    private static func waitForEditor() async -> EditorState? {
        for _ in 0..<60 {
            if let ready = PlaytestHarness.readyEditors.first { return ready }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    /// The panel's W box, by the label it shows, the same way a walk's `focus`
    /// step finds it.
    private static func widthField(in window: NSWindow) -> NSTextField? {
        guard let content = window.contentView else { return nil }
        var found: [NSTextField] = []
        func walk(_ view: NSView) {
            if let field = view as? NSTextField, field.isEditable, !field.isHiddenOrHasHiddenAncestor {
                found.append(field)
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(content)
        return found.first { field in
            [field.placeholderString, field.accessibilityLabel()]
                .compactMap { $0 }
                .contains { $0.caseInsensitiveCompare("W") == .orderedSame }
        }
    }

    /// What the fill pair was before this run touched it, and who to give it
    /// back to.
    private static var restore: (foreground: String, background: String, editor: EditorState)?

    private static func finish() {
        if let restore {
            restore.editor.foregroundFillHex = restore.foreground
            restore.editor.backgroundFillHex = restore.background
        }
        let text = out.joined(separator: "\n") + "\n"
        try? text.write(toFile: "/tmp/photonz-shortcut-diag.txt", atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
#endif
