import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The panel's order in a document with time is a RULE about what the picked
/// layer is for, not a list somebody keeps by hand (`TimePanelOrder.swift`).
///
/// Written before the rule. Every video section shipped at the bottom of the
/// panel because each one was appended to a hand-kept order: Sound's level
/// fader lowest in the dock, Speed under six sections, a title's fade below
/// the fold at 1080.
@Suite("What the panel leads with in a document with time")
struct TimePanelOrderTests {

    // MARK: - Fixtures

    static let saved = ["layers", "measureTool", "arrange", "component", "text", "geometry",
                        "color", "effects", "keys", "reframe", "motion", "editPoint",
                        "transition", "speed", "sound", "fades", "gain", "soundEffects", "captions",
                        "library"]

    static func clip() -> Layer {
        var layer = Layer(name: "Recording",
                          content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#000000")),
                          frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        layer.movie = MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 8000, hasSound: true)
        layer.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 8000)
        return layer
    }

    static func title() -> Layer {
        var layer = Layer(name: "Hello",
                          content: .text(TextContent(string: "Hello")),
                          frame: CGRect(x: 10, y: 10, width: 200, height: 40))
        layer.time = LayerTime(inMS: 1000, outMS: 4000)
        return layer
    }

    static func sound() -> Layer {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        let id = doc.addSound(SoundRef(durationMS: 4000), name: "music", atMS: 0)
        return doc.layer(id: id) ?? Layer(name: "missing", content: .text(TextContent(string: "")),
                                          frame: .zero)
    }

    static func still() -> Layer {
        Layer(name: "Box",
              content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FF0000")),
              frame: CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    // MARK: - What a layer is for

    @Test func aRecordingIsForPlaying() {
        #expect(TimePanelOrder.role(of: Self.clip()) == .playing)
    }

    @Test func aTitleIsForBeingRead() {
        #expect(TimePanelOrder.role(of: Self.title()) == .onScreen)
    }

    @Test func aSoundIsForBeingHeard() {
        #expect(TimePanelOrder.role(of: Self.sound()) == .heard)
    }

    static func captions() -> Layer {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        doc.addLayer(clip())
        doc.landCaptions(CaptionCues.cues(from: [
            TranscribedWord("Capture", startMS: 200, endMS: 700),
            TranscribedWord("it.", startMS: 700, endMS: 1_200),
        ]))
        return doc.captionsLayers.first ?? still()
    }

    @Test func aCaptionsLayerIsForCaptioningAndSoIsOneOfItsCues() {
        let layer = Self.captions()
        #expect(layer.isCaptionsLayer)
        #expect(TimePanelOrder.role(of: layer) == .captioned)
        #expect(layer.children.first.flatMap { TimePanelOrder.role(of: $0) } == .captioned)
    }

    @Test func aLayerWithNoTimeHasNoRoleAndTheOrderIsLeftAlone() {
        #expect(TimePanelOrder.role(of: Self.still()) == nil)
        #expect(TimePanelOrder.arrange(Self.saved, for: nil) == Self.saved)
    }

    // MARK: - What each role leads with

    // Every role opens on Properties (raw id `keys`): the clip line and what
    // is animating, as `video.html` draws its dock (2026-09-25).

    @Test func aClipLeadsWithItsPropertiesThenHowItPlays() {
        let order = TimePanelOrder.arrange(Self.saved, for: .playing)
        #expect(Array(order.prefix(3)) == ["layers", "keys", "speed"])
    }

    /// A video clip is a picture first: its sound sections come AFTER how it
    /// looks, never ahead of it (the user, 2026-10-03: "when i right click on
    /// a video clip, it gives me audio options. I only expect that on audio
    /// clips"). `video.html` draws no Audio section for a video clip at all.
    @Test func aClipsSoundComesAfterItsPicture() {
        let order = TimePanelOrder.arrange(Self.saved, for: .playing)
        let effects = order.firstIndex(of: "effects") ?? -1
        let color = order.firstIndex(of: "color") ?? -1
        for sound in ["sound", "fades", "gain", "soundEffects"] {
            let at = order.firstIndex(of: sound) ?? -1
            #expect(at > effects && at > color, "\(sound) sits under the picture")
        }
        let effectsAt = order.firstIndex(of: "effects") ?? 0
        #expect(Array(order[(effectsAt + 1)...].prefix(4)) == ["sound", "fades", "gain", "soundEffects"])
    }

    @Test func withNoPictureSectionAClipsSoundStaysWhereItWasSaved() {
        let order = TimePanelOrder.arrange(["layers", "keys", "speed", "sound", "fades", "captions"],
                                           for: .playing)
        #expect(order == ["layers", "keys", "speed", "sound", "fades", "captions"])
    }

    /// A clip's sound sections say whose sound they are, so Fades on a video
    /// is never read as the picture fading. A sound's own keep the mock's
    /// names.
    @Test func aClipsSoundSectionsAreNamedAsItsAudio() {
        #expect(TimePanelOrder.title("sound", shown: "Channel", for: .playing) == "Audio")
        #expect(TimePanelOrder.title("fades", shown: "Fades", for: .playing) == "Audio Fades")
        #expect(TimePanelOrder.title("gain", shown: "Gain", for: .playing) == "Audio Gain")
        #expect(TimePanelOrder.title("soundEffects", shown: "Audio Effects", for: .playing) == "Audio Effects")
        #expect(TimePanelOrder.title("speed", shown: "Time", for: .playing) == "Time")
        #expect(TimePanelOrder.title("fades", shown: "Fades", for: .heard) == "Fades")
        #expect(TimePanelOrder.title("sound", shown: "Channel", for: .heard) == "Channel")
        #expect(TimePanelOrder.title("fades", shown: "Fades", for: nil) == "Fades")
    }

    @Test func aTitleLeadsWithItsPropertiesThenWhenItIsOnThenItsWords() {
        let order = TimePanelOrder.arrange(Self.saved, for: .onScreen)
        #expect(Array(order.prefix(4)) == ["layers", "keys", "speed", "text"])
    }

    @Test func aSoundLeadsWithItsPropertiesThenItsLevelThenItsTime() {
        let order = TimePanelOrder.arrange(Self.saved, for: .heard)
        #expect(Array(order.prefix(7)) == ["layers", "keys", "sound", "fades", "gain", "soundEffects",
                                           "speed"])
    }

    /// The captions mock opens its panel on the captions' own options, then
    /// their style (`video-captions.html`, Properties).
    @Test func aCaptionLeadsWithTheCaptionsOptionsThenItsType() {
        let order = TimePanelOrder.arrange(Self.saved, for: .captioned)
        #expect(Array(order.prefix(4)) == ["layers", "captions", "text", "keys"])
    }

    /// Fades sit straight under Sound wherever Sound leads, as the audio mock
    /// draws its channel strip: the level, then the fades.
    @Test func fadesFollowTheLevelWhereverItLeads() {
        for role in TimePanelOrder.Role.allCases {
            let lead = TimePanelOrder.leads(role) + TimePanelOrder.trails(role)
            guard let sound = lead.firstIndex(of: "sound") else { continue }
            #expect(lead.indices.contains(sound + 1) && lead[sound + 1] == "fades")
        }
    }

    /// Gain sits straight under Fades, in the audio mock's per-selection slot
    /// under the channel strip (`#chExtra`), so the strip keeps its one Volume.
    @Test func gainFollowsTheFadesWhereverTheyLead() {
        for role in TimePanelOrder.Role.allCases {
            let lead = TimePanelOrder.leads(role) + TimePanelOrder.trails(role)
            guard let fades = lead.firstIndex(of: "fades") else { continue }
            #expect(lead.indices.contains(fades + 1) && lead[fades + 1] == "gain")
        }
    }

    /// The sound's Effects list sits straight under Gain, the last of the
    /// sound's own sections, as the audio mock stacks its Effects group under
    /// the channel strip (`#gEffects`).
    @Test func theSoundsEffectsFollowItsGainWhereverItLeads() {
        for role in TimePanelOrder.Role.allCases {
            let lead = TimePanelOrder.leads(role) + TimePanelOrder.trails(role)
            guard let gain = lead.firstIndex(of: "gain") else { continue }
            #expect(lead.indices.contains(gain + 1) && lead[gain + 1] == "soundEffects")
        }
    }

    // MARK: - What the rule never does

    @Test func everythingElseKeepsTheOrderItWasSavedIn() {
        for role in TimePanelOrder.Role.allCases {
            let order = TimePanelOrder.arrange(Self.saved, for: role)
            let lead = Set(TimePanelOrder.leads(role) + TimePanelOrder.trails(role))
            #expect(order.filter { !lead.contains($0) } == Self.saved.filter { !lead.contains($0) })
            #expect(order.sorted() == Self.saved.sorted(), "nothing is lost or doubled")
        }
    }

    @Test func aLeadSectionTheSavedOrderDoesNotHaveIsNotInvented() {
        let order = TimePanelOrder.arrange(["layers", "geometry", "speed"], for: .playing)
        #expect(order == ["layers", "speed", "geometry"])
    }

    @Test func withNoLayersSectionTheLeadGoesToTheTop() {
        let order = TimePanelOrder.arrange(["geometry", "keys", "speed"], for: .playing)
        #expect(order == ["keys", "speed", "geometry"])
    }

    @Test func theRuleIsWrittenDownForEveryRole() {
        for role in TimePanelOrder.Role.allCases {
            #expect(!TimePanelOrder.leads(role).isEmpty)
            #expect(!role.purpose.isEmpty)
        }
    }
}

