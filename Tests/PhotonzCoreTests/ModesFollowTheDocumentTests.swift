import Foundation
import Testing
@testable import PhotonzCore

/// The mode list offers only what fits what is open (the user, 2026-10-17: "i
/// open an image and the top left dropdown says 'video'. WTF is this... Redline
/// should just be 'Image' and it should be the default mode for images...
/// when you open a video, you shouldn't see the dropdown. it makes no sense if
/// only one mode is relevant").
///
/// Three facts hold that up:
///
/// 1. A picture is offered Image, Icon and Design, in that order, and starts in
///    Image. Video is not among them.
/// 2. A document with time has one setup, the video one, and no list at all,
///    so the window draws no chip for it and a mode key changes nothing.
/// 3. The mode is the WINDOW's, so one window picking Video for a recording
///    cannot reach the next picture. What older builds wrote down (one mode for
///    the whole app, `{"modeID":"video"}` on the user's Mac) is read back as
///    arrangements only, never as the mode a new window starts in.
struct ModesFollowTheDocumentTests {

    // MARK: 1 · a picture

    @Test("A picture is offered Image, Icon and Design, in that order, and no Video")
    func aPictureIsOfferedImageIconDesign() {
        let offered = WindowModes.offered(hasTime: false)
        #expect(offered.map(\.id) == [WindowModes.imageID, "icon", "design"])
        #expect(offered.map(\.title) == ["Image", "Icon", "Design"])
        #expect(!offered.contains { $0.id == WindowModes.videoID })
        // Control 1 Image, Control 2 Icon, Control 3 Design.
        #expect(WindowModes.shortcutNumber(for: WindowModes.imageID) == 1)
        #expect(WindowModes.shortcutNumber(for: "icon") == 2)
        #expect(WindowModes.shortcutNumber(for: "design") == 3)
    }

    @Test("Redline is called Image now, and Image folds nothing")
    func redlineIsImage() {
        #expect(WindowModes.mode("redline") == nil)
        #expect(!WindowModes.all.contains { $0.title == "Redline" })
        #expect(WindowModes.image.title == "Image")
        #expect(!WindowModes.image.preset.hasAnyCustom)
        #expect(WindowModes.image.toolStrip == nil)
    }

    @Test("A new window starts a picture in Image, whatever another window picked")
    func aNewPictureWindowStartsInImage() {
        var recording = WindowModeSession()
        // The recording's window cannot be put in a picture's mode at all.
        let swapped1 = recording.swap(to: "design", hasTime: true)
        #expect(!swapped1)
        #expect(recording.modeID(hasTime: true) == WindowModes.videoID)

        var other = WindowModeSession()
        other.swap(to: "design", hasTime: false)
        // A second window is its own session, so it starts where every
        // picture starts.
        let fresh = WindowModeSession()
        #expect(fresh.modeID(hasTime: false) == WindowModes.imageID)
        #expect(other.modeID(hasTime: false) == "design")
    }

    @Test("A picture window cannot be put in Video")
    func aPictureCannotBeInVideo() {
        var session = WindowModeSession()
        let swapped2 = session.swap(to: WindowModes.videoID, hasTime: false)
        #expect(!swapped2)
        #expect(session.modeID(hasTime: false) == WindowModes.imageID)
        // Nor can it be started there.
        let started = WindowModeSession(pickedID: WindowModes.videoID)
        #expect(started.modeID(hasTime: false) == WindowModes.imageID)
    }

    // MARK: 2 · a document with time

    @Test("A document with time has one setup and no list, so no chip")
    func aRecordingHasNoList() {
        #expect(WindowModes.offered(hasTime: true).isEmpty)
        #expect(!WindowModeSession.showsChip(hasTime: true))
        #expect(WindowModeSession.showsChip(hasTime: false))
        // Whatever the window picked while it held a picture, a recording is
        // in the video setup, with the video's folds.
        var session = WindowModeSession()
        session.swap(to: "icon", hasTime: false)
        #expect(session.modeID(hasTime: true) == WindowModes.videoID)
        #expect(session.mode(hasTime: true).preset == WindowModes.mode(WindowModes.videoID)?.preset)
        // And a mode key does nothing to it.
        let swapped3 = session.swap(to: WindowModes.imageID, hasTime: true)
        #expect(!swapped3)
        #expect(session.modeID(hasTime: false) == "icon")
    }

    @Test("Use Automatic for All in a recording unfolds its own setup and stays in it")
    func automaticForAllInARecording() {
        var session = WindowModeSession()
        var arrangements = WindowModeArrangements()
        session.showEverything(hasTime: true, arrangements: &arrangements)
        #expect(session.modeID(hasTime: true) == WindowModes.videoID)
        #expect(!arrangements.arrangement(of: WindowModes.videoID).hasAnyCustom)
        // The picture modes are untouched by it.
        #expect(!arrangements.isBent(WindowModes.imageID))
    }

    // MARK: 3 · what older builds wrote down

    @Test("The user's saved Video mode does not carry to the next picture")
    func savedVideoIsNotWhereAPictureStarts() {
        // Exactly what the user's Mac held on 2026-10-17.
        let migrated = WindowModeArrangements.migrating(
            legacySession: #"{"bends":{},"modeID":"video"}"#,
            livePanel: "columns=0;measurements=0;placement=0")
        // The live panel was the Video preset unbent, so nothing is bent.
        #expect(migrated == WindowModeArrangements())
        #expect(WindowModeSession().modeID(hasTime: false) == WindowModes.imageID)
    }

    @Test("A bent arrangement an older build was holding comes across under the mode's new name")
    func oldBendsComeAcross() {
        let migrated = WindowModeArrangements.migrating(
            legacySession: #"{"bends":{"icon":"columns=0;library=0","everything":"motion=0","redline":"motion=0;component=0","gone":"arrange=0"},"modeID":"design"}"#,
            livePanel: "shadow=0")
        #expect(migrated.arrangement(of: "icon") == PanelSectionVisibility.Choices(stored: "columns=0;library=0"))
        // Everything is Image now.
        #expect(migrated.arrangement(of: WindowModes.imageID) == PanelSectionVisibility.Choices(stored: "motion=0"))
        // The live panel was Design, bent by hand, and is kept for Design.
        #expect(migrated.arrangement(of: "design") == PanelSectionVisibility.Choices(stored: "shadow=0"))
        // Redline's arrangement folded things for a narrower job than Image's,
        // and a mode that does not ship is gone, so neither comes across.
        #expect(migrated.isBent("icon"))
        #expect(!migrated.isBent(WindowModes.videoID))
    }

    @Test("A panel bent while in Everything, with no mode ever picked, is Image's")
    func neverPickedAMode() {
        let migrated = WindowModeArrangements.migrating(legacySession: nil, livePanel: "motion=0")
        #expect(migrated.arrangement(of: WindowModes.imageID) == PanelSectionVisibility.Choices(stored: "motion=0"))
        #expect(WindowModeArrangements.migrating(legacySession: nil, livePanel: nil) == WindowModeArrangements())
        // A live panel held while in Redline was Redline's, and does not
        // become Image's.
        let fromRedline = WindowModeArrangements.migrating(
            legacySession: #"{"bends":{},"modeID":"redline"}"#,
            livePanel: "motion=0;component=0;placement=0;columns=0")
        #expect(fromRedline == WindowModeArrangements())
        // Nonsense is nothing.
        #expect(WindowModeArrangements.migrating(legacySession: "{not json", livePanel: "")
                == WindowModeArrangements())
    }
}
