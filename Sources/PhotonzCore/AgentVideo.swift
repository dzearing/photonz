import CoreGraphics
import Foundation

// The video slice of the agent channel (`docs/design/agent-mcp.md`, slice 4):
// cut a video out of History recordings with title pages, transitions and the
// zooms the app recommends, and write it out as an MP4.
//
// Every tool is a typed way into an edit a person already makes: File > New
// Video (from clips, the way Premiere's New Sequence from Clip sizes the
// frame to the first), Add Media at Playhead, the blade, the trim handles, a
// clip dragged along, the transition picker, Insert Title Page with its words
// typed in, Suggest Zooms and Export. The app half is
// `Sources/Photonz/Agent/AgentVideoWork.swift`.

/// A recording to put on the timeline: a file, or an item of History by its
/// place in `list_history`.
public enum AgentClipSource: Hashable, Sendable {
    case path(String)
    case history(index: Int)
}

/// File > New Video, sized by hand or by the first clip, with the clips laid
/// end to end on its first picture track.
public struct AgentNewVideo: Hashable, Sendable {
    public var size: CGSize?
    public var lengthMS: Int?
    public var clips: [AgentClipSource]

    public init(size: CGSize? = nil, lengthMS: Int? = nil, clips: [AgentClipSource] = []) {
        self.size = size
        self.lengthMS = lengthMS
        self.clips = clips
    }
}

/// A title page or name card in one of the app's styles, with its words.
public struct AgentTitle: Hashable, Sendable {
    public var kind: TitleKind
    /// The style's name as Insert Title Page lists it; the first when nil.
    public var style: String?
    /// The main line: a page's Title, a card's Name.
    public var text: String
    /// The second line: a page's Subtitle, a card's Role. Nil takes the
    /// style's sample line away rather than leaving it in.
    public var subtitle: String?
    /// The clip a page goes in front of, everything after it moving along.
    public var beforeClip: String?
    /// Where it goes when it is not in front of a clip.
    public var atMS: Int?
    public var track: String?

    public init(kind: TitleKind, style: String? = nil, text: String, subtitle: String? = nil,
                beforeClip: String? = nil, atMS: Int? = nil, track: String? = nil) {
        self.kind = kind
        self.style = style
        self.text = text
        self.subtitle = subtitle
        self.beforeClip = beforeClip
        self.atMS = atMS
        self.track = track
    }
}

extension AgentTools {

    // MARK: Schema pieces

    private static let videoDocument: AgentJSON = [
        "type": "string",
        "description": "The video's id from list_documents, such as d2. Leave it out to use the document in front.",
    ]

    private static func secondsProperty(_ words: String) -> AgentJSON {
        ["type": "number", "minimum": 0, "description": .string(words)]
    }

    private static let clipProperty: AgentJSON = [
        "type": "string", "description": "The clip's layer id, from read_document's tracks.",
    ]

    private static let trackProperty: AgentJSON = [
        "type": "string", "description": "A track id from read_document. The first picture track (V1) when left out.",
    ]

    /// A recording, by path or by History index.
    private static let clipSourceProperties: [String: AgentJSON] = [
        "historyIndex": ["type": "integer", "minimum": 0,
                         "description": "The recording's index in list_history; 0 is the newest."],
        "path": ["type": "string", "description": "An absolute path to a recording."],
    ]

    private static func videoSchema(_ properties: [String: AgentJSON], required: [String] = []) -> AgentJSON {
        ["type": "object", "properties": .object(properties),
         "required": .array(required.map(AgentJSON.string)), "additionalProperties": false]
    }

    // MARK: The tools

