import CoreGraphics
import Foundation

// Sound, as a layer (`docs/design/video-audio.md`).
//
// The thesis every video clickthrough repeats is that video is not a mode, it
// is the layer document with time in it. Sound is the same sentence one step
// further: **a piece of sound is a layer that occupies time and happens to draw
// nothing.** It has an in and an out, it is cut into pieces, it is named,
// switched off, reordered and undone by exactly the machinery a picture is, so
// a mixer is not a separate app and there is no second model to keep in step.
//
// Three things are added here and nothing else:
//
// - `SoundRef` — which file and how long, in the same bargain `MovieRef` and
//   `ImageRef` already strike. **No samples and no path, ever.**
// - `LayerContent.sound` — a layer that is only sound. The renderer is told
//   about it once, where it draws nothing, and every other switch in the app
//   is made to say what it means by it because the compiler asks.
// - Taking a recording's sound off its picture, and putting somebody else's
//   sound on the timeline.
//
// A CLIP does not carry a `SoundRef` of its own. Its sound IS its recording's,
// because it is the same file, so there is one identity rather than two that
// could drift. Taking the sound off is a flag on the clip and a new layer
// beside it, which is why it undoes for nothing.

/// The sound a layer plays: which file, and how long it runs for.
///
/// The id is the sound's identity inside the running app, exactly as an
/// `ImageRef`'s is: where the file lives is the app's business. A recording's
/// sound shares the recording's own id, because a recording is one file with a
/// picture in it and a sound in it.
public struct SoundRef: Hashable, Codable, Sendable {

    public let id: UUID
    /// How long the file runs for. The whole file, not the part a layer keeps:
    /// a trim moves the layer's in and out and never shortens this, which is
    /// what lets the timeline draw what a trim put out of play.
    public let durationMS: Int
    /// Set only on a cleaned copy of a sound, which the mix plays in place of
    /// the file when its segment is cleaned (`NoiseCleaning.swift`). Never in
    /// a document: a layer holds the file, and says how hard to clean it.
    public let cleaning: SoundCleaning?

    public init(id: UUID = UUID(), durationMS: Int, cleaning: SoundCleaning? = nil) {
        self.id = id
        self.durationMS = max(0, durationMS)
        self.cleaning = cleaning
    }
}

// MARK: - A recording's own sound

extension MovieRef {

    /// This recording's sound, where it has one.
    ///
    /// The same id as the picture, because it is the same file. That is what
    /// makes taking the sound off a recording cost nothing: the new layer
    /// points at a file the app has already opened.
    public var soundRef: SoundRef? {
        hasSound ? SoundRef(id: id, durationMS: durationMS) : nil
    }
}

// MARK: - What a layer says about its sound

extension Layer {

    /// The sound this layer plays, or nil for one that makes none.
    ///
    /// Two layers answer this: a clip that still has its recording's sound on
    /// it, and a layer that is nothing but sound. Everything else in every
    /// document ever written answers nil.
    public var sound: SoundRef? {
        if case .sound(let ref) = content { return ref }
        guard soundDetached != true else { return nil }
        return movie?.soundRef
    }

    /// Whether this layer is sound and nothing else: no picture, no shape, no
    /// words, nothing on the canvas to grab.
    public var isSoundOnly: Bool {
        if case .sound = content { return true }
        return false
    }

    /// Set how loud this layer plays.
    ///
    /// A level nobody has touched is put back to nothing at all rather than
    /// written down as "the ordinary one", so a document that was never mixed
    /// reads back byte for byte the same as one saved before sound existed.
    public mutating func setSoundLevel(_ level: AudioLevel) {
        soundLevel = level.isUntouched ? nil : level
    }

    /// Whether this layer makes a sound at all at the level it is set to.
    public var isAudible: Bool {
        sound != nil && isVisible && (soundLevel ?? AudioLevel()).isSilent == false
    }
}

// MARK: - Sound in the document

extension PhotonzDocument {

    /// Whether anything in this document makes a sound.
    public var hasAudio: Bool { layers.contains { $0.containsSelfOrDescendant { $0.sound != nil } } }

    /// Whether this layer's sound can be taken off its picture: it is a clip,
    /// its recording has a sound track, and nobody has taken it off already.
    public func canDetachSound(ofLayer id: UUID) -> Bool {
        guard let layer = layer(id: id), layer.isClip, layer.soundDetached != true else { return false }
        return layer.movie?.soundRef != nil
    }

