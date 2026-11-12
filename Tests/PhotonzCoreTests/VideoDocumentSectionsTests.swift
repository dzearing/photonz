import PhotonzCore
import Testing

/// On a video, Captions and Transitions show only where they apply to what is
/// picked (`VideoDocumentSections.swift`). Written before the rule: both sat
/// under every pick, so a sound's Fades fell under the fold on a laptop window
/// and a picked arrow carried the document's captions form under its own rows.
@Suite("Where Captions and Transitions show on a video")
struct VideoDocumentSectionsTests {

    static let clipPanel = ["layers", "keys", "speed", "color", "effects", "sound", "fades",
                            "gain", "soundEffects", "captions", "transitions", "library"]

    @Test func nothingPickedShowsTheCaptionsAndNoTiles() {
        #expect(VideoDocumentSections.shows("captions", for: .nothing) == true)
        #expect(VideoDocumentSections.shows("transitions", for: .nothing) == false)
    }

    @Test func captionsPickedShowTheirOwnSection() {
        #expect(VideoDocumentSections.shows("captions", for: .captions) == true)
        #expect(VideoDocumentSections.shows("transitions", for: .captions) == false)
    }

    @Test func aCutPickedShowsTheTilesAndNoCaptions() {
        #expect(VideoDocumentSections.shows("transitions", for: .cut) == true)
        #expect(VideoDocumentSections.shows("captions", for: .cut) == false)
    }

    @Test func aClipTitleSoundOrGraphicPickedShowsNeither() {
        #expect(VideoDocumentSections.shows("captions", for: .other) == false)
        #expect(VideoDocumentSections.shows("transitions", for: .other) == false)
    }

    @Test func everyOtherSectionIsLeftToThePanel() {
        for pick: VideoDocumentSections.Pick in [.nothing, .captions, .cut, .other] {
            #expect(VideoDocumentSections.shows("fades", for: pick) == nil)
            #expect(VideoDocumentSections.shows("library", for: pick) == nil)
        }
    }

    @Test func aPickedClipEndsOnItsAudioThenTheLibrary() {
        #expect(VideoDocumentSections.filter(Self.clipPanel, for: .other)
                == ["layers", "keys", "speed", "color", "effects", "sound", "fades",
                    "gain", "soundEffects", "library"])
    }

    @Test func filteringKeepsTheOrder() {
        #expect(VideoDocumentSections.filter(["transitions", "keys", "captions", "library"], for: .cut)
                == ["transitions", "keys", "library"])
    }
}
