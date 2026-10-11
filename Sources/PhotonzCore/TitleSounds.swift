import CoreGraphics
import Foundation

// Titles can play a soft whoosh and tick as they build (task
// `titles-can-play-a-soft-whoosh-and-tick-as-they-b`,
// `docs/design/video-titles-polish.md`, step 6).
//
// Sound is credited with half of how finished an intro feels, so a title can
// be heard arriving: a soft whoosh as its headline comes in and a light tick as
// each small accent lands. It is a switch on the title's recipe, off until
// somebody turns it on.
//
// **One bar of sound per title, owned by it.** What it plays is a score worked
// out from the title's own compiled design (`TitleSoundScore`): which sounds,
// at which moments, and how long. The bar is an ordinary sound layer, so it is
// heard, exported, muted with its track and turned down like any other; it
// carries a link back to its title (`Layer.titleSound`) holding the score, and
// the app makes the file the score describes (`PhotonzMedia/TitleSoundSynth`).
//
// **The title decides where it is.** Every edit ends with
// `keepTitleSoundsInStep`, which puts each title's bar back at the title's
// start with the title's current score, makes one for a title that has none
// (a copy, a paste, the switch just turned on), and takes away any bar whose
// title is gone or whose switch is off. So no move, trim, nudge, copy or
// delete had to learn about title sounds: whatever happens to the title, the
// bar follows on the same step, and undo puts both back together.

/// One sound in a title's score.
public enum TitleSoundKind: String, CaseIterable, Hashable, Codable, Sendable {
    /// Filtered air swelling past: the headline coming in.
    case whoosh
    /// A short bright click: a small accent landing.
    case tick
}

/// One sound, at one moment of a title.
public struct TitleSoundCue: Hashable, Codable, Sendable {
    public var kind: TitleSoundKind
    /// From the title's own start.
    public var atMS: Int
    /// How long it sounds, tail included.
    public var lengthMS: Int

    public init(_ kind: TitleSoundKind, atMS: Int, lengthMS: Int) {
        self.kind = kind
        self.atMS = max(0, atMS)
        self.lengthMS = max(1, lengthMS)
    }

    public var endMS: Int { atMS + lengthMS }
}

/// Everything a title's bar of sound plays, worked out from its design.
public struct TitleSoundScore: Hashable, Codable, Sendable {
    public var cues: [TitleSoundCue]
    /// Calm is a longer, darker whoosh; Punchy a short bright one.
    public var energy: TitleEnergy

    /// What the bar is called on the timeline and in the layers list.
    public static let barName = "Title Sounds"
    /// A whoosh is never shorter or longer than this, however its words move.
    public static let whooshLengthRange: ClosedRange<Int> = 280...1_100
    public static let tickLengthMS = 90
    /// Ticks closer than this run into one another and read as a rattle.
    public static let tickSpacingMS = 120
    public static let mostTicks = 3
    /// An accent covering more than this share of the frame (a wash of
    /// light, a panel) arrives as a scene change, not a click.
    static let smallAccentShare: CGFloat = 0.2

    public init(cues: [TitleSoundCue], energy: TitleEnergy) {
        self.cues = cues.sorted { ($0.atMS, $0.kind.rawValue) < ($1.atMS, $1.kind.rawValue) }
        self.energy = energy
    }

    /// The score of a placed title as its recipe stands, nil for one with
    /// nothing to sound (no words coming in at all).
    public init?(title: Layer, recipe: TitleRecipe, canvasSize: CGSize) {
        let design = recipe.compiled
        let span = title.time?.lengthMS ?? .max
        var cues: [TitleSoundCue] = []

        // The whoosh: the headline's in, or the first words in where a title
        // has no headline.
        let words: [TitlePartRole] = [.headline, .subtitle, .kicker]
        let entering = words.lazy.compactMap { role in
            design.parts.filter { $0.role == role }.compactMap(\.in).min { $0.delayMS < $1.delayMS }
        }.first
        guard let entering, entering.delayMS < span else { return nil }
        let whooshLength = Int((Double(entering.lengthMS) * 1.2).rounded())
        cues.append(TitleSoundCue(.whoosh, atMS: entering.delayMS,
                                  lengthMS: min(max(whooshLength, Self.whooshLengthRange.lowerBound),
                                                Self.whooshLengthRange.upperBound)))

        // The ticks: each small accent, at the moment it reads as landed.
        let frameArea = max(canvasSize.width * canvasSize.height, 1)
        var lands: [Int] = []
        for part in design.parts where part.role == .accent {
            guard let build = part.in, let piece = TitleDesign.find(part.path, in: title) else { continue }
            let area = abs(piece.frame.width * piece.frame.height)
            guard area / frameArea < Self.smallAccentShare else { continue }
            let at = build.delayMS + Int((Double(build.lengthMS) * Self.landedShare(build.curve)).rounded())
            if at < span { lands.append(at) }
        }
        var kept: [Int] = []
        for at in lands.sorted() where kept.count < Self.mostTicks {
            if let last = kept.last, at - last < Self.tickSpacingMS { continue }
            kept.append(at)
        }
        cues += kept.map { TitleSoundCue(.tick, atMS: $0, lengthMS: Self.tickLengthMS) }
        self.init(cues: cues, energy: recipe.energy)
    }

    /// How far through a move on `curve` the thing moving reads as arrived:
    /// nine tenths of the way there. An expo ease is home in well under half
    /// its length, and a tick at the very end of it would land late.
    static func landedShare(_ curve: EasingCurve) -> Double {
        for step in 1...20 {
            let t = Double(step) / 20
            if curve.value(at: t) >= 0.9 { return t }
        }
        return 1
    }

