import Foundation

/// **Every command the app runs, by a name an agent can say.**
///
/// The menu bar, the timeline's right-click rows and the layer's right-click
/// rows are three ways a person reaches a command; an agent reaches the same
/// command by its name here (`docs/design/agent-mcp.md`, slice 2). The app
/// carries each one out through the same function its menu row calls, so a
/// command an agent runs is the command a click runs, and it lands as one undo
/// step.
///
/// A name is stable: it is what an agent's script says, so a row may change
/// its words without its command changing its name.
public enum AppCommandID: String, CaseIterable, Hashable, Sendable {
    // Sequence: playing
    case playPause = "play_pause"
    case playInToOut = "play_in_to_out"
    case playBackward = "play_backward"
    case stop = "stop"
    case playForward = "play_forward"
    case goToPreviousEdit = "go_to_previous_edit"
    case goToNextEdit = "go_to_next_edit"
    // Sequence: marks and markers
    case addMarker = "add_marker"
    case setIn = "set_in"
    case setOut = "set_out"
    case markClip = "mark_clip"
    case goToIn = "go_to_in"
    case goToOut = "go_to_out"
    case clearIn = "clear_in"
    case clearOut = "clear_out"
    case clearInAndOut = "clear_in_and_out"
    case goToNextMarker = "go_to_next_marker"
    case goToPreviousMarker = "go_to_previous_marker"
    case removeMarker = "remove_marker"
    case clearAllMarkers = "clear_all_markers"
    // Sequence: what a range does
    case extract = "extract"
    case lift = "lift"
    case splitAtRangeEdges = "split_at_range_edges"
    case mergeIntoOneClip = "merge_into_one_clip"
    case addCaptionsForRange = "add_captions_for_range"
    case splitEverythingAtPlayhead = "split_everything_at_playhead"
    case snapInTimeline = "snap_in_timeline"
    // Sequence > Track
    case addVideoTrack = "add_video_track"
    case addAudioTrack = "add_audio_track"
    case addCaptionsTrack = "add_captions_track"
    case addTrackAbove = "add_track_above"
    case addTrackBelow = "add_track_below"
    case muteTrack = "mute_track"
    case hideTrack = "hide_track"
    case soloTrack = "solo_track"
    case lockTrack = "lock_track"
    case groupTrack = "group_track"
    case ungroupTracks = "ungroup_tracks"
    case deleteTrack = "delete_track"
    case deleteEmptyTracks = "delete_empty_tracks"
    // Sequence: captions, and the recording itself
    case addCaptions = "add_captions"
    case cancelCaptions = "cancel_captions"
    case captionsLater = "captions_later"
    case captionsEarlier = "captions_earlier"
    case clearCaptions = "clear_captions"
    case resetCaptions = "reset_captions"
    case revertToOriginal = "revert_to_original"
    // Clip: cutting
    case splitAtPlayhead = "split_at_playhead"
    case delete = "delete"
    case rippleDelete = "ripple_delete"
    case rippleTrimStart = "ripple_trim_start"
    case rippleTrimEnd = "ripple_trim_end"
    case nudgeEarlier = "nudge_earlier"
    case nudgeLater = "nudge_later"
    case breakApart = "break_apart"
    // Clip: the clip itself
    case selectForward = "select_forward"
    case hideClickAtPlayhead = "hide_click_at_playhead"
    case nextClick = "next_click"
    case showClickEffects = "show_click_effects"
    case addZoom = "add_zoom"
    case suggestZooms = "suggest_zooms"
    // Clip: time
    case showPicture = "show_picture"
    case setSpeed = "set_speed"
    case addSpeedStop = "add_speed_stop"
    case deleteSpeedStop = "delete_speed_stop"
    case resetRamp = "reset_ramp"
    case punchIn = "punch_in"
    case pullBackOut = "pull_back_out"
    case resetReframe = "reset_reframe"
    case setFade = "set_fade"
    // Clip > Transition at Cut
    case setTransition = "set_transition"
    case hardCut = "hard_cut"
    case resetTransitionLength = "reset_transition_length"
    case setTransitionLength = "set_transition_length"
    case setTransitionCurve = "set_transition_curve"
    case applyTransitionToEveryCut = "apply_transition_to_every_cut"
    case setDefaultTransition = "set_default_transition"
    case applyDefaultTransition = "apply_default_transition"
    case expandCut = "expand_cut"
    case rollEditToPlayhead = "roll_edit_to_playhead"
    case joinThroughEdit = "join_through_edit"
    // Clip: sound
    case detachAudio = "detach_audio"
    case reattachAudio = "reattach_audio"
    case flattenLevel = "flatten_level"
    case normalizePeaks = "normalize_peaks"
    case normalizeLoudness = "normalize_loudness"
    case normalizeCleansNoise = "normalize_cleans_noise"
    case cleanNoise = "clean_noise"
    case resetGain = "reset_gain"
    case replayTitle = "replay_title"
    // Clip > Animate
    case startAtPlayhead = "start_at_playhead"
    case endAtPlayhead = "end_at_playhead"
    case animateIn = "animate_in"
    case animateOut = "animate_out"
    case goToNextKey = "go_to_next_key"
    case goToPreviousKey = "go_to_previous_key"
    case keyAtPlayhead = "key_at_playhead"
    case curveThePath = "curve_the_path"
    case removeKeyAtPlayhead = "remove_key_at_playhead"
    case selectAllKeys = "select_all_keys"
    // Edit
    case selectAll = "select_all"
    case deselect = "deselect"
    case invertSelection = "invert_selection"
    case fillWithForeground = "fill_with_foreground"
    case fillWithBackground = "fill_with_background"
    case swapFillColors = "swap_fill_colors"
    // Layer
    case newLayer = "new_layer"
    case newLayerViaCopy = "new_layer_via_copy"
    case newLayerViaCut = "new_layer_via_cut"
    case blurBehindSelection = "blur_behind_selection"
    case duplicateLayer = "duplicate_layer"
    case mirrorAcrossCenter = "mirror_across_center"
    case centerOnArtboard = "center_on_artboard"
    case selectPixels = "select_pixels"
    case putOnTimeline = "put_on_timeline"
    case copyLook = "copy_look"
    case pasteLook = "paste_look"
    case mergeDown = "merge_down"
    case combineShapes = "combine_shapes"
    case union = "union"
    case outlineStroke = "outline_stroke"
    case separateIntoLayers = "separate_into_layers"
    case turnIntoText = "turn_into_text"
    case arrangeInCollage = "arrange_in_collage"
    case newCollageLayer = "new_collage_layer"
    case group = "group"
    case ungroup = "ungroup"
    case stackSelection = "stack_selection"
    case gridSelection = "grid_selection"
    case frameSelection = "frame_selection"
    case makeComponent = "make_component"
    case makeUnique = "make_unique"
    case align = "align"
    case spaceEvenly = "space_evenly"
    case bringToFront = "bring_to_front"
    case bringForward = "bring_forward"
    case sendBackward = "send_backward"
    case sendToBack = "send_to_back"
    case deleteLayer = "delete_layer"
    // Measure
    case showAllMeasurements = "show_all_measurements"
    case hideAllMeasurements = "hide_all_measurements"
    case clearMeasurements = "clear_measurements"
    // View
    case zoomIn = "zoom_in"
    case zoomOut = "zoom_out"
    case zoomToFit = "zoom_to_fit"
    case actualSize = "actual_size"
    case zoomTimelineToFit = "zoom_timeline_to_fit"
    case compactTracks = "compact_tracks"
    case captionSafeAreas = "caption_safe_areas"
}

