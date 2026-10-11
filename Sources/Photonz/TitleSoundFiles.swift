import Foundation
import PhotonzCore
import PhotonzMedia

/// The files a title's whoosh and ticks play (`TitleSounds.swift`,
/// `PhotonzMedia/TitleSoundSynth.swift`).
///
/// A title's bar of sound is an ordinary sound layer, so the mix, the waveform
/// and the export all ask the sound library for its file like any other. This
/// is where that file comes from: made from the score the bar carries, the
/// first time a document holding it is drawn, into the app's caches folder,
/// and filed against the score's own id. Nobody ever picks one, and a project
/// saved with title sounds in it copies them in like any sound, so it opens
/// anywhere with them.
@MainActor
enum TitleSoundFiles {

    /// The scores already filed this run, so a redraw asks nothing twice.
    private static var filed: Set<UUID> = []

    static var folder: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.dzearing.photonz")
            .appendingPathComponent("Title Sounds", isDirectory: true)
    }

    /// Make and file every score `document` plays that has no file yet.
    /// A few milliseconds for a new score, nothing at all otherwise.
    static func prepare(for document: PhotonzDocument) {
        let scores = document.titleSoundScores
        guard !scores.isEmpty else { return }
        for (id, score) in scores where !filed.contains(id) {
            filed.insert(id)
            // A project read back already filed its own copy.
            guard SoundLibrary.shared.url(forID: id) == nil else { continue }
            let url = folder.appendingPathComponent("\(id.uuidString).wav")
            if !FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try TitleSoundSynth.wav(for: score).write(to: url, options: .atomic)
                } catch {
                    filed.remove(id)
                    continue
                }
            }
            SoundLibrary.shared.link(score.soundRef, to: url)
            SoundLibrary.shared.loadWaveform(for: score.soundRef)
        }
    }
}
