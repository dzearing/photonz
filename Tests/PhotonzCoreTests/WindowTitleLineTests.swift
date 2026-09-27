import CoreGraphics
import Foundation
import Testing

@testable import PhotonzCore

/// The one quiet line a video window's title bar carries: the project name,
/// the picture size, the length, and saved or edited, the way the video mocks
/// draw it (`video.html`: "launch-teaser · 1920 x 1080 · 0:15 · saved").
@Suite("A video window's title line")
struct WindowTitleLineTests {

    @Test("An opened recording reads name, size, length and saved, as the mock draws it")
    func readsLikeTheMock() {
        let line = WindowTitleLine(fileName: "launch-teaser.mp4",
                                   pictureSize: CGSize(width: 1920, height: 1080),
                                   lengthMS: 15_400,
                                   affordance: .upToDate)
        #expect(line.name == "launch-teaser")
        #expect(line.details == "1920 x 1080 · 0:15")
        #expect(line.state == .saved)
        #expect(line.text == "launch-teaser · 1920 x 1080 · 0:15 · saved")
    }

    @Test("The length reads the way the transport's end does, whole seconds rounded down")
    func lengthMatchesTheTransport() {
        #expect(WindowTitleLine.clock(20_940) == "0:20")
        #expect(WindowTitleLine.clock(0) == "0:00")
        #expect(WindowTitleLine.clock(75_000) == "1:15")
        #expect(WindowTitleLine.clock(3_723_000) == "1:02:03")
    }

    @Test("Anything closing would lose reads edited; only a document matching disk reads saved")
    func savedOrEdited() {
        func state(_ affordance: SaveAffordance) -> WindowTitleLine.SaveState? {
            WindowTitleLine(fileName: "a.mov", pictureSize: CGSize(width: 10, height: 10),
                            lengthMS: 1000, affordance: affordance).state
        }
        #expect(state(.upToDate) == .saved)
        #expect(state(.unsavedChanges) == .edited)
        #expect(state(.unsavedRecording) == .edited)
        #expect(state(.saving) == .edited)
        // Still reading its own length: nothing to claim either way yet.
        #expect(state(.nothingToSave) == nil)
        // The rule the line exists for: it says edited exactly when closing
        // would stop and ask.
        for affordance in SaveAffordance.allCases where affordance != .nothingToSave {
            #expect((state(affordance) == .edited) == affordance.asksBeforeClosing)
        }
    }

    @Test("A new video nobody has saved or changed claims neither saved nor edited")
    func neverSavedSaysNeither() {
        let fresh = WindowTitleLine(fileName: "Untitled 1", pictureSize: CGSize(width: 1920, height: 1080),
                                    lengthMS: 10_000, affordance: .upToDate, hasFile: false)
        #expect(fresh.state == nil)
        #expect(fresh.text == "Untitled 1 · 1920 x 1080 · 0:10")
        let touched = WindowTitleLine(fileName: "Untitled 1", pictureSize: CGSize(width: 1920, height: 1080),
                                      lengthMS: 12_000, affordance: .unsavedChanges, hasFile: false)
        #expect(touched.state == .edited)
    }

    @Test("A saved project is named without its package extension")
    func projectName() {
        let line = WindowTitleLine(fileName: "My Edit.photonz",
                                   pictureSize: CGSize(width: 1280, height: 720),
                                   lengthMS: 9_000, affordance: .upToDate)
        #expect(line.text == "My Edit · 1280 x 720 · 0:09 · saved")
    }

    @Test("A name with no extension, or dots of its own, keeps all of itself")
    func namesWithDots() {
        #expect(WindowTitleLine(fileName: "Untitled 2", pictureSize: nil, lengthMS: nil,
                                affordance: .nothingToSave).name == "Untitled 2")
        #expect(WindowTitleLine(fileName: "v1.2 teaser.mp4", pictureSize: nil, lengthMS: nil,
                                affordance: .nothingToSave).name == "v1.2 teaser")
    }

    @Test("What is not known yet is left out rather than shown as a zero")
    func unknownsAreLeftOut() {
        let loading = WindowTitleLine(fileName: "clip.mov", pictureSize: nil, lengthMS: nil,
                                      affordance: .nothingToSave)
        #expect(loading.details == "")
        #expect(loading.text == "clip")
        let noLength = WindowTitleLine(fileName: "clip.mov",
                                       pictureSize: CGSize(width: 800, height: 600),
                                       lengthMS: 0, affordance: .upToDate)
        #expect(noLength.text == "clip · 800 x 600 · saved")
    }

    @Test("A fractional picture size reads as whole pixels")
    func wholePixels() {
        let line = WindowTitleLine(fileName: "a.mov",
                                   pictureSize: CGSize(width: 1919.6, height: 1080.2),
                                   lengthMS: 1000, affordance: .upToDate)
        #expect(line.details == "1920 x 1080 · 0:01")
    }
}