/// One thing a command can be told besides its name.
public struct AppCommandArgument: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A moment, in seconds from the start.
        case seconds
        case integer(minimum: Int, maximum: Int)
        /// One of a fixed list of words.
        case choice([String])
        /// One of a fixed list of whole numbers.
        case number([Int])
        case flag
        /// A layer or clip id from read_document.
        case layerIDs
        /// A track id from read_document.
        case trackID
    }

    public let name: String
    public let kind: Kind
    public let summary: String
    public let required: Bool

    public init(_ name: String, _ kind: Kind, _ summary: String, required: Bool = false) {
        self.name = name
        self.kind = kind
        self.summary = summary
        self.required = required
    }

    /// The JSON schema `run_command` checks this argument against.
    public var schema: AgentJSON {
        var schema: [String: AgentJSON] = ["description": .string(summary)]
        switch kind {
        case .seconds:
            schema["type"] = "number"
            schema["minimum"] = 0
        case let .integer(minimum, maximum):
            schema["type"] = "integer"
            schema["minimum"] = .number(Double(minimum))
            schema["maximum"] = .number(Double(maximum))
        case .choice(let words):
            schema["type"] = "string"
            schema["enum"] = .array(words.map(AgentJSON.string))
        case .number(let numbers):
            schema["type"] = "integer"
            schema["enum"] = .array(numbers.map { .number(Double($0)) })
        case .flag:
            schema["type"] = "boolean"
        case .layerIDs:
            schema["type"] = "array"
            schema["items"] = ["type": "string"]
        case .trackID:
            schema["type"] = "string"
        }
        return .object(schema)
    }
}

/// One command: its name, the words its row wears, where a person finds it,
/// when it can run, and what it can be told.
public struct AppCommand: Hashable, Sendable {

    /// What part of a document a command works on, for `list_commands` to
    /// filter by.
    public enum Area: String, CaseIterable, Hashable, Sendable {
        /// Time: clips, cuts, tracks, the playhead, marks, captions.
        case timeline
        /// Layers: making, arranging, grouping, combining.
        case layers
        /// The selection and the fill colours.
        case edit
        /// Measurements.
        case measure
        /// How the window shows the document. Changes no pixels and no undo.
        case view
    }

