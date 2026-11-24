import CoreGraphics
import Foundation

// A recording whose file was replaced on disk while a document holds it.
//
// The new file goes by a new id, so nothing kept for the old one can be shown
// for it, and a frame of the old file still being read lands where nobody
// looks. Here is the document's half: every place it points at the old
// recording points at the new one. It is run over the undo steps as well
// (`History.applyOutsideHistory`), because a file changing is not an edit and
// Command Z must not bring the old one back.

extension MovieRef {
    /// The same facts under an id nothing has been kept under.
    public func underNewID() -> MovieRef {
        MovieRef(pixelSize: pixelSize, durationMS: durationMS, hasSound: hasSound)
    }
}

extension PhotonzDocument {

    /// Point everything that is the recording `old` at `new`.
    ///
    /// A recording nobody has edited becomes the new file exactly as if it had
    /// just been opened, its length and canvas included. An edit keeps its
    /// cuts, its timing and its canvas: the new picture is fitted whole into
    /// the box the old one had, and a piece reading past the end of a shorter
    /// file holds its last frame.
    public mutating func replaceRecording(_ old: UUID, with new: MovieRef) {
        if let untouched = untouchedRecording, untouched.id == old {
            let fresh = PhotonzDocument.recording(new, name: layers[0].name, pixelScale: pixelScale)
            layers[0].movie = new
            layers[0].content = fresh.layers[0].content
            layers[0].frame = fresh.layers[0].frame
            layers[0].time = fresh.layers[0].time
            canvasSize = fresh.canvasSize
            durationMS = fresh.durationMS
        } else {
            layers.replaceRecording(old, with: new)
        }
        if !componentOriginals.isEmpty { componentOriginals.replaceRecording(old, with: new) }
        for index in media.indices where media[index].id == old {
            switch media[index].media {
            case .recording:
                media[index] = DocumentMediaSource(media: .recording(new), name: media[index].name)
            case .sound:
                media[index] = DocumentMediaSource(media: .sound(SoundRef(id: new.id, durationMS: new.durationMS)),
                                                   name: media[index].name)
            case .picture:
                break
            }
        }
    }
}

extension [Layer] {
    fileprivate mutating func replaceRecording(_ old: UUID, with new: MovieRef) {
        for index in indices {
            self[index].replaceRecording(old, with: new)
            if self[index].isGroup {
                var children = self[index].children
                children.replaceRecording(old, with: new)
                self[index].children = children
            }
        }
    }
}

extension Layer {
    fileprivate mutating func replaceRecording(_ old: UUID, with new: MovieRef) {
        if var inside = merged {
            inside.layers.replaceRecording(old, with: new)
            merged = inside
        }
        var plays = false
        if case .sound(let sound) = content, sound.id == old {
            content = .sound(SoundRef(id: new.id, durationMS: new.durationMS))
            plays = true
        }
        if let was = movie, was.id == old {
            movie = new
            if case .image(let ref) = content, let frame = was.frameIndex(ofFrameID: ref.id) {
                content = .image(new.frameRef(atFrame: Swift.min(frame, new.frameIndex(atSourceMS: new.durationMS))))
            }
            fit(from: was.pixelSize, to: new.pixelSize)
            plays = true
        }
        guard plays else { return }
        if let time, time.sourceLengthMS != nil {
            self.time = LayerTime(inMS: time.inMS, outMS: time.outMS,
                                  sourceInMS: time.sourceInMS, sourceLengthMS: new.durationMS)
        }
        if let cuts, cuts.sourceLengthMS != nil {
            self.cuts = ClipPieces(pieces: cuts.pieces, sourceLengthMS: new.durationMS)
        }
    }

    /// A picture of another shape goes whole into the box the old one had,
    /// centred, so it is never stretched.
    private mutating func fit(from old: CGSize, to new: CGSize) {
        guard old.width > 0, old.height > 0, new.width > 0, new.height > 0,
              abs(old.width / old.height - new.width / new.height) > 0.005 else { return }
        let scale = Swift.min(frame.width / new.width, frame.height / new.height)
        let size = CGSize(width: new.width * scale, height: new.height * scale)
        frame = CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                       width: size.width, height: size.height)
    }
}
