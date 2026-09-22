import AppKit
import Foundation
import PhotonzCore
import PhotonzMedia
import UniformTypeIdentifiers

// Captions, in the window (`Captions.swift`,
// `docs/design/mocks/pages/video-captions.html`).
//
// **Captions are not a mode that replaces the app. They are what the Title /
// Text tool does when the document has time.** Which means there is almost
// nothing here: Write Captions listens, the words land as ordinary text layers
// with an in and an out, and from that moment every single thing you would want
// to do to one is something the app already does to text. Correcting a word is
// typing. Restyling a line is the font and colour controls. Moving one is
// dragging its bar. Deleting one is ⌫. All of it undoes, because all of it goes
// through `perform`.
//
// The five things that ARE here, and nothing else:
//
// - Which sound gets listened to, and where its words land on the timeline.
// - Saying how far along it is, and stopping it without losing what it heard.
// - Nudging the whole track when the machine ran late.
// - Taking them all off again.
// - Writing them out as a subtitle file, for the way out that is not a picture.
extension EditorState {

    // MARK: - Whether there is anything to caption

    /// Whether Write Captions would do anything: the feature is on, this
    /// document has time and something in it makes a sound.
    var canWriteCaptions: Bool {
        guard Experiments.shared.captionsFromTheSoundEnabled, documentHasTime,
              SpeechTranscription.isAvailable, !isWritingCaptions else { return false }
        return captionableSound.url != nil
    }

    /// Whether the listening is running right now.
    var isWritingCaptions: Bool { captionsBeingWritten != nil }

    /// Whether this document has captions in it at all.
    var hasCaptions: Bool { document?.hasCaptions ?? false }

    /// How many, for a panel that would rather say a number than a list.
    var captionCount: Int { document?.captionLayers.count ?? 0 }

    /// The sound to listen to, and the file it lives in.
    ///
    /// Where a document has several sounds — a voiceover, some music, a second
    /// take — the one worth captioning is the one there is most of, because
    /// that is the one somebody is talking over. There is no picker for this on
    /// purpose: a picker is a question asked before anybody has a reason to
    /// answer it, and the answer here is right almost every time. Somebody who
    /// wants a different one switches the others off and runs it again.
    var captionableSound: (sound: SoundRef?, url: URL?) {
        let mix = audioMix
        guard !mix.isEmpty else { return (nil, nil) }
        var lengths: [UUID: Int] = [:]
        var sounds: [UUID: SoundRef] = [:]
        for segment in mix {
            lengths[segment.sound.id, default: 0] += segment.lengthMS
            sounds[segment.sound.id] = segment.sound
        }
        guard let winner = lengths.max(by: { $0.value < $1.value })?.key,
              let sound = sounds[winner] else { return (nil, nil) }
        return (sound, SoundLibrary.shared.url(for: sound))
    }

    /// What the Captions section says right now, in one line.
    var captionsReading: String {
        if let progress = captionsBeingWritten { return progress.reading }
        guard hasCaptions else {
            return canWriteCaptions
                ? "Nothing has been captioned yet."
                : (documentHasAudio ? "Ready." : Captions.nothingToHear)
        }
        let cues = document?.captionCues ?? []
        let words = cues.reduce(0) { $0 + $1.words.count }
        let unsure = cues.filter(\.isUncertain).count
        let said = "\(CaptionProgress.count(words)) in \(cues.count) caption\(cues.count == 1 ? "" : "s")"
        guard unsure > 0 else { return said }
        return said + " · \(unsure) with a word it was unsure of"
    }

    // MARK: - Listening

