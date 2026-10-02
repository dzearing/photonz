import Foundation
import Testing
@testable import PhotonzCore

@Suite("Capture hotkeys clear the corner")
struct CaptureHotkeyTests {
    @Test("Every shortcut that starts a capture or opens the last one clears the toasts")
    func capturesClear() {
        #expect(CaptureHotkey.captureFullScreen.clearsToasts)
        #expect(CaptureHotkey.captureRegion.clearsToasts)
        #expect(CaptureHotkey.record.clearsToasts)
        #expect(CaptureHotkey.editLastCapture.clearsToasts)
    }

    @Test("Showing history and stopping a recording leave the corner alone")
    func othersDoNot() {
        #expect(!CaptureHotkey.toggleHistory.clearsToasts)
        #expect(!CaptureHotkey.stopRecording.clearsToasts)
    }

    @Test("The family is read off the number row: 3, 4, 5 and 6")
    func numbers() {
        #expect(CaptureHotkey(digit: "3") == .captureFullScreen)
        #expect(CaptureHotkey(digit: "4") == .captureRegion)
        #expect(CaptureHotkey(digit: "5") == .record)
        #expect(CaptureHotkey(digit: "6") == .editLastCapture)
        #expect(CaptureHotkey(digit: "7") == nil)
    }
}

@Suite("Toast hush")
struct ToastHushTests {
    @Test("A toast asked for before anything was cleared still shows")
    func untouched() {
        let hush = ToastHush()
        #expect(hush.stillWanted(hush.ticket))
    }

    @Test("Clearing the corner drops every toast asked for before it")
    func clearingDropsEarlier() {
        var hush = ToastHush()
        let earlier = hush.ticket
        hush.clear()
        #expect(!hush.stillWanted(earlier))
    }

    @Test("A toast asked for after the clear shows as normal")
    func laterShows() {
        var hush = ToastHush()
        hush.clear()
        let later = hush.ticket
        #expect(hush.stillWanted(later))
        hush.clear()
        #expect(!hush.stillWanted(later))
        #expect(hush.stillWanted(hush.ticket))
    }
}

@Suite("A walk presses the capture shortcuts")
struct CaptureHotkeyWalkTests {
    @Test("Each capture shortcut, the toast and a held save are actions a walk can name")
    func actionsDecode() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [
            { "do": "action", "action": "showCaptureToast" },
            { "do": "action", "action": "hotkeyCaptureFullScreen" },
            { "do": "action", "action": "hotkeyCaptureRegion" },
            { "do": "action", "action": "hotkeyRecord" },
            { "do": "action", "action": "hotkeyEditLastCapture" },
            { "do": "action", "action": "beginHeldSave" },
            { "do": "action", "action": "finishHeldSave" }
        ] }
        """.utf8))
        let actions: [PlaytestAction] = script.steps.compactMap { step in
            if case .action(let action) = step { return action } else { return nil }
        }
        #expect(actions == [.showCaptureToast, .hotkeyCaptureFullScreen, .hotkeyCaptureRegion,
                            .hotkeyRecord, .hotkeyEditLastCapture, .beginHeldSave, .finishHeldSave])
    }

    @Test("Each hotkey action names the shortcut it presses")
    func hotkeyOfAction() {
        #expect(PlaytestAction.hotkeyCaptureFullScreen.captureHotkey == .captureFullScreen)
        #expect(PlaytestAction.hotkeyCaptureRegion.captureHotkey == .captureRegion)
        #expect(PlaytestAction.hotkeyRecord.captureHotkey == .record)
        #expect(PlaytestAction.hotkeyEditLastCapture.captureHotkey == .editLastCapture)
        #expect(PlaytestAction.showCaptureToast.captureHotkey == nil)
    }
}
