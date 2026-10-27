import AppKit
import PhotonzCore
import ServiceManagement

/// This app's login item, through the system's own list
/// (`SMAppService.mainApp`), so it shows under System Settings > General >
/// Login Items by the app's own name. The decisions live in `OpenAtLogin`; this
/// is only the call into macOS.
final class SystemLoginItemService: LoginItemService {
    var state: OpenAtLogin.SystemState {
        switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        case .notFound: .notFound
        case .notRegistered: .off
        @unknown default: .off
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// Opening at login, for this copy of the app.
@MainActor
enum LoginItem {
    /// The system's list for the Dev and shipping builds. The probe gets a list
    /// that lives only in memory, starting the way a new install's does (on),
    /// so a walk can flip the switch and the test app never starts at login.
    static let service: any LoginItemService =
        AppInfo.flavor == .probe ? InMemoryLoginItemService(state: .on) : SystemLoginItemService()

    /// Whether the switch can do anything here: the probe's pretend list, or a
    /// real bundle at a place that lasts (not the disk image, not a bare build).
    static var isAvailable: Bool {
        AppInfo.flavor == .probe
            || OpenAtLogin.mayRegister(flavor: AppInfo.flavor, bundlePath: Bundle.main.bundleURL.path)
    }

    /// What macOS said when the first launch tried to turn it on, if it
    /// refused, so Settings can say so.
    private(set) static var launchTrouble: String?

    /// Once per launch: a new install turns opening at login on.
    static func applyDefaultOnLaunch() {
        launchTrouble = OpenAtLogin.applyDefaultOnLaunch(
            service: service, defaults: .standard,
            flavor: AppInfo.flavor, bundlePath: Bundle.main.bundleURL.path)
    }

    /// Whether this process was started by the login item, rather than by a
    /// person opening it. Only meaningful during launch, while the open event
    /// that started the app is still the current one.
    static var wasLaunchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// The button beside a refusal or a wait for approval.
    static func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