    /// The document with this clip's sound taken off it and laid on its own
    /// layer just above, plus which layer that is.
    ///
    /// **The sound lands in step with the picture**: the same in, the same out,
    /// and the same cuts the picture already had. From that moment on they are
    /// two ordinary layers, so cutting one leaves the other exactly where it
    /// was, which is the whole case the cut clickthrough is built around.
    ///
    /// Nil where there is nothing to take off. Nothing is copied and nothing is
    /// decoded: both layers point at the one file.
    public func detachingSound(ofLayer id: UUID) -> SoundDetachment? {
        guard canDetachSound(ofLayer: id), let clip = layer(id: id),
              let sound = clip.movie?.soundRef, let time = clip.time,
              let path = path(of: id)
        else { return nil }

        var layer = Layer.sound(sound, name: "\(clip.name) sound", time: time)
        layer.cuts = clip.cuts
        // Everything already done to the sound goes with it: level, fades,
        // gain, cleaning and effects. Its points are measured from the layer's
        // own start, and the new layer starts where the clip does, so they
        // land on the same moments.
        layer.soundLevel = clip.soundLevel
        let soundLayerID = layer.id

        var after = self
        // It lands on the very audio track its linked segment was drawn on,
        // so the only thing that changes on the timeline is the link. That
        // track is written down first, or it would go with the link.
        if let track = linkedSoundTrackID(ofClip: id) {
            after.materializeTracks()
            layer.trackID = track
        }
        // The silent picture lets go of the level, so the mix lives in one
        // place, on the layer that plays it.
        after.updateLayer(id: id) {
            $0.soundDetached = true
            $0.soundLevel = nil
        }
        if path.count == 1 {
            after.addLayer(layer, at: path[0] + 1)
        } else if let parent = after.layer(atPath: Array(path.dropLast()))?.id {
            after.addLayer(layer, toGroup: parent, at: path[path.count - 1] + 1)
        } else {
            after.addLayer(layer)
        }
        // `addLayer` may number the name to keep it unique, which never changes
        // the id it was made with.
        return SoundDetachment(document: after, soundLayerID: soundLayerID, sound: sound)
    }

    // MARK: Putting it back

    /// Whether Re-attach Audio would do anything for this layer: it is a
    /// picture whose recording's sound was taken off, or the loose sound of a
    /// picture like that.
    public func canReattachSound(ofLayer id: UUID) -> Bool {
        reattachPair(ofLayer: id) != nil
    }

    /// The document with a detached sound put back into its picture: the
    /// loose sound layer goes, and the picture speaks for its recording again,
    /// linked to it on the audio track the loose sound was sitting on.
    ///
    /// **It comes back in step.** A linked sound is the picture's own time and
    /// cuts drawn a second time, so however far the loose sound was slid,
    /// trimmed or cut, what plays is the picture's stretch of the recording.
    /// Volume, gain, cleaning and effects come back with it; a level line
    /// (points and fades) comes back only when the sound was still in step,
    /// since one drawn on a different stretch would land on the wrong words.
    ///
    /// Nil where there is nothing to put back.
    public func reattachingSound(ofLayer id: UUID) -> SoundReattachment? {
        guard let (pictureID, soundID) = reattachPair(ofLayer: id),
              let picture = layer(id: pictureID) else { return nil }
        let loose = soundID.flatMap { layer(id: $0) }
        var after = self
        var track: UUID?
        if let soundID {
            after.materializeTracks()
            track = after.layer(id: soundID)?.trackID
        }
        let inStep = loose.map { $0.time == picture.time && $0.cuts == picture.cuts } ?? false
        var level = loose?.soundLevel
        if !inStep { level?.clearPoints() }
        after.updateLayer(id: pictureID) {
            $0.soundDetached = nil
            $0.setSoundLevel(level ?? AudioLevel())
            if let track { $0.soundTrackID = track }
        }
        if let soundID { after.removeLayers(ids: [soundID]) }
        return SoundReattachment(document: after, pictureID: pictureID, soundLayerID: soundID)
    }

