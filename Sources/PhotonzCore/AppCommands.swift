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
    case exportCaptions = "export_captions"
    case renameTrack = "rename_track"
    case section = "section"
    // Sequence > Caption Word: the word being said at the playhead
    case editCaptionWord = "edit_caption_word"
    case splitCaptionWord = "split_caption_word"
    case mergeCaptionWord = "merge_caption_word"
    case deleteCaptionWord = "delete_caption_word"
    case moveWordToPreviousLine = "move_word_to_previous_line"
    case moveWordToNextLine = "move_word_to_next_line"
    case joinWithNextLine = "join_with_next_line"
    case playFromWord = "play_from_word"
    case goToCaptionStart = "go_to_caption_start"
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
    case renameClip = "rename_clip"
    case addClick = "add_click"
    case followCursor = "follow_cursor"
    case setZoomAmount = "set_zoom_amount"
    case deleteZoom = "delete_zoom"
    case addMediaAtPlayhead = "add_media_at_playhead"
    case insertTitle = "insert_title"
    case saveTitlePreset = "save_title_preset"
    case exportSound = "export_sound"
    // Clip: time
    case freezeFrame = "freeze_frame"
    case showPicture = "show_picture"
    case setSpeed = "set_speed"
    case addSpeedStop = "add_speed_stop"
    case deleteSpeedStop = "delete_speed_stop"
    case resetRamp = "reset_ramp"
    case punchIn = "punch_in"
    case pullBackOut = "pull_back_out"
    case resetReframe = "reset_reframe"
    case setFade = "set_fade"
    case fadeInAndOut = "fade_in_and_out"
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
    case setEasing = "set_easing"
    case straightenStretch = "straighten_stretch"
    case animateProperty = "animate_property"
    case stopAnimating = "stop_animating"
    // File
    case save = "save"
    case importMedia = "import_media"
    // Image
    case resizeImage = "resize_image"
    case canvasSize = "canvas_size"
    // Edit
    case cut = "cut"
    case copy = "copy"
    case copyMerged = "copy_merged"
    case copySVG = "copy_svg"
    case copyVideo = "copy_video"
    case copyAsGIF = "copy_as_gif"
    case paste = "paste"
    case selectAll = "select_all"
    case deselect = "deselect"
    case invertSelection = "invert_selection"
    case fillWithForeground = "fill_with_foreground"
    case fillWithBackground = "fill_with_background"
    case swapFillColors = "swap_fill_colors"
    case flipHorizontal = "flip_horizontal"
    case flipVertical = "flip_vertical"
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
    case renameLayer = "rename_layer"
    case lockLayer = "lock_layer"
    case showColumns = "show_columns"
    case addEffect = "add_effect"
    case addSavedEffect = "add_saved_effect"
    case removeEffect = "remove_effect"
    case setArrowStyle = "set_arrow_style"
    case reshuffleArrows = "reshuffle_arrows"
    case straightenArrows = "straighten_arrows"
    case turnIntoPath = "turn_into_path"
    case putTextOnPath = "put_text_on_path"
    case turnIntoPicture = "turn_into_picture"
    case bringIntoView = "bring_into_view"
    case fillTheStack = "fill_the_stack"
    case surfaceBehind = "surface_behind"
    case inFrontOfTheRest = "in_front_of_the_rest"
    case newFrame = "new_frame"
    case addVariant = "add_variant"
    case applyToOtherVersions = "apply_to_other_versions"
    case makeAlternatives = "make_alternatives"
    case editOriginal = "edit_original"
    case doneEditingOriginal = "done_editing_original"
    case reset3DRotation = "reset_3d_rotation"
    case bringNearer = "bring_nearer"
    case sendFurther = "send_further"
    // Measure
    case showAllMeasurements = "show_all_measurements"
    case hideAllMeasurements = "hide_all_measurements"
    case clearMeasurements = "clear_measurements"
    case copySpecList = "copy_spec_list"
    case copyMeasurements = "copy_measurements"
    // View
    case zoomIn = "zoom_in"
    case zoomOut = "zoom_out"
    case zoomToFit = "zoom_to_fit"
    case actualSize = "actual_size"
    case zoomTimelineToFit = "zoom_timeline_to_fit"
    case compactTracks = "compact_tracks"
    case captionSafeAreas = "caption_safe_areas"
    case resetCamera = "reset_camera"
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
        /// Words: a name, a caption word, a path to a file.
        case text
        /// A measured amount, such as a width in points.
        case amount(minimum: Double, maximum: Double)
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
        case .trackID, .text:
            schema["type"] = "string"
        case let .amount(minimum, maximum):
            schema["type"] = "number"
            schema["minimum"] = .number(minimum)
            schema["maximum"] = .number(maximum)
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
        /// The document itself: saving it, its size, what comes into it.
        case document
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
    public func amount(_ name: String) -> Double? { options[name]?.doubleValue }
    public func flag(_ name: String) -> Bool? { options[name]?.boolValue }
}

