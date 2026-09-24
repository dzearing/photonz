import CoreGraphics
import Foundation

// A clip is a layer that points at a recording (`docs/design/video.md`).
//
// `DocumentTime.swift` gave a layer an in and an out. This gives it something
// to PLAY between them, and it does it without breaking the one rule
// `CLAUDE.md` puts above the rest: **pixel data never lives in the document
// model.** A clip carries three numbers about a file — which file, how big its
// picture is, how long it runs — and the frame under the playhead is worked out
// here and fetched by somebody else.
//
// The trick that keeps the renderer out of this entirely: a clip layer is an
// ordinary picture layer whose `ImageRef` is the frame it is showing. Asking
// the document what it looks like at a moment swaps that reference for the one
// belonging to the frame at that moment, and the renderer — which has drawn
// pictures since the first day — draws it without knowing time exists. So a
// clip takes a corner radius, a drop shadow, an effect, a blend mode and a
// place in the stack for free, because it IS a picture layer.

/// The recording a clip plays: which file, how big it is, how long it runs.
///
/// **No pixels and no path.** The id is the recording's identity inside the
/// running app; where the file actually lives is the app's business, the same
/// bargain `ImageRef` already strikes with `ImageStore`.
public struct MovieRef: Hashable, Codable, Sendable {

    /// How far apart the frames a clip is willing to ask for are.
    ///
    /// Frames are asked for on a grid rather than at the exact millisecond the
    /// playhead is on, for one reason: a scrub that asked for a new moment
    /// every pixel would decode a frame per pixel and cache none of them. At
    /// 33ms the grid is about thirty frames a second, which is finer than
    /// anything a screen recording holds and coarse enough that dragging along
    /// a second of timeline asks for thirty frames rather than nine hundred.
    public static let frameStepMS = 33

    public let id: UUID
    /// The recording's own picture size, in pixels.
    public let pixelSize: CGSize
    /// How long the file runs for. This is the whole file, not the part a clip
    /// keeps: a trim moves a clip's in and out and never shortens this, which
    /// is what lets the timeline draw the spare at both ends.
    public let durationMS: Int
    /// Whether the file has a sound track in it at all.
    ///
    /// Not what the sound IS — that is `soundRef`, and it is derived — only
    /// whether asking for it would get anything. A recording with no sound has
    /// nothing to take off it, and the app says so rather than offering it.
    public let hasSound: Bool

    public init(id: UUID = UUID(), pixelSize: CGSize, durationMS: Int, hasSound: Bool = false) {
        self.id = id
        self.pixelSize = pixelSize
        self.durationMS = max(0, durationMS)
        self.hasSound = hasSound
    }

    private enum CodingKeys: String, CodingKey { case id, pixelSize, durationMS, hasSound }

