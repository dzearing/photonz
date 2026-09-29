import Foundation
import PhotonzCore
import PhotonzMedia

// Clean noise: the cleaned copies of sounds, made on this Mac and kept beside
// the originals (`docs/design/video-audio.md`, "Clean noise").
//
// A cleaned segment's sound plays under its own id (`SoundRef.cleaned`), so
// everything that finds a file by id finds the cleaned copy through
// `SoundLibrary.url(for:)` with no idea it is one. Making the copy takes a
// second or two for a few minutes of sound, so it happens in the background:
// until it lands, playing reads the last cleaned copy of the same file at the
// same strength (a trim relearns the noise, and the one before sounds all but
// the same), or the file itself; the segment shows how far along it is; and
// the moment it lands, a playthrough under way picks it up. An export and
// Normalize wait for it (`readyURLs`, `readyURL`), so what is written and
// what is measured is always the cleaned sound.

/// A file cleaned at one strength, whichever stretches taught it the noise.
struct CleaningGroup: Hashable {
    let sourceID: UUID
    let reduction: NoiseReduction

    init?(_ ref: SoundRef) {
        guard let cleaning = ref.cleaning else { return nil }
        sourceID = cleaning.sourceID
        reduction = cleaning.reduction
    }
}

extension SoundLibrary {

    /// Where cleaned copies are kept: the app's caches, since each one can be
    /// made again from its file whenever it is wanted.
    static let cleanedFolder: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let bundle = Bundle.main.bundleIdentifier ?? "com.dzearing.photonz"
        return caches.appendingPathComponent(bundle, isDirectory: true)
            .appendingPathComponent("Cleaned sound", isDirectory: true)
    }()

    /// How long a cleaned copy nobody has made or played is kept.
    static let cleanedKeptFor: TimeInterval = 7 * 24 * 60 * 60

    static func cleanedFileURL(for ref: SoundRef) -> URL? {
        cleanedFolder?.appendingPathComponent("\(ref.id.uuidString).caf")
    }

    /// The cleaned copy, if it has been made (this run or an earlier one).
    func cleanedFileOnDisk(_ ref: SoundRef) -> URL? {
        if let known = cleanedFiles[ref.id] { return known }
        guard let url = Self.cleanedFileURL(for: ref),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        // Found again: kept another week from now.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        cleanedFiles[ref.id] = url
        if let group = CleaningGroup(ref) { lastCleaned[group] = ref }
        return url
    }

    /// The file to play for a cleaned sound: the copy if it is made, and
    /// otherwise the best stand-in while it is made.
    func cleanedURLOrStandIn(for ref: SoundRef) -> URL? {
        if let made = cleanedFileOnDisk(ref) { return made }
        clean(ref, waitingFirst: true)
        if let group = CleaningGroup(ref), let last = lastCleaned[group], last.id != ref.id,
           let made = cleanedFiles[last.id] {
            return made
        }
        return url(for: ref.source)
    }

    /// How far along the cleaning of this file is, nought to one, or nil
    /// where nothing of it is being cleaned: what the segment draws.
    func cleaningProgress(ofSource id: UUID) -> Double? {
        for (cleaned, value) in cleaningProgress where pendingGroups[cleaned]?.sourceID == id {
            return value
        }
        return nil
    }

    /// Start making a cleaned copy, once.
    ///
    /// `waitingFirst` holds off a moment, because a trim being dragged asks
    /// for a new copy on every step and only the last of them is wanted: a
    /// newer ask for the same file at the same strength calls off an older
    /// one that is still waiting or running.
    @discardableResult
    func clean(_ ref: SoundRef, waitingFirst: Bool) -> Task<URL?, Never>? {
        guard let group = CleaningGroup(ref) else { return nil }
        if let running = cleaningTasks[ref.id] { return running }
        for (id, task) in cleaningTasks where id != ref.id && pendingGroups[id] == group {
            task.cancel()
            forget(id)
        }
        let task = Task { [weak self] () -> URL? in
            if waitingFirst { try? await Task.sleep(for: .milliseconds(350)) }
            guard let self, !Task.isCancelled else { return nil }
            let made = await self.make(ref)
            self.forget(ref.id)
            return made
        }
        cleaningTasks[ref.id] = task
        pendingGroups[ref.id] = group
        return task
    }

    private func forget(_ id: UUID) {
        cleaningTasks[id] = nil
        pendingGroups[id] = nil
        cleaningProgress[id] = nil
    }

    /// The cleaned copy, made now if it has to be. Nil where the file cannot
    /// be read or the cleaning was called off by a newer one.
    func readyURL(for ref: SoundRef) async -> URL? {
        if let made = cleanedFileOnDisk(ref) { return made }
        guard let task = clean(ref, waitingFirst: false) else { return nil }
        return await task.value
    }

    /// Every file a mix plays, with every cleaned copy in it made first: what
    /// an export hands the writer, so the file on disk is the cleaned sound
    /// and never a stand-in.
    func readyURLs(for mix: [AudioMixSegment]) async -> [UUID: URL] {
        var found: [UUID: URL] = [:]
        for segment in mix where found[segment.sound.id] == nil {
            if segment.sound.cleaning != nil {
                found[segment.sound.id] = await readyURL(for: segment.sound)
                    ?? url(for: segment.sound.source)
            } else {
                found[segment.sound.id] = url(for: segment.sound)
            }
        }
        return found
    }

    /// Make one cleaned copy: learn the noise from the quiet stretches of what
    /// the segment plays, clean, and read the result's shape for the lane.
    private func make(_ ref: SoundRef) async -> URL? {
        guard let cleaning = ref.cleaning, let destination = Self.cleanedFileURL(for: ref),
              let source = url(for: ref.source) else { return nil }
        if let made = cleanedFileOnDisk(ref) { return made }
        cleaningProgress[ref.id] = 0
        var shape = exactWaveform(for: ref.source)
        if shape == nil {
            shape = await SoundFile.read(at: source)?.waveform
            if let shape, !shape.isEmpty { remember(shape, for: ref.source) }
        }
        let quiet = shape.map { NoiseReduction.quietStretchesMS(of: $0, within: cleaning.learnFromMS) } ?? []

        Self.pruneCleanedFolder()
        if let folder = Self.cleanedFolder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        // Written beside the final name and moved into place, so a copy half
        // made when the app quit is never taken for a finished one.
        let partial = destination.deletingPathExtension().appendingPathExtension("partial.caf")
        do {
            try await NoiseCleaner.write(from: source, reduction: cleaning.reduction, quietMS: quiet,
                                         to: partial) { value in
                let id = ref.id
                Task { @MainActor in
                    guard SoundLibrary.shared.cleaningProgress[id] != nil else { return }
                    SoundLibrary.shared.cleaningProgress[id] = value
                }
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            return nil
        }
        cleanedFiles[ref.id] = destination
        if let group = CleaningGroup(ref) { lastCleaned[group] = ref }
        if let reading = await SoundFile.read(at: destination), !reading.waveform.isEmpty {
            remember(reading.waveform, for: ref)
        }
        cleanedArrivals += 1
        return destination
    }

    /// Throw away cleaned copies nobody has touched in a week.
    private static func pruneCleanedFolder() {
        guard let folder = cleanedFolder,
              let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-cleanedKeptFor)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if modified < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }
}
