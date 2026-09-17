/// Which sections the right hand panel puts on screen, and which it leaves out
/// until you ask for them.
///
/// ## The one rule
///
/// **What you PICK never adds or removes an optional section. Only what the
/// document holds, the tool in your hand, and what you asked for may.**
///
/// The panel has always drawn a section only when the selection made it
/// applicable, and that is not what was wrong with it: the complaint was that
/// even the applicable set runs to nine or ten tall sections, some of which a
/// given person never wants at all. So this adds two things and no more.
///
/// 1. A short list of **optional** sections: the ones that answer for a JOB
///    (measuring, animating, laying out, keeping a shelf of things) rather than
///    for every layer. Everything else — the layers list, the section named
///    after the thing you picked, Appearance, Effects — is never optional, so
///    there is no way to end up with an empty panel.
/// 2. An **automatic** answer for each of them, which is a fact about the
///    DOCUMENT or the window and never about the selection. A document that
///    holds no measurement has no Measurements section; make one and it
///    arrives, and it does not then come and go as you click around.
///
/// Anything automatic decides can be overridden one section at a time, and an
/// override is remembered. An override is also exactly the shape a MODE will
/// want later: a mode is a named preset of these choices, not a second
/// mechanism (see the queue task "Modes you can swap, rather than project types
/// you are stuck in").
///
/// Sections are named by their stored string ids, so this stays a pure rule
/// with nothing about SwiftUI in it.
public enum PanelSectionVisibility {

    // MARK: What the rule looks at

    /// The facts the automatic answers are allowed to read. Every one of them
    /// is about the document or the window; there is deliberately nothing here
    /// about what is selected, which is what makes the panel hold still while
    /// you click from one layer to the next.
    public struct Situation: Sendable, Equatable {
        /// The document holds at least one measurement.
        public var documentHasMeasurement: Bool
        /// The document holds a component, original or copy.
        public var documentHasComponent: Bool
        /// The document holds something that puts other things somewhere: a
        /// screen, or a group.
        public var documentHasContainer: Bool
        /// A screen in the document is showing its columns.
        public var documentHasColumns: Bool
        /// View ▸ Show Library has asked for the shelf.
        public var isLibraryAskedFor: Bool

        /// Whether every fact a walk of the document could still discover is
        /// already yes, so the walk can stop. The two window facts are not part
        /// of it: they are known before the walk starts.
        public var isSettled: Bool {
            documentHasMeasurement && documentHasComponent
                && documentHasContainer && documentHasColumns
        }

        public init(documentHasMeasurement: Bool = false,
                    documentHasComponent: Bool = false,
                    documentHasContainer: Bool = false,
                    documentHasColumns: Bool = false,
                    isLibraryAskedFor: Bool = false) {
            self.documentHasMeasurement = documentHasMeasurement
            self.documentHasComponent = documentHasComponent
            self.documentHasContainer = documentHasContainer
            self.documentHasColumns = documentHasColumns
            self.isLibraryAskedFor = isLibraryAskedFor
        }
    }

    // MARK: Which sections may be turned off

    /// The sections you are allowed to say no to, in the order the panel's own
    /// list shows them. Anything absent from here is part of what the panel IS
    /// and can never be hidden.
    public static let optionalSections: [String] = [
        "library", "libraryItem", "measurements", "motion",
        "placement", "columns", "arrange", "component", "shadow",
    ]

    public static func isOptional(_ section: String) -> Bool {
        optionalSections.contains(section)
    }

    // MARK: The automatic answers, in one table

    /// What automatic says about one optional section. **This is the whole of
    /// "relevant to the situation"** — there is no other place a section is
    /// decided, and each answer is one fact about the document or the window.
    ///
    /// A section that is not optional always answers yes: it is not automatic's
    /// business.
    public static func isShownAutomatically(_ section: String, in situation: Situation) -> Bool {
        switch section {
        // The shelf is a thing you go and fetch from, so it waits to be asked
        // for. The user's own words: "the library pane will almost never be
        // used".
        case "library", "libraryItem":
            return situation.isLibraryAskedFor
        // Redlining. A document with no measurement in it has no list to show.
        case "measurements":
            return situation.documentHasMeasurement
        // Laying out. Nothing is placed against anything until the document
        // holds a screen or a group.
        case "placement":
            return situation.documentHasContainer
        case "columns":
            return situation.documentHasColumns
        // Motion, Arrange and Shadow have no job to wait for. Automatic says
        // yes, and the point of listing them is that you can say no.
        //
        // Motion is the one that was nearly written the other way, and the
        // reason it is not is worth keeping. Waiting for the document to
        // already move would be a trap: the plus on the Motion section's own
        // header is how the FIRST motion is made, and the timing strip only
        // exists once something moves, so hiding the section would leave
        // nothing in the window that could start an animation at all. A rule
        // that hides the only door is not an automatic rule, it is a bug. So
        // Motion arrives for every picked layer exactly as it did, and somebody
        // who never animates turns it off once and it stays off.
        case "motion", "arrange", "shadow":
            return true
        // Components. Once the document holds one you are working with them.
        case "component":
            return situation.documentHasComponent
        default:
            return true
        }
    }

