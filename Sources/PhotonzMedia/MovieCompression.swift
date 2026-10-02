import AVFoundation
import Foundation
import VideoToolbox

/// What the H.264 encoder is asked for when an MP4 is written with a budget,
/// shared by the recording's export (`VideoExporter`) and the document's
/// (`DocumentMovieWriter`) so the two cannot drift apart.
///
/// **An average bit rate is a target, not a limit.** On a page of fine text
/// scrolling past the system's encoder overshot it: Small of a three second
/// 1280 x 800 page at 900 pixels a second came to 830,895 bytes against
/// 324,000. Measured 2026-09-28 on a quiet machine, against the same source:
///
/// | Asked for                         | 300 px/s High/Std/Small | 900 px/s |
/// | --------------------------------- | ----------------------- | -------- |
/// | average only                      | 1.13 / 1.20 / 1.70      | 1.25 / 1.68 / 2.56 |
/// | constant bit rate                 | 1.16 / 1.21 / 1.53      | 1.30 / 1.44 / 1.84 |
/// | a cap of 1.3x the budget a second | 0.92 / 0.92 / 0.96      | 0.95 / 1.28 / 1.64 |
///
/// **So a picture that would overshoot is held by the cap, and only that
/// one.** Any cap changes how the encoder spends everywhere, not just where it
/// would go over: a five minute talk at 1080p, a twentieth of its budget, came
/// out 43 per cent smaller under a cap of twice its budget a second, and larger
/// under ten times (`VideoExportSample.holdsToBudget`). Each write therefore
/// weighs its stretches unheld first and holds only a picture that would land
/// over its budget.
///
/// What the cap cannot fix is the encoder's own floor: nothing it was asked
/// for, constant bit rate at a tenth of the budget included, got Small of the
/// fast page under 1.3 times its budget. The sheet says what that lands at
/// rather than quoting the budget (`VideoExportSample`).
///
/// Also tried and turned down: a longer key frame interval (helps at 300 px/s,
/// worse at 900, and slows scrubbing), frame reordering off (larger at every
/// choice), a maximum quantiser of 51 (no change), and the software encoder,
/// which ignores the budget altogether and wrote Small of the fast page at 19
/// times it.
enum MovieCompression {

    /// How far over its budget one second of a held file may go. A little
    /// headroom, so a scene change still gets the bits for a sharp key frame
    /// and the file lands just under the number rather than well under it.
    static let secondCeiling = 1.3

    /// The compression properties for a stream of `bitsPerSecond` at `fps`,
    /// held to that budget when `holdsToBudget`.
    static func properties(bitsPerSecond: Int, fps: Double,
                           holdsToBudget: Bool) -> [String: Any] {
        var properties: [String: Any] = [
            AVVideoAverageBitRateKey: bitsPerSecond,
            AVVideoExpectedSourceFrameRateKey: Int(fps.rounded()),
            // A key frame every two seconds, so scrubbing and the preview a
            // chat app builds both land quickly. The sheet's weigh writes
            // two second stretches for the same reason (`VideoExportSample`).
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            // Frame reordering stays ON, and it was worth measuring rather
            // than assuming. Turning it off makes a short export reproducible
            // to the byte, which the Export sheet would like to be able to
            // promise; it also more than DOUBLED the file on a three second
            // clip with real movement in it, 130,349 bytes to 278,280.
            // Doubling the file to buy reproducibility is exactly the wrong
            // trade for a feature whose whole point is a file small enough to
            // send, and it did not even buy it on a longer clip. So: smallest
            // file, and the sheet says "about".
            AVVideoAllowFrameReorderingKey: true,
        ]
        if holdsToBudget {
            // Bytes, then seconds: no second of the file spends more than
            // `secondCeiling` of a second's budget.
            properties[kVTCompressionPropertyKey_DataRateLimits as String] = [
                Double(bitsPerSecond) / 8 * secondCeiling, 1.0,
            ]
        }
        return properties
    }

    /// What the pictures of a written file weigh from `fromMS` on, read off
    /// the size of each compressed frame without decoding any of them. From
    /// the start it is the whole file, container and all, since that is what
    /// lands. The sheet's weigh uses this to leave the encoder's warm-up out
    /// (`VideoExportSample.writingOrder`).
    static func pictureBytes(of url: URL, fromMS: Int) async -> Int {
        guard fromMS > 0 else {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return 0 }
        // The read blocks, so it never holds a thread of the shared pool
        // (`GuardedReads` says what that cost an export).
        let handed = HandedTrack(track: track, asset: asset)
        return await OffThePool.run { pictureBytes(of: handed, from: Double(fromMS) / 1000) }
    }

    private static func pictureBytes(of handed: HandedTrack, from: Double) -> Int {
        guard let reader = try? AVAssetReader(asset: handed.asset) else { return 0 }
        let output = AVAssetReaderTrackOutput(track: handed.track, outputSettings: nil)
        guard reader.canAdd(output) else { return 0 }
        reader.add(output)
        guard reader.startReading() else { return 0 }
        var bytes = 0
        while let sample = output.copyNextSampleBuffer() {
            let at = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard at.isFinite, at >= from - 0.001 else { continue }
            bytes += CMSampleBufferGetTotalSampleSize(sample)
        }
        return bytes
    }
}
