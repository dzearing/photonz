import AVFoundation
import AppKit
import Foundation
import PhotonzCore
import PhotonzMedia
import UniformTypeIdentifiers

// Where a layer's sound actually comes from (`docs/design/video-audio.md`).
//
// The same split pictures have always had: the document holds a `SoundRef`,
// this turns that reference back into a file, and the SHAPE of the sound — the
// waveform the timeline draws — is kept here too rather than in the document.
// Nothing in here is ever written to disk with a document, which is what keeps
// the model pure and what makes a recording's sound and a separated copy of it
// the same file rather than two.

/// Which file each sound in a document is, for the length of this run.
@MainActor
final class SoundLibrary {
    static let shared = SoundLibrary()

    private var urls: [UUID: URL] = [:]
    private var refsByURL: [URL: SoundRef] = [:]
    private var waveforms: [UUID: Waveform] = [:]
    private var reading: Set<UUID> = []

    /// Called on the main actor whenever a waveform lands, so a timeline drawn
    /// before the file had been read can draw it now.
    var onWaveformLanded: (() -> Void)?

    /// The file types Add Sound will open. Recordings are in the list on
    /// purpose: taking the sound off a video you are not otherwise using is a
    /// perfectly ordinary thing to want.
    static let openableTypes: [UTType] = [.audio, .mp3, .wav, .aiff, .mpeg4Audio, .movie, .mpeg4Movie]

    /// Read a file's length and hand back the reference a document can hold.
    /// The same file asked for twice is the same reference.
    func sound(at url: URL) async -> SoundRef? {
        let standardized = url.standardizedFileURL
        if let known = refsByURL[standardized] { return known }
        guard await SoundFile.hasSound(at: standardized),
              let durationMS = await SoundFile.durationMS(at: standardized), durationMS > 0
        else { return nil }
        let ref = SoundRef(durationMS: durationMS)
        link(ref, to: standardized)
        return ref
    }

    /// File a reference against a file somebody else already opened. This is
    /// what taking a recording's sound off its picture needs: the sound and the
    /// picture share an id because they are one file.
    func link(_ ref: SoundRef, to url: URL) {
        let standardized = url.standardizedFileURL
        urls[ref.id] = standardized
        refsByURL[standardized] = ref
    }

    /// Where this sound lives. A recording's own sound is looked up among the
    /// recordings, because it IS the recording.
    func url(for ref: SoundRef) -> URL? {
        urls[ref.id] ?? MovieLibrary.shared.url(forID: ref.id)
    }

    /// Every sound in a document, against the file it plays: what an export
    /// needs and the only thing it needs from the app.
    func urls(for mix: [AudioMixSegment]) -> [UUID: URL] {
        var found: [UUID: URL] = [:]
        for segment in mix where found[segment.sound.id] == nil {
            found[segment.sound.id] = url(for: segment.sound)
        }
        return found.compactMapValues { $0 }
    }

    // MARK: The shape of it

    /// The shape of this sound, if it has been read yet.
    func waveform(for ref: SoundRef) -> Waveform? { waveforms[ref.id] }

    /// Read the shape of this sound in the background, once.
    ///
    /// The timeline asks for this every time it draws a bar and does not wait
    /// for it: a bar with no waveform in it yet is a bar, and the peaks land a
    /// moment later and it redraws. Reading a file twice at once is refused,
    /// which matters because every row of the strip asks on every redraw.
    func loadWaveform(for ref: SoundRef) {
        guard waveforms[ref.id] == nil, !reading.contains(ref.id),
              let url = url(for: ref) else { return }
        reading.insert(ref.id)
        Task { [weak self] in
            let reading = await SoundFile.read(at: url)
            guard let self else { return }
            self.reading.remove(ref.id)
            guard let reading, !reading.waveform.isEmpty else { return }
            waveforms[ref.id] = reading.waveform
            onWaveformLanded?()
        }
    }
}
