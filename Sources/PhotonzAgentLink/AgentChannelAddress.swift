import Foundation

/// Where each build of the app listens for agents: a Unix socket of its own in
/// the user's Library, so release, Dev and Probe never answer for each other.
public enum AgentChannelAddress {

    public static let releaseBundleID = "com.dzearing.photonz"
    public static let devBundleID = "com.dzearing.photonz.dev"
    public static let probeBundleID = "com.dzearing.photonz.probe"

    /// The bytes `sockaddr_un.sun_path` holds, less its closing nought.
    public static let longestSocketPath = 103

    public static func directory(home: String) -> String {
        home + "/Library/Application Support/Photonz/Agent"
    }

    /// The socket for one app. Our own three go by a short name, because a
    /// Unix socket's whole path must fit in 103 bytes and the Library folder
    /// has already spent half of them.
    public static func socketPath(bundleID: String, home: String) -> String {
        let name = switch bundleID {
        case releaseBundleID: "release"
        case devBundleID: "dev"
        case probeBundleID: "probe"
        default: bundleID
        }
        return directory(home: home) + "/" + name + ".sock"
    }

    /// The handshake and tool list the app leaves beside its socket
    /// (`AgentMCP.handshake`), for the bridge to answer from while it is closed.
    public static func handshakePath(bundleID: String, home: String) -> String {
        String(socketPath(bundleID: bundleID, home: home).dropLast(".sock".count)) + ".json"
    }

    /// The apps to try, in order, for a `PHOTONZ_APP` setting: `release`,
    /// `dev`, `probe`, or a bundle id. Unset, the Dev build a person is
    /// working in comes first, then the shipping app, then the loop's probe.
    /// The setting the bridge goes by: `PHOTONZ_APP`, except that a session
    /// the go loop started (it exports `GO_LOOP_PID`) and that named no app is
    /// sent to the probe. An unmanned runner must never drive the Dev app a
    /// person is working in, and the server a person installs for themselves
    /// is also in every runner's session.
    ///
    /// A bridge that ships inside an app (`Contents/Helpers/photonz-mcp`,
    /// installed from Settings > Agents) passes that app's bundle id as
    /// `ownBundleID`, and with nothing else said it reaches that app alone: a
    /// server installed from the shipping app never drives a Dev build.
    public static func choice(environment: [String: String], ownBundleID: String? = nil) -> String? {
        if let named = environment["PHOTONZ_APP"], !named.trimmingCharacters(in: .whitespaces).isEmpty {
            return named
        }
        return environment["GO_LOOP_PID"] == nil ? ownBundleID : "probe"
    }

    /// The app bundle a bundled bridge sits in, from the bridge's own path
    /// (`<app>.app/Contents/Helpers/<bridge>`), or nil for a bridge built
    /// anywhere else.
    public static func bundle(containingHelper path: String) -> String? {
        let parts = (path as NSString).standardizingPath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 4,
              parts[parts.count - 2] == "Helpers",
              parts[parts.count - 3] == "Contents",
              parts[parts.count - 4].hasSuffix(".app") else { return nil }
        return parts.dropLast(3).joined(separator: "/")
    }

    /// The `open` arguments to try, in order, when the app the bridge reaches
    /// is not running. Only ever the app it was asked for: `appPath`
    /// (`PHOTONZ_APP_PATH`, said on purpose), then the bundle the bridge sits
    /// in when that IS the app asked for, then the app asked for by bundle id.
    /// Nothing named: the shipping app, else Dev.
    ///
    /// The bundle the bridge sits in used to come first whatever was asked
    /// for, so a go loop session (sent to the probe) whose bridge was installed
    /// from /Applications opened the installed Photonz beside the person's Dev
    /// app, then waited for a probe that never came.
    public static func launchAttempts(choice: String?, appPath: String?, ownBundle: String?,
                                      ownBundleID: String?) -> [[String]] {
        let named = !(choice ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let wanted = named ? candidates(for: choice) : [releaseBundleID, devBundleID]
        var attempts: [[String]] = []
        if let appPath, !appPath.isEmpty { attempts.append(["-g", "-a", appPath]) }
        if let ownBundle, !ownBundle.isEmpty, let ownBundleID, wanted.contains(ownBundleID),
           !attempts.contains(["-g", "-a", ownBundle]) {
            attempts.append(["-g", "-a", ownBundle])
        }
        return attempts + wanted.map { ["-g", "-b", $0] }
    }

    /// What the bridge does with a request while no app is listening.
    public enum WhileClosed: Sendable, Equatable {
        /// From the handshake the app left beside its socket.
        case answerFromHandshake
        /// Answered on the spot (`ping`).
        case answerHere
        /// Answered "not understood", as the app answers it (-32601).
        case notUnderstood
        /// Only the app can answer: start it.
        case startTheApp
    }

    /// Only a tool call, or the handshake on a machine where the app has never
    /// left one, starts the app. Anything else the app does not answer either
    /// is turned away here: Claude Code opens every session with
    /// `server/discover` before `initialize`, and starting the app to hear it
    /// say no opened Photonz the second a session began, with no tool called.
    public static func whileClosed(method: String, handshakeSaved: Bool) -> WhileClosed {
        switch method {
        case "ping": .answerHere
        case "initialize", "tools/list": handshakeSaved ? .answerFromHandshake : .startTheApp
        case "tools/call": .startTheApp
        default: .notUnderstood
        }
    }

    public static func candidates(for choice: String?) -> [String] {
        switch choice?.trimmingCharacters(in: .whitespaces).lowercased() {
        case nil, "": [devBundleID, releaseBundleID, probeBundleID]
        case "release": [releaseBundleID]
        case "dev": [devBundleID]
        case "probe": [probeBundleID]
        default: [choice?.trimmingCharacters(in: .whitespaces) ?? releaseBundleID]
        }
    }
}