/// The Time section says what a speed did in values, not sentences.
@Suite("Short readings for the Time section")
struct ClipSpeedValueTests {

    @Test func theSoundIsOneWord() {
        #expect(ClipSpeedSound.asRecorded.word == "As recorded")
        #expect(ClipSpeedSound.pitchedUp.word == "Higher")
        #expect(ClipSpeedSound.pitchedDown.word == "Lower")
        #expect(ClipSpeedSound.silentTooFast.word == "Silent")
        #expect(ClipSpeedSound.silentTooSlow.word == "Silent")
        #expect(ClipSpeedSound.silentHeld.word == "Silent")
    }

    @Test func theLengthIsSourceIntoTimeline() {
        let fast = ClipPiece(sourceInMS: 0, lengthMS: 2000, speedPercent: 400)
        #expect(ClipSpeedReading(fast).lengthValue == "8s \u{2192} 2s")
        let normal = ClipPiece(sourceInMS: 0, lengthMS: 3000)
        #expect(ClipSpeedReading(normal).lengthValue == "3s")
    }

    @Test func aSpeedInTheMenuSaysWhenItIsSilent() {
        #expect(ClipSpeed.menuTitle(100) == "Normal")
        #expect(ClipSpeed.menuTitle(400) == "4x (silent)")
        #expect(ClipSpeed.menuTitle(25) == "0.25x (silent)")
    }
}
