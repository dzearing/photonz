import Testing
@testable import PhotonzCore

/// A menu item that is simply on or off keeps ONE name and wears a checkmark.
/// These tests hold that line: a name that announces its own state is the bug.
@Suite struct MenuToggleNamesTests {
    // MARK: One name each

    @Test func everyToggleKeepsTheNameItAlreadyHad() {
        #expect(MenuToggleNames.grid == "Show Grid")
        #expect(MenuToggleNames.snapToGrid == "Snap to Grid")
        #expect(MenuToggleNames.layersPanel == "Show Layers")
        #expect(MenuToggleNames.library == "Show Library")
        #expect(MenuToggleNames.history == "Show History")
    }

    /// A row in a list is already the thing, so its menu says what the row IS
    /// rather than what a click would do to it.
    @Test func aRowSaysWhatItIsRatherThanWhatAClickWouldDo() {
        #expect(MenuToggleNames.layerVisible == "Visible")
        #expect(MenuToggleNames.layerLocked == "Locked")
    }

    // MARK: None of them says its own state

    /// The whole point: no reading of any of these tells you the state, because
    /// the checkmark does. A name that starts with Hide, Stop or Un is a name
    /// that flipped.
    @Test func noNameAnnouncesTheStateItIsIn() {
        for name in MenuToggleNames.all {
            #expect(!name.hasPrefix("Hide "), "\(name) reads as the off half of a pair")
            #expect(!name.hasPrefix("Stop "), "\(name) reads as the off half of a pair")
            #expect(!name.hasPrefix("Un"), "\(name) reads as the off half of a pair")
            #expect(!name.contains("/"), "\(name) offers two readings at once")
        }
    }

    /// Every on/off item in the app is listed here, so one added later without
    /// a name in this file shows up as a missing entry rather than silently
    /// growing its own flip.
    @Test func everyOnOffItemInTheAppIsAccountedFor() {
        #expect(MenuToggleNames.all.count == 7)
        #expect(Set(MenuToggleNames.all).count == 7)
    }

    // MARK: The capture menus agree with it

    @Test func theHistoryItemIsNamedOnceForBothMenus() {
        #expect(CaptureMenuNames.history == MenuToggleNames.history)
    }

    /// Starting and stopping a recording are two different actions, not one
    /// setting, so that pair keeps its flip.
    @Test func recordingIsAnActionPairAndKeepsItsFlip() {
        #expect(CaptureMenuNames.recording(isRecording: false) == "Record Screen / Video…")
        #expect(CaptureMenuNames.recording(isRecording: true) == "Stop Recording")
    }
}
