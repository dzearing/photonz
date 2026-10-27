import Foundation
import Testing
@testable import PhotonzCore

@Suite("Open at login")
struct OpenAtLoginTests {
    private static let applications = "/Applications/Photonz.app"

    private func freshDefaults() -> UserDefaults {
        let name = "OpenAtLoginTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: Who may register

    @Test func theShippingAndDevBuildsMayRegisterTheProbeNever() {
        // The probe is launched by every walk; if it registered, the test app
        // would start at every login.
        #expect(OpenAtLogin.mayRegister(flavor: .release, bundlePath: Self.applications))
        #expect(OpenAtLogin.mayRegister(flavor: .dev, bundlePath: "/Users/me/git/photonz/dist/Photonz Dev.app"))
        #expect(!OpenAtLogin.mayRegister(flavor: .probe, bundlePath: "/Users/me/git/photonz/dist/Photonz Probe.app"))
    }

    @Test func onlyAnAppBundleAtAPlaceThatLastsMayRegister() {
        // A bare `swift build` binary has no bundle to name; a copy run from the
        // disk image or from a translocated quarantine copy would register a
        // path that is gone tomorrow.
        #expect(!OpenAtLogin.mayRegister(flavor: .dev, bundlePath: nil))
        #expect(!OpenAtLogin.mayRegister(flavor: .dev, bundlePath: "/Users/me/git/photonz/.build/debug"))
        #expect(!OpenAtLogin.mayRegister(flavor: .release, bundlePath: "/Volumes/Photonz/Photonz.app"))
        #expect(!OpenAtLogin.mayRegister(
            flavor: .release,
            bundlePath: "/private/var/folders/x/AppTranslocation/ABC/d/Photonz.app"))
    }

    // MARK: The default

    @Test func aNewInstallRegistersItselfOnItsFirstLaunch() {
        let service = InMemoryLoginItemService(state: .off)
        let defaults = freshDefaults()
        let trouble = OpenAtLogin.applyDefaultOnLaunch(
            service: service, defaults: defaults, flavor: .release, bundlePath: Self.applications)
        #expect(trouble == nil)
        #expect(service.state == .on)
        #expect(service.registerCalls == 1)
    }

    @Test func theDefaultIsAppliedOnceAndNeverAgain() {
        // Turning it off, in Photonz or in System Settings, must stick: the
        // next launch does not quietly turn it back on.
        let service = InMemoryLoginItemService(state: .off)
        let defaults = freshDefaults()
        _ = OpenAtLogin.applyDefaultOnLaunch(
            service: service, defaults: defaults, flavor: .release, bundlePath: Self.applications)
        service.state = .off
        _ = OpenAtLogin.applyDefaultOnLaunch(
            service: service, defaults: defaults, flavor: .release, bundlePath: Self.applications)
        #expect(service.state == .off)
        #expect(service.registerCalls == 1)
    }

    @Test func anAlreadyRegisteredAppIsLeftAlone() {
        // An update over the old version keeps its registration; launching the
        // new one must not register a second time.
        let service = InMemoryLoginItemService(state: .on)
        _ = OpenAtLogin.applyDefaultOnLaunch(
            service: service, defaults: freshDefaults(), flavor: .release, bundlePath: Self.applications)
        #expect(service.registerCalls == 0)
        #expect(service.state == .on)
    }

    @Test func theProbeNeverRegistersEvenOnItsFirstLaunch() {
        let service = InMemoryLoginItemService(state: .off)
        _ = OpenAtLogin.applyDefaultOnLaunch(
            service: service, defaults: freshDefaults(), flavor: .probe,
            bundlePath: "/Users/me/git/photonz/dist/Photonz Probe.app")
        #expect(service.registerCalls == 0)
    }

    @Test func aCopyOnTheDiskImageWaitsForTheRealInstall() {
        // The launch from the disk image registers nothing and does not use
        // the default up, so the first launch from Applications still does.
        let service = InMemoryLoginItemService(state: .off)
        let defaults = freshDefaults()
        _ = OpenAtLogin.applyDefaultOnLaunch(
            service: service, defaults: defaults, flavor: .release, bundlePath: "/Volumes/Photonz/Photonz.app")
        #expect(service.registerCalls == 0)
        _ = OpenAtLogin.applyDefaultOnLaunch(
            service: service, defaults: defaults, flavor: .release, bundlePath: Self.applications)
        #expect(service.registerCalls == 1)
    }

    @Test func aRefusedRegistrationSaysSoAndIsNotRetriedEveryLaunch() {
        let service = InMemoryLoginItemService(state: .off)
        service.refusesRegistration = true
        let defaults = freshDefaults()
        let trouble = OpenAtLogin.applyDefaultOnLaunch(
            service: service, defaults: defaults, flavor: .release, bundlePath: Self.applications)
        #expect(trouble == OpenAtLogin.refusedLine)
        _ = OpenAtLogin.applyDefaultOnLaunch(
            service: service, defaults: defaults, flavor: .release, bundlePath: Self.applications)
        #expect(service.registerCalls == 1)
    }

    // MARK: The switch

    @Test func theSwitchReadsTheSystemNeverAStoredCopy() {
        // Turned off under System Settings > Login Items: Photonz shows off.
        #expect(OpenAtLogin.row(state: .on, trouble: nil).isOn)
        #expect(!OpenAtLogin.row(state: .off, trouble: nil).isOn)
        #expect(!OpenAtLogin.row(state: .notFound, trouble: nil).isOn)
    }

    @Test func waitingForApprovalSaysSoInOneLineWithTheWayThere() {
        let row = OpenAtLogin.row(state: .needsApproval, trouble: nil)
        #expect(row.isOn)
        #expect(row.line == OpenAtLogin.needsApprovalLine)
        #expect(row.offersLoginItems)
    }

    @Test func aFailureSaysSoWithTheWayThere() {
        let row = OpenAtLogin.row(state: .off, trouble: OpenAtLogin.refusedLine)
        #expect(!row.isOn)
        #expect(row.line == OpenAtLogin.refusedLine)
        #expect(row.offersLoginItems)
    }

    @Test func theNormalStatesSayNothingMore() {
        #expect(OpenAtLogin.row(state: .on, trouble: nil).line == nil)
        #expect(!OpenAtLogin.row(state: .on, trouble: nil).offersLoginItems)
        #expect(OpenAtLogin.row(state: .off, trouble: nil).line == nil)
    }

    @Test func flippingTheSwitchRegistersAndUnregisters() {
        let service = InMemoryLoginItemService(state: .on)
        #expect(OpenAtLogin.set(false, service: service) == nil)
        #expect(service.state == .off)
        #expect(OpenAtLogin.set(true, service: service) == nil)
        #expect(service.state == .on)
    }

    @Test func aRefusalWhileTurningOnIsReported() {
        let service = InMemoryLoginItemService(state: .off)
        service.refusesRegistration = true
        #expect(OpenAtLogin.set(true, service: service) == OpenAtLogin.refusedLine)
        #expect(service.state == .off)
    }

    @Test func aRegistrationThatNeedsApprovalIsNotATrouble() {
        // macOS answers "needs your OK" by throwing and leaving the item
        // waiting; the row says that itself, so there is no second line.
        let service = InMemoryLoginItemService(state: .off)
        service.registersAsNeedingApproval = true
        #expect(OpenAtLogin.set(true, service: service) == nil)
        #expect(service.state == .needsApproval)
    }

    // MARK: Words

    @Test func theWordsAreShortAndPlain() {
        let words = [OpenAtLogin.sectionTitle, OpenAtLogin.label, OpenAtLogin.needsApprovalLine,
                     OpenAtLogin.refusedLine, OpenAtLogin.notRemovedLine,
                     OpenAtLogin.unavailableLine, OpenAtLogin.openLoginItemsButton]
        for line in words {
            #expect(line.count <= 40, "\(line)")
            #expect(!line.contains("\u{2014}"), "\(line)")
        }
        #expect(OpenAtLogin.label == "Open at login")
    }
}
