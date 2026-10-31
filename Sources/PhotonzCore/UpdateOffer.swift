/// What a request for a release's DMG said: the file is there, it is not
/// (yet), or the network never got an answer.
public enum UpdateDownloadProbe: Equatable, Sendable {
    case answers
    case missing
    case unreachable(String)

    /// The status after redirects are followed. Only a success means the
    /// download is there: GitHub answers 404 for a release whose DMG the
    /// Release workflow has not uploaded yet.
    public init(httpStatus: Int) {
        self = (200..<300).contains(httpStatus) ? .answers : .missing
    }
}

/// What the update check reports.
public enum UpdateCheckOutcome: Equatable, Sendable {
    case upToDate
    case updateAvailable(SemanticVersion)
    case failed(String)
}

/// Whether to offer the version the website's `version.json` names.
///
/// The website can announce a release before its download exists: on
/// 2026-10-25 the site said 0.19.0 about 20 minutes before the Release
/// workflow published the DMG, and Update & Restart failed on the 404. So a
/// newer version is offered only once its download answers; until then the
/// running build is reported up to date and the next check tries again.
public enum UpdateOffer {
    /// `probeDownload` is asked only when `latest` is newer than `current`,
    /// and only about `latest`.
    public static func decide(
        current: SemanticVersion,
        latest: SemanticVersion,
        probeDownload: (SemanticVersion) async -> UpdateDownloadProbe
    ) async -> UpdateCheckOutcome {
        guard case .updateAvailable(let newer) = UpdateAvailability(current: current, latest: latest) else {
            return .upToDate
        }
        switch await probeDownload(newer) {
        case .answers: return .updateAvailable(newer)
        case .missing: return .upToDate
        case .unreachable(let message): return .failed(message)
        }
    }
}

/// The sentence a person reads when the DMG download itself is refused,
/// instead of "the server returned an unexpected response".
public enum UpdateDownloadFailure {
    public static func message(httpStatus: Int) -> String {
        if (500..<600).contains(httpStatus) {
            return "The download server isn't answering right now. Try again in a few minutes."
        }
        return "This update isn't ready to download yet. Try again in a few minutes."
    }
}
