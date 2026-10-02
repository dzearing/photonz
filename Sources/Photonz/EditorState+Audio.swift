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

    // MARK: - The picked sound's channel

    /// The track whose Mute and Solo the Channel section switches: the very
    /// switches on that track's header, never a second mute of its own.
    var soundChannelTrack: DocumentTrack? {
        guard let id = soundLayerInHand?.id, let document,
              let track = document.soundTrackID(ofLayer: id) else { return nil }
        return document.track(id: track)
    }

    /// The name beside the Channel header: the file the sound came from.
    var soundChannelFileName: String? {
        guard let id = soundLayerInHand?.id else { return nil }
        return document?.soundFileName(ofLayer: id)
    }

    /// Mute and Solo in the Channel section: one undo step each, the same one
    /// the track header's button takes.
    func toggleSoundChannelMuted() {
        guard let track = soundChannelTrack?.id else { return }
        toggleTrackMuted(track)
    }

    func toggleSoundChannelSolo() {
        guard let track = soundChannelTrack?.id else { return }
        toggleTrackSolo(track)
    }

    /// The Volume slider: the fader, set in the mock's decibels.
    func setSoundVolume(sliderDB dB: Double) {
        setSoundGain(AudioLevel.volumeGain(sliderDB: dB))
    }

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
        let length = soundLengthMS(layer)
        var level = layer.soundLevel ?? AudioLevel()
        let before = level
        if fadeIn { level.setFadeIn(ms, lengthMS: length) } else { level.setFadeOut(ms, lengthMS: length) }
        guard level != before else { return }
        writeSoundLevel(level, onLayer: id)
    }

    /// How long the picked layer's sound fades in and out, in milliseconds.
    var soundFadesInHand: (inMS: Int, outMS: Int) {
        guard let layer = soundLayerInHand else { return (0, 0) }
        let level = soundLevelInHand
        return (level.fadeInMS, level.fadeOutMS(lengthMS: soundLengthMS(layer)))
    }

    /// The Fades section's In or Out, typed: the same edit the handle at that
    /// corner of the bar makes, as one step to undo.
    @discardableResult
    func setSoundFadeInHand(fadeIn: Bool, ms: Int) -> Int {
        guard let id = soundLayerInHand?.id else { return 0 }
        setSoundFade(onLayer: id, fadeIn: fadeIn, ms: ms)
        return fadeIn ? soundFadesInHand.inMS : soundFadesInHand.outMS
    }

    /// The Fades section's Curve: how both fades of the picked layer rise and
    /// fall. Picked before there is a fade, it waits for the next one.
    func setSoundFadeCurve(_ curve: EasingCurve) {
        guard let id = soundLayerInHand?.id else { return }
        var level = soundLevelInHand
        guard level.fadeCurve != curve else { return }
        level.fadeCurve = curve
        writeSoundLevel(level, onLayer: id)
    }

    private func soundLengthMS(_ layer: Layer) -> Int {
        layer.clipPieces?.totalLengthMS ?? layer.time?.lengthMS ?? 0
    }

    /// Put the level back to flat, keeping the fader where it is.
    func clearSoundLevelPoints() {
        guard let id = soundLayerInHand?.id, !soundLevelInHand.points.isEmpty else { return }
        var level = soundLevelInHand
        level.clearPoints()
        writeSoundLevel(level, onLayer: id)

    }

    // MARK: - Gain and Normalize

    /// The layers a right-click on one sound acts on: everything picked that
    /// has sound when the clicked one is among the picks, the way Premiere
    /// normalizes every selected clip at once, and otherwise just the one.
    func soundLayers(actingOn id: UUID) -> [UUID] {
        guard let document else { return [] }
        let picked = actionableLayerIDs
        let ids = picked.contains(id) ? Array(picked) : [id]
        return ids.filter { document.layer(id: $0)?.sound != nil }
    }

    /// Set the picked layer's gain, in decibels: the Gain row in the panel.
    func setSoundClipGain(_ dB: Double) {
        guard let id = soundLayerInHand?.id else { return }
        setSoundClipGain([id: dB])
    }

    /// Set gain on several layers as one step to undo.
    func setSoundClipGain(_ gains: [UUID: Double]) {
        guard let document else { return }
        var levels: [UUID: AudioLevel] = [:]
        for (id, dB) in gains {
            guard let layer = document.layer(id: id), layer.sound != nil else { continue }
            var level = layer.soundLevel ?? AudioLevel()
            let before = level
            level.clipGainDB = dB
            if level != before { levels[id] = level }
        }
        setSoundLevels(levels)
    }

    /// **Normalize**: bring each layer's loudest peak, over the stretch it
    /// plays, to -1 dBFS. Written as gain, so it can be undone or changed
    /// and the file is never touched. Cleans the noise first when Clean
    /// noise is checked (`normalizeCleansNoise`), and measures the cleaned
    /// sound, so the voice lands where it would have without it.
    func normalizeSound(layers ids: [UUID]) async {
        await normalize(layers: ids) { played, pieces in
            guard let wave = await self.measuredShape(of: played),
                  let peak = AudioNormalize.peakDBFS(of: wave, playedBy: pieces) else { return nil }
            return AudioNormalize.gainDB(toPeak: AudioNormalize.peakTargetDBFS, fromPeakDBFS: peak)
        }
    }

    /// **Normalize Loudness**: bring each layer to a loudness target (-14
    /// LUFS for the web, -16 for a podcast), measured off the file over the
    /// stretch it plays, and never past -1 dBFS at its loudest peak.
    func normalizeSoundLoudness(layers ids: [UUID], to target: AudioNormalize.Target) async {
        await normalize(layers: ids) { played, pieces in
            let url = played.cleaning == nil
                ? SoundLibrary.shared.url(for: played)
                : await SoundLibrary.shared.readyURL(for: played)
            guard let url else { return nil }
            let ranges = AudioNormalize.sourceRangesMS(playedBy: pieces)
            guard let lufs = await SoundFile.loudnessLUFS(at: url, sourceRangesMS: ranges) else { return nil }
            let peak = await self.measuredShape(of: played).flatMap { AudioNormalize.peakDBFS(of: $0, playedBy: pieces) }
            return AudioNormalize.gainDB(toLoudness: target.lufs, fromLUFS: lufs, peakDBFS: peak)
        }
    }

    /// Both Normalizes: clean first where Clean noise is checked, measure
    /// what will play, and write the cleaning and the gain as ONE step to
    /// undo, onto whatever the level has become by the time the measuring
    /// is done.
    private func normalize(layers ids: [UUID],
                           measure: (SoundRef, ClipPieces) async -> Double?) async {
        let cleans = normalizeCleansNoise
        soundsBeingNormalized += 1
        defer { soundsBeingNormalized -= 1 }
        var wanted: [UUID: (reduction: NoiseReduction?, gainDB: Double)] = [:]
        for id in ids {
            guard var layer = document?.layer(id: id), layer.sound != nil,
                  let pieces = layer.clipPieces else { continue }
            var level = layer.soundLevel ?? AudioLevel()
            if cleans, level.noiseReduction == nil { level.noiseReduction = .standard }
            layer.setSoundLevel(level)
            guard let played = layer.playedSound, let dB = await measure(played, pieces) else { continue }
            wanted[id] = (level.noiseReduction, dB)
        }
        guard let document else { return }
        var levels: [UUID: AudioLevel] = [:]
        for (id, change) in wanted {
            guard let layer = document.layer(id: id), layer.sound != nil else { continue }
            var level = layer.soundLevel ?? AudioLevel()
            let before = level
            level.noiseReduction = change.reduction
            level.clipGainDB = change.gainDB
            if level != before { levels[id] = level }
        }
        setSoundLevels(levels)
    }

    /// A sound's shape as Normalize measures it: a cleaned sound's own,
    /// made first if it has to be, never the stand-in the lane draws.
    private func measuredShape(of played: SoundRef) async -> Waveform? {
        guard played.cleaning != nil else { return await soundShape(of: played) }
        if await SoundLibrary.shared.readyURL(for: played) != nil,
           let exact = SoundLibrary.shared.exactWaveform(for: played) {
            return exact
        }
        return await soundShape(of: played.source)
    }

    /// A sound's shape, read now if the timeline has not read it yet.
    private func soundShape(of sound: SoundRef) async -> Waveform? {
        if let known = SoundLibrary.shared.exactWaveform(for: sound) { return known }
        guard let url = SoundLibrary.shared.url(for: sound),
              let reading = await SoundFile.read(at: url), !reading.waveform.isEmpty else { return nil }
        return reading.waveform
    }

    /// Write levels onto several layers as one step to undo.
    func setSoundLevels(_ levels: [UUID: AudioLevel]) {
        guard !levels.isEmpty else { return }
        perform { doc in
            for (id, level) in levels { doc.updateLayer(id: id) { $0.setSoundLevel(level) } }
        }
        followAudio()
    }

    // MARK: - Clean noise

    /// Where "Clean noise" beside Normalize is remembered, per user.
    static let normalizeCleansNoiseKey = "sound.normalizeCleansNoise"

    /// Whether Normalize cleans the noise first. On until somebody unchecks it.
    var normalizeCleansNoise: Bool {
        get { UserDefaults.standard.object(forKey: Self.normalizeCleansNoiseKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.normalizeCleansNoiseKey) }
    }

    /// Clean noise on several layers at a strength, or stop cleaning it
    /// (nil), as one step to undo. The cleaned copy starts being made at once.
    func setSoundNoiseReduction(_ reduction: NoiseReduction?, layers ids: [UUID]) {
        changeSoundLevels(layers: ids) { level in
            guard level.noiseReduction != reduction else { return false }
            level.noiseReduction = reduction
            return true
        }
    }

    /// The picked sound's Audio Effects list: put one on, or take one off, the
    /// picked sound and whatever is picked with it, as one step to undo.
    func addSoundEffectInHand(_ kind: SoundEffectKind) {
        guard let id = soundLayerInHand?.id, soundLevelInHand.canAddEffect(kind) else { return }
        changeSoundLevels(layers: soundLayers(actingOn: id)) { $0.addEffect(kind) }
        revealAddedSoundEffect()
    }

    func removeSoundEffectInHand(_ kind: SoundEffectKind) {
        guard let id = soundLayerInHand?.id else { return }
        changeSoundLevels(layers: soundLayers(actingOn: id)) { $0.removeEffect(kind) }
    }

    /// The row's switch: stop hearing an effect and keep its settings, or
    /// hear it again, on the picked sound and whatever is picked with it.
    func setSoundEffectInHand(_ kind: SoundEffectKind, on: Bool) {
        guard let id = soundLayerInHand?.id else { return }
        changeSoundLevels(layers: soundLayers(actingOn: id)) { $0.setEffect(kind, on: on) }
    }

    /// One setting of the EQ, on every picked sound that has an EQ.
    func changeSoundEQInHand(_ change: @escaping (inout SoundEQ) -> Void) {
        guard let id = soundLayerInHand?.id else { return }
        changeSoundLevels(layers: soundLayers(actingOn: id)) { level in
            guard var eq = level.eq else { return false }
            change(&eq)
            guard eq != level.eq else { return false }
            level.eq = eq
            return true
        }
    }

    /// One setting of the compressor, on every picked sound that has one.
    func changeSoundCompressorInHand(_ change: @escaping (inout SoundCompressor) -> Void) {
        guard let id = soundLayerInHand?.id else { return }
        changeSoundLevels(layers: soundLayers(actingOn: id)) { level in
            guard var compressor = level.compressor else { return false }
            change(&compressor)
            guard compressor != level.compressor else { return false }
            level.compressor = compressor
            return true
        }
    }

    /// Each layer's level changed by `change` (true where it changed), written
    /// as one step, and any cleaned copy that now has to exist started.
    private func changeSoundLevels(layers ids: [UUID], _ change: (inout AudioLevel) -> Bool) {
        guard let document else { return }
        var levels: [UUID: AudioLevel] = [:]
        for id in ids {
            guard let layer = document.layer(id: id), layer.sound != nil else { continue }
            var level = layer.soundLevel ?? AudioLevel()
            guard change(&level) else { continue }
            levels[id] = level
        }
        setSoundLevels(levels)
        for id in levels.keys {
            if let played = self.document?.layer(id: id)?.playedSound, played.cleaning != nil {
                SoundLibrary.shared.clean(played, waitingFirst: false)
            }
        }
    }

    /// The Strength on the Audio Effects list's Noise reduction row: the
    /// picked sound's strength.
    func setSoundNoiseReductionInHand(_ reduction: NoiseReduction?) {
        guard let id = soundLayerInHand?.id else { return }
        setSoundNoiseReduction(reduction, layers: soundLayers(actingOn: id))
    }

    /// How far along the cleaned copy of this layer's sound is, or nil where
    /// none is being made: the mark on its segment.
    func soundCleaningProgress(of id: UUID) -> Double? {
        guard let sound = document?.layer(id: id)?.sound else { return nil }
        return SoundLibrary.shared.cleaningProgress(ofSource: sound.sourceID)
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
    /// Kept between asks: the player and an export ask for it often and the
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

    /// Whether the mix has to be held down to fit in a file.
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

    /// Read the shape of every sound in the document, so the player and any
    /// export are working off the real files rather than off the safe guess.
    func loadSoundShapes() {
        SoundLibrary.shared.loadWaveforms(for: audioPlan)
    }

    /// Where a layer's sound is, as the app has it. Made the first time
    /// something asks to be heard, or when the timeline of a document with
    /// sound opens (`readyAudio`).
    var audioPlayer: DocumentAudioPlayer {
        if let already = audioPlayerStorage { return already }
        let player = DocumentAudioPlayer()
        player.setOutputGain(playerVolume.outputGain)
        audioPlayerStorage = player
        return player
    }

    /// Have the sound engine made before anybody presses play. Making one is
    /// the slowest part of starting the sound, and it happens on the player's
    /// own queue, so the window never waits for it.
    func readyAudio() {
        guard documentHasAudio else { return }
        _ = audioPlayer
    }

    /// Start the sound with the picture. Called where playing starts, so the
    /// two are hung off the same press.
    func startAudio() {
        guard documentHasAudio else { return }
        loadSoundShapes()
        audioPlayer.setOutputGain(playerVolume.outputGain)
        cleanedSoundsHeard = SoundLibrary.shared.cleanedArrivals
        audioPlayer.play(audioMix, fromMS: documentTimeMS)
    }

    /// The speaker on the transport: the sound off, or back on at the level it
    /// had. A playthrough in progress goes quiet at once and keeps its place,
    /// so turning the sound back on picks up where the picture is.
    func toggleDocumentMute() {
        var volume = playerVolume
        volume.toggleMute()
        applyPlayerVolume(volume)
    }

    /// The slider on the transport: a click, a drag or the wheel. Heard at
    /// once, playing or not, and remembered for the next recording.
    func setPlayerVolumeLevel(_ level: Double) {
        var volume = playerVolume
        volume.setLevel(level)
        applyPlayerVolume(volume)
    }

    /// The wheel over the slider, by a share of its length.
    func nudgePlayerVolume(by delta: Double) {
        var volume = playerVolume
        volume.nudge(by: delta)
        applyPlayerVolume(volume)
    }

    private func applyPlayerVolume(_ volume: PlayerVolume) {
        guard volume != playerVolume else { return }
        if volume.level != playerVolume.level {
            UserDefaults.standard.set(volume.level, forKey: Self.playerVolumeLevelKey)
        }
        playerVolume = volume
        audioPlayerStorage?.setOutputGain(volume.outputGain)
        scrubAudioStorage?.setOutputGain(volume.outputGain)
        if volume.isSilent { scrubAudioStorage?.end() }
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
              !isDocumentPlaying, !playerVolume.isSilent else { return }
        scrubAudio.setOutputGain(playerVolume.outputGain)
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
        // A cleaned copy landed while this was playing a stand-in for it:
        // carry on from here with the cleaned sound.
        if audioPlayerStorage != nil, cleanedSoundsHeard != SoundLibrary.shared.cleanedArrivals {
            startAudio()
            return
        }
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
        let urls = await SoundLibrary.shared.readyURLs(for: mix)
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
