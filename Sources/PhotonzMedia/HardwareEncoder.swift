import AVFoundation
import Foundation
import VideoToolbox

/// Every MP4 the app encodes is written on the Mac's hardware H.264 encoder,
/// waiting for it when it is busy, rather than quietly on the software one.
///
/// **The hardware encoder takes 32 sessions at once, across the whole Mac.**
/// Measured 2026-11-09: one process holding 24 sessions left a second process
/// 8, and a session asked for past that is handed the software encoder with
/// no error and no sign. The software encoder does not keep to a budget
/// (`MovieCompression`: Small of a fast page at 19 times it), so a file
/// written then lands several times what the Export sheet said: a two second
/// Small document wrote 1,887,382 bytes against 234,015 on the hardware
/// encoder (`HardwareEncoderTests`). Inside the full test suite the parallel
/// video suites hold more than 32 sessions between them, which is why the
/// size checks in `BusyVideoSizeTests` failed there and nowhere else.
///
/// So a writer asks for the hardware encoder outright. When it is full,
/// `startWriting()` says so at once, before a single frame is drawn, and the
/// writer is made again a moment later. Only after `patience` with no session
/// coming free is it made without the requirement, so an export never fails
/// just because other apps are encoding; it lands heavier, as it always did.
enum HardwareEncoder {

    /// What a writer's video settings carry to ask for the hardware encoder.
    static var required: [String: Any] {
        [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true]
    }

    /// How long a writer waits for a hardware session before settling for
    /// the software encoder. Sessions are held for the length of an encode,
    /// which for anything the app writes is seconds.
    static let patience: Duration = .seconds(30)

    /// How often a waiting writer tries again.
    static let retryEvery: Duration = .milliseconds(200)

    /// Whether a writer that would not start was told the hardware encoder is
    /// taken (`kVTInvalidSessionErr`, the error a full encoder gives, or
    /// `kVTVideoEncoderNotAvailableNowErr`), anywhere down its underlying
    /// errors.
    static func isBusy(_ error: Error?) -> Bool {
        var next = error.map { $0 as NSError }
        while let error = next {
            if error.domain == NSOSStatusErrorDomain,
               error.code == Int(kVTInvalidSessionErr)
                || error.code == Int(kVTVideoEncoderNotAvailableNowErr) {
                return true
            }
            next = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    /// A writer made by `make` and started, on the hardware encoder when one
    /// comes free within `patience`. `make` is handed whether to ask for the
    /// hardware, puts that into its video input's settings
    /// (`AVVideoEncoderSpecificationKey`), and returns what it made with the
    /// writer first. Anything at `destination` is cleared before each try,
    /// since a writer will not start over a file. A writer that will not
    /// start for any other reason throws what `wouldNotStart` makes of the
    /// writer's own error, so each caller keeps the error it always threw.
    static func start<Made>(at destination: URL,
                            patience: Duration = HardwareEncoder.patience,
                            wouldNotStart: (Error?) -> Error,
                            make: (_ hardware: Bool) throws -> (AVAssetWriter, Made))
        async throws -> (AVAssetWriter, Made) {
        let clock = ContinuousClock()
        let giveUp = clock.now.advanced(by: patience)
        while true {
            try? FileManager.default.removeItem(at: destination)
            let made = try make(true)
            if made.0.startWriting() { return made }
            guard isBusy(made.0.error) else { throw wouldNotStart(made.0.error) }
            guard clock.now < giveUp else { break }
            try await Task.sleep(for: retryEvery)
        }
        try? FileManager.default.removeItem(at: destination)
        let made = try make(false)
        guard made.0.startWriting() else { throw wouldNotStart(made.0.error) }
        return made
    }
}