    /// **Write Captions.** Listen to the recording and put the words on the
    /// timeline at the moments they were said.
    ///
    /// Nothing leaves this Mac. The words land in one undo step at the end
    /// rather than dribbling in: a document that changes under you four hundred
    /// times while you watch is a document you cannot undo out of, and the
    /// progress line is already saying it is getting somewhere.
    func writeCaptions() {
        guard canWriteCaptions else { return }
        let subject = captionableSound
        guard let sound = subject.sound, let url = subject.url else {
            raiseCanvasNotice(.captionsCameTo(Captions.nothingToHear))
            return
        }
        pauseDocument()
        captionsBeingWritten = TranscriptionProgress(listenedToMS: 0, ofMS: sound.durationMS,
                                                     words: [])
        let landing = CaptionLanding()
        captionsTask = Task { [weak self] in
            do {
                let heard = try await SpeechTranscription.words(of: url,
                                                                locale: Locale(identifier: "en-US")) {
                    landing.note($0)
                }
                await MainActor.run { self?.captionsLanded(heard, of: sound) }
            } catch {
                await MainActor.run {
                    self?.captionsBeingWritten = nil
                    self?.raiseCanvasNotice(.captionsCameTo(
                        (error as? LocalizedError)?.errorDescription
                            ?? "The recording could not be listened to."))
                }
            }
        }
        // The readings land off whatever thread heard them; this walks them
        // onto the window's own actor at a pace a person can read, which is
        // also a pace SwiftUI can draw without redrawing the panel per buffer.
        captionsWatcher = Task { [weak self] in
            while let self, self.isWritingCaptions, !Task.isCancelled {
                if let latest = landing.latest, latest.listenedToMS > 0 {
                    self.captionsBeingWritten = latest
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    /// **Stop.** Keep every word it already heard.
    func stopWritingCaptions() {
        guard isWritingCaptions else { return }
        captionsTask?.cancel()
    }

    /// Nothing is left listening when the window goes.
    func forgetCaptionsInFlight() {
        captionsTask?.cancel()
        captionsWatcher?.cancel()
        captionsTask = nil
        captionsWatcher = nil
        captionsBeingWritten = nil
    }

    /// What happens when the listening finishes, whether it ran out of
    /// recording or somebody stopped it.
    private func captionsLanded(_ heard: HeardWords, of sound: SoundRef) {
        captionsBeingWritten = nil
        captionsTask = nil
        captionsWatcher?.cancel()
        captionsWatcher = nil
        guard let document else { return }

        // The recogniser heard a FILE. The timeline is not the file: a trim, a
        // cut or a change of speed moves every word after it, and a piece
        // thrown away takes its words with it (`CaptionTiming`).
        let placed = CaptionTiming.onTheTimeline(heard.words, of: sound, in: document.audioMix())
        let cues = CaptionCues.cues(from: placed)
        guard !cues.isEmpty else {
            raiseCanvasNotice(.captionsCameTo(heard.wasStopped
                ? CaptionProgress.stopped(doneMS: heard.listenedToMS, ofMS: heard.ofMS, words: 0)
                : Captions.heardNothing))
            return
        }

        let canvas = document.canvasSize
        perform { doc in
            // Writing captions again replaces the last lot rather than laying a
            // second track over the first, which is what a second press
            // obviously means and what stops two copies of every line.
            doc.clearCaptions()
            var ids: Set<UUID> = []
            for layer in CaptionLayers.layers(for: cues, in: canvas) {
                doc.addLayer(layer)
                ids.insert(layer.id)
            }
            // One row in the layers list rather than four hundred. Each caption
            // still gets its own bar on the timeline, because the strip walks
            // into groups.
            _ = doc.groupLayers(ids: ids, name: CaptionLayers.groupName)
        }
        // Read back off the document the edit LANDED in, not the one captured
        // before it: the captured one has no captions in it, so this quietly
        // selected nothing and left whatever was picked before still picked.
        selectLayer(self.document?.captionLayers.first?.id)
        documentMomentChanged()

        if heard.wasStopped {
            raiseCanvasNotice(.captionsCameTo(
                CaptionProgress.stopped(doneMS: heard.listenedToMS, ofMS: heard.ofMS,
                                        words: placed.count)))
        } else {
            raiseCanvasNotice(.captionsWritten(words: placed.count, cues: cues.count,
                                               ofMS: heard.ofMS))
        }
    }

    // MARK: - Fixing the timing by hand

    /// How far one press moves the whole track.
    ///
    /// A tenth of a second, which is about the smallest shift anybody can see
    /// against a voice and small enough that holding the key is a dial rather
    /// than a jump.
    static let captionNudgeMS = 100

    var canNudgeCaptions: Bool {
        Experiments.shared.captionsFromTheSoundEnabled && hasCaptions && !isWritingCaptions
    }

    /// **Captions Later / Captions Earlier.** Move every caption together.
    ///
    /// The one correction that fixes a whole track at once. A recogniser that
    /// runs a fraction late runs late by the same amount everywhere, so this is
    /// a judgment made once instead of four hundred times, and the other half
    /// of fixing timing — this one line is wrong — is dragging its bar end,
    /// which needs nothing written for it.
    func nudgeCaptions(byMS ms: Int) {
        guard canNudgeCaptions else { return }
        perform { $0.shiftCaptions(byMS: ms) }
        documentMomentChanged()
    }

    // MARK: - Taking them off

    var canClearCaptions: Bool {
        Experiments.shared.captionsFromTheSoundEnabled && hasCaptions && !isWritingCaptions
    }

    /// **Clear Captions.** Take them all off, leaving everything else alone.
    func clearCaptions() {
        guard canClearCaptions else { return }
        perform { $0.clearCaptions() }
        documentMomentChanged()
    }

    // MARK: - The way out that is not a picture

    /// Whether there is anything to write out. Burning them into the film needs
    /// nothing here: a caption is an ordinary text layer, so the exporter draws
    /// it along with everything else.
    var canExportCaptions: Bool {
        Experiments.shared.captionsFromTheSoundEnabled && hasCaptions
    }

    /// **Export Captions…** Write the same words out as a subtitle file.
    func exportCaptions() {
        guard canExportCaptions, let cues = document?.captionCues, !cues.isEmpty else {
            raiseCanvasNotice(.captionsFileWritten(file: nil))
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: CaptionsSRT.fileExtension) ?? .plainText]
        panel.nameFieldStringValue = captionsFileName + "." + CaptionsSRT.fileExtension
        panel.message = "Write the captions out as a subtitle file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CaptionsSRT.text(cues).write(to: url, atomically: true, encoding: .utf8)
            raiseCanvasNotice(.captionsFileWritten(file: url.lastPathComponent))
        } catch {
            raiseCanvasNotice(.captionsFileWritten(file: nil))
        }
    }

    /// What the subtitle file is called before anybody renames it: the
    /// recording's own name, so it sits beside the film it belongs to.
    private var captionsFileName: String {
        recordingURL?.deletingPathExtension().lastPathComponent ?? "Captions"
    }
}

/// Where the progress readings land on their way from the listening to the
/// window.
///
/// They arrive off whatever thread heard them, and the window is on the main
/// actor, so they are parked here and picked up there. Holding the latest
/// rather than a queue of them on purpose: a reading nobody has drawn yet is
/// worth nothing next to the one after it.
final class CaptionLanding: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: TranscriptionProgress?

    func note(_ progress: TranscriptionProgress) {
        lock.lock(); defer { lock.unlock() }
        kept = progress
    }

    var latest: TranscriptionProgress? {
        lock.lock(); defer { lock.unlock() }
        return kept
    }
}
