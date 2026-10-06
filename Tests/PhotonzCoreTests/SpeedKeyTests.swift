import Foundation
import PhotonzCore
import Testing

/// **⌘R opens the picked clip's speed**, Premiere's Speed/Duration key.
///
/// The speeds already live in the panel's Time section, so the key does not
/// bring a dialog of its own: it opens that dropdown. These pin the key, that
/// it works wherever the keyboard is in a document with time, that plain R is
/// still the Range tool, and what the canvas says when there is no clip to
/// retime.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("Command R opens the picked clip's speed")
struct SpeedKeyTests {

    @Test("Command R is Speed wherever the keyboard is, and plain R is not")
    func theKey() {
        let press = TimelineKeyPress(key: .letter("r"), modifiers: .command)
        #expect(TimelineKeys.command(for: press, timelineFocused: true) == .openClipSpeed)
        #expect(TimelineKeys.command(for: press, timelineFocused: false) == .openClipSpeed)
        // R alone is Final Cut's Range tool on the timeline, and the canvas's
        // rectangle on the picture.
        #expect(TimelineKeys.command(for: TimelineKeyPress(key: .letter("r")), timelineFocused: true) == .rangeTool)
        #expect(TimelineKeys.command(for: TimelineKeyPress(key: .letter("r")), timelineFocused: false) == nil)
        // ⇧⌘R is Rasterize, and stays its own.
        #expect(TimelineKeys.command(for: TimelineKeyPress(key: .letter("r"), modifiers: [.command, .shift]),
                                     timelineFocused: true) == nil)
    }

    @Test("Opening the speed is an edit, so it brings the editor out of View")
    func startsAnEdit() {
        #expect(TimelineKeyCommand.openClipSpeed.startsAnEdit)
    }

    @Test("With no clip to retime the canvas names what the key needs, inside the chrome's budget")
    func refusal() {
        let notice = CopyConfirmation(subject: .speedNeedsAClip, shownAt: Date())
        #expect(notice.title == "No clip picked")
        #expect(notice.detail == "Pick a clip to set its speed")
        #expect(notice.title.count <= 30)
        #expect(notice.detail.count <= 30)
        #expect(!notice.detail.contains("\u{2014}"))
    }

    @Test("A walk can wait for a panel dropdown to be open")
    func walkCondition() {
        let json = """
        { "out": "/tmp/x", "steps": [
            { "do": "waitFor", "condition": "panelMenuOpen", "value": "Speed", "timeout": 3 }
        ] }
        """
        let script = try! PlaytestScript.decode(Data(json.utf8))
        guard case .waitFor(let condition, _) = script.steps[0] else { Issue.record("waitFor"); return }
        #expect(condition == .panelMenuOpen("Speed"))
    }
}
