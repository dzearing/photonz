import Foundation
import PhotonzCore
import SwiftUI

/// Weighing a GIF or a HEIC, which means writing one.
///
/// **Why there is no cheaper way.** A video's size is arithmetic: the export
/// asks the encoder for a number of bits per second, so the file is that number
/// times the length (`VideoExportRecipe`). An animated picture has no such
/// number, and no formula survived being measured against real files. Sampling
/// eight frames from across a recording, encoding those and multiplying came
/// out between 100 and 400 per cent over, because ImageIO spends a fraction as
/// much on a frame that follows a frame like it, and frames sampled from far
/// apart are all unlike their neighbours. Taking runs of consecutive frames
/// instead swung from 76 per cent under to 120 per cent over depending on the
/// material. A number that wrong is worse than the sentence it replaced.
///
/// So this writes the file, into a scratch copy, while the sheet is open. Two
/// things make that pay rather than cost:
///
/// - **The answer is exact.** An animated export written twice lands at the
///   same size (`AnimatedExportWeighTests`), so the number is what arrives
///   rather than an estimate, and the line drops the word "about".
/// - **The work is not thrown away.** Pressing Export hands the scratch file
///   straight to the save box, so a GIF somebody waited to see the size of is
///   saved instantly. It is the same bargain the one-frame picture already
///   makes on this sheet: the bytes that were weighed are the bytes that get
///   saved.
///
/// **Nothing runs when nobody is looking.** The write starts when a sheet shows
/// an animated format, restarts when the format or the preset changes, and is
/// cancelled with its scratch file when the sheet goes away. So the cost is
/// bounded by how long somebody leaves the sheet open, and the line says how
/// far along it is the whole time, which is what keeps a long recording from
/// looking stuck.
@MainActor
@Observable
final class ExportWeigh {

    /// The weigh the sheet on screen is running, so a scripted walk can wait
    /// for the number rather than guess at a delay.
    static weak var onScreen: ExportWeigh?

    /// How far the writing has got, and what it weighed once it finished. Nil
    /// when nothing is being weighed: a video, one frame as a picture, or a
    /// write that failed.
    private(set) var result: RecordingExport.Weighing?

    /// Where the scratch copy is being written, while this weigh owns it.
    private var scratch: URL?
    private var job: Task<Void, Never>?

    /// What a weigh does: write the file the sheet is describing to `url`,
    /// reporting how far along it is. The sheet supplies it, because only the
    /// sheet knows whether it is writing a recording or a document.
    typealias Write = @MainActor (URL, @escaping @Sendable (Double) -> Void) async throws -> Void

    /// Start weighing this format at this preset, stopping whatever was being
    /// weighed before.
    ///
    /// Restarting rather than keeping the old answer is the point: the number
    /// on the sheet belongs to the choice showing on the sheet, and a High
    /// number left sitting under Small would be a lie told by omission.
    func weigh(format: RecordingFormat, quality: VideoExportQuality, write: @escaping Write) {
        stop()
        Self.onScreen = self
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-weigh-\(UUID().uuidString).\(format.fileExtension)")
        scratch = file
        result = RecordingExport.Weighing(format: format, quality: quality, fraction: 0)
        job = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await write(file) { done in
                    Task { @MainActor [weak self] in
                        self?.reached(done, format: format, quality: quality)
                    }
                }
            } catch {
                // Stopped on purpose, or it could not be written at all. Either
                // way there is no number to show: the line goes back to saying
                // the size comes with the file, which is what it said before
                // any of this existed.
                if !Task.isCancelled { forget() }
                return
            }
            guard !Task.isCancelled else { return }
            let landed = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            result = RecordingExport.Weighing(format: format, quality: quality,
                                              fraction: 1, bytes: landed)
            job = nil
        }
    }

    /// Stop weighing and take the scratch file with it, so a sheet somebody
    /// closed leaves nothing behind on the disk.
    ///
    /// The file is removed only once the writer has really stopped: deleted out
    /// from under a half-finished write, it would be written back a moment
    /// later and left there for good.
    func stop() {
        if Self.onScreen === self { Self.onScreen = nil }
        result = nil
        let file = scratch
        scratch = nil
        guard let running = job else {
            if let file { try? FileManager.default.removeItem(at: file) }
            return
        }
        job = nil
        running.cancel()
        Task {
            _ = await running.value
            if let file { try? FileManager.default.removeItem(at: file) }
        }
    }

    /// Hand the weighed file over to an export, when the finished one answers
    /// exactly what is being exported. The weigh no longer owns it, so closing
    /// the sheet cannot delete it out from under the save.
    ///
    /// Nil for a weigh still running: what has been written so far is a piece
    /// of a GIF, not a small one.
    func take(format: RecordingFormat, quality: VideoExportQuality) -> URL? {
        guard let result, result.answers(format: format, quality: quality),
              let bytes = result.bytes, bytes > 0, let file = scratch,
              FileManager.default.fileExists(atPath: file.path) else { return nil }
        scratch = nil
        self.result = nil
        return file
    }

    /// Whether the number on the sheet is settled: something was weighed and
    /// the answer is in. What a walk waits on.
    var isSettled: Bool { result?.bytes != nil }

    /// How far the writer has got, ignored once the answer is in or once the
    /// sheet has moved on to a different choice.
    ///
    /// **Only when the whole percentage changes.** The writer reports every
    /// frame it lays down, which on a GIF is fifty times a second, and every
    /// one of those redraws a sheet whose line is written in whole per cent.
    /// Forty-nine of every fifty redraws show exactly what was already there,
    /// and they cost real milliseconds on the main thread of a window somebody
    /// is looking at.
    private func reached(_ done: Double, format: RecordingFormat,
                         quality: VideoExportQuality) {
        guard var live = result, live.answers(format: format, quality: quality),
              live.bytes == nil else { return }
        let shown = Int((min(max(live.fraction, 0), 1) * 100).rounded())
        let now = Int((min(max(done, 0), 1) * 100).rounded())
        guard now != shown else { return }
        live.fraction = done
        result = live
    }

    /// Drop the scratch file and the answer that went with it.
    private func forget() {
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        scratch = nil
        result = nil
    }
}
