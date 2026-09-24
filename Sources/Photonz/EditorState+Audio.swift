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
        perform {
            landed = $0.addSound(sound, name: name, atMS: max(0, ms))
            $0.rememberMedia(.sound(sound), named: url.lastPathComponent)
        }
        if let landed { selectLayer(landed) }
        SoundLibrary.shared.loadWaveform(for: sound)
        documentMomentChanged()
        raiseCanvasNotice(.soundAdded(name: name))
        // A voiceover laid over a recording is somebody talking: its captions
        // write themselves the way a recording's own do.
        writeCaptionsByThemselves()
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

    /// A point on one layer's level line put down, or let go after a drag,
    /// as one step to undo however far the hand travelled. `fromMS` is where
    /// a dragged point started, which it leaves; nil for a new point.
    func setSoundLevelPoint(onLayer id: UUID, fromMS: Int?, to point: AudioLevelPoint) {
        guard let layer = document?.layer(id: id), layer.sound != nil else { return }
        var level = layer.soundLevel ?? AudioLevel()
        let before = level
        if let fromMS, fromMS != point.atMS { level.removePoint(atMS: fromMS) }
        level.setPoint(atMS: point.atMS, gain: point.gain)
        guard level != before else { return }
        if selectedLayerID != id { selectLayer(id) }
        writeSoundLevel(level, onLayer: id)
    }

    /// A point on one layer's level line double clicked away.
    func removeSoundLevelPoint(onLayer id: UUID, atLayerMS ms: Int) {
        guard var level = document?.layer(id: id)?.soundLevel,
              level.points.contains(where: { $0.atMS == ms }) else { return }
        level.removePoint(atMS: ms)
        writeSoundLevel(level, onLayer: id)
    }

    /// Set how loud one layer plays, from its level line on the timeline: the
    /// line dragged up or down as a whole, which is the fader.
    func setSoundGain(_ gain: Double, onLayer id: UUID) {
        guard let layer = document?.layer(id: id), layer.sound != nil else { return }
        var level = layer.soundLevel ?? AudioLevel()
        guard level.gain != AudioLevel.bounded(gain) else { return }
        level.gain = AudioLevel.bounded(gain)
        writeSoundLevel(level, onLayer: id)
    }

    /// Fade a layer's sound in at its start, or out at its end, over `ms`,
    /// from the handle at that top corner of its segment. Nought takes the
    /// fade away.
    func setSoundFade(onLayer id: UUID, fadeIn: Bool, ms: Int) {
        guard let layer = document?.layer(id: id), layer.sound != nil else { return }
        let length = layer.clipPieces?.totalLengthMS ?? layer.time?.lengthMS ?? 0
        var level = layer.soundLevel ?? AudioLevel()
        let before = level
        if fadeIn { level.setFadeIn(ms, lengthMS: length) } else { level.setFadeOut(ms, lengthMS: length) }
        guard level != before else { return }
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

    /// The plan the document says, before anything is done about how loud it
    /// adds up to (`AudioMix.swift`).
    var audioPlan: [AudioMixSegment] { document?.audioMix() ?? [] }

    /// The plan: what plays, in one list, read by the player and by an export
    /// without either working anything out.
    ///
    /// Held under what a sound file can carry (`AudioHeadroom`), because sound
    /// adds up: three things at the level they were recorded at are three times
    /// full scale where they overlap, and everything past the top is sheared
    /// off flat. So the plan the player is handed and the plan the export is
    /// handed are both the held-down one, which keeps the promise this whole
    /// module is built on — what you hear is what exports — true of the
    /// holding down as well as of everything else.
    var audioMix: [AudioMixSegment] { AudioHeadroom.limited(audioPlan, by: audioHeadroom.trim) }

    /// The shape of every sound in the document, as far as the app has read
    /// them. Missing ones are counted at full scale, which is the safe guess.
    var soundShapes: [UUID: Waveform] { SoundLibrary.shared.waveforms(for: audioPlan) }

    /// How loud this document's mix gets, and by how much it is over.
    ///
    /// Kept between asks: the meter wants this thirty times a second and the
    /// answer is a walk over every twenty milliseconds of sound there is, while
    /// noticing that nothing changed costs one pass over the segments.
    var audioHeadroom: AudioHeadroom {
        let plan = audioPlan
        let shapes = soundShapes
        if let cached = audioHeadroomCache, cached.shapes == shapes.count, cached.plan == plan {
            return cached.reading
        }
        let reading = AudioHeadroom.reading(of: plan, peaks: shapes)
        audioHeadroomCache = (plan, shapes.count, reading)
        return reading
    }

    /// Whether the mix has to be held down to fit in a file. What the mark on
    /// the meter and the line on the export notice are drawn from.
    var isMixHeldDown: Bool { audioHeadroom.isOver }

    /// How loud the mix is coming out at the moment the playhead is on, nought
    /// to one and beyond.
    ///
    /// Read off the plan rather than off a tap on the engine, on purpose: it
    /// moves while you drag the playhead and not only while it plays, it says
    /// the same thing the export will, and it is arithmetic a test can pin.
    var audioLevelNow: Double {
        AudioHeadroom.level(of: audioMix, peaks: soundShapes, atMS: documentTimeMS)
    }

    /// Where that level sits on the meter, nought at the bottom, one at the top.
    var audioMeterFraction: Double { AudioHeadroom.meterFraction(ofLevel: audioLevelNow) }

    /// Read the shape of every sound in the document, so the meter and any
    /// export are working off the real files rather than off the safe guess.
    func loadSoundShapes() {
        SoundLibrary.shared.loadWaveforms(for: audioPlan)
    }

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
        loadSoundShapes()
        audioPlayer.setMuted(isDocumentMuted)
        audioPlayer.play(audioMix, fromMS: documentTimeMS)
    }

    /// The volume button on the transport: the sound off at the speaker, or
    /// back on. A playthrough in progress goes quiet at once and keeps its
    /// place, so turning the sound back on picks up where the picture is.
    func toggleDocumentMute() {
        isDocumentMuted.toggle()
        audioPlayerStorage?.setMuted(isDocumentMuted)
        if isDocumentMuted { scrubAudioStorage?.end() }
    }

    func stopAudio() {
        audioPlayerStorage?.stop()
    }

    // MARK: - Hearing the scrub

    /// Where a drag on the playhead is heard from, made the first time one is
    /// dragged.
    var scrubAudio: ScrubAudioPlayer {
        if let already = scrubAudioStorage { return already }
        let player = ScrubAudioPlayer()
        scrubAudioStorage = player
        return player
    }

    /// Whether a drag on the playhead is in hand and being listened to.
    var isAuditioningScrub: Bool { scrubAudioStorage?.isAuditioning ?? false }

    /// A drag on the playhead started. Nothing is heard yet: what a scrub
    /// plays is MOVEMENT, and so far there has been none, which is what keeps
    /// a single click to place the playhead silent.
    ///
    /// Not while it is playing. A scrub mid-play already restarts the whole
    /// mix from where the hand put the playhead (`EditorState+Time`), and that
    /// IS the sound of that moment, so laying grains over it would be the same
    /// sound twice.
    func beginScrubAudition() {
        guard Experiments.shared.scrubAuditionEnabled, documentHasAudio,
              !isDocumentPlaying, !isDocumentMuted else { return }
        scrubAudio.begin(audioMix, atMS: documentTimeMS)
    }

    /// The playhead landed somewhere new while a drag is in hand.
    func auditionScrub() {
        guard let player = scrubAudioStorage, player.isAuditioning else { return }
        guard !isDocumentPlaying else {
            player.end()
            return
        }
        player.moved(audioMix, toMS: documentTimeMS)
    }

    /// The hand let go.
    func endScrubAudition() {
        scrubAudioStorage?.end()
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
        // The PLAN rather than the held-down mix, so the export does the
        // holding down itself and can say by how much. It is the same
        // arithmetic off the same shapes, so what lands is the same file
        // either way; this is only about who gets to tell the story.
        let mix = audioPlan
        guard !mix.isEmpty else {
            raiseCanvasNotice(.mixWritten(file: nil))
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.nameFieldStringValue = mixFileName + ".m4a"
        panel.message = "Write the mix out as one sound file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await writeMix(to: url) }
    }

    /// The same thing without the panel: what a scripted walk drives, so the
    /// words on screen after an export are the app's own rather than a walk's
    /// stand-in for them.
    func writeMix(to url: URL) async {
        let mix = audioPlan
        guard !mix.isEmpty else {
            raiseCanvasNotice(.mixWritten(file: nil))
            return
        }
        let urls = SoundLibrary.shared.urls(for: mix)
        let shapes = soundShapes
        do {
            let headroom = try await AudioMixdown.write(mix, urls: urls, to: url, peaks: shapes)
            // Said before the file is judged by ear rather than after: a mix
            // that had to come down is quieter on disk than it was in the room,
            // and somebody who is not told that spends the next ten minutes
            // wondering why.
            if let over = headroom.overByDB {
                raiseCanvasNotice(.mixHeldDown(file: url.lastPathComponent, byDB: over))
            } else {
                raiseCanvasNotice(.mixWritten(file: url.lastPathComponent))
            }
        } catch {
            raiseCanvasNotice(.mixWritten(file: nil))
        }
    }
}