/// The table of every command, and the checking of a call against it.
public enum AppCommandTable {

    public static let all: [AppCommand] = timeline + clip + layers + edit + measure + view + document

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

    /// How far Clip > Zoom takes a zoom in, in percent.
    public static let zoomPercents = [125, 150, 200, 250, 300, 400]

    /// How far Picked in Range > Lower Volume takes a section down, in dB.
    public static let lowerVolumeSteps = [3, 6, 12, 20]

    /// What Picked in Range offers in the menu bar (Delete and Ripple Delete
    /// are Clip > Delete and Ripple Delete, which say Section then).
    public static let sectionOperations = SectionOperation.allCases.filter {
        $0 != .deleteSection && $0 != .rippleDeleteSection
    }

    private static let pathArgument = AppCommandArgument(
        "path", .text, "An absolute path to write, or to read from.", required: true)
    private static let nameArgument = AppCommandArgument("name", .text, "The new name.", required: true)
    private static func size(_ what: String) -> [AppCommandArgument] {
        [.init("width", .amount(minimum: 1, maximum: 30_000), "The \(what) width, in points.", required: true),
         .init("height", .amount(minimum: 1, maximum: 30_000), "The \(what) height, in points.", required: true)]
    }

    // MARK: The table

    static let timeline: [AppCommand] = {
        let seq = "Sequence", track = "Sequence > Track", word = "Sequence > Caption Word"
        let wordSaid = "a caption word being said at the playhead"
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
            make(.exportCaptions, "Export Captions as SRT\u{2026}", seq, .timeline, needs: "captions",
                 options: [.init("format", .choice(CaptionFileFormat.allCases.map(\.rawValue)),
                                 "srt or vtt (WebVTT).", required: true), pathArgument],
                 also: ["Export Captions as WebVTT\u{2026}"]),
            make(.renameTrack, "Rename Track\u{2026}", track, .timeline, needs: trackInHand, picks: .track,
                 options: [nameArgument]),
            make(.section, "Picked in Range", "Sequence > Picked in Range", .timeline,
                 needs: "an in and an out set, and clips picked that run through them", picks: .layers,
                 options: [.init("operation", .choice(sectionOperations.map(\.rawValue)),
                                 "What to do to the picked clips between in and out.", required: true),
                           .init("db", .number(lowerVolumeSteps), "lowerVolume: how far down, in dB."),
                           .init("percent", .number(speeds.filter { $0 != ClipPiece.asRecordedPercent }),
                                 "speedForSection: the speed, in percent of normal.")]),
            make(.editCaptionWord, "Edit Word", word, .timeline, needs: wordSaid, picks: .playhead,
                 options: [.init("text", .text, "The word as it should read.", required: true)]),
            make(.splitCaptionWord, "Split Here", word, .timeline, needs: "a word of two letters or more being said",
                 picks: .playhead),
            make(.mergeCaptionWord, "Merge with Next", word, .timeline, needs: "a word being said with one after it",
                 picks: .playhead),
            make(.deleteCaptionWord, "Delete Word", word, .timeline, needs: wordSaid, picks: .playhead),
            make(.moveWordToPreviousLine, "Move to Previous Line", word, .timeline,
                 needs: "the first word of a caption with one before it", picks: .playhead),
            make(.moveWordToNextLine, "Move to Next Line", word, .timeline, needs: wordSaid, picks: .playhead),
            make(.joinWithNextLine, "Join with Next Line", word, .timeline, needs: "a caption with one after it",
                 picks: .playhead),
            make(.playFromWord, "Play from Here", word, .timeline, needs: wordSaid, picks: .playhead),
            make(.goToCaptionStart, "Start Here", word, .timeline, needs: wordSaid, picks: .playhead),
        ]
    }()

    static let clip: [AppCommand] = {
        let clip = "Clip", animate = "Clip > Animate", cut = "Clip > Transition at Cut"
        let normalize = "Clip > Normalize"
        let zoomHere = "a zoom at the playhead on the recording in hand"
        let soundPicked = "a sound picked, or a clip with sound under the playhead"
        return [
            make(.splitAtPlayhead, "Split at Playhead", clip, .timeline, needs: "a clip under the playhead",
                 picks: .clipAtPlayhead),
            make(.delete, "Delete This Piece", clip, .timeline,
                 needs: "a piece, range, gap, transition or keys in hand", picks: [.playhead, .layers, .piece, .track],
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
            make(.renameClip, "Rename\u{2026}", clip, .timeline, needs: clipInHand, picks: [.playhead, .layers],
                 options: [nameArgument]),
            make(.addClick, "Add Click at Playhead\u{2026}", clip, .timeline, needs: "a recording in hand",
                 picks: [.playhead, .layers],
                 options: [.init("x", .amount(minimum: -100_000, maximum: 100_000),
                                 "Where the click lands across the canvas, in points.", required: true),
                           .init("y", .amount(minimum: -100_000, maximum: 100_000),
                                 "Where the click lands down the canvas, in points.", required: true)]),
            make(.followCursor, "Follow Cursor", clip, .timeline, needs: zoomHere, picks: [.playhead, .layers],
                 toggle: true),
            make(.setZoomAmount, "Zoom", "Clip > Zoom", .timeline, needs: zoomHere, picks: [.playhead, .layers],
                 options: [.init("percent", .number(zoomPercents), "How far in, in percent.", required: true)]),
            make(.deleteZoom, "Delete Zoom", clip, .timeline, needs: zoomHere, picks: [.playhead, .layers]),
            make(.addMediaAtPlayhead, "Add Media at Playhead\u{2026}", "Sequence", .timeline, needs: aVideo,
                 picks: .playhead,
                 options: [.init("path", .text, "An absolute path to a recording or a sound.", required: true)]),
            make(.insertTitle, "Insert Title", "Sequence > Insert Title Page", .timeline,
                 needs: "a video", picks: [.playhead, .track],
                 options: [.init("kind", .choice(TitleKind.allCases.map(\.rawValue)), "Which kind of title.",
                                 required: true),
                           .init("preset", .text, "The style's name, as the Insert menu lists it.", required: true)]),
            make(.saveTitlePreset, "Save as Preset\u{2026}", clip, .timeline, needs: "a title page or name card in hand",
                 picks: [.playhead, .layers], options: [nameArgument]),
            make(.exportSound, "Export Sound\u{2026}", "Sequence", .timeline, needs: "a video with sound",
                 options: [pathArgument]),
            make(.freezeFrame, "Freeze Frame\u{2026}", clip, .timeline, needs: "a picture clip under the playhead",
                 picks: .clipAtPlayhead,
                 options: [.init("milliseconds", .integer(minimum: 1, maximum: 3_600_000),
                                 "How long the frame holds.", required: true),
                           .init("everyTrack", .flag, "true holds every track while it holds; false holds only its own.")]),
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
            make(.fadeInAndOut, "Fade In and Out", clip, .timeline, needs: "a picture or title in hand",
                 picks: [.playhead, .layers], toggle: true),
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
            make(.setEasing, "Easing", "Clip > Animate > Easing", .timeline,
                 needs: "a layer in hand that is between two keys", picks: [.playhead, .layers],
                 options: [.init("curve", .choice(EasingCurve.named.map(\.title)),
                                 "How it speeds up and slows down between the keys.", required: true)]),
            make(.straightenStretch, "Straighten This Stretch", animate, .timeline,
                 needs: "a layer in hand whose path bends at the playhead", picks: [.playhead, .layers]),
            make(.animateProperty, "Animate", animate, .timeline, needs: "a layer in hand with a value not animating",
                 picks: [.playhead, .layers],
                 options: [.init("property", .text,
                                 "The value, in the words its Animate row uses: Position, Scale, Opacity.",
                                 required: true)]),
            make(.stopAnimating, "Stop Animating", animate, .timeline, needs: "a layer in hand with a value animating",
                 picks: .layers,
                 options: [.init("property", .text,
                                 "The value to stop, in its row's words. Left out, the only one animating.")]),
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
            make(.makeComponent, "Make Component", layer, .layers, needs: "one group picked", picks: .layers),
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
            make(.renameLayer, "Rename Layer\u{2026}", layer, .layers, needs: "a layer picked", picks: .layers,
                 options: [nameArgument]),
            make(.lockLayer, MenuToggleNames.layerLocked, layer, .layers, needs: "a layer picked", picks: .layers,
                 toggle: true),
            make(.showColumns, MenuToggleNames.showColumns, layer, .layers, needs: "a frame picked", picks: .layers,
                 toggle: true),
            make(.addEffect, "Add Effect", "Layer > Add Effect", .layers, needs: layersPicked, picks: .layers,
                 options: [.init("kind", .choice(AddableEffect.allCases.map(\.rawValue)), "The effect to add.",
                                 required: true)]),
            make(.addSavedEffect, "Saved Effects", "Layer > Add Effect", .layers,
                 needs: "an effect saved by name, and layers picked", picks: .layers,
                 options: [.init("style", .text, "The saved effect's name.", required: true)]),
            make(.removeEffect, "Remove Effect", "Layer > Remove Effect", .layers, needs: "a layer with an effect picked",
                 picks: .layers,
                 options: [.init("index", .integer(minimum: 0, maximum: 99),
                                 "Which effect, counting from 0 in the order read_document lists them.", required: true)]),
            make(.setArrowStyle, ArrowStyle.menuTitle, "Layer > Arrow Style", .layers, needs: "an arrow picked",
                 picks: .layers,
                 options: [.init("style", .choice(ArrowStyle.allCases.map(\.rawValue)), "How the arrow is drawn.",
                                 required: true)]),
            make(.reshuffleArrows, ArrowStyle.reshuffleTitle, layer, .layers, needs: "a hand-drawn arrow picked",
                 picks: .layers),
            make(.straightenArrows, ArrowBend.straightenTitle, layer, .layers, needs: "a bent arrow picked",
                 picks: .layers),
            make(.turnIntoPath, TurnIntoPathPrompt.menuItem, layer, .layers, needs: "shapes or outlines picked",
                 picks: .layers, also: [PathJoin.menuItem, PathClose.menuItem]),
            make(.putTextOnPath, "Put Text on a Path", layer, .layers, needs: "a text layer and a path picked",
                 picks: .layers),
            make(.turnIntoPicture, RasterizePrompt.menuItem, layer, .layers, needs: "a shape or text picked",
                 picks: .layers),
            make(.bringIntoView, "Bring into View", layer, .layers, needs: "a layer picked outside its container",
                 picks: .layers),
            make(.fillTheStack, FlowFillCommand.defaultTitle, layer, .layers, needs: "a layer picked in a stack",
                 picks: .layers, toggle: true),
            make(.surfaceBehind, SurfaceCommand.menuTitle, layer, .layers, needs: "a layer picked in a stack",
                 picks: .layers, toggle: true),
            make(.inFrontOfTheRest, FloatingCommand.menuTitle, layer, .layers, needs: "a layer picked in a stack",
                 picks: .layers, toggle: true),
            make(.newFrame, "New Frame\u{2026}", layer, .layers, needs: "a document", options: size("frame's")),
            make(.addVariant, "Add Variant", layer, .layers, needs: "a component's original picked", picks: .layers),
            make(.applyToOtherVersions, "Apply to Other Variants", layer, .layers,
                 needs: "a component copy picked that differs from its other variants", picks: .layers),
            make(.makeAlternatives, "Make Alternatives", layer, .layers,
                 needs: "shapes picked inside a component's original, being edited",
                 picks: .layers),
            make(.editOriginal, "Edit Original", layer, .layers, needs: "a component copy picked", picks: .layers),
            make(.doneEditingOriginal, "Done Editing Original", layer, .layers, needs: "an original being edited"),
            make(.reset3DRotation, "Reset 3D Rotation", layer, .layers, needs: "a layer turned in depth picked",
                 picks: .layers),
            make(.bringNearer, "Bring Nearer", layer, .layers, needs: layersPicked, picks: .layers),
            make(.sendFurther, "Send Further", layer, .layers, needs: layersPicked, picks: .layers),
        ]
    }()

    static let edit: [AppCommand] = {
        let edit = "Edit"
        let inHand = "something picked: layers, a clip, keys, a range or a transition"
        return [
            make(.cut, "Cut", edit, .edit, needs: inHand, picks: .clipAtPlayhead),
            make(.copy, "Copy", edit, .edit, needs: inHand, picks: .clipAtPlayhead),
            make(.copyMerged, "Copy Merged", edit, .edit, needs: "a document"),
            make(.copySVG, "Copy SVG", edit, .edit, needs: "a drawing: shapes, paths or text", picks: .layers),
            make(.copyVideo, "Copy Video", edit, .edit, needs: aVideo),
            make(.copyAsGIF, "Copy as GIF", edit, .edit, needs: aVideo),
            make(.paste, "Paste", edit, .edit, needs: "something copied",
                 picks: [.playhead, .layers, .track]),
            make(.selectAll, "Select All", edit, .edit, needs: "a document"),
            make(.deselect, "Deselect", edit, .edit, needs: "a selection"),
            make(.invertSelection, "Invert Selection", edit, .edit, needs: "a selection"),
            make(.fillWithForeground, "Fill with Foreground", edit, .edit, needs: "a selection or a layer picked",
                 picks: .layers),
            make(.fillWithBackground, "Fill with Background", edit, .edit, needs: "a selection or a layer picked",
                 picks: .layers),
            make(.swapFillColors, "Swap Fill Colors", edit, .edit, needs: "a document"),
            make(.flipHorizontal, FlipAxis.horizontal.title, "Edit > Transform", .edit,
                 needs: "a layer picked", picks: .layers),
            make(.flipVertical, FlipAxis.vertical.title, "Edit > Transform", .edit,
                 needs: "a layer picked", picks: .layers),
        ]
    }()

    static let measure: [AppCommand] = {
        let menu = "Measure"
        return [
            make(.showAllMeasurements, "Show All Measurements", menu, .measure, needs: "a hidden measurement"),
            make(.hideAllMeasurements, "Hide All Measurements", menu, .measure, needs: "a measurement shown"),
            make(.clearMeasurements, "Clear Measurements", menu, .measure, needs: "a measurement"),
            make(.copySpecList, "Copy as Spec List", menu, .measure, needs: "a measurement shown"),
            make(.copyMeasurements, "Copy Measurement", menu, .measure, needs: "a measurement picked",
                 picks: .layers, also: ["Copy Measurements"]),
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
            make(.resetCamera, "Reset Camera", menu, .layers, needs: "a camera moved"),
        ]
    }()

    static let document: [AppCommand] = [
        make(.save, "Save", "File", .document, needs: "changes, and a file or History item to save them to"),
        make(.importMedia, "Import Media\u{2026}", "File", .document, needs: "a document with a Library",
             options: [.init("path", .text, "An absolute path to a recording, a sound or a picture.", required: true)]),
        make(.resizeImage, "Resize Image\u{2026}", "Image", .document, needs: "a document",
             options: size("new")),
        make(.canvasSize, "Canvas Size\u{2026}", "Image", .document, needs: "a document",
             options: size("canvas's new") + [.init("anchor", .choice(CanvasAnchor.allCases.map(\.rawValue)),
                                                    "Which edge or corner stays put. center when left out.")]),
    ]

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
