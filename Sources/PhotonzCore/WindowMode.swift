import Foundation

/// A MODE is what the WINDOW is set up for, never what the document IS.
///
/// The difference is the whole design (`docs/design/modes.md`). A *type* is
/// something a file is and cannot easily stop being; a *mode* is a named preset
/// of choices the app already stores, and swapping costs nothing because there
/// is nothing to convert. Nothing here reaches the document, nothing here is
/// written into a file, and an old document opens with no question asked
/// because there is no value in it to guess at.
///
/// What a mode is made of is deliberately small: a bundle of
/// `PanelSectionVisibility.Choices`, which is already a per-section yes/no the
/// app saves and reads back. That is the first slice. Folding tool groups into
/// the overflow, and writing modes down as data so a new one needs no Swift,
/// are later slices and are filed separately.
public struct WindowMode: Sendable, Equatable, Codable, Identifiable {
    /// The id written to settings. Stable; the title may be reworded.
    public let id: String
    /// What the chip reads and what the list calls it.
    public let title: String
    /// What this mode is for, in ONE LINE. Not a paragraph: the list is read at
    /// a glance while you are already doing something else, and three modes
    /// each wrapping onto three lines turned a quiet popup into a settings
    /// dialog (seen in `window-modes-2-mode-list-sc.png`, 2026-09-22). What
    /// each mode folds is not said here either, because the Sections row at the
    /// foot of the panel says it, live, for the mode you are actually in.
    public let summary: String
    /// The glyph the chip and the list draw. A plain name, so this file stays
    /// pure: nothing here imports a UI framework to hold a string.
    public let symbol: String
    /// The panel this mode asks for. Only `optionalSections` can appear here,
    /// because `Choices` refuses anything else, which is what stops any mode
    /// from hiding the parts that make every mode the same app.
    ///
    /// **Folds only, never unfolds.** A `Choices` entry can say yes as well as
    /// no, and a mode deliberately never says yes, because the panel would not
    /// listen: a section reaches this rule only once the SELECTION has already
    /// said it applies, and for every optional section the thing that makes it
    /// available and the thing automatic waits for are the same fact. The
    /// Measurements list is offered only once the document holds a measurement,
    /// so Redline pinning it on produced exactly nothing (watched on 2026-09-22
    /// in `window-modes-walk`, which went looking for a section a mode had
    /// asked for and found the panel unchanged). A mode folds what a job does
    /// not need; conjuring a surface the document has nothing to put in is a
    /// different feature and not this one.
    public let preset: PanelSectionVisibility.Choices

    public init(id: String, title: String, summary: String, symbol: String,
                preset: PanelSectionVisibility.Choices) {
        self.id = id
        self.title = title
        self.summary = summary
        self.symbol = symbol
        self.preset = preset
    }
}

/// The modes the app ships with, in the order the list shows them.
///
/// They are written as data rather than as code branches on purpose: the second
/// slice moves this list into a file somebody can edit, and nothing else has to
/// change when it does, because nowhere in the app is there a switch over a
/// mode's id.
public enum WindowModes {

    /// The mode a window is in until somebody picks another, and the one **Show
    /// everything** goes back to: it folds nothing, so the panel follows the
    /// automatic rule exactly as it does for somebody who never finds modes.
    public static let everythingID = "everything"

    public static let all: [WindowMode] = [
        WindowMode(
            id: everythingID,
            title: "Everything",
            summary: "The whole app, every section following the document.",
            symbol: "square.grid.2x2",
            preset: choices([:])),
        WindowMode(
            id: "icon",
            title: "Icon",
            summary: "Drawing a glyph on a small frame.",
            symbol: "app.dashed",
            // Motion stays: an icon that moves is the point of the icon work.
            // Component stays: an icon becomes a component, which is the chain
            // this whole direction rests on.
            preset: choices(["measurements": false, "library": false, "columns": false])),
        WindowMode(
            id: "redline",
            title: "Redline",
            summary: "Measuring a capture, handing over a spec.",
            symbol: "ruler",
            preset: choices(["motion": false, "component": false,
                             "placement": false, "columns": false])),
        WindowMode(
            id: "video",
            title: "Video",
            summary: "Cutting and arranging a recording.",
            symbol: "film",
            preset: choices(["measurements": false, "columns": false,
                             "placement": false])),
        WindowMode(
            id: "design",
            title: "Design",
            summary: "Building screens out of components.",
            symbol: "square.on.square",
            preset: choices(["measurements": false, "motion": false])),
    ]

    /// The one mode that folds nothing.
    public static let everything: WindowMode = mode(everythingID) ?? all[0]