    /// Slice 4: cut a video.
    static let videoTools: [AgentTool] = [
        AgentTool(
            name: "new_video",
            description: "Open a new video in its own window, as File > New Video does, and answer with its id. Give clips to lay recordings end to end on V1; the frame then takes the first clip's size unless width and height say otherwise, and the length follows what is on it. One undo step takes the clips back off.",
            inputSchema: videoSchema([
                "width": ["type": "integer", "minimum": 16, "maximum": 8000, "description": "Frame width in pixels. 1920, or the first clip's, when left out."],
                "height": ["type": "integer", "minimum": 16, "maximum": 8000, "description": "Frame height in pixels. 1080, or the first clip's, when left out."],
                "seconds": secondsProperty("How long an empty video runs. 10 when left out with no clips; with clips it is as long as they are."),
                "clips": ["type": "array", "description": "Recordings to lay end to end on V1, in order.",
                          "items": ["type": "object", "properties": .object(clipSourceProperties),
                                    "additionalProperties": false]],
            ])),
        AgentTool(
            name: "add_clip",
            description: "Put a recording on the timeline, as Add Media at Playhead does: at the end of what is on the track unless seconds says where, over anything already there. Answers with the clip's id and times. One undo step.",
            inputSchema: videoSchema(clipSourceProperties.merging([
                "document": videoDocument,
                "seconds": secondsProperty("Where the clip starts. Straight after the last clip on the track when left out."),
                "track": trackProperty,
            ]) { $1 })),
        AgentTool(
            name: "cut",
            description: "Cut a clip in two at a moment with the blade, as Split at Playhead does. The two pieces stay one clip, so a transition can go on the cut. One undo step.",
            inputSchema: videoSchema([
                "document": videoDocument,
                "seconds": secondsProperty("Where to cut, on the video's clock."),
                "clip": ["type": "string", "description": "The clip to cut. The clip under that moment on the highest picture track when left out."],
            ], required: ["seconds"])),
        AgentTool(
            name: "trim",
            description: "Keep only part of a clip's recording, as dragging its ends does. Times are on the recording's own clock, 0 being its first frame; for a title or shape, which has no recording, they say when it arrives and goes from its own first frame, so toSeconds alone sets how long it lasts. The clip keeps its start; with ripple, everything after it moves up to close the gap (or along to make room). One undo step.",
            inputSchema: videoSchema([
                "document": videoDocument,
                "clip": clipProperty,
                "fromSeconds": secondsProperty("The first moment of the recording to keep. Unchanged when left out."),
                "toSeconds": secondsProperty("The last moment to keep. Unchanged when left out."),
                "ripple": ["type": "boolean", "description": "Close or open the gap after the clip on every track. False when left out."],
            ], required: ["clip"])),
        AgentTool(
            name: "move_clip",
            description: "Slide a clip along the timeline or onto another track, as dragging its bar does. Refused where it would land over another clip. One undo step.",
            inputSchema: videoSchema([
                "document": videoDocument,
                "clip": clipProperty,
                "seconds": secondsProperty("Where it should start. Where it is when left out."),
                "track": ["type": "string", "description": "A track id from read_document to move it onto."],
            ], required: ["clip"])),
        AgentTool(
            name: "set_transition",
            description: "Put a transition on a cut, as the transition picker does: the cut at seconds (read_document lists every cut with its time), the kind, and how long. A kind that needs frames the cut does not have is refused with the kinds it can take. One undo step.",
            inputSchema: videoSchema([
                "document": videoDocument,
                "seconds": secondsProperty("The cut's time from read_document's cuts."),
                "kind": ["type": "string",
                         "enum": .array((ClipTransitionKind.allCases.map(\.rawValue) + ["none"]).map(AgentJSON.string)),
                         "description": "The transition, or none for a plain cut."],
                "lengthSeconds": ["type": "number", "minimum": .number(0.05), "maximum": 10,
                                  "description": "How long it takes. The kind's usual length when left out, shortened to what the cut can pay for."],
            ], required: ["seconds", "kind"])),
        AgentTool(
            name: "add_title",
            description: "Insert a title page or name card in one of the app's styles, with its words, as Sequence > Insert Title Page does and typing does. Give clip to put a page in front of that clip (or page) on its track, it and what follows moving along, with the default transition on the join. Lines of the style's sample words you do not word are taken out. One undo step.",
            inputSchema: videoSchema([
                "document": videoDocument,
                "kind": ["type": "string", "enum": .array([TitleKind.titlePage, .nameCard].map { .string($0.rawValue) }),
                         "description": "titlePage fills the frame; nameCard sits low over the picture. titlePage when left out."],
                "style": ["type": "string", "description": "The style's name as list_titles gives it. The first style when left out."],
                "text": ["type": "string", "description": "The main line: a page's title, a card's name."],
                "subtitle": ["type": "string", "description": "The second line: a page's subtitle, a card's role. Left out, the style's sample line is taken away."],
                "clip": ["type": "string", "description": "A clip's or another title page's id: the page goes in front of it on its track."],
                "seconds": secondsProperty("Where it goes when no clip is given. The playhead when left out."),
                "track": ["type": "string", "description": "With seconds: the track it goes on when that track is free there; otherwise a new track over it, since a title never covers a clip. The answer names the track."],
            ], required: ["text"])),
        AgentTool(
            name: "list_titles",
            description: "The title page and name card styles the Insert menu offers, by name, your own first.",
            inputSchema: videoSchema(["document": videoDocument])),
        AgentTool(
            name: "recommended_zooms",
            description: "The zooms the app recommends for a recording, from the clicks it kept while recording: when each eases in and out, on the video's clock, and how far in. Nothing changes; apply_zooms puts them on.",
            inputSchema: videoSchema([
                "document": videoDocument,
                "clip": ["type": "string", "description": "One clip's id. Every recording on the timeline when left out."],
            ])),
        AgentTool(
            name: "apply_zooms",
            description: "Put the recommended zooms on a clip, or on every recording, as Suggest Zooms does. One undo step for all of them.",
            inputSchema: videoSchema([
                "document": videoDocument,
                "clip": ["type": "string", "description": "One clip's id. Every recording that has recommendations when left out."],
            ])),
        AgentTool(
            name: "set_playhead",
            description: "Move the playhead to a moment, as clicking the ruler does. The window shows that frame.",
            inputSchema: videoSchema([
                "document": videoDocument,
                "seconds": secondsProperty("The moment, on the video's clock."),
            ], required: ["seconds"])),
    ]