    /// What a command can be told to pick before it runs, the way a person
    /// clicks a thing before choosing a menu row: the playhead, layers or
    /// clips, one piece of a cut clip, a track.
    public struct Picks: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let playhead = Picks(rawValue: 1 << 0)
        public static let layers = Picks(rawValue: 1 << 1)
        public static let piece = Picks(rawValue: 1 << 2)
        public static let track = Picks(rawValue: 1 << 3)
        /// What a command on a clip at a moment takes.
        public static let clipAtPlayhead: Picks = [.playhead, .layers, .piece]
    }

    public let id: AppCommandID
    /// The words of its menu row.
    public let title: String
    /// Other words the same row wears in some states ("Pause" for "Play").
    public let otherTitles: [String]
    /// Where a person finds it in the menu bar, as "Clip > Speed".
    public let menu: String
    public let area: Area
    /// When it can run, in a few plain words.
    public let needs: String
    public let picks: Picks
    /// Its own arguments, besides what it picks.
    public let options: [AppCommandArgument]
    /// A switch with a tick: told `on` it sets it, told nothing it flips.
    public let isToggle: Bool

    public var name: String { id.rawValue }
    public var titles: [String] { [title] + otherTitles }

    /// Everything it can be told: what it picks first, then its own.
    public var arguments: [AppCommandArgument] {
        var all: [AppCommandArgument] = []
        if picks.contains(.playhead) {
            all.append(.init("seconds", .seconds, "Move the playhead here first, as a click on the ruler does."))
        }
        if picks.contains(.layers) {
            all.append(.init("layers", .layerIDs, "Pick these layers or clips first, by their ids from read_document."))
        }
        if picks.contains(.piece) {
            all.append(.init("piece", .integer(minimum: 0, maximum: 9_999),
                             "Pick this piece of a clip that has been cut, 0 first. Needs exactly one id in layers."))
        }
        if picks.contains(.track) {
            all.append(.init("track", .trackID, "Pick this track first, by its id from read_document."))
        }
        if isToggle {
            all.append(.init("on", .flag, "true turns it on, false turns it off. Left out, it flips."))
        }
        return all + options
    }

    /// The schema `run_command` checks a call's `arguments` against.
    public var inputSchema: AgentJSON {
        var properties: [String: AgentJSON] = [:]
        for argument in arguments { properties[argument.name] = argument.schema }
        return ["type": "object", "properties": .object(properties),
                "required": .array(arguments.filter(\.required).map { .string($0.name) }),
                "additionalProperties": false]
    }
}

/// A command checked and ready to run: what to pick first, then its own
/// arguments.
public struct AppCommandCall: Hashable, Sendable {
    public let id: AppCommandID
    /// Where to put the playhead first.
    public var atMS: Int?
    /// Which layers or clips to pick first, as the ids read_document gave.
    public var layers: [String]
    public var piece: Int?
    public var track: String?
    /// For a toggle: the state asked for, or nil to flip it.
    public var on: Bool?
    public var options: [String: AgentJSON]

    public init(_ id: AppCommandID, atMS: Int? = nil, layers: [String] = [], piece: Int? = nil,
                track: String? = nil, on: Bool? = nil, options: [String: AgentJSON] = [:]) {
        self.id = id
        self.atMS = atMS
        self.layers = layers
        self.piece = piece
        self.track = track
        self.on = on
        self.options = options
    }

    /// The call a menu row makes: nothing to pick, it acts on what is in hand.
    public static func menu(_ id: AppCommandID) -> AppCommandCall { AppCommandCall(id) }

    public var picksAnything: Bool { atMS != nil || !layers.isEmpty || piece != nil || track != nil }

    public func word(_ name: String) -> String? { options[name]?.stringValue }
    public func integer(_ name: String) -> Int? { options[name]?.intValue }
}

/// The table of every command, and the checking of a call against it.
public enum AppCommandTable {

    public static let all: [AppCommand] = timeline + clip + layers + edit + measure + view

    private static let byID: [AppCommandID: AppCommand] = Dictionary(all.map { ($0.id, $0) },
                                                                     uniquingKeysWith: { first, _ in first })

    public static func command(_ id: AppCommandID) -> AppCommand? { byID[id] }

    public static func command(named name: String) -> AppCommand? {
        AppCommandID(rawValue: name).flatMap { byID[$0] }
    }

    // MARK: Building rows

    private static func make(_ id: AppCommandID, _ title: String, _ menu: String, _ area: AppCommand.Area,
                             needs: String, picks: AppCommand.Picks = [], options: [AppCommandArgument] = [],
                             also: [String] = [], toggle: Bool = false) -> AppCommand {
        AppCommand(id: id, title: title, otherTitles: also, menu: menu, area: area, needs: needs,
                   picks: picks, options: options, isToggle: toggle)
    }