    /// The picture and the loose sound Re-attach would join, from either one.
    ///
    /// The document does not write down which sound came off which picture,
    /// so the pair is the one reading the most of the same stretch of the same
    /// recording: with a recording laid down twice and both detached, each
    /// picture takes back the sound of its own stretch. A picture whose loose
    /// sound was deleted pairs with nothing and simply gets its sound back.
    func reattachPair(ofLayer id: UUID) -> (picture: UUID, sound: UUID?)? {
        guard let layer = layer(id: id) else { return nil }
        func isSilencedPicture(_ layer: Layer) -> Bool {
            layer.isClip && layer.merged == nil && layer.soundDetached == true && layer.movie?.soundRef != nil
        }
        func score(_ a: Layer, _ b: Layer) -> (Int, Int, Int) {
            guard let ta = a.time, let tb = b.time else { return (0, 0, Int.min) }
            func overlap(_ x: Range<Int>, _ y: Range<Int>) -> Int {
                max(0, min(x.upperBound, y.upperBound) - max(x.lowerBound, y.lowerBound))
            }
            let source = overlap(ta.sourceInMS..<(ta.sourceInMS + ta.lengthMS),
                                 tb.sourceInMS..<(tb.sourceInMS + tb.lengthMS))
            let placed = overlap(ta.inMS..<ta.outMS, tb.inMS..<tb.outMS)
            return (source, placed, -abs(ta.inMS - tb.inMS))
        }
        let everything = allLayers
        if isSilencedPicture(layer), let recording = layer.movie?.id {
            let sounds = everything.filter { $0.isSoundOnly && $0.sound?.id == recording }
            let best = sounds.max { score(layer, $0) < score(layer, $1) }
            return (layer.id, best?.id)
        }
        if layer.isSoundOnly, let recording = layer.sound?.id {
            let pictures = everything.filter { isSilencedPicture($0) && $0.movie?.id == recording }
            guard let best = pictures.max(by: { score(layer, $0) < score(layer, $1) }) else { return nil }
            return (best.id, layer.id)
        }
        return nil
    }

    /// Put a piece of sound on the timeline at a moment, and stretch the
    /// document to hold it where it runs past the end.
    ///
    /// The one way sound arrives from outside a recording. It lands as a layer
    /// like anything else, which is what makes it immediately cuttable,
    /// movable, nameable and undoable with nothing new built for it.
    @discardableResult
    public mutating func addSound(_ sound: SoundRef, name: String, atMS ms: Int) -> UUID {
        let start = max(0, ms)
        let time = LayerTime(inMS: start, outMS: start + max(LayerTime.shortestMS, sound.durationMS),
                             sourceInMS: 0, sourceLengthMS: sound.durationMS)
        let layer = Layer.sound(sound, name: name, time: time)
        let id = layer.id
        addLayer(layer)
        // A document that already knows how long it is has to grow, or the
        // sound would run past its own last frame and never be heard.
        if let written = durationMS, written < time.outMS { durationMS = time.outMS }
        return id
    }
}

/// A clip's sound, taken off its picture.
public struct SoundDetachment: Sendable {
    public let document: PhotonzDocument
    /// The layer the sound landed on.
    public let soundLayerID: UUID
    /// The file it plays, so the app can file it where it files the rest.
    public let sound: SoundRef

    public init(document: PhotonzDocument, soundLayerID: UUID, sound: SoundRef) {
        self.document = document
        self.soundLayerID = soundLayerID
        self.sound = sound
    }
}

/// A detached sound, put back into its picture.
public struct SoundReattachment: Sendable {
    public let document: PhotonzDocument
    /// The picture that speaks for its recording again.
    public let pictureID: UUID
    /// The loose sound layer that went, or nil where there was none left.
    public let soundLayerID: UUID?

    public init(document: PhotonzDocument, pictureID: UUID, soundLayerID: UUID?) {
        self.document = document
        self.pictureID = pictureID
        self.soundLayerID = soundLayerID
    }
}

// MARK: - Making one

extension Layer {

    /// A layer that is nothing but sound.
    ///
    /// Its frame is empty on purpose: there is nothing to draw and nothing to
    /// take hold of on the canvas, so it is reached through the layers list and
    /// its bar on the timeline, which is where a piece of sound belongs.
    public static func sound(_ ref: SoundRef, name: String, time: LayerTime) -> Layer {
        var layer = Layer(name: name, content: .sound(ref), frame: .zero)
        layer.time = time
        return layer
    }
}
