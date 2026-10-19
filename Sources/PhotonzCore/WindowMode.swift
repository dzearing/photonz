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
/// app saves and reads back, and optionally the tools it puts in front of the
/// tool bar (`toolStrip`), the rest folding under More. Writing modes down as
/// data so a new one needs no Swift is a later slice, filed separately.
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

    /// The tools this mode puts in front of the tool bar, in families, or nil
    /// for a mode that leaves the window's own bar as it is.
    ///
    /// **Folds only, never removes.** Every tool the bar holds that is not in
    /// the strip goes under More and keeps its key and its row there
    /// (`ToolBarFold.init(_:strip:room:metrics:keeping:)`), so a mode changes
    /// what is in front and never what you can reach. A strip tool the release
    /// has not switched on is simply not drawn.
    public let toolStrip: [[ToolBarLayout.Entry]]?

    /// The order the strip's slots stay in front when the window is too narrow
    /// for all of them, first kept first, or nil to fold from the strip's far
    /// end. It only decides WHICH slots fold; the strip still draws in its own
    /// order (`ToolBarFold.init(_:strip:priority:room:metrics:keeping:)`).
    public let toolStripPriority: [ToolBarLayout.Entry]?

    /// The member a family's slot wears in this mode until a person picks
    /// another one, for a family whose own first member is the wrong face for
    /// the job: the shapes family starts on the Line, and a person building a
    /// screen reaches for a Rectangle (`ui-entry-wt.html` draws the slot as a
    /// square, "Shape (R)"). A family named here keeps its own memory in this
    /// mode, so the window's bar outside it keeps its own default and its own
    /// last pick. Read through `startingMember(of:)`.
    public let toolStripMembers: [ToolGroup: Tool]

    /// The Library stays out of this mode's panel until the person turns it
    /// on here (the Sections list or View ▸ Library), whatever the app-wide
    /// Library switch says. True for the picture modes: the shelf is mostly
    /// for video and design, and design work turning the switch on used to
    /// leave it open in every picture after (the user, 2026-10-18: "library
    /// was expanded by default. I think for image editing it should be
    /// hidden"). Design and the video setup keep their own default.
    public let libraryWaitsToBeTurnedOn: Bool

    /// What the automatic rule may take as "the Library was asked for" in
    /// this mode, given the app-wide switch.
    public func libraryAsked(_ switchIsOn: Bool) -> Bool {
        switchIsOn && !libraryWaitsToBeTurnedOn
    }

    public init(id: String, title: String, summary: String, symbol: String,
                preset: PanelSectionVisibility.Choices,
                toolStrip: [[ToolBarLayout.Entry]]? = nil,
                toolStripPriority: [ToolBarLayout.Entry]? = nil,
                toolStripMembers: [ToolGroup: Tool] = [:],
                libraryWaitsToBeTurnedOn: Bool = false) {
        self.id = id
        self.title = title
        self.summary = summary
        self.symbol = symbol
        self.preset = preset
        self.toolStrip = toolStrip
        self.toolStripPriority = toolStripPriority
        self.toolStripMembers = toolStripMembers
        self.libraryWaitsToBeTurnedOn = libraryWaitsToBeTurnedOn
    }

    /// The member `group`'s slot starts on in this mode, or nil when the mode
    /// leaves the family as it is. Only a mode with a strip of its own can
    /// name one, and only a tool of that family counts.
    public func startingMember(of group: ToolGroup) -> Tool? {
        guard toolStrip != nil, let tool = toolStripMembers[group],
              group.tools.contains(tool) else { return nil }
        return tool
    }
}

/// The modes the app ships with, in the order the list shows them.
///
/// They are written as data rather than as code branches on purpose: the second
/// slice moves this list into a file somebody can edit, and nothing else has to
/// change when it does, because nowhere in the app is there a switch over a
/// mode's id.
///
/// **Modes are for pictures.** A picture is offered Image, Icon and Design and
/// starts in Image. A document with time has one sensible setup, the video one,
/// so it is offered no list at all and its window draws no chip (the user,
/// 2026-10-17: "when you open a video, you shouldn't see the dropdown. it makes
/// no sense if only one mode is relevant").
public enum WindowModes {

    /// The mode every picture starts in, and the one **Show Everything** goes
    /// back to: it folds nothing, so the panel follows the automatic rule
    /// exactly as it does for somebody who never finds modes. It was called
    /// Redline until 2026-10-17, and folded the building sections then.
    public static let imageID = "image"

    /// The one setup a document with time has. Never in a list.
    public static let videoID = "video"