    // MARK: Checking a call

    static let videoToolNames: Set<String> = Set(videoTools.map(\.name))

    private static func clipSource(_ json: AgentJSON?, _ tool: String) -> Result<AgentClipSource?, AgentToolError> {
        let path = json?["path"]?.stringValue
        let index = json?["historyIndex"]?.intValue
        switch (path, index) {
        case (nil, nil): return .success(nil)
        case (let path?, nil):
            let full = (path as NSString).expandingTildeInPath
            guard full.hasPrefix("/") else { return .failure(AgentToolError("\(tool): path must be absolute.")) }
            return .success(.path(full))
        case (nil, let index?): return .success(.history(index: index))
        default: return .failure(AgentToolError("\(tool): give either path or historyIndex, not both."))
        }
    }

    private static func milliseconds(_ json: AgentJSON?) -> Int? {
        json?.doubleValue.map { Int(($0 * 1000).rounded()) }
    }

    static func videoRequest(_ name: String, _ args: [String: AgentJSON],
                             document: String?) -> Result<AgentRequest, AgentToolError> {
        func fail(_ words: String) -> Result<AgentRequest, AgentToolError> { .failure(AgentToolError("\(name): \(words)")) }
        switch name {
        case "new_video":
            let width = args["width"]?.intValue, height = args["height"]?.intValue
            if (width == nil) != (height == nil) { return fail("give width and height together, or neither.") }
            var clips: [AgentClipSource] = []
            for (index, item) in (args["clips"]?.arrayValue ?? []).enumerated() {
                switch clipSource(item, name) {
                case .failure(let error): return .failure(error)
                case .success(nil): return fail("clips[\(index)] needs a path or a historyIndex.")
                case .success(let source?): clips.append(source)
                }
            }
            let size = width.flatMap { w in height.map { CGSize(width: w, height: $0) } }
            return .success(.newVideo(AgentNewVideo(size: size, lengthMS: milliseconds(args["seconds"]), clips: clips)))
        case "add_clip":
            switch clipSource(.object(args), name) {
            case .failure(let error): return .failure(error)
            case .success(nil): return fail("give the recording's path or its historyIndex.")
            case .success(let source?):
                return .success(.addClip(document: document, clip: source, atMS: milliseconds(args["seconds"]),
                                         track: args["track"]?.stringValue))
            }
        case "cut":
            return .success(.cut(document: document, atMS: milliseconds(args["seconds"]) ?? 0,
                                 clip: args["clip"]?.stringValue))
        case "trim":
            let from = milliseconds(args["fromSeconds"]), to = milliseconds(args["toSeconds"])
            guard from != nil || to != nil else { return fail("say fromSeconds, toSeconds or both.") }
            if let from, let to, to <= from { return fail("toSeconds must come after fromSeconds.") }
            return .success(.trim(document: document, clip: args["clip"]?.stringValue ?? "",
                                  keepFromMS: from, keepToMS: to, ripple: args["ripple"]?.boolValue ?? false))
        case "move_clip":
            let to = milliseconds(args["seconds"]), track = args["track"]?.stringValue
            guard to != nil || track != nil else { return fail("say seconds, track or both.") }
            return .success(.moveClip(document: document, clip: args["clip"]?.stringValue ?? "", toMS: to, track: track))
        case "set_transition":
            let word = args["kind"]?.stringValue ?? ""
            let kind = ClipTransitionKind(rawValue: word)
            if kind == nil, word != "none" { return fail("kind is required.") }
            if kind == nil, args["lengthSeconds"] != nil { return fail("a plain cut has no length.") }
            return .success(.setTransition(document: document, atMS: milliseconds(args["seconds"]) ?? 0,
                                           kind: kind, lengthMS: milliseconds(args["lengthSeconds"])))
        case "add_title":
            let words = args["text"]?.stringValue ?? ""
            guard !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fail("text is empty.") }
            let kind = args["kind"]?.stringValue.flatMap(TitleKind.init(rawValue:)) ?? .titlePage
            let clip = args["clip"]?.stringValue
            if clip != nil, args["seconds"] != nil || args["track"] != nil {
                return fail("a title in front of a clip goes where the clip starts; leave seconds and track out.")
            }
            if clip != nil, kind != .titlePage { return fail("only a title page goes in front of a clip; a name card sits over one.") }
            return .success(.addTitle(document: document, title: AgentTitle(
                kind: kind, style: args["style"]?.stringValue, text: words,
                subtitle: args["subtitle"]?.stringValue, beforeClip: clip,
                atMS: milliseconds(args["seconds"]), track: args["track"]?.stringValue)))
        case "list_titles":
            return .success(.listTitles(document: document))
        case "recommended_zooms":
            return .success(.recommendedZooms(document: document, clip: args["clip"]?.stringValue))
        case "apply_zooms":
            return .success(.applyZooms(document: document, clip: args["clip"]?.stringValue))
        case "set_playhead":
            return .success(.setPlayhead(document: document, atMS: milliseconds(args["seconds"]) ?? 0))
        default:
            return .failure(AgentToolError("There is no tool called \(name).", isUnknownTool: true))
        }
    }

    /// `export` with format mp4: the size and the quality the Export sheet
    /// offers, written straight to the path with no save box.
    static func videoExportRequest(_ args: [String: AgentJSON], document: String?,
                                   path: String) -> Result<AgentRequest, AgentToolError> {
        if args["scale"] != nil || args["background"] != nil {
            return .failure(AgentToolError("export: scale and background are for a picture; an MP4 takes size and quality."))
        }
        let size = args["size"]?.stringValue.flatMap(AgentVideoSize.init(rawValue:)) ?? .full
        let quality = args["quality"]?.stringValue.flatMap(VideoExportQuality.init(rawValue:)) ?? .high
        return .success(.exportVideo(document: document, path: path, size: size.exportSize, quality: quality))
    }
}

