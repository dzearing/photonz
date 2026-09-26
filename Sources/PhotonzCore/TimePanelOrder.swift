import Foundation

/// **In a document with time, the panel leads with what the picked layer is
/// for.** A rule, not a list somebody keeps by hand.
///
/// Every one but captions opens on Properties (raw id `keys`): the clip line that
/// names it and says when it runs, then what about it is animating, as
/// `video.html` draws its dock (2026-09-25). After that:
///
/// - A recording is for PLAYING: how fast it plays (Time), how loud (Sound)
///   and how its sound fades (Fades).
/// - A title, or anything else placed on the timeline, is for being ON SCREEN
///   and read: when it is on and how it fades (Time), its words (Text).
/// - A sound is for being HEARD: its level (Sound), its fades, then its time.
/// - Captions are for CAPTIONING: the captions' own options (Captions), then
///   their type (Text), as the captions mock opens its panel.
///
/// Those sections go straight under Layers, in that order. Everything else
/// keeps the order the dock has saved, so a person's own arrangement of the
/// rest is left alone, and a document with no time is not touched at all.
///
/// It exists because the dock's order was a hand-kept list with numbered
/// moves, and every video section was appended to the end of it: the level
/// fader lowest in the dock, the speed under six sections, a title's fade
/// below the fold at 1080 (2026-09-21 audits).
///
/// Sections are named by their raw ids (`InspectorSectionID` in the app), so
/// the rule stays pure.
public enum TimePanelOrder {

    /// What a layer in a document with time is for.
    public enum Role: String, CaseIterable, Sendable {
        /// A recording: pictures that play.
        case playing
        /// A title, a component, a shape: placed on the timeline to be seen.
        case onScreen
        /// A piece of sound.
        case heard
        /// A Captions layer, or one of its cues.
        case captioned

        /// The rule in words, for the design doc and a walk's log.
        public var purpose: String {
            switch self {
            case .playing: "A clip is for playing: what is animating, how fast, how loud."
            case .onScreen: "A title is for being read: what is animating, when it is on, its words."
            case .heard: "A sound is for being heard: what is animating, its level, its fades, then its time."
            case .captioned: "Captions are for reading along: their options, their type, then what is animating."
            }
        }
    }

    /// The section every lead goes under, when the dock has it.
    public static let anchor = "layers"

    /// The sections a role leads with, in order.
    public static func leads(_ role: Role) -> [String] {
        switch role {
        case .playing: ["keys", "speed", "sound", "fades"]
        case .onScreen: ["keys", "speed", "text"]
        case .heard: ["keys", "sound", "fades", "speed"]
        case .captioned: ["captions", "text", "keys"]
        }
    }

    /// What this layer is for, or nil when it has no time and the rule does
    /// not apply.
    public static func role(of layer: Layer) -> Role? {
        if layer.isCaptionsLayer || layer.isCaption { return .captioned }
        guard layer.time != nil else { return nil }
        if layer.movie != nil { return .playing }
        if layer.sound != nil { return .heard }
        if layer.hasMediaBehindIt { return .playing }
        return .onScreen
    }

    /// The saved order with the role's lead moved up under Layers. Only
    /// sections the order already holds are moved; nothing is added or lost.
    public static func arrange(_ order: [String], for role: Role?) -> [String] {
        guard let role else { return order }
        let lead = leads(role).filter(order.contains)
        guard !lead.isEmpty else { return order }
        var rest = order.filter { !lead.contains($0) }
        let at = rest.firstIndex(of: anchor).map { $0 + 1 } ?? 0
        rest.insert(contentsOf: lead, at: at)
        return rest
    }
}
