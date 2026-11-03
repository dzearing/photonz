import Foundation

/// Which running Photonz answers the system-wide capture shortcuts (⇧⌘3, ⇧⌘4,
/// ⇧⌘5 and the rest). Exactly one may.
///
/// The system lets any number of apps hold the same shortcut and hands the
/// press to every one of them. On 2026-11-03 the installed Photonz 0.21.0 and
/// Photonz Dev both did: each photographed the screen, each wrote the picture
/// under the same file name and each put it on the clipboard, one clearing the
/// other's copy while it made its own, so a paste in the first few hundred
/// milliseconds found the clipboard empty or without a picture.
///
/// The rule, which every build that knows it applies the same way:
/// - the probe never answers (it is driven by a script, see
///   `AppFlavor.claimsInputOutsideItself`);
/// - a running build from before this rule cannot step aside, so when there is
///   one it keeps the shortcuts and everybody else stands down;
/// - otherwise the one opened last answers, ties going to the higher process id.
public enum CaptureShortcutOwner {

    /// One running copy of Photonz, as far as the rule needs to know it.
    public struct Instance: Sendable, Equatable {
        public var pid: Int32
        public var flavor: AppFlavor
        /// When it was opened; nil when the system cannot say, which counts as
        /// the oldest.
        public var launched: Date?
        /// Whether it was built knowing this rule, so it stands down when it is
        /// not the holder.
        public var stepsAside: Bool

        public init(pid: Int32, flavor: AppFlavor, launched: Date?, stepsAside: Bool) {
            self.pid = pid
            self.flavor = flavor
            self.launched = launched
            self.stepsAside = stepsAside
        }
    }

    /// The process id of the copy that answers, or nil when none may.
    public static func holder(of instances: [Instance]) -> Int32? {
        let candidates = instances.filter { $0.flavor.claimsInputOutsideItself }
        let stubborn = candidates.filter { !$0.stepsAside }
        return newest(stubborn.isEmpty ? candidates : stubborn)?.pid
    }

    /// Whether `me` answers, among the copies `others` lists. `me` is counted
    /// whether or not the list already has it, since the system's list of
    /// running apps can lag a launch.
    public static func holds(_ me: Instance, among others: [Instance]) -> Bool {
        let everyone = others.filter { $0.pid != me.pid } + [me]
        return holder(of: everyone) == me.pid
    }

    private static func newest(_ instances: [Instance]) -> Instance? {
        instances.max { a, b in
            let ta = a.launched ?? .distantPast, tb = b.launched ?? .distantPast
            return ta == tb ? a.pid < b.pid : ta < tb
        }
    }
}
