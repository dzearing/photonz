import Foundation
import Testing
@testable import PhotonzCore

@Suite("System screenshot shortcut conflicts")
struct SystemScreenshotShortcutsTests {

    @Test func neverCustomizedDomainMeansEverythingConflicts() {
        #expect(SystemScreenshotShortcuts.conflicting(in: nil) == SystemScreenshotShortcuts.Shortcut.allCases)
    }

    @Test func emptyDictionaryMeansEverythingConflicts() {
        #expect(SystemScreenshotShortcuts.conflicting(in: [:]) == SystemScreenshotShortcuts.Shortcut.allCases)
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
            "28": ["enabled": false],   // ⌘⇧3 freed
            // 30 missing → system default: enabled
            "184": ["enabled": true],   // ⌘⇧5 still the system's
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
        // 29/31 are the copy-to-clipboard variants (⌃⌘⇧3/4) — not ours.
        let hotkeys: [String: Any] = [
            "28": ["enabled": false],
            "29": ["enabled": true],
            "30": ["enabled": false],
            "31": ["enabled": true],
            "184": ["enabled": false],
        ]
        #expect(SystemScreenshotShortcuts.conflicting(in: hotkeys).isEmpty)
    }

    @Test func keyLabelsReadLikeMenuShortcuts() {
        #expect(SystemScreenshotShortcuts.Shortcut.fullScreen.keyLabel == "⇧⌘3")
        #expect(SystemScreenshotShortcuts.Shortcut.region.keyLabel == "⇧⌘4")
        #expect(SystemScreenshotShortcuts.Shortcut.toolbar.keyLabel == "⇧⌘5")
    }
}
