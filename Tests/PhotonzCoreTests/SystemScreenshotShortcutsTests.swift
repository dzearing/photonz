import Foundation
import Testing
@testable import PhotonzCore

@Suite("System screenshot shortcut conflicts")
struct SystemScreenshotShortcutsTests {

    private typealias Shortcut = SystemScreenshotShortcuts.Shortcut

    @Test func neverCustomizedDomainMeansEverythingConflicts() {
        #expect(SystemScreenshotShortcuts.conflicting(in: nil) == [.fullScreen, .region, .toolbar])
        #expect(SystemScreenshotShortcuts.conflicting(in: nil, touchBar: true) == Shortcut.allCases)
    }

    @Test func emptyDictionaryMeansEverythingConflicts() {
        #expect(SystemScreenshotShortcuts.conflicting(in: [:]) == [.fullScreen, .region, .toolbar])
        #expect(SystemScreenshotShortcuts.conflicting(in: [:], touchBar: true) == Shortcut.allCases)
    }

    @Test func allDisabledMeansNoConflicts() {
        let hotkeys: [String: Any] = [
            "28": ["enabled": false],
            "30": ["enabled": 0],
            "184": ["enabled": NSNumber(value: 0)],
        ]
        #expect(SystemScreenshotShortcuts.conflicting(in: hotkeys).isEmpty)
    }

    @Test func onlyStillEnabledEntriesConflict() {
        let hotkeys: [String: Any] = [
            "28": ["enabled": false],   // ⇧⌘3 freed
            // 30 missing → system default: enabled
            "184": ["enabled": true],   // ⇧⌘5 still the system's
        ]
        #expect(SystemScreenshotShortcuts.conflicting(in: hotkeys) == [.region, .toolbar])
    }

    @Test func entryWithoutEnabledFlagDefaultsToEnabled() {
        let hotkeys: [String: Any] = [
            "28": ["value": ["type": "standard"]],
            "30": ["enabled": false],
            "184": ["enabled": false],
        ]
        #expect(SystemScreenshotShortcuts.conflicting(in: hotkeys) == [.fullScreen])
    }

    @Test func numericNSNumberFlagsAreUnderstood() {
        // CFPreferences hands back CFBoolean/CFNumber bridged to NSNumber.
        let hotkeys: [String: Any] = [
            "28": ["enabled": NSNumber(value: 1)],
            "30": ["enabled": NSNumber(value: 0)],
            "184": ["enabled": NSNumber(value: true)],
        ]
        #expect(SystemScreenshotShortcuts.conflicting(in: hotkeys) == [.fullScreen, .toolbar])
    }

    @Test func unrelatedHotkeyIDsAreIgnored() {
        // 29/31 are the copy-to-clipboard variants (⌃⇧⌘3/4) — not ours.
        let hotkeys: [String: Any] = [
            "28": ["enabled": false],
            "29": ["enabled": true],
            "30": ["enabled": false],
            "31": ["enabled": true],
            "184": ["enabled": false],
        ]
        #expect(SystemScreenshotShortcuts.conflicting(in: hotkeys).isEmpty)
    }

    // MARK: Touch Bar (⇧⌘6 "Save picture of Touch Bar as a file", id 181)

    @Test func touchBarShortcutIsNeverReportedWithoutATouchBar() {
        // Keyboard Settings does not even list the Touch Bar row on these
        // Macs, so a warning about it could never be acted on.
        let hotkeys: [String: Any] = [
            "28": ["enabled": false],
            "30": ["enabled": false],
            "184": ["enabled": false],
            "181": ["enabled": true],
        ]
        #expect(SystemScreenshotShortcuts.conflicting(in: hotkeys).isEmpty)
        #expect(SystemScreenshotShortcuts.conflicting(in: hotkeys, touchBar: false).isEmpty)
    }

    @Test func touchBarShortcutConflictsLikeTheOthersOnATouchBarMac() {
        let freed: [String: Any] = [
            "28": ["enabled": false], "30": ["enabled": false], "184": ["enabled": false],
        ]
        // Missing → system default → still the system's.
        #expect(SystemScreenshotShortcuts.conflicting(in: freed, touchBar: true) == [.touchBar])

        var stillHeld = freed
        stillHeld["181"] = ["enabled": NSNumber(value: 1)]
        #expect(SystemScreenshotShortcuts.conflicting(in: stillHeld, touchBar: true) == [.touchBar])

        var released = freed
        released["181"] = ["enabled": false]
        #expect(SystemScreenshotShortcuts.conflicting(in: released, touchBar: true).isEmpty)

        // ⌃⇧⌘6 (copy Touch Bar picture to clipboard, id 182) is not ours.
        var clipboardOnly = released
        clipboardOnly["182"] = ["enabled": true]
        #expect(SystemScreenshotShortcuts.conflicting(in: clipboardOnly, touchBar: true).isEmpty)
    }

    @Test func touchBarShortcutSortsAfterTheOthers() {
        #expect(SystemScreenshotShortcuts.conflicting(in: nil, touchBar: true)
                == [.fullScreen, .region, .toolbar, .touchBar])
    }

    @Test func touchBarIsRecognisedFromTheModelIdentifier() {
        #expect(SystemScreenshotShortcuts.hasTouchBar(modelIdentifier: "MacBookPro17,1", hotkeys: nil))
        #expect(SystemScreenshotShortcuts.hasTouchBar(modelIdentifier: "MacBookPro16,1", hotkeys: [:]))
        #expect(SystemScreenshotShortcuts.hasTouchBar(modelIdentifier: "MacBookPro13,2", hotkeys: nil))
        // Apple silicon Pros from 2021 on, Airs, desktops: no Touch Bar.
        #expect(!SystemScreenshotShortcuts.hasTouchBar(modelIdentifier: "MacBookPro18,3", hotkeys: nil))
        #expect(!SystemScreenshotShortcuts.hasTouchBar(modelIdentifier: "Mac16,5", hotkeys: nil))
        #expect(!SystemScreenshotShortcuts.hasTouchBar(modelIdentifier: "MacBookAir10,1", hotkeys: [:]))
        #expect(!SystemScreenshotShortcuts.hasTouchBar(modelIdentifier: "", hotkeys: nil))
    }

    @Test func touchBarIsRecognisedFromATouchBarHotkeyInThePreferences() {
        // macOS only writes the Touch Bar screenshot entry on a Mac that shows
        // that row in Keyboard Settings, so its presence settles it even for a
        // model identifier the list does not know.
        let hotkeys: [String: Any] = ["181": ["enabled": false]]
        #expect(SystemScreenshotShortcuts.hasTouchBar(modelIdentifier: "Mac99,1", hotkeys: hotkeys))
        let unrelated: [String: Any] = ["28": ["enabled": false], "182": ["enabled": true]]
        #expect(!SystemScreenshotShortcuts.hasTouchBar(modelIdentifier: "Mac99,1", hotkeys: unrelated))
    }

    @Test func keyLabelsReadLikeMenuShortcuts() {
        #expect(Shortcut.fullScreen.keyLabel == "⇧⌘3")
        #expect(Shortcut.region.keyLabel == "⇧⌘4")
        #expect(Shortcut.toolbar.keyLabel == "⇧⌘5")
        #expect(Shortcut.touchBar.keyLabel == "⇧⌘6")
    }
}
