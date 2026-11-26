import Foundation

/// A macOS privacy permission the app may have to ask the person for.
public enum PermissionService: String, Codable, Sendable, CaseIterable {
    case screenRecording
    case microphone
}

/// What an unmanned build remembers about the permissions it has asked for,
/// across launches. Keyed by `PermissionService.rawValue`, valued by when it
/// first asked (any string the caller chooses; the app writes ISO 8601).
public struct PermissionAskLedger: Codable, Sendable, Equatable {
    public var askedAt: [String: String]

    public init(askedAt: [String: String] = [:]) {
        self.askedAt = askedAt
    }

    /// The ledger in `data`, or an empty one when there is none or it cannot
    /// be read. An unreadable ledger must never turn into a crash or a storm;
    /// at worst it costs the one ask it would have prevented.
    public static func read(_ data: Data?) -> PermissionAskLedger {
        guard let data, let ledger = try? JSONDecoder().decode(PermissionAskLedger.self, from: data) else {
            return PermissionAskLedger()
        }
        return ledger
    }
}

/// The one rule for raising a macOS permission dialog.
///
/// On macOS 15 and later a Screen Recording request (`CGRequestScreenCaptureAccess`,
/// or any ScreenCaptureKit call) from an app without the grant puts up a
/// dialog EVERY time, even after the person clicked Deny, and each one waits in
/// a queue behind the one on screen after the asking app has quit. The loop
/// launches its probe hundreds of times a night, so "once per launch" left a
/// stack of dialogs, and on 2026-11-26 the person denied a dozen in a row while
/// each next one came straight up. So:
///
/// - nothing ever asks for a permission it already has;
/// - the person's own app asks at most once per launch (they launched it, they
///   are there to answer, and a second dialog in one sitting never helps);
/// - the unmanned probe asks at most once EVER: after its one ask it reads the
///   permission as missing and says so, until somebody clears its ledger.
public enum PermissionAskPolicy {
    public enum Asker: Sendable {
        /// Photonz, Photonz Next or a dev build: a person launched it.
        case person
        /// The loop's probe, launched by machinery with nobody watching.
        case unmannedProbe
    }

    public enum Answer: Equatable, Sendable {
        /// Raise the system's request now, and record that it was raised.
        case ask
        /// It is granted; there is nothing to ask.
        case alreadyGranted
        /// This launch already asked once.
        case askedThisLaunch
        /// The probe asked once already, at this time, and never asks again.
        case askedBefore(at: String)
    }

    public static func decide(_ service: PermissionService, granted: Bool, asker: Asker,
                              askedThisLaunch: Set<PermissionService>,
                              ledger: PermissionAskLedger) -> Answer {
        if granted { return .alreadyGranted }
        if askedThisLaunch.contains(service) { return .askedThisLaunch }
        if asker == .unmannedProbe, let at = ledger.askedAt[service.rawValue] {
            return .askedBefore(at: at)
        }
        return .ask
    }

    /// `ledger` with `service` recorded as asked at `at`, keeping the first
    /// time it was asked if it already was.
    public static func recording(_ service: PermissionService, at: String,
                                 in ledger: PermissionAskLedger) -> PermissionAskLedger {
        var next = ledger
        if next.askedAt[service.rawValue] == nil { next.askedAt[service.rawValue] = at }
        return next
    }
}