    public static let all: [WindowMode] = [
        WindowMode(
            id: imageID,
            title: "Image",
            summary: "Editing a picture or a screenshot.",
            symbol: "photo",
            preset: choices([:]),
            libraryWaitsToBeTurnedOn: true),
        WindowMode(
            id: "icon",
            title: "Icon",
            summary: "Drawing a glyph on a small frame.",
            symbol: "app.dashed",
            // Motion stays: an icon that moves is the point of the icon work.
            // Component stays: an icon becomes a component, which is the chain
            // this whole direction rests on.
            preset: choices(["measurements": false, "library": false, "columns": false]),
            libraryWaitsToBeTurnedOn: true),
        WindowMode(
            id: "design",
            title: "Design",
            summary: "Building screens out of components.",
            symbol: "square.on.square",
            preset: choices(["measurements": false, "motion": false]),
            toolStrip: designStrip,
            toolStripPriority: designStripPriority,
            toolStripMembers: [.shapes: .rectangle]),
        WindowMode(
            id: videoID,
            title: "Video",
            summary: "Cutting and arranging a recording.",
            symbol: "film",
            preset: choices(["measurements": false, "columns": false,
                             "placement": false])),
    ]

    /// The tools for building screens, as the UI entry mock draws them
    /// (`ui-entry-wt.html` step 4, UX-PATTERNS D4 "UI design"):
    /// Select | Frame, Component insert, Shape, Pen, Text | Measure | Hand.
    /// The mock's Zoom is not a tool at all (the user, 2026-09-29), so it is
    /// not here.
    public static let designStrip: [[ToolBarLayout.Entry]] = [
        [.tool(.select)],
        [.tool(.frame), .tool(.component), .group(.shapes), .tool(.pen), .tool(.text)],
        [.tool(.measure)],
        [.tool(.hand)],
    ]

    /// How the Design bar folds in a narrow window, as the mock folds it: its
    /// `ovf` slots (Shape, Pen, Text and Measure) go under More first, from the
    /// far end, and Select, Frame, Component insert and the Hand stay.
    public static let designStripPriority: [ToolBarLayout.Entry] = [
        .tool(.select), .tool(.frame), .tool(.component), .tool(.hand),
        .group(.shapes), .tool(.pen), .tool(.text), .tool(.measure),
    ]

    /// The mode every picture starts in.
    public static let image: WindowMode = mode(imageID) ?? all[0]

    public static func mode(_ id: String) -> WindowMode? {
        all.first { $0.id == id }
    }

    /// The modes a window offers for what it holds, in list order: Image, Icon
    /// and Design for a picture, nothing for a document with time.
    public static func offered(hasTime: Bool) -> [WindowMode] {
        hasTime ? [] : all.filter { $0.id != videoID }
    }

    /// The number this mode answers to on the keyboard, or nil for one with no
    /// key. `⌃1 … ⌃3`, in a picture's list order, so the key and the list never
    /// disagree. The video setup has none: it is never picked.
    public static func shortcutNumber(for id: String) -> Int? {
        guard let index = offered(hasTime: false).firstIndex(where: { $0.id == id }),
              index < 9 else { return nil }
        return index + 1
    }

    /// What an id an older build wrote down means now, or nil for one that no
    /// longer ships. Everything was the mode that folded nothing, which is
    /// Image now.
    static func currentID(for stored: String) -> String? {
        if stored == "everything" { return imageID }
        return mode(stored)?.id
    }

    private static func choices(_ entries: [String: Bool]) -> PanelSectionVisibility.Choices {
        var choices = PanelSectionVisibility.Choices()
        for key in entries.keys.sorted() { choices.set(key, shown: entries[key] == true) }
        return choices
    }
}

/// How each mode is arranged, kept once for the whole app.
///
/// It holds no live panel of its own: a window's panel IS the arrangement of
/// the mode that window is in, read from here, and a switch ticked in the
/// Sections list is written straight back here for that mode. So swapping a
/// window's mode hands nothing over, and "swapping back restores exactly the
/// arrangement you left" is true rather than a promise. Two windows in the same
/// mode share how you like it, the way the panel choices always were shared;
/// two windows in different modes never touch each other.
public struct WindowModeArrangements: Sendable, Equatable, Codable {

    /// The arrangement each bent mode is holding, as the same string the
    /// settings file stores. A mode absent from here is sitting on its preset,
    /// so a mode never bent stays the mode as shipped even if its preset is
    /// later reworded.
    private var bends: [String: String]

    public init(bends: [String: String] = [:]) {
        var kept: [String: String] = [:]
        for (id, stored) in bends {
            guard let mode = WindowModes.mode(id),
                  PanelSectionVisibility.Choices(stored: stored) != mode.preset else { continue }
            kept[id] = stored
        }
        self.bends = kept
    }

    /// The arrangement this mode is holding: what it was bent to, or its own
    /// preset.
    public func arrangement(of id: String) -> PanelSectionVisibility.Choices {
        if let bent = bends[id] { return PanelSectionVisibility.Choices(stored: bent) }
        return WindowModes.mode(id)?.preset ?? PanelSectionVisibility.Choices()
    }