    public static func mode(_ id: String) -> WindowMode? {
        all.first { $0.id == id }
    }

    /// The modes the list offers as a swap, which is everything but the one
    /// that means "no mode". **Show everything** is a separate row under the
    /// line rather than a fifth peer: it is the panic button, and it reads as
    /// leaving a mode rather than as entering one.
    public static var swappable: [WindowMode] {
        all.filter { $0.id != everythingID }
    }

    /// The number this mode answers to on the keyboard, or nil for one with no
    /// key. `⌃1 … ⌃5`, in list order, so the key and the list never disagree.
    public static func shortcutNumber(for id: String) -> Int? {
        guard let index = swappable.firstIndex(where: { $0.id == id }),
              index < 9 else { return nil }
        return index + 1
    }

    private static func choices(_ entries: [String: Bool]) -> PanelSectionVisibility.Choices {
        var choices = PanelSectionVisibility.Choices()
        for key in entries.keys.sorted() { choices.set(key, shown: entries[key] == true) }
        return choices
    }
}

/// Which mode a window is in, and the arrangement it is holding for each mode
/// it has been bent away from.
///
/// It holds no choices of its own: the panel's own store is still the one place
/// the live arrangement lives, and this hands it a new one on a swap and takes
/// the old one back. That is what keeps a mode from being a second mechanism,
/// and it is why turning a section off by hand while in a mode is not a
/// conflict but simply the mode, bent.
public struct WindowModeSession: Sendable, Equatable, Codable {

    /// The mode the window is in.
    public private(set) var modeID: String

    /// The arrangement each bent mode is holding, as the same string the
    /// settings file stores. A mode absent from here is sitting on its preset.
    /// This is what makes "swapping back restores exactly the arrangement you
    /// left" true rather than a promise.
    private var bends: [String: String]

    public init(modeID: String = WindowModes.everythingID, bends: [String: String] = [:]) {
        self.modeID = WindowModes.mode(modeID) == nil ? WindowModes.everythingID : modeID
        self.bends = bends.filter { WindowModes.mode($0.key) != nil }
    }

    public var mode: WindowMode {
        WindowModes.mode(modeID) ?? WindowModes.everything
    }

    /// The arrangement this mode is currently holding: what it was bent to, or
    /// its own preset.
    public func arrangement(of id: String) -> PanelSectionVisibility.Choices {
        if let bent = bends[id] { return PanelSectionVisibility.Choices(stored: bent) }
        return WindowModes.mode(id)?.preset ?? PanelSectionVisibility.Choices()
    }

    /// Whether what is on screen is no longer what this mode asks for. The chip
    /// says so, because a mode that has quietly stopped being itself is a mode
    /// you cannot trust the name of.
    public func isBent(with choices: PanelSectionVisibility.Choices) -> Bool {
        choices != mode.preset
    }

    /// What the chip reads: the mode's name, and whether you have bent it.
    public func chipLabel(with choices: PanelSectionVisibility.Choices) -> String {
        isBent(with: choices) ? "\(mode.title), edited" : mode.title
    }

    /// Move to another mode, handing over what is on screen right now.
    /// Returns the arrangement the panel should take.
    ///
    /// The outgoing mode keeps what you did to it, so coming back lands on the
    /// window you left; a mode you never bent stores nothing, so it stays the
    /// mode as shipped even if its preset is later reworded.
    public mutating func swap(to id: String,
                              leaving choices: PanelSectionVisibility.Choices)
    -> PanelSectionVisibility.Choices {
        guard WindowModes.mode(id) != nil else { return choices }
        if choices == mode.preset {
            bends[modeID] = nil
        } else {
            bends[modeID] = choices.stored
        }
        modeID = id
        return arrangement(of: id)
    }

    /// Put this mode back the way it shipped, without leaving it.
    public mutating func resetCurrent() -> PanelSectionVisibility.Choices {
        bends[modeID] = nil
        return mode.preset
    }

    /// Leave modes altogether: the panel every section of which follows the
    /// document again, which is the window of somebody who never touched a
    /// mode. The one move that can never leave you short of anything.
    public mutating func showEverything(leaving choices: PanelSectionVisibility.Choices)
    -> PanelSectionVisibility.Choices {
        // The mode you are leaving keeps what you did to it, exactly as an
        // ordinary swap does, so this is a way OUT and never a way to lose an
        // arrangement. What it does not keep is a bend on Everything itself:
        // the whole meaning of the button is "give me the lot back", so it
        // lands on the clean one however bent it was last time.
        _ = swap(to: WindowModes.everythingID, leaving: choices)
        bends[WindowModes.everythingID] = nil
        return WindowModes.everything.preset
    }
}