    private static let aVideo = "a video"
    private static let clipInHand = "a clip picked, or under the playhead"
    private static let layersPicked = "one or more layers picked"
    private static let cutInHand = "a cut picked, or the cut at the playhead on the clip in hand"
    private static let marked = "an in and an out set"
    private static let trackInHand = "a track picked, or the track of the clip in hand"

    /// The speeds Clip > Speed offers, in percent.
    public static let speeds = ClipSpeed.stops

    // MARK: The table

    static let timeline: [AppCommand] = {
        let seq = "Sequence", track = "Sequence > Track"
        return [
            make(.playPause, "Play", seq, .timeline, needs: aVideo, also: ["Pause"]),
            make(.playInToOut, "Play In to Out", seq, .timeline, needs: marked),
            make(.playBackward, "Play Backward", seq, .timeline, needs: aVideo),
            make(.stop, "Stop", seq, .timeline, needs: "the video playing"),
            make(.playForward, "Play Forward", seq, .timeline, needs: aVideo),
            make(.goToPreviousEdit, "Go to Previous Edit", seq, .timeline, needs: "an edit before the playhead"),
            make(.goToNextEdit, "Go to Next Edit", seq, .timeline, needs: "an edit after the playhead"),
            make(.addMarker, "Add Marker", seq, .timeline, needs: aVideo, picks: .playhead),
            make(.setIn, "Set In", seq, .timeline, needs: aVideo, picks: .playhead),
            make(.setOut, "Set Out", seq, .timeline, needs: aVideo, picks: .playhead),
            make(.markClip, "Mark Clip", seq, .timeline, needs: clipInHand, picks: [.playhead, .layers]),
            make(.goToIn, "Go to In", seq, .timeline, needs: "an in set"),
            make(.goToOut, "Go to Out", seq, .timeline, needs: "an out set"),
            make(.clearIn, "Clear In", seq, .timeline, needs: "an in set"),
            make(.clearOut, "Clear Out", seq, .timeline, needs: "an out set"),
            make(.clearInAndOut, "Clear In and Out", seq, .timeline, needs: "an in or an out set"),
            make(.goToNextMarker, "Go to Next Marker", seq, .timeline, needs: "a marker after the playhead"),
            make(.goToPreviousMarker, "Go to Previous Marker", seq, .timeline,
                 needs: "a marker before the playhead"),
            make(.removeMarker, "Remove Marker", seq, .timeline, needs: "a marker at the playhead",
                 picks: .playhead),
            make(.clearAllMarkers, "Clear All Markers", seq, .timeline, needs: "a marker"),
            make(.extract, "Extract", seq, .timeline, needs: marked),
            make(.lift, "Lift", seq, .timeline, needs: marked),
            make(.splitAtRangeEdges, "Split at Range Edges", seq, .timeline, needs: "a range with a clip across an edge"),
            make(.mergeIntoOneClip, "Merge into One Clip", seq, .timeline, needs: "a range over two or more pieces"),
            make(.addCaptionsForRange, "Add Captions for Range", seq, .timeline, needs: "a range over speech"),
            make(.splitEverythingAtPlayhead, "Split Everything at Playhead", seq, .timeline,
                 needs: "clips under the playhead", picks: .playhead),
            make(.snapInTimeline, "Snap in Timeline", seq, .timeline, needs: aVideo, toggle: true),
            make(.addVideoTrack, "Add Video Track", track, .timeline, needs: aVideo),
            make(.addAudioTrack, "Add Audio Track", track, .timeline, needs: aVideo),
            make(.addCaptionsTrack, "Add Captions Track", track, .timeline, needs: aVideo),
            make(.addTrackAbove, "Add Track Above", track, .timeline, needs: trackInHand, picks: .track),
            make(.addTrackBelow, "Add Track Below", track, .timeline, needs: trackInHand, picks: .track),
            make(.muteTrack, "Mute Track", track, .timeline, needs: "an audio track in hand", picks: .track,
                 toggle: true),
            make(.hideTrack, "Hide Track", track, .timeline, needs: "a video or captions track in hand",
                 picks: .track, toggle: true),
            make(.soloTrack, "Solo Track", track, .timeline, needs: trackInHand, picks: .track, toggle: true),
            make(.lockTrack, "Lock Track", track, .timeline, needs: trackInHand, picks: .track, toggle: true),
            make(.groupTrack, "Group Track", track, .timeline, needs: "a track in hand that is in no group",
                 picks: .track),
            make(.ungroupTracks, "Ungroup Tracks", track, .timeline, needs: "a track in hand that is in a group",
                 picks: .track),
            make(.deleteTrack, "Delete Track", track, .timeline, needs: trackInHand, picks: .track,
                 also: ["Delete Tracks"]),
            make(.deleteEmptyTracks, "Delete Empty Tracks", track, .timeline, needs: "an empty track"),
            make(.addCaptions, "Add Captions", seq, .timeline, needs: "a video with speech in its sound",
                 also: ["Rewrite Captions"]),
            make(.cancelCaptions, "Cancel Captions", seq, .timeline, needs: "captions being written"),
            make(.captionsLater, "Captions Later", seq, .timeline, needs: "captions"),
            make(.captionsEarlier, "Captions Earlier", seq, .timeline, needs: "captions"),
            make(.clearCaptions, "Clear Captions", seq, .timeline, needs: "captions"),
            make(.resetCaptions, "Reset Captions", seq, .timeline, needs: "captions that were edited"),
            make(.revertToOriginal, "Revert to Original", seq, .timeline, needs: "a recording that was edited"),
        ]
    }()

