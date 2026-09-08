import Foundation

/// One question the app is allowed to stop and ask, and to be told to stop
/// asking.
///
/// A command that stops and asks is a tax on every use of that command forever,
/// so the bar to ask is high: only when what the command takes away is
/// invisible the instant after (UX-PATTERNS §3, "The question you can
/// silence"). This type is the roll call of the ones that cleared that bar, so
/// there is somewhere to read them back from.
///
/// The words are for a person: `command` is what the menu row says, minus its
/// ellipsis, and `warns` is one sentence of what the question is protecting.
/// Nothing here is an internal name.
public struct SilenceableQuestion: Hashable, Sendable, Identifiable {
    /// Stable across releases; it identifies the question, not its wording.
    public let id: String
    /// The command that raises it, in the words on its menu row.
    public let command: String
    /// What the question warns about, in one sentence.
    public let warns: String
    /// Where the answer is remembered: the app's own settings, per app bundle,
    /// under a key named for the command. NEVER in the document — a file you
    /// send someone must not carry your answer.
    public let storageKey: String

    public init(id: String, command: String, warns: String, storageKey: String) {
        self.id = id
        self.command = command
        self.warns = warns
        self.storageKey = storageKey
    }

    /// The first, and so far only, silenceable question the app ships.
    public static let turnIntoPicture = SilenceableQuestion(
        id: "turnIntoPicture",
        command: "Turn Into Picture",
        warns: "Warns you that a shape or a piece of text is about to stop being editable.",
        storageKey: "photonz.turnIntoPicture.dontAsk")

    /// Every question the app can ask, in the order a list should show them.
    /// Grow this one at a time, each with its reason written down.
    public static let all: [SilenceableQuestion] = [.turnIntoPicture]
}

/// The tiny slice of key-value storage the silence store needs. Injecting it
/// keeps the store testable without touching the real defaults database.
public protocol SilenceDefaults: AnyObject {
    func isSilenced(forKey key: String) -> Bool
    func setSilenced(_ silenced: Bool, forKey key: String)
}

/// The real backing store: `UserDefaults`, so each app bundle keeps its own
/// answers and the dev build cannot silence a question for the shipping one.
public final class UserDefaultsSilenceDefaults: SilenceDefaults {
    private let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isSilenced(forKey key: String) -> Bool { defaults.bool(forKey: key) }

    public func setSilenced(_ silenced: Bool, forKey key: String) {
        defaults.set(silenced, forKey: key)
    }
}

/// In-memory storage for tests and previews.
public final class InMemorySilenceDefaults: SilenceDefaults {
    private var values: [String: Bool] = [:]

    public init() {}

    public func isSilenced(forKey key: String) -> Bool { values[key] ?? false }

    public func setSilenced(_ silenced: Bool, forKey key: String) { values[key] = silenced }
}

/// Which questions the person has told the app to stop asking, and the way
/// back.
///
/// "Don't ask again" must never be a door that locks behind you: whatever
/// surface shows this, `silenced` is the list it draws and `askAgain` is the
/// button on every row. `silenced` holds ONLY what was actually turned off, so
/// the list can never read as a set of switches inviting you to go and silence
/// things.
public final class SilencedQuestions {
    private let defaults: any SilenceDefaults

    public init(defaults: any SilenceDefaults) {
        self.defaults = defaults
    }

    public func isSilenced(_ question: SilenceableQuestion) -> Bool {
        defaults.isSilenced(forKey: question.storageKey)
    }

    public func silence(_ question: SilenceableQuestion) {
        defaults.setSilenced(true, forKey: question.storageKey)
    }

    /// Puts the question back. The command asks again the very next time it
    /// runs, because the command reads this answer each time rather than
    /// caching it.
    public func askAgain(_ question: SilenceableQuestion) {
        defaults.setSilenced(false, forKey: question.storageKey)
    }

    /// The questions that are off right now, in catalog order. Empty is the
    /// normal state and is worth saying out loud (`emptyMessage`).
    public var silenced: [SilenceableQuestion] {
        SilenceableQuestion.all.filter(isSilenced)
    }

    /// The words the surface uses, so every home for this list says the same
    /// thing.
    public static let listTitle = "Questions you have silenced"
    public static let emptyMessage = "Photonz is asking you every question it knows how to ask."
    public static let askAgainButton = "Ask Me Again"
}