    /// Whether this mode is no longer what it shipped as. The chip says so,
    /// because a mode that has quietly stopped being itself is a mode you
    /// cannot trust the name of.
    public func isBent(_ id: String) -> Bool { bends[id] != nil }

    /// Keep what is on screen as this mode's arrangement. Bending it back to
    /// its own preset by hand is not a bend.
    public mutating func keep(_ choices: PanelSectionVisibility.Choices, for id: String) {
        guard let mode = WindowModes.mode(id) else { return }
        bends[id] = choices == mode.preset ? nil : choices.stored
    }

    /// Put this mode back the way it shipped.
    public mutating func reset(_ id: String) { bends[id] = nil }

    /// What an older build wrote down, read into arrangements.
    ///
    /// Until 2026-10-17 the app held ONE mode for every window
    /// (`{"modeID":"video","bends":{…}}`) and one live panel string that was
    /// that mode's arrangement. The mode itself is not carried over: it was the
    /// bug, a recording's Video reaching every picture. What is carried is how
    /// each mode was arranged: its bends, and the live panel for the mode it
    /// belonged to when that differs from the mode's preset. Everything is
    /// Image's now. Redline's arrangement folded the building sections for a
    /// narrower job than Image's, so it is left behind rather than folding
    /// them on every picture.
    public static func migrating(legacySession: String?, livePanel: String?) -> WindowModeArrangements {
        struct Legacy: Decodable {
            var modeID: String?
            var bends: [String: String]?
        }
        let legacy = legacySession?.data(using: .utf8)
            .flatMap { try? JSONDecoder().decode(Legacy.self, from: $0) }
        var bends: [String: String] = [:]
        for (id, stored) in legacy?.bends ?? [:] {
            guard let current = WindowModes.currentID(for: id) else { continue }
            bends[current] = stored
        }
        let liveModeID = legacy?.modeID ?? "everything"
        if let live = livePanel, !live.isEmpty,
           let current = WindowModes.currentID(for: liveModeID) {
            bends[current] = live
        }
        return WindowModeArrangements(bends: bends)
    }
}

/// Which mode one window is in.
///
/// Per WINDOW, never shared: a recording's window in its video setup and a
/// picture's window in Design are two sessions that never meet, and a new
/// window starts a picture in Image whatever any other window picked. It holds
/// no arrangement, only the name of the mode; what that mode looks like is the
/// app's (`WindowModeArrangements`).
///
/// The document decides the rest. A document with time is in the video setup
/// whatever was picked, and gets its picked mode back if it ever stops having
/// time, because the pick is remembered rather than overwritten.
public struct WindowModeSession: Sendable, Equatable {

    /// The picture mode this window is in.
    public private(set) var pickedID: String

    public init(pickedID: String = WindowModes.imageID) {
        self.pickedID = WindowModes.offered(hasTime: false).contains { $0.id == pickedID }
            ? pickedID : WindowModes.imageID
    }

    /// The mode the window is in for what it holds.
    public func modeID(hasTime: Bool) -> String {
        hasTime ? WindowModes.videoID : pickedID
    }

    public func mode(hasTime: Bool) -> WindowMode {
        WindowModes.mode(modeID(hasTime: hasTime)) ?? WindowModes.image
    }

    /// Whether the window draws the chip: only when there is more than one
    /// mode to be in. A list of one is not a choice.
    public static func showsChip(hasTime: Bool) -> Bool {
        WindowModes.offered(hasTime: hasTime).count > 1
    }

    /// Move to another mode. Refuses, and changes nothing, for a mode this
    /// document is not offered: Video on a picture, anything on a recording.
    @discardableResult
    public mutating func swap(to id: String, hasTime: Bool) -> Bool {
        guard WindowModes.offered(hasTime: hasTime).contains(where: { $0.id == id }) else {
            return false
        }
        pickedID = id
        return true
    }

    /// What the chip reads: the mode's name, and whether you have bent it.
    public func chipLabel(hasTime: Bool, arrangements: WindowModeArrangements) -> String {
        let id = modeID(hasTime: hasTime)
        let title = mode(hasTime: hasTime).title
        return arrangements.isBent(id) ? "\(title), edited" : title
    }

    /// Hand the lot back: every section follows the document again, which is
    /// the window of somebody who never touched a mode. A picture lands in
    /// Image, put back as it shipped; the mode being left keeps what you did to
    /// it, so this is a way out and never a way to lose an arrangement. A
    /// recording has nowhere else to go, so its own setup is unfolded instead.
    public mutating func showEverything(hasTime: Bool, arrangements: inout WindowModeArrangements) {
        if hasTime {
            arrangements.keep(PanelSectionVisibility.Choices(), for: WindowModes.videoID)
        } else {
            pickedID = WindowModes.imageID
            arrangements.reset(WindowModes.imageID)
        }
    }
}