    static let clip: [AppCommand] = {
        let clip = "Clip", animate = "Clip > Animate", cut = "Clip > Transition at Cut"
        let normalize = "Clip > Normalize"
        let soundPicked = "a sound picked, or a clip with sound under the playhead"
        return [
            make(.splitAtPlayhead, "Split at Playhead", clip, .timeline, needs: "a clip under the playhead",
                 picks: .clipAtPlayhead),
            make(.delete, "Delete This Piece", clip, .timeline,
                 needs: "a piece, range, gap, transition or keys in hand", picks: .clipAtPlayhead,
                 also: ["Delete Points", "Delete Keys", "Delete Transition", "Delete Section", "Delete Range",
                        "Delete Pieces", "Delete Gap"]),
            make(.rippleDelete, "Ripple Delete", clip, .timeline, needs: "a piece in hand",
                 picks: .clipAtPlayhead, also: ["Ripple Delete Section"]),
            make(.rippleTrimStart, "Ripple Trim Start to Playhead", clip, .timeline,
                 needs: "a clip under the playhead", picks: .clipAtPlayhead),
            make(.rippleTrimEnd, "Ripple Trim End to Playhead", clip, .timeline,
                 needs: "a clip under the playhead", picks: .clipAtPlayhead),
            make(.nudgeEarlier, "Nudge Earlier", clip, .timeline, needs: "clips picked", picks: .layers),
            make(.nudgeLater, "Nudge Later", clip, .timeline, needs: "clips picked", picks: .layers),
            make(.breakApart, "Break Apart", clip, .timeline, needs: "a merged clip in hand", picks: .layers),
            make(.selectForward, "Select Forward", clip, .timeline, needs: clipInHand, picks: [.playhead, .layers]),
            make(.hideClickAtPlayhead, "Hide Click at Playhead", clip, .timeline,
                 needs: "a recorded click at the playhead", picks: .playhead, also: ["Show Click at Playhead"]),
            make(.nextClick, "Next Click", clip, .timeline, needs: "a recorded click after the playhead"),
            make(.showClickEffects, "Show Click Effects", clip, .timeline, needs: "a recording with clicks",
                 picks: [.playhead, .layers], toggle: true),
            make(.addZoom, "Add Zoom", clip, .timeline, needs: "a recording under the playhead", picks: .playhead),
            make(.suggestZooms, "Suggest Zooms", clip, .timeline, needs: "a recording in hand",
                 picks: [.playhead, .layers]),
            make(.showPicture, "Show Picture", clip, .timeline, needs: "a stretch whose picture was hidden",
                 picks: .clipAtPlayhead),
            make(.setSpeed, "Speed", "Clip > Speed", .timeline, needs: clipInHand, picks: .clipAtPlayhead,
                 options: [.init("percent", .number(speeds), "The speed, in percent of normal.", required: true)]),
            make(.addSpeedStop, "Add Speed Stop", "Clip > Speed", .timeline, needs: "a picture clip in hand",
                 picks: .clipAtPlayhead),
            make(.deleteSpeedStop, "Delete Speed Stop", "Clip > Speed", .timeline, needs: "a speed stop in hand",
                 picks: .clipAtPlayhead),
            make(.resetRamp, "Reset Ramp", "Clip > Speed", .timeline, needs: "a ramped piece in hand",
                 picks: .clipAtPlayhead),
            make(.punchIn, "Punch In", clip, .timeline, needs: "a picture under the playhead",
                 picks: [.playhead, .layers]),
            make(.pullBackOut, "Pull Back Out", clip, .timeline, needs: "a punch in at the playhead",
                 picks: [.playhead, .layers]),
            make(.resetReframe, "Reset Reframe", clip, .timeline, needs: "a reframed clip in hand",
                 picks: [.playhead, .layers]),
            make(.setFade, "Fade In", clip, .timeline, needs: "a picture or title in hand",
                 picks: [.playhead, .layers],
                 options: [.init("end", .choice(FadeEnd.allCases.map(\.rawValue)), "Which end fades.", required: true),
                           .init("milliseconds", .integer(minimum: 0, maximum: 10_000),
                                 "How long the fade lasts; 0 takes it off.", required: true)],
                 also: ["Fade Out"]),
            make(.setTransition, "Transition at Cut", cut, .timeline, needs: cutInHand, picks: .clipAtPlayhead,
                 options: [.init("kind", .choice(ClipTransitionKind.allCases.map(\.rawValue)),
                                 "The transition to put on the cut.", required: true)]),
            make(.hardCut, "Hard Cut", cut, .timeline, needs: "a transition on the cut in hand",
                 picks: .clipAtPlayhead),
            make(.resetTransitionLength, "Reset to Default Length", cut, .timeline,
                 needs: "a transition with a length of its own", picks: .clipAtPlayhead),
            make(.setTransitionLength, "Length", "Clip > Transition at Cut > Length", .timeline,
                 needs: "a transition on the cut in hand", picks: .clipAtPlayhead,
                 options: [.init("milliseconds", .integer(minimum: 1, maximum: 10_000),
                                 "One of the lengths the Length menu offers for this cut.", required: true)]),
            make(.setTransitionCurve, "Curve", "Clip > Transition at Cut > Curve", .timeline,
                 needs: "a transition on the cut in hand", picks: .clipAtPlayhead,
                 options: [.init("curve", .choice(EasingCurve.named.prefix(EasingCurve.standardCount).map(\.title)),
                                 "How the transition speeds up and slows down.", required: true)]),
            make(.applyTransitionToEveryCut, "Apply to Every Cut", cut, .timeline,
                 needs: "a transition on the cut in hand", picks: .clipAtPlayhead),
            make(.setDefaultTransition, "Set as Default Transition", cut, .timeline,
                 needs: "a transition on the cut in hand", picks: .clipAtPlayhead),
            make(.applyDefaultTransition, "Apply Default Transition", clip, .timeline, needs: cutInHand,
                 picks: .clipAtPlayhead),
            make(.expandCut, "Expand the Cut", clip, .view, needs: cutInHand, picks: .clipAtPlayhead, toggle: true),
            make(.rollEditToPlayhead, "Roll Edit to Playhead", clip, .timeline, needs: "a cut picked",
                 picks: .clipAtPlayhead),
            make(.joinThroughEdit, "Join Through Edit", clip, .timeline, needs: "a cut that joins one clip",
                 picks: .clipAtPlayhead),
            make(.detachAudio, "Detach Audio", clip, .timeline, needs: "a video clip with sound in hand",
                 picks: [.playhead, .layers]),
            make(.reattachAudio, "Re-attach Audio", clip, .timeline, needs: "a detached sound in hand",
                 picks: [.playhead, .layers]),
            make(.flattenLevel, "Flatten Level", clip, .timeline, needs: "a sound with level points in hand",
                 picks: [.playhead, .layers]),
            make(.normalizePeaks, "Peaks to -1 dB", normalize, .timeline, needs: soundPicked,
                 picks: [.playhead, .layers]),
            make(.normalizeLoudness, "Normalize", normalize, .timeline, needs: soundPicked,
                 picks: [.playhead, .layers],
                 options: [.init("target", .choice(AudioNormalize.Target.allCases.map(\.rawValue)),
                                 "The loudness to bring it to.", required: true)]),
            make(.normalizeCleansNoise, "Clean Noise", normalize, .timeline, needs: soundPicked, toggle: true),
            make(.cleanNoise, "Clean Noise", clip, .timeline, needs: soundPicked, picks: [.playhead, .layers],
                 also: ["Remove Noise Cleaning"], toggle: true),
            make(.resetGain, "Reset Gain", clip, .timeline, needs: "a sound with its gain changed",
                 picks: [.playhead, .layers]),
            make(.replayTitle, "Replay Title", clip, .timeline, needs: "a title in hand", picks: [.playhead, .layers]),
            make(.startAtPlayhead, "Start at Playhead", animate, .timeline, needs: "a placed layer in hand",
                 picks: [.playhead, .layers]),
            make(.endAtPlayhead, "End at Playhead", animate, .timeline, needs: "a placed layer in hand",
                 picks: [.playhead, .layers]),
            make(.animateIn, "Animate In", animate, .timeline, needs: "a placed layer in hand",
                 picks: [.playhead, .layers],
                 options: [.init("kind", .choice(TitleAnimation.allCases.map(\.rawValue)), "How it comes in.",
                                 required: true)]),
            make(.animateOut, "Animate Out", animate, .timeline, needs: "a placed layer in hand",
                 picks: [.playhead, .layers],
                 options: [.init("kind", .choice(TitleAnimation.allCases.map(\.rawValue)), "How it goes out.",
                                 required: true)]),
            make(.goToNextKey, "Go to Next Key", animate, .timeline, needs: "a key after the playhead"),
            make(.goToPreviousKey, "Go to Previous Key", animate, .timeline, needs: "a key before the playhead"),
            make(.keyAtPlayhead, "Key at Playhead", animate, .timeline, needs: "a layer in hand",
                 picks: [.playhead, .layers]),
            make(.curveThePath, "Curve the Path", animate, .timeline, needs: "a layer that moves along a path",
                 picks: .layers, toggle: true),
            make(.removeKeyAtPlayhead, "Remove Key at Playhead", animate, .timeline, needs: "a key at the playhead",
                 picks: [.playhead, .layers]),
            make(.selectAllKeys, "Select All Keys", animate, .timeline, needs: "a layer with keys in hand",
                 picks: .layers),
        ]
    }()

