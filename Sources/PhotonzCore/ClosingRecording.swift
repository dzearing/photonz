import CoreGraphics
import Foundation

// A recording you can open the moment you press Stop.
//
// macOS takes a while to close a recording's file: about 4 ms for every second
// recorded with sound, so most of a second for three minutes. Nothing the
// person does next should wait on that. The stream's last frame is already in
// memory when Stop is pressed, so the recording opens at once on that frame,
// with a stand-in for the file that knows the picture's size and roughly how
// long it runs. When the file lands its real facts are taken on under the SAME
// identity: every frame filed for the stand-in is a frame of the real thing,
// so the picture on screen keeps drawing until the file's own frames are read,
// and anything done in the meantime is still there.

/// What is known about a recording whose file is still being closed.
public struct ClosingRecording: Hashable, Sendable {
    /// The picture's size in pixels, as the stream delivered it.
    public let pixelSize: CGSize
    /// The moment of the file the last frame the stream delivered sits at:
    /// that frame's time less the first frame's, which is where the file
    /// starts.
    public let lastFrameMS: Int
    /// The moment of the file Stop was pressed at. A screen that stopped
    /// changing sends no more frames, so this can be well past the last one,
    /// and the file runs to it all the same.
    public let stoppedMS: Int
    /// Whether the recording was made with sound.
    public let hasSound: Bool

    public init(pixelSize: CGSize, lastFrameMS: Int, stoppedMS: Int, hasSound: Bool) {
        self.pixelSize = pixelSize
        self.lastFrameMS = max(0, lastFrameMS)
        self.stoppedMS = max(0, stoppedMS)
        self.hasSound = hasSound
    }

    /// A reference standing in for the file until it lands: the picture's own
    /// size, running to Stop, and at least one frame past the last frame.
    public func standIn(id: UUID = UUID()) -> MovieRef {
        MovieRef(id: id, pixelSize: pixelSize, durationMS: durationMS, hasSound: hasSound)
    }

    /// How long the stand-in runs.
    public var durationMS: Int { max(lastFrameMS + MovieRef.frameStepMS, stoppedMS) }

    /// Where the playhead waits while the file lands: its last moment. The
    /// picture there is the last frame, because nothing on screen changed
    /// after it.
    public var waitingMS: Int { durationMS - 1 }
}

extension PhotonzDocument {

    /// The file a stand-in was holding the place of has landed: every clip of
    /// it, and its tile on the shelf, take on the file's real length and size.
    ///
    /// A clip that played the whole stand-in plays the whole file; one trimmed
    /// in the meantime keeps its stretch and only learns how much file lies
    /// either side of it. A canvas the size of the stand-in's picture follows
    /// the file's, and so does a document length that ended with the clip.
    /// Everything else, a title put on meanwhile included, is left as it is.
    public mutating func adoptLandedRecording(_ landed: MovieRef) {
        var standIn: MovieRef?
        var endedWith: Int?
        var endsAt: Int?
        func adopt(_ layer: inout Layer) {
            guard let old = layer.movie, old.id == landed.id else { return }
            standIn = old
            layer.movie = landed
            if case .image(let ref) = layer.content, old.frameIndex(ofFrameID: ref.id) != nil {
                layer.content = .image(ImageRef(id: ref.id, pixelSize: landed.pixelSize))
            }
            if layer.frame.size == old.pixelSize {
                layer.frame.size = landed.pixelSize
            }
            guard let time = layer.time else { return }
            let wholeFile = time.sourceInMS == 0 && time.lengthMS == max(LayerTime.shortestMS, old.durationMS)
            let next = wholeFile
                ? LayerTime(inMS: time.inMS, outMS: time.inMS + landed.durationMS,
                            sourceInMS: 0, sourceLengthMS: landed.durationMS)
                : LayerTime(inMS: time.inMS, outMS: time.outMS,
                            sourceInMS: time.sourceInMS, sourceLengthMS: landed.durationMS)
            if wholeFile {
                endedWith = time.outMS
                endsAt = next.outMS
            }
            layer.time = next
        }
        func walk(_ list: inout [Layer]) {
            for index in list.indices {
                adopt(&list[index])
                if list[index].isGroup {
                    var children = list[index].children
                    walk(&children)
                    list[index].children = children
                }
            }
        }
        walk(&layers)
        for index in media.indices {
            guard case .recording(let movie) = media[index].media, movie.id == landed.id else { continue }
            standIn = standIn ?? movie
            media[index] = DocumentMediaSource(media: .recording(landed), name: media[index].name)
        }
        guard let standIn else { return }
        if canvasSize == standIn.pixelSize { canvasSize = landed.pixelSize }
        if let endedWith, let endsAt, durationMS == endedWith { durationMS = endsAt }
    }
}
