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

    public init(id: UUID = UUID(), durationMS: Int) {
        self.id = id
        self.durationMS = max(0, durationMS)
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
    public var hasAudio: Bool { allLayers.contains { $0.sound != nil } }

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
        let soundLayerID = layer.id

        var after = self
        after.updateLayer(id: id) { $0.soundDetached = true }
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
