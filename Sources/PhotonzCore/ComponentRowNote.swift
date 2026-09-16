import Foundation

/// What a layers row says under its name when the row is a component.
///
/// Every copy carries its original's NAME, because the name belongs to the
/// component rather than to one drawing of it (`renameComponent`). So an
/// original with two copies beside it put three rows reading "Save Button" in
/// the layers list, and the only thing telling them apart was a nine point
/// violet mark: four diamonds for the original, one for a copy. Somebody
/// scanning for the one they can actually edit had to squint at three
/// identical rows (2026-09-13).
///
/// This is the list saying it in words instead. It renames nothing: the note
/// is what the ROW says, the document is untouched, and the mark stays exactly
/// where it was, because the mark is what says "component at all" at a glance
/// and the word is what says WHICH.
///
/// It grew out of the version line that was already printed here, so the two
/// are one line rather than two: a copy showing the Disabled drawing of a
/// button reads "Copy, Disabled".

// MARK: - Which of the two a row is

/// An original, or a copy that follows one.
///
/// The app's own words, the same two the Component section of the dock uses
/// ("This is the original. Copies you place will follow it." / "A copy.
/// Editing the original changes this one too."), so the list and the panel
/// never teach two vocabularies for one idea.
public enum ComponentRowRole: String, Hashable, Sendable, CaseIterable, Codable {
    /// The drawing the Library tile points at, and the one an edit reaches.
    case original
    /// A placed copy. It follows the original, so what can be edited on it is
    /// only what the original made adjustable.
    case copy

    /// The one word the row wears.
    public var word: String {
        switch self {
        case .original: "Original"
        case .copy: "Copy"
        }
    }
}

// MARK: - The note itself

/// The second line of one layers row: the role, what it follows when its own
/// name no longer says, and which version it is showing.
///
/// A small value rather than a bare string so the row can also explain itself
/// on hover without parsing its own label back apart.
public struct ComponentRowNote: Hashable, Sendable {
    public let role: ComponentRowRole
    /// The component this copy follows, ONLY when the row's own name has
    /// stopped saying it. Nil on an original, which is the name it wears.
    public let followedName: String?
    /// Which drawing of the component this is, while the component holds more
    /// than one (`ComponentVersions`). Nil for nearly every row.
    public let versionName: String?

    public init(role: ComponentRowRole, followedName: String? = nil, versionName: String? = nil) {
        self.role = role
        self.followedName = followedName
        self.versionName = versionName
    }

    /// What the line reads, left to right: the word, what it follows, then the
    /// version.
    ///
    /// "Original", "Copy", "Copy of Save Button", "Original, Disabled",
    /// "Copy of Save Button, Disabled". Short first, because the row is narrow
    /// and the truncation is at the tail: whatever gets cut off, the word that
    /// answers "which one is the original" never does.
    public var text: String {
        var line = role.word
        if let followedName { line += " of \(followedName)" }
        if let versionName { line += ", \(versionName)" }
        return line
    }

    /// The sentence hovering it explains, for somebody who does not yet know
    /// what a copy of a component can and cannot be told to do.
    public func help(rowName: String) -> String {
        let component = followedName ?? rowName
        switch role {
        case .original:
            return versionName.map {
                "This is the original, showing its \($0) version. Copies you place follow it."
            } ?? "This is the original. Copies you place follow it."
        case .copy:
            return versionName.map {
                "A copy of \(component), showing its \($0) version. Editing the original changes this one too."
            } ?? "A copy of \(component). Editing the original changes this one too."
        }
    }

    /// The same sentence when the row's name is all there is to go on, which
    /// is what the tests read.
    public var help: String { help(rowName: followedName ?? "") }

    /// What one row says, or nil for a row that is not a component at all,
    /// which is nearly every row in nearly every document.
    ///
    /// `componentName` is the name of the original this row follows. A copy
    /// nearly always wears it already, so naming it again would make the
    /// longest line on the row the one that says least; it is spelled out only
    /// once the two have drifted apart, which is the case where "Copy" alone
    /// would leave somebody hunting for what it is a copy OF.
    public static func forRow(isMain: Bool, isInstance: Bool, rowName: String,
                              componentName: String?, versionName: String?) -> ComponentRowNote? {
        if isMain {
            return ComponentRowNote(role: .original, versionName: versionName)
        }
        guard isInstance else { return nil }
        let followed = componentName.flatMap { $0 == rowName ? nil : $0 }
        return ComponentRowNote(role: .copy, followedName: followed, versionName: versionName)
    }
}