/// The sizes an MP4 is written at, in the words the Export sheet's Size row
/// uses.
public enum AgentVideoSize: String, CaseIterable, Hashable, Sendable {
    case full
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"

    public var exportSize: VideoExportSize {
        switch self {
        case .full: .full
        case .p1080: .p1080
        case .p720: .p720
        case .p480: .p480
        }
    }
}

// MARK: - The timeline arithmetic the tools need

extension PhotonzDocument {

    /// The picture track a clip goes on when the agent names none: V1, the
    /// lowest picture track, the way a new sequence's first clip lands.
    public var agentDefaultPictureTrack: UUID? {
        timelineTracks.last { $0.kind == .video && !$0.isLocked }?.id
    }

    /// Where the last clip on a track ends: where the next one goes.
    public func endOfTrackMS(_ trackID: UUID) -> Int {
        clipIDs(onTrack: trackID).compactMap { layer(id: $0)?.time?.outMS }.max() ?? 0
    }

    /// The cut nearest `ms` within `reachMS`, so a time read off read_document
    /// (rounded to a millisecond) finds the cut it was read from.
    public func agentCut(nearMS ms: Int, reachMS: Int = 60) -> DocumentCut? {
        transitionCuts().filter { abs($0.atMS - ms) <= reachMS }
            .min { abs($0.atMS - ms) < abs($1.atMS - ms) }
    }