    static let layers: [AppCommand] = {
        let layer = "Layer"
        return [
            make(.newLayer, "New Layer", layer, .layers, needs: "a document"),
            make(.newLayerViaCopy, "New Layer via Copy", layer, .layers, needs: "a selection or layers picked",
                 picks: .layers),
            make(.newLayerViaCut, "New Layer via Cut", layer, .layers, needs: "a selection on a picture"),
            make(.blurBehindSelection, "Blur Behind Selection", layer, .layers, needs: "a selection"),
            make(.duplicateLayer, "Duplicate Layer", layer, .layers, needs: layersPicked, picks: .layers),
            make(.mirrorAcrossCenter, MirrorAcrossCenter.title, layer, .layers, needs: "a shape picked on a picture",
                 picks: .layers),
            make(.centerOnArtboard, CenterOnArtboard.title, layer, .layers, needs: "a shape picked on a picture",
                 picks: .layers),
            make(.selectPixels, "Select Pixels", layer, .layers, needs: "a layer picked", picks: .layers),
            make(.putOnTimeline, "Put on Timeline", layer, .layers, needs: "a layer on no track, in a video",
                 picks: [.playhead, .layers]),
            make(.copyLook, "Copy Look", layer, .layers, needs: "a layer picked", picks: .layers),
            make(.pasteLook, "Paste Look", layer, .layers, needs: "a look copied, and layers picked",
                 picks: .layers),
            make(.mergeDown, "Merge Down", layer, .layers, needs: "a layer with one under it", picks: .layers),
            make(.combineShapes, PathCombine.menuItem, "Layer > Combine Shapes", .layers,
                 needs: "two or more shapes picked", picks: .layers,
                 options: [.init("operation", .choice(PathCombine.Operation.allCases.map(\.rawValue)),
                                 "How the shapes combine.", required: true)]),
            make(.union, PathCombine.unionTitle, layer, .layers, needs: "two or more shapes picked on a picture",
                 picks: .layers),
            make(.outlineStroke, OutlineStroke.title, layer, .layers, needs: "a stroked shape picked on a picture",
                 picks: .layers),
            make(.separateIntoLayers, "Separate into Layers", layer, .layers, needs: "a picture layer picked",
                 picks: .layers),
            make(.turnIntoText, "Turn into Text", layer, .layers, needs: "a picture of words picked",
                 picks: .layers),
            make(.arrangeInCollage, "Arrange in Collage", layer, .layers, needs: "two or more pictures picked",
                 picks: .layers),
            make(.newCollageLayer, "New Collage Layer", layer, .layers, needs: "a document"),
            make(.group, "Group", layer, .layers, needs: layersPicked, picks: .layers),
            make(.ungroup, "Ungroup", layer, .layers, needs: "a group picked", picks: .layers),
            make(.stackSelection, LayersPanelHeader.MenuRow.stackTitle, layer, .layers,
                 needs: "two or more layers picked", picks: .layers),
            make(.gridSelection, "Grid Selection", layer, .layers, needs: "two or more layers picked",
                 picks: .layers),
            make(.frameSelection, "Frame Selection", layer, .layers, needs: layersPicked, picks: .layers),
            make(.makeComponent, "Make Component", layer, .layers, needs: layersPicked, picks: .layers),
            make(.makeUnique, "Make Unique", layer, .layers, needs: "a component copy picked", picks: .layers),
            make(.align, "Align", "Layer > Align", .layers, needs: layersPicked, picks: .layers,
                 options: [.init("edge", .choice(LayerAlignment.allCases.map(\.rawValue)),
                                 "Which edges or centres line up.", required: true)]),
            make(.spaceEvenly, "Space Evenly", "Layer > Space Evenly", .layers, needs: "three or more layers picked",
                 picks: .layers,
                 options: [.init("axis", .choice(LayerDistribution.allCases.map(\.rawValue)),
                                 "Across or down.", required: true)],
                 also: ["Across", "Down"]),
            make(.bringToFront, "Bring to Front", layer, .layers, needs: layersPicked, picks: .layers),
            make(.bringForward, "Bring Forward", layer, .layers, needs: layersPicked, picks: .layers),
            make(.sendBackward, "Send Backward", layer, .layers, needs: layersPicked, picks: .layers),
            make(.sendToBack, "Send to Back", layer, .layers, needs: layersPicked, picks: .layers),
            make(.deleteLayer, "Delete Layer", layer, .layers, needs: layersPicked, picks: .layers),
        ]
    }()