    /// How long the whole score runs.
    public var lengthMS: Int { cues.map(\.endMS).max() ?? 0 }

    /// The sound this score is, the same every time it is worked out: two
    /// titles that sound alike share one file, and a document read back
    /// finds the file it was playing.
    public var soundID: UUID {
        var text = "photonz-title-sounds-1|\(energy.rawValue)"
        for cue in cues { text += "|\(cue.kind.rawValue):\(cue.atMS):\(cue.lengthMS)" }
        return Self.stableUUID(text)
    }

    public var soundRef: SoundRef { SoundRef(id: soundID, durationMS: lengthMS) }

    /// A name-based id: two 64 bit FNV-1a hashes of the text, marked as a
    /// version 8 (custom) UUID.
    static func stableUUID(_ text: String) -> UUID {
        func fnv(_ seed: UInt64) -> UInt64 {
            var hash = seed
            for byte in text.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100_0000_01B3
            }
            return hash
        }
        let a = fnv(0xCBF2_9CE4_8422_2325), b = fnv(0x8422_2325_CBF2_9CE4)
        var bytes = (0..<8).map { UInt8(truncatingIfNeeded: a >> (8 * $0)) }
            + (0..<8).map { UInt8(truncatingIfNeeded: b >> (8 * $0)) }
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

/// What makes a sound layer a title's: which title, and the score it plays.
public struct TitleSoundLink: Hashable, Codable, Sendable {
    public var titleID: UUID
    public var score: TitleSoundScore

    public init(titleID: UUID, score: TitleSoundScore) {
        self.titleID = titleID
        self.score = score
    }
}

extension TitleRecipe {
    /// Whether this title plays its whoosh and ticks. Off until somebody
    /// turns it on.
    public var playsSounds: Bool { sounds == true }
}

// MARK: - Keeping the bar under its title

extension PhotonzDocument {

    /// Every score a document's title sounds play, by the sound each one is:
    /// what the app makes files from.
    public var titleSoundScores: [UUID: TitleSoundScore] {
        var found: [UUID: TitleSoundScore] = [:]
        forEachLayer { layer in
            if let score = layer.titleSound?.score { found[score.soundID] = score }
        }
        return found
    }

    /// Turn a title's sounds on or off. False when it was already so, or the
    /// layer is not a title.
    @discardableResult
    public mutating func setTitleSounds(layerID: UUID, on: Bool) -> Bool {
        guard let recipe = titleRecipe(layerID: layerID), recipe.playsSounds != on else { return false }
        updateLayer(id: layerID) { edited in
            guard case .group(var content) = edited.content else { return }
            content.titleRecipe?.sounds = on ? true : nil
            edited.content = .group(content)
        }
        keepTitleSoundsInStep()
        return true
    }

    /// Put every title's bar of sound where its title says, as the last part
    /// of an edit. `was` is the document before the edit: a bar it had that
    /// somebody has since deleted, under a title still there, turns that
    /// title's sounds off rather than coming straight back.
    public mutating func keepTitleSoundsInStep(since was: PhotonzDocument? = nil) {
        var titles: [Layer] = []
        var bars: [UUID: [Layer]] = [:]
        forEachLayer { layer in
            if let link = layer.titleSound {
                bars[link.titleID, default: []].append(layer)
            } else if layer.group?.titleRecipe?.playsSounds == true, layer.time != nil {
                titles.append(layer)
            }
        }
        guard !titles.isEmpty || !bars.isEmpty else { return }

        // A bar deleted by hand is somebody saying they do not want it.
        if let was {
            var hadBar: Set<UUID> = []
            was.forEachLayer { layer in
                if let link = layer.titleSound { hadBar.insert(link.titleID) }
            }
            let deliberate = Set(titles.map(\.id).filter { hadBar.contains($0) && bars[$0] == nil })
            if !deliberate.isEmpty {
                for id in deliberate {
                    updateLayer(id: id) { edited in
                        guard case .group(var content) = edited.content else { return }
                        content.titleRecipe?.sounds = nil
                        edited.content = .group(content)
                    }
                }
                titles.removeAll { deliberate.contains($0.id) }
            }
        }

        var gone: Set<UUID> = []
        for title in titles {
            let owned = bars.removeValue(forKey: title.id) ?? []
            guard let recipe = title.group?.titleRecipe, let time = title.time,
                  let score = TitleSoundScore(title: title, recipe: recipe, canvasSize: canvasSize) else {
                gone.formUnion(owned.map(\.id))
                continue
            }
            let length = max(LayerTime.shortestMS, min(score.lengthMS, time.lengthMS))
            let wanted = LayerTime(inMS: time.inMS, outMS: time.inMS + length,
                                   sourceInMS: 0, sourceLengthMS: score.lengthMS)
            let link = TitleSoundLink(titleID: title.id, score: score)
            if let bar = owned.first {
                gone.formUnion(owned.dropFirst().map(\.id))
                guard bar.time != wanted || bar.titleSound != link || bar.sound != score.soundRef
                        || bar.cuts != nil else { continue }
                updateLayer(id: bar.id) { edited in
                    edited.content = .sound(score.soundRef)
                    edited.time = wanted
                    edited.cuts = nil
                    edited.titleSound = link
                }
            } else {
                var bar = Layer.sound(score.soundRef, name: TitleSoundScore.barName, time: wanted)
                bar.titleSound = link
                addLayer(bar)
            }
        }
        // Bars whose title is gone or has its sounds off.
        for owned in bars.values { gone.formUnion(owned.map(\.id)) }
        if !gone.isEmpty { removeLayers(ids: gone) }
    }
}