    /// The clip under `ms` on the highest picture track that has one, which is
    /// the one a person sees there.
    public func agentClipUnder(ms: Int) -> UUID? {
        for track in timelineTracks where track.kind == .video {
            for id in clipIDs(onTrack: track.id) {
                guard let clip = layer(id: id), clip.movie != nil, let time = clip.time,
                      time.inMS < ms, ms < time.outMS else { continue }
                return id
            }
        }
        return nil
    }

    /// What a clip would land over if it ran `span` on `trackID`, leaving
    /// itself out: the first clip in the way, or nil when the way is clear.
    public func agentClipInTheWay(of clipID: UUID, span: Range<Int>, onTrack trackID: UUID) -> UUID? {
        clipIDs(onTrack: trackID).first { id in
            guard id != clipID, let time = layer(id: id)?.time else { return false }
            return time.inMS < span.upperBound && span.lowerBound < time.outMS
        }
    }

    /// Whether a title page can go in front of this: anything placed in time
    /// at the top of the document on an unlocked picture track, a title page
    /// included. The person's Insert Title Page goes in front of recordings
    /// only (`canInsertTitle(beforeClip:)`); an agent building a sequence of
    /// pages also puts an opening page in front of a clip's own page.
    public func canInsertTitle(inFrontOf id: UUID) -> Bool {
        if canInsertTitle(beforeClip: id) { return true }
        guard hasTime, let placed = layer(id: id), placed.time != nil, parentID(of: id) == nil,
              let trackID = trackID(ofClip: id), let track = track(id: trackID) else { return false }
        return track.kind == .video && !track.isLocked
    }

    /// A title page in front of `id` on its track, it and everything after it
    /// moving along by the page's length, as `insertTitle(_:beforeClip:)`
    /// does for a recording.
    public mutating func insertTitle(_ preset: TitlePreset, inFrontOf id: UUID,
                                     join: ClipTransitionKind = .usualDefault,
                                     motionBlur: Bool = false) -> InsertedTitle? {
        guard preset.goesInFrontOfAClip, canInsertTitle(inFrontOf: id),
              let trackID = trackID(ofClip: id), let track = track(id: trackID),
              let start = layer(id: id)?.time?.inMS else { return nil }
        let landing = ClipLanding(target: .onto(trackID), startMS: start, lengthMS: preset.lengthMS,
                                  edit: .insert, trackName: track.name, allowed: true)
        return insertTitle(preset, atTimeMS: start, landing: landing, motionBlur: motionBlur, join: join)
    }

