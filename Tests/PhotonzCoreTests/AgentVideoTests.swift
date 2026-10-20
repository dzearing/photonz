import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The video tools of the agent channel (`docs/design/agent-mcp.md`, slice
/// 4): their calls checked before the app sees them, and the timeline
/// arithmetic they stand on (`AgentVideo.swift`).
@Suite("Agent tools: cutting a video")
struct AgentVideoTests {

    static func args(_ json: String) throws -> AgentJSON {
        try AgentJSON.parse(Data(json.utf8))
    }

    static func request(_ tool: String, _ json: String?) throws -> Result<AgentRequest, AgentToolError> {
        AgentTools.request(tool: tool, arguments: try json.map(args))
    }

    static func refusal(_ tool: String, _ json: String?) throws -> String? {
        guard case .failure(let error) = try request(tool, json) else { return nil }
        return error.message
    }

    // MARK: Checking calls

    @Test("new_video takes clips from History and from files, in order, and sizes itself unless told")
    func newVideo() throws {
        let made = try Self.request("new_video", #"{"clips": [{"historyIndex": 4}, {"path": "/tmp/a.mp4"}, {"historyIndex": 0}]}"#).get()
        #expect(made == .newVideo(AgentNewVideo(clips: [.history(index: 4), .path("/tmp/a.mp4"), .history(index: 0)])))
        let sized = try Self.request("new_video", #"{"width": 1280, "height": 720, "seconds": 5}"#).get()
        #expect(sized == .newVideo(AgentNewVideo(size: CGSize(width: 1280, height: 720), lengthMS: 5000)))
        #expect(try Self.refusal("new_video", #"{"width": 1280}"#)?.contains("together") == true)
        #expect(try Self.refusal("new_video", #"{"clips": [{}]}"#)?.contains("clips[0]") == true)
        #expect(try Self.refusal("new_video", #"{"clips": [{"path": "a.mp4"}]}"#)?.contains("absolute") == true)
        #expect(try Self.refusal("new_video", #"{"clips": [{"path": "/a.mp4", "historyIndex": 1}]}"#)?.contains("not both") == true)
    }

    @Test("add_clip needs exactly one recording, and takes a time and a track")
    func addClip() throws {
        let call = try Self.request("add_clip", #"{"document": "d2", "historyIndex": 1, "seconds": 2.5, "track": "T"}"#).get()
        #expect(call == .addClip(document: "d2", clip: .history(index: 1), atMS: 2500, track: "T"))
        #expect(try Self.refusal("add_clip", #"{"seconds": 1}"#) != nil)
        #expect(try Self.refusal("add_clip", #"{"historyIndex": -1}"#) != nil, "a negative index passed the schema")
    }

    @Test("cut, trim, move_clip and set_playhead read seconds as milliseconds and refuse a call that says nothing")
    func editing() throws {
        #expect(try Self.request("cut", #"{"seconds": 3.25}"#).get() == .cut(document: nil, atMS: 3250, clip: nil))
        #expect(try Self.refusal("cut", "{}") != nil, "a cut with no time")
        #expect(try Self.request("trim", #"{"clip": "C", "fromSeconds": 1, "ripple": true}"#).get()
                == .trim(document: nil, clip: "C", keepFromMS: 1000, keepToMS: nil, ripple: true))
        #expect(try Self.refusal("trim", #"{"clip": "C"}"#)?.contains("fromSeconds") == true)
        #expect(try Self.refusal("trim", #"{"clip": "C", "fromSeconds": 4, "toSeconds": 2}"#)?.contains("after") == true)
        #expect(try Self.request("move_clip", #"{"clip": "C", "seconds": 0}"#).get()
                == .moveClip(document: nil, clip: "C", toMS: 0, track: nil))
        #expect(try Self.refusal("move_clip", #"{"clip": "C"}"#) != nil)
        #expect(try Self.request("set_playhead", #"{"seconds": 12}"#).get() == .setPlayhead(document: nil, atMS: 12_000))
    }

    @Test("set_transition offers the picker's kinds and none, with an optional length")
    func setTransition() throws {
        #expect(try Self.request("set_transition", #"{"seconds": 4, "kind": "dipToBlack", "lengthSeconds": 0.6}"#).get()
                == .setTransition(document: nil, atMS: 4000, kind: .dipToBlack, lengthMS: 600))
        #expect(try Self.request("set_transition", #"{"seconds": 4, "kind": "none"}"#).get()
                == .setTransition(document: nil, atMS: 4000, kind: nil, lengthMS: nil))
        #expect(try Self.refusal("set_transition", #"{"seconds": 4, "kind": "none", "lengthSeconds": 1}"#) != nil)
        #expect(try Self.refusal("set_transition", #"{"seconds": 4, "kind": "spin"}"#)?.contains("one of") == true)
        let schema = try #require(AgentTools.tool(named: "set_transition")?.inputSchema)
        let kinds = schema["properties"]?["kind"]?["enum"]?.arrayValue?.compactMap(\.stringValue) ?? []
        #expect(Set(kinds) == Set(ClipTransitionKind.allCases.map(\.rawValue) + ["none"]))
    }

    @Test("add_title is a title page unless it says, and goes in front of a clip or at a time, not both")
    func addTitle() throws {
        let page = try Self.request("add_title", #"{"text": "Case 1", "subtitle": "Signing in", "clip": "C", "style": "Clean"}"#).get()
        #expect(page == .addTitle(document: nil, title: AgentTitle(kind: .titlePage, style: "Clean", text: "Case 1",
                                                                    subtitle: "Signing in", beforeClip: "C")))
        let card = try Self.request("add_title", #"{"kind": "nameCard", "text": "Ada", "seconds": 2}"#).get()
        #expect(card == .addTitle(document: nil, title: AgentTitle(kind: .nameCard, text: "Ada", atMS: 2000)))
        #expect(try Self.refusal("add_title", #"{"text": "  "}"#)?.contains("empty") == true)
        #expect(try Self.refusal("add_title", #"{"text": "A", "clip": "C", "seconds": 1}"#) != nil)
        #expect(try Self.refusal("add_title", #"{"text": "A", "kind": "nameCard", "clip": "C"}"#) != nil)
        #expect(try Self.refusal("add_title", #"{"text": "A", "kind": "chart"}"#) != nil, "a chart is not a title an agent words")
    }

    @Test("export writes an MP4 at the Export sheet's sizes, and keeps picture arguments for pictures")
    func exportMP4() throws {
        let call = try Self.request("export", #"{"format": "mp4", "path": "/tmp/montage.mp4", "size": "1080p", "quality": "standard"}"#).get()
        #expect(call == .exportVideo(document: nil, path: "/tmp/montage.mp4", size: .p1080, quality: .standard))
        #expect(try Self.request("export", #"{"format": "mp4", "path": "/tmp/m.mp4"}"#).get()
                == .exportVideo(document: nil, path: "/tmp/m.mp4", size: .full, quality: .high))
        #expect(try Self.refusal("export", #"{"format": "mp4", "path": "/tmp/m.mov"}"#)?.contains(".mp4") == true)
        #expect(try Self.refusal("export", #"{"format": "mp4", "path": "/tmp/m.mp4", "scale": 2}"#) != nil)
        #expect(try Self.refusal("export", #"{"format": "png", "path": "/tmp/m.png", "size": "720p"}"#) != nil)
    }

    // MARK: The timeline arithmetic

    static func movie(durationMS: Int) -> MovieRef {
        MovieRef(id: UUID(), pixelSize: CGSize(width: 1920, height: 1080), durationMS: durationMS)
    }

    /// What new_video with two clips makes: a twelve second take and a five
    /// second one straight after it, on V1 of an empty video.
    static func edit() -> (doc: PhotonzDocument, take: UUID, next: UUID) {
        var doc = PhotonzDocument.emptyVideo(size: CGSize(width: 1920, height: 1080), lengthMS: BlankVideo.shortestLengthMS)
        func land(_ name: String, _ length: Int) -> UUID {
            let movie = movie(durationMS: length)
            var layer = Layer(name: name, content: .image(movie.frameRef(atSourceMS: 0)),
                              frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
            layer.movie = movie
            layer.time = LayerTime(inMS: 0, outMS: length, sourceInMS: 0, sourceLengthMS: length)
            let track = doc.agentDefaultPictureTrack
            let landing = doc.clipLanding(kind: .video, lengthMS: length, atMS: track.map(doc.endOfTrackMS) ?? 0,
                                          over: track.map { .onto($0) }, edit: .overwrite)
            return doc.land(layer, at: landing) ?? UUID()
        }
        let take = land("Take", 12_000)
        let next = land("Next", 5000)
        return (doc, take, next)
    }

    @Test("A clip goes after the last one on V1, and the cut between them is found from its rounded time")
    func placesAndCuts() throws {
        let (doc, take, next) = Self.edit()
        let track = try #require(doc.agentDefaultPictureTrack)
        #expect(doc.trackID(ofClip: take) == track)
        #expect(doc.trackID(ofClip: next) == track)
        #expect(doc.layer(id: next)?.time?.inMS == 12_000)
        #expect(doc.endOfTrackMS(track) == 17_000)
        #expect(doc.documentDurationMS == 17_000, "the video grew to hold its clips")
        let cut = try #require(doc.agentCut(nearMS: 12_001))
        #expect(cut.atMS == 12_000)
        #expect(doc.agentCut(nearMS: 6000) == nil)
        #expect(doc.agentClipUnder(ms: 13_000) == next)
        #expect(doc.agentClipInTheWay(of: next, span: 10_000..<15_000, onTrack: track) == take)
        #expect(doc.agentClipInTheWay(of: next, span: 12_000..<17_000, onTrack: track) == nil)
    }

    @Test("A plain trim keeps the clip's start and leaves the gap; a ripple trim closes it")
    func trims() throws {
        var plain = Self.edit()
        #expect(plain.doc.agentTrim(plain.take, keepFromMS: 2000, keepToMS: 7000, ripple: false) == nil)
        #expect(plain.doc.layer(id: plain.take)?.time?.inMS == 0)
        #expect(plain.doc.layer(id: plain.take)?.time?.lengthMS == 5000)
        #expect(plain.doc.layer(id: plain.take)?.clipPieces?.sourceMS(atMS: 0) == 2000)
        #expect(plain.doc.layer(id: plain.next)?.time?.inMS == 12_000, "a plain trim moved the next clip")

        var ripple = Self.edit()
        #expect(ripple.doc.agentTrim(ripple.take, keepFromMS: 2000, keepToMS: 7000, ripple: true) == nil)
        #expect(ripple.doc.layer(id: ripple.take)?.time?.lengthMS == 5000)
        #expect(ripple.doc.layer(id: ripple.take)?.clipPieces?.sourceMS(atMS: 0) == 2000)
        #expect(ripple.doc.layer(id: ripple.next)?.time?.inMS == 5000)
        #expect(ripple.doc.documentDurationMS == 10_000)
    }

    @Test("A trim that keeps nothing, or reaches past the recording, says why and changes nothing")
    func trimRefusals() {
        var (doc, take, _) = Self.edit()
        let before = doc
        #expect(doc.agentTrim(take, keepFromMS: 13_000, keepToMS: nil, ripple: false)?.contains("12") == true)
        #expect(doc.agentTrim(take, keepFromMS: 0, keepToMS: 12_000, ripple: false)?.contains("already") == true)
        #expect(doc.agentTrim(UUID(), keepFromMS: 0, keepToMS: 1000, ripple: false) != nil)
        #expect(doc == before)
    }

    @Test("An opening page goes in front of a clip's own page, both moving along with what follows")
    func pageInFrontOfAPage() throws {
        var (doc, take, next) = Self.edit()
        let page = try #require(TitlePreset.builtIn(of: .titlePage, movingBackdrops: false).first)
        let insertedFirst = doc.insertTitle(page, beforeClip: take)
        let caseOne = try #require(insertedFirst)
        #expect(doc.canInsertTitle(beforeClip: caseOne.layerID) == false, "the person's door takes recordings only")
        #expect(doc.canInsertTitle(inFrontOf: caseOne.layerID))
        let insertedOpening = doc.insertTitle(page, inFrontOf: caseOne.layerID)
        let opening = try #require(insertedOpening)
        #expect(doc.layer(id: opening.layerID)?.time?.inMS == 0)
        #expect(doc.layer(id: caseOne.layerID)?.time?.inMS == page.lengthMS)
        #expect(doc.layer(id: take)?.time?.inMS == 2 * page.lengthMS)
        #expect(doc.layer(id: next)?.time?.inMS == 2 * page.lengthMS + 12_000)
        #expect(doc.trackID(ofClip: opening.layerID) == doc.trackID(ofClip: take))
    }
}