    static let edit: [AppCommand] = {
        let edit = "Edit"
        return [
            make(.selectAll, "Select All", edit, .edit, needs: "a document"),
            make(.deselect, "Deselect", edit, .edit, needs: "a selection"),
            make(.invertSelection, "Invert Selection", edit, .edit, needs: "a selection"),
            make(.fillWithForeground, "Fill with Foreground", edit, .edit, needs: "a selection or a layer picked",
                 picks: .layers),
            make(.fillWithBackground, "Fill with Background", edit, .edit, needs: "a selection or a layer picked",
                 picks: .layers),
            make(.swapFillColors, "Swap Fill Colors", edit, .edit, needs: "a document"),
        ]
    }()

    static let measure: [AppCommand] = {
        let menu = "Measure"
        return [
            make(.showAllMeasurements, "Show All Measurements", menu, .measure, needs: "a hidden measurement"),
            make(.hideAllMeasurements, "Hide All Measurements", menu, .measure, needs: "a measurement shown"),
            make(.clearMeasurements, "Clear Measurements", menu, .measure, needs: "a measurement"),
        ]
    }()

    static let view: [AppCommand] = {
        let menu = "View"
        return [
            make(.zoomIn, "Zoom In", menu, .view, needs: "a document"),
            make(.zoomOut, "Zoom Out", menu, .view, needs: "a document"),
            make(.zoomToFit, "Zoom to Fit", menu, .view, needs: "a document"),
            make(.actualSize, "Actual Size", menu, .view, needs: "a document"),
            make(.zoomTimelineToFit, "Zoom Timeline to Fit", menu, .view, needs: "a timeline zoomed in"),
            make(.compactTracks, "Compact Tracks", menu, .view, needs: "tracks drawn taller than compact"),
            make(.captionSafeAreas, "Caption Safe Areas", menu, .view, needs: "captions", toggle: true),
        ]
    }()