    /// Keep `fromMS` to `toMS` of a clip's recording, on the recording's own
    /// clock, as the trim handles do; nil leaves that end where it is. With
    /// `ripple` the time the clip gives up or takes is closed or opened on
    /// every track after it (`rippleTrimClipEdge`); without, the clip keeps
    /// its start and the gap stays (`applyTrim`). Nil with the reason when it
    /// cannot.
    public mutating func agentTrim(_ clipID: UUID, keepFromMS: Int?, keepToMS: Int?,
                                   ripple: Bool) -> String? {
        guard let clip = layer(id: clipID), clip.time != nil else { return "That layer is not on the timeline." }
        if clip.movie == nil, clip.startIsFree {
            return agentRetime(clipID, fromMS: keepFromMS, toMS: keepToMS, ripple: ripple)
        }
        guard var session = ClipTrimSession(layer: clip) else { return "That layer is not a clip with time." }
        let whole = session.wholeLengthMS
        let from = keepFromMS ?? session.keepInMS
        let to = keepToMS ?? session.keepOutMS
        guard from < whole else {
            return "The recording is \(AgentContactSheet.label(ms: whole)) long; fromSeconds must be inside it."
        }
        guard to > from else { return "That keeps nothing: toSeconds must come after fromSeconds." }
        let cappedTo = min(to, whole)
        guard cappedTo - from >= ClipPiece.shortestMS else { return "That keeps too little of the clip." }
        if isClipOnLockedTrack(clipID) { return "\(clip.name) is on a locked track." }
        guard ripple else {
            session.dragIn(toMS: from)
            session.dragOut(toMS: cappedTo)
            guard session.isChanged else { return "The clip already keeps exactly that." }
            return applyTrim(session) ? nil : "The clip would not take that trim."
        }
        let inDelta = from - session.openedInMS
        let outDelta = cappedTo - session.openedOutMS
        guard inDelta != 0 || outDelta != 0 else { return "The clip already keeps exactly that." }
        // The back first, so the front's piece count is the one it was opened with.
        if outDelta != 0 {
            let last = (layer(id: clipID)?.clipPieces?.count ?? 1) - 1
            guard rippleTrimClipEdge(clipID, .seam(after: last), byMS: outDelta) else {
                return "The clip's end would not move that far."
            }
        }
        if inDelta != 0, !rippleTrimClipEdge(clipID, .clipStart, byMS: inDelta) {
            return "The clip's start would not move that far."
        }
        return nil
    }

    /// A title, a shape or words placed in time: nothing is behind it to
    /// trim into, so `fromMS` and `toMS` say when it arrives and goes, from
    /// its own first frame, as dragging the ends of its bar does
    /// (`moveLayerStart`, `moveLayerEnd`). With `ripple` a longer or shorter
    /// end moves what follows on every track by the difference.
    private mutating func agentRetime(_ id: UUID, fromMS: Int?, toMS: Int?, ripple: Bool) -> String? {
        guard let time = layer(id: id)?.time else { return "That layer is not on the timeline." }
        if isClipOnLockedTrack(id) { return "\(layer(id: id)?.name ?? "It") is on a locked track." }
        let start = time.inMS + (fromMS ?? 0)
        let end = toMS.map { time.inMS + $0 } ?? time.outMS
        guard end - start >= LayerTime.shortestMS else { return "That keeps too little of it." }
        guard start != time.inMS || end != time.outMS else { return "It already runs exactly that long." }
        if ripple {
            if start != time.inMS { return "ripple moves the end of a title or shape; leave fromSeconds out." }
            let gained = end - time.outMS
            if gained < 0 {
                extractStretch(fromMS: end, toMS: time.outMS, exceptLayers: [id])
            } else {
                rippleTime(atMS: time.outMS, byMS: gained, exceptLayer: id, sparingLocked: true)
            }
            updateLayer(id: id) { $0.time = LayerTime(inMS: time.inMS, outMS: end, sourceInMS: time.sourceInMS) }
            refreshDuration()
            return nil
        }
        if end != time.outMS { _ = moveLayerEnd(id, toMS: end) }
        if start != time.inMS { _ = moveLayerStart(id, toMS: start) }
        return nil
    }
}
