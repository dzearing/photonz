import Foundation

// The shape of a sound (`docs/design/video-audio.md`).
//
// A waveform is what lets a cut be aimed at a word or a beat rather than
// guessed at, and it obeys the same rule everything else in this module obeys:
// **it is not in the document.** The document holds a `SoundRef`; the peaks are
// read off the file by the app and kept beside it, exactly as an `ImageRef`'s
// pixels live in `ImageStore` rather than in a layer.
//
// What is here is the arithmetic a view cannot be trusted with: how a run of
// peaks becomes the columns a bar of a given width draws, and how the cuts a
// clip has been given move those columns around. Get that wrong and the picture
// of the sound stops being a picture of what plays, which is the one thing a
// waveform is for.

/// A sound reduced to how loud it is, moment by moment.
///
/// One number per `bucketMS` of the file, each the loudest thing inside that
/// bucket. The loudest rather than the average on purpose: a drum hit is two
/// milliseconds long and averaging it away is exactly what makes a waveform
/// useless for aiming at a beat.
public struct Waveform: Hashable, Codable, Sendable {

    /// How much of the file one peak covers.
    ///
    /// Twenty milliseconds is fifty numbers a second, which draws a legible
    /// shape at any width a timeline is ever going to be and keeps a quarter of
    /// an hour of sound under fifty thousand floats.
    public static let bucketMS = 20

    /// How loud the sound is in each bucket, nought to one.
    public let peaks: [Float]

    public init(peaks: [Float]) {
        self.peaks = peaks.map { $0.isFinite ? min(max(0, $0), 1) : 0 }
    }

    /// How long the sound this was read off runs for, to the nearest bucket.
    public var durationMS: Int { peaks.count * Self.bucketMS }

    public var isEmpty: Bool { peaks.isEmpty }

    /// How loud the file is at a moment of itself. Silence outside it, which is
    /// what a clip trimmed past the end of its own sound draws.
    public func peak(atSourceMS ms: Int) -> Float {
        guard ms >= 0 else { return 0 }
        let bucket = ms / Self.bucketMS
        guard bucket < peaks.count else { return 0 }
        return peaks[bucket]
    }

    /// The loudest the file gets anywhere in a stretch of itself.
    public func peak(fromSourceMS start: Int, toSourceMS end: Int) -> Float {
        let lo = max(0, min(start, end)) / Self.bucketMS
        // At least one bucket, so a stretch shorter than a bucket still reads
        // the bucket it lands in rather than nothing at all.
        let hi = max(lo, (max(0, max(start, end)) - 1) / Self.bucketMS)
        guard lo < peaks.count else { return 0 }
        var loudest: Float = 0
        for index in lo...min(hi, peaks.count - 1) where peaks[index] > loudest {
            loudest = peaks[index]
        }
        return loudest
    }

    // MARK: - Drawing it

    /// A stretch of the file as the columns a bar that wide draws.
    ///
    /// Each column says the loudest thing inside it rather than the average, so
    /// a bar squeezed down to forty pixels still shows where the hits are.
    public func columns(count: Int, fromSourceMS start: Int, toSourceMS end: Int) -> [Float] {
        guard count > 0 else { return [] }
        let length = max(0, end - start)
        return (0..<count).map { index in
            let from = start + length * index / count
            let to = start + length * (index + 1) / count
            return peak(fromSourceMS: from, toSourceMS: max(to, from + 1))
        }
    }

    /// The columns a CLIP draws: the same width of bar, but reading the file
    /// the way the clip's own pieces read it.
    ///
    /// This is what keeps the picture of the sound honest after a cut. A piece
    /// thrown away takes its columns with it, a piece moved takes them along,
    /// and a held frame draws flat because there is no sound under one frame.
    public func columns(count: Int, forPieces pieces: ClipPieces) -> [Float] {
        guard count > 0 else { return [] }
        let total = max(1, pieces.totalLengthMS)
        return (0..<count).map { index in
            let from = total * index / count
            let to = max(from + 1, total * (index + 1) / count)
            guard let pieceIndex = pieces.pieceIndex(atMS: from),
                  let piece = pieces.piece(at: pieceIndex), piece.playsSound,
                  let sourceFrom = pieces.sourceMS(atMS: from)
            else { return 0 }
            // The far edge of the column, clamped into the same piece so a
            // column straddling a cut reads the piece it started in rather
            // than a stretch of file that never plays.
            let pieceEnd = pieces.rangeMS(ofPiece: pieceIndex)?.end ?? to
            let sourceTo = pieces.sourceMS(atMS: min(to, max(from + 1, pieceEnd - 1))) ?? sourceFrom
            return peak(fromSourceMS: sourceFrom, toSourceMS: max(sourceTo, sourceFrom + 1))
        }
    }
}
