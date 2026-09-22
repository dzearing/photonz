import CoreGraphics
import Foundation

/// Which files are sound and which are recordings, as a drop reads them.
///
/// Read off the name rather than the contents, because this is asked on every
/// mouse move while something is in the air. Whether the file really holds a
/// playable sound is settled when it lands, which is the only moment it can be
/// settled honestly.
public enum MediaFiles {

    /// The sound files the app will take. The same family Add Sound offers
    /// (`SoundLibrary.openableTypes`), written as extensions so a drag can ask
    /// without touching the disk.
    public static let soundExtensions: Set<String> =
        ["m4a", "mp3", "wav", "aiff", "aif", "caf", "aac", "flac", "mp2", "au"]

    /// What kind of media this file is, or nil when it is neither: a picture, a
    /// Photonz document and a text file all come back nil, and are answered for
    /// where they always were.
    public static func kind(of url: URL) -> MediaDrop.Kind? {
        let ext = url.pathExtension.lowercased()
        if RecordingFiles.isRecording(url) { return .recording }
        if soundExtensions.contains(ext) { return .sound }
        return nil
    }
}

/// What letting go of a sound or a recording over an open document would do,
/// and the one line the canvas says about it while it is still in the air.
///
/// Dragging a picture in has always drawn the box it would fill, so the drag
/// answers before the button comes up. A sound draws nothing on the canvas and
/// a clip arriving at the playhead is not where your eye is, so the answer for
/// both is a sentence instead of a box — the same shape a saved text style
/// already uses (`TextStyleDrop`).
///
/// Every case says something. A drop that will be taken says where it is going;
/// a drop that cannot be taken says why and names the one move that works. A
/// refusal that goes quiet is the thing this exists to stop
/// (`UX-PATTERNS.md` §refusals).
public enum MediaDrop {

    /// The two kinds of file this is about.
    public enum Kind: Equatable, Sendable {
        case sound
        case recording
    }

    /// Where the file ends up.
    public enum Landing: Equatable, Sendable {
        /// On the timeline, as a piece of sound, exactly as Add Sound puts one
        /// there.
        case soundLayer
        /// On the timeline, as a clip, over whatever is under it.
        case clipLayer
        /// In a window of its own. A recording IS a document, so a recording
        /// let go on a picture opens rather than landing there, which is what
        /// a `.photonz` dropped on a canvas has always done.
        case openDocument
        /// Nothing lands. `note` says why and what to do instead.
        case refused
    }

    public struct Answer: Equatable, Sendable {
        public var landing: Landing
        /// The one line the canvas draws under the pointer. Never empty.
        public var note: String

        public init(landing: Landing, note: String) {
            self.landing = landing
            self.note = note
        }

        /// Whether the pointer promises anything. The no-entry sign is shown
        /// when this is false, and the sentence is shown either way.
        public var lands: Bool { landing != .refused }
    }

    /// What this drop would do.
    ///
    /// - Parameters:
    ///   - kind: sound or recording.
    ///   - name: the file's own name, extension and all. What the sentence says
    ///     is the name without it, because that is what the layer will be
    ///     called and what the person picked.
    ///   - documentHasTime: whether the open document runs in time
    ///     (`PhotonzDocument.hasTime`). This is the whole of the decision: a
    ///     sound needs a timeline to sit on and a picture has none.
    ///   - atMS: where the playhead is, which is where a drop on the canvas
    ///     lands in time.
    ///   - hasDocument: whether this window holds anything at all.
    public static func answer(for kind: Kind, named name: String,
                              documentHasTime: Bool, atMS: Int,
                              hasDocument: Bool = true) -> Answer {
        let title = (name as NSString).deletingPathExtension
        let moment = CaptionProgress.clock(max(0, atMS))
        switch kind {
        case .recording:
            // A recording is a document. Into one that already runs in time it
            // joins as a clip; anywhere else it opens, the way any other
            // document dropped on a window does.
            guard documentHasTime, hasDocument else {
                return Answer(landing: .openDocument, note: "\(title) opens in its own window")
            }
            return Answer(landing: .clipLayer, note: "\(title) lands as a clip at \(moment)")
        case .sound:
            guard documentHasTime, hasDocument else {
                // The refusal names the file, says the reason in words anybody
                // can act on, and gives the one move that works. There is no
                // way to put time into a picture today, so "open a recording"
                // is not a shrug: it is the whole answer.
                return Answer(landing: .refused,
                              note: "No timeline here for \(title). Open a recording first")
            }
            return Answer(landing: .soundLayer,
                          note: "\(title) lands on the timeline at \(moment)")
        }
    }
}

// MARK: - A second recording, put into a document that already runs in time

extension PhotonzDocument {

    /// Put a clip on the timeline at a moment, in a box on the canvas, and
    /// stretch the document to hold it where it runs past the end.
    ///
    /// The mirror of `addSound`, and deliberately the same shape: a clip is a
    /// layer with an in and an out, so everything the timeline already does to
    /// a layer — cutting it, sliding it, naming it, switching it off, undoing
    /// any of it — works on this the moment it arrives, with nothing built for
    /// it.
    ///
    /// It lands on TOP, because something you have just brought in that you
    /// cannot see is indistinguishable from a drop that did nothing.
    @discardableResult
    public mutating func addClip(_ movie: MovieRef, name: String, atMS ms: Int,
                                 frame: CGRect) -> UUID {
        let start = max(0, ms)
        let time = LayerTime(inMS: start,
                             outMS: start + max(LayerTime.shortestMS, movie.durationMS),
                             sourceInMS: 0, sourceLengthMS: movie.durationMS)
        var layer = Layer(name: name, content: .image(movie.frameRef(atSourceMS: 0)), frame: frame)
        layer.movie = movie
        layer.time = time
        let id = layer.id
        addLayer(layer)
        // A document that knows how long it is has to grow, or the clip would
        // run past its own last frame and never be seen.
        if let written = durationMS, written < time.outMS { durationMS = time.outMS }
        return id
    }
}

/// The two files a walk can ask for that are not files on disk until somebody
/// asks: the tutorial's own sample recording and its sample music, written on
/// demand.
///
/// A walk names one in its `scratch` list and gets a copy in its own folder
/// under the file's real name, so nothing about a walk depends on some earlier
/// walk having made it. Here rather than in the app because the guard test that
/// checks every walk's setup reads it too, and the name a walk writes and the
/// name the copy lands under must be one fact.
public enum PlaytestSampleFile: String, CaseIterable, Sendable {
    case recording = "sample:recording"
    case music = "sample:music"

    /// What the copy is called once it is in the walk's folder, which is what a
    /// step names after `scratch/`.
    public var fileName: String {
        switch self {
        case .recording: return "Tutorial Sample.mp4"
        case .music: return "Sample Music.m4a"
        }
    }

    public static func named(_ name: String) -> PlaytestSampleFile? {
        PlaytestSampleFile(rawValue: name)
    }
}
