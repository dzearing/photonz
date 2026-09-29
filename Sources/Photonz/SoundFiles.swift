import AVFoundation
import AppKit
import Foundation
import Observation
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
///
/// Observed for one thing only, the shapes: a bar drawn before its file had
/// been read draws the waveform the moment it lands, because the bar read
/// `waveform(for:)` and SwiftUI is watching that. Nothing told it before
/// 2026-09-26, and a recording added at the playhead kept a flat line under
/// it for as long as anyone looked.
@MainActor
@Observable
final class SoundLibrary {
    static let shared = SoundLibrary()

    @ObservationIgnored private var urls: [UUID: URL] = [:]
    @ObservationIgnored private var refsByURL: [URL: SoundRef] = [:]
    private var waveforms: [UUID: Waveform] = [:]
    /// Ignored on purpose: a bar asks for its file to be read from inside its
    /// own body, and a body that changed something it was watching would ask
    /// to be drawn again straight away.
    @ObservationIgnored private var reading: Set<UUID> = []

    // Clean noise (`CleanedSounds.swift`).
    /// The cleaned copies known to be on disk, by the id the mix plays them as.
    @ObservationIgnored var cleanedFiles: [UUID: URL] = [:]
    /// The newest cleaned copy of each file at each strength: what plays while
    /// a newer one (after a trim) is still being made.
    @ObservationIgnored var lastCleaned: [CleaningGroup: SoundRef] = [:]
    /// The cleanings under way or waiting to start, by the id they will play
    /// as, and which file at which strength each one is.
    @ObservationIgnored var cleaningTasks: [UUID: Task<URL?, Never>] = [:]
    @ObservationIgnored var pendingGroups: [UUID: CleaningGroup] = [:]
    /// How far along each cleaning being made is, nought to one, by the id it
    /// will play as. Observed: the segment draws it.
    var cleaningProgress: [UUID: Double] = [:]
    /// Counts the cleaned copies that have landed, so whatever is playing
    /// can pick one up the moment it does.
    var cleanedArrivals = 0

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
        if ref.cleaning != nil { return cleanedURLOrStandIn(for: ref) }
        return urls[ref.id] ?? MovieLibrary.shared.url(forID: ref.id)
    }

    /// The same question asked with an id on its own, which is what saving a
    /// project has for every file it points at (`ProjectMedia`).
    func url(forID id: UUID) -> URL? {
        urls[id] ?? MovieLibrary.shared.url(forID: id)
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
    ///
    /// A cleaned copy still being made draws as the last cleaned copy of the
    /// same file, or the file itself, until it lands.
    func waveform(for ref: SoundRef) -> Waveform? {
        if let known = waveforms[ref.id] { return known }
        guard ref.cleaning != nil else { return nil }
        if let group = CleaningGroup(ref), let last = lastCleaned[group], let known = waveforms[last.id] {
            return known
        }
        return waveforms[ref.sourceID]
    }

    /// The shape of this sound exactly, never a stand-in: what Normalize
    /// measures.
    func exactWaveform(for ref: SoundRef) -> Waveform? { waveforms[ref.id] }

    /// Keep a shape read somewhere else.
    func remember(_ waveform: Waveform, for ref: SoundRef) { waveforms[ref.id] = waveform }

    /// The shape of every sound a mix plays, as far as they have been read.
    ///
    /// What "how loud does this mix get" is worked out from (`AudioHeadroom`):
    /// a fader says how loud a layer is ASKED to play, and only the file says
    /// how loud it actually is. Anything not read yet is simply missing, and
    /// the arithmetic counts a missing shape at full scale rather than at
    /// silence, so the guess is always the safe way round.
    func waveforms(for mix: [AudioMixSegment]) -> [UUID: Waveform] {
        var found: [UUID: Waveform] = [:]
        for segment in mix where found[segment.sound.id] == nil {
            found[segment.sound.id] = waveforms[segment.sound.id]
        }
        return found.compactMapValues { $0 }
    }

    /// Read the shape of everything a mix plays, once each.
    ///
    /// Called where sound starts mattering rather than where a bar is drawn,
    /// so the meter and the export are working off the real files even when
    /// nothing has scrolled the timeline into view.
    func loadWaveforms(for mix: [AudioMixSegment]) {
        var asked: Set<UUID> = []
        for segment in mix where !asked.contains(segment.sound.id) {
            asked.insert(segment.sound.id)
            loadWaveform(for: segment.sound)
        }
    }

    /// Read the shape of this sound in the background, once.
    ///
    /// The timeline asks for this every time it draws a bar and does not wait
    /// for it: a bar with no waveform in it yet is a bar, and the peaks land a
    /// moment later and it redraws. Reading a file twice at once is refused,
    /// which matters because every row of the strip asks on every redraw.
    func loadWaveform(for ref: SoundRef) {
        guard waveforms[ref.id] == nil, !reading.contains(ref.id) else { return }
        // A cleaned copy is read once it is on disk; until then it is asked
        // for, and the file it is made from draws in its place.
        if ref.cleaning != nil, cleanedFileOnDisk(ref) == nil {
            clean(ref, waitingFirst: true)
            loadWaveform(for: ref.source)
            return
        }
        guard let url = url(for: ref) else { return }
        reading.insert(ref.id)
        Task { [weak self] in
            let reading = await SoundFile.read(at: url)
            guard let self else { return }
            self.reading.remove(ref.id)
            guard let reading, !reading.waveform.isEmpty else { return }
            waveforms[ref.id] = reading.waveform
        }
    }
}