    /// Whether the panel draws this section, once the selection has already
    /// said it applies. Your own answer beats automatic's; a section nobody may
    /// hide ignores both.
    public static func isShown(_ section: String, choices: Choices,
                               in situation: Situation) -> Bool {
        // The picked tile's own section belongs to the shelf: it is never on
        // screen without it, so it takes the shelf's answer whole rather than
        // having one of its own. Turning the Library off has to take it with
        // it, or the panel keeps a section headed "Component" for a shelf that
        // is not there.
        if section == "libraryItem" {
            return isShown("library", choices: choices, in: situation)
        }
        guard isOptional(section) else { return true }
        if let chosen = choices.choice(for: section) { return chosen }
        return isShownAutomatically(section, in: situation)
    }

    /// The same question asked of a whole list, keeping its order. What the
    /// panel itself calls.
    public static func shown(_ sections: [String], choices: Choices,
                             in situation: Situation) -> [String] {
        sections.filter { isShown($0, choices: choices, in: situation) }
    }

    // MARK: What the list at the foot of the panel says

    /// Why a section is where it is, so the list can say it in words. Without
    /// this there is no way to tell a section you turned off from one the
    /// document simply has nothing for, and "where did it go" is the whole risk
    /// of hiding anything.
    public enum Reason: Sendable, Equatable {
        /// Automatic put it on screen, because the document earned it.
        case automaticallyIn
        /// Automatic left it out, because nothing in the document needs it yet.
        case automaticallyOut
        /// You turned it on and it stays on.
        case turnedOn
        /// You turned it off and it stays off.
        case turnedOff
    }

    /// One line of the list at the foot of the panel.
    public struct Row: Sendable, Equatable {
        public let section: String
        public let isShown: Bool
        public let reason: Reason

        public init(section: String, isShown: Bool, reason: Reason) {
            self.section = section
            self.isShown = isShown
            self.reason = reason
        }
    }

    public static func rows(for sections: [String], choices: Choices,
                            in situation: Situation) -> [Row] {
        sections.map { section in
            if let chosen = choices.choice(for: section) {
                return Row(section: section, isShown: chosen,
                           reason: chosen ? .turnedOn : .turnedOff)
            }
            let automatic = isShownAutomatically(section, in: situation)
            return Row(section: section, isShown: automatic,
                       reason: automatic ? .automaticallyIn : .automaticallyOut)
        }
    }

    /// What the row at the foot of the panel reads.
    ///
    /// It counts the sections somebody TURNED OFF, and nothing else. The ones
    /// automatic left out are not missing: a document that holds no measurement
    /// has no Measurements list to show, and the section arrives on its own the
    /// moment the first measurement is made. Counting those made a brand new
    /// document open saying "Sections · 5 hidden", which is an alarm about
    /// settings the document never had, and the exact opposite of what the row
    /// is for.
    ///
    /// So it says nothing but "Sections" until a person has actually hidden
    /// something, because a number that is there whatever you do is noise; and
    /// it says how many the moment one is off, because "where did Measurements
    /// go" is the whole risk of hiding anything.
    public static func footerLabel(for rows: [Row]) -> String {
        let hidden = rows.filter { $0.reason == .turnedOff }.count
        return hidden == 0 ? "Sections" : "Sections · \(hidden) hidden"
    }

    // MARK: What you chose, and how it is written down

    /// Your answers, one section at a time. A section this does not mention is
    /// automatic, which is the default state of everything: saying "automatic"
    /// is saying nothing rather than storing a third value.
    public struct Choices: Sendable, Equatable {
        private var overrides: [String: Bool]

        public init() { overrides = [:] }

        /// Read back off disk. Ids this build does not have are dropped, the
        /// way a saved panel ORDER drops sections it no longer knows, so a
        /// stale setting can never keep a section that no longer exists.
        public init(stored: String) {
            var overrides: [String: Bool] = [:]
            for entry in stored.split(separator: ";") {
                let parts = entry.split(separator: "=", maxSplits: 1)
                guard parts.count == 2, PanelSectionVisibility.isOptional(String(parts[0])),
                      let flag = Int(parts[1]), flag == 0 || flag == 1 else { continue }
                overrides[String(parts[0])] = flag == 1
            }
            self.overrides = overrides
        }

        /// The form written to disk: `motion=1;library=0`, sorted so the same
        /// choices always write the same string and a settings file does not
        /// churn.
        public var stored: String {
            overrides.keys.sorted()
                .map { "\($0)=\(overrides[$0] == true ? 1 : 0)" }
                .joined(separator: ";")
        }

        /// Your answer for this section, or nil when it is still automatic.
        public func choice(for section: String) -> Bool? { overrides[section] }

        public func isCustom(_ section: String) -> Bool { overrides[section] != nil }

        public var hasAnyCustom: Bool { !overrides.isEmpty }

        /// Everything you have answered for, in the panel's own order.
        public var customSections: [String] {
            PanelSectionVisibility.optionalSections.filter { overrides[$0] != nil }
        }

        public mutating func set(_ section: String, shown: Bool) {
            guard PanelSectionVisibility.isOptional(section) else { return }
            overrides[section] = shown
        }

        /// Hand one section back to automatic.
        public mutating func useAutomatic(for section: String) {
            overrides[section] = nil
        }

        /// Hand the lot back.
        public mutating func useAutomaticForAll() { overrides = [:] }
    }
}
