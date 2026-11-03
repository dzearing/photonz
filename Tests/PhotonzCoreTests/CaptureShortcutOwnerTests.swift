import Foundation
import Testing
@testable import PhotonzCore

/// Exactly one running Photonz answers ⇧⌘3, ⇧⌘4, ⇧⌘5. On 2026-11-03 the
/// installed 0.21.0 and Photonz Dev both took every screenshot, under the same
/// file name, and both wrote the clipboard, so a paste in the first few hundred
/// milliseconds found it empty or without a picture.
@Suite("Capture shortcut owner")
struct CaptureShortcutOwnerTests {
    typealias Instance = CaptureShortcutOwner.Instance

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: seconds) }

    @Test func aLoneAppHoldsTheShortcuts() {
        let me = Instance(pid: 10, flavor: .release, launched: at(0), stepsAside: true)
        #expect(CaptureShortcutOwner.holder(of: [me]) == 10)
        #expect(CaptureShortcutOwner.holds(me, among: [me]))
    }

    @Test func theProbeNeverHoldsThem() {
        let probe = Instance(pid: 3, flavor: .probe, launched: at(50), stepsAside: true)
        let dev = Instance(pid: 4, flavor: .dev, launched: at(10), stepsAside: true)
        #expect(CaptureShortcutOwner.holder(of: [probe]) == nil)
        #expect(CaptureShortcutOwner.holder(of: [probe, dev]) == 4)
        #expect(!CaptureShortcutOwner.holds(probe, among: [probe, dev]))
    }

    @Test func theLastOneOpenedHoldsThemWhenEveryoneStepsAside() {
        let release = Instance(pid: 20, flavor: .release, launched: at(100), stepsAside: true)
        let dev = Instance(pid: 30, flavor: .dev, launched: at(200), stepsAside: true)
        #expect(CaptureShortcutOwner.holder(of: [release, dev]) == 30)
        #expect(CaptureShortcutOwner.holds(dev, among: [release, dev]))
        #expect(!CaptureShortcutOwner.holds(release, among: [release, dev]))
        // Same answer whichever order the list comes in.
        #expect(CaptureShortcutOwner.holder(of: [dev, release]) == 30)
    }

    @Test func anOlderBuildThatCannotStepAsideKeepsThem() {
        // 0.21.0 does not know the rule and will answer whatever anyone else
        // does, so everyone who knows it stands down: one app, not two.
        let old = Instance(pid: 35362, flavor: .release, launched: at(0), stepsAside: false)
        let dev = Instance(pid: 8872, flavor: .dev, launched: at(500), stepsAside: true)
        #expect(CaptureShortcutOwner.holder(of: [old, dev]) == 35362)
        #expect(!CaptureShortcutOwner.holds(dev, among: [old, dev]))
    }

    @Test func aTieOnLaunchTimeIsSettledTheSameWayEverywhere() {
        let a = Instance(pid: 41, flavor: .release, launched: at(7), stepsAside: true)
        let b = Instance(pid: 42, flavor: .dev, launched: at(7), stepsAside: true)
        #expect(CaptureShortcutOwner.holder(of: [a, b]) == 42)
        #expect(CaptureShortcutOwner.holder(of: [b, a]) == 42)
    }

    @Test func anUnknownLaunchTimeCountsAsTheOldest() {
        let unknown = Instance(pid: 90, flavor: .dev, launched: nil, stepsAside: true)
        let known = Instance(pid: 5, flavor: .release, launched: at(1), stepsAside: true)
        #expect(CaptureShortcutOwner.holder(of: [unknown, known]) == 5)
    }

    @Test func anAppMissingFromTheListStillAsksForItself() {
        // NSWorkspace can lag a launch: the asking app always counts itself.
        let me = Instance(pid: 77, flavor: .dev, launched: at(9), stepsAside: true)
        let other = Instance(pid: 12, flavor: .release, launched: at(1), stepsAside: true)
        #expect(CaptureShortcutOwner.holds(me, among: [other]))
    }
}
