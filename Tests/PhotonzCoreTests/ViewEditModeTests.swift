import CoreGraphics
import Testing
@testable import PhotonzCore

// View mode and Edit mode: a recording opens to watch, one switch brings the
// editor (queue task view-mode-and-edit-mode-a-recording-opens-to-wat,
// 2026-09-28). Replaced the tucked-away timeline of 2026-09-25, which only
// folded the tracks and remembered the last choice for the next recording.
@Suite("Which mode a document opens in")
struct ViewEditModeOpeningTests {

    private func movie() -> MovieRef {
        MovieRef(pixelSize: CGSize(width: 1280, height: 800), durationMS: 8000)
    }

    @Test("a fresh recording opens in View")
    func freshRecordingWatches() {
        let document = PhotonzDocument.recording(movie(), name: "Recording")
        #expect(ViewEditMode.opening(document) == .view)
    }

    @Test("there is nothing remembered: every fresh recording opens in View")
    func nothingRemembered() {
        // The mode is decided from the document alone, so a person who went to
        // Edit on the last recording still lands in View on the next one.
        let first = PhotonzDocument.recording(movie(), name: "First")
        let second = PhotonzDocument.recording(movie(), name: "Second")
        #expect(ViewEditMode.opening(first) == .view)
        #expect(ViewEditMode.opening(second) == .view)
    }

    @Test("a recording somebody has already trimmed reopens in Edit")
    func trimmedReopensInEdit() throws {
        var document = PhotonzDocument.recording(movie(), name: "Recording")
        let clipID = try #require(document.allLayers.first(where: \.isClip)?.id)
        let clip = try #require(document.layer(id: clipID))
        var session = try #require(ClipTrimSession(layer: clip))
        session.dragOut(toMS: 6000)
        _ = document.applyTrim(session)
        #expect(document.isUntouchedRecording == false)
        #expect(ViewEditMode.opening(document) == .edit)
    }

    @Test("a recording cut into pieces reopens in Edit")
    func cutReopensInEdit() throws {
        var document = PhotonzDocument.recording(movie(), name: "Recording")
        let clipID = try #require(document.allLayers.first(where: \.isClip)?.id)
        let didSplit = document.splitClip(clipID, atMS: 3000)
        #expect(didSplit)
        #expect(ViewEditMode.opening(document) == .edit)
    }

    @Test("a guide's sample opens in Edit, because its cards point at the tracks")
    func guideOpensInEdit() {
        let document = PhotonzDocument.recording(movie(), name: "Recording")
        #expect(ViewEditMode.opening(document, forAGuide: true) == .edit)
    }

    @Test("a picture has no View mode")
    func pictureIsEdit() {
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [])
        #expect(document.isUntouchedRecording == false)
        #expect(ViewEditMode.opening(document) == .edit)
        #expect(ViewEditMode.applies(to: document) == false)
    }

    @Test("a document with time offers both modes")
    func recordingOffersModes() {
        let document = PhotonzDocument.recording(movie(), name: "Recording")
        #expect(ViewEditMode.applies(to: document))
    }

    @Test("the two modes, in the order the switch shows them, with their keys")
    func switchOrder() {
        #expect(ViewEditMode.allCases == [.view, .edit])
        #expect(ViewEditMode.allCases.map(\.title) == ["View", "Edit"])
        #expect(ViewEditMode.view.commandKey == "1")
        #expect(ViewEditMode.edit.commandKey == "2")
        #expect(ViewEditMode.view.toggled == .edit)
        #expect(ViewEditMode.edit.toggled == .view)
    }

    @Test("the switch's words are labels, not sentences")
    func copyIsChrome() {
        for mode in ViewEditMode.allCases {
            #expect(CopyBudget.chromeFaults(mode.title).isEmpty, "\(mode.title)")
            #expect(CopyBudget.chromeFaults(mode.menuTitle).isEmpty, "\(mode.menuTitle)")
        }
    }
}

@Suite("Which tools start an edit")
struct ViewEditModeToolTests {

    @Test("every tool but the arrow starts an edit")
    func toolsStartAnEdit() {
        for tool in Tool.allCases {
            #expect(ViewEditMode.pickingStartsAnEdit(tool) == (tool != .select), "\(tool)")
        }
    }
}

@Suite("Which timeline keys start an edit")
struct TimelineKeysStartAnEditTests {

