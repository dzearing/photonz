import AVFoundation
import AppKit
import Foundation
import PhotonzCore
import PhotonzMedia
import UniformTypeIdentifiers

// Sound, in the window (`docs/design/video-audio.md`).
//
// Four things a person does, and nothing else: take a recording's sound off its
// picture, bring a sound in from a file, set how loud something is, and shape
// how loud it is as it runs. Everything past that — cutting it, moving it,
// naming it, switching it off, undoing any of it — is what the timeline already
// does to a layer, because a piece of sound IS a layer.
extension EditorState {

    // MARK: - Whether there is sound at all

    /// Whether anything in this document makes a sound.
    var documentHasAudio: Bool { document?.hasAudio ?? false }

    /// The layer whose sound the panel and the menu are talking about: the one
    /// picked, where it has a sound.
    var soundLayerInHand: Layer? {
        guard let id = selectedLayerID, let layer = document?.layer(id: id), layer.sound != nil
        else { return nil }
        return layer
    }

    /// How loud the picked layer is, and how that changes as it runs.
    var soundLevelInHand: AudioLevel { soundLayerInHand?.soundLevel ?? AudioLevel() }

    // MARK: - Taking the sound off the picture

    /// Whether Detach Sound would do anything: a clip is in hand, its recording
    /// has a sound track, and nobody has taken it off already.
    var canDetachSound: Bool {
        guard let id = selectedLayerID else { return false }
        return document?.canDetachSound(ofLayer: id) ?? false
    }

    /// **Detach Sound.** The picture keeps its place and goes quiet; the sound
    /// lands on its own layer just above it, in step, with the same cuts.
    ///
    /// From that moment they are two ordinary layers, so cutting the picture
    /// leaves the voiceover over it exactly where it was — which is the case
    /// the cut clickthrough is built around and the reason this command exists.
    func detachSound() {
        guard let id = selectedLayerID, let document,
              let split = document.detachingSound(ofLayer: id) else { return }
        pauseDocument()
        perform { $0 = split.document }
        selectLayer(split.soundLayerID)
        SoundLibrary.shared.loadWaveform(for: split.sound)
        raiseCanvasNotice(.soundDetached(clip: document.layer(id: id)?.name ?? "The clip"))
    }

    // MARK: - Bringing sound in

    /// **Add Sound.** Pick a file; it lands on the timeline where the playhead
    /// is, as a layer, and everything the timeline does works on it at once.
    func addSoundFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = SoundLibrary.openableTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        panel.message = "Choose a sound to put on the timeline"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await addSound(from: url, atMS: documentTimeMS) }
    }

    /// The same thing without the panel: what a drop on the timeline does, and
    /// what a scripted walk does.
    @discardableResult
    func addSound(from url: URL, atMS ms: Int) async -> UUID? {
        guard let sound = await SoundLibrary.shared.sound(at: url) else {
            raiseCanvasNotice(.mixWritten(file: nil))
            return nil
        }
        let name = url.deletingPathExtension().lastPathComponent
        var landed: UUID?
        pauseDocument()
        perform { landed = $0.addSound(sound, name: name, atMS: max(0, ms)) }
        if let landed { selectLayer(landed) }
        SoundLibrary.shared.loadWaveform(for: sound)
        documentMomentChanged()
        raiseCanvasNotice(.soundAdded(name: name))
        return landed
    }

    // MARK: - How loud

    /// Set the picked layer's level: the fader, which takes the whole shape
    /// with it where there is a shape.
    func setSoundGain(_ gain: Double) {
        guard let id = soundLayerInHand?.id else { return }
        var level = soundLevelInHand
        guard level.gain != AudioLevel.bounded(gain) else { return }
        level.gain = AudioLevel.bounded(gain)
        writeSoundLevel(level, onLayer: id)
    }

    /// Pin the level at a moment of the picked layer, measured from its own
    /// start. This is the whole of level over time: a duck is a point either
    /// side of a dip, and a fade in is a point at nought and a point at full.
    func setSoundLevelPoint(atLayerMS ms: Int, gain: Double) {
        guard let id = soundLayerInHand?.id else { return }
        var level = soundLevelInHand
        level.setPoint(atMS: ms, gain: gain)
        writeSoundLevel(level, onLayer: id)
    }

    func removeSoundLevelPoint(atLayerMS ms: Int) {
        guard let id = soundLayerInHand?.id else { return }
        var level = soundLevelInHand
        level.removePoint(atMS: ms)
        writeSoundLevel(level, onLayer: id)
    }

    /// Put the level back to flat, keeping the fader where it is.
    func clearSoundLevelPoints() {
        guard let id = soundLayerInHand?.id, !soundLevelInHand.points.isEmpty else { return }
        var level = soundLevelInHand
        level.clearPoints()
        writeSoundLevel(level, onLayer: id)

    }

    /// What the mix is called before anybody renames it: the document's own
    /// name, so a mix off a recording lands beside it under the same word.
    var mixFileName: String {
        (documentURL ?? openedFileURL)?.deletingPathExtension().lastPathComponent ?? "Mix"
    }

    private func writeSoundLevel(_ level: AudioLevel, onLayer id: UUID) {
        perform { document in
            document.updateLayer(id: id) { $0.setSoundLevel(level) }
        }
        followAudio()
    }

    // MARK: - What it sounds like

    /// The plan: what plays, in one list, read by the player and by an export
    /// without either working anything out (`AudioMix.swift`).
    var audioMix: [AudioMixSegment] { document?.audioMix() ?? [] }

    /// Where a layer's sound is, as the app has it. Made the first time
    /// something asks to be heard.
    var audioPlayer: DocumentAudioPlayer {
        if let already = audioPlayerStorage { return already }
        let player = DocumentAudioPlayer()
        audioPlayerStorage = player
        return player
    }

    /// Start the sound with the picture. Called where playing starts, so the
    /// two are hung off the same press.
    func startAudio() {
        guard documentHasAudio else { return }
        audioPlayer.play(audioMix, fromMS: documentTimeMS)
    }

    func stopAudio() {
        audioPlayerStorage?.stop()
    }

    /// Keep every layer's level where the plan says it is as the playhead moves.
    func followAudio() {
        guard isDocumentPlaying else { return }
        audioPlayerStorage?.follow(audioMix, atMS: documentTimeMS)
    }

    // MARK: - Writing it out

    /// **Export Sound.** The mix as one file, built from the same plan that
    /// plays, so what lands on disk is what was in the room.
    ///
    /// Its own command rather than part of a video export because there is no
    /// document video export yet (`video-share`), and because a mix you can
    /// play in anything is the fastest way to check a mix by ear.
    func exportSound() {
        let mix = audioMix
        guard !mix.isEmpty else {
            raiseCanvasNotice(.mixWritten(file: nil))
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.nameFieldStringValue = mixFileName + ".m4a"
        panel.message = "Write the mix out as one sound file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let urls = SoundLibrary.shared.urls(for: mix)
        Task { [weak self] in
            do {
                try await AudioMixdown.write(mix, urls: urls, to: url)
                self?.raiseCanvasNotice(.mixWritten(file: url.lastPathComponent))
            } catch {
                self?.raiseCanvasNotice(.mixWritten(file: nil))
            }
        }
    }
}