    /// A recording with no sound writes nothing about sound, so every document
    /// written before sound existed reads back byte for byte the same.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(pixelSize, forKey: .pixelSize)
        try c.encode(durationMS, forKey: .durationMS)
        if hasSound { try c.encode(true, forKey: .hasSound) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  pixelSize: try c.decode(CGSize.self, forKey: .pixelSize),
                  durationMS: try c.decode(Int.self, forKey: .durationMS),
                  hasSound: try c.decodeIfPresent(Bool.self, forKey: .hasSound) ?? false)
    }

    /// Which frame of the grid a moment of the file falls on.
    public func frameIndex(atSourceMS ms: Int) -> Int {
        let inside = min(max(0, ms), durationMS)
        return inside / Self.frameStepMS
    }

    /// The moment of the file the frame under `ms` actually starts at. This is
    /// what gets decoded, and two moments inside one frame answer the same
    /// thing, which is what makes the cache worth having.
    public func frameSourceMS(atSourceMS ms: Int) -> Int {
        frameIndex(atSourceMS: ms) * Self.frameStepMS
    }

    /// The picture reference the frame at a moment is registered under.
    ///
    /// Derived rather than stored, so the same frame of the same recording is
    /// the same reference in every window, every render and every run — which
    /// is what lets a frame be fetched once and drawn by anything.
    public func frameRef(atSourceMS ms: Int) -> ImageRef {
        ImageRef(id: MovieRef.frameID(movie: id, frameIndex: frameIndex(atSourceMS: ms)),
                 pixelSize: pixelSize)
    }

    /// The recording's id with the frame number folded into its tail. Two
    /// frames of one recording differ; two recordings never meet, because the
    /// leading bytes are the recording's own random ones.
    static func frameID(movie: UUID, frameIndex: Int) -> UUID {
        var bytes = withUnsafeBytes(of: movie.uuid) { Array($0) }
        var remaining = UInt64(bitPattern: Int64(frameIndex))
        for offset in 0..<8 {
            bytes[15 - offset] ^= UInt8(truncatingIfNeeded: remaining)
            remaining >>= 8
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// One frame somebody has to go and fetch before a moment can be drawn.
///
/// The document says what it needs; the app decodes it and files it under
/// `ref`. Nothing in here is a bitmap and nothing in here is a file path.
public struct MovieFrameRequest: Hashable, Sendable {
    public let layerID: UUID
    public let movie: MovieRef
    /// Where in the recording the frame is, already rounded to the grid.
    public let sourceMS: Int
    /// What to file the decoded frame under.
    public let ref: ImageRef

    public init(layerID: UUID, movie: MovieRef, sourceMS: Int, ref: ImageRef) {
        self.layerID = layerID
        self.movie = movie
        self.sourceMS = sourceMS
        self.ref = ref
    }
}

// MARK: - What a layer says about the recording behind it

extension Layer {

    /// Whether this layer plays a recording.
    public var isClip: Bool { movie != nil }

    /// Which frame of its own file this clip shows at a moment of the
    /// DOCUMENT's clock, or nil at a moment it is not on screen for.
    ///
    /// Everything about where the clip sits, what it was trimmed to, where it
    /// was cut and how fast a piece plays is already answered by `clipPieces`;
    /// this only turns the answer into a moment of the file, rounded to the
    /// grid a frame is actually fetched on.
    public func movieFrameSourceMS(atTimeMS ms: Int) -> Int? {
        guard let movie, let moment = clipMoment(atTimeMS: ms) else { return nil }
        return movie.frameSourceMS(atSourceMS: moment.sourceMS)
    }

    /// The frame coming IN over this one, while a transition that needs an
    /// overlap is running at this moment. Nil the rest of the time, which is
    /// nearly always (`ClipTransitions.swift`).
    public func incomingMovieFrameSourceMS(atTimeMS ms: Int) -> Int? {
        guard let movie, let moment = clipMoment(atTimeMS: ms),
              let incoming = moment.incomingSourceMS else { return nil }
        return movie.frameSourceMS(atSourceMS: incoming)
    }

    /// The frame this clip needs fetched to be drawn at a moment, or nil where
    /// there is nothing to fetch: not a clip, not on screen, or switched off in
    /// the layers list.
    public func movieFrameRequest(atTimeMS ms: Int) -> MovieFrameRequest? {
        guard isVisible, let movie, let sourceMS = movieFrameSourceMS(atTimeMS: ms) else { return nil }
        return MovieFrameRequest(layerID: id, movie: movie, sourceMS: sourceMS,
                                 ref: movie.frameRef(atSourceMS: sourceMS))
    }

    /// Every frame this clip needs at a moment: one ordinarily, and two while a
    /// dissolve is running, because both shots are on screen then and a picture
    /// nobody fetched is a picture nobody draws.
    public func movieFrameRequests(atTimeMS ms: Int) -> [MovieFrameRequest] {
        guard let first = movieFrameRequest(atTimeMS: ms) else { return [] }
        guard let movie, let incoming = incomingMovieFrameSourceMS(atTimeMS: ms) else { return [first] }
        return [first, MovieFrameRequest(layerID: Layer.transitionPartnerID(of: id), movie: movie,
                                         sourceMS: incoming,
                                         ref: movie.frameRef(atSourceMS: incoming))]
    }

    /// This clip showing the frame at a moment: the same layer, with the
    /// picture it points at swapped for that frame's.
    ///
    /// A clip somewhere else in time, or one switched off, comes back
    /// untouched — it is not being drawn, so which frame it would have shown is
    /// nobody's business.
    ///
    /// A frame not yet read is stood in for by the newest one that has been,
    /// when the caller says what has (`MovieFramesInHand.swift`).
    func playing(atTimeMS ms: Int, framesInHand: MovieFramesInHand? = nil) -> Layer {
        guard let request = movieFrameRequest(atTimeMS: ms) else { return self }
        var shown = self
        shown.content = .image(request.movie.frameRef(atSourceMS: request.sourceMS,
                                                      holding: framesInHand))
        return shown
    }
}

// MARK: - A recording, opened as a document

extension PhotonzDocument {

    /// A recording opened as an ordinary document: one clip layer, the size of
    /// the picture, running the length of the file.
    ///
    /// This is the whole of "a recording opens the editor you already know".
    /// There is no video document type, no video window and no second model —
    /// what comes back is the same `PhotonzDocument` a screenshot opens as, and
    /// the only thing different about it is that something in it occupies time.
    public static func recording(_ movie: MovieRef, name: String,
                                 cutList: VideoCutList? = nil,
                                 pixelScale: CGFloat = 1) -> PhotonzDocument {
        var clip = Layer(name: name,
                         content: .image(movie.frameRef(atSourceMS: 0)),
                         frame: CGRect(origin: .zero, size: movie.pixelSize))
        clip.movie = movie
        clip.time = LayerTime(inMS: 0, outMS: max(LayerTime.shortestMS, movie.durationMS),
                              sourceInMS: 0, sourceLengthMS: movie.durationMS)
        // A recording already cut in the old window arrives as ONE clip with
        // its pieces on it, never as a row per cut (UX-PATTERNS D18 §3).
        if let cutList { clip.setClipPieces(ClipPieces(cutList: cutList)) }
        var doc = PhotonzDocument(canvasSize: movie.pixelSize, layers: [clip],
                                  pixelScale: pixelScale)
        doc.durationMS = clip.time?.outMS
        return doc
    }

    /// Every frame that has to be fetched before this moment can be drawn.
    ///
    /// Empty for every document anybody has today, which is what makes all of
    /// this free for a screenshot.
    public func movieFrames(atTimeMS ms: Int) -> [MovieFrameRequest] {
        guard hasTime else { return [] }
        let moment = min(max(0, ms), lastDrawableTimeMS)
        let own = allLayers.flatMap { $0.movieFrameRequests(atTimeMS: moment) }
        guard hasEditPointTransitions else { return own }
        return own + editPointFrameRequests(atMS: moment)
    }

    /// Whether anything in this document plays a recording.
    public var hasMovies: Bool { allLayers.contains(where: \.isClip) }
}
