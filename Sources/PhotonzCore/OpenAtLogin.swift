import Foundation

/// Photonz starting by itself when you log in, quietly in the menu bar.
///
/// Capture shortcuts and the agent connection only work while the app is
/// running, so it is on for a new install: the first launch registers the app
/// as a login item without asking. Settings > General has the one switch that
/// turns it off. The switch always reads the system's own answer, never a
/// stored copy, so turning it off under System Settings > Login Items shows as
/// off here too.
///
/// The system call itself sits behind `LoginItemService` (the app wraps
/// `SMAppService.mainApp`), so tests and the probe never register anything.
public enum OpenAtLogin {

    /// What the system says about this app's login item.
    public enum SystemState: String, Sendable, Equatable {
        /// Registered and allowed: the app opens at login.
        case on
        /// Not registered.
        case off
        /// Registered, but macOS is waiting for the person's OK in Login Items.
        case needsApproval
        /// The system cannot find the app's login item at all, which reads as
        /// off.
        case notFound
    }

    // MARK: Words

    public static let sectionTitle = "General"
    public static let label = "Open at login"
    public static let needsApprovalLine = "Waiting for your OK in Login Items."
    public static let refusedLine = "macOS would not add Photonz."
    public static let notRemovedLine = "macOS would not remove Photonz."
    public static let unavailableLine = "Works once Photonz is in Applications."
    public static let openLoginItemsButton = "Open Login Items"

    /// Remembers that the first launch has applied the default, so turning the
    /// switch off sticks. It says nothing about whether the switch is on.
    public static let defaultAppliedKey = "openAtLogin.defaultApplied"

    // MARK: Who may register

    /// Whether this copy of the app may register itself at all. The probe never
    /// does: every walk launches it, and the test app must not start at every
    /// login. Nor does anything without an app bundle at a place that lasts: a
    /// bare build has no bundle, and a copy run from the disk image or from a
    /// translocated quarantine copy names a path that is gone tomorrow.
    public static func mayRegister(flavor: AppFlavor, bundlePath: String?) -> Bool {
        guard flavor != .probe, let path = bundlePath, path.hasSuffix(".app") else { return false }
        if path.hasPrefix("/Volumes/") { return false }
        if path.contains("/AppTranslocation/") { return false }
        return true
    }

    // MARK: The default

    /// Runs once per launch. The first launch of a copy that may register turns
    /// opening at login on; every later launch leaves the system's state alone,
    /// whatever it is. Returns the line to show beside the switch when macOS
    /// refused, or nil.
    @discardableResult
    public static func applyDefaultOnLaunch(service: any LoginItemService, defaults: UserDefaults,
                                            flavor: AppFlavor, bundlePath: String?) -> String? {
        guard mayRegister(flavor: flavor, bundlePath: bundlePath),
              !defaults.bool(forKey: defaultAppliedKey) else { return nil }
        // Marked first: a refusal is reported once, never retried every launch.
        defaults.set(true, forKey: defaultAppliedKey)
        switch service.state {
        case .on, .needsApproval: return nil
        case .off, .notFound: return set(true, service: service)
        }
    }

    // MARK: The switch

    /// What the switch shows.
    public struct Row: Sendable, Equatable {
        public let isOn: Bool
        /// One line under the switch, only when something needs saying.
        public let line: String?
        /// Whether the row carries the button that opens Login Items.
        public let offersLoginItems: Bool
    }

    public static func row(state: SystemState, trouble: String?) -> Row {
        let isOn = state == .on || state == .needsApproval
        if let trouble {
            return Row(isOn: isOn, line: trouble, offersLoginItems: true)
        }
        if state == .needsApproval {
            return Row(isOn: true, line: needsApprovalLine, offersLoginItems: true)
        }
        return Row(isOn: isOn, line: nil, offersLoginItems: false)
    }

    /// Turns opening at login on or off. Returns the line to show when macOS
    /// refused, or nil. A registration that macOS holds for the person's OK is
    /// not a refusal: the row says that itself.
    @discardableResult
    public static func set(_ on: Bool, service: any LoginItemService) -> String? {
        do {
            if on { try service.register() } else { try service.unregister() }
            return nil
        } catch {
            if on, service.state == .needsApproval { return nil }
            if !on, service.state == .off || service.state == .notFound { return nil }
            return on ? refusedLine : notRemovedLine
        }
    }
}

/// The system's login item list, for this one app.
public protocol LoginItemService: AnyObject {
    var state: OpenAtLogin.SystemState { get }
    func register() throws
    func unregister() throws
}

/// A login item list that lives only in memory: the probe's, so a walk can
/// flip the switch without the test app ever starting at login, and the
/// tests'.
public final class InMemoryLoginItemService: LoginItemService {
    public struct Refused: Error {}

    public var state: OpenAtLogin.SystemState
    public var refusesRegistration = false
    public var registersAsNeedingApproval = false
    public private(set) var registerCalls = 0

    public init(state: OpenAtLogin.SystemState) {
        self.state = state
    }

    public func register() throws {
        registerCalls += 1
        if refusesRegistration { throw Refused() }
        if registersAsNeedingApproval {
            state = .needsApproval
            throw Refused()
        }
        state = .on
    }

    public func unregister() throws {
        state = .off
    }
}