    // MARK: Checking a call

    /// A `run_command` call checked against the command's own arguments.
    public static func call(_ name: String, arguments: AgentJSON?) -> Result<AppCommandCall, AgentToolError> {
        guard let command = command(named: name) else {
            let near = nearest(to: name).map { " Did you mean \($0)?" } ?? ""
            return .failure(AgentToolError("There is no command called \(name). list_commands lists them.\(near)"))
        }
        let given = arguments ?? .object([:])
        if let problem = AgentSchema.problem(with: given, against: command.inputSchema, at: "") {
            return .failure(AgentToolError("\(name): \(problem)"))
        }
        let args = given.objectValue ?? [:]
        let layers = args["layers"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let piece = args["piece"]?.intValue
        if piece != nil, layers.count != 1 {
            return .failure(AgentToolError("\(name): piece needs exactly one clip id in layers."))
        }
        let own = Set(command.options.map(\.name))
        return .success(AppCommandCall(
            command.id,
            atMS: args["seconds"]?.doubleValue.map { Int(($0 * 1000).rounded()) },
            layers: layers, piece: piece, track: args["track"]?.stringValue,
            on: args["on"]?.boolValue,
            options: args.filter { own.contains($0.key) }))
    }

    /// The command whose name is closest to `name`, for a call that misspelt
    /// one: the one containing it, else the one sharing the most words.
    static func nearest(to name: String) -> String? {
        let asked = name.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
        if let exact = command(named: asked) { return exact.name }
        if let containing = all.first(where: { $0.name.contains(asked) || asked.contains($0.name) }) {
            return containing.name
        }
        let words = Set(asked.split(separator: "_"))
        let scored = all.map { ($0.name, Set($0.name.split(separator: "_")).intersection(words).count) }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        return best.0
    }

    // MARK: Listing

    /// One command as `list_commands` lists it. `ready` says whether it can
    /// run right now on the document asked about, as it stands.
    public static func listing(_ command: AppCommand, ready: Bool) -> AgentJSON {
        var entry: [String: AgentJSON] = [
            "name": .string(command.name),
            "title": .string(command.title),
            "menu": .string(command.menu),
            "area": .string(command.area.rawValue),
            "needs": .string(command.needs),
            "ready": .bool(ready),
        ]
        if !command.arguments.isEmpty {
            entry["arguments"] = command.inputSchema["properties"]
            let required = command.arguments.filter(\.required).map(\.name)
            if !required.isEmpty { entry["required"] = .array(required.map(AgentJSON.string)) }
        }
        return .object(entry)
    }
}
