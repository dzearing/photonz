import Foundation

/// Writing a file beside where it goes and swapping it in whole.
///
/// Every route that writes a video starts by removing what is at its
/// destination. Pointed at the file it reads from (Export over the
/// recording's own name, which is the name the save box offers), the verbatim
/// copy removed the recording and then had nothing to copy: the recording was
/// gone and the export failed (measured 2026-10-28). And a write that stops
/// part way, a quit or a full disk, took the file that was there with it.
///
/// So the write goes to a scratch file on the destination's own disk, and
/// only a finished, non-empty file takes the destination's place, in one
/// rename. Until then whatever was there is untouched and readable.
public enum FileSwap {

    public enum SwapError: Error {
        /// The write finished without leaving a file, or left an empty one.
        case nothingWritten
    }

    /// Run `write` against a scratch URL beside `destination`, then put what
    /// it wrote in `destination`'s place. Throws what `write` throws, leaving
    /// `destination` as it was and nothing beside it.
    @discardableResult
    public static func write<T>(to destination: URL,
                                isolation: isolated (any Actor)? = #isolation,
                                _ write: (URL) async throws -> T) async throws -> T {
        let fm = FileManager.default
        // A folder the system keeps for exactly this on the destination's
        // volume, so the last step is a rename and never a copy. Where the
        // volume has none, the destination's own folder, under a hidden name.
        let folder = (try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                  appropriateFor: destination, create: true))
        let scratchFolder = folder ?? destination.deletingLastPathComponent()
        let scratch = scratchFolder.appendingPathComponent(
            ".\(UUID().uuidString)-\(destination.lastPathComponent)")
        defer {
            try? fm.removeItem(at: scratch)
            if let folder { try? fm.removeItem(at: folder) }
        }
        let result = try await write(scratch)
        let bytes = (try? scratch.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard bytes > 0 else { throw SwapError.nothingWritten }
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: scratch)
        } else {
            try fm.moveItem(at: scratch, to: destination)
        }
        return result
    }
}