    @Test("watching keys stay in View")
    func watchingKeys() {
        let watching: [TimelineKeyCommand] = [
            .playPause, .shuttle(.forward), .shuttle(.stop), .stepFrames(1), .stepFrames(-5),
            .editPoint(forward: true), .marker(forward: true), .marker(forward: false),
            .goToStart, .goToEnd, .selectTool,
            .showMode(.view), .showMode(.edit), .toggleViewEdit,
        ]
        for command in watching { #expect(command.startsAnEdit == false, "\(command)") }
    }

    @Test("editing keys switch to Edit")
    func editingKeys() {
        let editing: [TimelineKeyCommand] = [
            .markIn, .markOut, .clearIn, .clearOut, .addMarker, .splitAtPlayhead, .lift, .rippleDelete,
            .extractMarked, .liftMarked, .rippleTrimToPlayhead(.start), .rippleTrimToPlayhead(.end),
            .applyDefaultTransition, .toggleSnapping, .bladeTool, .trackSelectForwardTool, .rangeTool,
            .zoomIn, .zoomOut, .zoomToFit, .nudgeClips(frames: 1), .nudgeClips(frames: -5),
        ]
        for command in editing { #expect(command.startsAnEdit, "\(command)") }
    }

    @Test("⌘1 is View and ⌘2 is Edit, wherever the keyboard is")
    func commandDigits() {
        for focused in [true, false] {
            #expect(TimelineKeys.command(for: TimelineKeyPress(key: .letter("1"), modifiers: [.command]),
                                         timelineFocused: focused) == .showMode(.view))
            #expect(TimelineKeys.command(for: TimelineKeyPress(key: .letter("2"), modifiers: [.command]),
                                         timelineFocused: focused) == .showMode(.edit))
        }
    }

    @Test("E toggles, wherever the keyboard is, once per press")
    func eToggles() {
        for focused in [true, false] {
            #expect(TimelineKeys.command(for: TimelineKeyPress(key: .letter("e")),
                                         timelineFocused: focused) == .toggleViewEdit)
        }
        #expect(TimelineKeys.command(for: TimelineKeyPress(key: .letter("e"), isRepeat: true),
                                     timelineFocused: true) == nil)
        // ⌘E and ⇧⌘E are the menu's, not the switch's.
        #expect(TimelineKeys.command(for: TimelineKeyPress(key: .letter("e"), modifiers: [.command]),
                                     timelineFocused: true) == nil)
    }
}

// The timeline toggle at the right of the transport (user 2026-09-29: "the x
// next to it should really be a toggle button"). It opens and closes the
// tracks, and closing them never leaves Edit: the tool bar and the panel stay.
@Suite("The timeline toggle")
struct TimelineToggleTests {

    @Test("in Edit with the tracks open, it closes them and stays in Edit")
    func closesInEdit() {
        let after = TimelineToggle.pressed(mode: .edit, tracksShown: true)
        #expect(after.mode == .edit)
        #expect(after.tracksShown == false)
    }

    @Test("in Edit with the tracks closed, it opens them")
    func opensInEdit() {
        let after = TimelineToggle.pressed(mode: .edit, tracksShown: false)
        #expect(after.mode == .edit)
        #expect(after.tracksShown == true)
    }

    @Test("in View it switches to Edit and opens the tracks, whatever they were")
    func viewGoesToEdit() {
        for shown in [true, false] {
            let after = TimelineToggle.pressed(mode: .view, tracksShown: shown)
            #expect(after.mode == .edit)
            #expect(after.tracksShown == true)
        }
    }

    @Test("it is lit only while the tracks are on screen")
    func litOnlyWhileOpen() {
        #expect(TimelineToggle.isOn(mode: .edit, tracksShown: true))
        #expect(!TimelineToggle.isOn(mode: .edit, tracksShown: false))
        #expect(!TimelineToggle.isOn(mode: .view, tracksShown: true))
        #expect(!TimelineToggle.isOn(mode: .view, tracksShown: false))
    }

    @Test("its tooltip says what a press does, as chrome")
    func tooltip() {
        #expect(TimelineToggle.tooltip(isOn: true) == "Hide Timeline")
        #expect(TimelineToggle.tooltip(isOn: false) == "Show Timeline")
        for on in [true, false] {
            #expect(CopyBudget.chromeFaults(TimelineToggle.tooltip(isOn: on)).isEmpty)
        }
    }
}
