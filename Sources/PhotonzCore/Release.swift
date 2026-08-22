import Foundation

/// Which Photonz experience the app is running. Both releases ship inside the
/// SAME binary — there is no separate build, no separate install. `public` is
/// what everyone gets by default and must stay stable; `next` is where the
/// next-generation experience is built.
///
/// A third case (`legacy`) is coming: when Next is good enough it gets promoted
/// to Public, and today's Public is demoted to Legacy so nobody is yanked out
/// from under the app they know. Nothing here hard-codes "there are two" —
/// every trait is a property on the case, the dialog lists `allCases`, and the
/// flag catalog declares availability per release as data.
///
/// See `docs/design/experiments.md` for the porting rule (Public ports forward
/// into Next; Next is NEVER back-ported).
public enum Release: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    /// Today's shipping experience. The default, and the one Next-only branches
    /// must never touch.
    case `public`
    /// The next-generation experience, built in the open behind this switch.
    case next

    /// What a fresh install runs, and the fallback for anything unreadable.
    public static let `default`: Release = .public

    public var id: String { rawValue }

    public var isDefault: Bool { self == Self.default }

    /// Name shown in the Experiments dialog.
    public var title: String {
        switch self {
        case .public: "Public"
        case .next: "Next"
        }
    }

    /// One line under the name in the release picker.
    public var tagline: String {
        switch self {
        case .public: "The Photonz everyone gets. Stable, and it stays that way."
        case .next: "The next generation, still being built. Expect rough edges."
        }
    }

    /// Prefix for everything this release persists, so two releases never read
    /// or clobber each other's settings.
    public var storageNamespace: String { "experiments.\(rawValue)" }
}

/// Formats the release tag that the `release-tag-in-window-title` flag puts in
/// editor window titles. Pure string work, so the app layer stays dumb.
public enum ReleaseTag {

    /// Where the tag sits relative to the title.
    public enum Placement: Sendable, Hashable, CaseIterable {
        case prefix
        case suffix

        /// The stored (and displayed) case name for the flag's enum parameter.
        public var name: String {
            switch self {
            case .prefix: "Prefix"
            case .suffix: "Suffix"
            }
        }

        public init?(name: String) {
            guard let match = Self.allCases.first(where: { $0.name == name }) else { return nil }
            self = match
        }

        /// The parameter's allowed cases, in display order.
        public static var allNames: [String] { allCases.map(\.name) }
    }

    /// Returns `title` with `(tag)` attached, or the untouched title when the
    /// tag is blank.
    public static func decorate(_ title: String, tag: String,
                                placement: Placement, uppercase: Bool) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return title }
        let badge = "(\(uppercase ? trimmed.uppercased() : trimmed))"
        switch placement {
        case .prefix: return "\(badge) \(title)"
        case .suffix: return "\(title) \(badge)"
        }
    }
}

/// How the app names itself. The name follows the release you're running, so
/// "About", "Quit" and the window that greets you all say which Photonz this
/// is: `Photonz`, `Photonz Next`, and dev builds keep their `(Dev)` on the end
/// (`Photonz Next (Dev)`).
public enum AppNaming {
    /// What dev bundles append to their name (see Scripts/build-app.sh).
    public static let devSuffix = "(Dev)"

    /// The plain product name behind a bundle name, so a dev bundle's
    /// "Photonz (Dev)" and a release bundle's "Photonz" both come back as
    /// "Photonz". Any release word is stripped too, so re-deriving a name that
    /// was already decorated can't produce "Photonz Next Next".
    public static func baseName(fromBundleName bundleName: String) -> String {
        var name = bundleName
        if let range = name.range(of: " \(devSuffix)", options: .backwards) {
            name.removeSubrange(range)
        }
        for release in Release.allCases {
            guard let word = release.appNameWord else { continue }
            if name.hasSuffix(" \(word)") {
                name.removeLast(word.count + 1)
            }
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// The user-facing app name for one release.
    public static func appName(base: String, release: Release, isDevBuild: Bool) -> String {
        var name = base
        if let word = release.appNameWord { name += " \(word)" }
        if isDevBuild { name += " \(devSuffix)" }
        return name
    }
}

extension Release {
    /// The word added to the app's name for this release, or nil for the
    /// default one: plain Photonz is just "Photonz".
    public var appNameWord: String? { isDefault ? nil : title }
}
