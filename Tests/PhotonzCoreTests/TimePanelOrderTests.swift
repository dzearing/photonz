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
                        "transition", "speed", "sound", "captions", "library"]

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

    @Test func aLayerWithNoTimeHasNoRoleAndTheOrderIsLeftAlone() {
        #expect(TimePanelOrder.role(of: Self.still()) == nil)
        #expect(TimePanelOrder.arrange(Self.saved, for: nil) == Self.saved)
    }

    // MARK: - What each role leads with

    @Test func aClipLeadsWithHowItPlaysThenHowLoudThenWhatIsKeyed() {
        let order = TimePanelOrder.arrange(Self.saved, for: .playing)
        #expect(Array(order.prefix(4)) == ["layers", "speed", "sound", "keys"])
    }

    @Test func aTitleLeadsWithWhenItIsOnThenItsWordsThenWhatIsKeyed() {
        let order = TimePanelOrder.arrange(Self.saved, for: .onScreen)
        #expect(Array(order.prefix(4)) == ["layers", "speed", "text", "keys"])
    }

    @Test func aSoundLeadsWithItsLevelThenItsTime() {
        let order = TimePanelOrder.arrange(Self.saved, for: .heard)
        #expect(Array(order.prefix(3)) == ["layers", "sound", "speed"])
    }

    // MARK: - What the rule never does

    @Test func everythingElseKeepsTheOrderItWasSavedIn() {
        for role in TimePanelOrder.Role.allCases {
            let order = TimePanelOrder.arrange(Self.saved, for: role)
            let lead = Set(TimePanelOrder.leads(role))
            #expect(order.filter { !lead.contains($0) } == Self.saved.filter { !lead.contains($0) })
            #expect(order.sorted() == Self.saved.sorted(), "nothing is lost or doubled")
        }
    }

    @Test func aLeadSectionTheSavedOrderDoesNotHaveIsNotInvented() {
        let order = TimePanelOrder.arrange(["layers", "geometry", "speed"], for: .playing)
        #expect(order == ["layers", "speed", "geometry"])
    }

    @Test func withNoLayersSectionTheLeadGoesToTheTop() {
        let order = TimePanelOrder.arrange(["geometry", "sound", "speed"], for: .playing)
        #expect(order == ["speed", "sound", "geometry"])
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
        #expect(ClipSpeed.menuTitle(400) == "4x Speed (silent)")
        #expect(ClipSpeed.menuTitle(25) == "Quarter Speed (silent)")
    }
}
